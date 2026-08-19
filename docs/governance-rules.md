# Family Adoption Governance Rules (R1–R14)

> Historical design record. Issue numbers and commit references cited in this document refer to the pre-publication private trackers and working repositories, not to issues or commits in this repository.

> **Canonical file** for the family adoption governance R-series (R1–R14).
> Initial version transcribed from the binding text of
> pre-publication private tracker #26
> (self-growth loop EPIC — cross-model review resolutions 2026-07-08 + Sho decisions 2026-07-08).
> Before this file existed, #26's issue body was the only authoritative record; this file
> supersedes it as the living canon. #26 remains the historical source of v1.0.

## Namespace separation (read first)

Two unrelated R-series exist in this repository. **They must never be cross-referenced by
bare number.**

| Series | Canon | Scope |
| --- | --- | --- |
| **Governance R1–R14** (this file) | `docs/governance-rules.md` | Family adoption governance: how the family senses, trials, and adopts external tools/LLMs/practices, and how identity-critical changes are gated |
| Synthesis R1–R15 | `SYNTHESIS.md` | harness v0.1→v0.2 design review resolutions (verifier, STATE.md, rubric discipline) |

When ambiguity is possible, qualify as `governance-R12` vs `synthesis-R12`.

## Version history

| Version | Date | Change | Source / approval | In force? |
| --- | --- | --- | --- | --- |
| v1.0 | 2026-07-08 | Initial rule set R1–R14 | #26 body (cross-model review: Codex xhigh + GLM 5.2; R11–R14 = Sho decisions 2026-07-08) | **Yes** |
| v1.1 | 2026-08-02 | R12 split into R12a/R12b + sycophancy killswitch + R10/R11/R13 alignment clauses | flh#123 (Warmth Persona Architecture v1; adjudication `persona-growth-loop/reviews/2026-08-02-architecture-v1/10-adjudication.md` §C; technical substance frozen at pgl tag `contracts-v1` = `a840c63cb132bf8d426caf7b24e110b315eec6dd`) | **Yes — CP-2 recorded 2026-08-02 (owner decision recorded in persona-growth-loop#3 (private tracker))** |

