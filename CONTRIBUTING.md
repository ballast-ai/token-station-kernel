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

Run `scripts/sync-upstream.sh --tag <upstream-tag>` — it splits both prefixes
at the released upstream tag, subtree-pulls them in, verifies byte-identity,
updates `mirror.*` in `compatibility.json`, and runs all gates, leaving
review, the `v0.x` tag, and the push to you. The design and the underlying
manual commands are documented in
[docs/design/mirroring.md](docs/design/mirroring.md). A weekly CI job
(`upstream-freshness`) fails when upstream has released a tag the mirror
doesn't yet reflect.

## Commit style

English commit messages; one logical change per commit. Sync merges keep the
`git subtree` default messages so the mirrored range stays traceable.
