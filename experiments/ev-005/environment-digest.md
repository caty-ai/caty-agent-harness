# EV-005 environment digest (analysis-plan §2, §10; runner-spec §6)

Status: **SEALED** (covered by `MANIFEST.sha256`). Phase-1 image verification was performed
2026-08-15 by both cell operators against the shipped image artifact; operator reports and the
author's acceptance are in family-vault `20_projects/ev-005/env-prep/{alec,cero}-env-prep.md`.
Amendment A-3 (2026-08-16) moved both series onto a single host; the arm64 image and the
mac-mini host below are retained only as the record of what was verified in phase 1 and are no
longer a run environment.

## Execution host (amendment A-3 — both cells)

Both the confirmatory main series and the descriptive crossover execute on **one host**, so the
only registered difference between the cells is the model id.

| field | value (both cells) |
| --- | --- |
| host OS / arch | Ubuntu 24.04.4, kernel 6.8.0-90 / x86_64 |
| capacity | 96 logical CPUs / **48 physical cores** / 377 GiB RAM / 1.4 TiB free |
| container runtime | Docker Engine 29.3.1 (Community), containerd 2.2.2, runc 1.3.4 |
| image tag | `ev005-validate:v3-amd64` |
| image ID (sha256) | `09fe0422da1342751365965cc8733113cbba9510fc7049c72368da3a299d1b41` |
| base, pinned by OCI index digest | `python:3.12-slim@sha256:dd29372629eeba2dd003fd9e9d35a5b8236c44727875a0364254b5127af88e65` |
| in-image toolchain | Python 3.12.14 / node v20.19.2 / ripgrep 14.1.1 / GNU Make 4.4.1 / git 2.47.3 |
| host operator | Cero |
| registered runner | the main-cell operator's implementation (`runners/alec/ev005/`), by wrapper commit SHA |

**Why the cells were assigned this way (recorded, per A-3.2).** The pre-A-3 pack assigned the
main series to the mac-mini cell but recorded no reason for it; reconstructed honestly, the reason
was that the mini cell's operator wrote the implementation — a staffing fact, not a scientific
one. The owner's 2026-08-16 decision replaces it with a stated reason: with both series on one
host, machine, architecture, container host and harness version stop varying between cells, so the
crossover's model comparison is a comparison of models rather than of five things at once.

**The cost this creates.** Both series now run on hardware operated by one person. Three things
carry that load: the registered runner is the *other* operator's implementation; every audit log
is self-verifying against the sealed pack (image digest, realized agent argv, MCP config digest,
canary checks, gate bytes); and the host operator's independent second implementation is retained
and cross-checks a **registered sample** of runs on the same host and the same inputs
(sealed-parameters §8: seed, sample size, draw procedure and disagreement handling — a delta
seat found the earlier "a sample" unfalsifiable as written).

**Phase-1 record, superseded as a run environment (retained, not deleted).** Main-series cell,
operator Alec: `ev005-validate:v3-arm64`, image ID
`c1859bf00f07c768f91786fe88920d804dc661a1299edd953e72ab710b70c331`, Colima 0.10.1
(Virtualization.Framework), Docker Engine 29.2.1 / CLI 29.5.2, macOS 26.5.2 (25F84) / arm64,
10 cores / 32 GiB RAM. Same pinned base and same in-image toolchain, verified independently.

Distribution rule: images are built once from the pinned Dockerfile, shipped as
`docker save` archives, and `docker load`ed at each cell. **Local rebuilds are prohibited** —
a rebuild produces a different image ID and breaks the digest recorded here.

## Agent harness (amendment A-2, revised by A-3)

The container is the **task execution sandbox**; the model/controller runs on the host and drives
it through the registered exec bridge (runner-spec §1.4, §5b, §5c). Registered identities:

| | main-series cell | crossover cell |
| --- | --- | --- |
| model id | `claude-sonnet-5` | `claude-opus-5` |
| harness | Claude Code CLI 2.1.132 | Claude Code CLI 2.1.132 |
| path | `/home/admin/.local/bin/claude` | `/home/admin/.local/bin/claude` |

