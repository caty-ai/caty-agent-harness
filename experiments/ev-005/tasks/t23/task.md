# Task t23

## Goal

Make task intake and runner processing reject or recover from malformed inputs
with clear diagnostics, consistent parsing, and retry-safe state.

## Done when

- [ ] U1. A corrupt artifact `state.json` is reported clearly and quarantined
  from processing without an uncaught parse crash; other healthy queued work
  can still progress, and a regression test covers this recovery.
- [ ] U2. Quoted frontmatter identifiers are interpreted consistently by
  intake and the runner, without creating a second quoted artifact identity,
  and a regression test covers the behavior.
- [ ] U3. If intake cannot copy a task into the queue, it leaves neither an
  artifact directory nor a partial queue entry, so retrying the same ID can
  succeed; a regression test covers the failure path.
- [ ] U4. Intake requires `created` to be a real UTC ISO-8601 timestamp with
  seconds and rejects missing or impossible values with a clear message; a
  regression test covers both forms.
- [ ] U5. Legacy queued tasks whose `created` value is missing or invalid are
  reported and sorted after valid timestamps instead of silently running
  first; a regression test covers the scheduling behavior.
- [ ] U6. `TR_STEP_TIMEOUT_S` and `TR_GRACE_S` are validated as non-negative
  integers before runner arithmetic; bad values exit with a clear message and
  a regression test covers each variable.

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
