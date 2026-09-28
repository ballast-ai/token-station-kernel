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
- 镜像只跟随上游已发布的 kernel 源码标签（`kernel-v*`），不跟随任意提交或
  应用发布标签；因此每个镜像状态都对应上游明确命名的 kernel 源码状态。

## Cut point

The initial cut is upstream tag **`v1.1.3`** (commit
`9864e79c48c1a05c17db7ecb0b34cd9179a016f1`)。这是独立标签族建立前的历史
切点；当前及后续切点统一使用 **`kernel-v*`**。当前切点记录在
`compatibility.json` 的
`mirror.*` together with the two subtree tree-hashes, which is what makes
"byte-identical" a checkable claim rather than a promise.

One naming caveat for archaeologists: an earlier private lineage of the
upstream project also used the tag name `v1.1.3` for different content. Any
reference to an upstream tag is only meaningful together with the repository
(and ideally the commit hash), which is why `compatibility.json` records the
commit, not just the tag.

## Sync procedure

下述流程由 **`scripts/sync-upstream.sh --tag <kernel-v-tag>`** 自动执行：脚本
幂等、拒绝应用 `v*` 标签、校验字节一致性、更新 `compatibility.json` 并运行
门禁，但把评审、打标签和推送留给维护者。每周 `upstream-freshness` CI 在上游
出现更新的 `kernel-v*` 源码标签时失败，并明确忽略应用 `v*` 发布。下方保留
手工命令，用于解释脚本实际执行的步骤。

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

同步脚本会机械比较上述继承项以及完整的 `clippy.toml`、`rustfmt.toml`。
上游根清单即使因应用成员或 south 依赖而变化，只要 kernel 继承面完全相容，脚本才
继续；任何继承面漂移都会在 subtree 合并前硬失败。本仓当前根配置已与
`kernel-v0.4.0` 的这些项目逐项相容。
