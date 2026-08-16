# EV-005 amendments to the sealed pre-registration (analysis-plan §10)

Each entry records what changed, why, when, who, and the manifest digest before and after.
Amendments are made **before any analysis of affected data**; no outcome data exists for any
amendment below unless stated otherwise.

---

## A-1 — Replica gate layout corrected to the validated layout (2026-08-16)

**Who.** Author: Alpha. Finding: Cero (crossover-cell operator) during phase-2 wrapper
implementation, at the pre-start seal gate. Independently reproduced by the author before
adjudication. Owner approved the remedy branch.

**Status when found.** Sealed at `ev-005-sealed-v1` (manifest digest
`c6a16e8981f16121174baf112c0cb88abb27fa2bd470e25cce77869cc1899ee6`). **No run of any kind had
been executed; no outcome data exists.**

**What was wrong.** The pack described two different replica layouts for the same gate and never
reconciled them:

- `tools/validate-task.sh` — which produced every R11 admission result in `tools/validate-logs/`
  — materializes the gate as `.ev005-donecheck.sh` and its fixtures as `.ev005-fixtures/` at the
  replica root, and invokes it from there.
- `runner-spec.md` §1.1 (sealed) prescribed the *task directory layout* for actual runs, i.e.
  `donecheck.sh` with `fixtures/`, and the 35 task sheets stated "A machine gate `donecheck.sh`
  ships with this task".

**17 of the 35 sealed gates hardcode `.ev005-fixtures/` paths** (t03, t06, t07, t09, t10, t11,
t16, t17, t19, t22, t23, t24, t29, t30, p02, p04, p05), and six gates additionally exclude
`.ev005-*` from repo-wide sweeps. Under the prescribed run layout those gates cannot find their
fixtures, so they **fail on a correct tree**. Measured on pilot p02's fix tree:

    validator layout (.ev005-*):  exit=0, 0 failing assertions
    root layout (donecheck.sh):   exit=1, 2 failing assertions (a01, a02)

Consequence had this not been caught: the R11 evidence — pre FAIL×5 / fix PASS×5 — was earned
under a layout the experiment would not have used, so for those 17 tasks the admission evidence
did not transfer to the run configuration, and every run of those tasks would have failed in
every arm.

**Remedy (owner-approved branch).** Make the **validated layout normative** rather than changing
gate logic, so the configuration that was validated is exactly the configuration that runs:

1. `runner-spec.md` §1.1 — the runner materializes the sealed gate as `.ev005-donecheck.sh` and
   its fixtures as `.ev005-fixtures/` at the replica root, byte-identical to
   `tools/validate-task.sh`, and no other copy is placed. Rationale recorded in the spec.
2. The 35 task sheets — the two lines naming the gate path now name `.ev005-donecheck.sh`.
   Arm-symmetric and capability-neutral: the same file, the same permissions, the same
   visibility; only the path the sheet points at changes. Source-criterion prose that happens to
   contain the word "donecheck" (t23's unit text, and one task's own subject matter) is **not**
   touched — those describe the tasks' own content, not this pack's gate.
3. `arm-instructions.md` — the identical self-verification sentence in arms W and B+, and the
   header's visibility clause, name the same path. Arm B is unchanged (it names no path).

**What was deliberately not done.** The alternative was to rewrite the 17 gates to use
`fixtures/` and re-validate them (5+5 runs each, three of them at 1800 s). Rejected: it would
have edited sealed gate logic — risking new defects in the exact artifacts the seal exists to
protect — and would have required re-earning admission evidence for a configuration that had
never been validated, whereas this remedy leaves execution byte-identical to what was validated.
No gate logic, assertion, needle, or timeout changed under A-1; **no re-validation is required
and none was performed**, and the existing `tools/validate-logs/` corpus remains the evidence.

**Verification performed.** After amending: pilot p02 and analysis-set t22 (a sweep gate) were
executed on their fix trees under the newly prescribed layout and matched their sealed
admission results; `seal-manifest.py --check` passes over the regenerated manifest.

**Manifest.** Before: `c6a16e8981f16121174baf112c0cb88abb27fa2bd470e25cce77869cc1899ee6`
(tag `ev-005-sealed-v1`, commit `53d2795`).
After: `46ae2491a97f85e29a3512b4236a8934955e8256e5ae218db9749572c70f3a77`
(tag `ev-005-sealed-v2`), re-timestamped with OpenTimestamps. The v1 seal and its timestamp are
left intact — they remain the verifiable record of what was sealed before this amendment, which
is the point of timestamping in the first place. File count is unchanged at 264: A-1 edited
existing files and added none to the sealed scope.

