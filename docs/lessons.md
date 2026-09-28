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

## 2026-09-29 — 标签名必须同时校验对象类型与 peeled commit

`rev-parse <name>^{commit}` 会接受同名分支，单独比较标签名也无法发现远端移动了
同名标签。镜像入口必须只解析 `refs/tags/<name>`，确认其对象类型为 annotated
`tag`；新鲜度检查还要读取远端 `refs/tags/<name>^{}`，将 peeled commit 与
`compatibility.json` 的 `source_commit` 精确对账。

## 2026-09-29 — 幂等条件要覆盖操作的全部目标状态

同步源提交相同只说明 subtree 无需更新，不代表整个同步请求无事可做。
`--release` 也是目标状态的一部分；只有源提交相同，且 release 未指定或已经一致时
才能 no-op。即使 no-op，也必须继续执行边界门，不能让幂等捷径绕过漂移检查。
