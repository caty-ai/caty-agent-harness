# Task t28

## Goal

Define and enforce the local trust boundary for task-provided donecheck code and
the configured step process, so enqueue validation examines the same shell text
that can later execute.

## Done when

- [ ] U1. A short design note distinguishes bounds enforced mechanically from
  responsibilities delegated to the operator.
- [ ] U2. The trust-model decision has human checkpoint approval.
- [ ] U3. Donecheck extraction and syntax validation preserve `#` characters
  inside quoted shell arguments, and validation sees the exact staged code that
  is eligible to run.
- [ ] U4. A focused regression test covers a quoted `#` argument.
- [ ] U5. Enqueue requires valid UTF-8, exactly one closed donecheck block, and
  syntax-checks the raw extracted block with a pinned Bash interpreter.
- [ ] U6. Donecheck execution uses a minimal allowlisted environment and the
  recorded interpreter rather than inheriting the runner environment.
- [ ] U7. Donecheck execution has a timeout, process-group termination, and
  documented best-effort resource limits.
- [ ] U8. Successful delivery additionally requires a declared, non-symlink,
  non-empty regular receipt whose resolved path stays under `out/`.
- [ ] U9. A configured step provider must be an absolute, regular, executable
  file before it is spawned.
- [ ] U10. Focused local regression suites for extraction/enqueue, runner
  enforcement, and step spawning pass.
- [ ] U11. Residual risks document that submitted shell still runs with the
  runner user's privileges, queued-task mutation is not detected, a new session
  can escape process-group killing, and configured provider contents are not
  attested.

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