Identical within a cell across all three arms, and now identical **across** cells except for the
model id. The main-series harness version changed from 2.1.220 to 2.1.132 under A-3.2; that is a
registered change, not drift. The confirmatory contrast lives entirely inside the main-series cell
(§4); the crossover carries no α claim and runs the ten designated tasks only.

**Closed set (A-3.5).** Only these two model ids may execute runs. Substituting any other model or
harness — under load, as a fallback, or for any other operational reason — is an
infrastructure-integrity failure (runner-spec §7), not a judgement call. **Fable is inadmissible
for this experiment in any role**, by owner decision of 2026-08-16.

**Provider seat pool (A-3.5), as non-secret labels:**

| seat label | subscription | `claude-sonnet-5` | `claude-opus-5` |
| --- | --- | --- | --- |
| `seat-01` | max | live | live |
| `seat-02` | max | live | live |
| `seat-04` | max | live | live |
| `seat-05` | max | live | live |
| `seat-06` | max | live | live |

Five independent provider seats, each an isolated harness configuration directory. Liveness was
established **by a live API call per seat per model id** (all probes returning the expected
token), not by the harness's own `auth status` — which on this host reported
`{"loggedIn": true, …}` for a credential the API rejected with
`401 OAuth access token has been revoked`, and separately reported a stale account identity for a
credential that had been replaced. Any future seat check uses the same rule: a status field is not
evidence of a working seat.

**Why five and not six (owner decision, 2026-08-16).** A sixth authenticated account exists on the
host and is deliberately **excluded** from the pool: it is the account the host's *default*
harness configuration uses, i.e. the one any ad-hoc operator work on this machine consumes.
Including it would let unregistered work outside the experiment add provider load to one pool
member — and because blocks map to seats deterministically, that load would fall on a specific,
identifiable subset of tasks rather than spreading. The pool is therefore reserved for the
experiment. A second, smaller benefit: 90, 30 and 15 are all divisible by five, so seat occupancy
is exactly uniform in **all three** series (with six, the pilot's 15 blocks would have split
9/9/9/6/6/6).

The seat label → account mapping is **operational and deliberately not recorded here**; the
sealed corpus is public and the mapping is personal data. `account_id` in the audit log carries a
label from this table and never a credential; the runner fails closed on anything that looks like
one. Each seat's configuration directory is created empty, so no workstation `CLAUDE.md`, hook,
setting or plugin is loaded into a controller process — the isolation a review seat required of
the host-side controller is a property of how the seats are provisioned, not a promise.

Two mechanical guards keep it a property rather than a promise (registered, A-3 revision round;
scope per runner-spec §5b, stated at the width of the evidence): (a) each run's
`env_fingerprint` includes a **controller config digest** — SHA-256 over the seat configuration
directory's sorted relative paths and non-credential file bytes — recorded at preflight and
**compared fail-closed at every run start**: a seat that acquires a settings file, hook or
plugin after preflight aborts the next run before the agent acts; (b) the preflight check
`C-HOST-SUBPROC` runs a real controller session (startup plus one registered-tool turn) under
host-side process tracing and fails on any host subprocess beyond the registered MCP server and
the docker client. A configuration that executes host commands at startup or on a tool turn
fails at preflight; the controller is not traced during the 45-minute run itself — that
residual is registered in runner-spec §5b rather than glossed here.

## Run invariants (both cells)

- `--init` is **mandatory**. Without it, PID 1 lacks normal signal semantics and suites that
  sweep descendants on SIGTERM fail spuriously (measured: FMA suite 402/403 without `--init`,
  403/403 with it).
- `HOME` is run-private and **passwd-consistent** — the guarantee the t12 r4-1 exemption
  depends on, and the reason runs are container-mandatory: a bare-metal macOS cell cannot
  provide a fresh HOME and passwd consistency simultaneously (upstream evidence: FMA#18).
- Network, `gh`, and web access are unreachable from the sandbox (`--network none`), and the
  agent holds no tool that executes outside it (runner-spec §5b).
- Each run's audit-log header records `env_fingerprint` (image ID + cell id + per-run HOME path +
  wrapper SHA + realized agent argv + MCP config digest + controller config digest) so drift —
  including drift inside the controller's own configuration directory — is detectable post hoc.

## Concurrency (amendment A-3.3 — replaces "runs are serialized per cell")

