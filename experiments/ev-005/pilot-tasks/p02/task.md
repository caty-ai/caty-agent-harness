# Task p02

## Goal

Add the missing consumer for queued flush records: pending `flush-*.md`
artifacts produced by the adapter hooks must be folded into `STATE.md`,
archived after consumption, wired to the distill deadman route, and implemented
through the shared state-fold helper instead of duplicated adapter-local logic.

## Done when

- [ ] U1. `adapters/claude-code/flush-intake.sh` exists and folds a real
  `flush-*.md` corpus into `STATE.md` as `Lessons learned` only; duplicate
  bullets are rejected and the state rewrite goes through the shared lock-backed
  fold path.
- [ ] U2. Consumed `flush-*.md` files leave `loop/pending/` and are archived
  instead of deleted.
- [ ] U3. Successful intake touches `loop/.deadman/distill.marker`, and
  `adapters/claude-code/INSTALL.md` documents the consumer and deadman-probe
  wiring for that marker route.
- [ ] U4. The fold implementation used by the Claude-Code intake path is shared
  with the openclaw distillation adapter rather than duplicated inside the
  adapter scripts.

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
