#!/usr/bin/env bash
# Sync this mirror to a released upstream kernel source tag
# (`kernel-v*`; docs/design/mirroring.md). Application `v*` tags are not
# mirror source releases.
#
#   scripts/sync-upstream.sh --tag <upstream-tag> [--upstream <path|url>]
#                            [--release <x.y.z>] [--no-verify]
#
# What it does, in order:
#   1. Refuses to run on a dirty tree; resolves the upstream clone (default:
#      a ../token-station sibling checkout, else a fresh temporary clone of
#      the canonical https://github.com/ballast-ai/token-station.git).
#   2. Requires <upstream-tag> to be a real annotated tag, then resolves its
#      peeled commit. A same-source run is a no-op only when --release is
#      absent or already matches compatibility.json.
#   3. Verifies the inherited workspace package/dependency/lint keys and the
#      complete clippy.toml / rustfmt.toml against the upstream source tag.
#      Root changes outside that inherited surface are compatible; inherited
#      drift is fatal before subtree merging.
#   4. `git subtree split` both prefixes at the tag commit in the upstream
#      clone (branches kernel-split/* updated for incremental reuse), then
#      `git subtree pull` each into this repository.
#   5. Verifies byte-identity: HEAD:crates/<c> tree hash must equal the
#      upstream tag commit's — a mismatch means local drift and is fatal.
#   6. Rewrites compatibility.json (mirror.source_tag/source_commit/subtrees,
#      and release.version when --release is given) and commits it.
#   7. Runs the gates (fmt, clippy, tests, check-boundaries) unless
#      --no-verify.
#
# It deliberately does NOT push or tag: review the merge, pick the v0.x
# version, then `git tag -a v0.x.y && git push origin main v0.x.y`.
set -euo pipefail
cd "$(dirname "$0")/.."

UPSTREAM_URL="https://github.com/ballast-ai/token-station.git"
TAG="" UPSTREAM="" RELEASE="" VERIFY=1
while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --upstream) UPSTREAM="$2"; shift 2 ;;
        --release) RELEASE="$2"; shift 2 ;;
        --no-verify) VERIFY=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
if [ -z "$TAG" ]; then
    echo "usage: scripts/sync-upstream.sh --tag <upstream-tag> [--upstream <path|url>] [--release <x.y.z>] [--no-verify]" >&2
    exit 2
fi
case "$TAG" in
    kernel-v*) ;;
    *) echo "upstream mirror source tag must match kernel-v*: $TAG" >&2; exit 2 ;;
esac

git diff-index --quiet HEAD -- || { echo "working tree is dirty; commit or stash first" >&2; exit 1; }

# --- 1. upstream clone ------------------------------------------------------
if [ -z "$UPSTREAM" ]; then
    if [ -d "../token-station/.git" ]; then
        UPSTREAM="../token-station"
    else
        UPSTREAM="$UPSTREAM_URL"
    fi
fi
case "$UPSTREAM" in
    http://*|https://*|git@*|ssh://*)
        TMP=$(mktemp -d)
        trap 'rm -rf "$TMP"' EXIT
        echo "cloning $UPSTREAM (full history; subtree split needs it) ..."
        git clone --quiet "$UPSTREAM" "$TMP/upstream"
        UPSTREAM="$TMP/upstream"
        ;;
    *)
        git -C "$UPSTREAM" fetch --tags --quiet origin 2>/dev/null || true
        ;;
esac

# --- 2. resolve the annotated tag; determine idempotence -------------------
TAG_REF="refs/tags/$TAG"
if ! git -C "$UPSTREAM" show-ref --verify --quiet "$TAG_REF"; then
    echo "upstream mirror source must be an annotated tag: $TAG_REF" >&2
    exit 1
fi
TAG_TYPE=$(git -C "$UPSTREAM" cat-file -t "$TAG_REF")
if [ "$TAG_TYPE" != "tag" ]; then
    echo "upstream mirror source must be an annotated tag: $TAG_REF is $TAG_TYPE" >&2
    exit 1
fi
COMMIT=$(git -C "$UPSTREAM" rev-parse "$TAG_REF^{}")
CURRENT=$(python3 -c "import json; print(json.load(open('compatibility.json'))['mirror']['source_commit'])")
CURRENT_RELEASE=$(python3 -c "import json; print(json.load(open('compatibility.json'))['release']['version'])")

# --- 3. root compatibility --------------------------------------------------
UPSTREAM="$UPSTREAM" COMMIT="$COMMIT" python3 - <<'PY'
import os
import re
import subprocess
import sys

upstream = os.environ["UPSTREAM"]
commit = os.environ["COMMIT"]

def upstream_bytes(path):
    return subprocess.run(
        ["git", "-C", upstream, "show", f"{commit}:{path}"],
        check=True,
        capture_output=True,
    ).stdout

