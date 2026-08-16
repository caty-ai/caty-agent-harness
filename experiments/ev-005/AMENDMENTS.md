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
