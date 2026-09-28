#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GIT_AUTHOR_NAME="Mirror Policy Test"
export GIT_AUTHOR_EMAIL="mirror-policy@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

write_root_files() {
    local repo=$1
    cat >"$repo/Cargo.toml" <<'EOF'
[workspace]
resolver = "2"

[workspace.package]
edition = "2024"
license = "MIT"
rust-version = "1.96"

[workspace.dependencies]
serde = "1"
serde_json = "1"

[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
pedantic = "warn"
EOF
    : >"$repo/clippy.toml"
    : >"$repo/rustfmt.toml"
}

init_upstream() {
    local repo=$1
    git init -q "$repo"
    write_root_files "$repo"
    mkdir -p "$repo/crates/protocol" "$repo/crates/router-core"
    printf 'protocol-v1\n' >"$repo/crates/protocol/payload.txt"
    printf 'router-v1\n' >"$repo/crates/router-core/payload.txt"
    git -C "$repo" add .
    git -C "$repo" commit -qm "fixture source"
}

write_compatibility() {
    local mirror=$1 upstream=$2 tag=$3 release=$4
    local commit protocol_tree router_tree
    commit=$(git -C "$upstream" rev-parse HEAD)
    protocol_tree=$(git -C "$upstream" rev-parse HEAD:crates/protocol)
    router_tree=$(git -C "$upstream" rev-parse HEAD:crates/router-core)
    cat >"$mirror/compatibility.json" <<EOF
{
  "schema_version": 1,
  "release": {"version": "$release", "stability": "test"},
  "mirror": {
    "source_repository": "fixture",
    "source_tag": "$tag",
    "source_commit": "$commit",
    "subtrees": {
      "crates/protocol": "$protocol_tree",
      "crates/router-core": "$router_tree"
    }
  },
  "contracts": {"canonical_ir": 2, "router_config": 1, "error_catalog": 1, "stream": 2},
  "notes": {}
}
EOF
}

init_mirror() {
    local mirror=$1 upstream=$2 tag=$3 release=$4
    git init -q "$mirror"
    write_root_files "$mirror"
    mkdir -p "$mirror/crates" "$mirror/scripts"
    cp -R "$upstream/crates/protocol" "$mirror/crates/protocol"
    cp -R "$upstream/crates/router-core" "$mirror/crates/router-core"
    cp "$ROOT/scripts/sync-upstream.sh" "$mirror/scripts/sync-upstream.sh"
    cp "$ROOT/scripts/check-upstream-freshness.sh" "$mirror/scripts/check-upstream-freshness.sh" 2>/dev/null || true
    cat >"$mirror/scripts/check-boundaries.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
    chmod +x "$mirror/scripts/"*.sh
    write_compatibility "$mirror" "$upstream" "$tag" "$release"
    git -C "$mirror" add .
    git -C "$mirror" commit -qm "fixture mirror"
}

assert_branch_cannot_impersonate_tag() {
    local upstream="$TMP/upstream-branch" mirror="$TMP/mirror-branch"
    init_upstream "$upstream"
    git -C "$upstream" branch kernel-v9.9.1
    init_mirror "$mirror" "$upstream" kernel-v9.9.1 0.3.0

    if "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.1 --upstream "$upstream" --no-verify \
        >"$TMP/branch.out" 2>"$TMP/branch.err"; then
        echo "FAIL: a branch named kernel-v9.9.1 impersonated an annotated tag" >&2
        return 1
    fi
    grep -q "annotated tag" "$TMP/branch.err" || {
        echo "FAIL: branch rejection did not explain the annotated-tag requirement" >&2
        cat "$TMP/branch.err" >&2
        return 1
    }
}

assert_lightweight_tag_cannot_impersonate_annotated_tag() {
    local upstream="$TMP/upstream-lightweight" mirror="$TMP/mirror-lightweight"
    init_upstream "$upstream"
    git -C "$upstream" tag kernel-v9.9.4
    init_mirror "$mirror" "$upstream" kernel-v9.9.4 0.3.0

    if "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.4 --upstream "$upstream" --no-verify \
        >"$TMP/lightweight.out" 2>"$TMP/lightweight.err"; then
        echo "FAIL: a lightweight tag impersonated an annotated tag" >&2
        return 1
    fi
    grep -q "annotated tag" "$TMP/lightweight.err" || {
        echo "FAIL: lightweight-tag rejection did not explain the requirement" >&2
        cat "$TMP/lightweight.err" >&2
        return 1
    }
}

assert_release_updates_at_same_source_commit() {
    local upstream="$TMP/upstream-release" mirror="$TMP/mirror-release"
    init_upstream "$upstream"
    git -C "$upstream" tag -am "kernel source" kernel-v9.9.2
    init_mirror "$mirror" "$upstream" kernel-v9.9.2 0.3.0

    "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.2 --upstream "$upstream" --release 0.4.0 --no-verify \
        >"$TMP/release.out" 2>"$TMP/release.err"
    local recorded
    recorded=$(python3 -c \
        "import json; print(json.load(open('$mirror/compatibility.json'))['release']['version'])")
    if [ "$recorded" != "0.4.0" ]; then
        echo "FAIL: same source commit left release.version at $recorded" >&2
        return 1
    fi
    git -C "$mirror" log -1 --format=%s | grep -q "record mirror state" || {
        echo "FAIL: release-only update was not committed" >&2
        return 1
    }
}

assert_source_tag_updates_at_same_source_commit() {
    local upstream="$TMP/upstream-source-tag" mirror="$TMP/mirror-source-tag"
    init_upstream "$upstream"
    git -C "$upstream" tag -am "old kernel source" kernel-v9.9.5
    git -C "$upstream" tag -am "new kernel source" kernel-v9.9.6
    init_mirror "$mirror" "$upstream" kernel-v9.9.5 0.3.0

    "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.6 --upstream "$upstream" --no-verify \
        >"$TMP/source-tag.out" 2>"$TMP/source-tag.err"
    local recorded
    recorded=$(python3 -c \
        "import json; print(json.load(open('$mirror/compatibility.json'))['mirror']['source_tag'])")
    if [ "$recorded" != "kernel-v9.9.6" ]; then
        echo "FAIL: same source commit left mirror.source_tag at $recorded" >&2
        return 1
    fi
    git -C "$mirror" log -1 --format=%s | grep -q "kernel-v9.9.6" || {
        echo "FAIL: source-tag-only update was not committed" >&2
        return 1
    }
}

assert_true_noop_runs_compatibility_and_boundary() {
    local upstream="$TMP/upstream-noop" mirror="$TMP/mirror-noop"
    init_upstream "$upstream"
    git -C "$upstream" tag -am "kernel source" kernel-v9.9.7
    init_mirror "$mirror" "$upstream" kernel-v9.9.7 0.3.0
    cat >"$mirror/scripts/check-boundaries.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: > boundary.called
EOF
    chmod +x "$mirror/scripts/check-boundaries.sh"
    git -C "$mirror" add scripts/check-boundaries.sh
    git -C "$mirror" commit -qm "instrument boundary gate"
    local before_head after_head
    before_head=$(git -C "$mirror" rev-parse HEAD)

    "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.7 --upstream "$upstream" --no-verify \
        >"$TMP/noop.out" 2>"$TMP/noop.err"
    after_head=$(git -C "$mirror" rev-parse HEAD)
    if [ "$after_head" != "$before_head" ]; then
        echo "FAIL: true no-op created a commit" >&2
        return 1
    fi
    test -f "$mirror/boundary.called" || {
        echo "FAIL: true no-op did not run the boundary gate" >&2
        return 1
    }

    sed -i.bak 's/rust-version = "1.96"/rust-version = "1.95"/' "$mirror/Cargo.toml"
    rm "$mirror/Cargo.toml.bak"
    git -C "$mirror" add Cargo.toml
    git -C "$mirror" commit -qm "make root incompatible"
    if "$mirror/scripts/sync-upstream.sh" \
        --tag kernel-v9.9.7 --upstream "$upstream" --no-verify \
        >"$TMP/noop-compat.out" 2>"$TMP/noop-compat.err"; then
        echo "FAIL: true no-op skipped root compatibility" >&2
        return 1
    fi
    grep -q "root is incompatible" "$TMP/noop-compat.err" || {
        echo "FAIL: no-op compatibility rejection did not explain the mismatch" >&2
        cat "$TMP/noop-compat.err" >&2
        return 1
    }
}

assert_freshness_detects_moved_annotated_tag() {
    local upstream="$TMP/upstream-freshness" compat="$TMP/freshness.json"
    init_upstream "$upstream"
    git -C "$upstream" tag -am "kernel source" kernel-v9.9.3
    local first_commit
    first_commit=$(git -C "$upstream" rev-parse HEAD)
    cat >"$compat" <<EOF
{"mirror":{"source_tag":"kernel-v9.9.3","source_commit":"$first_commit"}}
EOF

    "$ROOT/scripts/check-upstream-freshness.sh" \
        --upstream "$upstream" --compatibility "$compat" >"$TMP/freshness-ok.out"

    printf 'moved\n' >>"$upstream/crates/protocol/payload.txt"
    git -C "$upstream" add .
    git -C "$upstream" commit -qm "move source"
    git -C "$upstream" tag -fam "moved kernel source" kernel-v9.9.3

    if "$ROOT/scripts/check-upstream-freshness.sh" \
        --upstream "$upstream" --compatibility "$compat" \
        >"$TMP/freshness-moved.out" 2>"$TMP/freshness-moved.err"; then
        echo "FAIL: moving an annotated tag did not invalidate freshness" >&2
        return 1
    fi
    grep -q "source commit" "$TMP/freshness-moved.err" || {
        echo "FAIL: moved-tag rejection did not report the source commit mismatch" >&2
        cat "$TMP/freshness-moved.err" >&2
        return 1
    }
}

case "${1:-all}" in
    branch) assert_branch_cannot_impersonate_tag ;;
    lightweight) assert_lightweight_tag_cannot_impersonate_annotated_tag ;;
    release) assert_release_updates_at_same_source_commit ;;
    source-tag) assert_source_tag_updates_at_same_source_commit ;;
    noop) assert_true_noop_runs_compatibility_and_boundary ;;
    freshness) assert_freshness_detects_moved_annotated_tag ;;
    all)
        assert_branch_cannot_impersonate_tag
        assert_lightweight_tag_cannot_impersonate_annotated_tag
        assert_release_updates_at_same_source_commit
        assert_source_tag_updates_at_same_source_commit
        assert_true_noop_runs_compatibility_and_boundary
        assert_freshness_detects_moved_annotated_tag
        ;;
    *) echo "usage: $0 [branch|lightweight|release|source-tag|noop|freshness|all]" >&2; exit 2 ;;
esac
echo "mirror policy tests: PASS"
