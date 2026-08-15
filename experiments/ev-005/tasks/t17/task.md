# Task t17

## Goal

Make task-runner failures and operational knobs visible: preserve failed
dead-letter pushes as evidence, keep scheduler marker guidance aligned with the
probe, make the completion-gate timeout configurable, and remove the fixed
baseline placeholder from generated metrics.

## Done when

- [ ] U1. A failed dead-letter report push is recorded in a log beside the
  report.
- [ ] U2. A failed dead-letter report push is surfaced in the report and as a
  warning, without turning the push failure into the task-runner's result.
- [ ] U3. Scheduler templates name the same marker files that the deadman probe
  derives from its default checks.
- [ ] U4. A regression test covers the template-to-probe marker agreement.
- [ ] U5. The completion-gate timeout is tunable through
  `TR_DONECHECK_TIMEOUT_S`.
- [ ] U6. `TR_DONECHECK_TIMEOUT_S` has a documented and validated default of
  `60` seconds.
- [ ] U7. The generated metrics baseline contains no fixed `B0` estimate row;
  that row is either computed from repository data or removed.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `120 s` per `.ev005-donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `.ev005-donecheck.sh` ships with this task at the repository root; it is
  readable and executable.
