# Mirroring design

## Decision

This repository is a **one-way mirror** of two subtrees of
[`ballast-ai/token-station`](https://github.com/ballast-ai/token-station)
(`crates/protocol`, `crates/router-core`), not a migration. The upstream
repository stays the source of truth and needs zero changes.

The deciding constraint: upstream's `deny.toml` sets `unknown-git = "deny"`
("Git dependencies create a non-reproducible trust chain"), so its ten
in-repo consumers cannot be repointed at this repository without either
overturning that policy or publishing to crates.io. Neither is a
mirror-side call. A one-way mirror sidesteps the question entirely: upstream
keeps its path dependencies, external consumers get a slim two-crate git
source.

Consequences:

- Local commits may touch **scaffolding only**. The mirrored subtrees are
  byte-identical to a recorded upstream state; the boundary gate fails on any
  drift.
- Code pull requests are not accepted here (see CONTRIBUTING.md).
- The mirror moves only at released upstream tags, never at arbitrary
  commits, so every mirror state names a state upstream has also named.

## Cut point

The initial cut is upstream tag **`v1.1.3`** (commit
`9864e79c48c1a05c17db7ecb0b34cd9179a016f1`). Cut points are always released
upstream tags; the current one is recorded in `compatibility.json` under
`mirror.*` together with the two subtree tree-hashes, which is what makes
"byte-identical" a checkable claim rather than a promise.

One naming caveat for archaeologists: an earlier private lineage of the
upstream project also used the tag name `v1.1.3` for different content. Any
reference to an upstream tag is only meaningful together with the repository
(and ideally the commit hash), which is why `compatibility.json` records the
commit, not just the tag.

## Sync procedure

Initial import (already done, kept for reference):

```bash
# In a clone of ballast-ai/token-station:
git subtree split --prefix=crates/protocol    -b kernel-split/protocol    <upstream-tag-commit>
git subtree split --prefix=crates/router-core -b kernel-split/router-core <upstream-tag-commit>

# In this repository (bootstrap scaffolding committed first):
git subtree add --prefix=crates/protocol    <path-or-url-to-upstream-clone> kernel-split/protocol
git subtree add --prefix=crates/router-core <path-or-url-to-upstream-clone> kernel-split/router-core
```

Subsequent syncs re-run the two `git subtree split` commands in the upstream
clone at the new tag (reusing the same `kernel-split/*` branch names keeps the
split incremental) and then:

```bash
git subtree pull --prefix=crates/protocol    <upstream-clone> kernel-split/protocol
git subtree pull --prefix=crates/router-core <upstream-clone> kernel-split/router-core
```

After the two merges, one scaffolding commit updates `compatibility.json`
(`mirror.source_tag`, `mirror.source_commit`, `mirror.subtrees.*`, and any
contract version that upstream bumped), all gates run, and a new `v0.x` tag is
cut. Verification is mechanical:

```bash
git rev-parse HEAD:crates/protocol HEAD:crates/router-core
# must equal, in the upstream clone at the new tag:
git rev-parse '<tag>^{commit}:crates/protocol' '<tag>^{commit}:crates/router-core'
```

`scripts/check-boundaries.sh` runs the same comparison against
`compatibility.json` on every invocation, so a sync that forgets the manifest
update fails CI.

## Workspace assembly rules

The mirrored crate manifests inherit `workspace.*` keys from the root
manifest, which is mirror-owned. The root must therefore track upstream's
`[workspace.package]` (edition, license, rust-version), `[workspace.dependencies]`
(serde, serde_json), and `[workspace.lints]` (including `clippy::pedantic`)
whenever a sync changes them — plus upstream's `clippy.toml` and
`rustfmt.toml` — so the crates compile and lint with identical semantics in
both repositories. The two deliberate divergences are `repository` (points
here) and `publish = true`.
