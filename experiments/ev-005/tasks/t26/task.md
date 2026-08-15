# Task t26

## Goal

Give the repository's command-line tools one documented contract for output
prefixes, exit codes, and stdout/stderr routing, while preserving consumer-bound
behaviors as explicit frozen deviations and pinning the contract with focused
regressions.

## Done when

- [ ] U1. `docs/cli-conventions.md` defines the warning-prefix convention and
  records the current nonconforming prefixes as frozen or deferred deviations.
- [ ] U2. The note defines exit-code meanings and records the deliberate
  deviations, including `tr-enqueue` usage exit `1` and optional diagnostic
  `FAIL` rows that still exit `0`.
- [ ] U3. The note defines stdout/stderr routing: machine rows stay on stdout
  and human `warning:` advisories stay on stderr.
- [ ] U4. The note accounts for the listed command-line surfaces either as
  conforming behavior or as a recorded frozen deviation, and inventories the
  existing regression pins that prevent silent drift.
- [ ] U5. A focused conventions regression pins the current usage exit codes,
  including the deliberate `tr-enqueue` deviation, and passes without changing
  the repository or its throwaway workspace.

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