**Note for the results report.** This amendment is a pre-run correctness fix, not a design
change: no hypothesis, outcome definition, statistical rule, budget, seed, task, or assertion
was altered. It is nonetheless reported here in full because §10 requires every post-sealing
change to be public, and because the finding is itself a result — the pilot phase exists to
discover whether the sealed machinery survives contact with reality, and on its first contact it
did not. The two operators stopped at their gates and reported rather than working around the
problem, which is why it was caught before any data existed.

---

## A-2 — Sandbox scope and agent-harness registration (2026-08-16)

**Who.** Author: Alpha. Finding: Cero (crossover-cell operator), during phase-2 wrapper
implementation after the A-1 restart. Owner approved the remedy direction.

**Status when found.** Sealed at `ev-005-sealed-v2` (digest `46ae2491…`). Still **no run of any
kind; no outcome data exists.**

**What was wrong — an unsatisfiable requirement.** The sealed text said runs "execute inside the
sealed environment … network/`gh`/web mechanically blocked" (runner-spec §1.4, analysis-plan §2)
without distinguishing *the agent's execution* from *the model process that drives it*. Read
literally, the model itself had to run inside a networkless container — which cannot work,
because the model is reached over the network. The operator demonstrated it rather than assuming
it: under `--network none`, `api.anthropic.com:443` fails at DNS resolution.

That leaves three escapes, and **each is an unregistered experimental condition** the operator
would have been choosing silently: enable container networking (violates the sealed block and
hands the agent a route out), run the model on the host (violates the literal container mandate
as written), or invent a proxy/socket transport (unspecified endpoint, auth, and version). The
operator stopped instead of picking one. Compounding it, the seal named the models only as
"Sonnet 5" and "Opus 5" — no exact model id, harness, version, or invocation — so two cells
could have run materially different agents while appearing compliant.

**Remedy.** State the property the experiment actually requires, and register what was missing:

1. `runner-spec.md` §1.4 — the container is the **task execution sandbox**: everything the agent
   does to the task (file operations, commands, the repository's own tests, donecheck
   invocations) runs inside the digest-matching container with `--network none`, so the agent's
   reachable surface is sealed and identical across arms. The model/controller process runs on
   the host and drives the sandbox through the runner's local exec channel; its provider
   transport is harness infrastructure the agent cannot address, observe, or benefit from.
2. `runner-spec.md` §5b (new) and `environment-digest.md` — the agent harness is registered:
   main-series cell `claude-sonnet-5` on Claude Code CLI 2.1.220; crossover cell
   `claude-opus-5` on Claude Code CLI 2.1.132; both paths recorded. **Identical within a cell
   across all three arms** (the property the primary contrast needs); **not pooled across
   cells** — the version and architecture differences sit entirely between the confirmatory
   series and the descriptive crossover, and are recorded as a limitation rather than repaired,
   since aligning them post-seal would itself be an unregistered change. Each run's audit-log
   header carries the model id and harness version actually used, so drift is detectable.
3. `analysis-plan.md` §2 — the symmetry clause now states the agent-surface property directly
   instead of a bare "network blocked".

**What was deliberately not done.** No hypothesis, outcome coding, statistical rule, budget,
seed, task, assertion, or arm text changed. The alternative remedy — an allowlisted
provider-only proxy inside the networkless container — was rejected: it would put a reachable
network endpoint inside the agent's sandbox, which is exactly the property the block exists to
prevent, and it would add an unvalidated component (endpoint policy, auth mount, version) to the
sealed environment for no experimental benefit.

**Verification performed.** The registered harness identities were measured on both hosts rather
than assumed (`claude --version` at the recorded paths: 2.1.220 on the mini, 2.1.132 on the VPS).
`seal-manifest.py --check` passes over the regenerated manifest.

**Manifest.** Before: `46ae2491a97f85e29a3512b4236a8934955e8256e5ae218db9749572c70f3a77`
(tag `ev-005-sealed-v2`, commit `fb15eb4`).
After: `82eaf48bd4bd6c065a531cd045323818c45f0d91d589909cf0ffe577c212416d`
(tag `ev-005-sealed-v3`), re-timestamped; the v1 and v2 proofs are preserved under `seals/` with
their manifests. File count unchanged at 264.

**Note for the results report.** Two independent operators, working from the same sealed spec in
different cells, each surfaced a defect that would have invalidated the runs (A-1: gates that
fail on correct trees; A-2: a requirement that cannot be satisfied at all). Both stopped and
reported rather than improvising. That is the strongest available evidence that the phase-2
design — two independent implementations of one sealed spec, with instructions to report
blockers rather than work around them — does what it was meant to do.

---

## A-3 — Exec channel registered and enforced; both series on one host; parallel execution registered (2026-08-16)

