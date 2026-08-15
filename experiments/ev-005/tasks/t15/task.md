# Task t15

## Goal

Add a minimal bundled fixture set that lets a reader verify the three shipped
worked-example validators on a clean clone without depending on local paths or
budgets.

## Done when

- [ ] U1. `injection-budget-check` has one bundled input that exits 0 on a
  clean clone.
- [ ] U2. `injection-lint` has one bundled input that exits 0 on a clean clone.
- [ ] U3. `watchdog` has one bundled input that exits 0 on a clean clone.
- [ ] U4. A README or the repository map points to the green fixture set in
  one line.

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
