# t23 units ledger

Units: 6 total; covered 6/6
MECH: 6
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | Corrupt artifact state is clearly diagnosed and isolated without an uncaught parse crash; healthy queued work can still progress, with a regression test. | `a01` (T5: seed one corrupt state plus one healthy queued task in a temporary workspace; require a `corrupt state.json`/`quarantined` diagnostic, unchanged corrupt bytes, no corrupt attempt, and healthy delivery) plus `a07` (T6 test-coverage structure). |
| U2 | MECH | Intake and runner interpret quoted frontmatter identifiers consistently, with a regression test. | `a02` (T5: enqueue `id: "qt-1"`, run one successful tick, require exactly the unquoted artifact/delivery identity, and require duplicate detection on re-enqueue) plus `a07`. The arbitrary probe ID is fixture data, not a T1/T4 needle. |
| U3 | MECH | A failed queue copy leaves no artifact or partial queue entry and allows retry, with a regression test. | `a03` (T5: inject a failing `cp` through temporary `PATH`, require no artifact/queue/temp residue, then retry successfully) plus `a07`. The shim and all writes stay outside the repository. |
| U4 | MECH | Intake rejects missing and impossible UTC `created` values with clear messages, with regression tests. | `a04` (T5: submit one missing timestamp and one calendar-impossible timestamp; both must reject and co-locate `created` with `UTC` in the diagnostic) plus `a07`. The probe timestamp is synthetic fixture data, not provenance. |
| U5 | MECH | Legacy invalid `created` values are reported and sort after valid timestamps, with a regression test. | `a05` (T5: queue a valid and missing-`created` task, require valid delivery first with a warning, then legacy delivery on the next tick) plus `a07`. |
| U6 | MECH | `TR_STEP_TIMEOUT_S` and `TR_GRACE_S` reject non-integers before arithmetic or workspace mutation with a clear message, with regression tests. | `a06` (T5: invoke the runner once per named variable with a non-integer, require exit 2, a variable-specific `non-negative integer` diagnostic, and no lock/artifact mutation) plus `a07`. The fix also validates another replay-size variable, but it is intentionally outside this gate because the source criterion does not name it. |

`a07` is a T6 structural coverage check over the two pre-fix-derivable targeted
test modules. It uses short behavior identifiers rather than historical test
case prose. Direct T5 probes independently prove every runtime behavior, so a
broad full-suite T3 is unnecessary.

## Pair sanity, anonymization, and needle record

- Pair: fix `1aa6bdaa385458c78e6d0c06e84647a5f9359672`; resolved parent pre-fix `5ae06864018abf3c1aaa3e08ec72bfa4a47241cd`. The fix is an ancestor of `origin/main`.
- Central spot check before authoring: the pre-fix tree has no corrupt-state quarantine diagnostic and no UTC `created` intake validation; both behavior paths and their regression cases exist at the fix.
- Mapping: the source harness repository is rendered as “this repository,” matching the established harness stand-in. Script paths, frontmatter key, and environment-variable names remain because the criterion names or relies on them.
- Longest T1/T4-style structural needle: `TR_STEP_TIMEOUT_S` (17 characters, criterion-constitutive). No assertion pins a historical fix-prose sentence.
- Timeout remains the default 120 seconds. The gate uses six narrow temporary-workspace T5 probes and does not run the broad task-runner suite.