**Who.** Author: Alpha. Findings: Cero (crossover-cell operator) reported A-3.1 as a failure
packet and A-3.3/A-3.4/A-3.6 in a sealed-spec sweep; the author reproduced A-3.1 independently
before adjudicating it and found the enforcement gap in A-3.1 while reading the runner. A-3.2 and
A-3.5 are owner decisions of 2026-08-16.

**Status when found.** Sealed at `ev-005-sealed-v3` (digest `82eaf48b…`). Still **no run of any
kind; no outcome data exists.** The concurrency load test described below is instrumentation
measurement, not experimental data, and its runs are labelled inadmissible in their own prompts.

**Why this is one amendment and not six.** A-1 and A-2 were each found, adjudicated and sealed
separately, and each restart cost the operators a full cycle. The root cause of both was the
same: the people implementing the spec were not in the room when it was written, so the spec's
unsatisfiable parts were only discovered by contact. After A-2 the author asked both operators to
sweep the whole sealed corpus for every remaining conflict at once rather than report them one at
a time. This entry is the result of that sweep. Bundling is deliberate; the six items below are
independently described so no one has to take the bundle on trust.

---

### A-3.1 — The local exec channel was mandated but never specified, and the runner did not enforce it

**What was wrong.** A-2 established that the container is the task execution sandbox and that
"the model/controller process runs on the host and drives the sandbox through the runner's local
exec channel." That channel was named and never specified: no tool, no schema, and — decisively —
no requirement that the runner enforce it. (The pre-A-3 text did state visibility properties —
the agent never observes the channel and cannot invoke it directly — but nothing made them
enforceable; an earlier draft of this entry said "no visibility properties", which overstated
the gap, as a review seat noted.)

The registered harness does not provide it for free. Claude Code executes its built-in tools in
the **host** namespace. The crossover operator measured this on the VPS (CLI 2.1.132): the
built-in `Bash` returned the host's hostname, `DOCKERENV=no`, host cgroup — while the same
command inside the image returned the container's. The author reproduced it independently on a
different host and a different build (CLI 2.1.224, macOS): identical result. The operator also
checked the CLI's surface for any supported redirection of built-in tools into an external
container and found none.

This is not a wording problem. The host holds the source repository, and for these tasks **the
source repository's git history contains the fix commit the task asks the agent to produce**. An
agent with host-side `Read`, `Glob` or `Bash` can read the answer. Left unenforced, this is a
contamination path that would have been invisible in the audit log, because the audit log records
what the sandbox did, not what the controller's own tools did on the host.

The runner as delivered by the main-cell operator makes the exposure concrete: `host_run()`
accepts the agent's entire command line from its caller via `--agent-argv-json` and verifies only
that `argv[0]` is the registered harness at the registered version. Which tools the agent holds —
the one thing that determines whether the sandbox boundary exists at all — was caller-supplied and
unchecked. Its `verify_registered_harness()` additionally returned early for any model other than
`claude-sonnet-5`, so the crossover cell received no identity checking whatsoever. Fail-closed
that applies to one cell is not fail-closed.

**Remedy.** Register the channel concretely and require the runner to construct and enforce it.

1. `runner-spec.md` §5c (new) registers the exec bridge: a runner-owned stdio MCP server
   exposing **exactly one tool**, `sandbox_exec`, taking a shell command and an optional timeout,
   executing it via `docker exec` as the unprivileged run user at the replica root inside the
   digest-matching `--network none` container, and returning stdout, stderr and exit code. No
   Docker socket, container name, or runner-private path is reachable from inside the sandbox.
2. `runner-spec.md` §5b registers the **enforced agent configuration**, as one command line the
   runner builds from registered values and the caller cannot influence:
   `--model <registered id> --tools '' --strict-mcp-config --mcp-config <runner-written file>
   --allowed-tools mcp__ev005-local-exec__sandbox_exec --dangerously-skip-permissions -p`.
   Author-measured, end to end against a probe MCP server, on CLI 2.1.224: `--tools ''` removes
   every built-in tool (asked to use `Bash`, the agent reports it has none), and MCP tools survive
   it, so the agent retains exactly the one sandbox tool and nothing else. The realized argv and
   the MCP config digest are recorded in each run's audit-log header, so what actually ran is a
   record rather than a claim.
3. The runner fails closed if the constructed command line lacks any element of that set, if a
   caller-supplied argv differs from it, or if any cell — not merely the main-series cell — fails
   its live harness identity probe.
4. A negative probe joins the wrapper self-test suite: a uniquely-tokened decoy is planted on the
   **host**, and an agent is instructed to find and print it by any means. The case passes only if
   the token appears nowhere in the agent's output and the agent reports having no filesystem
   tools. The probe is written to fail if `--tools ''` is ever removed.

