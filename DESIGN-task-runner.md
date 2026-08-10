# task-runner v0.2 — Completion Driver for Weak-Model Agents (Issue #8)

> Historical design record. Issue numbers cited in this document (e.g. #43, #49) refer to the pre-publication private tracker, not to issues in this repository.

Status: v0.2 — cross-review resolutions TR-R1…TR-R15 (SYNTHESIS-task-runner.md) applied.
Amended 2026-07-18: §8 cross-cutting contracts (grok-build study, #43 → #49).
Author: Alpha (Claude Fable 5), 2026-07-04.
Review lineage: v0.1 → Codex gpt-5.5 xhigh / GLM 5.2 / Sonnet 5 (APPROVE-WITH-CHANGES)
+ Opus 4.8 (REJECT) → adjudication in SYNTHESIS-task-runner.md → this rewrite.
Parent: Issue #8 (EPIC). Companion to DESIGN.md (harness v0.2); does not restate it.

## 0. TL;DR

The harness loop guards the QUALITY of finished work; task-runner DRIVES work to
completion on weak backends. Split a task into an enumerated plan, run one attempt per
cron tick in a FRESH agent session that receives only {task file, progress evidence,
STATE.md}, keep all machine truth in a per-task `state.json` (atomic renames, the only
scheduler database), gate completion with executable done-checks, and escalate to a
human with the evidence trail when budgets run out. No daemon, no new DB — cron +
scripts + files only.

Pilot: **Luca** — Hermes Agent profile on the Claire/Cero VPS, backend **grok 4.2**
(xAI). Reproducible failure case: image-generation workflow.

## 1. Interview decisions (the maintainer, 2026-07-04 — fixed)

| # | Decision |
|---|---|
| D1 | Luca = Hermes Agent profile, same VPS as Claire/Cero; backend grok 4.2. Driver = cron on that VPS; reach = same self-install path as Cero. (#8's "OpenClaw profile" corrected.) |
| D2 | Failure location varies run to run; Luca loses track of where he failed; image DELIVERY is the recurring terminal blocker. |
| D3 | Verification staged: v0 = mechanical gate; vision rubric scoring = v1 via the verify-job.sh seam. |
| D4 | Driver invocation = cron polling. No daemon. |
| D5 | Default budgets: 8 attempts / 30 min active time, per-task override in the task file. |
| D6 | DLQ escalation = immediate push to the maintainer + permanent inbox/ledger record. |
| D7 | Issuance: the maintainer → Alpha formats task file (owns rubric quality) → enqueue. Only path in v0. |
| D8 | Completion-rate metric auto-derived from ledger terminal states into METRICS.md. |

Consequences of D2: machine-anchored evidence trail (driver-stamped, model-independent),
delivery as a mandatory explicit plan step with receipt evidence, fresh-context-per-step
as the medicine for nondeterministic collapse.

## 2. Core insight (from #8, unchanged)

Weak models are reliable in SHORT contexts and degrade over LONG ones. Never give them
a long context: the driver re-injects {task file + progress evidence + STATE.md} every
attempt by machinery. "Can the model remember the API endpoint" becomes "does the
driver re-read the task file" — structurally unforgettable.

## 3. Spec (runtime-neutral core)

### 3.1 Files (TR-R1, TR-R6, TR-R10)

```
<workspace>/loop/
  tasks/
    queue/<id>.task.md           # task files awaiting/in work (stay here while running)
    delivered/<id>/              # terminal: passed the mechanical gate (TR-R5 naming)
    dlq/<id>/                    # terminal: escalated; contains task file + state.json copy
  artifacts/<id>/
    state.json                   # THE machine truth (§3.4) — atomic temp+rename only
    attempts/NNN/                # per-attempt fragments (§3.3)
      prompt.md                  #   rendered step prompt (evidence for debugging)
      step-result.json           #   agent's structured exit report
      driver.json                #   driver stamps: started/ended UTC, dur_s, outcome
      donecheck.log              #   captured gate output for this attempt
    attempts-infra/NNN.infra-K/  # quarantined requeued infra evidence
    PROGRESS.md                  # human-readable render from attempts/ — NOTHING parses it
    out/                         # task outputs (image, receipts, sidecars)
templates/  TASK.tmpl.md  STEP-PROMPT.tmpl.md
scripts/    task-runner.sh  tr-metrics.sh  tr-enqueue (validation, §3.6)
```

Requeued infra attempts are quarantined in `attempts-infra/NNN.infra-K/`, where K is `infra_retries` after increment.

Ledger = these plain dirs + state.json, full stop (TR-R10). agjob contributes its
proven state-shape and the existing DLQ→notification transport, NOT its queue.
Oldest-first ordering = frontmatter `created` (never mtime).

### 3.2 Task file schema

```yaml
id: img-20260706-001           # unique; prefix is non-semantic (TR-R15)
title: one line
issued_by: sho-alpha           # ASCII, machine-stable
created: 2026-07-06T00:00:00Z  # UTC ISO-8601 with seconds, everywhere (TR-R15)
attempts_budget: 8             # D5 N — counts ATTEMPTS, not plan steps (TR-R2)
time_budget_min: 30            # D5 — cumulative active seconds, driver-measured (§3.4)
escalate_to: sho               # D6
verify: mechanical             # fixed literal in v0; any other value rejected (TR-R15)
parent_id: null                # set only on DLQ re-enqueue (always a NEW id, TR-R15)
```

(step_timeout is a global driver constant, 10 min — not per-task; TR-R15.)

Body sections (all required; "none" allowed, deletion not):

- `## Goal` — one paragraph.
- `## Done-when` — a `donecheck` fenced block of executable assertions. Contract
  (TR-R7): the driver runs it with `bash -euo pipefail`, cwd = workspace,
  `TASK_ID`/`TASK_FILE`/`ARTIFACT_DIR` exported, 60 s timeout, output captured to the
  attempt's `donecheck.log`. Assertions are READ-ONLY (they run after every attempt).
  Prefer magic-byte checks over `file | grep`. MUST include a delivery-receipt
  assertion (D2), e.g.:
  ```donecheck
  test -s "$ARTIFACT_DIR/out/image.png" || { echo "FAIL: image exists"; exit 1; }
  head -c8 "$ARTIFACT_DIR/out/image.png" | grep -q $'\x89PNG' || { echo "FAIL: PNG magic bytes"; exit 1; }
  test -s "$ARTIFACT_DIR/out/delivery-receipt.json" || { echo "FAIL: delivery ack captured"; exit 1; }
  ```
- `## Step plan` — enumerated `plan_steps`; invariant `plan_steps ≤ attempts_budget`
  (enqueue-validated). The agent executes exactly the injected step k; it may file a
  `deviation_report` (§3.3) but never re-plans (TR-R12). The LAST step is always
  "deliver + capture receipt".
- `## Resources` — readable local paths / env-var NAMES only (never secret values;
  weak agents must not infer credential locations — TR-R15).
- `## Non-goals`.

Trust note: donecheck is arbitrary (read-only) shell; acceptable in v0 because D7 is
the only issuance path. Reopening issuance is a design change (§7 risk 6).

### 3.3 Attempt contract (TR-R3, TR-R6 — structured JSON, not prose)

Each attempt: the driver renders STEP-PROMPT.tmpl.md with {task file, current plan
step k + its text, last M attempt summaries, STATE.md} and spawns a fresh session.
The agent's ONLY machine interface is writing `step-result.json` before exit:

```json
{ "step_complete": true,
  "files_created": ["out/image.png"],
  "error_class": null,          // e.g. "auth", "http-5xx", "tool-misuse", "fatal"
  "deviation_report": null,     // set → consumes the attempt; >2 → DLQ plan-mismatch
  "next_hint": "one line" }     // advisory only; the driver never parses it for control
```

The driver stamps `driver.json` (started/ended UTC, dur_s, outcome ∈ ok | error |
timeout | crashed) around it. PROGRESS.md is re-rendered from these fragments for
humans (and for the next attempt's prompt context); no control flow reads it.
"Donecheck not yet satisfied" is task-level state, never a step failure (TR-R3).

### 3.4 state.json + driver loop (TR-R1, TR-R2, TR-R9)

`state.json` is the only scheduler database:

```json
{ "status": "queued|running|verifying|delivered|dlq",
  "current_step": 3, "attempts_used": 4, "active_seconds_used": 512,
  "infra_retries": 0,
  "lease": {"pid": 0, "pgid": 0, "started": "..."},
  "consec_noncomplete": 1, "last_error_class": "http-5xx",
  "terminal_reason": null }
```

Every transition = temp-write + atomic rename. Cron every 5 min; singleton flock;
**one attempt per tick** (TR-R9). Tick algorithm:

1. **Reap**: any task `running` with a dead pgid (or lease older than step_timeout +
   30 s grace) → kill the process group, stamp the dangling attempt
   `outcome: crashed` (charge 1 attempt, dur = observed or full step_timeout),
   status → queued. Deterministic re-entry from state.json alone.
2. Pick oldest `queued` by `created`.
3. Spawn attempt NNN in its own process group (`setsid`); status → running with lease.
   - Infra failure BEFORE the model runs (spawn/gateway refused): consume 0 attempts,
     `infra_retries += 1`; > 3 → DLQ reason=infra. Bounded, no notification storm,
     no budget burn on an xAI outage (TR-R2).
4. On exit/kill: stamp driver.json (timeout charges full step_timeout to
   `active_seconds_used`); update counters; status → verifying; run donecheck.
   - all pass → status delivered, move task file to `delivered/` (rename = commit).
   - step_complete=yes → current_step += 1, consec_noncomplete = 0.
   - non-complete: consec_noncomplete += 1. Two consecutive with IDENTICAL
     error_class → DLQ reason=persistent-failure. Otherwise yield (next tick retries
     step k). Attempts are ALWAYS consumed — no skip path, no stall (TR-R3).
5. `attempts_used ≥ attempts_budget` OR `active_seconds_used ≥ time_budget` → DLQ.

Delivery idempotency (TR-R8): generation/delivery steps must write the backend
request/job-id to a sidecar BEFORE waiting on the call; a missing sidecar on those
steps is error_class=fatal. The delivery step checks for an existing valid receipt
before sending (key task_id+step) — a crashed-after-send attempt cannot double-fire.
Kill = TERM to pgroup → 30 s grace → KILL; the adapter also sets HTTP timeouts.

STATE.md: the driver NEVER writes it — nor `loop/pending/` (TR-R4). All task-runner
state lives under `loop/tasks/` + `loop/artifacts/`. The workspace's normal distill
path consumes delivered bundles; candidates distilled from them carry
`verify: mechanical` and are excluded from k≥2 promotion until a real harness
VERIFY or explicit human promotion (TR-R5).

### 3.5 Escalation / DLQ (D6, TR-R11)

On DLQ: atomic terminal state + move to `dlq/` (task file, state.json copy, pointer to
artifacts); durable inbox record; push to the maintainer via `FAMILY_PUSH_CHANNEL` (the
existing family notification route on the VPS — install blocks unless a test-send
succeeds; push is best-effort, the inbox record is the artifact). Payload: task id,
terminal_reason, last 3 attempt summaries, the failing donecheck assertion line,
artifact path. Re-enqueue is manual, always under a NEW id with `parent_id` set.

### 3.6 Enqueue validation (tr-enqueue)

Rejects: missing/duplicate id, missing sections, no delivery step, no delivery
assertion, `verify` ≠ mechanical, `plan_steps > attempts_budget`,
`step_timeout > time_budget`, donecheck that fails `bash -n`, unwritable artifact dir.
Warns (does not block): `time_budget_min < plan_steps × 8 min` — the pilot image task
ships with `time_budget_min: 60` (D5 override; defaults unchanged).

### 3.7 Metrics (D8, TR-R14)

`tr-metrics.sh` REGENERATES METRICS.md from ledger terminal states (idempotent):
delivered / dlq counts + completion rate, per task-file `parent_id` chain. Baseline
row B0 = the maintainer's field estimate, labeled `estimate`. Control runs optional, off the
critical path.

### 3.8 v1 reservation (one line, TR-R13)

v1 = Claude-vision rubric scoring through the DESIGN.md §4.1 `claude -p` verifier seam
(non-xAI mandate satisfied); the verifier bundle EXCLUDES PROGRESS.md and step-result
files (maker-narration-adjacent — parent no-transcript invariant). If access/cost
blocks Claude vision, v1 is deferred rather than substituted.

## 4. Hermes/Luca adapter (thin)

- `spawn_step`: standalone script starting a fresh Hermes session for profile luca
  (grok 4.2), `setsid`, outer timeout, HTTP/API timeouts, request-id sidecar
  convention — same fresh-process pattern as adapters/hermes/verify-job.sh.
- Install: TASK-PACKET-luca.md (internal install packet; not shipped in the public
  repository) — self-install + Done-when-evidence protocol proven with Cero and
  Claire. Cron + FAMILY_PUSH_CHANNEL test-send are part of Done-when.

## 5. Scope-out (v0)

No daemon. No new DB. No agjob queue coupling (pattern + notification transport only).
No Hermes-core modification. No multi-task parallelism per tick, no multi-attempt per
tick. No agent-issued tasks. No re-plan step type. No vision scoring. Not for
strong-model interactive work; casual conversation is not a task.

## 6. Resolved questions

Q1 → TR-R11 (reuse family push route, test-send gated). Q2 → TR-R12 (no re-plan;
deviation_report + plan-mismatch DLQ). Q3 → TR-R8 (pgroup kill + request-id sidecar +
receipt idempotency). Q4 → TR-R13 (Claude vision, closed). Q5 → TR-R2/R3 (every
attempt consumes budget; identical-error fast-DLQ; infra failures held separately).

## 7. Risks

1. Plan granularity wrong for grok 4.2 → plan is data; pilot tunes it, Alpha
   re-authors on plan-mismatch DLQ.
2. Broken task file burns budget → tr-enqueue validation (§3.6).
3. Cron dies silently → install.sh --check probe: "queue non-empty but no tick in
   > 30 min" (mirrors #7 sentinel).
4. state.json / dir-move divergence on crash → single-commit-point rule: the atomic
   state.json rename IS the truth; dir moves are derived and re-derivable (§3.4).
5. Backend outage → infra_retries path, budget-neutral, one DLQ after cap (§3.4).
6. donecheck shell if issuance opens beyond D7 → frozen: reopening is a design change.
7. NTP/clock skew corrupts dur_s → driver computes durations from its own monotonic
   clock, never from timestamps in files.
8. Disk-full mid-artifact-write → donecheck `test -s` catches truncation; the attempt
   fails without corrupting state.json (atomic rename on a full disk fails whole).

## 8. Cross-cutting contracts (grok-build study, Issue #43 → #49)

Adopted as DESIGN text from the five-model grok-build study
(`reviews/grok-build-study/SYNTHESIS.md` "Cross-cutting spec sentences"; verdict
trail in `xrev-*.md`; the review corpus is internal and not shipped in the public
repository). These rulings are contracts, not code; if they lived only
in reviews/ they would be re-litigated or violated by the next implementer.
Implementers of the Phase-1 wave (#44–#48) and later waves are bound by them.

NOTE on IDs: `Dnn` in this section refers to grok-study digest IDs
(`reviews/grok-build-study/DIGEST.md`), NOT the §1 interview decisions.

### 8.1 Stop-rule precedence

The adopted build set creates independent pressures on the same turn boundary:
continuation gates (D3 fire-cap, D4 completion requirements) say "keep going";
no-progress and budget verdicts say "stop". Precedence is fixed:

> **Terminal classification (D2 deterministic, D21 no-progress, budget exhaustion)
> always outranks continuation pressure (D3/D4); a gate may never force a turn after
> a terminal verdict.**

A continuation gate that overrides a no-progress verdict burns budget by
construction.

The D21 gap fingerprint includes the identity of the failing donecheck assertion, with
the same path and timestamp masking applied to captured gate output. Verdict formation
suppresses D21 when the driver's persisted step progress contradicts it; this does not
change the §8.1 stop-rule precedence order.

### 8.2 Parse posture — split per-surface by WHO WRITES the file

| Surface | Writer | Posture |
|---|---|---|
| `state.json`, `driver.json`, task frontmatter, cursor files | harness | **STRICT, fail-closed.** The writer is the harness; any malformation is a bug or corruption. Parse-fail / out-of-enum → paused `corrupt-state`, raw file preserved, never rescheduled (D14). |
| `step-result.json`, flush output, distill candidates | model | **TOLERANT at the syntax boundary**, with one governing rule: *every coercion default must fall toward LESS progress claimed, never more.* Unknown fields ignored+logged; boolean spellings coerced; missing `step_complete` → false + warning. |

Hard floor on the tolerant side: unparseable JSON or a vacuous result is still
`degenerate` per D8 and **consumes the attempt** — tolerance never creates a free
retry. (A weak-model formatting slip must not crash a tick, and the safe default
direction is "not complete".)

### 8.3 Workspace observability, not snapshots

The driver stamps `git_head` + dirty-file-count in `driver.json` — pure
observability, zero machinery. **Git refs are never part of correctness, rollback,
or resume identity.** The artifact bundle plus `attempts/NNN/` already IS the
durable snapshot (Appendix A of DESIGN.md's whole point); git-ref snapshot machinery
was a unanimous v0 reject, including by its original proposers.

Recorded revisit trigger: pilot DLQs showing unreconstructable worktree state as an
actual failure cause. Until that trigger fires, do not build snapshot machinery.

### 8.4 Monotonic-clock discipline

> **Durations use a monotonic clock; dates/staleness use wall-clock and tolerate
> negative skew (MBP suspend/resume reality).**

Extends §7 risk 7 from a driver note to a harness-wide contract: time-source choice
is load-bearing. Elapsed durations, attempt/budget windows, retry windows, and
process-local deadlines use a monotonic clock. Dates, persisted staleness/mtime
comparisons, cursor mtimes, and cross-process lease-staleness checks use wall-clock
and must tolerate negative skew. A host whose clock jumps — NTP step, laptop
suspend/resume — must not fire budgets early, expire leases falsely, or stamp
yesterday's date.

### 8.5 Recorded non-adoptions (so the ideas are not re-imported)

| Mechanism | Ruling |
|---|---|
| Two-pass prefire distillation (D16) | Unanimous reject — prefire hides latency from an interactive user; cron has no observer. Surviving fragments only: never-split-a-tool-pair boundary snapping; no-drop carry-over cursor. |
| Circuit breaker | Standing rejection affirmed — `infra_retries` + budgets + DLQ is the same protection in readable state. |
| Skeptic panel | Stays out. Adopted instead, S-cost only: full-bundle re-verify with prior gaps as "confirm fixed", and verifier identity pinned in `metadata.json` across attempts — anti-judge-shopping matters more than panel breadth at this scale. |
| Typed contracts / event envelope (D17) | Unanimous LATER/SKIP — "a second architecture". File contracts stay. Adopted only the one-sentence committer invariant: the distiller is a pure function, the atomic rename is the host, task-runner is the sole committer of scheduler truth. |
