# Task Packet — family-updater rollout

From: Alpha · SoT: fable-loop-harness Issue #36
For: Claude Code, OpenClaw, and Hermes family agents

## Claude Code

### Why (read first)

Claude Code needs the harness clone to follow released tags without giving the
updater any write authority. The updater fetches tags, checks out the selected
release in detached HEAD, runs `install.sh --check`, and rolls back if the check
fails.

### What to do

1. Prepare a stable harness clone with a read-only deploy key or fine-grained PAT.
   Do not use a token with write access.
2. Copy `templates/updater-cron.tmpl.sh` into a cron-owned scripts location.
3. Install a cron line like:
   ```cron
   12 * * * * REPO_DIR="$HOME/claude-workspace/caty-agent-harness" WORKSPACE="$HOME/claude-workspace" AGENT="claude-code" RING="stable" SOAK_HOURS="24" FMA_SCRIPTS_DIR="$HOME/claude-workspace/family-memory-architecture/scripts" "$HOME/claude-workspace/caty-agent-harness/templates/updater-cron.tmpl.sh" >>"$HOME/claude-workspace/updater-cron.log" 2>&1
   ```

### Constraints

- The credential on the clone is read-only. The updater never pushes.
- Keep Claude Code on `stable` unless Alpha assigns a canary duty.
- The cron wrapper must point at an absolute `REPO_DIR`.

### Done when

- [ ] Cron is installed and points at the intended clone and workspace.
- [ ] `scripts/family-updater --repo-dir <clone> --workspace <ws> --ring stable`
      succeeds once manually.
- [ ] Heartbeats appear as `job-heartbeat updater-claude-code`.
- [ ] Local ledger entries appear for real updates and failures in
      `~/.claude/state/installed-versions.log`; no-op already-current runs do
      not add a line.

## OpenClaw / Claire

### Why (read first)

Claire is the family canary. She should receive the newest valid release tag first
so failures are caught before stable agents update.

> Status: Claire installed as canary on 2026-07-09 (v1.1.0, RING=canary SOAK_HOURS=0,
> hourly cron, heartbeat `updater-claire.json` ok, 34/34 tests green on host).
> v1.1.1 is the first tag distributed via the rail itself.

> Path correction (install learning, fable-loop #40): the cron line below shows
> `WORKSPACE="/path/to/claire-home/.openclaw-claire/workspace"`, but Claire's real workspace
> is `/path/to/openclaw-home/.openclaw/workspace-claire`. Verify the live workspace path on
> the host before installing; do not copy packet paths blindly.

### What to do

1. Prepare Claire's harness clone with a read-only deploy key or fine-grained PAT.
2. Use the updater cron wrapper with Claire on canary:
   ```cron
   17 * * * * REPO_DIR="/path/to/clones/caty-agent-harness" WORKSPACE="/path/to/claire-home/.openclaw-claire/workspace" AGENT="claire" RING="canary" SOAK_HOURS="0" FMA_SCRIPTS_DIR="/path/to/fma/scripts" "/path/to/clones/caty-agent-harness/templates/updater-cron.tmpl.sh" >>"/path/to/claire-home/.openclaw-claire/workspace/loop/updater-cron.log" 2>&1
   ```

### Constraints

- Claire is canary; do not reuse this ring assignment for other OpenClaw profiles
  unless Alpha explicitly says so.
- Keep the harness credential read-only.
- Failure reports must be caution-only hot-inbox posts from the updater.

### Done when

- [ ] Claire reports `job-heartbeat updater-claire` after a no-op or successful update.
- [ ] A failed canary check produces exactly one hot-inbox caution post.
- [ ] The ledger records real updates and failures under
      `~/.claude/state/installed-versions.log`; no-op already-current runs do
      not add a line.

## Hermes

### Why (read first)

Hermes should follow stable release tags after the soak window so the profile gets
the same harness fixes without being first to absorb release risk.

### What to do

1. Prepare the Hermes harness clone with a read-only deploy key or fine-grained PAT.
2. Install a stable cron line:
   ```cron
   22 * * * * REPO_DIR="$HOME/caty-agent-harness" WORKSPACE="$HOME/.hermes/profiles/default/workspace" AGENT="hermes" RING="stable" SOAK_HOURS="24" FMA_SCRIPTS_DIR="$HOME/claude-workspace/family-memory-architecture/scripts" "$HOME/caty-agent-harness/templates/updater-cron.tmpl.sh" >>"$HOME/.hermes/profiles/default/workspace/loop/updater-cron.log" 2>&1
   ```

### Constraints

- Use `stable` unless Hermes is explicitly assigned a canary role.
- Do not give the updater write access to the remote.
- Keep `WORKSPACE` aligned with the active Hermes profile.

### Done when

- [ ] Manual updater run passes for the target Hermes workspace.
- [ ] Heartbeats appear as `job-heartbeat updater-hermes`.
- [ ] Failures, if any, land in hot-inbox as caution posts and the clone rolls back.
- [ ] The local ledger records real updates and failures; no-op
      already-current runs do not add a line.

## Verified deployments — actual paths (as of 2026-07-14, fable-loop #40)

The packet templates above use illustrative paths. These are the paths that were
actually verified working at install time — trust this table over the templates,
and always confirm the live workspace path on the host before installing.

| Agent | Host | Trigger | Deploy clone | Credential |
| --- | --- | --- | --- | --- |
| Claire (canary) | VPS | cron `:17` | `/path/to/clones/caty-agent-harness` | read-only deploy key |
| Alpha | MBP | launchd `com.alpha.fable-loop.updater` `:12` | `~/claude-workspace/systems/caty-agent-harness-stable` | `alpha-mbp-updater-ro` |
| Cero | VPS | cron `:22` | `/path/to/hermes-home/.hermes/profiles/cero/systems/caty-agent-harness-stable` | `cero-vps-updater-ro` |
| Mine | VPS | cron `:27` | `/path/to/openclaw-home/.openclaw/workspace/systems/caty-agent-harness-stable` | `mine-vps-updater-ro` |
| Caty | mac-mini | launchd `com.caty.fable-loop.updater` `:22` | `~/systems/caty-agent-harness-stable` | mini's existing read ssh key |

Install learnings folded back from the rollout:

- Claire's real workspace is `/path/to/openclaw-home/.openclaw/workspace-claire`, not the
  packet's `/path/to/claire-home/.openclaw-claire/workspace` (see the correction note in
  the Claire section).
- On macOS hosts (Alpha MBP, Caty mini) launchd is the source of truth, not
  crontab — register a `com.<agent>.fable-loop.updater` plist instead of a cron
  line.
- VPS agents share one heartbeat dir (`/path/to/hermes-home/.hermes/profiles/cero/state/heartbeats`);
  the fma watchdog reads a single dir per host and resolves entries by filename,
  so per-agent heartbeat dirs are not required.
- Caty on the mini needed `FMA_SCRIPTS_DIR=~/.openclaw/bin/fma`; an existing
  host key with read access makes a dedicated deploy key unnecessary.
- Register the fma `jobs.yaml` entry only after the real heartbeat file exists
  (fma #77 lesson): alpha=#85, caty=#103, cero/mine=#105.
