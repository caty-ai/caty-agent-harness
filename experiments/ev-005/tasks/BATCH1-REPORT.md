# EV-005 batch 1 drafting report

| Task ID | Source | Units MECH/HUMAN/MOOT | Validate VERDICT | Notes / BLOCKED |
|---|---|---:|---|---|
| t01 | `harness-37.md` | 19 / 3 / 3 | `VERDICT t01 PASS` | `timeout_s=1800`: the source-required full test suite exceeded the default timeout in isolated replicas. Two source-verification units were weakened to deterministic repository evidence; owner confirmation was dropped as HUMAN, and post-merge/tag/release actions were dropped as MOOT. |
| t02 | `harness-17.md` | 25 / 0 / 0 | `VERDICT t02 PASS` | All 25 units have mechanical assertions. |
| t03 | `harness-43.md` | 7 / 1 / 2 | `VERDICT t03 PASS` | The non-test filename sweep preserves the mechanically decidable part of the source criterion; risk-label review is HUMAN, and CI/merge-state requirements are MOOT. |
| t04 | `sgl-1.md` | 8 / 1 / 0 | `VERDICT t04 PASS` | The private-reference semantic review is HUMAN; a deterministic private-reference count was retained as the documented HUMAN-to-MECH extraction. |
| t05 | `harness-18.md` | 37 / 0 / 0 | `VERDICT t05 PASS` | All 37 units have mechanical assertions. |
| t06 | `harness-15.md` | 26 / 0 / 0 | `VERDICT t06 PASS` | All 26 units have mechanical assertions. |
| t07 | `harness-39.md` | 21 / 0 / 4 | `VERDICT t07 PASS` | `timeout_s=1800`: the source-required full test and lint suites exceeded the default timeout in isolated replicas. A T4 sweep rejects occurrences outside the explicit frozen-identifier/model-name allowlist without requiring allowed occurrences to remain; mainline/tag/release actions are MOOT. |
| t08 | `harness-16.md` | 39 / 0 / 0 | `VERDICT t08 PASS` | All 39 units have mechanical assertions; the complete binding frozen-identifier list is retained as code-level identifiers. |

## Verification summary

- Coverage: 196/196 Done when units are recorded in the eight `units.md` ledgers.
- Admission: every task completed five clean pre-fix failures and five clean fix-state passes.
- Read-only gate: no validation log contains a `DIRTY-TREE` line.
- Shell syntax: all eight `donecheck.sh` files pass `bash -n`.
- Anonymization: all eight `task.md` files have zero case-insensitive matches for the required provenance sweep.
- Blocked tasks: none.