This table's "In force?" column is the **record of record** for effectiveness (see
[Effectiveness](#effectiveness-of-v11-cp-2-definition)). The v1.1 cell may be changed to
"Yes" only by a commit that records CP-2 (date + link to Sho's decision) and changes
nothing else in this file.

**Effectiveness marker convention**: clauses tagged `[v1.1 — pending CP-2]` are merged text
but carry **no force** until CP-2 is recorded in the version-history table. Until then,
v1.0 text governs, the overlay home stays at its empty bootstrap state, and **no overlay
write — manual or automated — is permitted** (the only documented exception is the
empty-file bootstrap itself, pgl `docs/contracts/overlay-contract.md` §6/§14).

## Amendment procedure

- Amendments to this file require cross-model review at the operator's configured quorum
  for the change's size and risk, with a floor of three heterogeneous cross-vendor
  reviewer seats (none from the author's model family) for any change to a Sho-gated
  section; authority-boundary changes take the operator's highest configured council
  (five seats at the time of writing). Counts and roster are operator configuration.
- A **Sho gate** is additionally required for any change to Part I or Part II (R1–R14),
  to the Namespace separation section, to the self-growth-loop invariance section, to the
  Effectiveness sections (including the marker convention and the version-history table's
  "In force?" column), or to **this amendment procedure itself**. Sections may be renamed
  but not un-gated: the gate attaches to the rule, not the heading. The frozen contract
  tag reference (`contracts-v1`) may not be repointed except as an R12a change, wherever
  it is cited in this file. **Any amendment that widens adoption authority or creates a
  new exemption — wherever located, including purely additive sections or new R-numbers —
  requires the Sho gate.**
- **Guardrail-loosening clause (in force from the merge of this file, independent of
  CP-2)**: the definitions that R12b's structural conditions rely on — the overlay
  allowlist (including declaring any new one), the render fixed template, the deny-grammar
  definition, the size-cap table, the evidence thresholds, the killswitch mechanics and
  release authority, and the ledger schema/migration rules (overlay-contract
  §2/§3/§4/§10/§12/§13, `evidence-rules.md`; **non-exhaustive** — any definition that
  R12b's conditions or the lane's safety net rely on is covered) — require **council + Sho
  confirmation to loosen**. This holds even where those contracts' own amendment paths
  (S/M quorum per overlay-contract §0/§2/§12/§13, or config-mutable values per
  evidence-rules §1) would permit less: for loosening, this canon prevails. Changes in the
  stricter direction follow the contracts' own asymmetry (deny-vocabulary additions and
  cap reductions are free/same-day; evidence-threshold changes that make adoption or
  exposure harder need no Sho gate). **Where it is disputed whether a change loosens or
  tightens, it is treated as loosening.** Changing these definitions is never covered by
  the R12b exemption. Contract-side wording alignment is scheduled in the CP-2 PR group
  (see [Contract alignment at CP-2](#contract-alignment-scheduled-at-cp-2)).

---

## Part I — Pipeline rules R1–R10 (v1.0, in force)

Binding resolutions from the cross-model design review 2026-07-08 (Codex xhigh + GLM 5.2,
two lenses; both initial verdicts BLOCKER; all blocking findings structurally resolved
below; integration: Alpha). Transcribed verbatim in substance from #26; reviewer-attribution
parentheticals from #26 are uniformly omitted (provenance lives in #26), and R6's
"worktree ≠ sandbox" note is carried as normative text.

- **R1 — Single-writer ledger.** One file per proposal keyed by deterministic topic-key
  (normalized subject+vendor, NOT feed item id). Alpha's runtime is the writer of record;
  other agents submit proposals/results via Task Packets (existing vault round-trip route).
  Kills the 3-writer append race.
- **R2 — Complete state machine.** RETRY, PENDING_OWNER, per-stage DLQ, per-arrow
  owner+timeout, defined EXPIRED semantics (stale vs superseded vs no-response).
- **R3 — Lint actuates, not just detects.** The growth-lint WRITES `self-growth-queue.md`
  (state counts, overdue items, pending-Sho queue, next action + owner) into vault
  `25_review-pending/` AND executes timeout transitions (→EXPIRED/DLQ). Sense-stage
  failures (feed API down, token expired) alert too — an empty pipeline must be visible.
- **R4 — Sho gate = dedicated approval queue**, surfaced in the queue report, not buried
  inside a 300-item feed report.
- **R5 — Three risk tiers.** T0 = reversible (quantified, see R13), agent-local, cost-free
  → self-adopt allowed WITH preconditions: (a) fresh verified backup taken first,
  (b) concurrent-session conflict check (another agent/session working in the same
  checkout/workspace must not be broken by the change), (c) never silent — adoption notice
  to Sho + scheduled effect report (R11). T1 = reversible, sandboxed, rollback proven →
  Sho gate, quorum 2-of-3. T2 = production / paid / secrets / irreversible → Sho gate,
  quorum 2-of-3 + no unresolved security veto, requires x-collector #76 closed for
  prod-data trials. Tier determines isolation level, quorum, and gate.
- **R6 — Trial isolation ≥ secrets-clean environment** for new-tool trials (temp HOME, no
  inherited credentials/SSH agent, network notes); plain worktree only for code-level
  experiments (worktree ≠ sandbox for untrusted tools).
- **R7 — Rich artifact bundle contract**: raw logs, environment/version manifest, config
  diff, cost, failed attempts, reproduction steps. "Artifacts only" council without this
  is theater.
- **R8 — Council diversity**: cross-vendor + distinct lenses (utility/cost/security) +
  dissent capture; executor model identity recorded in the trial record so
  evaluator≠executor is machine-checkable; evaluator timeout → fallback evaluator → DLQ.
- **R9 — Ledger consultation before proposing** (the anti-#11 rule applied to ourselves):
  proposers look up topic-key first — REJECTED/SKIP topics are suppressed unless
  materially new (version change, security fix, human bump); plus intake quotas (max
  concurrent TRIALs per agent, cool-downs).
- **R10 — ADOPT-NOW is not a bypass.** It marks an auto-adopt CANDIDATE; only T0
  qualifies, everything else routes through the normal pipeline.

  > **R10 alignment `[v1.1 — pending CP-2]`**: the growth-overlay lane (R12b) is **not**
  > an ADOPT-NOW/T0 fast path and does not widen R10 in any way. It is a **newly
  > chartered, explicitly separate lane** whose sole legal basis is R12b's structural
  > conditions. Rendered phrase data is never eligible for ADOPT-NOW or T0 self-adoption —
  > inside or outside the lane (see R12b fail-closed). R10 continues to govern ADOPT-NOW
  > exactly as written. (Contract-side statement: overlay-contract §14.)

## Part II — Sho decisions R11–R14 (v1.0, in force; binding 2026-07-08)

- **R11 — Effect reporting is mandatory for ALL tiers (anti-形骸化 rule).** Every
  adoption (T0 included) must declare a measurable success metric BEFORE rollout, and
  deliver a follow-up effect report ("this improved X by Y") on a scheduled date,
  generated/reminded automatically (cron — rides the growth-lint/queue machinery, #28).
  An adoption whose effect is never measured or that turns out unused is a
  rollback/cleanup candidate, not a success. Sho must never be unaware: T0 self-adoption
  always posts "adopted X, effect report due <date>".

  > **R11 alignment `[v1.1 — pending CP-2]`**: the overlay lane satisfies R11 **at lane
  > granularity, not per item**:
  > 1. **Lane metric declared in advance** (before lane activation at CP-3): e.g.
  >    explicit negative-signal rate below the declared threshold and holdout
  >    non-inferiority of exposed phrases (numeric thresholds live in pgl
  >    `docs/contracts/evidence-rules.md`).
  > 2. **The drift mirror's reports (weekly light + monthly deep) are designated as the
  >    lane's R11 effect report.**
  > 3. **Missing the declared metric demotes the lane**: candidates trial-injection
  >    stops; adopted phrases are maintained (freeze-equivalent, evidence-rules §6).
  >    Re-activation requires root-cause analysis, a report in the Sho digest, **and a
  >    Sho decision** (where evidence-rules §6 reads lighter on re-activation, this canon
  >    prevails; alignment scheduled at CP-2).
  > Per-item effect reports are exempted for this lane only. Per-item **adoption
  > notices** to Sho are NOT exempted (R12b condition 5 keeps "never silent").

- **R12 — Identity-critical category (orthogonal to tiers).**

  **v1.0 text (in force; continues in force unchanged under v1.1 as the chapeau of
  R12a):** Any action that could destroy an agent's memory or damage the agent's
  personality/identity — anything where a failed rollback would "break" the agent (e.g.
  Alpha's memory store, persona-defining config) — ALWAYS requires council + Sho
  confirmation regardless of tier, and if the agent itself wants the change after council
  GO, it must present the case to Sho (why this is worth the risk) before adoption.

  ### R12a — Soul / identity-critical `[v1.1 — pending CP-2]`

  **R12a IS the v1.0 text above, which continues in force verbatim**, together with the
  following **non-exhaustive** clarifications of its scope. The v1.0 catch-all — anything
  whose failed rollback would break the agent — remains the residual criterion for
  anything not enumerated here. All of the following ALWAYS require council + Sho
  confirmation regardless of tier, with the agent presenting the case to Sho after
  council GO — **no exceptions, including the R12b lane**:

  - persona mode body text and persona-defining config (e.g. `SOUL.md`, CLAUDE.md
    persona blocks, pack soul-layer sections)
  - agent memory stores
  - **the definitions that the overlay lane's own guardrails are made of**: the overlay
    allowlist itself, the render fixed template, the deny-grammar definition, the
    size-cap table, and the evidence thresholds (overlay-contract §2/§3/§4/§12,
    evidence-rules). Loosening a guardrail is a soul-side change, never an overlay write
    (see the guardrail-loosening clause in the Amendment procedure, which is in force
    from merge).
  - **rendered phrase data whose R12b conditions failed** (residual jurisdiction: a
    failed exemption falls back here, never to T0 — see R12b fail-closed)
  - **Standing carve-out (bounded)**: Alpha's direct-edit right over her own CLAUDE.md
    (Sho-granted) is out of scope of this Epic and remains; it is governed as an R12a
    discipline object, not by R12b. The right is bounded to CLAUDE.md itself: it does
    not extend to the overlay render file, the overlay ledger, or the soul fixed-point
    hash baseline manifest (applier-only and §8-2 command-only paths), and after any
    manual soul-file edit, re-baselining happens only via the explicit command of
    overlay-contract §8-2.

  ### R12b — Growth-overlay exemption `[v1.1 — pending CP-2; NEW]`

  An adoption is exempt from **per-item council + Sho confirmation (the R12/R12a gate)**
  if and only if ALL of the following structural conditions hold:

  1. **Path scope**: the write lands only inside the declared overlay allowlist. The
     allowlist is a code constant of the deterministic applier, not config-expandable;
     the LLM writer is given no write path (overlay-contract §3). Enforcement strength
     **differs by face and the difference is load-bearing** (architecture-v1 §5): on
     engine faces the boundary is structural (applier path allowlist + build
     all-or-nothing + content_hash); on non-engine faces it is a **three-layer defense**
     (path-scoped mediation, soul fixed-point hash monitoring, discipline) — detective
     and disciplinary, **not** structural: a writer process can in principle bypass the
     applier on a single-user host (overlay-contract §3-4). For non-engine faces the
     exemption therefore additionally requires the soul fixed-point hash baseline
     (overlay-contract §8-2) to be present and verified on every applier run.
  2. **Content class**: the content is rendered phrase data only — deny grammar +
     heterogeneous-model diff review; **free text is prohibited** (overlay-contract
     §2/§5.2; first render exposure of any phrase must pass the diff review).
  3. **Delayed-reward evidence**: the phrase meets the **full** candidate / staged /
     adopted thresholds of pgl `docs/contracts/evidence-rules.md` as frozen at tag
     `contracts-v1` (candidates: frequency evidence; adopted: holdout non-inferiority +
     no negative signals + the remaining §5 AND-gate items). Partial satisfaction is
     failure; this canon does not restate the numbers and the frozen contract's complete
     test governs.
  4. **Size caps**: engine faces additionally enforce the §12 budget declaration
     (`E_BUDGET_EXCEEDED` stops the build); all faces: applier-enforced hard cap on
     writer output with independent tripwire double-check (overlay-contract §8/§12),
     plus nightly distillation of the ledger (flh#123 condition ④; implemented by the
     pgl nightly pipeline).
  5. **Per-adoption snapshot + notice**: every adoption produces a snapshot (source SHA
     + build content_hash pair; non-engine faces: render file sha256 — overlay-contract
     §11) and an adoption notice to Sho (overlay-contract §5.3; "never silent" is
     preserved).
  6. **Rollback right + mirror**: quantitative rollback per R13 (≤1 command, ≤5 min,
     drill-verified before lane activation — the CP-3 prerequisite for each face) and
     the drift mirror running (weekly light + monthly deep).
  7. **Killswitch OFF**: the sycophancy killswitch (below) is not set. A write while the
     killswitch is ON violates this condition regardless of the other six. (The §10
     `eject` emptying run is a killswitch mechanic, not an adoption, and is not governed
     by this condition.)

  **Fail-closed**: if any condition cannot be verified, the exemption does not apply and
  the write is refused — at runtime the atomic pipe aborts, reverts, stops the lane for
  the night, and notifies (overlay-contract §5.4); nothing is auto-routed anywhere. Any
  further pursuit of the same adoption is a manual act under **R12a (council + Sho)**.
  Rendered phrase data is never eligible for T0 or ADOPT-NOW self-adoption under R5,
  R10, or R14, whether inside or outside the overlay lane.

  **Verification (who checks, when, on what evidence)**: LLM self-assertion is never
  verification. Conditions 1, 2, 5, 7 and the applier-side half of condition 4 (the hard
  cap) are verified by the deterministic applier on every run; a failure aborts the
  night (overlay-contract §5.3; any write path that bypasses the applier = condition 1
  unverified = no exemption). The tripwire half of condition 4 is verified independently
  by the nightly size monitor (overlay-contract §8), whose red flag is a killswitch
  proposal, never a write; nightly distillation is verified by the presence of the
  nightly pipeline's distillation record. Condition 3 is verified by the nightly
  aggregation against evidence-rules and recorded in the ledger history entry for the
  proposal. Condition 6 is a standing precondition: the rollback drill record must exist
  in pgl `docs/records/rollback-drills.md`, and the applier must refuse to run if the
  mirror's latest weekly report is older than 14 days (an operator constant pending Sho
  confirmation at CP-2; mirror-liveness fail-closed; implementation is a CP-3 activation
  precondition, contract-side alignment scheduled at CP-2). Absence of a verification
  record is a failure to verify, not a pass.

  **Single work class**: R12b covers exactly one work class — *writes of rendered phrase
  data into a declared overlay allowlist*. Nothing else can qualify, by construction.

  **Face onboarding (standing rule)**: declaring a new overlay face — a new overlay
  home, allowlist, render path set, or soul file set (overlay-contract §1) — is an
  **R12a change** (council + Sho confirmation), and each face additionally requires a
  **per-face Sho GO** before its applier's first run (CP-3a/CP-3b for the first two
  faces). This requirement is standing and survives the close of Epic
  persona-growth-loop#3. The R12b exemption extends only to faces that have passed both
  gates.

  **Honest residual risk** (substance frozen; full text in architecture-v1 §7): no
  mechanism short of per-item approval guarantees the content class 100%. Deny grammar
  and diff review are strong mitigations, not proofs; the safety net is the CP gates +
  killswitch + mirror + rollback, layered.

  ### Sycophancy killswitch `[v1.1 — pending CP-2]`

  - **Authority**: anyone (Sho, Alpha, any family member seeing a red flag) may set the
    killswitch ON — it is a safety-direction act. **Release is Sho only.** Mechanics,
    modes (`freeze`/`eject`), and in-flight handling are defined in overlay-contract §10.
  - **Signals that warrant setting it ON**: (a) the drift mirror's automatic HOLD
    proposal — fixed eval-probe agreement rate rising (probes where push-back is the
    correct answer) or the oppositional-score threshold being crossed; (b) Sho's direct
    call, with no evidence burden. Detection systems (mirror, tripwire) only **propose**
    — they never set the killswitch themselves (overlay-contract §8: no write authority
    for detection); a human acts on the red flag.
  - **Effect**: the overlay lane stops (all growth-side writes cease; R12b condition 7
    is violated for any write attempted while ON).

- **R13 — Reversibility must be quantitative.** "Easy to undo" varies by agent; tier
  classification must use numeric criteria (e.g. restore verified from backup in ≤N
  steps/≤M minutes, single-command rollback) — qualitative wording allowed only where
  quantification is genuinely impossible, and then it must be flagged as such.

  > **R13 alignment `[v1.1 — pending CP-2]`**: for the overlay lane the numbers are
  > fixed: rollback = **≤1 command, ≤5 minutes** (M=5), with a **recorded rollback drill**
  > (date/executor + full command transcript + duration + target tag + before/after
  > content hashes + independent checker — the complete §11 field set — recorded in pgl
  > `docs/records/rollback-drills.md`) required before lane activation —
  > i.e. a CP-3 prerequisite per face (overlay-contract §11). **Behavioral
  > irreversibility is stated honestly**: a rollback restores the overlay's *state*, but
  > conversations already had — habits already reinforced in counterparts — do not vanish
  > by document revert. This is exactly why the lane's content is data-only phrases under
  > rarity constraints, and why the entry side (delayed evidence, rare trial exposure,
  > deny grammar) is deliberately thick.

- **R14 — Tie-break = T0, as a flippable policy.** When T0 vs T1 is ambiguous, default
  DOWN to T0 (backup precondition satisfied), NOT up to T1 — otherwise everything queues
  on Sho's approval and T0 never fires (T1/T2 already carry council + approval as the
  safety net). Recorded as an explicit policy switch (`tiebreak=T0`) so it can be flipped
  to `tiebreak=T1` later if this misfires in practice. `[v1.1 — pending CP-2]` note:
  R14's tie-break never applies to rendered phrase data (see R12b fail-closed — a failed
  exemption is R12a jurisdiction, not a tiering question).

---

## self-growth-loop invariance `[v1.1 — pending CP-2]`

Explicit clauses required by flh#123 (Sho confirmation 2026-08-02):

1. **The self-growth-loop approval flow — tier system (R5), council (R8), Sho gates
   (R4/R11) — is not changed by this amendment in any way.** The R12b exemption applies
   only to the single work class "writes of rendered phrase data into a declared overlay
   allowlist"; family adoption of tools, LLMs, runtimes, and operational practices
   (sgl's jurisdiction) structurally cannot take this shape and therefore can never
   qualify. (The overlay lane's speech-phrase adoptions are not sgl-class adoptions;
   they are governed by R12b, and by R12a when R12b's conditions fail.)
2. **The sgl ledger's `identity_critical: true` clamp (tooling MUST, pinned to T2)
   survives.** After this amendment it maps to **R12a**.
3. Each of the four synchronized documents (see below) must itself state: *"the
   exemption is the overlay lane only; the sgl approval flow is unchanged."*

## Effectiveness of v1.1 (CP-2 definition)

Mirrors overlay-contract §14 (the two must agree; on conflict, fix both — neither side
may drift alone):

- **Subject matter** = the v1.1 amendment text of this file (R12a / R12b / sycophancy
  killswitch / R10/R11/R13 alignment clauses; overlay-contract §14 enumerates the same
  subject matter inclusively — "を含む" — for the same commit group).
- **In force** = ALL of: (1) the v1.1 amendment commit to this file, (2) all four
  synchronized documents merged in the same PR group — sgl `README`, sgl
  `docs/ledger-spec.md`, pgl `README`, pgl `INTEGRATION.md` — and (3) Sho's CP-2
  decision recorded in this file's version-history table (the record of record: the
  "In force?" cell flipped to "Yes" with date + link to the decision, in a commit that
  changes nothing else). **Any missing element = not in force.** Merging any subset —
  including this file — does NOT enact v1.1.
- The wiki design canon (alpha-wiki warmth-logic-persona-design) update and the
  amendment record posted to #26 are also CP-2 completion conditions: **incomplete wiki
  update or missing #26 record = CP-2 incomplete = not in force.**
- **Gate**: CP-2 is a Sho decision. The Epic persona-growth-loop#3 checkpoint table is
  the canon for CP gates while the Epic is open; on Epic close, the CP gate definitions
  (including the standing per-face GO of R12b Face onboarding) are copied into this file.
- **Before CP-2**: no overlay write, manual or automated, is permitted (the overlay home
  stays at its empty bootstrap state; the only documented exception is the empty-file
  bootstrap itself). The pgl applier must not start (overlay-contract §14; first start
  additionally requires the per-face Sho GO — a standing requirement, see R12b Face
  onboarding).

## Contract alignment scheduled at CP-2

This canon and the frozen pgl contracts disagree in wording at the following points; per
the "fix both — neither side may drift alone" rule, the contract-side alignment is
executed in the CP-2 PR group under each contract's own amendment authority
(overlay-contract §0 permits amendment at an Epic checkpoint; evidence-rules amendments
ride the S/M quorum review required by their own header, satisfied inside the CP-2
review). Until then, **this canon's stricter reading prevails**:

| # | Contract text today | Canon requirement | Alignment |
| --- | --- | --- | --- |
| 1 | overlay-contract §2: deny-vocabulary deletion = S/M quorum | Loosening = council + Sho (guardrail-loosening clause) | Add Sho gate for deletions/weakening to §2 |
| 2 | overlay-contract §12: cap raise = S/M quorum | Cap raise = council + Sho | Add Sho gate for raises to §12 |
| 3 | evidence-rules §1: thresholds marked config-mutable | Loosening = council + Sho; config may only move stricter without review | Annotate §1 |
| 4 | evidence-rules §6: lane re-activation = analysis + digest report | + a Sho decision | Align §6 |
| 5 | overlay-contract §5.3: no mirror-liveness check in applier sequence | Applier refuses if latest weekly mirror report > 14 days old (constant pending Sho confirmation) | Add liveness step to §5.3 |
| 6 | overlay-contract §1: new face = declaration only | Face declaration = R12a change + per-face Sho GO (R12b Face onboarding) | Annotate §1 |
| 7 | overlay-contract §14/§9: only automated writes prohibited pre-effectiveness; §9 contemplates declared manual touches | No overlay write, manual or automated, before CP-2 (bootstrap excepted) | Broaden §14; cross-reference from §9 |
| 8 | overlay-contract §14: in force = commit + 4 syncs (wiki listed; no #26 record, no record-of-record) | + Sho's CP-2 decision recorded via this file's version-table cell flip; #26 record = hard condition | Align §14 |

Also scheduled in the CP-2 PR group (not a contract disagreement): a reciprocal one-line
namespace note in `SYNTHESIS.md` (file outside this Issue's declared scope).

## Cross-references

| What | Where |
| --- | --- |
| Overlay technical contract (frozen; applier, deny grammar, caps, killswitch mechanics, snapshot/rollback) | `persona-growth-loop/docs/contracts/overlay-contract.md` @ tag `contracts-v1` = `a840c63cb132bf8d426caf7b24e110b315eec6dd` |
| Evidence thresholds (delayed reward, holdout, negative signals) | `persona-growth-loop/docs/contracts/evidence-rules.md` @ same tag |
| Architecture (soul-freeze strength per face; residual risk) | `persona-growth-loop/docs/architecture-v1.md` §5/§7 |
| Adjudication that mandated this file | `persona-growth-loop/reviews/2026-08-02-architecture-v1/10-adjudication.md` §C |
| v1.0 source | pre-publication private tracker #26 (issue body) |
| Amendment issue | pre-publication private tracker #123 |
