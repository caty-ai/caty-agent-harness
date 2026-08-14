# t28 units ledger

Units: 11 total; covered 11/11
MECH: 10
HUMAN: 1
MOOT: 0

Anonymization mapping: the source repository is "this repository"; epic,
checkpoint number, issue/commit references, owner identity, dates, and the
Japanese summary are omitted. Functional boundary names and repository-local
paths remain because they are necessary to solve and execute the task.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | A design note distinguishes mechanical enforcement from operator responsibility. | `a01` (T1 content-presence in `DESIGN-task-runner.md`, co-locating trust/boundary language with mechanical limits and operator responsibility). |
| U2 | HUMAN | The trust-model decision has human checkpoint approval. | Dropped (HUMAN: checkpoint approval is an external human judgment and tracker record unavailable in the history-zero replica). |
| U3 | MECH | Quoted `#` is preserved and validation sees the exact staged executable text. | `a02` (T5 direct production probe: install a temporary workspace, enqueue a valid task whose raw donecheck contains a quoted `#`, require acceptance, and byte-compare the installed staged task with the submitted file). The probe exercises the public enqueue path rather than grepping the historical implementation. |
| U4 | MECH | A focused regression covers quoted `#`. | `a03` (T3 discovery: find and execute a tracked `tests/*.test.sh` containing the quoted-hash enqueue case). The test filename is not pinned. |
| U5 | MECH | Enqueue validates UTF-8, a single closed block, raw syntax, and a pinned Bash. | `a04` (T1/T6 structural checks in the design note and production sources) plus `a10` (T3 focused suites). The functional tokens `UTF-8`, `donecheck`, and pinned interpreter paths are replica-derivable. |
| U6 | MECH | Donecheck execution uses an allowlisted environment and recorded interpreter. | `a05` (T1 content-presence of the environment/interpreter contract in the design note) plus `a10` (T3 runner regression suite). |
| U7 | MECH | Timeout, process-group termination, and best-effort resource limits are implemented and documented. | `a06` (T1 content-presence in the design note and runner) plus `a10` (T3 runner/spawn regressions). |
| U8 | MECH | Delivery requires a safe declared receipt below `out/`. | `a07` (T1/T6 content and implementation anchors for non-symlink, regular, non-empty, resolved-under-`out/` enforcement) plus `a10` (T3 enqueue/runner regressions). |
| U9 | MECH | The configured step provider must be absolute, regular, and executable. | `a08` (T1 content-presence in the design note and runner) plus `a10` (T3 spawn regression suite). |
| U10 | MECH | Focused boundary regression suites pass. | `a10` (T3 command-exit: the existing extraction, enqueue, runner, and spawn suites; these are narrower than the full repository suite, which the source criterion does not demand). |
| U11 | MECH | Residual risks cover same-user arbitrary shell, queued mutation, process-group escape, and unattested provider contents. | `a09` (T1 content-presence inside the residual-risk section using small functional fragments). |

Needle calibration and solvability:
- Longest fixed T1/T4 phrase is `post-enqueue mutation` (21 characters), a
  task-stated residual-risk concept rather than historical fix prose.
- The quoted-hash check is behavioral. Other needles are functional boundary
  tokens stated in task.md or derivable from pre-fix design/runner sources.
- Timeout remains 120 seconds; only focused local suites are run.