Serialization was registered because of a measured failure: a 120 s gate timed out purely from
concurrent host load and passed in 24 s on the same tree once the host was quiet. That hazard is
**not arm-symmetric** — a load-induced gate timeout codes a correct tree as a failure, and arm W
must pass the gate to end a run at all — so it is bias correlated with the manipulated variable.
Parallel execution is therefore registered with three layers of protection, not merely permitted.

**1. Structural — no oversubscription.** Each worker receives a disjoint set of **two whole
physical cores** — 4 logical CPUs allocated as SMT sibling pairs read from the host CPU topology
(`/sys/devices/system/cpu/cpu*/topology/thread_siblings_list`), so no two workers share a physical
core (a review seat observed that disjoint *logical* CPU sets can still share physical cores under
SMT, which would break the "a gate runs the same at *N* workers as at *N* = 1" claim) — plus a
memory cap (8 GiB), swap disabled, and a private 8 GiB tmpfs, enforced by cgroup. The sum of
worker cores never exceeds the host's 48 physical cores. A gate runs on the same dedicated
physical cores at *N* workers as at *N* = 1. The failure above was CPU oversubscription on a
10-core machine; here it is prevented by construction.

**2. Empirical — calibrated on the pilot, by a rule fixed before the calibration is read.**
The unit of concurrency is the **block**, not the run, because a block's three arms must be
concurrent (below) and a block is served by one seat. With five seats:

    pilot_blocks_concurrent = 5      (= 15 concurrent runs; one block per seat, so a wave never
                                      places two blocks on the same seat)

15 workers × 2 physical cores = 30 of the host's 48 physical cores, so the no-oversubscription
rule of layer 1 holds with headroom. The pilot is the calibration workload because it is the
first workload with the real shape — long agentic sessions, not probe calls — and because it is
sealed as a separate list that can never enter §4 or §6. Then, read from the pilot's audit logs:

    main_blocks_concurrent = 5   if every pilot donecheck invocation completed within 50% of its
                                 timeout_s, and provider_throttle_count summed over the pilot is 0
    main_blocks_concurrent = 3   otherwise

**Null branch (fail-closed, registered on a delta-seat finding):** a `null` in any quantity this
rule reads — a missing `gate_resource_sample`, an unmeasured `provider_throttle_count` — means
the 5-condition is **not satisfied**: the value resolves to 3, and the measurement failure itself
is reported to the owner before the main series starts. An uncomputable condition never resolves
upward. Values above 5 require a further amendment with recorded evidence. No operator discretion
enters, and the rule is fixed here before the calibration exists.

**3. Runtime backstop — a drift detector, and honest about being one.** Each donecheck invocation
records the worker cgroup's `cpu.stat` (`nr_throttled`, `throttled_usec`) and its own wall-clock as
a fraction of the task's `timeout_s`.

The registered void rule, with its numbers rather than a dangling reference to "the threshold":

    A run is void for INFRASTRUCTURE if, during any donecheck_invocation, the worker cgroup's
    throttled_usec increases by more than 1% of that invocation's wall-clock duration.

Under the registered configuration this counter is expected to be **exactly zero**, because
workers are pinned by cpuset with no CPU bandwidth quota (`cpu.max` unset), and a cgroup without a
quota cannot be throttled. That is the point: this rule does not detect load, it detects that the
**structural** protection above is not actually in place — a worker that acquired a quota, an
oversubscribed cpuset, a configuration that drifted. A reviewer noted that a counter which is
always zero makes a decorative guard; it is registered as a drift detector precisely so that
nobody mistakes it for the load protection, which is layer 1.

Gate wall-clock as a fraction of `timeout_s` is **reported, not a void criterion** — a slow gate
can be a genuinely slow tree, and voiding on it would let an outcome-adjacent quantity remove
runs. It is published per invocation, summarised per arm, and it is the quantity the
`main_blocks_concurrent` rule reads.

