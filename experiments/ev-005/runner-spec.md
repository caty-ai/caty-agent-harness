# EV-005 runner/wrapper specification (sealed; analysis-plan §2, §8, §10)

- Status: **SEALED** — covered by `MANIFEST.sha256` (analysis-plan §10); verify with
  `python3 tools/seal-manifest.py experiments/ev-005 --check`. Post-sealing changes follow the §10 amendment
  procedure only. This document specifies the run harness for all arms and
  cells: replica provisioning, prompt assembly, the declaration/delivery measurement layer, the
  W gate, budget enforcement, the audit log schema, and the environment digest. The pilot's
  §7 order-guarantee check is verified against the audit log this spec defines.
- Implementations must follow this spec exactly; any deviation discovered after a run starts is
  an infrastructure-integrity failure (§7). Under amendment A-3.2 both cells execute on one host
  (environment-digest); the **registered** runner is the main-cell operator's implementation, and
  the host operator's independent second implementation is retained to cross-check a sample of
  runs on the same host and the same inputs.

## 1. Run lifecycle

1. **Replica provisioning.** History-zero export of the task's `pre_fix` tree (same construction
   as `tools/validate-task.sh` `build_replica`: `git archive` of the sealed SHA, fresh `git init`
   + single snapshot commit with the run-local identity `ev005 <ev005@local>`). The task sheet is
   placed as `task.md`; **the sealed gate is materialized exactly as `tools/validate-task.sh`
   materializes it — the script as `.ev005-donecheck.sh` at the replica root and its fixtures, if
   any, as `.ev005-fixtures/` — and no other copy of the gate is placed.** All of this is
   **byte-identical in all three arms** (frozen visibility ruling).
   *Rationale (amendment A-1): every R11 admission result in `tools/validate-logs/` was produced
   under that layout, 17 of the 35 sealed gates hardcode `.ev005-fixtures/` paths, and six
   exclude `.ev005-*` from repo-wide sweeps. Prescribing any other layout would run gates in a
   configuration that was never validated — measured on p02's fix tree: exit 0 under this layout,
   exit 1 under a root-`donecheck.sh` layout. Making the validated layout normative is what lets
   the admission evidence transfer to the runs.*
2. **Runner scaffolding (arm W only).** A `.ev005/` directory containing `deliver.sh` (§4) is
   injected into the replica. This is the enforcement surface — the manipulated variable — not
   part of the task file layout; arms B/B+ receive no `.ev005/`. Rationale: the treatment is
   enforcement; the information surface (readable, executable `donecheck.sh`) is identical in
   all arms. Flagged for non-author review as a design-reading decision.
3. **Prompt assembly** (arm-instructions.md): `<task.md> + <shared budget block> + <arm text>`,
   byte-exact, nothing else injected, identical model parameters across arms within a cell.
