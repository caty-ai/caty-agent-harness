# Plugin Convention v0 (2026-07-20)

Caty Agent Harness is a **generic completion engine**: cron tick → one fresh-context
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

## Task execution boundary

- Every task frontmatter must declare `receipt: out/<path>`. The exact grammar is
  `^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$`; `.` and `..` path segments are also
  forbidden. The runner delivers only when that target is a non-symlink, non-empty
  regular file whose resolved path remains under the task's resolved `out/` directory.
  Queue-dropped legacy tasks with a missing or invalid value go to DLQ with
  `missing-receipt` before a model attempt.
- A donecheck opener is a column-zero `` ```donecheck `` line with only trailing
  whitespace; its closer is the first subsequent column-zero `` ``` `` line with
  only trailing whitespace. Exactly one closed block is required. Because extraction
  is deliberately textual, a column-zero fence inside a shell heredoc closes the
  block: plugins must not put column-zero Markdown fences inside donecheck heredocs.
- Donechecks run with `env -i`. The supplied variables are `TASK_ID`, `TASK_FILE`,
  `ARTIFACT_DIR`, `TR_DC_CWD`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and `HOME`, plus
  `LANG`, `LC_ALL`, and `TZ` only when the runner has them. The shell also creates
  variables such as `PWD`, `SHLVL`, and `_`. Donechecks that depended on any other
  inherited variable, including `TR_PUSH_CMD`, break loudly at their next run.
- `TR_SPAWN_STEP` must be an absolute path to an executable file. PATH-resolved
  command names and relative configurations must migrate to an absolute provider path.
- Workspace initialization records the absolute Bash and Perl used for validation
  and execution in `loop/.tr-interpreters`. Existing workspaces self-heal this record
  on first enqueue or runner use; invalid recorded paths fail closed.

## Extraction policy (avoiding premature frameworks)

Shared machinery (ledger schema, council runner, approval queue) starts life inside
the FIRST plugin that needs it. Only when a SECOND plugin needs the same machinery do
we decide copy-vs-extract, with real usage data. No "common" library repo before then.
