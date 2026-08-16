# EV-005 sealed parameters (analysis-plan §10)

Status: **SEALED** (covered by `MANIFEST.sha256`). Every numeric lever that can move an outcome
lives here, frozen, so no parameter is chosen after seeing data.

## 1. Gaming-audit sample (analysis-plan §8)

    gaming_audit_seed = 20260815
    arm_index         = {W: 0, "B+": 1, B: 2}
    sample_size(arm)  = all runs if n_arm < 5, else max(5, ceil(0.20 * n_arm))

Draw procedure (deterministic, reproducible by any third party from the sealed run ledger):
for each arm, take that arm's `verified_pass` run_ids, sort them lexicographically, and select
with `random.Random(gaming_audit_seed + arm_index).sample(sorted_ids, sample_size)`. No operator
discretion enters the sample. The auditor receives only the task sheet and a `git archive`
export of the adjudicated snapshot — no runner artifacts, no logs, no arm identity (§8).

## 2. MDD simulation

Seed `20260815`, sealed in `tools/mdd-sim.py` (`SEED`). Scenario grid, data model, and the exact
sign-flip construction are documented in that file's header; the resulting table is
`tools/mdd-power-table.md`, summarized in §4. The table is **n = 30 only** — an extension
amendment must re-run the simulation at the new n before extension runs start (§2).

## 3. Crossover cell (descriptive, §2)

Ten designated tasks, fixed before any run, by the deterministic every-third rule from t02:

    t02, t05, t08, t11, t14, t17, t20, t23, t26, t29

## 4. Budgets and replicates (owner decision, 2026-08-14)

- Attempt budget per run: **45 minutes agent wall-clock**, **at most 5 completion declarations**.
  Identical across arms; printed in every task sheet.
- Verification time is carved out of the attempt budget and is not itself budgeted:
  per-invocation bound = the task's `meta.json` `timeout_s`, fail-closed. The wrapper pauses the
  wall-clock for every `donecheck_invocation`, arm- and invoker-symmetric (runner-spec §1.6),
  and publishes `wallclock_s` / `paused_s` / `elapsed_s` per run.
- **Budget definition (amendment A-3.4):** budgeted agent wall-clock = *controller process
  elapsed time* − *the registered `donecheck_invocation` pause intervals*, **and nothing else**.
  Provider queueing, retries, backoff, throttling and reconnects are inside the budget — excluding
  them would give arms that make more model turns more effective model time, and W is exactly that
  arm. `provider_wait_s`, `provider_retry_count`, `provider_throttle_count` and
  `provider_longest_stall_s` are published per run; unmeasurable components are `null`, not `0`.
- Replicates: **k = 3** runs per task × arm cell; task-level outcome = success proportion
  (0, 1/3, 2/3, 1). Run order interleaved and recorded.

## 5. Analysis set and pilot

- Analysis set: the 30 admitted tasks in `tasks/`, frozen at sealing (§2).
- Pilot: `p01`–`p05` in `pilot-tasks/`, constructed per §7's rule, sealed as a separate list,
  never entering the analysis set or any §4/§6 computation.

## 6. Execution scheduling (amendment A-3.3)

    schedule_seed = 20260816

Governs execution scheduling only; it enters no analysis, no outcome coding and no test. A
**block** is one (task, replicate *k*) pair, and its three runs — W, B+, B — execute concurrently
in one scheduling group, so all three meet the same host and provider conditions at the same
moment.

Only the **block order** is drawn from the seed. The arm→slot and block→seat mappings are
deterministic rotations, so they are balanced **exactly** rather than in expectation. This is the
complete procedure; it is valid Python and any third party can run it against the sealed task
lists and the sealed seat pool and obtain the schedule byte-for-byte:

```python
import random

SCHEDULE_SEED = 20260816
ARMS = ["B", "B+", "W"]          # canonical order, fixed by the seal

def blocks_of(task_ids, k_max=3):
    """Canonical enumeration: task id ascending lexicographically, then k ascending."""
    return [(t, k) for t in sorted(task_ids) for k in range(1, k_max + 1)]

def schedule(series, task_ids, seat_pool, k_max=3):
    """series is one of "main", "crossover", "pilot" — each is scheduled independently."""
    order = blocks_of(task_ids, k_max)
    random.Random(f"{SCHEDULE_SEED}:order:{series}").shuffle(order)
    rows = []
    for rank, block in enumerate(order):            # rank is the 0-based execution position
        seat = seat_pool[rank % len(seat_pool)]
        for arm in ARMS:
            slot = (ARMS.index(arm) + rank) % 3     # cyclic rotation by the block's rank
            rows.append({"block": block, "rank": rank, "arm": arm,
                         "slot": slot, "seat": seat})
    return rows
```