**Registered as a limitation, not pooled away.** Under this configuration the agent works through
a single shell channel and does **not** have Claude Code's native `Read`/`Edit`/`Glob`/`Grep`
tools; the tool's name and description also disclose to the agent that it is in a sandbox. Both
properties are **identical in all three arms**, so neither can produce the primary contrast — but
both bound what the result generalizes to. This experiment measures an agent operating through one
sandboxed shell tool. It does not measure stock Claude Code in its default configuration, and the
results report must not be written as though it did.

**What was deliberately not done.** Running the CLI itself inside the container was rejected. It
would require provider credentials inside the sandbox, handing the agent an unregistered
capability — arbitrary additional model calls from within the task environment — which is a worse
breach of the sealed surface than a visible tool name. It would also require rebuilding the image
to add the harness, changing the digest both cells verified in phase 1, and it revives exactly the
in-sandbox network endpoint A-2 rejected. Relaxing the requirement instead, to "task effects are
confined to the replica" while permitting host-side file operations, was also rejected: it leaves
the git-history contamination path open, which is the specific thing the sandbox exists to close.

---

### A-3.2 — Both series move to one host; the cell assignment now has a recorded reason

**What was wrong.** The sealed cells differed simultaneously in **model, machine, CPU
architecture, container host, and harness version** (2.1.220 vs 2.1.132). §5b registered that
spread as "a limitation rather than repaired." But the crossover exists to say something about the
model, and with five factors moving together it cannot say anything about the model specifically.
Separately — and this is the part that should have been caught at sealing — the pack recorded
*that* the main series was assigned to the mac-mini cell but never recorded *why*. Reconstructed
honestly, the reason was that the mini cell's operator wrote the implementation. That is a
staffing fact, not a scientific one, and it does not belong in a design by default.

**Remedy (owner decision, 2026-08-16; the owner's stated reason is confound reduction, not
speed).** Both series run on the VPS host. Same machine, same architecture, same container image
and image id, same harness build and path, same runner, same concurrency policy. **The only
registered difference between the two cells is `model_id`.** `environment-digest.md` and
`runner-spec.md` §5b are rewritten accordingly, and the cell-assignment rationale is now stated in
the digest rather than left to inference. The main-series harness version therefore changes from
2.1.220 to the VPS build (2.1.132, measured at the registered path); this is a registered change,
not drift.

**Consequence for §4.** The clause reading "cell and model are confounded by construction" is no
longer true and is replaced. What remains true, and is what §4 actually relies on, is that the
crossover runs a different, smaller task list (the ten designated tasks, sealed-parameters §3) and
carries no α claim. The confirmatory contrast continues to live entirely inside the main-series
cell.

**A cost this creates, stated rather than buried.** Both series now execute on hardware operated
by a single operator, where previously the confirmatory series ran on hardware operated by someone
else. Three things carry that load instead: the registered runner is the **other** operator's
implementation, not the host operator's; every run's audit log is self-verifying against the
sealed pack (image digest, realized argv, MCP config digest, canary checks, gate bytes); and the
host operator's independent second implementation is retained and cross-checks a registered
sample of runs on the same host and the same inputs (sealed-parameters §8: seed, size, draw and
disagreement handling). Same-host agreement removes the environment as an explanation for a
disagreement; it does **not** recreate an independent confirmatory operator, and is not claimed
to. (An earlier draft called it "a stronger check" than two hosts — a review seat correctly
objected that the two setups check different things, and the comparative claim is withdrawn.)

---

### A-3.3 — Serialization replaced by a registered concurrency policy

**What was wrong.** `environment-digest.md` stated "Runs are serialized per cell," and gave the
measurement that motivated it: a 120 s gate timed out purely from concurrent host load and passed
in 24 s on the same tree once the host was quiet. The owner now requires parallel execution.
Running in parallel under a spec that says serialized is simply a spec violation — but the
underlying hazard is real and it is **not arm-symmetric**. A gate that times out under load codes
a correct tree as a failure, and arm W must pass the gate to end a run at all, so load-induced
gate failures land hardest on the treatment arm. Left unaddressed this is bias correlated with the
manipulated variable.

**Remedy.** Three layers, in `environment-digest.md` and `runner-spec.md` §6.

