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

## 2026-09-29 — Check a tag's object type and its peeled commit

`rev-parse <name>^{commit}` also accepts a branch with the same name. Comparing
tag names alone cannot detect a remote tag that moved. The mirror entry point
must resolve only `refs/tags/<name>` and confirm that the object is an annotated
`tag`. The freshness check must also read the remote `refs/tags/<name>^{}` and
compare the peeled commit exactly with `source_commit` in `compatibility.json`.

## 2026-09-29 — An idempotence check must cover the whole target state

An unchanged source commit means only that the subtrees need no update. It does
not mean the sync request has nothing to do. `--release` is part of the target
state too. The sync can be a no-op only when the source commit is unchanged and
the release is absent or already equal. Even a no-op must still run the boundary
gate, so the shortcut cannot skip the drift checks.
