# Cross-Review Synthesis & Adjudication — harness design v0.1 → v0.2

> Namespace note: the R1–R15 in this file are harness v0.2 design-review resolutions —
> a separate series from the family adoption **governance** R1–R14 in
> [docs/governance-rules.md](../governance-rules.md). Never cross-reference by bare number.

Adjudicator: Alpha (Claude Fable 5), 2026-07-02
Inputs: [DESIGN.md](./DESIGN.md) (v0.1) + reviews/review-codex-clean.md (Codex gpt-5.5 xhigh) +
reviews/review-glm.md (GLM 5.2) + reviews/review-sonnet.md (Claude Sonnet 5)

## Verdicts
| Reviewer | Verdict | Sharpest contribution |
|---|---|---|
| Codex xhigh | APPROVE-WITH-CHANGES (10 blocking) | artifact bundle schema, verdict taxonomy, rubric gaming, skill-promotion criteria |
| GLM 5.2 | APPROVE-WITH-CHANGES (5 blocking) | Claire cron self-contradiction, n=1→General-rules category error, staging quarantine |
| Sonnet 5 | APPROVE-WITH-CHANGES (0 blocking, 4 major) | fresh-context unenforceability per adapter, cross-vendor mandate for Cero, dedup vs Alpha auto-memory |
| #148 raw review v0.2.1 | IMPLEMENTED | nightly/retroactive two-week raw-layer review; host-validated citations and K; append-only promotion outputs |

No REJECT. Core loop (files-as-interface, asymmetric adapters, verified-only gate)
unanimously endorsed. All blocking issues are specification gaps, not architecture flaws.

## Binding resolutions for v0.2 (adjudicated)

R1. **Claire nightly cron is NOT verify.** (unanimous) Rename to "nightly distillation
    audit"; it may draft skills and update Lessons/Open failures but may NOT promote
    skills nor write Verified facts. Real per-task verify for Claire = one-day
    feasibility spike on verifier agent binding; if impractical → Claire ships v0.1 as
    distill-only (adopting Codex/Sonnet's honest-relabel over GLM's full deferral,
    because distill-only still closes part of Claire's "no learning at all" gap).

R2. **Rubric anti-gaming.** Verifier receives {original request, rubric, artifact} and
    may return `rubric-invalid` before judging the artifact. Rubric minimum fields:
    objective, acceptance criteria, non-goals, evidence required, failure definition.

R3. **Verdict taxonomy**: pass | fail | inconclusive | rubric-invalid | needs-human |
    blocked-missing-artifact. (Codex #5)

R4. **N=3 terminal behavior**: artifact quarantined, entry → Open failures, task marked
    blocked, nothing promoted, CHECKPOINT still runs. Never silent-ship. (GLM #4)

R5. **n=1 category error fix**: single verify pass writes Lessons learned only.
    General rules / Verified facts require k≥2 independent passes OR explicit human
    promotion. (GLM #5 — adopted in full)

R6. **STATE.md concurrency**: single-writer rule. Cero: all STATE writes serialized
    through the agjob queue. Others: temp-file + atomic rename; parallel actors append
    to `loop/pending/` and one distiller folds. (Codex #2, GLM #3)

R7. **Fresh-context mechanization per adapter** (the invariant, now a seam):
    - Alpha: verifier = separate CLI process (glm/codex/claude -p), never same-session subagent.
    - Cero: verify job body = standalone one-file script, fresh process; agjob does
      scheduling only, NOT cross-model dispatch (GLM Q1 split adopted).
    - Claire: verifier agent binding with fresh session, input = artifact bundle only.
    Artifact bundle (minimal, file-based): result.md, rubric.md, file manifest/patch,
    evidence, metadata.json. Transcripts are NEVER artifact. (Codex #1/#4)

R8. **Cross-model policy**: fresh context mandatory everywhere; cross-VENDOR verifier
    mandatory only for Cero skill promotion (documented same-family bias #15204).
    Elsewhere cross-model is preferred, not required. (Sonnet #2 + Codex cut-list merged)

R9. **Cero skill flow**: DISTILL on Cero writes STATE.md ONLY. Skill creation stays
    native (auto_generate) but lands in `skills/_staging/`; promotion (move +
    `verified_at` stamp) only on verify pass. No second distillation path. (GLM #6/Q5)

R10. **STATE vs native memory precedence**: STATE.md = operational truth for task
     execution and overrides MEMORY.md there; MEMORY/SOUL/USER = episodic/persona
     context, untouched. Load order: bootstrap → STATE → skills. Disagreement →
     STATE wins operationally + conflict logged to Open failures. (Codex #8, Sonnet Q5)

R11. **STATE.md caps**: fact-section budgets remain Verified facts 120, General rules
     80, Open failures 100, and Lessons 60. Last session is a newest-first index capped
     at 20 entries: entry 1 carries the four restart fields plus a handoff pointer;
     entries 2..20 are pointers; the host appends older entries verbatim to the weekly
     archive before eviction. (Codex Q3 + Sonnet Q3 merged; #145)

R12. **Skill promotion criteria**: replace "≥5 tool calls" with "repeated OR
     high-friction workflow with stable trigger and reusable procedure", plus skill
     `status` field: draft | verified | deprecated | needs_reverify. (Codex #7)

R13. **Verifier outage**: hold the promotion queue; never degrade to self-critique.
     (GLM #9)

R14. **CHECKPOINT staleness**: session-end hook where available; on resume, if Last
     session date < newest activity → cold start, don't trust pointer. (GLM #8)

R15. **Alpha dedup**: Phase 0 must define migration — per-project STATE.md subsumes
     project README "現在地" section; auto-memory stays global-essentials only (matches
     existing 2026-06-16 context policy — no second overlapping state system). (Sonnet Q5)

## CUT from v0.1 (unanimous or 2/3)
- Phase 3 family sharing (revisit after Phase 1 data) — 3/3
- SKILL.md → OpenClaw YAML auto-derivation (manual + lint) — 3/3
- STATE.archive.md 30d aging + 60d skill lint (delete-on-overflow only) — 2/3
- Dual "5-stage" vocabulary (headers suffice) — GLM, accepted
- Free-window strategy moved from spec to rollout notes — Codex/GLM, accepted
- Broad model-routing table (v0.1 needs only maker/verifier/distiller) — Codex, accepted

## Q1–Q5 final answers
- Q1: agjob for scheduling; standalone fresh-process script as job body (GLM split).
- Q2: nightly = distillation-audit only, honestly named; per-task verify after 1-day spike (R1).
- Q3: 400 lines + per-section budgets (R11).
- Q4: manual derivation + consistency lint; automate v0.2+.
- Q5: duplications identified and removed via R9 (Cero) and R15 (Alpha).

## Remaining scope for v0.2 rewrite (Phase 0 implementation task)
Rewrite [DESIGN.md](./DESIGN.md) §3–§7 incorporating R1–R15; add artifact-bundle and rubric schemas as
appendix; add per-adapter "verifier launch" subsection. Estimated: 1 codex-worker task +
Alpha final review.
