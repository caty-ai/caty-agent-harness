• ## Verdict

  **NO-GO (narrow, document-level) — cumulative over DESIGN v0.3 + EV007-PREREG v0.1.**

  Same shape as my r1 verdict: the skeleton is right, the r1 course corrections mostly landed, and no redesign is needed. But the EV-007 pre-registration — the document whose entire function is to freeze decision-critical definitions — contains two demonstrated internal defects and one unmet r1 gate item. All three are one-paragraph fixes; a second delta review of the prereg plus one design section suffices. The DESIGN document itself would be GO-with-concerns standing alone.

  **R1 blocking findings, per seat-relevance:**

  - **F1 (my r1#1, fire predicate unification) — RESOLVED.** §4 freezes the single predicate on post-turn usage (`injected = input + cache_read + cache_creation`, MA(N=3) level OR slope projection), degenerate rules for turns 1–2 stated, pre-send checkpoint demoted to v2 with the correct physical argument (all enumerated sources are post-turn). The OR-composition rule is one sentence, as required.
  - **F2 (my r1#3, absolute threshold) — RESOLVED.** §4/§5: T_abs=40k OR w×ctx_window, 1M-window blind spot explicitly named and closed, T_abs ∈ {30k,40k,80k} added to the sweep.
  - **F3 (my r1#2, EV-007 freeze) — PARTIALLY RESOLVED.** The prereg exists as a separate document and freezes most of what r1 demanded (miss/false-fire definitions, forced-overflow sub-arm at 64k, per-model pass criteria incl. codex fire-rate-0, nested B/C cells with a pre-registered decision rule, env freeze, exclusion rules, arithmetic checks out: 48+4+8+6=68). But the r1 F3 text explicitly required "auto-enqueue 腕には mid-task handoff 契約を §5 に新設" — that contract is absent (see B3), and the frozen sweep selection rule is inoperable (B2).
  - **F4 (my r1 D-5, TTFB alert-only) — RESOLVED.** §4-1: detect+log+alert only, no kill, unknown models get the longest floor (240s) — the correct inverse of the Hermes GLM incident — SSE-ping exclusion codified in the tap contract, and the #162 ownership boundary (live detection vs post-mortem classification, shared byte tap only) is stated plainly.
  - **F5 (my r1 D-4, fire log split) — RESOLVED with minor omissions** (see N1, N2 — non-blocking).
  - **F6 — RESOLVED.** Unknown-only prior, auto-compaction MA reset + nudge suppression, schema_version, exclusive-accounting rule, tap_status all present in §3–§5.

  ## New blocking findings

  **B1 — False-fire definition: ratio direction unspecified, and under the document's own convention it inverts the metric (demonstrated defect).**
  EV007-PREREG defines false fire as: fired task where the bare control had "硬あふれ無し **かつ** トークン総量比 < 1.5x". Everywhere else in the same document, トークン比 means sentinel/bare (sonnet: "sentinel ≤ bare × 0.6"; codex: "トークン比 ≤ bare × 1.05"). Under that convention, a fire that causes the EV-006 harm pattern — completes but burns 4–6x, i.e. sentinel/bare ≥ 1.5 — is **excluded** from the false-fire count. That is exactly the case DESIGN §6 names as the main one ("EV-006 の本命ケースは『完走するが4〜6x高い』… 誤発火の定義はコストで行う"). The two embedded documents contradict each other on the prereg's primary metric. The definition is only coherent if the ratio is bare/sentinel (bare fine *and* sentinel saved <1.5x → unnecessary fire; bare/sentinel ≥ 1.5x → justified cost-saving catch; sentinel blowup → bare/sentinel ≈ 0.25 < 1.5 → counted). Fix is one line — state the ratio direction explicitly — but a pre-registration with an ambiguous primary metric direction is precisely the failure mode pre-registration exists to prevent.

  **B2 — Sweep selection rule is inoperable as frozen (demonstrated defect).**
  副腕3's frozen selection rule: pick the (T_abs, w) minimizing sonnet token ratio "**codex 腕の発火率0 を制約条件**として". But the frozen sweep grid is 6 cells × sonnet-5 only. Codex runs exist solely in the main grid, at the default (40k, 50%). For the other five cells the constraint variable is never measured, so the rule cannot be executed as written. (A clean fix exists — codex's per-turn injected series is logged in the main grid and, if codex never fires at default, is threshold-independent, so fire/no-fire can be re-scored counterfactually across all six cells from those logs — but that procedure is not in the prereg.) Either pre-register the counterfactual re-scoring, add codex cells to the sweep, or drop the constraint from the selection rule.

  **B3 — Mid-task handoff contract: unmet r1 gate criterion.**
  The r1 adjudication's adopted F3 text required the auto-enqueue arm's mid-task handoff contract (interruption of the current step, artifact handoff, context distillation into the new task file) to be newly added to §5. DESIGN v0.3 §5 contains no such contract; §8 defers it to v2 ("…を定義してから"). Yet EV-007's sentinel arm is defined as "v1 実装 + **auto-enqueue on の実験特例**" — the experiment depends on the exact mechanism the design says must be specified before use. As frozen, the sentinel arm's behavior is implementation-defined and non-reproducible, and the prereg's haiku/sonnet pass criteria (which compare this arm) inherit that ambiguity. Add the contract to the prereg or the design before 決裁.

  ## Non-blocking findings

  - **N1.** The `axis` enum regressed against the r1 F5 text: v0.3 has `level|slope|alert`, dropping `both`. Simultaneous level_fire ∧ slope_fire is then unrepresentable. Add `both` back.
  - **N2.** `started_at` (explicitly in the r1 F5 field list) appears in neither the fire nor task_end schema.
  - **N3.** §5 cites bare sonnet L-帯 steady state at ~56% of window, but the w sweep range is {40%, 50%} — entirely below it. For the savings-side reference model, every frozen sweep cell over-fires at steady state, so the sweep cannot discover a *selective* w for sonnet (it can only rank cost among always-firing cells). Defensible if over-firing full-readers is accepted by design (harness helps sonnet), but then say so; otherwise extend the range above steady state (e.g. 60/70%).
  - **N4.** TTFB floor tiers key on request size (>50k / >100k tok), but the v1 byte event carries no size field and pre-send estimation is explicitly v2. State the tier-key source (e.g. previous turn's `injected`) or add an optional size field to the byte event.
  - **N5.** §4's threshold line ("injected絶対 T_abs または w×ctx_window") leaves it ambiguous whether the absolute leg compares MA or instantaneous `injected_t`; the predicate line implies MA for both. One clarifying clause.
  - **N6.** The miss definition counts runtime auto-compaction as hard overflow; a task that auto-compacts and then completes inflates the miss rate even though the runtime self-defended. Conservative and acceptable — just pre-register how this case will be *interpreted*, or it becomes a post-hoc argument.

  ## Model identity

  Kimi (Moonshot AI), running via Kimi Code CLI with its default model routing; exact model version not disclosed by the runtime. Same seat as r1's kimi-k3.

