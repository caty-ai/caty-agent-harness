# Caty Agent Harness — Engineering Guide

[English](engineering.md) | [日本語](engineering.ja.md) ｜ back to the [front page](../README.md)

This is the technical guide for engineers. It explains what is actually enforced, where, and how. The exact command flags and contract documents live in the [reference](reference.md).

---

## A system around the AI, not a better request to the AI

Asking an AI to "remember everything" or "do not give up" is still only a request inside one conversation. The AI works in a project folder, called a **workspace**. Caty Agent Harness manages work in that folder from outside the conversation with plain files and checks.

`scripts/task-runner.sh` is the script that breaks one job into recorded steps and checks whether it is complete. Only work it manages receives the full completion rail. Other registered automatic paths enforce only their narrower contracts—for example, pausing new work or running scheduled checks and watchdogs—not the whole rail. Ordinary interactive work in Claude Code, Codex, and Kimi uses a short startup instruction (managed bootstrap) and end-of-work reminders (`Stop` hooks; Claude Code also has a `PreCompact` hook); it does not force every rule with the same strength.

Across supported use, the shared work record is:

- A handover notebook (`STATE.md`) holds the current facts, previous failures, and restart point.
- Execution records and outputs show what happened; the next session has a concrete place to restart.

On the full completion rail, `task-runner` additionally enforces:

- A real completion check runs against the requested result instead of trusting a status message.
- Attempt and active-time limits prevent endless effort without progress.
- The next attempt receives the previous failure and is instructed—via the generated step prompt—to take a different recovery approach; what is mechanically enforced is the failure injection itself plus the next rule.
- Repeated identical error classes or no progress stop the work instead of spending effort forever.

That is why this is useful even when you change models or start a new session: the important work record is kept with the workspace, not only in an AI chat.

---

<a id="learning"></a>

## Learning from repeated failures

The **completion rail** means work managed by `scripts/task-runner.sh`. It gives long-running work a recorded route to an honest finish. It is different from ordinary interactive work, where instructions and reminders guide rather than enforce every step.

### On one job: the completion rail

1. Record the failure reason and the evidence that showed it.
2. On the next attempt, include that failure and require a different recovery approach—not the same retry.
3. If errors repeat or work makes no progress, stop rather than continue wastefully.

### Across jobs: carry forward only proven learning

1. A successful check can save a method first as a lesson.
2. Turn that lesson into reusable guidance or a known fact only after the same lesson passes independent verification checks in two different jobs, or when a human explicitly promotes it.
3. At the next similar job, read the confirmed record before acting.

This reduces repeated failures and reuses verified solutions. It does **not** mean "never fail again" or "always succeed."

### The loop, step by step

The front page shows the loop as one diagram; these are the six stages as the design documents name them.

1. **CONSULT** reads the handover notebook (`STATE.md`) and relevant proven lessons.
2. **PLAN** writes down what evidence will count as complete before work starts.
3. **ACT** produces the result and keeps the supporting evidence.
4. **CHECK** (called **VERIFY** in the design documents) runs the mechanical completion check first. Independent review is used only when configured; without it, the mechanical check remains the core. If its verification provider is unavailable, promotion waits rather than falling back to self-review.
5. **REPAIR / LEARN** fixes a finding using the recorded failure, or saves a verified lesson. The evidence-backed organizing of lessons is called **DISTILL** in the design documents.
6. **CHECKPOINT** leaves the next session a trustworthy restart point.

---

## What improves across five AI tools

The same Harness helps each tool in the way that tool can support.

| AI tool | What becomes easier for you |
| --- | --- |
| Claude Code | Keep a handover notebook and completion reminder across session endings, context compaction, and context breaks. |
| Codex CLI | Keep a handover notebook and completion reminder across session endings. |
| Kimi Code CLI | Keep a handover notebook and completion reminder across session endings. |
| Hermes Agent | In addition, use deeper scheduled automation for one-step work, completion checks, retries, and watchdog paths. |
| OpenClaw | Keep outcome-based learning records through distillation (summarizing useful outcomes) and monitoring through its sentinel (scheduled watcher) path. |

