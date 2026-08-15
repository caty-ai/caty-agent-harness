# Task t25

## Goal

Make the family updater establish the identity and authenticity of a release
before checking it out or running repository code, and fail closed with an
actionable diagnostic when verification cannot be completed.

## Done when

- [ ] U1. The updater's trust mechanism is explicitly chosen and documented:
  release tags use SSH signatures verified against an out-of-repository
  `allowed_signers` pin.
- [ ] U2. The updater refuses any candidate checkout that has not passed that
  verification, and never runs its installer for the refused candidate.
- [ ] U3. Verification failures are fail-closed and report a clear reason.
- [ ] U4. Focused updater regressions cover a tampered or moved tag and an
  attacker-substituted unsigned tag.

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
