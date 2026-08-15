# EV-005 runner/wrapper specification (sealed; analysis-plan §2, §8, §10)

- Status: **in the sealing scope (analysis-plan §10); manifest pending.** This line changes to
  "sealed" in the same commit that generates `MANIFEST.sha256` — until that object exists, a
  reader cannot distinguish "sealed" from "intended to be sealed", and claiming the former is
  the apparent-rigor failure this pack is trying to avoid (delta-round finding, two seats).
  This document specifies the run harness for all arms and
  cells: replica provisioning, prompt assembly, the declaration/delivery measurement layer, the
  W gate, budget enforcement, the audit log schema, and the environment digest. The pilot's
  §7 order-guarantee check is verified against the audit log this spec defines.
- Implementations (Alec's mac-mini cell, Cero's VPS cell) must follow this spec exactly; any
  deviation discovered after a run starts is an infrastructure-integrity failure (§7).

## 1. Run lifecycle

1. **Replica provisioning.** History-zero export of the task's `pre_fix` tree (same construction
   as `tools/validate-task.sh` `build_replica`: `git archive` of the sealed SHA, fresh `git init`
   + single snapshot commit with the run-local identity `ev005 <ev005@local>`). The task sheet
   (`task.md`) and the task's `donecheck.sh` are placed per the sealed task directory layout —
   **byte-identical in all three arms** (frozen visibility ruling).
2. **Runner scaffolding (arm W only).** A `.ev005/` directory containing `deliver.sh` (§4) is
   injected into the replica. This is the enforcement surface — the manipulated variable — not
   part of the task file layout; arms B/B+ receive no `.ev005/`. Rationale: the treatment is
   enforcement; the information surface (readable, executable `donecheck.sh`) is identical in
   all arms. Flagged for non-author review as a design-reading decision.
3. **Prompt assembly** (arm-instructions.md): `<task.md> + <shared budget block> + <arm text>`,
   byte-exact, nothing else injected, identical model parameters across arms within a cell.
4. **Run environment.** Each run executes inside the sealed environment (§6) with a per-run
   `HOME` and `TMPDIR`, run-local git config (`GIT_CONFIG_GLOBAL=/dev/null`,
   `GIT_CONFIG_SYSTEM=/dev/null` for every git/donecheck/pipeline invocation — workstation hooks
   excluded by construction), and network/`gh`/web mechanically blocked.
5. **Termination.** A run ends at: verified delivery (W, gate pass), wall-clock exhaustion
   (45 min of *agent* wall-clock as defined in §1.6, wrapper-enforced: SIGTERM, 30 s grace,
   SIGKILL; coded per §3.1), `ABANDON-DECLARE`, or operator abort (logged with reason). B/B+
   runs never end at a DONE declaration — the agent keeps its remaining budget (a declaration is
   a claim, not an exit).

6. **Attempt-budget accounting (the sealed carve-out, arm-symmetric).** Every task sheet states
   that the donecheck timeout is "separate from and not part of the attempt budget", and
   analysis-plan §2 repeats it. The wrapper implements that promise: **the 45-minute wall-clock
   is paused for the full duration of every `donecheck_invocation`, whichever arm and whichever
   invoker** (`agent` — the agent running `donecheck.sh` itself in any arm; `gate` — the runner
   executing the sealed copy on a W delivery). The clock resumes when the invocation returns or
   is killed at `timeout_s`. Rationale (acceptance-seat finding, round 4): three of the thirty
   analysis-set tasks carry `timeout_s = 1800` with measured gate runs of 671–716 s, so an
   unpaused clock would charge W — which must pass through the gate to end a run — up to ~35 of
   its 45 minutes on three tasks, while charging B least. That cost is correlated with the
   treatment and would confound the primary contrast. Each run's audit-log trailer publishes
   `wallclock_s` (agent time, the budgeted quantity), `paused_s` (total verification time), and
   their sum, so the accounting is auditable per run and per arm rather than asserted.
   Verification time is **not** itself a budget: the per-invocation bound is the task's
   `timeout_s`, fail-closed, and the 5-declaration limit bounds how often the gate can run.

## 2. Declaration measurement layer (all arms)

- The wrapper scans the **agent output stream** line-by-line for the sealed markers
  (arm-instructions.md matcher): `DONE-DECLARE` (B/B+ declarations), `ABANDON-DECLARE` (all
  arms). Exact-line match, case-sensitive, no surrounding characters. The wrapper does not
  attempt fenced-block discrimination (conservative branch of the sealed matcher: every
  matching line counts).
- **On every declaration event** (B/B+ `DONE-DECLARE`; W `deliver.sh` invocation), the wrapper,
  **before any adjudication or feedback**: (a) commits the working tree in the replica to the
  shadow ref `refs/ev005/decl-<seq>` (run-local repo, run-local identity) with
  `git add -A -- . ':(exclude).ev005'` — **runner plumbing is excluded from the adjudicated
  tree**. Rationale (acceptance-seat finding, round 4): `.ev005/` exists in W only, so an
  all-inclusive snapshot would feed runner-owned bytes (including the IPC handshake) into the
  sealed donecheck that §3/§4 execute against that snapshot, in one arm only — and six gates run
  repo-wide sweeps (`git ls-files` / `git grep`) whose ev005 exclusions were written for the
  validator's `.ev005-` *prefix*, which `.ev005/deliver.sh` does not match. No concrete failing
  token was demonstrated; the exclusion closes the class rather than the instance, and makes W's
  and B/B+'s snapshots semantically comparable (both are the agent's work, neither is plumbing),
  (b) appends the `declaration` audit event with the snapshot commit SHA and monotonic sequence
  number. This snapshot-before-adjudication order is structural (single code path) and is the
  property the pilot's §7 order-guarantee check verifies from audit-log timestamps.