def section(document, name):
    match = re.search(
        rf"^\[{re.escape(name)}\]\s*$\n(.*?)(?=^\[|\Z)",
        document,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise ValueError(f"missing TOML section [{name}]")
    return match.group(1)

def value(document, section_name, key):
    body = section(document, section_name)
    match = re.search(rf"^{re.escape(key)}\s*=\s*(.+?)\s*$", body, flags=re.MULTILINE)
    if not match:
        raise ValueError(f"missing TOML key [{section_name}] {key}")
    return re.sub(r"\s+", "", match.group(1))

def key_values(document, section_name):
    result = {}
    for line in section(document, section_name).splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, raw = line.split("=", 1)
        result[key.strip()] = re.sub(r"\s+", "", raw)
    return result

local = open("Cargo.toml", encoding="utf-8").read()
remote = upstream_bytes("Cargo.toml").decode()

def pair(section_name, key):
    return value(local, section_name, key), value(remote, section_name, key)

checks = {
    "workspace.resolver": pair("workspace", "resolver"),
    "workspace.package.edition": pair("workspace.package", "edition"),
    "workspace.package.license": pair("workspace.package", "license"),
    "workspace.package.rust-version": pair("workspace.package", "rust-version"),
    "workspace.dependencies.serde": pair("workspace.dependencies", "serde"),
    "workspace.dependencies.serde_json": pair("workspace.dependencies", "serde_json"),
    "workspace.lints.rust": (
        key_values(local, "workspace.lints.rust"),
        key_values(remote, "workspace.lints.rust"),
    ),
    "workspace.lints.clippy": (
        key_values(local, "workspace.lints.clippy"),
        key_values(remote, "workspace.lints.clippy"),
    ),
}
errors = [name for name, values in checks.items() if values[0] != values[1]]
for path in ("clippy.toml", "rustfmt.toml"):
    if open(path, "rb").read() != upstream_bytes(path):
        errors.append(path)
if errors:
    print("FATAL: mirror root is incompatible with the upstream kernel source tag:", file=sys.stderr)
    for name in errors:
        print(f"  - {name}", file=sys.stderr)
    sys.exit(1)
print("root compatibility OK: workspace rust/serde/lints, clippy.toml, rustfmt.toml")
PY

RELEASE_UPDATE=0
if [ -n "$RELEASE" ] && [ "$RELEASE" != "$CURRENT_RELEASE" ]; then
    RELEASE_UPDATE=1
fi
if [ "$COMMIT" = "$CURRENT" ] && [ "$RELEASE_UPDATE" = 0 ]; then
    echo "already mirroring $TAG ($COMMIT); nothing to do"
    scripts/check-boundaries.sh
    exit 0
fi

# --- 4. split + pull --------------------------------------------------------
if [ "$COMMIT" != "$CURRENT" ]; then
    echo "syncing $CURRENT -> $TAG ($COMMIT)"
    for c in protocol router-core; do
        echo "splitting crates/$c at $TAG ..."
        SPLIT=$(git -C "$UPSTREAM" subtree split --prefix="crates/$c" "$COMMIT" 2>/dev/null)
        git -C "$UPSTREAM" branch -f "kernel-split/$c" "$SPLIT"
        git subtree pull --prefix="crates/$c" "$UPSTREAM" "kernel-split/$c" \
            -m "Sync crates/$c from token-station $TAG"
    done
else
    echo "source commit unchanged at $TAG ($COMMIT); updating release $CURRENT_RELEASE -> $RELEASE"
fi

# --- 5. byte-identity check -------------------------------------------------
for c in protocol router-core; do
    want=$(git -C "$UPSTREAM" rev-parse "$COMMIT:crates/$c")
    got=$(git rev-parse "HEAD:crates/$c")
    if [ "$want" != "$got" ]; then
        echo "FATAL: HEAD:crates/$c tree is $got but upstream $TAG has $want." >&2
        echo "       The mirror has drifted (a local commit touched crates/?)." >&2
        echo "       Do not push; investigate per docs/design/mirroring.md." >&2
        exit 1
    fi
done

# --- 6. compatibility.json --------------------------------------------------
TAG="$TAG" COMMIT="$COMMIT" RELEASE="$RELEASE" python3 - <<'PY'
import json, os, subprocess

compat = json.load(open("compatibility.json"))
compat["mirror"]["source_tag"] = os.environ["TAG"]
compat["mirror"]["source_commit"] = os.environ["COMMIT"]
for prefix in compat["mirror"]["subtrees"]:
    compat["mirror"]["subtrees"][prefix] = subprocess.run(
        ["git", "rev-parse", f"HEAD:{prefix}"], check=True, capture_output=True, text=True
    ).stdout.strip()
if os.environ["RELEASE"]:
    compat["release"]["version"] = os.environ["RELEASE"]
with open("compatibility.json", "w") as f:
    json.dump(compat, f, indent=2)
    f.write("\n")
PY
git add compatibility.json
git commit -q -m "chore: record mirror state at token-station $TAG (${COMMIT:0:7})"

# --- 7. gates ---------------------------------------------------------------
if [ "$VERIFY" = 1 ]; then
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test --workspace
fi
scripts/check-boundaries.sh

echo
echo "sync complete. Next steps:"
echo "  1. Review the merge:            git log --oneline -8"
if [ -z "$RELEASE" ]; then
    echo "  3. Set release.version in compatibility.json (re-run with --release, or edit + amend)."
fi
echo "  4. Tag and push:                git tag -a v0.x.y && git push origin main v0.x.y"
echo "  5. Bump consumers (token-station-server workspace deps) to the new tag."
