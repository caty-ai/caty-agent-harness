# Claude Code Adapter Install

The Claude Code adapter is the reference implementation (DESIGN §4.1). Most of the
loop is covered by existing practice (cross-model review = VERIFY; project dirs +
`scripts/loop-init` = layout). This directory adds the mechanical piece: CHECKPOINT
enforcement.

The [shared adapter runtime contract](../CONTRACT.md) is normative for this adapter.
The rules there apply in addition to the Claude Code-specific wiring below.

## Initialize and register the marker-aware bootstrap

Use absolute paths so the installer can register the instruction file for pause
health checks:

```sh
HARNESS=/absolute/path/to/caty-agent-harness
WS=/absolute/path/to/workspace
"$HARNESS/install.sh" --workspace "$WS" --bootstrap-runtime claude-code \
  --append-bootstrap "$WS/CLAUDE.md"
```

This appends only the harness-owned block and records the target in
`$WS/.caty-agent-harness/instruction-files`; it does not replace the existing
`CLAUDE.md`. To pause hooks and automation while preserving `STATE.md`, learning
records, queues, and artifacts:

```sh
"$HARNESS/install.sh" --disable --workspace "$WS" --dry-run
"$HARNESS/install.sh" --disable --workspace "$WS"
"$HARNESS/install.sh" --enable --workspace "$WS"
```

Pause takes effect at the next entry-point boundary. The registered v2 bootstrap is
instruction-driven and therefore softer than the shell guards.

## checkpoint-stop-hook.sh (Stop hook)

What it does: when the assistant ends a turn in a cwd for a Caty Agent Harness
workspace that contains `STATE.md` and workspace files changed after `STATE.md`
was last written, it blocks ONCE per session (exit 2) with a reminder to update
`## Last session`. Silent in every other case: no STATE.md, nothing changed,
already nagged this session, stop-hook-forced continuation, or any environment
problem (a guard hook must never crash the hook chain). Its reminder also
demands a delta-only, unverified flush append when there are genuinely new
durable observations.

Known accepted false positive: `git checkout`/`rebase` rewrites tree mtimes and can
trigger one spurious nag; the message allows the assistant to decline explicitly.

## Register (once)

Add to `~/.claude/settings.json` under `hooks.Stop`:

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash /path/to/caty-agent-harness/adapters/claude-code/checkpoint-stop-hook.sh"
    }
  ]
}
```

Point at your repo clone — `git pull` then updates the hook with no re-registration.

## precompact-flush-hook.sh (PreCompact hook)

What it does: before Claude Code compacts a context window, this hook makes one
governed, headless capture attempt per session. It supplies the current
`## Lessons learned`, `## Open failures`, and today's flush file as already
captured context, so the model extracts delta-only candidates into
`loop/pending/`. Every attempted write has a synthetic-origin stamp and is
classified as `ok`, `no_reply`, `degenerate`, `timeout`, or `error`; bullets
are appended only for `ok`. It never self-promotes these unverified candidates
into `STATE.md`, and its outside-workspace guard prevents more than one attempt
per session.

Known accepted bounded re-arm: the per-session guard file is cleaned up after
about two days, so a session that runs longer can flush once more after the guard
re-arms. This mirrors the Stop hook's `nagged-*` pattern and is not a spam risk.

Environment knobs: `FLH_FLUSH_TIMEOUT` sets the model-call timeout in seconds
(default: `120`); `FLH_FLUSH_CMD` sets the headless command (default:
`claude -p --bare`). PreCompact cannot block compaction, so the hook always exits 0
regardless of capture outcome.
This requires a Claude Code version that supports the `PreCompact` hook event and
`claude -p --bare`; on older versions the hook is a silent no-op (`outcome=error`).

## Register (once)

