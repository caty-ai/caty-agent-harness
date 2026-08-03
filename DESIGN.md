# fable-loop v0.2 — Minimal Self-Improving Loop Harness for OpenClaw & Hermes Agent

Status: v0.2 — cross-review resolutions R1–R15 (SYNTHESIS.md) applied.
Amended 2026-07-18: §10 cross-cutting contracts (grok-build study, #43 → #49).
Amended 2026-07-24: P1 implementation roll-up (#74–#84) and related CHECKPOINT
documentation drift (tracked by #107).
Author: Alpha (Claude Fable 5), 2026-07-02.
Review lineage: v0.1 → Codex gpt-5.5 xhigh / GLM 5.2 / Claude Sonnet 5 (all
APPROVE-WITH-CHANGES) → adjudication in SYNTHESIS.md → this rewrite.

## 0. TL;DR

The "Fable 5 self-improving agent" pattern is harness engineering, not model magic:
file-based operational memory (STATE.md), an independent fresh-context verifier, and
verified-only skills distillation. This design ports it asymmetrically onto three
runtimes: Claude Code / Alpha (reference), Hermes Agent / Cero (has a native learning
loop but documented self-evaluation bias — add verification discipline only), and
OpenClaw / Claire (no persistent learning — add a distillation loop, honestly scoped).

Design creed: **files as the only interface. No additional persistence substrate beyond
runtime-native job/state files. Thin adapters. Every promotion gated by verification.**

## 1. Evidence base (verified 2026-07-02)

- Verifier sub-agent outperforms self-critique with Fable 5 (~6x pipeline improvement vs
  Opus 4.7 self-critique on Parameter Golf; Anthropic engineering reports).
- STATE.md five-section pattern; Fable 5 reaches ~73% verification coverage vs ~17%
  Opus 4.7 baseline on Continual Learning Bench.
- SKILL.md is emerging as a harness-neutral procedural-knowledge format (Claude Code,
  ClawHub, Hermes near-variants).
- The loop compounds regardless of orchestrator model; assets persist across model
  transitions. (Fable 5 free-window seeding: see Rollout notes, §9 — deliberately kept
  out of the core spec.)

## 2. Local ground truth (family-vault survey, 2026-07-02)

| | OpenClaw (Claire, VPS `<home>/.openclaw-claire/`) | Hermes Agent (Cero, VPS `<home>/.hermes/profiles/cero/`) |
|---|---|---|
| Philosophy | Gateway-first, broad reactive tool chaining | Learning-first: auto-skill generation, persistent user model |
| Memory | Session-based only | SOUL/MEMORY/USER.md + Supermemory provider |
| Skills | Human-curated YAML claims (ClawHub) | Native auto_generate + background quality agent |
| Known gap | **No learning loop at all** | **Self-evaluation bias** (issue #15204) |
| Job state | None durable (agjob pilot in progress) | agjob ledger pilot: jobs/heartbeats/DLQ |

The harness is therefore **asymmetric**: Claire gets a distillation loop; Cero gets only
the missing verification discipline; neither runtime's native machinery is duplicated.

## 3. Core spec — LOOP protocol v0.2 (runtime-neutral)

### 3.1 Files (per agent workspace)

```
<workspace>/
  STATE.md            # operational truth; per-section caps (§3.6)
  skills/             # promoted skills only (status: verified)
    _staging/         # unpromoted drafts; never auto-loaded at CONSULT
  loop/
    RUBRIC.tmpl.md    # rubric template with required fields (§3.2, Appendix B)
    VERIFY.log.md     # append-only verifier verdict log
    pending/          # host-staged, unverified candidates from parallel actors (§3.4)
    artifacts/        # artifact bundles per task (Appendix A), quarantine lives here
```

STATE.md sections (fixed order, machine-locatable by `## ` headers):

```markdown
## Verified facts      (cap 120 lines)
## General rules       (cap 80)
## Open failures       (cap 100)
## Lessons learned     (cap 60)
## Last session        (cap 20 — restricted to: task id, next action, blockers,
                        last verified artifact path)
```

Every entry: one fact per bullet, absolute date (YYYY-MM-DD), provenance (source task or
job id, and verifier id if verified). Entries may carry `invalidated-by:` pointers —
a later entry can invalidate an earlier one without history rewriting (§3.3).

### 3.2 The loop (per task)

A **task** is the runtime's native unit of dispatched work: a user request or job in
Claude Code, an agjob job in Hermes, a dispatched skill invocation or operator request
in OpenClaw. Reactive sub-steps inside one dispatch are not separate tasks.

```
CONSULT     read STATE.md + trigger-matching promoted skills at task start.
PLAN        fill rubric from RUBRIC.tmpl.md BEFORE acting. Required fields: objective,
            acceptance criteria, non-goals, evidence required, failure definition.
ACT         maker executes; maker sees its own reasoning. Maker assembles the artifact
            bundle (Appendix A) as it works.
VERIFY      independent fresh-context verifier receives {original request, rubric,
            artifact bundle} — never the maker's session context or reasoning trail.
            The verifier MAY return rubric-invalid without judging the artifact
            (anti-goalpost authority: a rubric that does not cover the actual request
            fails first). Verdicts (R3):
              pass | fail | inconclusive | rubric-invalid | needs-human |
              blocked-missing-artifact
            fail/rubric-invalid → back to PLAN/ACT, at most N=3 total attempts.
            On N=3 without pass (R4): artifact bundle moved to loop/artifacts/ as
            quarantined, one entry written to Open failures, task marked blocked,
            nothing promoted. CHECKPOINT still runs. Never silent-ship.
VERIFY.log  every verdict appended: UTC timestamp, task id, verifier id (model+vendor),
            verdict, one-line reason.
DISTILL     on pass: candidate observations appended to loop/pending/ (or STATE.md
            directly if this actor is the single writer, §3.4). Promotion rules: §3.3.
CHECKPOINT  rewrite "## Last session" (restricted fields only). Non-negotiable; enforced
            by a session-end hook where the runtime has one (§4). On next CONSULT, if
            Last session is older than the newest entry in VERIFY.log.md → treat as
            cold start and do not trust the pointer (R14).
```

For task-runner-managed tasks, CONSULT also renders a deterministic index of promoted
skill directories. Each entry contains the skill directory's absolute path and its
regular-file names only (including nested relative names), never file contents.
`skills/_staging/` and symlinked directories or files are excluded.

Verifier independence is a **seam, not a policy** (R7): each adapter must specify how
the verifier process is launched, what context is excluded, and how transcript leakage
is prevented. Transcripts are never part of an artifact bundle. Fresh context is
mandatory everywhere; cross-model is preferred; cross-VENDOR is mandatory only where
§4 says so (R8). If no verifier is reachable (provider outage), the promotion queue
holds; the loop never degrades to self-critique (R13).

Retry MUST differ (2026-07-22, #73): when a task loops back to PLAN/ACT after a non-pass, the next attempt's prompt must include the prior failure's error_class plus a one-line summary and a short recovery instruction; byte-identical retry prompts are forbidden. This changes prompt rendering only — the 2-consecutive-identical-error DLQ rule is unchanged.

VERIFY output contract (2026-07-22, #73): verifier output is findings-first — defects before praise, severity-ordered, each with file:line and a one-line reason; zero findings requires an explicit no-findings declaration plus residual risks; an interrupted or partial verification is never pass. The VERIFY.log one-line reason carries the top finding (file:line) or the no-findings declaration.

Task-runner budget rendering (2026-07-23, #74): every normal STEP prompt renders
attempts and active-time used from scheduler state, their budgets from task front
matter, and the computed remaining values. The prompt renders a wind-down block on the
final attempt or when no more than 20% of the active-time budget remains: start no new
work, summarize progress, and leave an exact next step. This changes maker guidance
only; terminal classification and driver authority remain unchanged. The pre-existing
degraded no-template fallback does not render this block.

### 3.3 Promotion rules (anti-slop gates)

- A single verify pass certifies task completion at n=1, nothing more (R5). It may
  write **Lessons learned** only.
- **General rules** and **Verified facts** require k≥2 independent verify passes of the
  same lesson (different tasks) OR explicit human promotion. The k-count lives with the
  Lessons entry (`confirmations: 1`).
- OpenClaw distillation records use a host-computed
  `dedup_key = task_id:lesson_hash`, where the task id identifies the sorted input batch
  and the lesson hash covers the whitespace-normalized dated candidate bullet, including
  its source marker. Under the STATE lock, the host rejects composite keys already seen
  in pending records or the current batch and rejects exact candidate lines already in
  STATE or the current batch. Keys from an atomically replaced same-day pending record
  are carried forward. Model-supplied keys are discarded and recomputed.
- **Skills**: promotion criterion is "repeated or high-friction workflow with a stable
  trigger and a reusable procedure" (R12) — tool-call counts are not a criterion.
  Skill frontmatter: `name, description, trigger (deterministic: keyword list or glob),
  status (draft | verified | deprecated | needs_reverify), verified_at (UTC),
  verifier_id`. Drafts live in `skills/_staging/` and are never loaded at CONSULT.
  If two promoted skills match one task, the more specific trigger wins; tie → most
  recent `verified_at`; the collision is logged to Open failures for human review.
- OpenClaw distillation skill drafts may declare `source_task_id`, `target_skill`, and
  `files_created`. When present, the host checks `source_task_id` against either the full
  selected input path or its basename, requires `target_skill` to equal the draft name,
  and accepts only non-empty workspace-relative paths that resolve to regular files. Any
  mismatch rejects that draft and creates a dated Open failures entry; it never silently
  promotes. Omitted declaration fields preserve the legacy draft path.
- **Rollback**: a wrong fact/rule/skill is never edited away silently — it gets
  `status: deprecated` or an `invalidated-by:` pointer plus an Open failures entry
  explaining what the verifier missed.

### 3.4 Concurrency (single-writer rule, R6)

- Exactly one actor per workspace may rewrite STATE.md ("the distiller").
- On Cero, all STATE.md writes are serialized through the agjob queue.
- All rewrites: write temp file → atomic rename. Parallel actors (background agents,
  verifier jobs, cron) never touch STATE.md. A trusted verifier host may append its
  verdict to `loop/VERIFY.log.md`; OpenClaw model-derived distillation output is staged
  under `loop/pending/`, which the trusted single-writer host validates and folds.
- `VERIFY.log.md` is append-only verifier history: the harness neither rewrites
  existing verdict entries nor implements retention or pruning. Any future bounded
  lifecycle requires an evidence-based retention policy and a separate loss-safe design.
- OpenClaw retrospective distillation treats an empty result as correct when the inputs
  contain no durable learning. Its model prompt forbids invented observations, requires
  each emitted observation to be worded as `success`, `partial`, `fail`, or `uncertain`,
  gives verified evidence priority over heuristic inference, and maps missing evidence
  to `uncertain`; these semantic labels are prompt requirements, not host validation.

### 3.5 Precedence vs native memory (R10)

STATE.md is **operational truth** ("what is true / what failed / where to resume") and
overrides native memory for task execution. Native memory (MEMORY/SOUL/USER, Supermemory,
auto-memory) remains episodic/persona/user context and is untouched by this harness.
Instruction precedence is:
**user request > runtime safety > loop gates > instruction files > bootstrap > STATE >
skill**. Within the loop-controlled tail, CONSULT loads bootstrap → STATE.md → promoted
skills. If STATE.md and native memory disagree on an operational fact, STATE.md wins for
the task and the conflict is logged to Open failures. `install.sh --check` warns about
duplicate bootstrap markers and instruction files over 200 lines (or the configured
limit); these lint findings are diagnostic and do not change existing fatal check
semantics.

### 3.6 STATE.md hygiene

Per-section line caps as in §3.1 (protects "Last session" from crowd-out). On overflow
of a section: delete resolved/stale entries of that section, oldest first. That is all —
no archive file, no time-windowed aging in v0.1 (cut per review; revisit in v0.2+ if
deletion proves lossy). Caps count rendered lines including code blocks.

### 3.7 Resume convention (v0.3 note)

An interrupted task resumes from a fresh session by reading three existing sources, in
order. First: the task's artifact bundle (Appendix A layout), accepting whatever files
exist so far. Second: the `## Last session` pointer in STATE.md: task id, next action,
blockers, and last verified artifact path only, per the §3.1 cap. Third, on Cero only:
the job's `claimed` entry in the agjob ledger. Resume on Cero means re-claim from that
ledger; staged commands live in the job payload, not in a new sidecar file. This
convention introduces no new persistence substrate. It is only a reading order over the
artifact bundle, STATE.md pointer, and runtime-native ledger entry.

## 4. Adapters (thin by design; each specifies its verifier launch seam)

The [shared adapter runtime contract](adapters/CONTRACT.md) is the single normative
home for blank-tool-call recovery, untrusted verifier/distiller fork isolation, and
verifier-bundle assembly for Claude Code, Hermes, and OpenClaw. Adapter-specific guides
define wiring only and must not weaken or contradict that contract. The same contract
now also defines the machine-checked wrapper conformance gate: exact single-path
wrapper config, strict fresh evidence, wrapper/provider/probe hash binding, staged
wrapper/provider execution, and read-only `install.sh --check` conformance diagnostics.

### 4.1 Claude Code / Alpha — reference implementation (Phase 0)

- Files: `STATE.md` per project dir via a `loop-init` script.
- **Migration/dedup (R15)**: per-project STATE.md subsumes the README "現在地" section
  (README keeps orientation + pointers); global auto-memory stays essentials-only per
  the existing 2026-06-16 context policy. One state system per scope — no parallel
  duplicates.
- **Verifier launch seam**: a separate CLI wrapper process, invoked through one
  absolute wrapper path with fresh conformance evidence and passed the artifact bundle
  content only. Never a same-session subagent (it would inherit conversation history
  and break the invariant).
- CHECKPOINT enforcement: when workspace files are newer than STATE.md, the Stop hook
  blocks and creates a session guard. It does not block again while that guard exists;
  guards older than two days are pruned, so a long session can re-arm. Environment
  errors fail open.
- Purpose: validate the spec on the cheapest runtime before touching the VPS.

### 4.2 Hermes Agent / Cero (Phase 1 — highest value)

- Files: `STATE.md` in the cero workspace + a ~10-line bootstrap block stating
  CONSULT/CHECKPOINT, load order, and §3.5 precedence. SOUL/MEMORY/USER untouched.
- **Verifier launch seam**: agjob provides **scheduling only** (queue, heartbeats,
  retries, DLQ). The job body is a standalone one-file script that runs in a fresh
  process, validates wrapper conformance, stages the wrapper and provider copies, and
  calls the verifier through those staged paths. agjob is NOT extended to do
  cross-model dispatch (wrong seam for a pilot).
- **Cross-vendor mandate (R8)**: verifiers gating skill promotion on Cero must be a
  different vendor than the maker (documented same-family bias, issue #15204).
- **Skill flow (R9)**: native auto_generate keeps creating skills, but they land in
  `skills/_staging/`; promotion only on verify pass. DISTILL on Cero writes STATE.md
  only — this harness adds no second skill-authoring path.
- DLQ entries feed "Open failures". STATE writes serialized via the agjob queue (§3.4).

### 4.3 OpenClaw / Claire (Phase 2)

- Files: `STATE.md` + `skills/` in the claire workspace; bootstrap block in AGENTS.md.
- **v0.1 shape is a nightly distillation audit, and it is NOT verify** (R1): a cron
  reads the day's outcomes, drafts skills into `_staging/` (status: draft), updates
  Lessons learned and Open failures. It may not promote skills and may not write
  Verified facts — transcript-derived observations never carry verified status,
  because reading transcripts exposes the maker's reasoning trail.
- **Per-task verify**: a one-day feasibility spike on a fresh-session verifier agent
  binding (input = artifact bundle only). Spike outcome decides: per-task verify
  becomes Phase 2.5, or Claire stays distill-only for v0.1. Both outcomes are honest;
  what is banned is calling the cron "verification".
- Skills: OpenClaw-native YAML claims are derived **manually** from SKILL.md (SoT) in
  v0.1, with a consistency lint (frontmatter ↔ claims). No auto-derivation.

### 4.4 Codex CLI and Kimi Code CLI — CHECKPOINT compatibility

Codex and Kimi reuse the Claude Code CHECKPOINT policy but adapt the runtime block
contract. Codex blocks by emitting `{"decision":"block","reason":...}` on stdout with
exit 0. Kimi blocks with exit 2 and the reminder on stderr. Codex supplies
`stop_hook_active`; Kimi currently does not, so Kimi's external once-per-session guard
file is the actual loop guard. The Kimi hook still honors `stop_hook_active` if a future
payload supplies it. Missing or malformed payload fields fall back to hook defaults;
environment failures that prevent safe evaluation fail open. Both hooks instruct the
continued model turn to stage only delta, unverified observations under `loop/pending/`.

### 4.5 Adapter learning-path diagnostics

`install.sh --check` reports four availability rows for each shipped adapter:
CONSULT injection, candidate generation, `verifier available`, and distiller cron.
It also reports separate isolation-conformance rows for the shipped verifier route
(Hermes) and distiller route (OpenClaw). Availability and conformance are never
collapsed into one status. These probes read the adapter implementation and, for
conformance, hash the configured wrapper, provider, probe, and evidence files; they
do not execute any of them, inspect live authentication, or prove host cron
registration. A route `FAIL` is diagnostic and does not change the existing
`--check` exit status.

## 5. Model roles

v0.1 needs exactly three roles: **maker** (runtime-native model), **verifier**
(fresh-context; cheap model fine; cross-vendor where §4.2 mandates), **distiller**
(the single writer per §3.4). Orchestrator-model choice is a rollout concern (§9),
not part of the spec.

## 6. Phasing

| Phase | Scope | Size | Route |
|---|---|---|---|
| 0 | DESIGN v0.2 ✓ + Alpha reference (STATE template, loop-init, dedup note) + seeding | L/M | direct + codex-worker for script |
| 1 | Cero: STATE.md + bootstrap + agjob-scheduled verify script + staging gate | M | Issue #3 + codex-worker |
| 2 | Claire: workspace files + nightly distillation audit + verify spike | M | Issue #4 + codex-worker |
| — | CUT from v0.1: family skills sharing, YAML auto-derivation, archive/time-window lints | — | revisit after Phase 1 data |

## 7. Risks & mitigations

1. **STATE.md bloat** → per-section caps + delete-on-overflow (§3.6).
2. **Rubric gaming by the maker** → rubric-invalid authority + required fields (§3.2).
3. **Bad facts/rules compounding** → n=1 → Lessons only; k≥2 for rules; invalidation
   pointers + deprecated status for rollback (§3.3).
4. **Concurrent-write corruption** → single-writer + atomic rename + pending/ (§3.4).
5. **Verifier outage** → hold promotions; never self-critique (§3.2).
6. **Fighting Hermes's native loop** → gate-only integration (§4.2); no second
   skill path.
7. **Fable/Mythos classifier blocks** (auto-route to Opus 4.8) can look like silent
   errors → bootstrap blocks name this failure mode explicitly; verifier scripts log
   the responding model id so a silent fallback is visible in VERIFY.log.md.
8. **OpenClaw binary/version drift** → adapter is file-level only (§4.3).
9. **Instruction-drift on CONSULT/CHECKPOINT** (bootstrap blocks are advisory) →
   session-end hooks where available (Alpha, agjob job wrapper); staleness check makes
   a skipped CHECKPOINT detectable rather than silently trusted (§3.2 CHECKPOINT).
10. **Skill trigger collisions** → deterministic precedence + logged collision (§3.3).
11. **reasoning_extraction refusals** (Fable/Mythos-class models refuse prompts that
    ask them to transcribe or echo their internal reasoning) → verifier/distiller
    prompts must request verdicts, evidence, and one-line justifications — never
    "show your thinking". Current prompts comply; keep it that way when editing.

## 8. Resolved questions (from v0.1 review)

Q1 agjob = scheduling only, verify body = standalone script. Q2 nightly = distillation
audit, honestly named; spike decides per-task. Q3 400-line budget expressed as
per-section caps. Q4 manual YAML derivation + lint. Q5 duplications removed (R9, R15).

## 9. Rollout notes (non-normative)

- **Free-window seeding (until 2026-07-07)**: use Fable 5 to distill each agent's
  initial STATE.md and first skill drafts from existing transcripts/handoffs. Seeded
  entries enter as Lessons learned (unverified) unless individually verified — the
  spec's gates apply to seeds too.
- After the window: Alpha orchestrates on Opus 4.8; Cero/Claire stay on native models.
  Verifier costs are unchanged (cheap models throughout).

## 10. Cross-cutting contracts (grok-build study, Issue #43 → #49 — normative)

Adopted as spec text from the five-model grok-build study
(`reviews/grok-build-study/SYNTHESIS.md` "Cross-cutting spec sentences"; the review
corpus is internal and not shipped in the public repository). The full
batch — including the per-surface parse-posture table and the
workspace-observability rule — lives in DESIGN-task-runner.md §8; restated here only
where this spec's own sections are bound:

- **Stop-rule precedence.** Terminal classification (deterministic failure
  classification, no-progress stop, budget exhaustion) always outranks continuation
  pressure; **a gate may never force a turn after a terminal verdict**. This binds
  the checkpoint-stop-hook seam (§4.1): the hook's continuation nudges are
  continuation pressure and yield to any terminal verdict — a continuation gate that
  overrides a no-progress verdict burns budget by construction.
- **Parse posture.** Split per-surface by WHO WRITES the file. Harness-owned files
  are strict, fail-closed: corrupt → paused, never scheduled. Model-authored files
  (flush output and distill candidates in `loop/pending/`, step results) are
  tolerant at the syntax boundary with *every coercion default falling toward LESS
  progress claimed, never more*; an unparseable or vacuous result is still
  `degenerate` and consumes the attempt.
- **Monotonic-clock discipline.** Durations use a monotonic clock; dates/staleness —
  including the §3.2 CHECKPOINT cold-start comparison (R14) — use wall-clock and
  tolerate negative skew (MBP suspend/resume reality).
- **Recorded non-adoptions (do not re-import).** Two-pass prefire distillation
  (prefire hides latency from an interactive user; cron has no observer — the 5-min
  cadence already bounds staleness); circuit breaker (`infra_retries` + budgets +
  DLQ is the same protection in readable state); skeptic panel (the single
  fresh-context verifier stays; adopted instead: full-bundle re-verify with prior
  gaps and verifier identity pinned across attempts); typed contracts / event
  envelope, digest D17 ("a second architecture" — file contracts stay; only the
  committer invariant is adopted: the distiller is a pure function, the atomic
  rename is the host, task-runner is the sole committer of scheduler truth).

## Appendix A — Artifact bundle (minimal, file-based)

```
loop/artifacts/<task-id>/
  request.md        # the original ask, verbatim
  rubric.md         # filled rubric (required fields, §3.2)
  result.md         # what was produced / where it lives
  manifest.md       # files changed (or patch), commands run, outputs referenced
  evidence.md       # test output, screenshots, links — what the rubric demands
  metadata.json     # task id, maker id, timestamps (UTC), attempt number
```

Rule: everything the verifier needs, nothing the maker thought. No transcripts.
Transport of this layout is governed by the shared
[verifier bundle assembly contract](adapters/CONTRACT.md#verifier-bundle-assembly).

## Appendix B — Rubric required fields

```
objective:            one sentence, restates the request
acceptance_criteria:  checkable list; each item maps to evidence
non_goals:            explicit exclusions
evidence_required:    what artifacts prove each criterion
failure_definition:   what outcome counts as fail (not just "not pass")
```

Completion audit (2026-07-22, #73): for both maker and verifier, uncertain or indirect evidence is treated as incomplete — acceptance criteria pass only on direct evidence.

Verification and execution discipline (2026-07-23, #75):

- `evidence_required` starts with the nearest, cheapest check. Broaden only after it
  passes and only when the criterion requires it; never begin with a broad expensive
  suite, and never skip verification.
- Incidental formatting or lint repair is capped at three fixes per attempt.
  Beyond that cap, remaining formatting is left untouched.
- Bugs outside the current plan step are report-only, not fix targets. Because
  `deviation_report` is a scheduler control signal, it remains null when the planned
  step was followed exactly; three cumulative non-null deviation reports terminate the
  task as `plan-mismatch`. A worthwhile unrelated observation may be recorded in
  `next_hint` only when that step otherwise succeeded. The driver exposes up to the
  three most-recent unique successful hints as bounded, redacted, advisory-only data in
  `PROGRESS.md`; it never places them in a later prompt or uses them for scheduling,
  step selection, retry policy, deviation counting, or terminal decisions. A failed
  attempt's `next_hint` remains a distinct bounded first-line diagnostic that may be
  replayed as neutralized DATA to the next attempt at the same step.
