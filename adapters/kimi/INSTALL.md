# Kimi Code CLI Adapter Install

Kimi Code CLI exposes lifecycle hooks including a blockable `Stop` event, so
Caty Agent Harness CHECKPOINT enforcement reuses the reference Stop-hook logic
(DESIGN §4.1) with no cron watchdog. This adapter targets a "relief Alpha"
running on Kimi while the Claude Code Alpha is down (see the relief operating
charter at `~/path/to/your/AGENTS.md`). Replace this placeholder with the
operator's own agent charter file path during setup.

## checkpoint-stop-hook.sh (Stop hook)

What it does: identical policy to the Claude Code reference — when the model
is about to end a turn in a cwd for a Caty Agent Harness workspace that
contains `STATE.md` and workspace files changed after `STATE.md` was last
written, it asks ONCE per session to update `## Last session` and demands a
delta-only, unverified flush append for genuinely new observations. Silent in
every other case, and it never crashes the hook chain.

Kimi block contract: the `Stop` event is blockable, so the hook exits 2 with the
reminder on stderr, and Kimi appends that message so the model continues — the same
contract as Claude Code. Exit 0 means allow; any other non-zero code is treated as
fail-open (allow), so an environment problem degrades to silence rather than a block.

Loop guard: Kimi's Stop payload has no `stop_hook_active` field, so the once-per-session
guard file is the loop protection — the second Stop in the same session finds the guard
and exits 0. The hook still honors `stop_hook_active` if a future Kimi adds it.

Known accepted false positive: `git checkout`/`rebase` rewrites tree mtimes and can
trigger one spurious ask; the message allows the model to decline explicitly.

## Register (once)

Add a `[[hooks]]` table to `~/.kimi-code/config.toml`:

```toml
[[hooks]]
event = "Stop"
command = "bash /path/to/caty-agent-harness/adapters/kimi/checkpoint-stop-hook.sh"
timeout = 30
```

Only `event`, `command`, `timeout`, and an optional `matcher` are allowed — Kimi fails
to load a config that carries unknown hook fields, so do not add extras. Point `command`
at your repo clone; `git pull` then updates the hook with no re-registration.

## AGENTS.md and bootstrap-block

Kimi reads `AGENTS.md` (no `KIMI.md` symlink is required). Use the managed append
command with absolute paths so the existing file is preserved and the instruction
target is registered for pause health checks.

```sh
HARNESS=/absolute/path/to/caty-agent-harness
WS=/absolute/path/to/workspace
"$HARNESS/install.sh" --workspace "$WS" --bootstrap-runtime kimi \
  --append-bootstrap "$WS/AGENTS.md"
```

Pause and resume without deleting `STATE.md`, learning records, queues, or artifacts:

```sh
"$HARNESS/install.sh" --disable --workspace "$WS" --dry-run
"$HARNESS/install.sh" --disable --workspace "$WS"
"$HARNESS/install.sh" --enable --workspace "$WS"
```

Pause takes effect at the next entry-point boundary. Shell entry points are hard
paused; bootstrap compliance is a softer model-instruction boundary.

## Scope note / Destructive-command policy

Same as the other adapters: the hook keys on the session cwd (project-dir sessions are
enforced; workspace-root sessions rely on the bootstrap-block). Never run the denylisted
destructive commands (`git reset --hard`, `git checkout -- <path>`, `git clean -f`, `git
push --force`, history rewrites, or `rm -rf` outside the task artifact directory) without
a `loop/approvals/<task-id>` approval file naming the exact command; unattended sessions
are deny-by-default.
