# Contributing

## Code changes: upstream, not here

This repository is a one-way mirror of the `crates/protocol` and
`crates/router-core` subtrees of
[`ballast-ai/token-station`](https://github.com/ballast-ai/token-station).
**Pull requests that touch anything under `crates/` are declined** — a local
edit there forks the mirror from its source and is overwritten by the next
sync. File issues and code pull requests against the upstream repository; the
change lands here with the next sync.

Pull requests that touch only the mirror-owned scaffolding (README, docs,
workspace manifest, gates, CI, `compatibility.json`) are in scope here.

## Running the checks

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
scripts/check-boundaries.sh
```

All four must pass before any commit. `check-boundaries.sh` needs `git`,
`python3`, and `cargo` on PATH.

## Syncing from upstream (maintainers)

The procedure, including how the cut point is chosen and how
`compatibility.json` is updated, is documented in
[docs/design/mirroring.md](docs/design/mirroring.md). In short: subtree-split
both prefixes at a released upstream tag, `git subtree pull` each into this
repository, update `mirror.*` in `compatibility.json` to the new tag/commit
and tree hashes, run all gates, and tag a new `v0.x` release.

## Commit style

English commit messages; one logical change per commit. Sync merges keep the
`git subtree` default messages so the mirrored range stays traceable.