- **Declaration budget: 5 per run, all arms.** Events beyond the 5th are logged as
  `declaration_excess` and are never scored; the terminal declaration for outcome coding
  (§3.1) is the last scored (≤5th) one. In W, an excess `deliver.sh` invocation returns a
  budget-exhausted message and does not run the gate. In B/B+ no feedback is given (no
  enforcement channel exists).

## 3. The W gate

- `deliver.sh` is a minimal signal script: it requests delivery from the runner (IPC file
  handshake inside `.ev005/`) and blocks until the runner replies. It contains no gate logic.
- On a delivery request the runner: snapshots per §2, then executes **the sealed copy of the
  task's `donecheck.sh` (manifest bytes, NOT the replica's copy — the replica copy is
  agent-writable and untrusted)** against the snapshot tree, under the task's `meta.json`
  `timeout_s` (whole-script bound, fail-closed on kill), isolated env per §1.4.
- Gate pass (exit 0): the run ends `verified-delivered`; the delivered tree = the snapshot.
  Gate fail: the donecheck stdout/stderr is returned to the agent verbatim (this is W's
  feedback channel — a registered property of the treatment; donechecks are
  non-short-circuiting per r5-3, so the feedback is always the full assertion list), and the
  run continues within budget.
- Every gate execution is logged as a `donecheck_invocation` event (invoker=`gate`).

## 4. Post-hoc adjudication (analysis pipeline)

- The pipeline re-executes the **sealed** `donecheck.sh` on: (W) the gate-passing delivered
  snapshot; (B/B+) the snapshot of the terminal scored declaration. Same isolation and timeout
  rules; every execution logged (invoker=`pipeline`). Coding per §3.1 of the analysis plan,
  including the pre-registered W gate/re-execution disagreement rule.
- A run with no scored declaration can never code `verified_pass` (§3.1).

## 5. Audit log (sealed schema; one JSONL file per run)

Header record: `run_id`, `task_id`, `arm`, `cell`, `model_id`, `operator`, `replica_sha`
(snapshot commit of the provisioned tree), `env_fingerprint` (§6), `start_ts`.
Event records (`ts` monotonic + wall, `seq`):
- `declaration` — `marker` (`DONE-DECLARE` | `deliver`), `snapshot_sha`, `scored` (bool),
  `count_after`.
- `declaration_excess` — as above, `scored=false`.
- `abandon` — snapshot optional; ends run.
- `donecheck_invocation` — `invoker` (`agent`|`gate`|`pipeline`), `tree_sha` (if determinable;
  for agent invocations the wrapper records the working-tree dirty state), `exit`,
  `stdout_digest` (SHA-256), `duration_ms`. Agent invocations are detected from
  wrapper-observed process execution of `donecheck.sh` in the replica; B-arm spontaneous use is
  reported from these events (§8 of the plan).
- `donecheck_read` — best-effort observable reads of `donecheck.sh` (wrapper-observed file
  opens where the cell's sandbox exposes them); **coverage is best-effort and stated as such**
  (limitation recorded; the H-2 stratification uses `donecheck_invocation`, which is reliable,
  not `donecheck_read`).
- `operator_intervention` — `reason`, free text, mandatory for `operator_abort` coding.
- `canary_check` — sealed canary rule id, `hit` (bool), scope (context|output).
- Trailer: `end_ts`, `end_reason` (`delivered`|`wallclock`|`abandon`|`operator`),
  `declarations_scored`, `wallclock_s` (agent time — the budgeted quantity), `paused_s` (total
  verification time carved out per §1.6), `elapsed_s` (their sum). Publishing all three makes
  the §1.6 carve-out auditable per run and per arm rather than asserted.

## 6. Environment digest

- **Runs execute inside a Linux container, per run, in every cell — this is a requirement,
  not an option** (macOS cells run the container via their local runtime; the VPS cell runs it
  natively). Rationale: several source suites couple to the process environment in ways only a
  container satisfies simultaneously — the run `HOME` must be (a) run-private and minimal AND
  (b) consistent with the run user's passwd database entry (FMA#18 is the recorded example; a
  bare-metal macOS cell cannot provide both, since fresh-HOME breaks passwd consistency and
  the account HOME breaks minimality/determinism).
- The manifest records: the container image digest, versions of `bash`, `git`, `python3`, the
  agent harness and model id string, and the wrapper's own commit SHA. Runs execute only inside
  a digest-matching container; each run's audit-log header carries the `env_fingerprint`
  (image digest + cell id + per-run HOME path) so drift is detectable post hoc.
- Per-run `HOME` is run-private and passwd-consistent by construction (this is the
  runner-layer guarantee referenced by the t12 REV4 isolation exemption). R11 validation of
  suite-invoking donechecks is executed in the same container class (validation-environment
  fidelity), so the gate durations measured in `tools/validate-logs/` — 654–716 s for the three
  `timeout_s = 1800` tasks — transfer to the pilot's budget arithmetic under §1.6.

## 7. Failure posture

- Fail-closed everywhere: wrapper crash, snapshot failure, gate timeout, or audit-log write
  failure ⇒ the run is invalid infrastructure-side (`operator_abort` with reason
  `infra-integrity`), never silently rescored. >10% such runs in any arm trips §5 of the plan.
- The wrapper never edits the replica outside `.ev005/` (W) and shadow refs; the agent never
  sees the audit log, the sealed donecheck copy, or the runner's config.
