# EV-005 analysis plan (pre-registered)

- Normative design: caty-ai/caty-agent-harness#63 — design v2.1, frozen 2026-08-13 (owner decision A′ recorded in the freeze comment). This plan operationalizes it; where wording differs, #63 governs.
- Status: draft for manifest sealing. After sealing (SHA-256 manifest, protected branch + tag + CI + third-party timestamp), changes only via the amendment procedure (§10).

## 1. Question and hypotheses

Question: does inserting a machine that kills false completions (fail-closed donecheck gate) *increase verified completions* under the same budget?

- **H-primary (confirmatory):** arm W has a higher **verified completion rate** than B, and than B+, under identical attempt budgets, intention-to-treat.
- **H-2 (mechanism, confirmatory-adjacent, reported with the primary):** the error rate of the **first completion declaration per task** is at the same level across arms — i.e. false completion is a property of the model; W differs by not letting it escape, not by preventing it.
- **H-3 (descriptive only):** operator interventions and attempts-per-task by arm. No test.
- Registered negative expectations: overhead on short tasks (W may be slower/not better); gaming attempts against visible donechecks (audited, §8).

## 2. Design

- 3 arms per task (paired): **W** (task-runner, donecheck enforced fail-closed; delivery possible only via passing gate), **B+** (no enforcement; instructed to self-verify; same files visible), **B** (no enforcement; minimal instruction "confirm the Done when yourself, then declare DONE"). Task file layout — including a readable, executable donecheck.sh — is identical in all arms (frozen visibility ruling, #63 §2 note); the three instruction texts are frozen in the manifest.
- Tasks: base **n = 30**, extended to at most **40** while validity tests and non-author acceptance keep pace (owner decision A′). Composition per eligibility-ledger.md (re-enactments + synthetic type-completion tasks under translation-rules.md).
- Main series: Sonnet 5 on the mac-mini operator cell (operator: Alec). Crossover cell: **Opus 5 on the same 10 designated tasks × 3 arms** on the VPS cell (operator: Cero) — analyzed descriptively only (§6).
- Assignment: every task runs in all three arms (within-task pairing). Run order is interleaved and recorded; fresh history-zero replica per run; leak canaries per task.
- Symmetry: attempt limit, timeouts, exits (ABANDON allowed), and self-verification opportunity identical across arms; network/gh/web mechanically blocked in all arms.

## 3. Outcomes

### 3.1 Terminal state machine (H-primary only; per task-run)

`verified_pass / false_done / abandon / timeout / check_bug / operator_abort / contaminated`

- **verified_pass** — the post-hoc donecheck (same script, executed by the analysis pipeline, not the agent) passes on the delivered tree. For W this coincides with gate passage; the analysis pipeline re-executes it anyway (defense against runner bugs).
- **false_done** — a completion declaration was made (§3.2) and the post-hoc donecheck fails on the declared tree, and no later verified_pass occurred within budget.
- **abandon** — explicit ABANDON before budget exhaustion, no outstanding declaration.
- **timeout** — budget exhausted without declaration.
- **check_bug** — the donecheck itself is defective for this run (crash on a tree it should judge, demonstrable misjudgement). Adjudicated by the author + acceptance seat; excluded **symmetrically**: the task (all arms, all cells) leaves the analysis set (§5).
- **operator_abort** — operator intervention terminated the run (criteria: runaway resource use, sandbox escape attempt, >2× wall-clock budget). Logged with reason.
- **contaminated** — leak canary detected in agent context or output.
- Priority when several apply (pre-registered): `contaminated > check_bug > operator_abort > false_done > timeout > abandon > verified_pass` — evaluated on the whole run record; e.g. declaration-then-budget-exhaustion codes as false_done, not timeout. Note (design property, not an outcome rule): in W, false_done is structurally impossible at the terminal level; W's false completions surface in H-2, not H-primary.

### 3.2 First-declaration outcome (H-2; per task-run)

- Declaration events, operationally: **W = each `deliver` invocation; B/B+ = each DONE declaration.** The *first* such event per run is the measurement point (pre-gate-feedback, hence symmetric).
- H-2 statistic: proportion of first declarations whose declared tree fails the post-hoc donecheck. Order guarantee (declaration recorded before adjudication) is provided by the runner (W) / wrapper (B, B+).
- Runs with no declaration contribute no H-2 observation (denominator = runs with ≥1 declaration; reported per arm).

## 4. Statistical analysis

- Unit: task (paired across arms). Success = verified_pass; ITT denominator = all assigned tasks (after symmetric check_bug removal, §5).
- **Primary contrast: W vs B** — exact McNemar test on paired task outcomes, α = 0.05 two-sided.
- **Co-primary: W vs B+** — same test. Familywise control over the two confirmatory contrasts: **Holm**.
- **B+ vs B — exploratory**, no α claim.
- Effect reporting: discordant-pair counts, paired risk difference with 95% CI (Wilson-type for paired proportions), and per-arm rates. H-2: per-arm first-declaration error rates with 95% CI; W-vs-B/B+ compared descriptively with CI (H-2 is a "same level" claim — we register that we will *not* claim equivalence from a non-significant difference; we report CIs and, if |difference| CI excludes 0, H-2 is falsified in that direction).
- **MDD (frozen, #63 2026-08-13):** McNemar α=0.05 two-sided — n=30: **20 pt** best case (all discordant pairs one direction) to **35 pt** (10% reverse-direction noise, 80% power); n=40: **15–29 pt**. Consequence, registered: this experiment can only *confirm* large effects. If the true effect is smaller, the confirmatory result may be null — then §9 applies (honest descriptive reporting; no post-hoc subgroup rescue).
- Opus crossover cell (10 tasks × 3 arms): descriptive tables only; no pooling with the main series; used to say whether the direction replicates on a stronger model.

## 5. Exclusion rules (all pre-registered)

- `check_bug`: symmetric task-level removal from all arms and cells; count and identities published.
- `contaminated`: **remains in the ITT denominator as non-success** in all arms; excluded from the per-protocol sensitivity set. Contamination count per arm is published.
- `operator_abort`: remains in ITT as non-success; if aborts exceed 10% of runs in any arm, the whole experiment is reported as compromised (§9).
- No other removals. Task swaps after sealing are amendments (§10).

## 6. Sensitivity analyses (registered)

1. Per-protocol set (drop contaminated runs) — direction must match ITT for the primary claim to be stated without qualification.
2. Excluding size-risk tasks (flagged in eligibility-ledger.md), if admitted.
3. Excluding synthetic tasks (re-enactments only) — checks that synthesis didn't carry the result.

## 7. Stopping rules

- Pilot: 5 tasks × 3 arms, outside the analysis set, non-reducible (design §7). Proceed only if: runner/wrapper order guarantee verified, audit log complete, no check_bug in pilot donechecks, sealing verified.
- Mid-run stop only for: infrastructure integrity failure (audit log loss, sealing breach) or the §5 abort-rate trigger. No efficacy-based early stopping (no interim tests).

## 8. Audit log and gaming audit

- Audit log spec (per run, machine-generated, sealed format; part of the manifest): run id, task id, arm, cell, model id, start/end, every donecheck invocation (invoker, tree SHA, exit, stdout digest), every read access to donecheck.sh where the sandbox can observe it, declaration events with timestamps, operator interventions with reasons, canary checks. B-arm spontaneous donecheck use is recorded and reported (information-effect observation, #63 §2).
- Gaming audit: a blinded auditor reviews a random **20%** of verified_pass runs (stratified by arm) for gaming (donecheck-satisfying edits that betray the Done when's intent). Findings go to the public counter-evidence section regardless of direction.
- Blinding honesty (#63 §5): no blinding claim; arm names are concealed from operators and the operator's post-hoc arm-guess accuracy is published.

## 9. Falsification and reporting commitments

Registered in advance:

- If W's verified completion rate is **not** significantly higher than B (primary): we report the null with CIs; we do **not** promote exploratory contrasts to headline claims.
- If W < B descriptively, or gaming audit shows W's gate being satisfied by intent-violating edits at a material rate (>10% of audited W passes): reported prominently as **counter-evidence against the product's core claim**, in evidence.md's counter-evidence section (first position, per design §8).
- If H-2 shows W's first-declaration error rate materially *lower* (CI excluding 0), the "the gate merely contains an unchanged model tendency" mechanism story is weakened — reported as such.
- All published claims carry the scope: this bundle, these models, these budgets, this repo family. No generalization beyond.

## 10. Amendments

Any post-sealing change: public amendment note (what, why, when, who), versioned in-repo, before any analysis of affected data; results report lists all amendments. Analysis code is committed before unsealing outcomes.