4. **Run environment — the container is the *task execution sandbox* (amendment A-2).** Every
   action the agent takes on the task — reading and writing files, running commands, running the
   repository's own tests, invoking `.ev005-donecheck.sh` — executes inside the digest-matching
   container (§6) with a per-run `HOME` and `TMPDIR`, run-local git config
   (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null` for every git/donecheck/pipeline
   invocation — workstation hooks excluded by construction), and **no network reachable from
   inside it** (`--network none`): the agent has no web, no `gh`, no package fetch, no route to
   anything.
   The **model/controller process runs on the host** and drives the sandbox through the registered
   exec bridge (§5c, amendment A-3.1: exactly one MCP tool, `sandbox_exec`, with every built-in
   tool disabled — because the harness's built-in tools otherwise execute on the *host*, where the
   source repository's git history contains each task's fix commit).
   Its provider transport is harness infrastructure, not an agent capability
   — the agent cannot address it, cannot reach the provider, and gains nothing from its
   existence. *Rationale (A-2): the earlier wording ("each run executes inside the sealed
   environment … network blocked") admitted a reading under which the model process itself had
   to live in a networkless container, which is unsatisfiable — the crossover-cell operator
   demonstrated that `api.anthropic.com:443` fails at DNS under `--network none`, and the three
   escape routes (enable container networking / run the model on the host / pick a transport)
   are each an unregistered experimental condition. The property the experiment actually needs is
   that **the agent's reachable surface is sealed and identical across arms**, which this
   wording states directly.*
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
   analysis-set tasks carry `timeout_s = 1800` with measured full gate runs of 663–716 s
   (recomputed from `tools/validate-logs/{t01,t07,t30}.log`; t30's pre-tree runs fail in 1–2 s
   and are excluded from the range — a delta seat found this document previously carried two
   different ranges for one measurement), so an
   unpaused clock would charge W — which must pass through the gate to end a run — up to ~35 of
   its 45 minutes on three tasks, while charging B least. That cost is correlated with the
   treatment and would confound the primary contrast. Each run's audit-log trailer publishes
   `wallclock_s` (agent time, the budgeted quantity), `paused_s` (total verification time), and
   their sum, so the accounting is auditable per run and per arm rather than asserted.
   Verification time is **not** itself a budget: the per-invocation bound is the task's
   `timeout_s`, fail-closed, and the 5-declaration limit bounds how often the gate can run.
   **What the budget is, exactly (amendment A-3.4).** Budgeted agent wall-clock =
   *controller process elapsed time* − *the registered `donecheck_invocation` pause intervals*,
   **and nothing else**. Provider queueing, retries, backoff, throttling and reconnects are
   therefore *inside* the budget. This is a validity requirement, not a scheduling convenience:
   if provider waiting were free, an arm that makes more model turns would receive more effective
   model time — and W, which must iterate through a gate to deliver at all, is exactly the arm
   that makes more turns. Excluding provider wait would hand the treatment arm extra compute,
   correlated with the treatment. The §5 trailer publishes the wait components per run; the
   per-arm distribution of `provider_wait_s` is reported, and if the arms differ materially that
   is reported as a limitation on budget comparability rather than adjusted away.

## 2. Declaration measurement layer (all arms)

- The wrapper scans the **agent output stream** line-by-line for the sealed markers
  (arm-instructions.md matcher): `DONE-DECLARE` (B/B+ declarations), `ABANDON-DECLARE` (all
  arms). Exact-line match, case-sensitive, no surrounding characters. The wrapper does not
  attempt fenced-block discrimination (conservative branch of the sealed matcher: every
  matching line counts).
- **What "the agent output stream" is, registered (amendment A-3.7).** The stream is the sequence
  of **assistant text events** emitted by the harness under `--output-format stream-json
  --verbose` (§5b), taken in arrival order and split on newlines; the sealed exact-line rule above
  then applies unchanged to those lines. This is a registration of the measurement channel, not a
  change to the matcher.
  *Rationale — measured on the registered host and build (CLI 2.1.132), because a review seat
  observed that the previously registered argv could not support this section at all.* Under the
  **default** output format the harness emits only its final message: given a prompt asking for
  three separately-emitted lines, stdout carried `MARK-1` alone — `DONE-DECLARE` and the line
  after it were **lost**, so declarations would have been undercounted and B/B+ scoring would have
  been wrong in a way nothing in the log would reveal. Under `stream-json --verbose` the same run
  yields one event per assistant message in arrival order, and a tool-using run interleaves them
  correctly: `…text='I'll run the first command.'` → tool turn → `…text='DONE-DECLARE\n\nNow
  running the second command.'` → tool turn → `…text='MARK-3'`. That interleaving is precisely the
  "a declaration is a claim, not an exit" behaviour §1.5 requires of B and B+, and it is not
  observable in any other registered format.
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
(snapshot commit of the provisioned tree), `env_fingerprint` (§6), `start_ts`, and — amendment
A-3.3 — the concurrency identity of the run: `worker_id`, `account_id` (a non-secret provider
seat label from the sealed pool; the runner fails closed if it resembles a credential),
`block_id`, `slot_index`. The header also carries `agent_argv` (the realized agent command line,
with the prompt file path rather than the prompt bytes) and `mcp_config_digest` (amendment A-3.1),
so the enforced tool surface of each run is a record rather than a claim.
Event records (`ts` monotonic + wall, `seq`):
- `declaration` — `marker` (`DONE-DECLARE` | `deliver`), `snapshot_sha`, `scored` (bool),
  `count_after`.
- `declaration_excess` — as above, `scored=false`.
- `abandon` — snapshot optional; ends run.
- `donecheck_invocation` — `invoker` (`agent`|`gate`|`pipeline`), `tree_sha` (if determinable;
  for agent invocations the wrapper records the working-tree dirty state), `exit`,
  `stdout_digest` (SHA-256), `duration_ms`. Agent invocations are detected from
  wrapper-observed process execution of `donecheck.sh` in the replica; B-arm spontaneous use is
  reported from these events (§8 of the plan). **Registered boundary of "execution" (revision
  round 2):** an invocation is counted when a traced process executes the exact replica gate as
  its script operand under a trusted shell identity. In-process sourcing (`source <gate>`) and
  stdin-fed shells (`bash -s < <gate>`) execute the gate's *content* without a gate-operand
  process; they are classified as **read-equivalents** — not counted, and not budget-paused
  (§1.6), in every arm alike. H-2's stratification and the B-arm spontaneous-use report are
  therefore statements about *operand executions*; a run that only ever sources the gate
  contributes to `donecheck_read` coverage (best-effort), not to invocation counts. This is a
  measurement-boundary registration, symmetric across arms, made before any data exists.
- `donecheck_read` — best-effort observable reads of `donecheck.sh` (wrapper-observed file
  opens where the cell's sandbox exposes them); **coverage is best-effort and stated as such**
  (limitation recorded; the H-2 stratification uses `donecheck_invocation`, which is reliable,
  not `donecheck_read`).
- `operator_intervention` — `reason`, free text, mandatory for `operator_abort` coding.
- `canary_check` — sealed canary rule id, `hit` (bool), scope (context|output).
- `gate_resource_sample` (amendment A-3.3; this sentence is the same rule as
  `environment-digest.md`'s, stated once with its numbers — a delta seat found the two files
  previously described the trigger differently) — recorded at **every** `donecheck_invocation`,
  whichever invoker and whichever arm: the worker cgroup's `nr_throttled` and `throttled_usec`
  (CPU) and `memory.events` `oom_kill` (memory), sampled immediately before and after the
  invocation, with deltas and the invocation's wall-clock. A run is void for INFRASTRUCTURE if,
  during any `donecheck_invocation`, `throttled_usec` increases by more than 1% of that
  invocation's wall-clock duration, or `oom_kill` increases at all. Unreadable counters are
  published as `null`, never `0`, and a `null` sample can never satisfy the void criterion —
  but a `null` sample in the pilot fails the `main_blocks_concurrent` condition
  (`environment-digest.md`). On a void, the **whole block** — all three arms — is re-executed
  once, concurrently, under the same block assignment (same seat, same cores policy); all
  attempts of all arms remain in the log; the re-executed block's attempts are the scoring
  attempts; a second void in the re-executed block stops that block without replacement,
  operator-visible. The criterion never inspects the run's outcome, so it cannot act
  asymmetrically on the arms by way of their results.
- Trailer: `end_ts`, `end_reason` (`delivered`|`wallclock`|`abandon`|`operator`),
  `declarations_scored`, `wallclock_s` (agent time — the budgeted quantity), `paused_s` (total
  verification time carved out per §1.6), `elapsed_s` (their sum). Publishing all three makes
  the §1.6 carve-out auditable per run and per arm rather than asserted.
  Amendment A-3.4 adds `provider_wait_s`, `provider_retry_count`, `provider_throttle_count` and
  `provider_longest_stall_s`. **Provider waiting is inside the budget** (§1.6), so these are
  published to make that arithmetic checkable, not to remove it. **Source (A-3.7 / revision
  round 2):** the metrics are aggregated from the registered stream's `api_retry` events
  (count; sum of `retry_delay_ms`; count with `error_status` 429/529; max delay). With the
  stream present, zero `api_retry` events is a **measured zero** and is published as `0`; when
  the stream itself was unavailable or unparseable the metrics are `null` — never a fabricated
  `0`, which would assert a measurement that was not made. A `null` here is also an
  infrastructure-integrity signal for the run (the registered channel was broken).

## 5b. Agent harness and model invocation (sealed, amendment A-2)

The model identity and its invocation are outcome-relevant and are therefore registered, not
left to the operator:

| | main-series cell | crossover cell |
| --- | --- | --- |
| model id | `claude-sonnet-5` | `claude-opus-5` |
| agent harness | Claude Code CLI | Claude Code CLI |
| harness version | 2.1.132 | 2.1.132 |
| harness path | `/home/admin/.local/bin/claude` | `/home/admin/.local/bin/claude` |
| role | the confirmatory series (all three arms) | descriptive crossover only (§2) |

- **Identical within a cell across arms.** Model id, harness version, and every sampling or
  configuration parameter are byte-identical for W, B+ and B within a cell; only the sealed arm
  text and the enforcement mechanism differ. This is what the primary contrast requires.
- **Identical across cells except the model id (amendment A-3.2).** Both cells run on one host,
  one architecture, one image, one harness build and one runner. Results are still not pooled —
  the confirmatory contrast lives entirely inside the main-series cell and the crossover carries
  no α claim (§4) on a different task list — but the crossover's model comparison is now a
  comparison of models rather than of model, machine, architecture, container host and harness
  version at once. The main-series harness version therefore changed from 2.1.220 to 2.1.132;
  that is a registered change, not drift.
- **Closed set (amendment A-3.5).** Only these two model ids may execute runs. Substituting any
  other model or harness — under load, as a fallback, or for any other operational reason — is an
  infrastructure-integrity failure (§7). **Fable is inadmissible in any role**, by owner decision
  of 2026-08-16.
- **Enforced agent configuration (amendment A-3.1).** The runner **constructs** the agent command
  line from registered values; it is not supplied by the caller, by an environment variable, or by
  any config file the runner does not itself write:

      --model <registered id>  --tools ''  --strict-mcp-config
      --mcp-config <runner-written file>
      --allowed-tools mcp__ev005-local-exec__sandbox_exec
      --output-format stream-json  --verbose      (the §2 measurement channel)
      --debug-file <runner-private path>          (raw provider-transport evidence, retained;
                                                   the §5 provider metrics are derived from the
                                                   stream's api_retry events — A-3.7)
      --dangerously-skip-permissions  -p            (prompt on stdin, §1.3)

  `--tools ''` removes every built-in tool, and MCP tools survive it, so the agent holds exactly
  the one sandbox tool of §5c and nothing that executes outside the container. The runner fails
  closed if the constructed line lacks any element of this set, if a caller-supplied argv differs
  from it, or if **any** cell fails its live harness identity probe.
- **The check is on the realized tool list, not on the argv string (amendment A-3.7).** A review
  seat observed that validating the command line only proves what was *asked for*. Under
  `stream-json` the harness's first event publishes what it actually granted, so the runner
  asserts on that and aborts before the agent acts if it differs from the single registered tool:

      {"type":"system","subtype":"init", … ,"tools":["mcp__ev005-local-exec__sandbox_exec"], …}

  Measured on the **registered** build (CLI 2.1.132) for **both** registered model ids, against a
  probe MCP server: asked to use `Bash`, each model replied `NO_BASH_TOOL`; asked to call the
  single MCP tool, each reached it; and the init event's realized tool list was exactly
  `['mcp__probe__probe_exec']` with `mcp_servers: ['probe']` — no built-ins, nothing extra. (An
  earlier author measurement on CLI 2.1.224 is superseded by this one: a seat correctly objected
  that the enforcement had not been measured on the build the experiment actually runs.)
- **Recorded per run.** The audit-log header carries `model_id`, `env_fingerprint`, the realized
  `agent_argv` and `mcp_config_digest`, so a drift between this table and reality — including a
  quietly re-enabled built-in tool — is detectable post hoc rather than assumed away.
- **Controller isolation (registered, A-3 revision round; scope stated at the width of the
  evidence — a delta seat found the earlier sentence wider than what the check proves).** The
  controller process loads no workstation configuration: each provider seat is an isolated,
  empty-provisioned harness configuration directory (`environment-digest.md`). Three mechanical
  guards (digest scope per amendment A-5: the configuration-sensitive subset registered in
  `environment-digest.md`, not the whole stateful directory): (a) the preflight check
  `C-HOST-SUBPROC` runs a real controller session — startup plus
  one registered-tool turn — under host-side process tracing and fails if any host subprocess is
  spawned beyond the registered MCP server, the docker client, and the harness's **registered
  controller-intrinsic startup probes** (amendment A-4: a closed allowlist pinned by executable
  identity and exact argv, with the bundled-`rg` scans path-constrained to the seat
  configuration directory and the controller's runner-private working directory; allowed probes
  are recorded in the preflight artifact, and a new probe from a future harness build fails the
  check until registered by amendment). A stub probe mode exists for containerized unit tests
  only; the registered preflight is the real session, the probe mode actually used is recorded
  in the artifact, and a run may proceed only on a real-mode pass; (b) each run's
  `env_fingerprint` includes the controller config digest, **compared fail-closed at run start
  against the preflight-recorded value for that seat** — a mismatch aborts the run before the
  agent acts; (c) `--strict-mcp-config` covers MCP servers. What this does and does not prove:
  a configuration that executes host commands at startup or on a tool turn fails at preflight; a
  configuration planted after preflight is caught by the digest comparison at the next run
  start; the controller is **not** traced during the 45-minute run itself, and that residual is
  registered here rather than papered over.
- **Topology.** Host: model/controller process, wrapper, audit log, sealed gate bytes. Container:
  the replica and everything the agent does to it, networkless. The channel between them is §5c;
  the agent can invoke it, but cannot address the host, the Docker socket, the container name, or
  any runner-private path through it.

## 5c. The exec bridge (sealed, amendment A-3.1)

A-2 required that everything the agent does to the task happen inside the container while the
model runs on the host, and named "the runner's local exec channel" without specifying it. The
registered harness does not supply such a channel: Claude Code executes its built-in tools in the
**host** namespace — measured by the crossover operator on the VPS (CLI 2.1.132) and reproduced
independently by the author on a different host and build (CLI 2.1.224). Left unspecified this was
not a gap in prose but an open contamination path: the host holds the source repository, whose git
history contains the fix commit each task asks the agent to produce, so an agent holding host-side
file tools can read the answer.

The channel is therefore registered here, and enforced by §5b:

- **Exactly one tool**, `sandbox_exec`, served by a runner-owned stdio MCP server named
  `ev005-local-exec`. Input schema: `command` (string, required), `timeout_s` (number, optional).
  Output: combined stdout and stderr as text, plus the exit code.
- Each call runs `docker exec` into the run's digest-matching `--network none` container, as the
  unprivileged run user, with the working directory at the replica root and a fixed environment
  (run-private `HOME`/`TMPDIR`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`).
- **Nothing about the transport is reachable from inside the sandbox**: no Docker socket, no
  container name, no runner-private path, no host mount the agent can write through.
- Identical in all three arms and both cells. It is not a manipulated variable.

**Registered as a limitation.** Under this configuration the agent works through a single shell
channel and does not hold Claude Code's native `Read`/`Edit`/`Glob`/`Grep` tools, and the tool's
name and description disclose that it is operating in a sandbox. Both properties are constant
across arms, so neither can **differ** between arms — but constancy does not rule out
**effect modification**: the size of the enforcement effect measured through one sandboxed shell
tool may differ from the size the same enforcement would have under the native toolset (a delta
seat corrected the earlier "cannot produce the contrast" phrasing, which conflated the two).
Both properties bound generalization: this experiment measures an agent operating through one
sandboxed shell tool, **not** stock Claude Code in its default configuration; the §9 report must
not be written as though it did, and must carry the effect-modification caveat explicitly.

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
  (image digest + cell id + per-run HOME path + wrapper SHA + realized agent argv + MCP config
  digest + controller config digest + SHA-256 of the MCP server source and of the tool
  name/schema/description strings — the last two added in revision round 2 because the tool
  description is instruction text the agent reads, and unsealed instruction text must not be
  able to drift silently) so drift is detectable post hoc.
- **Concurrency (amendment A-3.3).** Runs are no longer serialized. `environment-digest.md`
  registers the policy in full — disjoint non-oversubscribed CPU sets per worker, memory cap,
  swap off, private tmpfs; `pilot_blocks_concurrent = 5` with `main_blocks_concurrent` set from
  the pilot by a rule fixed before the calibration is read; an arm-blind cgroup-throttling void
  rule; and the block-based assignment that makes arm **exactly** balanced across worker slots and
  holds the provider seat constant within a block. This spec's contribution is the record:
  `worker_id`, `account_id`, `block_id`, `slot_index` in the header (§5) and
  `gate_resource_sample` at every gate invocation.
- Per-run `HOME` is run-private and passwd-consistent by construction (this is the
  runner-layer guarantee referenced by the t12 REV4 isolation exemption). R11 validation of
  suite-invoking donechecks is executed in the same container class (validation-environment
  fidelity), so the gate durations measured in `tools/validate-logs/` — 663–716 s full-run range
  for the three `timeout_s = 1800` tasks (§1.6 carries the same number; fast-fail pre runs
  excluded) — transfer to the pilot's budget arithmetic under §1.6.
- **Run-identity re-validation (A-3 revision round, closing a two-seat finding).** The sealed
  R11 evidence was earned executing gates as uid 0 with `HOME=/root`; runs execute gates as the
  unprivileged run user (uid 1000 `ev005`, `HOME=/home/ev005`). Three representative gates —
  `p02`, `t22` (suite-invoking), and `t01` (`timeout_s = 1800` class) — were re-executed on the
  registered host, inside the registered amd64 image, under the run identity and the agent
  container's capability profile: verdicts identical to the sealed logs (pre FAIL 5/5, fix
  PASS 5/5, R7 clean), t01 gate wall-clock 782–791 s on the registered host (within budget
  margin). Evidence record: `C4-execution-evidence.md` in the review packet; re-validation logs
  retained by the author. The remaining 32 task gates rely on the sealed uid-0 validation plus
  this three-task identity bridge; any gate that fails at run time for an identity-dependent
  reason codes `check_bug` under §3.1 adjudication, which is the registered safety net for the
  unbridged remainder.

## 7. Failure posture

- Fail-closed everywhere: wrapper crash, snapshot failure, gate timeout, or audit-log write
  failure ⇒ the run is invalid infrastructure-side (`operator_abort` with reason
  `infra-integrity`), never silently rescored. >10% such runs in any arm trips §5 of the plan.
- The wrapper never edits the replica outside `.ev005/` (W) and shadow refs; the agent never
  sees the audit log, the sealed donecheck copy, or the runner's config.