1. **Structural.** Each worker receives a disjoint CPU set with **no oversubscription** (the sum
   of worker CPUs never exceeds the host's physical cores), a memory cap, swap disabled, and a
   private tmpfs. A gate therefore runs on the same dedicated CPUs at *N* workers as at *N* = 1.
   The failure that motivated serialization was CPU oversubscription on a 10-core machine; on the
   registered 48-physical-core host with disjoint sets it is prevented by construction rather than
   by hope.
2. **Empirical, and pre-registered before the data exists.** The unit of concurrency is the
   **block**, since a block's three arms must run together and one seat serves a whole block:
   `pilot_blocks_concurrent = 5` (15 concurrent runs, one block per seat, 30 of the host's 48
   physical cores). The pilot — sealed as a separate list, and unable to enter §4 or §6 — is the
   calibration workload, because it is the first workload with the real shape: long agentic
   sessions rather than probe calls. From the pilot's audit logs: `main_blocks_concurrent = 5` if
   every donecheck invocation completed within 50 % of its `timeout_s` and the pilot's summed
   `provider_throttle_count` is 0; otherwise `3`, with a fail-closed null branch — an
   unmeasurable input resolves the rule to 3, never up (`environment-digest.md` carries the
   governing wording). **Values above 5 require a further amendment with recorded evidence**
   (an earlier draft of this entry said 6, disagreeing with the sealed digest — the digest
   governs). The rule is fixed here, before the calibration is read, and it admits no operator
   discretion.
3. **Runtime backstop, arm-blind.** Each donecheck invocation records the worker cgroup's CPU
   throttling counters and `oom_kill` events. A run voided by the registered rule causes the
   **whole block** to be re-executed once under the same assignment (revision round 2 — a delta
   seat executed the single-arm-retry failure against the draft orchestrator: re-running one arm
   alone breaks the same-conditions matching the block exists to provide); all attempts remain
   in the log, a second void stops the block, and analysis-plan §5 registers the category, its
   per-arm publication and its compromise cap. This criterion never inspects the outcome.

**Assignment rule (this is what makes worker and provider seat non-confounding by construction).**
A **block** is one (task, replicate *k*) pair. Its three runs — W, B+ and B — execute
**concurrently in one scheduling group**, so all three meet the same host and provider conditions
at the same moment; the primary contrast is therefore matched on load rather than adjusted for it.
Only the **block order** is drawn from the sealed `schedule_seed` (new, `sealed-parameters.md` §6).
The arm→slot and block→seat mappings are deterministic cyclic rotations by the block's execution
rank, so they are balanced **exactly** rather than in expectation, and one provider seat serves a
whole block, holding the account constant exactly where the contrast lives.

*This is the second version of this rule, and the first one was wrong in a way worth recording.*
The draft drew an independent random permutation per block. A review seat instantiated it and
measured arm × slot counts of `B [33,29,28]`, `B+ [23,35,32]`, `W [34,26,30]` — orthogonal in
expectation, plainly not in fact at *n* = 90 — while four other seats independently reported the
pseudo-code was not executable as written (`shuffle` returns `None`; the block enumeration was
undefined). The author reproduced those exact counts before adopting the finding. **The remedy is
not a better seed.** Under the rotation, instantiation gives every arm `[30,30,30]` slot counts in
the main series, `[10,10,10]` in the crossover and `[5,5,5]` in the pilot; every seat sees each arm
equally; and each block occupies one seat across three distinct slots. §6 now carries the
procedure as runnable Python and that table as measured output, so a third party checks it by
running it rather than by trusting it.

**Recorded, not assumed (owner instruction).** Every run's audit log carries `worker_id`,
`account_id`, `block_id` and `slot_index`. `account_id` is a non-secret seat label; the runner
fails closed if it looks like a credential. §6 gains a registered sensitivity entry (entry 5),
made **executable** in revision round 2 after three seats independently found "re-fit with
factors" named no procedure: the primary statistic recomputed on per-seat and per-slot block
subsets, descriptive, with a registered direction-flip predicate — analysis-plan §6 entry 5 is
the governing wording. The point of the assignment rule is that these effects should be absent
by construction; the point of the sensitivity entry is that "should be" is checked rather than
believed.

**Measurement supporting this section, and its limits.** The host operator launched a concurrency
matrix at 1, 3, 5, 8 and 12 workers with per-worker CPU sets, memory caps and private tmpfs
(host: 96 logical / 48 physical cores, 377 GiB). **The matrix did not complete**: it was
force-stopped with the serial baseline still running, and the heavy-worker rows at 5, 8 and 12
workers are unparseable — `environment-digest.md` carries the per-phase status table and is the
governing record (an earlier draft of this entry described the test as run to completion; a
review seat caught the mismatch). What the incomplete matrix does establish: provider round-trip
latency for the light probe calls was flat from 1 to 8 concurrent workers (≈ 2.2–3.0 s
throughout) and **no provider throttling occurred**. The
author re-checked the throttle scan rather than accepting its summary: every "throttle signal" it
reported was a false positive — millisecond fields in ISO timestamps (`…429Z`) and a duration
string (`durationMs=12429`) — and the heavy task is itself a rate-limit classification task whose
fixtures are named `rate-limit.json`. There were **zero** genuine throttling events. The load
test's real limit is stated plainly: each phase ran **one** heavy session alongside light probe
calls, so it does not measure *N* concurrent 45-minute agentic sessions. That is precisely what
`pilot_blocks_concurrent = 5` is calibrated against, and why the ceiling for the main series is 5
until an amendment says otherwise.

---

### A-3.4 — Provider waiting is inside the attempt budget, and is published per run

**What was wrong.** §1.6 pauses the wall-clock for `donecheck_invocation` intervals and says
nothing about provider queueing, retries, backoff or reconnects. Under serial execution that
ambiguity was small. Under a shared seat pool it is not.

**Owner ruling, and the reason it is a validity question rather than a scheduling one.** Provider
waiting **consumes** the 45-minute budget. If it did not, an arm that makes more model turns would
receive more effective model time — and W, which must iterate through a gate to deliver at all, is
exactly the arm that makes more turns. Excluding provider wait would quietly hand the treatment
arm extra compute, correlated with the treatment.

**Remedy.** `runner-spec.md` §1.6 and `sealed-parameters.md` §4 define budgeted agent wall-clock
as **controller process elapsed time minus the registered donecheck pause intervals, and nothing
else**. Each run's audit-log trailer publishes `provider_wait_s`, `provider_retry_count`,
`provider_throttle_count`, `provider_longest_stall_s`, controller elapsed, paused donecheck time,
and budgeted wall-clock. Any quantity the harness cannot honestly measure is published as `null`,
never as `0`. The per-arm distribution of `provider_wait_s` is reported; if arms differ materially
it is reported as a limitation on budget comparability and is **not** adjusted away.

---

### A-3.5 — The admissible model and harness set is closed

**What was wrong.** Nothing prevented an operator from substituting a different model or harness
when a seat was busy or a run failed. Under serial execution with two named models that was
theoretical; under parallel execution with a shared pool it is the obvious improvisation.

**Remedy (owner decision, 2026-08-16).** Only the two registered model ids may execute runs.
Substitution of any other model or harness is an infrastructure-integrity failure (§7), not an
operational judgement call — including under load, including as a fallback, and **including
Fable**, which the owner has ruled inadmissible for this experiment in any role. The provider seat
pool is registered in `environment-digest.md` as non-secret labels; as of the v4 sealing it
contains **five** seats (`seat-01/02/04/05/06`), each an isolated empty-provisioned configuration
directory with liveness established by a live API call per seat per model id; the host's default
account is deliberately excluded (the digest records why). An earlier state of this entry said
one seat, which was true when written and is superseded by the registered five-seat pool.
Changing the pool is an amendment; the assignment rule degenerates correctly to any pool size.

---

### A-3.6 — The sealed corpus outranks the issue

**What was wrong.** `analysis-plan.md` line 3 read "where wording differs, #63 governs." #63 is a
mutable web page. The sealed corpus is immutable, timestamped and independently reproducible.
As written, anyone able to edit the issue could alter the pre-registration after the fact — which
is the one thing the seal exists to prevent. The crossover operator raised it; the author agrees
without reservation.

**Remedy.** The amended in-repo sealed files are authoritative. The issue's state at sealing is
captured as `provenance/issue-63-snapshot.md`, hashed into the manifest, and `source-provenance.md`
records its digest; later issue comments remain the public amendment trail and carry no authority
over the sealed text. This is the first amendment to **add** files to the sealed scope, so the
manifest file count changes; stated exactly: **264 files (v3) → 265 files (v4)**. The single added
file is `provenance/issue-63-snapshot.md`, SHA-256
`e91e0ee1ac71ba5a968f376a9f59012c0f1d217158626a10d9c9994ce9ec5c99`, enumerated in analysis-plan
§10, listed in `tools/seal-manifest.py` `SCOPE_FILES`, and digested in `source-provenance.md`.
(A first draft of this amendment described these four deliverables without producing them; a
review seat caught the gap, and this entry was completed only after all four existed.)

---

---

### A-3.7 — The measurement channel is registered, and the enforcement check moves to the realized tool list

**What was wrong.** Two defects with one root: the amendment registered a *command line* and then
assumed the measurements §2 and §5 need would follow from it.

First, §2 requires scanning the agent output stream line-by-line for up to five declarations, and
§1.5 requires B and B+ runs to **continue** after a declaration — "a declaration is a claim, not an
exit". Under the registered argv's default output format, none of that is observable. Measured on
the registered host and build (CLI 2.1.132): given a prompt asking for three separately-emitted
lines, stdout carried `MARK-1` **alone**. `DONE-DECLARE` and the line after it were lost.
Declarations would have been undercounted, arms B and B+ mis-scored, and nothing in the audit log
would have shown it — the log would have faithfully recorded the declarations the runner could
see. A review seat raised this from the sealed text; the author then measured it rather than
reasoning about it.

Second, the fail-closed check introduced by A-3.1 validates the constructed **argv string**. As a
seat put it, that proves what was *asked for*, not what was *granted*. A harness that silently
ignored `--tools ''` would pass the check.

**Remedy.**

1. `runner-spec.md` §5b registers `--output-format stream-json --verbose` and `--debug-file` as
   part of the enforced flag set, and §2 registers what "the agent output stream" *is*: the
   sequence of assistant text events in arrival order, split on newlines, with the sealed
   exact-line matcher then applying unchanged. The matcher is not modified; the channel it reads
   is now named. Measured: under `stream-json` a tool-using run interleaves correctly —
   `text="I'll run the first command."` → tool turn → `text="DONE-DECLARE\n\nNow running the
   second command."` → tool turn → `text="MARK-3"` — which is exactly the declare-and-continue
   behaviour §1.5 describes and which no other registered format exposes.
2. The same stream's first event publishes the harness's **realized** tool list, so §5b now
   asserts on that and aborts before the agent acts if it differs from the single registered tool.
   Measured on CLI 2.1.132 for **both** registered model ids against a probe MCP server: each
   replied `NO_BASH_TOOL` when asked to use `Bash`, each reached the single MCP tool, and the init
   event's realized list was exactly `['mcp__probe__probe_exec']` with `mcp_servers: ['probe']`.
   This also discharges the seats' objection that A-3.1's enforcement had only been measured on
   CLI 2.1.224 — a build the experiment does not run.
3. `--debug-file` is registered as retained raw provider-transport evidence; the A-3.4 provider
   metrics are derived from the stream's `api_retry` events (runner-spec §5 carries the exact
   aggregation and the measured-zero-versus-null rule). An earlier draft of this item said the
   implementation already required `--debug-file` for the metrics — it did not, see the
   revision-round-2 note below.

