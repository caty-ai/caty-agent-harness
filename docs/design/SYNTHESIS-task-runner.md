# SYNTHESIS — task-runner v0.1 cross-review adjudication (Issue #8)

Date: 2026-07-04. Synthesizer: Alpha (Claude Fable 5).
Panel: Codex gpt-5.5 xhigh (APPROVE-WITH-CHANGES, 6 blocking) / GLM 5.2 (A-W-C, 4) /
Claude Sonnet 5 (A-W-C, 5) / Claude Opus 4.8 (REJECT, 4). Full texts: reviews/tr-review-*.md.
Provenance note: the GLM seat self-labeled "Fable" via wrapper persona bleed (STATE.md
Lessons 2026-07-04); weights are GLM 5.2, so cross-vendor validity holds.

Convergence: every seat independently hit the same four load-bearing defects
(crash-recovery not transactional; budget semantics unreconstructable; driver's STATE.md
write vs parent single-writer; mechanical-pass leak into verified-only promotion).
Per the k≥2 convergence heuristic these were treated as confirmed without re-litigation.

## Resolutions TR-R1…TR-R15 (applied in [DESIGN-task-runner.md](./DESIGN-task-runner.md) v0.2)

| # | Finding (seats) | Resolution |
|---|---|---|
| TR-R1 | Crash-mid-tick not transactional; double-run/double-delivery windows (ALL; Opus B4, Codex B2) | Per-task `state.json` = the ONLY machine truth (status queued→running→verifying→delivered\|dlq, current_step, attempts_used, active_seconds_used, lease {pid,pgid,started}); every transition = temp-write + atomic rename, single commit point. Stale-lease rule at tick start: `running` + dead pgid (or lease older than step_timeout+grace) → reap orphan process group, stamp attempt `crashed`, charge it, resume deterministically. |
| TR-R2 | Budget semantics fork implementations; N=8×10min vs 30min inconsistent; false-DLQ on slow-but-working pilot (ALL; Opus B3, Codex B3, Sonnet B1, GLM B1/M6) | Rename: `attempts_budget` (=D5's N=8) vs `plan_steps` (enumerated list); enqueue invariant `plan_steps ≤ attempts_budget`. Every spawned attempt consumes exactly 1 attempt; driver measures spawn→reap seconds into `active_seconds_used` (kill/timeout charges full step_timeout). Infra failures BEFORE the model runs consume 0 attempts, bounded 3 infra-retries → DLQ reason=infra (kills Opus's outage fast-burn + notification storm). Exhaustion = attempts OR active-time. Enqueue validation rejects `step_timeout > time_budget` and requires `time_budget ≥ plan_steps × expected step minutes` — pilot image task ships with explicit `time_budget_min: 60` override (D5 defaults unchanged; overrides are part of D5). |
| TR-R3 | Step advancement authority ambiguous; "failed twice" rule unimplementable or queue-stalling (Codex B1, Sonnet B5, GLM B1, Opus B2) | Driver-authoritative: `current_step` lives in state.json; STEP-PROMPT injects "you are executing plan step k: <text>". Agent ends every attempt by writing `step-result.json` {step_complete, files_created[], error_class, deviation_report?, next_hint} (Codex M4 — structured JSON, not prose, is the machine interface). Advance only on step_complete=yes. 2 consecutive non-completes on step k → yield to next tick; 2 consecutive with IDENTICAL error_class → early DLQ reason=persistent-failure. No skip path exists and attempts are always consumed → Opus's permanent queue-head stall is structurally impossible. "Donecheck not yet satisfied" is task-level state, never a step failure (Codex M3). |
| TR-R4 | Driver rewriting STATE.md violates parent single-writer verbatim (Opus B1 — REJECT core; Sonnet B3, Codex B6, GLM M10) | Driver NEVER touches STATE.md — and (Codex cut #4) not `loop/pending/` either. All task-runner state lives in `loop/tasks/` + `loop/artifacts/`. The workspace's normal distill path consumes delivered bundles. Zero contact with parent-owned files; invariant conflict dissolved rather than mitigated. |
| TR-R5 | Mechanical pass leaks into verified-only promotion; `done/` overclaims (ALL; Sonnet B4, GLM B4, Codex B-summary) | Terminal state renamed `delivered` (completion, not quality). Distill candidates from delivered tasks carry `verify: mechanical` and are EXCLUDED from k≥2 counting until a real harness VERIFY (or explicit human promotion). v1 vision pass upgrades them. |
| TR-R6 | PROGRESS.md append-only contract breaks under crash/interleave; dual-role parsing fragile (Codex B5, GLM B3/M5, Sonnet B1) | PROGRESS.md demoted to human-readable evidence, RENDERED by the driver from per-attempt fragments `loop/artifacts/<id>/attempts/NNN/` (step-result.json, driver stamps, rendered step prompt, donecheck log). Nothing parses PROGRESS.md. |
| TR-R7 | Donecheck execution context unpinned → correct deliveries false-DLQ from cron's cwd (Codex B4, Opus M1, GLM m11, Sonnet m3) | Normative: `bash -euo pipefail`, cwd=workspace, exported `TASK_ID` `TASK_FILE` `ARTIFACT_DIR`, read-only assertions only, 60s timeout, output captured to `attempts/NNN/donecheck.log`; failing assertion line goes into the DLQ push payload. Magic-byte check replaces `file|grep` (Opus m3). |
| TR-R8 | Kill leaks orphaned/billable API calls; delivery can double-fire (GLM M8, Sonnet M3, Opus B4/Q3, Codex M7) | `setsid` process group; TERM → 30s grace → KILL; adapter-level HTTP timeout; backend request/job-id captured to a sidecar BEFORE waiting — missing id on generation/delivery steps = error_class=fatal; delivery idempotency = receipt-check before send keyed task_id+step; orphan reap at tick start (TR-R1). |
| TR-R9 | Within-tick multi-step loop: crash window + flock/cadence collapse (Opus cut #1, Codex cut #6, GLM M7, Sonnet m1) | ONE attempt per tick. Cron cadence = attempt cadence; flock trivial; crash window = one atomic attempt. Clean 5-step task ≈ 25 min wall at 5-min cron — acceptable at pilot volume. |
| TR-R10 | agjob "views over dirs" dual-mode contradiction (Codex B-summary/M6/cut#1, GLM cut; Sonnet dissented: hardcode agjob) | Plain dirs + state.json are the v0 ledger, full stop. agjob contributes the pattern and its existing DLQ→notification transport only. Adopted 3:1 — pinning agjob's claim/heartbeat contract is a bigger job than the pilot itself (Codex's argument). Oldest-first = frontmatter `created` (Codex M8). |
| TR-R11 | Q1 push channel (all converge) | Reuse the existing family notification route on the VPS as config `FAMILY_PUSH_CHANNEL`; install blocks unless a test-send succeeds (Codex); inbox/ledger record is the durable artifact, push is best-effort (GLM). No new bot. |
| TR-R12 | Q2 re-plan (all converge: NO) | No re-plan in v0. `deviation_report` field in step-result.json; a deviation consumes its attempt; >2 deviations → DLQ reason=plan-mismatch so Alpha re-authors the plan (plan is data, D7). Weak-model re-planning defeats the core insight. |
| TR-R13 | Q4 vision vendor (unanimous) | Claude vision for v1 (non-xAI mandate satisfied; reuses the §4.1 `claude -p` verifier seam). If access/cost blocks, defer v1 rather than adding a weak verifier (Codex). Question closed. |
| TR-R14 | Metrics/baseline ceremony (Sonnet, GLM, Opus, Codex minors) | `tr-metrics.sh` REGENERATES METRICS.md from ledger terminal states (idempotent, no append double-count), v0 columns = counts + completion rate only. Control runs optional and off the critical path. D8 satisfied. |
| TR-R15 | Adopted minors (Codex m1-m10, Opus m2/m4, Sonnet m4, GLM m12-13) | UTC ISO-8601 w/ seconds everywhere; `issued_by: sho-alpha` (ASCII); rendered step prompt stored per attempt; DLQ re-enqueue = NEW id + `parent_id` (never reuse); `verify:` fixed literal `mechanical` in v0, other values rejected at enqueue; Resources = readable paths/env-var names only; `attempts_budget` vs the harness's N=3 verify retries named distinctly; task-id prefix non-semantic; step_timeout is a global driver constant (10 min), not per-task frontmatter (Sonnet cut); PROGRESS.md render excluded from any v1 verifier bundle — maker-narration-adjacent (Opus M4). |

## Explicitly rejected / deferred

- Sonnet's "hardcode agjob" — outvoted (TR-R10); revisit when a second consumer exists.
- GLM's per-attempt API-cancel-endpoint call — deferred to the adapter child issue;
  request-id capture + reap is the v0 floor (cancel endpoints are backend-specific).
- Any re-plan step type (unanimous rejection, TR-R12).
- Vision scoring in v0 schema (Codex cut #5): `verify:` stays a fixed literal.

## Verdict on v0.2

All 19 blocking issues across the four seats map onto TR-R1…TR-R10; no blocker was
left unaddressed or deferred. Opus's REJECT grounds (single-writer, stall,
double-delivery, budget inconsistency) are each structurally removed, not patched.
