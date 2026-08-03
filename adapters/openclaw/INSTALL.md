# OpenClaw Adapter Install

These steps are written for Claire, the OpenClaw profile agent that owns the target
profile workspace. Run them from a shell where the profile can write its own workspace,
AGENTS.md, and cron entry.

The [shared adapter runtime contract](../CONTRACT.md) is normative for this adapter.
The rules there apply in addition to the OpenClaw-specific wiring below.

1. Clone this private repository into a stable local path.

   Access is by repo invite or deploy key. Do not copy adapter files by hand if the
   profile can clone; keeping a clone makes updates auditable.

2. Initialize the profile workspace.

   ```sh
   scripts/loop-init --workspace <openclaw profile workspace>
   ```

   This creates `STATE.md`, `skills/`, `skills/_staging/`, `loop/RUBRIC.tmpl.md`,
   `loop/artifacts/`, `loop/pending/`, and `loop/VERIFY.log.md` if they do not exist.

3. Append the marker-aware block with the managed installer.

   ```sh
   HARNESS=/absolute/path/to/caty-agent-harness
   WS=/absolute/path/to/openclaw-profile-workspace
   "$HARNESS/install.sh" --workspace "$WS" --bootstrap-runtime openclaw \
     --append-bootstrap "$WS/AGENTS.md"
   ```

   The existing file is preserved and its path is registered under the workspace.
   Pause and resume without deleting state, learning records, queues, or artifacts:

   ```sh
   "$HARNESS/install.sh" --disable --workspace "$WS" --dry-run
   "$HARNESS/install.sh" --disable --workspace "$WS"
   "$HARNESS/install.sh" --enable --workspace "$WS"
   ```

   Pause takes effect at the next entry-point boundary. Shell/model-call entry points
   are hard paused; bootstrap compliance is a softer model-instruction boundary.

4. Add the nightly distillation cron.

   Use the exact workspace path initialized in step 2, and pass each transcript or
   session-log directory with `--input`. Redirect stdout and stderr to the workspace
   cron log so warnings and run summaries are retained. Copy
   `templates/cron-wrapper.tmpl.sh` to `<openclaw profile workspace>/scripts/cron-wrapper.sh`,
   make the copy executable, and use it for cron so PATH and optional secrets loading
   are explicit.

   `distill-audit.sh` accepts ordinary transcript filenames and extensions so existing
   Claire-style input directories remain compatible. Before applying its existing
   newest-files-first 100 KB budget, it skips OpenClaw's non-conversation sidecars and
   snapshots by basename: `*.trajectory.jsonl` (including archived suffixes),
   `heartbeat.json`, `heartbeat-state.json`, `catalog.json`, `skills-catalog.json`,
   `sessions.json`, and temporary/backup suffixes of those JSON snapshots. Files that
   merely contain words such as `heartbeat`, `catalog`, or `trajectory` elsewhere in
   the basename are not skipped.

   ```cron
   15 3 * * * CATY_HARNESS_ROOT=/opt/caty-agent-harness TARGET=/opt/caty-agent-harness/adapters/openclaw/distill-audit.sh SECRETS_ENV=/path/to/claire-home/.openclaw-claire/cron.env /path/to/claire-home/.openclaw-claire/workspace/scripts/cron-wrapper.sh --workspace /path/to/claire-home/.openclaw-claire/workspace --input /path/to/openclaw/session-logs >>/path/to/claire-home/.openclaw-claire/workspace/loop/distill-cron.log 2>&1
   ```

   Put `DISTILLER_CMD=/abs/distiller-wrapper.sh` in `SECRETS_ENV` or another cron-owned
   environment source. If `SECRETS_ENV` exists, the wrapper requires it to be owned by
   the cron user and to have `0600` or `0400` permissions.

5. Locate Claire's real transcript/session-log directory on this host.

   The exact path varies by OpenClaw version and install method. Do not hardcode the
   example path above as fact. Inspect this host, choose the directory that contains
   Claire's session transcripts or outcome logs, and report back which path was used.

