I'll start by reading the full review brief so the delta re-review covers the complete v0.3 design and EV-007 draft.Round-1 blocking items are mapped onto v0.3 as written; the verdict below is cumulative over the sentinel design and the EV-007 draft.

## Verdict

**GO-with-concerns**

The v1 mechanism is now unique enough to implement: one post-turn observable, one fire predicate, dual level threshold, TTFB as alert-only, split logs, tap exclusive-accounting. That was the r1 NO-GO bar, and it is met. Remaining holes are localized to EV-007’s frozen measurement rules (denominator, selection-rule identification, auto-enqueue handoff). Those must be one-line locked before the experiment is frozen / 決裁, not before Codex implements taps + predicate + nudge. They do not reopen D1–D4.

| r1 finding | Status | Evidence in v0.3 / EV-007 |
|---|---|---|
| **F1** (Grok r1#1) unique fire predicate; pre-send demoted | **RESOLVED** | §4 freezes `injected_t = input + cache_read + cache_creation` from `turn` only; `fire = level_fire OR slope_fire`; turn-1 MA / turn-2 slope degeneration stated; pre-send explicit v2 (`pre_send` tap) because listed sources are all post-turn. |
| **F2** (Grok r1#2) absolute threshold beside relative | **RESOLVED** | `T_abs=40k` OR `w×ctx_window`; 1M-window 112k/turn = 11% blind spot named; EV-007 sweep includes `T_abs ∈ {30k,40k,80k}`. |
| **F3** (Grok r1#5) EV-007 freeze | **PARTIALLY RESOLVED** | Miss/false-fire/hard-overflow written; 64k forced-overflow arm; per-model endpoints; B/C nested; qwen-on-claude-CLI arm; env freeze; depth-1 auto-enqueue cap. **Not closed:** (1) false-fire `トークン総量比` has no denominator; (2) sweep selection rule is not identified by the cells that will be run; (3) mid-task handoff contract was required for the auto-enqueue arm and is only a v2 roadmap sketch, not in §5 and not in EV-007. |
| **F4** (Grok r1#4) TTFB alert-only + #162 boundary | **RESOLVED** | §4-1: detect+log+alert, kill never, step timeout unchanged; unknown = longest floor 240s; SSE ping/keep-alive excluded from first byte; sentinel = live detect+alert, #162 = post-mortem classify+early DLQ, shared = byte tap only. |
| **F5** (Grok r1#3) fire/task_end split + cost counterfactual | **RESOLVED** | Separate `fire` / `task_end`; in-place append forbidden; `axis`, `nudge_disposition`, `tap_status`, `ctx_window_source`, `total_tokens` present; false-fire “not defined by completed”; ledger join is first candidate. Schema nits (`both`, `started_at`) are non-blocking. |
| **F6** (non-blocking r1, touched) | **RESOLVED** | Exclusive accounting + adapter normalization; `tap_status: no-cache-accounting\|absent`; compaction → MA/slope reset + pending nudge suppress; class prior = unknown-only; `schema_version`; `ctx_window_source` on the 4-step ladder. |

## New blocking findings

None. The defects below are either F3 residuals or one-line schema locks. They are not new preferences.

## Non-blocking findings

1. **§4 predicate should be one boolean, not a prose OR inside `threshold`.** As written, `level_fire = MA > threshold` and `threshold = injected絶対 T_abs または w×ctx_window` can be read as last-turn `injected` vs MA. Lock:

   `level_fire = (MA(injected,N) > T_abs) OR (MA(injected,N) > w * ctx_window)`

   `slope_fire = (Δinjected_fit > 0) AND (ctx_window - injected_last) / Δinjected_fit ≤ M`

   State the fit window (recommend last `min(n,N)` points, origin = last turn, compaction resets the series). Under OR, `w` is inert whenever `ctx_window ≥ T_abs/w` (≈80k at defaults). That is intended (F2: absolute catches 1M-window waste); say so, so implementers do not “fix” it back to `max`.

2. **False-fire denominator is not operational (F3 residual).** EV-007: fire ∧ bare twin has 「硬あふれ無し かつ トークン総量比 < 1.5x」. A ratio needs two operands. Everywhere else in these docs, トークン比 = treatment / bare. If that convention is applied here, the two EV-006 regimes invert:
   - sonnet savings TP (sentinel/bare ≈ 0.4, bare no overflow) → classified false-fire
   - codex damage FP (sentinel/bare ≈ 4–6x) → *not* classified false-fire
   Grammatically the subject is the bare twin, which suggests the intended reading is “bare was already healthy.” Freeze one line before 決裁, e.g.  
   **false-fire** iff sentinel fired on `{level,slope,both}` AND the bare twin had `hard_overflow=false` AND `bare_tokens / always-harness_tokens < 1.5`.  
   Do not use sentinel/bare in this predicate.

3. **副腕3 selection rule is not identified by the grid (F3 residual / new text).** Frozen rule: “codex 発火率0 を制約とし、その下で sonnet トークン比を最小化する (T_abs, w).” 副腕3 is sonnet-5 × 6 cells only; codex is measured only at the main-grid default (40k, 50%). You cannot evaluate the constraint at the candidates you would adopt. On a native ≥200k sonnet window, the w dimension is also dead under the OR predicate (finding 1). Before freeze: either cross `(T_abs,w) × {sonnet, codex}` or change the rule to “pick T_abs on sonnet; confirm fire-rate-0 on a codex confirmation cell at the chosen T_abs; drop w from the sweep (already the stated first cut).”

4. **EV-007 sentinel arm = auto-enqueue on, but handoff is undefined (F3 residual).** v1 product is nudge-only (§6). The experiment’s causal arm is “v1 + auto-enqueue 実験特例” with depth 1. Adjudication F3 required a mid-task handoff contract in §5; v0.3 only has a v2 roadmap bullet. Without it, sonnet token ratios are uninterpretable (restart sealed plan from step 1 vs resume; abort vs finish the firing turn; workspace artifacts persist or not). One paragraph in EV-007 is enough, aligned with §2 driver semantics: fire is post-turn so the expensive turn already completed; enqueue starts the sealed plan in a fresh context, depth 1, workspace files persist, no re-fire. Until that exists, do not treat EV-007 as frozen; the owner 未決 list can absorb it.

5. **`fire` event currently swallows TTFB alerts.** §4: alert is 別種. §6 `axis: level|slope|alert` and `decision: nudge|alert` put alerts on the fire event. Codex’s structural pass is 発火 0 回. If an implementer counts `fire` rows, a slow reasoning turn that only alerts fails the pass without a context-pressure fire. Lock EV-007 発火 := `axis ∈ {level, slope, both}`; emit a separate `alert` event (or keep TTFB fields only on `task_end` / attempt receipt). Add `both` to the enum (F5 freeze had it; v0.3 dropped it). `threshold_hit: abs|ratio` needs `both` as well.

6. **`started_at` still absent** from both event schemas (F5 list). `ts` on fire is not task start; TTFB math wants `ts_request_sent` from the byte tap plus `first_byte_at` on the attempt receipt (already required). Add `started_at` on `task_end` as the ledger join/duration key.

7. **副腕2 “C > B → v2 nudge target = orchestrator” is not a decision rule.** n = 2 seeds, no minimum effect size, mixed endpoints (completion + donecheck quality, descriptive). Any noise flips v2 architecture. Pre-register a floor (e.g. completion Δ ≥ 15pt on both models) or mark the cell as descriptive only — do not bind v2 to the sign of a 4-run difference.

8. **Reasoning floor table is referenced, not included.** v1 unknown = 240s is the conservative direction (F4). Either inline the named overrides or state “v1 table = token-bucket 90/150/240 only; any unnamed model including reasoning = 240s.” Alert-only, so this is documentation, not a kill-risk.

9. **Power / budget are already in 未決 — do not silently treat 68 as frozen.** Miss is valid only on 副腕1 (sentinel n = 2). Haiku ±10/15pt on n = 4 is a coin flip. That is an owner cut, not a reviewer redesign. Keep miss arm and B/C; the writer’s own cut order (w dimension → p2-L → qwen) is consistent with finding 1.

## Model identity

Grok 4.6 (xAI) — same seat as r1. Read-only, fresh context; r1 content taken only from the embedded adjudication.
