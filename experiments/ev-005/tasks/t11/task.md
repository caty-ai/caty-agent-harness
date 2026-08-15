# Task t11

## Goal

Make the installer's read-only health check predict whether a configured
`SECRETS_ENV` file will be accepted by the scheduler wrapper, while keeping the
two consumers on one shared acceptance-rule source and preserving the checker's
published output contract.

## Done when

- [ ] U1. `install.sh --check` rejects a configured `SECRETS_ENV` symlink in
  the same way the scheduler wrapper rejects it.
- [ ] U2. Both consumers accept an indented `KEY=VALUE` assignment.
- [ ] U3. Both consumers reject a malformed line that is not a `KEY=VALUE`
  assignment.
- [ ] U4. Both consumers reject a value continued onto a second physical line.
- [ ] U5. Both consumers reject a configured `SECRETS_ENV` file containing an
  embedded NUL byte.
- [ ] U6. Both consumers reject interpreter- or loader-control variable names.
- [ ] U7. `install.sh --check` reports each rejected file as either a
  `warning:` advisory on stderr or a documented `FAIL` machine row on stdout.
- [ ] U8. Those `SECRETS_ENV` diagnostics do not change the existing successful
  exit-code contract of `install.sh --check`.
- [ ] U9. The acceptance grammar and refusal list have one production source
  shared by `install.sh` and the scheduler-wrapper template, so they cannot
  drift independently.
- [ ] U10. A targeted local regression test demonstrates that a file rejected
  by the wrapper is also diagnosed by `install.sh --check`.
- [ ] U11. The targeted regression test demonstrates that a file accepted by
  the wrapper produces no `SECRETS_ENV` diagnostic from `install.sh --check`.
- [ ] U12. Existing human advisories still use the exact `warning:` prefix on
  stderr.
- [ ] U13. Existing absent-path rows still use the exact `missing ` prefix on
  stdout.
- [ ] U14. Existing stdout machine rows remain on stdout rather than stderr.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `120 s` per `donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
