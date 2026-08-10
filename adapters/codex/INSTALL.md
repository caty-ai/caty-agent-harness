# Codex CLI Adapter Install

Codex CLI supports the same lifecycle hooks as Claude Code, so Caty Agent
Harness CHECKPOINT enforcement reuses the reference Stop-hook logic
(DESIGN §4.1) with no cron watchdog — the `Stop` event fires the reminder
mechanically. This adapter targets a "relief Alpha" running on Codex while the
Claude Code Alpha is down (see the relief operating charter at
`~/path/to/your/AGENTS.md`). Replace this placeholder with the operator's own
agent charter file path during setup.

## checkpoint-stop-hook.sh (Stop hook)

What it does: when the agent ends a turn in a cwd for a Caty Agent Harness
workspace that contains `STATE.md` and workspace files changed after `STATE.md`
was last written, it asks ONCE per session to update `## Last session`, and
demands a delta-only, unverified flush append when there are genuinely new
observations. Silent in every other case: no STATE.md, nothing changed,
already asked this session, a Stop-forced continuation (`stop_hook_active`),
or any environment problem (a guard hook must never crash the hook chain).

Codex block contract: the hook prints `{"decision":"block","reason":"..."}` on stdout
and exits 0. Codex turns the `reason` into an automatic continuation prompt, so the
agent receives the CHECKPOINT instruction as its next turn. This differs from Claude
Code, which blocks with exit 2 + stderr; plain-text stdout is invalid for a Codex Stop
hook, so the hook emits JSON or nothing. The loop guard is `stop_hook_active` plus a
once-per-session guard file, so a continuation is never re-blocked.

Known accepted false positive: `git checkout`/`rebase` rewrites tree mtimes and can
trigger one spurious ask; the message allows the agent to decline explicitly.

## Register (once)

Add to `~/.codex/hooks.json` under `hooks.Stop` (the file uses the same JSON shape as
Claude Code's `settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/caty-agent-harness/adapters/codex/checkpoint-stop-hook.sh"
          }
        ]
      }
    ]
  }
}
```

The same registration also works as a `[hooks]` table inside `~/.codex/config.toml`,
or as a project-local `<repo>/.codex/hooks.json`. Point the command at your repo
clone — `git pull` then updates the hook with no re-registration.

## Hook trust

Codex runs a hook only after its source is trusted. Interactive sessions prompt to
trust a newly added hook the first time it would fire — approve it once. Headless
`codex exec` automation cannot prompt, so it needs `--dangerously-bypass-hook-trust`
on the command line; use that only for automation that already vets its hook sources
(this repo clone), never as a blanket default.

## bootstrap-block (relief AGENTS.md)

Use the managed append command with absolute paths. It appends only the marker-aware
block, preserves the existing AGENTS.md, and records the instruction target for
`--check`.

```sh
HARNESS=/absolute/path/to/caty-agent-harness
WS=/absolute/path/to/workspace
"$HARNESS/install.sh" --workspace "$WS" --bootstrap-runtime codex \
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

## Flush intake consumer

The Stop hook produces the shared `loop/pending/flush-*.md` format. Schedule the
deterministic Claude Code intake consumer for this workspace; it calls no model and is
the supported fold route for Codex too:

```sh
HARNESS=/absolute/path/to/caty-agent-harness
WS=/absolute/path/to/workspace
"$HARNESS/adapters/claude-code/flush-intake.sh" "$WS"
```

Follow the scheduling, single-route, ledger-retention, and deadman-marker rules in
[`../claude-code/INSTALL.md`](../claude-code/INSTALL.md#flush-intake-consumer). Do not
also run OpenClaw `distill-audit.sh` in the same workspace.

## Scope note

The hook keys on the session cwd. Sessions started inside a project dir (the normal
pattern) are enforced; sessions started at a workspace root above the project are not —
those rely on the CONSULT/CHECKPOINT discipline in the bootstrap-block.

## Destructive-command policy

Never run the denylisted destructive commands (`git reset --hard`, `git checkout --
<path>`, `git clean -f`, `git push --force`, history rewrites, or `rm -rf` outside the
task artifact directory) without an approval file. `loop/approvals/<task-id>` must name
the exact command. Unattended sessions have no approver and are deny-by-default.

## Not included (follow-up)

Codex also supports a `PreCompact` event, so a governed pre-compaction memory flush
(the Claude Code `precompact-flush-hook.sh` analogue) is possible but out of scope for
this adapter — the Stop hook already demands a flush at session end. See
`adapters/claude-code/precompact-flush-hook.sh` for the reference if you add one.
