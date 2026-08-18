# Lessons

Operational lessons learned maintaining this mirror. Append; do not rewrite.

## 2026-08-18 — a tag name is not an identity

The upstream project existed in two lineages (an earlier private history and
the public `ballast-ai/token-station` bootstrap), and both carried a tag named
`v1.1.3` — pointing at different commits with different content. Every
mirror-side record therefore names the commit hash, not just the tag, and the
boundary gate compares tree hashes rather than trusting tag names. If you ever
reconcile this mirror against upstream, compare by hash.

## 2026-08-18 — the root manifest is part of the ABI

The mirrored crates inherit `edition`, `rust-version`, dependency versions,
and lint tables from the workspace root, which the mirror owns. Forgetting to
track an upstream change to any of these (or to `clippy.toml` / `rustfmt.toml`)
silently changes how identical source compiles or lints here. Treat upstream's
root-manifest diffs as part of every sync review, not just the `crates/` diff.
