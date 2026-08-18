#!/usr/bin/env bash
# Sync this mirror to a released upstream tag (docs/design/mirroring.md).
#
#   scripts/sync-upstream.sh --tag <upstream-tag> [--upstream <path|url>]
#                            [--release <x.y.z>] [--no-verify]
#
# What it does, in order:
#   1. Refuses to run on a dirty tree; resolves the upstream clone (default:
#      a ../token-station sibling checkout, else a fresh temporary clone of
#      the canonical https://github.com/ballast-ai/token-station.git).
#   2. Resolves <upstream-tag> to a commit; exits 0 if the mirror already
#      records that commit (idempotent).
#   3. Warns when upstream's root Cargo.toml / clippy.toml / rustfmt.toml
#      changed since the currently mirrored commit — the mirrored crates
#      inherit workspace.* keys from OUR root manifest, so those diffs need a
#      manual review (docs/lessons.md, "the root manifest is part of the ABI").
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

# --- 2. resolve the tag; idempotence ---------------------------------------
COMMIT=$(git -C "$UPSTREAM" rev-parse "refs/tags/$TAG^{commit}" 2>/dev/null \
    || git -C "$UPSTREAM" rev-parse "$TAG^{commit}")
CURRENT=$(python3 -c "import json; print(json.load(open('compatibility.json'))['mirror']['source_commit'])")
if [ "$COMMIT" = "$CURRENT" ]; then
    echo "already mirroring $TAG ($COMMIT); nothing to do"
    exit 0
fi
echo "syncing $CURRENT -> $TAG ($COMMIT)"

# --- 3. root-manifest drift warnings ---------------------------------------
WARNED=0
for f in Cargo.toml clippy.toml rustfmt.toml; do
    if ! git -C "$UPSTREAM" diff --quiet "$CURRENT" "$COMMIT" -- "$f" 2>/dev/null; then
        echo "WARNING: upstream $f changed between $CURRENT and $COMMIT."
        echo "         The mirrored crates inherit workspace.* keys from OUR root manifest;"
        echo "         review whether the mirror must track this (docs/lessons.md)."
        WARNED=1
    fi
done

# --- 4. split + pull --------------------------------------------------------
for c in protocol router-core; do
    echo "splitting crates/$c at $TAG ..."
    SPLIT=$(git -C "$UPSTREAM" subtree split --prefix="crates/$c" "$COMMIT" 2>/dev/null)
    git -C "$UPSTREAM" branch -f "kernel-split/$c" "$SPLIT"
    git subtree pull --prefix="crates/$c" "$UPSTREAM" "kernel-split/$c" \
        -m "Sync crates/$c from token-station $TAG"
done

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
if [ "$WARNED" = 1 ]; then
    echo "  2. RESOLVE THE WARNINGS ABOVE (root-manifest drift) before tagging."
fi
if [ -z "$RELEASE" ]; then
    echo "  3. Set release.version in compatibility.json (re-run with --release, or edit + amend)."
fi
echo "  4. Tag and push:                git tag -a v0.x.y && git push origin main v0.x.y"
echo "  5. Bump consumers (token-station-server workspace deps) to the new tag."
