# Security Policy

Token Station Kernel is a pre-1.0 library mirror with no supported production
release yet. Report suspected vulnerabilities privately through GitHub's
security advisory interface — for defects in the mirrored crates, prefer the
upstream repository
([`ballast-ai/token-station`](https://github.com/ballast-ai/token-station)),
which is where the fix must land; advisories filed here for mirrored code will
be forwarded. Do not include real credentials, customer content, or personal
data in an issue.

## Security invariants

- The kernel performs no I/O: no network, no filesystem, no environment
  reads, no databases, no clocks, no randomness. Its external dependency
  surface is exactly `serde` and `serde_json`, enforced by
  `scripts/check-boundaries.sh`.
- `unsafe` code is forbidden workspace-wide (`unsafe_code = "forbid"`).
- Routing decisions carry no request content: `router-core` digests protocol
  inputs into content-free records (numbers and operator-chosen names only).
- The mirrored subtrees are byte-identical to a recorded upstream state
  (`compatibility.json`), so the supply chain question reduces to the
  upstream repository plus this repository's scaffolding.
