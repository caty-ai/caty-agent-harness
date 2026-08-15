# EV-005 sealed parameters (analysis-plan §10)

Status: in the sealing scope; manifest pending. Every numeric lever that can move an outcome
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
- Replicates: **k = 3** runs per task × arm cell; task-level outcome = success proportion
  (0, 1/3, 2/3, 1). Run order interleaved and recorded.

## 5. Analysis set and pilot

- Analysis set: the 30 admitted tasks in `tasks/`, frozen at sealing (§2).
- Pilot: `p01`–`p05` in `pilot-tasks/`, constructed per §7's rule, sealed as a separate list,
  never entering the analysis set or any §4/§6 computation.
