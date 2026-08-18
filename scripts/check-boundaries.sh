#!/usr/bin/env bash
# Kernel boundary gate. Enforces the invariants that make this repository what
# it claims to be (see ARCHITECTURE.md):
#
#   1. Member set: exactly crates/protocol + crates/router-core.
#   2. Dependency allowlist: protocol -> {serde, serde_json}; router-core ->
#      {serde, token-station-protocol(path)} (+ serde_json as dev-dependency).
#      Every external dependency resolves from crates.io. No I/O crates, no
#      databases, no network — by exact allowlist, not by blocklist.
#   3. No re-export: router-core must not `pub use` protocol types; its public
#      surface is its own vocabulary (decision records stay content-free).
#   4. Mirror integrity: the crates/ trees are byte-identical to the upstream
#      state recorded in compatibility.json (git tree-hash comparison).
#   5. Contract anchor: compatibility.json's router_config equals router-core's
#      CONFIG_VERSION constant.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

# --- 4. Mirror integrity + 5. contract anchor + shape of compatibility.json --
python3 - <<'PY' || fail=1
import json, re, subprocess, sys

compat = json.load(open("compatibility.json"))
errors = []

for prefix, want in compat["mirror"]["subtrees"].items():
    got = subprocess.run(
        ["git", "rev-parse", f"HEAD:{prefix}"], check=True, capture_output=True, text=True
    ).stdout.strip()
    if got != want:
        errors.append(
            f"mirror drift: HEAD:{prefix} tree is {got}, compatibility.json records {want}"
        )

config_rs = open("crates/router-core/src/config.rs").read()
m = re.search(r"pub const CONFIG_VERSION: u32 = (\d+);", config_rs)
if not m:
    errors.append("CONFIG_VERSION constant not found in crates/router-core/src/config.rs")
elif int(m.group(1)) != compat["contracts"]["router_config"]:
    errors.append(
        f"contract drift: CONFIG_VERSION is {m.group(1)}, "
        f"compatibility.json records router_config={compat['contracts']['router_config']}"
    )

if errors:
    print("boundary gate failed:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
PY

# --- 1. member set + 2. dependency allowlist (cargo metadata) ----------------
python3 - <<'PY' || fail=1
import json, subprocess, sys

meta = json.loads(
    subprocess.run(
        ["cargo", "metadata", "--format-version", "1"], check=True, capture_output=True
    ).stdout
)
pkgs = {p["id"]: p for p in meta["packages"]}
members = {pkgs[m]["name"] for m in meta["workspace_members"]}
errors = []

WANT_MEMBERS = {"token-station-protocol", "token-station-router-core"}
if members != WANT_MEMBERS:
    errors.append(f"member set is {sorted(members)}, expected {sorted(WANT_MEMBERS)}")

# name -> {(dep_name, kind_normalized)}; kind None = normal, "dev" = dev-only.
ALLOW = {
    "token-station-protocol": {("serde", None), ("serde_json", None)},
    "token-station-router-core": {
        ("serde", None),
        ("token-station-protocol", None),
        ("serde_json", "dev"),
    },
}

for pid in meta["workspace_members"]:
    p = pkgs[pid]
    got = {(d["name"], d["kind"]) for d in p["dependencies"]}
    want = ALLOW.get(p["name"], set())
    if got != want:
        errors.append(f"{p['name']}: dependency set {sorted(got)} != allowlist {sorted(want)}")
    for d in p["dependencies"]:
        if d["name"] == "token-station-protocol":
            if not (d.get("path") or "").endswith("crates/protocol"):
                errors.append(f"{p['name']}: token-station-protocol must be a path dependency")
        elif d.get("registry") is not None or d.get("source") not in (
            "registry+https://github.com/rust-lang/crates.io-index",
            None,
        ):
            errors.append(f"{p['name']}: {d['name']} source {d.get('source')} is not crates.io")

# The resolved graph must contain nothing beyond the two members + the serde
# stack. serde_json has swapped formatting backends before (ryu -> zmij), so
# both spellings stay allowed; anything else appearing here is a review event.
RESOLVED_ALLOW = WANT_MEMBERS | {
    "serde", "serde_derive", "serde_json", "serde_core",
    "proc-macro2", "quote", "syn", "unicode-ident",
    "itoa", "ryu", "zmij", "memchr",
}
resolved = {pkgs[n["id"]]["name"] for n in meta["resolve"]["nodes"]}
extra = resolved - RESOLVED_ALLOW
if extra:
    errors.append(f"resolved graph has unexpected crates: {sorted(extra)}")

if errors:
    print("boundary gate failed:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
PY

# --- 3. no protocol re-export from router-core -------------------------------
if grep -rn "pub use token_station_protocol" crates/router-core/src; then
    echo "boundary gate failed: router-core re-exports protocol types" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "boundary gate OK: members, dependency allowlist, no re-export, mirror integrity, contract anchor"