**Verified by instantiation, not asserted** (author, 2026-08-16; re-runnable from the code above):

| series | blocks | runs | arm × slot counts | runs per seat (5 seats) |
| --- | --- | --- | --- | --- |
| main | 90 | 270 | every arm `[30, 30, 30]` | 54 each, spread 0 |
| crossover | 30 | 90 | every arm `[10, 10, 10]` | 18 each, spread 0 |
| pilot | 15 | 45 | every arm `[5, 5, 5]` | 9 each, spread 0 |

In every series: each block runs on **one** seat across three distinct slots; **every seat sees
each arm equally**; and arm × slot is exactly uniform. Seat occupancy is uniform in all three
series because 90, 30 and 15 are each divisible by the pool size of five — one of the reasons the
pool was fixed at five (`environment-digest.md`).

*Why this replaces the previous rule (pre-registration integrity note).* The first draft drew an
independent random permutation per block. A review seat instantiated it and measured arm × slot
counts of `B [33,29,28]`, `B+ [23,35,32]`, `W [34,26,30]` — orthogonal in expectation, visibly not
in fact at n = 90 — and four further seats independently reported that the pseudo-code was not
executable as written (`shuffle` returns `None`; the block enumeration was undefined). The author
reproduced those exact counts before adopting the finding. The remedy is not a better seed: a
cyclic rotation removes the sampling noise entirely and needs no luck.

Concurrency (`pilot_blocks_concurrent = 5`; `main_blocks_concurrent` from the pilot by the rule
fixed in `environment-digest.md`) is an operational parameter, not an analysis parameter, and is
recorded in the run ledger before the first main-series run. Note that the rotation above makes
five concurrent blocks land on five distinct seats, so a wave never puts two blocks on one seat.

## 7. Pilot gates (analysis-plan §7)

    provider_wait_gate_s = 135        # = 5% of the 2700 s attempt budget

Provider-wait disparity gate, fixed here before any pilot run exists: the pilot's per-arm mean
`provider_wait_s` (published per run, runner-spec §5) is compared between the primary-contrast
arms, and if `|mean_W − mean_B+| > provider_wait_gate_s` the main series does not start until
the owner has reviewed a public budget-comparability memo (analysis-plan §7). The threshold is
5% of the attempt budget: below it, a wait disparity moves effective per-run agent time by less
than the run-to-run noise the k=3 design already absorbs; above it, budget comparability — the
stated identity condition of the primary contrast — is in question and a human decides.
**Null branch (fail-closed):** any pilot run with `provider_wait_s = null` makes this gate not
evaluable, which is treated as triggered (analysis-plan §7); the same null condition fails the
`main_blocks_concurrent = 5` test in `environment-digest.md`, which then resolves to 3 pending
owner review of the channel failure.

## 8. Host-operator cross-check of the registered runner (amendment A-3.2)

    crosscheck_seed        = 20260817
    crosscheck_sample_size = max(10, ceil(0.10 * main_series_runs))   # = 27 at 270 runs

Fixed before any run exists: after the main series completes, take all main-series scoring
run_ids sorted lexicographically and draw `crosscheck_sample_size` of them with
`random.Random(crosscheck_seed).sample(sorted_ids, crosscheck_sample_size)`. The host operator's
independent second implementation re-executes the adjudication for each sampled run on the same
host and the same inputs. **The drawn run_ids are published together with the seed at draw time**
(a golden vector, so the draw is verifiable without pinning an interpreter version — delta-seat
suggestion). Every disagreement in outcome coding is published, and each is adjudicated under
the §3.1/§5 `check_bug` machinery (arm- and outcome-redacted records, symmetric removal if
upheld). Same-host agreement removes the environment as an explanation for a disagreement; it
does **not** recreate an independent operator, and is not claimed to.