Add to `~/.claude/settings.json` under `hooks.PreCompact` (an empty matcher runs for
both `manual` and `auto` compaction):

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash /path/to/caty-agent-harness/adapters/claude-code/precompact-flush-hook.sh"
    }
  ]
}
```

## Flush intake consumer

The stop and PreCompact hooks are producers. A workspace that enables either producer
must also schedule `adapters/claude-code/flush-intake.sh`; otherwise unverified
`loop/pending/flush-*.md` records accumulate without ever reaching the governed STATE
fold. The same deterministic consumer may be used by Codex and Kimi workspaces because
their checkpoint hooks emit the shared flush format. It does not assume that a
model-authored `session=` attribute has been sanitized.

Run the consumer two to four times per day. For a LaunchAgent, use a `StartInterval`
between `21600` and `43200` seconds. A daily schedule has no jitter margin at the
default deadman threshold. The consumer calls no model, so its scheduler does not need
Claude credentials; LaunchAgent remains the recommended macOS scheduler surface.

```sh
HARNESS=/absolute/path/to/caty-agent-harness
WS=/absolute/path/to/workspace
"$HARNESS/adapters/claude-code/flush-intake.sh" "$WS"
```

Exactly one fold route may run in a workspace: use flush intake for Claude Code, Codex,
or Kimi flush files, or use OpenClaw `distill-audit.sh`, never both. Pointing OpenClaw
distillation at the transcript store summarized by the flush hooks is also forbidden.
`install.sh --check` fails after it sees evidence from both routes:
`loop/.distill-last-run` and `loop/pending/intake-runs.log`. This check is evidence-based,
so a second route that is wired but has never run is detected only after its first run.

The consumer owns `loop/pending/intake-<UTC-date>.md` key ledgers. A ledger may be
deleted only when no unarchived `flush-*.md` file predates it. Folded keys are retained
after STATE cap eviction to prevent refold oscillation. The raw layer in `loop/archive/`
contains exactly the regular files `flush-<UTC-date>.md` and
`intake-evictions-<UTC-date>.md`; see [DESIGN.md §3.1](../../docs/design/DESIGN.md) for
the exact membership rule. Symlinks, and any other file that shares the directory, are
outside this layer and have no retention or weekly-reference guarantee. The raw layer
is append-only, is never auto-pruned, and is deleted only by a human or operations
owner. List one ISO week's raw files with:

```sh
"$HARNESS/scripts/raw-week.sh" --workspace "$WS" --week 2026-W34
```

Each parsed bullet is limited to `INTAKE_MAX_BULLET_BYTES` bytes (default `512` after
control-character stripping); an oversized bullet is dropped whole and counted as
`dropped_oversize` in the run receipt. Lessons displaced by the STATE cap are appended
to `loop/archive/intake-evictions-<UTC-date>.md`, while `evicted_by_cap` and the archive
path remain visible in the receipt.

The consumer itself touches `loop/.deadman/distill.marker` only after acquiring the
shared STATE lock and completing without an infrastructure error. The checked-in
`templates/cron-wrapper.tmpl.sh` recognizes this exact repository consumer as
self-marking and suppresses its own pre-touch when `DEADMAN_MARKER` names that
workspace's `distill.marker`; an explicit setting therefore cannot hide lock starvation
or intake failure. Leave `DEADMAN_MARKER` unset for a proxy or renamed target that the
wrapper cannot identify. The `distill` marker proves only that intake ran; inspect
`loop/pending/intake-runs.log` for content-level silence, dedup, deferral, eviction, and
quarantine counts. Stock OpenClaw distillation touches `.distill-last-run`, not the
deadman `distill.marker`.

## macOS scheduling: LaunchAgent, not crontab

On macOS, crontab sessions cannot reach the user Keychain, so `claude -p` exits 1
with `Not logged in · Please run /login` under cron while the same command succeeds
interactively and under launchd. The Phase-1 pilot on 2026-07-19 therefore adopted
LaunchAgent scheduling for Claude CLI jobs on macOS.
This is specific to the claude CLI's credential lookup; other targets may run fine
under cron. The rule: any tick wrapper or spawn adapter that shells out to the
claude CLI MUST be scheduled as a LaunchAgent in the `gui/<uid>` domain with
`StartInterval` — not via crontab.

Only the scheduler differs. The harness cron-wrapper
(`templates/cron-wrapper.tmpl.sh`) works unchanged under launchd; the deadman
marker and probe were verified in the pilot. A ready-to-fill plist wrapping the
cron-wrapper lives at `templates/launchd.tmpl.plist`. Copy it to
`~/Library/LaunchAgents/<label>.plist`, fill the placeholders, then:

```sh
launchctl bootstrap gui/501 ~/Library/LaunchAgents/<label>.plist
launchctl bootout gui/501/<label>    # to stop/remove
```

(`501` is the typical first-user uid; use `$(id -u)` if unsure.)

## Host hook isolation for headless spawn sessions

Headless `claude -p` sessions inherit the user-level hooks in
`~/.claude/settings.json`. The Phase-1 pilot on 2026-07-19 established the need to
isolate operator-level hooks after a host PreToolUse hook blocked the weak agent's
writes under `loop/artifacts/`; the weak model burned a full 381 s attempt
negotiating with the hook before failing. This is a silent, host-specific failure mode: the harness
looks broken while the actual cause lives in the operator's personal settings.

Contract for claude-code spawn adapters:

- The adapter must document/enumerate the environment its headless sessions run
  with (env vars it exports, cwd, and which user-level settings apply), so an
  operator can reason about what leaks in.
- Before running a loop, operators must verify their user-level hooks are either
  inert for paths under `loop/artifacts/`, or explicitly bypassed via a
  hook-scoped env var that the adapter exports for that session only. Never
  disable a hook globally to make the loop pass — the bypass must be scoped to
  the headless session.

## Scope note

The hook keys on the session cwd. Sessions started inside a project dir (the normal
pattern) are enforced; sessions started at a workspace root above the project are
not — those rely on the CONSULT/CHECKPOINT discipline in the usual instructions.

## Destructive-command policy

Never run the denylisted destructive commands (`git reset --hard`, `git checkout -- <path>`,
`git clean -f`, `git push --force`, history rewrites, or `rm -rf` outside the task artifact
directory) without an approval file. `loop/approvals/<task-id>` must name the exact command.
Cron-driven sessions have no approver and are deny-by-default.
