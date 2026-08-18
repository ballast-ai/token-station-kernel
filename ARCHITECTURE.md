# Architecture

## What the kernel is

Token Station Kernel is the pure computation layer of the Token Station
ecosystem: everything a host can decide about a request without touching the
network, a database, a clock, or a random number generator. It complements
[`token-station-south`](https://github.com/ballast-ai/token-station-south),
which owns the I/O-bearing southbound provider execution boundary — south's
`compatibility.json` reserves a `canonical_ir` slot; this repository is what
fills it.

## Crate layout and dependency direction

```
token-station-router-core ──► token-station-protocol ──► serde, serde_json
        (decisions)                 (vocabulary)
```

- **`protocol`** is the shared vocabulary: `ChatRequest`, `Message`,
  `Content`/`ContentPart`, `ToolDef`, `Usage`, `ErrorCode` (the error
  catalog with retry semantics kept beside it), `StreamEvent`/`StreamOutcome`,
  `ModelCapability`/`CapabilityState`, `ErrorEnvelope`. External dependencies
  are exactly `serde` and `serde_json`.
- **`router-core`** consumes protocol types as inputs and digests them into
  its own types (`RequestFeatures` is `Copy`; `Decision` carries no request
  content). It deliberately re-exports **no** protocol type: its `pub use`
  surface is entirely its own vocabulary. This keeps the decision record free
  of request content and keeps the two crates' API surfaces separable even
  though they version together.

There is no reverse dependency and no I/O dependency anywhere in the graph.
`unsafe` is forbidden workspace-wide. All of this is enforced mechanically by
`scripts/check-boundaries.sh`.

## Why one repository, not two

`router-core`'s public API leaks protocol types by design (three signatures:
`RequestFeatures::extract(&ChatRequest, …)`, `Candidate::new(…,
ModelCapability, Health)`, `NoRoute::error_code() -> ErrorCode`). If the two
crates lived in two git sources, every consumer would have to keep both
sources resolved to the same protocol revision; a mismatch compiles two copies
of `protocol` and fails with "two different versions of crate". Upstream
history confirms the coupling: semantic changes routinely land as single
commits touching both crates. One repository makes the invariant structural
instead of procedural.

## The mirror mechanism

This repository does not develop the crates; it mirrors them.

- **Source of truth:**
  [`ballast-ai/token-station`](https://github.com/ballast-ai/token-station).
- **Mechanism:** `git subtree split` of `crates/protocol` and
  `crates/router-core` at a released upstream tag, merged here with
  `git subtree add`/`git subtree pull`. Per-file upstream history is
  preserved.
- **Invariant:** the `crates/protocol` and `crates/router-core` trees are
  **byte-identical** to the upstream state recorded in
  [`compatibility.json`](compatibility.json) (`mirror.subtrees` holds the git
  tree hashes; the boundary gate compares them on every run). Local commits
  may only touch scaffolding — never the mirrored subtrees.
- **Why one-way:** upstream's `deny.toml` forbids git dependencies
  (`unknown-git = "deny"`), so upstream cannot consume this repository back.
  There is no double-maintenance ambiguity: code flows in exactly one
  direction.

Operational details (the exact sync commands, cut-point policy, and how a sync
updates `compatibility.json`) live in
[docs/design/mirroring.md](docs/design/mirroring.md).

## Workspace manifest ownership

The root `Cargo.toml` here is mirror-owned scaffolding, but it must replicate
every `workspace.*` key the mirrored crate manifests inherit
(`edition`, `license`, `rust-version`, the dependency versions, and the lint
tables — including `clippy::pedantic`) so that the crates compile with
identical semantics in both repositories. `clippy.toml` and `rustfmt.toml` are
copied from upstream for the same reason. Two deliberate divergences:
`repository` points here, and `publish` is `true` (upstream keeps `false` only
because unversioned path dependencies cannot pass `cargo publish`).