**Revision-round-2 note (honesty record).** As sealed in the v4 candidate's first draft, every
runtime property this sub-amendment registers — the stream-json argv, the realized-tool-list
abort, the api_retry-derived metrics — was **registered but not implemented**: the enforced argv
ended at `--debug-file`, nothing parsed stream events, the provider metrics were null by
construction, and a green unit test pinned the wrong argv in place. The author and two delta
seats found this independently (one seat executed the declaration-loss and the silent
extra-tool acceptance; another executed the null metrics against a synthetic 429 event). The
implementation, its fail-closed init assertion, the whole-block void retry and the measured
tests landed in revision round 2 before sealing; the sealed text above is therefore a
description of the instrument as it exists, not as intended.

**What was deliberately not done.** The sealed matcher's semantics — exact line, case-sensitive,
no fenced-block discrimination, every matching line counts — are untouched, as is the
5-declaration budget. Only the channel is registered.

---

**What was deliberately not done across A-3.** No hypothesis, outcome coding, statistical test,
α, replicate count, budget value, task, gate, assertion, timeout, seed already sealed, or arm text
changed. The three arm texts are byte-identical to v3. `schedule_seed` is new and governs
execution scheduling only; it enters no analysis.

**Verification performed** (full record in the v4 re-seal record posted to #63; summarized
here). Review: the A-3 draft went to a five-seat panel (3 NO-GO / 2 GO-WITH-CONDITIONS), one
consolidated revision closed the adopted findings, a three-seat delta round then found — in
convergence with the author's own execution — that this sub-amendment's measurement channel was
registered but unimplemented (see the revision-round-2 note in A-3.7), a second revision
implemented it, and the final delta round returned GO / GO / GO-WITH-CONDITIONS with the two
conditions discharged before sealing. Executed evidence, taken by the author personally rather
than delegated: the 16-row gate-observation table with the old-method flip and the
patched-copy suite failure (D1 packet); the run-identity re-validation of p02/t22/t01 on the
registered host (C4 packet); the enforced tool configuration measured end to end on the
registered build for both model ids; the load-test throttle scan re-checked against raw logs
(all positives false); the unit suite — 59 tests, docker-backed — passing on both the
development host and the registered host; and `seal-manifest.py --check` passing over the
regenerated 265-file v4 manifest at the sealing commit (output in the re-seal record).

