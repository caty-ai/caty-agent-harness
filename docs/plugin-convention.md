# Plugin Convention v0 (2026-07-20)

fable-loop-harness is a **generic completion engine**: cron tick → one fresh-context
step per tick → executable donecheck gate → budget/DLQ/escalation. Everything
domain-specific (what the tasks *do*) lives outside the engine.

A **plugin** is a separate repository that attaches domain automation to the engine
— e.g. a self-growth loop, a vocabulary harvester, a nightly audit. Plugins can be
attached and detached without touching this repo.

## The contract (the only four seams a plugin may use)

| # | Seam | Direction | Form |
|---|---|---|---|
| 1 | **Enqueue** | plugin → engine | `scripts/tr-enqueue <task-file> <workspace>` — task file per `templates/TASK.tmpl.md` with embedded ```donecheck``` block. This is the ONLY write a plugin makes into an engine workspace. |
| 2 | **Results** | engine → plugin | Read-only consumption of `loop/artifacts/<task-id>/` (`state.json`, `attempts/`, `out/`) and terminal dirs `loop/tasks/{delivered,dlq}/`. |
| 3 | **Templates/contract files** | engine → plugin | `templates/TASK.tmpl.md` + `templates/STEP-PROMPT.tmpl.md` placeholder contract. Plugins render task files against a **pinned engine version** (see rules). |
| 4 | **Data plane** | plugin ↔ plugin | Plugin state (ledgers, proposals, council verdicts) lives OUTSIDE engine workspaces — in the operator's shared store (family deployment: the shared vault). The engine never reads plugin state. |

Anything not listed above is engine-internal and may change without notice.

## Hard rules for plugin repos

1. **One entry point.** Never write into an engine workspace or this repo except via
   `tr-enqueue`. No reaching into `loop/` to mutate state, no template edits at runtime.
2. **Pin the engine version.** The plugin declares the engine tag it is verified
   against (e.g. `HARNESS_VERSION=v1.2.0` in its config) and ships **one integration
   test** that runs the real `tr-enqueue` + `task-runner.sh` from that tag against a
   temp workspace (lesson: parallel-implementation seam bugs, issues #9/#10 — unit
   suites pass while the seam is broken).
3. **Re-verify on bump.** Engine tags are the change signal. When the plugin moves to
   a newer engine tag, re-run the integration test before deploying.
4. **Dual bookkeeping.** Each plugin repo carries an `INTEGRATION.md` (what it
   enqueues, what it reads, target runtimes, cron entries). This repo lists all known
   plugins in [`docs/plugins.md`](plugins.md). Both sides must be updated when a
   plugin attaches or detaches.
5. **Own your cron.** Plugins schedule their own jobs and their own dead-man
   coverage; the engine's watchdogs only watch engine ticks.
6. **Naming.** Plugin repos are named `<topic>-loop` (e.g. `self-growth-loop`).

## Extraction policy (avoiding premature frameworks)

Shared machinery (ledger schema, council runner, approval queue) starts life inside
the FIRST plugin that needs it. Only when a SECOND plugin needs the same machinery do
we decide copy-vs-extract, with real usage data. No "common" library repo before then.
