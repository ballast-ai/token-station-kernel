# Token Station Kernel

Token Station Kernel is the pure computation slice of Token Station: the
wire-neutral protocol vocabulary and the routing decision engine, with no I/O
of any kind. The routing entry point is documented upstream as
*"Pure: no clock, no randomness, no IO"* — that property is the boundary this
repository exists to preserve. Where [`token-station-south`] owns the
I/O-bearing southbound provider execution path, the kernel owns what can be
computed from a request alone.

> [!WARNING]
> Pre-1.0. The API surface follows the upstream source of truth and may change
> between minor versions. Pin a tag; nothing here is a stability promise until
> 1.0.

## Crates

| Crate | Purpose |
|---|---|
| `crates/protocol` (`token-station-protocol`) | Canonical IR: requests, messages, content parts, tool definitions, usage accounting, the error catalog, stream events, and model capability metadata. Depends only on `serde` + `serde_json`. |
| `crates/router-core` (`token-station-router-core`) | The routing decision engine: operator rules, agent hints, difficulty heuristic, health-aware candidate ranking, quota-first mode. Depends only on `serde` + `token-station-protocol`. |

The two crates ship together because router-core's public API takes protocol
types by reference (`route(&ChatRequest, …)`). Split across two git sources, a
consumer can end up with two compiled copies of `protocol` and a type mismatch;
one repository makes that impossible. See [ARCHITECTURE.md](ARCHITECTURE.md).

## This is a mirror

> [!IMPORTANT]
> The source of truth is
> [`ballast-ai/token-station`](https://github.com/ballast-ai/token-station).
> This repository is a **one-way mirror** of its `crates/protocol` and
> `crates/router-core` subtrees, produced with `git subtree split`. **Code pull
> requests are not accepted here** — they would fork the mirror from its
> source. Contribute code upstream; the change arrives here with the next sync.
> Only the repository scaffolding (this README, the workspace manifest, the
> gates, `compatibility.json`) is owned by this repository.

Which upstream state the mirror currently reflects — tag, commit, and the
exact per-crate tree hashes — is recorded in
[`compatibility.json`](compatibility.json) and enforced by
`scripts/check-boundaries.sh`.

镜像源发布点使用独立的 `kernel-v*` 标签族，避免把上游应用的 `v*`
发布误判为 kernel 源码发布点。当前镜像源为 `kernel-v0.4.0`；历史切点仍保留在
提交记录与兼容性清单中。

## Consuming

```toml
[dependencies]
token-station-protocol = { git = "https://github.com/ballast-ai/token-station-kernel.git", tag = "v0.3.0" }
token-station-router-core = { git = "https://github.com/ballast-ai/token-station-kernel.git", tag = "v0.3.0" }
```

Both crates resolve from one source, so their shared protocol types are one
type. `cargo publish` to crates.io is not part of the current release process
(the workspace allows it, but router-core's path dependency would first need a
version requirement — an upstream decision, not a mirror-side edit).

## Gates

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
scripts/check-boundaries.sh
```

`check-boundaries.sh` enforces the kernel invariants: the exact two-crate
member set, the exact dependency allowlist (no I/O, no databases, no network,
crates.io sources only), the no-re-export rule (router-core must not `pub use`
protocol types), and mirror integrity (the `crates/` trees must be
byte-identical to the upstream state recorded in `compatibility.json`).

## License

Apache-2.0, same as upstream. See [LICENSE](LICENSE).

[`token-station-south`]: https://github.com/ballast-ai/token-station-south
