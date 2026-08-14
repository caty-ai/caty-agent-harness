# t17 units ledger

Units: 7 total; covered 7/7
MECH: 7
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | A failed dead-letter report push is recorded in a sibling log. | `a01` (T5 behavior probe: run a real task into the dead-letter path with a push helper that writes to both streams and exits 7; require both streams and the exit record in `push.log`). |
| U2 | MECH | The failed push is visible in the report and as a warning without replacing the runner result. | `a02` (T5 on the same isolated workspace: require the runner's successful tick result, a durable failure marker, a `push: failed rc=7` report row, and a `warning: push failed rc=7:` diagnostic). The small prefixes describe the functional output contract, not historical prose. |
| U3 | MECH | Scheduler templates agree with the deadman probe's default marker names. | `a03` (T6 structural: derive check names from `DEADMAN_CHECKS` defaults in `scripts/deadman-probe.sh`, derive marker paths from both scheduler templates, and require exactly the corresponding `.deadman/<check>.marker` form). |
| U4 | MECH | A regression test covers template-to-probe marker agreement. | `a04` (T6 structural discovery across `tests/*.test.sh`: require one test to consume the probe, both scheduler templates, the default-check contract, and the `.marker` convention with a failure path). Test filename and test prose are not pinned. |
| U5 | MECH | The completion-gate timeout is tunable through `TR_DONECHECK_TIMEOUT_S`. | `a05` (T5 behavior probe: run a three-second completion gate with the timeout set to one second and require the runner's log and reason artifact to report the one-second timeout). |
| U6 | MECH | The timeout has a documented, integer-validated 60-second default. | `a06` (T1/T6: require the shell default assignment and membership in the runner's existing integer-validation loop). `TR_DONECHECK_TIMEOUT_S` is retained as the task's public configuration contract; the task sheet exposes it so the replica is solvable. |
| U7 | MECH | The fixed `B0` estimate is computed or removed. | `a07` (T5/T4: generate `METRICS.md` through the repository script in an isolated workspace and require absence of the pre-fix-derived literal placeholder `| B0 | estimate |`; a computed baseline row remains admissible). |

## Anonymization and needle record

- Mapping: the source repository is described by its task runner, scheduler
  templates, probe, and metrics generator; issue, parent-issue, commit, person,
  and date provenance is omitted.
- Functional identifiers and paths already present in the replica remain.
  `TR_DONECHECK_TIMEOUT_S` is a criterion-constitutive public knob explicitly
  specified by this task and is therefore exempt from provenance removal.
- Longest T1/T4 needle: `TR_DONECHECK_TIMEOUT_S=${TR_DONECHECK_TIMEOUT_S-60}`
  (58 characters), a shell assignment that defines the configurable default,
  not a sentence of fix prose. The other absence needle,
  `| B0 | estimate |`, comes directly from the pre-fix tree.
- Timeout remains the default 120 seconds. Each T5 probe is narrow and runs
  against an isolated temporary workspace; no full repository suite is used.