On a void, the **whole block** — all three arms — is re-executed once, concurrently, under the
same block assignment (same seat, same cores policy), because the property being protected is
that a block's three arms meet the same conditions at the same moment: re-running one arm alone
would break exactly the matching the block exists to provide (a delta seat executed this failure
against the draft orchestrator). All attempts of all arms remain in the log; the re-executed
block's attempts are the scoring attempts; a second void in the re-executed block stops that
block without replacement, operator-visible — never a third attempt. Voids are counted and
published per arm, and the void rule now also covers `oom_kill` events in the worker cgroup's
`memory.events` during a donecheck invocation (the `/work` tmpfs and the memory cap share
8 GiB, so an OOM-killed gate would otherwise code a correct tree as a failure invisibly).
Neither the criterion nor the count inspects the run's outcome. Analysis-plan §5 registers the
per-arm publication and the compromise cap for this category.

**Assignment rule.** A **block** is one (task, replicate *k*) pair.

- A block's three runs — W, B+, B — execute **concurrently in one scheduling group**, so all three
  meet the same host and provider conditions at the same moment. The primary contrast is matched
  on load rather than adjusted for it.
- Only the **block order** is drawn from `schedule_seed` (sealed-parameters §6). The arm→slot and
  block→seat mappings are deterministic cyclic rotations by the block's execution rank, so they
  are balanced **exactly**, not in expectation: instantiated, every arm occupies every slot
  `[30,30,30]` times in the main series, `[10,10,10]` in the crossover, `[5,5,5]` in the pilot.
- One provider seat serves a whole block: the account is held constant exactly where the contrast
  lives, and **every seat sees each arm equally**.
- Block execution order is the seeded permutation, so drift across the run window aligns with
  neither task nor arm.

**Recorded, not assumed.** Every run's audit log carries `worker_id`, `account_id`, `block_id` and
`slot_index`, and analysis-plan §6 entry 5 re-fits the primary contrast with worker and seat as
factors. The assignment rule is what should make those effects absent; the sensitivity analysis is
what checks it.

**Measurement behind this section, stated at the precision the evidence supports.** The host
operator launched a concurrency matrix and it **did not complete**: the operator's own report
records that it was force-stopped with the serial baseline still running, so **no
serial-versus-parallel duration distribution exists and no timing-distortion threshold has been
located.** What the incomplete matrix does establish, verified by the author against the raw
per-worker logs rather than taken from the operator's summary:

| phase | status at author check | light-probe API time |
| --- | --- | --- |
| preflight, 1 worker | complete | 2.24 s |
| parallel, 3 workers | complete (heavy worker finished in 234 s) | 2.29–3.03 s |
| parallel, 5 workers | light workers complete; heavy worker's result unparseable | 2.34–2.46 s |
| parallel, 8 workers | light workers complete; heavy worker's result unparseable | 2.33–2.97 s |
| serial roster, 12 items | light workers complete; heavy worker's result unparseable | 2.26–2.68 s |
| parallel, 12 workers | reached, not analysed | — |

So: **provider round-trip time did not degrade as concurrent workers went from 1 to 8**, and
**genuine provider throttling events were zero**. The author re-checked the operator's throttle
scan against the raw logs rather than accepting its summary: every reported "throttle signal" was
a false positive — millisecond fields in ISO timestamps (`…429Z`) and a duration string
(`durationMs=12429`) — and the heavy probe task is itself a rate-limit classification task whose
fixtures are named `rate-limit.json`.

Two limits, stated rather than glossed. Each phase ran **one** heavy session alongside light probe
calls, so this does not measure *N* concurrent 45-minute agentic sessions — which is the workload
the experiment actually runs. And the phases that would have shown timing distortion are exactly
the ones whose heavy-worker results are missing. That is why the pilot is the calibration
workload and why `main_blocks_concurrent = 5` is the ceiling until an amendment raises it on
recorded evidence.

## Registered as a limitation

The confirmatory series and the descriptive crossover run the same host, image, harness and runner,
and differ only by model id — but they also run **different task lists** (the crossover uses the
ten designated tasks of sealed-parameters §3). Results are not pooled across cells (§4), and the
crossover carries no α claim. Under A-3.1 the agent's tool surface is a single sandboxed shell
channel rather than Claude Code's default toolset; this is identical in all three arms and so
cannot **differ** between arms — but constancy does not rule out effect modification: the size of
the enforcement effect under this tool surface may differ from its size under the native toolset
(runner-spec §5c carries the governing wording; a delta seat found this paragraph still carried
the pre-revision conflation). It bounds what the result generalizes to.
