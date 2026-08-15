# Task p01

## Goal

Generalize the deterministic flush-intake consumer so a second adapter shares
the same guarded core, ship a host-staged verifier example for that adapter,
and preserve the existing claude-code scheduler contract.

## Done when

- [ ] U1. `scripts/flush-intake.sh` holds the shared intake core, and both
  adapter entry scripts are real guarded entries that canonicalize the
  workspace, derive adapter identity, check pause state, and source the core
  only after the guard.
- [ ] U2. Pause-status output and the state-lock caller share the
  `<adapter>-flush-intake` identity; claude-code still reports
  `claude-code-flush-intake`, and Hermes reports `hermes-flush-intake`.
- [ ] U3. The claude-code intake entry remains the load-bearing scheduler
  target: it stays at `adapters/claude-code/flush-intake.sh`, keeps the
  one-argument interface and paused exit-0 contract, and is still the exact path
  the cron wrapper self-mark rule recognizes.
- [ ] U4. The Hermes bootstrap block remains `v2`, and both the Hermes
  bootstrap FLUSH text and the claude-code stop-hook flush reminder encode the
  same Lessons-only / Open failures / persona-guard / no self-fold contract.
- [ ] U5. The shared intake core strips control characters before parsing,
  drops oversized bullets at `INTAKE_MAX_BULLET_BYTES`, and surfaces
  `dropped_oversize`.
- [ ] U6. Lessons displaced by the STATE cap are appended to
  `loop/archive/intake-evictions-<UTC-date>.md`, and receipts surface both
  `evicted_by_cap` and the archive path.
- [ ] U7. The example verifier provider keeps credentials in environment
  variables, makes one stateless provider call, uses an unguessable delimiter
  around the untrusted bundle, and lets `VERIFIER_MODEL` choose the model.
- [ ] U8. The example verifier wrapper takes the bundle in `argv[1]`, rejects
  empty or undersized bundles, launches exactly
  `FABLE_CONFORMING_PROVIDER_PATH`, and rejects provider output with missing or
  repeated `VERDICT:` lines.
- [ ] U9. The example verifier probe relocates the provider and genuinely
  exercises the wrapper/provider path instead of echoing a constant verdict.
- [ ] U10. `scripts/activation-manifest.tsv` registers the shared intake core,
  both adapter entry points, and the Hermes example files with the correct
  guarded/exempt classes.
- [ ] U11. `adapters/hermes/INSTALL.md` documents the flush-intake LaunchAgent
  flow with `TARGET`, `CATY_HARNESS_ROOT`, `INTAKE_MAX_FOLD=5`,
  `StartInterval 28800`, and the requirement to leave `DEADMAN_MARKER` unset
  for the Hermes target.
- [ ] U12. Repository tests include substantive Hermes coverage for the shared
  intake entry path and the verifier examples.
- [ ] U13. The full repository shell test suite (`tests/*.test.sh`) passes.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `1800 s` per `.ev005-donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `.ev005-donecheck.sh` ships with this task at the repository root; it is
  readable and executable.
