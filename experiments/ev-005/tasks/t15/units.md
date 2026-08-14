# t15 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `injection-budget-check` has one bundled input that exits 0 on a clean clone. | `a01` (T3 command-exit). The unique U4 pointer resolves either a fixture directory or a fixture flag. For a directory, the check deterministically tries repository files beneath it with the pre-fix-derived `--manifest` contract and accepts when at least one exits 0; for a flag, it runs the validator with that exact flag. Every attempt gets fresh `HOME` and `TMPDIR`. No fixture filename or directory README is pinned. |
| U2 | MECH | `injection-lint` has one bundled input that exits 0 on a clean clone. | `a02` (T3 command-exit), using the same live directory-or-flag disjunction as U1. The directory branch derives the sorted set of directories containing files beneath the resolved pointer, tries each with the pre-fix-derived `--manifest-dir DIR --all` contract, and accepts when at least one exits 0. The flag branch passes the resolved flag directly. Every attempt gets fresh `HOME` and `TMPDIR`; no fixture subdirectory is pinned. |
| U3 | MECH | `watchdog` has one bundled input that exits 0 on a clean clone. | `a03` (T3 command-exit), using the same live directory-or-flag disjunction as U1. The directory branch deterministically tries repository files beneath it with the pre-fix-derived `--jobs-manifest` contract and accepts when at least one exits 0; the flag branch passes the resolved flag directly. Every attempt gets fresh `HOME` and `TMPDIR`; no fixture filename is pinned. |
| U4 | MECH | A README or the repository map points to the green fixture set in one line. | `a04` (T1/T6 discoverability check). Exactly one line in a root README variant or `docs/repository-map.md` must co-locate `fixture` with `validator` or `smoke` and contain exactly one safe backticked repository-relative directory token ending in `/` or one safe long option. Token names are not pinned: forms such as `examples/smoke/` and `--smoke` are accepted. A relative leaf is resolved against the nearest enclosing Markdown directory section; an already qualified path is used as written. Absolute paths, dot traversal, unsafe characters, missing directories, and multiple pointer lines/tokens fail closed. |

## Anonymization and needle record

- Mapping: the public source repository is rendered as “this repository”;
  tracker, review-seat, and scheduling-time provenance is omitted.
- Anonymization-sweep exemptions: the three validator names remain because
  they are criterion-constitutive targets and their scripts are present in the
  pre-fix replica. No fixture path or flag is exempted or pinned.
- Longest fixed structural needle: `python3 scripts/injection-budget-check`
  (38 characters). The criterion names the validator and the pre-fix tree
  contains that Python entry point. Candidate inputs are discovered beneath
  the resolved fixture directory and invoked through pre-fix CLI contracts,
  rather than copied from documentation or the historical fix.
- Timeout remains the default 120 seconds. The gate executes only three
  deterministic fixture-tree searches and bounded validator attempts, each
  under a fresh `HOME` and `TMPDIR`, so no escalation is needed.
