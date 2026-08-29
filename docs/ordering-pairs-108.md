# Startup ordering inventory for issue #108

This inventory covers the configurable thresholds and caps in
`scripts/task-runner.sh`, `adapters/hermes/spawn_step.sh`,
`adapters/hermes/verify-job.sh`, `scripts/flush-intake.sh`, and
`scripts/lib-state-fold.sh`. Phase 1 adds entry guards without changing valid
defaults. Phase 2 records the intake relationship but deliberately leaves its
consumer and tests unchanged.

## Ordering and positivity invariants

| Pair or threshold | Where asserted | Silent failure shape prevented | Phase |
| --- | --- | --- | --- |
| `TR_GRACE_S < TR_STEP_TIMEOUT_S` | `scripts/task-runner.sh` startup | Recovery can outlive the operation it is meant to clean up. | Phase 1 |
| `HERMES_HTTP_TIMEOUT_S <= HERMES_STEP_TIMEOUT_S` | `adapters/hermes/spawn_step.sh` pre-flight | The wrapper can kill the step before the HTTP client reports its own timeout, hiding the useful failure boundary. | Phase 1 |
| `HERMES_STEP_GRACE_S < HERMES_STEP_TIMEOUT_S` | `adapters/hermes/spawn_step.sh` pre-flight | Cleanup can take at least as long as the operation it is cleaning up. | Phase 1 |
| `HERMES_STEP_TIMEOUT_S + HERMES_STEP_GRACE_S < TR_STEP_TIMEOUT_S` | `adapters/hermes/spawn_step.sh` pre-flight | The driver hard-kill can preempt the adapter's partial-result quarantine. | Phase 1 |
| `VERIFY_GRACE_S < VERIFY_TIMEOUT_S` | `adapters/hermes/verify-job.sh` entry | Verifier cleanup can outlive the verification window. | Phase 1 |
| `TR_D21_NO_PROGRESS_THRESHOLD > 0` (hard internal value `2`) | `scripts/task-runner.sh` startup | A zero threshold can make the first noncomplete attempt terminal; the two normal and crash-recovery comparisons can also drift apart when expressed as literals. | Phase 1 |
| `INTAKE_MAX_FOLD <= STATE_FOLD_LESSONS_CAP_DEFAULT` (the current `STATE_FOLD_LESSONS_CAP`) | Not yet asserted; the values meet in `scripts/flush-intake.sh` after `scripts/lib-state-fold.sh` is sourced. | An intake soft limit above the Lessons hard cap never constrains a run before FIFO eviction. | Phase 2 |

Every Phase 1 ordering guard exits `2`, reports every involved variable and
value, and runs before the entry point begins work. The D21 value remains an
internal constant rather than a new environment configuration surface.

## Examined near-misses that are not ordering pairs

- `TR_LEDGER_FOLD_MAX_BYTES` is a per-loop chunk size, while
  `TR_LEDGER_FOLD_TOTAL_MAX_BYTES` is a cumulative budget. The fold loop already
  clips each chunk to the remaining total; neither value is a soft threshold
  that must be less than the other.
- `TR_DONECHECK_TIMEOUT_S` times a separate verification subprocess after a
  step. It is not an inner timeout under `TR_STEP_TIMEOUT_S`, so ordering the two
  would create a new combined-budget contract.
- `TR_GATE_REPLAY_MAX_BYTES` is independently clamped at use. It has no semantic
  ordering with the ledger byte budgets.
- `HERMES_VERIFY_BUNDLE_MAX_BYTES` and `INTAKE_MAX_BULLET_BYTES` have fixed
  numeric ranges, not relationships with another configurable threshold.
- `STATE_FOLD_LESSONS_CAP_DEFAULT`, `STATE_FOLD_FAILURES_CAP_DEFAULT`,
  `STATE_FOLD_VERIFIED_CAP_DEFAULT`, and `STATE_FOLD_RULES_CAP_DEFAULT` bound
  different `STATE.md` sections. Their relative sizes do not control one
  another.