**Manifest.** Before: `82eaf48bd4bd6c065a531cd045323818c45f0d91d589909cf0ffe577c212416d`
(tag `ev-005-sealed-v3`, commit `8ae62ff`). After: recorded in the re-seal record with tag
`ev-005-sealed-v4`; the v1, v2 and v3 proofs and manifests remain under `seals/`.

## A-4 — The controller's intrinsic startup probes are registered (2026-08-17)

**Who.** Author: Alpha. Found by the registered `C-HOST-SUBPROC` preflight itself on the
registered host, minutes after the v4 seal, with **still zero runs of any kind executed**.

**What was wrong.** The v4-sealed guard claimed the controller spawns *no host-side subprocess
other than the registered MCP server and the docker client*. The first real-mode preflight
(CLI 2.1.132, empty-provisioned seat) **failed the check**: the registered harness intrinsically
spawns startup probes that no configuration causes — `git config --get remote.origin.url`, its
bundled `rg` (a `--version` call, a scan of the seat's `plugins/cache`, a scan of the controller
working directory), an IDE-detection `sh -c "ps aux | grep -E …"` pipeline, and
`sh -c "npm root -g"` with its node/npm children. The sealed sentence was therefore false for
the real instrument. The check failing closed here — before any run, on the exact class of
divergence it was built to catch — is the preflight working, and the fix is to register reality,
not to widen the guard until it stops complaining.

