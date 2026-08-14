# Task t19

## Goal

Harden the scheduler wrapper's `SECRETS_ENV` loading by treating the file as
`KEY=VALUE` data rather than shell code and by refusing symlinks before loading
them.

## Done when

- [ ] U1. A valid `KEY=VALUE` assignment from `SECRETS_ENV` is exported to the
  scheduler target.
- [ ] U2. Shell syntax in a value is preserved as data and is never executed.
- [ ] U3. A configured `SECRETS_ENV` symlink is refused before the scheduler
  target runs.
- [ ] U4. A local regression test covers data-only loading without shell side
  effects.
- [ ] U5. A local regression test covers `SECRETS_ENV` symlink refusal in the
  same style as the neighboring protected helper path.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `{{BUDGET}}`
- Per-run timeout: `120 s`
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