The implementation is intentionally asymmetric. The Harness does not claim that every tool has the same built-in ability, and it does not invent missing native features.

---

<a id="quickstart"></a>

## Quickstart (full)

> Installing via your AI agent instead? Hand it [agent-guide.md](agent-guide.md) — it covers runtime selection, the health check, and required follow-up wiring.

Prerequisites for the installer, scaffold, and pause commands: Git and bash 3.2+ on macOS or Linux. Python 3 is required for runtime hooks, `task-runner`, adapter integrations, and fully operational runtime wiring.

```sh
git clone https://github.com/caty-ai/caty-agent-harness.git
cd caty-agent-harness
WORKSPACE="$HOME/your-agent-workspace"
./install.sh --workspace "$WORKSPACE" --bootstrap-runtime codex --append-bootstrap "$WORKSPACE/AGENTS.md"
./install.sh --check --workspace "$WORKSPACE"
```

`codex` and `AGENTS.md` are examples. Set `WORKSPACE` to the existing project folder—or a new folder—where the AI will actually work, **as an absolute path** (the `--append-bootstrap` target must be absolute with an existing, non-symlink parent). Choose the runtime and its instruction file from the runtime table in [agent-guide.md](agent-guide.md#step-1--identify-your-runtime) or the relevant adapter `INSTALL.md`. If that workspace or target instruction file does not exist, this command creates it; initialization creates missing scaffold only.

`--check` is read-only. A healthy required layout ends with:

```text
ok: required layout and STATE.md headers present
```

It also reports optional learning-path rows such as verifier availability or cron wiring. Optional rows can show `FAIL` while the required layout and required `STATE.md` headers are healthy; in that case the exit code is `0`. `FAIL` still means the loop is not fully operational for that runtime: complete the relevant adapter wiring before relying on it. The full flag list is in the [reference](reference.md).

**Quickstart is not the whole installation.** It creates the workspace scaffold and the managed bootstrap. End-of-session checkpoint reminders and deeper automation require the per-runtime wiring in the next section (user-level hook/cron registration); until that is done, only the start-of-task discipline from the bootstrap block is active.

---

<a id="runtime-setup"></a>

## Runtime setup

Start with Quickstart, then complete the runtime-specific integration you chose.

| Runtime | Setup document | Implemented Harness scope |
| --- | --- | --- |
| Claude Code | [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) | managed bootstrap; pause-aware `Stop` and `PreCompact` hook entry points |
| Codex CLI | [adapters/codex/INSTALL.md](../adapters/codex/INSTALL.md) | managed bootstrap; pause-aware `Stop` hook entry point |
| Kimi Code CLI | [adapters/kimi/INSTALL.md](../adapters/kimi/INSTALL.md) | managed bootstrap; pause-aware `Stop` hook entry point |
| Hermes Agent | [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) | managed bootstrap, verifier route, task-runner steps, and cron/watchdog paths |
| OpenClaw | [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) | managed bootstrap, distillation, and sentinel cron paths |

The table is deliberately asymmetric and does not claim identical native capabilities across runtimes.

### Flush intake consumer

The Claude Code `Stop` and `PreCompact` hooks above are producers only: their output is unverified records in `loop/pending/flush-*.md`. A workspace that enables either producer must also schedule the consumer, `adapters/claude-code/flush-intake.sh`, or those records accumulate without ever reaching the governed `STATE.md` fold. The same deterministic consumer may also be used by Codex CLI and Kimi Code CLI workspaces, since their checkpoint hooks emit the same flush format.

Run the consumer two to four times per day: for a LaunchAgent, a `StartInterval` between `21600` and `43200` seconds; a daily schedule leaves no jitter margin at the default deadman threshold. The consumer calls no model, so its scheduler does not need Claude credentials. On macOS, a LaunchAgent in the `gui/<uid>` domain remains the recommended scheduler surface; any tick wrapper or spawn adapter that shells out to the claude CLI must use one, since crontab sessions cannot reach the user Keychain.

Exactly one fold route may run per workspace: this consumer, or OpenClaw's `distill-audit.sh`, never both. The consumer touches `loop/.deadman/distill.marker` itself, only after acquiring the shared STATE lock and finishing without an infrastructure error—a self-marking design. The checked-in cron wrapper (`templates/cron-wrapper.tmpl.sh`) recognizes this exact consumer as self-marking and suppresses its own pre-touch when `DEADMAN_MARKER` names that workspace's `distill.marker`, so an explicit setting cannot hide lock starvation or intake failure; leave `DEADMAN_MARKER` unset for a proxy or renamed target the wrapper cannot identify.

See [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) for the full setup steps, ledger format, and scheduling detail.

---

<a id="pause"></a>

## Pause a workspace

Pause is a workspace-level, reversible pause—not a full uninstall or removal.

```sh
./install.sh --disable --workspace "$WORKSPACE" --dry-run
./install.sh --disable --workspace "$WORKSPACE"
./install.sh --check --workspace "$WORKSPACE"
./install.sh --enable --workspace "$WORKSPACE" --dry-run
./install.sh --enable --workspace "$WORKSPACE"
```

The pause marker preserves `STATE.md`, promoted skills, pending work, queues, verification history, task state, and artifacts. Global hooks, runtime configuration, and cron jobs stay installed. Registered pause-aware Harness runtime entry points become inert for the selected workspace; older copied cron wrappers or other legacy wiring may need an adapter-doc refresh, and `--check` warnings should be acted on. Explicit setup, control, and updater commands—including initialization, bootstrap append, wrapper attestation, and `scripts/family-updater`—remain available while a workspace is paused. Pause takes effect at the next entry-point boundary; it does not kill work already in flight.

| Boundary | Pause behavior |
| --- | --- |
| Registered pause-aware runtime hooks, schedulers, model-call paths, and task-lifecycle entry points | hard pause: no new Harness work begins for the selected workspace |
| Managed bootstrap instruction | soft pause: the model is told to skip Harness instructions; this depends on model compliance |

`--check` reports the interactive-bootstrap coverage of a paused workspace; the exact state values are listed in the [reference](reference.md#pause-states).

This is intentionally not an uninstall promise. Removing global resources safely needs managed-resource receipts and is outside the current feature.

---

<a id="completion"></a>

## Technical implementation scope

`STATE.md` is a small, bounded operational-memory file: a durable task pointer, verified facts, rules, and open failures that can survive a session boundary. It is not weight training, self-modification, or a claim to change the model itself.

In ordinary interactive work, the managed instruction file prompts the agent to read `STATE.md` at task start. The Harness does **not** inject the full file into every normal interactive prompt. `scripts/task-runner.sh` is the deliberate exception: it injects `STATE.md` into the generated step prompt so a scheduled, fresh-context step receives the workspace's operational context.

`task-runner` is a completion scaffold for weaker agents. It does not raise an agent's intelligence by magic. Instead, it reduces mid-task drop-off, repeated failures, and evidence-free completion by using a rubric template (`loop/RUBRIC.tmpl.md` is scaffolded; rubric *scoring* is deferred to a later version), explicit step budget, retries, a no-progress stop, executable `donecheck`, and—when configured and wired—an independent verifier, plus a DLQ with evidence.

Each scheduled tick runs one fresh-context step. Per-task files retain attempt state, receipts, artifacts, `delivered/`, and `dlq/` so progress does not depend on a single long session.

Claude Code, Codex CLI, and Kimi Code CLI provide their own generation and execution abilities. Hermes Agent and OpenClaw also have native memory or skill-evolution mechanisms. Caty Agent Harness sits alongside them: it adds evidence-bounded operational memory, verification, and completion discipline. It does not replace their native learning, nor claim that the same native mechanism exists in every runtime.

---

## Vertical and horizontal axes

Caty Agent Harness is the vertical axis in Family OS, the maintainers' multi-agent environment: it strengthens an individual agent's ability to learn across work and finish multi-step work. Family Memory Architecture (FMA) is the horizontal axis: it coordinates memory, schedules, and provenance across agents. The two roles are orthogonal, not competing. (Family OS and FMA live in private repositories; their names appear here only to explain this project's scope boundary.)

---

## Directory map

What lives where in this repository, and which parts land in a workspace.

```text
caty-agent-harness/
├── install.sh              # canonical installer: scaffold, bootstrap append, check, pause
├── scripts/                # task-runner, loop-init, tr-enqueue, family-updater, pause lib,
│                           # watchdog/deadman probes, wrapper attestation
├── adapters/               # per-runtime wiring (claude-code / codex / kimi / hermes / openclaw):
│                           # INSTALL.md, bootstrap-block.md, hooks, verifier/cron scripts
├── templates/              # step-prompt, rubric, cron-wrapper, task templates
├── tests/                  # shell suites pinning the contracts
├── docs/                   # this guide, reference, agent-guide, plugin & governance docs
├── DESIGN.md               # learning-loop contracts (source of truth)
└── DESIGN-task-runner.md   # task-runner contract (source of truth)

<workspace>/                # created by install; your project folder
├── STATE.md                # handover notebook (bounded operational memory)
├── skills/  skills/_staging/
├── loop/                   # RUBRIC.tmpl.md, pending/, artifacts/, VERIFY.log.md
└── <instruction file>      # CLAUDE.md / AGENTS.md / … with the appended marked block
```

---

## Architecture

Design principle: **plain files, scheduler ticks, receipts, and atomic state transitions instead of a daemon, database, or central controller**.

| Component | Role |
| --- | --- |
| `STATE.md`, `skills/`, `loop/` | bounded operational memory, promoted skills, and work evidence in a workspace |
| `install.sh` / `scripts/loop-init` | idempotent missing-scaffold initialization, managed bootstrap, health check, and reversible workspace pause |
| `scripts/task-runner.sh` | one fresh-context step per tick, backed by per-task state and executable completion checks |
| `scripts/tr-enqueue` | validates and enqueues task files; rejects new queue writes while paused |
| `adapters/*` | runtime-specific hooks, verifier routes, and schedule wiring |
| [plugin-convention.md](plugin-convention.md) | allowed plugin seams and extraction policy |

`ops-reliability` is a logical capability physically colocated in this repository, not a separate repository or a central controller. It covers retry classification, watchdog and deadman paths, wrapper conformance, and updater/rollback receipts.

Plugins attach through `tr-enqueue`, pinned templates, and read-only artifact consumption. They do not gain direct authority over task state.

---

## Boundary map

What this project owns, and what it deliberately does not.

| System | Current role | Does not own |
| --- | --- | --- |
| Caty Agent Harness | individual-agent operational memory, verification discipline, and task completion | cross-agent memory coordination or policy authority |
| `ops-reliability` (colocated) | install/check/pause, watchdog, updater, rollback, and receipt mechanisms | domain success semantics or a central controller |
| `self-growth-loop` (private plugin) | read-only consumer of Harness results for proposal/governance/adoption workflows | task semantics or direct task-state writes |
| `persona-growth-loop` (private plugin) | planned vocabulary/persona proposal plugin | scheduler, ledger, or adoption authority |
| `sitter` ([caty-ai/sitter](https://github.com/caty-ai/sitter)) | optional supervision seam in the architecture map | an integrated default in this Harness release |

---

## Status

- This is the public Caty AI release repository. Development happens in a private working repository; releases land here as clean snapshots.
- The canonical installer is the pure-shell `install.sh`. There is no npm package and none is required.
- Verification: merges are gated on every `tests/*.test.sh` suite passing; run them locally as shown in [CONTRIBUTING.md](../CONTRIBUTING.md). There is no public CI yet, so the claim is locally reproducible rather than badge-backed.
- `self-growth-loop` is an active plugin consumer; `persona-growth-loop` remains planned/scaffolded.
- `sitter` is a proposed architecture edge, not an integrated default.

---

## Contributing and tests

Contribution flow, issue-first rules, and code style live in [CONTRIBUTING.md](../CONTRIBUTING.md). From the repository root of the current checkout, run every shell suite:

```sh
set -e
for test_file in tests/*.test.sh; do
  bash "$test_file"
done
```

Exact contracts, budgets, and promotion rules are specified in the [reference](reference.md).