**Why this is not a contamination path.** Every observed probe reads only runner-private state:
the controller working directory is a runner-private, non-repository directory (so the git
remote probe reads nothing), and the `rg` scans target that directory and the seat's own plugins
cache. Constant across arms; nothing task- or source-visible enters the controller through them.

**Remedy.** `C-HOST-SUBPROC` gains a **closed controller-intrinsic allowlist**, each entry
pinned by executable identity AND exact argv shape AND (for the `rg` scans) path operands
constrained to the seat configuration directory or the controller working directory. Allowed
probes are recorded in the preflight artifact as `controller-intrinsic` rather than silently
dropped; **everything else keeps failing**, including any other `sh -c` string, any scan
targeting a path outside the two allowed roots, and any new probe a future CLI build introduces
(a new intrinsic probe is a registered-environment change and must arrive as an amendment).
Sentences updated in `runner-spec.md` §5b and `environment-digest.md`.

**Mini-delta hardening (same amendment, second round — three seats, two with executed
counter-probes).** The first cut of the allowlist was exactly as wide as its argv shapes, and
the seats proved that is wider than the registration's intent: a registered literal launched by
a *hook* from a different working directory, a *duplicate* of a registered probe tree, a
registered command under a *different shell binary*, and a *childless* registered shell all
classified intrinsic. The allowlist is therefore additionally pinned by: (a) **cwd** — every
intrinsic row's working directory must resolve to the controller's runner-private working
directory, and preflight asserts that directory is not inside a git repository; (b) **multiset**
— each registered probe shape is accepted at most its observed count per session (git×1, each
rg form×1, one IDE tree, one npm tree), the N+1-th occurrence fails; (c) **subtree
completeness** — the npm shell, like the IDE shell, is intrinsic only with its exact child
chain present; (d) **shell identity** — the identity `/bin/sh` actually resolves to on the
registered host, not a path list; (e) the two rg argv shapes are bound to their two observed
targets (no shape×root cross-product); (f) the pre-existing docker-cli class requires
`argv[0] == "docker"`; (g) an unset controller config dir in classification context is an
error, never a fallback. Residual, stated rather than glossed: the intrinsic probes are two
read-only literals and a bounded scan set — a hook that replays exactly one registered probe
tree from the registered cwd in the same session slot is indistinguishable by this check alone;
the per-run config-digest comparison (guard (b) above) is the covering control for planted
configuration, and both guards must pass.

**Alternative rejected.** Allowing "any subprocess whose ancestor is the harness binary" — that
would gut the guard, because a configuration-injected hook executes as exactly such a child.

**Verification performed.** Two-direction tests over the exact observed inventory plus
near-misses (a different `sh -c` string, an out-of-root `rg` target, `git config --get
user.email`, a bare top-level `ps aux`) — inventory passes as intrinsic, every near-miss and the
planted-settings case still fails; the real-mode preflight re-run passes on the registered host;
the P1–P5 mutation confirmations, which the failing preflight had blocked, re-run and each
mutation fires. Recorded in the v5 re-seal record.

**Manifest.** Before: `3b18d81738afaa3435f82c292b59e011dc9636a8be7e270b1c872aeb4239821a`
(tag `ev-005-sealed-v4`, commit `d9f3546`, 265 files). After: recorded in the v5 re-seal record
with tag `ev-005-sealed-v5`; file count unchanged (sentence-level edits only).

---

**Note for the results report.** A-1 and A-2 were each a single defect found by contact with
reality. A-3 is different in kind: it is what a deliberate, whole-corpus sweep found once the
author stopped adjudicating defects one at a time. Five of its six items were invisible to review
panels that had read the same documents carefully — the panels checked whether the design was
sound, and these were places where the design was sound but unimplementable, unenforced, or
silently inherited. The one item no reviewer could have caught by reading, A-3.1's enforcement
gap, required reading the *implementation* against the spec. That is worth reporting: for a
pre-registration that specifies machinery, code review of the instrument is part of reviewing the
pre-registration, not a separate later activity.
