# Task t16

## Goal

Make `recall` enforce owner-only permissions on the Supermemory credentials env
file at runtime, with regression coverage and matching usage documentation.

## Done when

- [ ] U1. `recall` rejects a credentials env file whose mode is not `0600`,
  with a clear error message.
- [ ] U2. A regression test covers acceptance of a credentials env file whose
  mode is `0600`.
- [ ] U3. A regression test covers rejection of a credentials env file whose
  mode is not `0600`.
- [ ] U4. `docs/recall-usage.md` documents that `recall` enforces mode `0600`
  for the credentials env file.

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