5b. Optional: relocate the draft-skill staging dir.

   By default drafts go to `<ws>/skills/_staging/`. If your `skills/` tree is shared
   with other consumers (e.g. a symlink into another skill root) and you cannot rule
   out recursive loaders picking `_staging` up, set `STAGING_DIR` in the cron line to
   a path outside that tree, e.g. `STAGING_DIR=<ws>/loop/skills-staging`. The script
   creates it if missing; the promotion flow (move + stamp on verify pass) is unchanged.

6. Set `DISTILLER_CMD` for any reachable model CLI.

   Cross-vendor distillation is not required here because `distill-audit.sh` never
   grants verified status to anything. Skill promotion still requires the verify gate
   described in DESIGN.md §3.2 and §3.3.

   `DISTILLER_CMD` must be exactly one absolute wrapper-script path. The adapter
   rejects legacy multi-token command strings and ships no provider default.

   Before enabling cron:

   1. Create a single-file distiller wrapper that enforces the runtime-specific
      fresh-session, persistence-off, and auto-deny behavior. It must invoke the exact
      provider path supplied by the host in `FABLE_CONFORMING_PROVIDER_PATH`.
   2. Create a separate provider-specific probe executable that validates those
      isolation claims, reports the underlying provider path, and proves that provider
      is a self-contained executable that remains runnable when copied away from its
      install directory. Symlink or sibling-dependent launchers are not conforming.
   3. Run the harness attester:

      ```sh
      scripts/attest-wrapper --route distiller --wrapper /abs/distiller-wrapper.sh --probe /abs/distiller-probe.sh
      ```

      This writes `/abs/distiller-wrapper.sh.conformance`.
   4. Set `DISTILLER_CMD=/abs/distiller-wrapper.sh` in the cron environment.
      Re-run the attester after changing the wrapper, probe, provider executable, or
      provider configuration.

   For the later per-task verify spike in DESIGN.md §4.3, reuse
   `adapters/hermes/verify-job.sh` as the natural starting point. It is runtime-neutral:
   bind it to a fresh-session verifier process and feed it artifact bundles only,
   instead of building a new verifier from scratch.

7. Keep the R1 boundary explicit.

   This cron is distillation, never verification. It cannot promote skills and cannot
   write `## Verified facts`, because transcript reading exposes the maker's reasoning
   trail and breaks fresh-context independence. Missing, stale, malformed, or
   mismatched conformance evidence blocks the distiller before model execution, lock
   acquisition, `STATE.md` mutation, or pending-file mutation; recover by re-attesting
   the wrapper/probe pair rather than bypassing the gate.

8. Preserve profile-owned state during updates.

   `git pull` refreshes the adapter and templates in this repository clone only. The
   profile's own `STATE.md`, `skills/`, `skills/_staging/`, and `loop/` contents live
   outside the repo clone and are not touched by an adapter update.

## Optional sentinel cron

Add a lightweight health sentinel if Claire needs an inbox notice when `install.sh
--check` starts warning or reporting missing layout paths. This cron never writes
`STATE.md`; it writes a single pending-file notice that the normal inbox/distiller flow
can consume.

```cron
*/30 * * * * TARGET=/opt/caty-agent-harness/adapters/openclaw/sentinel-cron.sh /path/to/claire-home/.openclaw-claire/workspace/scripts/cron-wrapper.sh --workspace /path/to/claire-home/.openclaw-claire/workspace >>/path/to/claire-home/.openclaw-claire/workspace/loop/sentinel-cron.log 2>&1
```

Set `SENTINEL_INBOX_FILE=/path/to/notice.md` to route the notice somewhere other than
`<workspace>/loop/pending/sentinel-notice.md`. Keep the target outside `STATE.md`; the
single-writer rule still applies.

`install.sh --check` remains read-only: its OpenClaw conformance row reads and hashes
the configured wrapper, provider, probe, and evidence files without executing them.

Verify once manually: remove or rename a disposable required path such as
`loop/RUBRIC.tmpl.md`, run `sentinel-cron.sh --workspace <ws>`, confirm the notice file
appears, restore the path, rerun, and confirm the notice is cleared.

## Destructive-command policy

Never run the denylisted destructive commands (`git reset --hard`, `git checkout -- <path>`,
`git clean -f`, `git push --force`, history rewrites, or `rm -rf` outside the task artifact
directory) without an approval file. `loop/approvals/<task-id>` must name the exact command.
Cron-driven sessions have no approver and are deny-by-default.
