# Hermes Adapter Install

These steps are written for the Hermes profile agent that owns the target profile.
Run them from a shell where the profile can write its own workspace and bootstrap file.

The [shared adapter runtime contract](../CONTRACT.md) is normative for this adapter.
The rules there apply in addition to the Hermes-specific wiring below.

1. Clone the public repository into a stable local path.

   ```sh
   git clone https://github.com/caty-ai/caty-agent-harness.git
   ```

   Keep the clone so updates remain auditable; do not copy adapter files by hand.

2. Initialize the profile workspace.

   ```sh
   scripts/loop-init --workspace ~/.hermes/profiles/<profile>/workspace
   ```

   This creates `STATE.md`, `skills/`, `skills/_staging/`, `loop/RUBRIC.tmpl.md`,
   `loop/artifacts/`, `loop/pending/`, and `loop/VERIFY.log.md` if they do not exist.

3. Append the marker-aware block with the managed installer.

   For Cero, use the profile's absolute system-instruction/bootstrap path:

   ```sh
   HARNESS=/absolute/path/to/caty-agent-harness
   WS=/absolute/path/to/.hermes/profiles/<profile>/workspace
   "$HARNESS/install.sh" --workspace "$WS" --bootstrap-runtime hermes \
     --append-bootstrap /absolute/path/to/profile-system-instructions.md
   ```

   The existing file is preserved and its path is registered under the workspace.
   Pause and resume without deleting state, learning records, queue, or artifacts:

   ```sh
   "$HARNESS/install.sh" --disable --workspace "$WS" --dry-run
   "$HARNESS/install.sh" --disable --workspace "$WS"
   "$HARNESS/install.sh" --enable --workspace "$WS"
   ```

   Pause takes effect at the next entry-point boundary. Shell/model-call entry points
   are hard paused; bootstrap compliance is a softer model-instruction boundary.

4. Wire an agjob job type named `verify`.

   The job body should only call:

   ```sh
   adapters/hermes/verify-job.sh <bundle-dir>
   ```

   agjob provides scheduling only: queueing, heartbeats, retries, and DLQ. Per
   DESIGN.md §4.2, do not extend agjob to perform cross-model dispatch itself.

   Exit-code mapping for the job wrapper: exit 0/1/4 mean the verification RAN and
   returned a verdict (pass / fail-or-rubric-invalid / inconclusive-or-needs-human) —
   treat the job as succeeded and read the verdict from stdout or VERIFY.log.md; a
   fail verdict routes the TASK back to PLAN/ACT, it is not an infra failure. Exit 2
   (usage), 3 (blocked-missing-artifact), and 5 (infrastructure/configuration,
   including wrapper-conformance failure) are job errors eligible for agjob retry/DLQ.

5. Set the verifier environment.

   `VERIFIER_CMD` is required for skill promotion and must target a different VENDOR
   than the maker model. This is DESIGN.md R8 and addresses Hermes same-family bias
   issue #15204. Use `VERIFIER_ID` when the command string is not a clear model/vendor
   identifier for `loop/VERIFY.log.md`.

   `VERIFIER_CMD` must be exactly one absolute wrapper-script path. The adapter
   rejects legacy multi-token command strings and ships no provider default.

   Before enabling the job:

   1. Create a single-file verifier wrapper that enforces the runtime-specific
      fresh-session, persistence-off, and auto-deny behavior. It must invoke the exact
      provider path supplied by the host in `FABLE_CONFORMING_PROVIDER_PATH`.
   2. Create a separate provider-specific probe executable that validates those
      isolation claims, reports the underlying provider path, and proves that provider
      is a self-contained executable that remains runnable when copied away from its
      install directory. Symlink or sibling-dependent launchers are not conforming.
   3. Run the harness attester:

      ```sh
      scripts/attest-wrapper --route verifier --wrapper /abs/verifier-wrapper.sh --probe /abs/verifier-probe.sh
      ```

      This writes `/abs/verifier-wrapper.sh.conformance`.
   4. Set `VERIFIER_CMD=/abs/verifier-wrapper.sh` in the Hermes job environment.
      Re-run the attester after changing the wrapper, probe, provider executable, or
      provider configuration.

   Optionally set `VERIFY_STEP` to the plan-step number when the verification belongs
   to a specific task-runner step: the log entry gains a `step=<k>` field, and the
   task-runner re-injects a non-pass finding into the next attempt's prompt only when
   that field matches the current step. For task-runner-produced artifact bundles,
   when unset, `VERIFY_STEP` is auto-derived from `state.json`'s `current_step`
   (positive integers only — zero, negative, or non-integer values are silently
   ignored and the entry gets no step field); an explicit value still overrides it. Entries without a step field are never
   re-injected.

6. Keep native skill generation staged.

   Hermes native `auto_generate` output goes to `skills/_staging/`. CONSULT never loads
   `_staging`. Promotion moves a skill to `skills/` only after a verify pass, and stamps
   the skill frontmatter with `verified_at` and `status: verified`.

7. Handle verifier outages conservatively.

   If the verifier is unreachable, hold promotions. Never fall back to self-critique;
   R13 requires no promotion when the independent verifier cannot be reached. Missing,
   stale, malformed, or mismatched conformance evidence is the same class of outage:
   re-attest the wrapper/probe pair instead of bypassing the gate.

8. Preserve profile-owned state during updates.

   `git pull` refreshes the adapter and templates in this repository clone only. The
   profile's own `STATE.md`, `skills/`, `skills/_staging/`, and `loop/` contents are
   outside the repo clone and are not touched by an adapter update.

## Optional stale-claim watchdog

Schedule `adapters/hermes/stale-claim-watchdog.sh` as an agjob job body if the profile
needs stale `claimed` entries surfaced back into the loop. Per DESIGN.md §4.2, agjob is
scheduling only here: queueing, heartbeats, retries, and DLQ around this standalone
script. The script itself reads the ledger, calls optional action commands, and appends
candidate lines to `loop/pending/`; it never writes `STATE.md`.

Ledger input is tab-separated, one job per line:

```text
job_id<TAB>status<TAB>last_heartbeat_epoch<TAB>attempts_used<TAB>attempts_budget
```

Wire one source:

- `AGJOB_LIST_CMD`: command string that prints the ledger format above.
- `--ledger-file <path>`: deterministic fixture/input seam for tests or manual checks.

Optional action and threshold env vars:

- `WATCHDOG_REQUEUE_CMD`: command string called with `"$job_id"` for stale claimed jobs
  with attempts remaining. If unset, the script prints `would requeue: <job_id>`.
- `WATCHDOG_DLQ_CMD`: command string called with `"$job_id"` for stale claimed jobs with
  exhausted attempts. If unset, the script prints `would dlq: <job_id>`.
- `WATCHDOG_STALE_SECS`: stale threshold in seconds; default `3600`.

Verify the wiring with a dry-run fixture before enabling action commands:

```sh
now=$(date +%s); old=$((now - 7200)); fresh=$((now - 60)); \
tmp=$(mktemp); printf 'job-old\tclaimed\t%s\t1\t3\njob-dlq\tclaimed\t%s\t3\t3\njob-fresh\tclaimed\t%s\t0\t3\n' "$old" "$old" "$fresh" >"$tmp"; \
WATCHDOG_STALE_SECS=3600 adapters/hermes/stale-claim-watchdog.sh --workspace ~/.hermes/profiles/<profile>/workspace --ledger-file "$tmp" --dry-run
```

## Cron wrapper pattern

For cron-driven verifier, watchdog, or Luca task-runner jobs, copy
`templates/cron-wrapper.tmpl.sh` into the profile workspace, for example
`<workspace>/scripts/cron-wrapper.sh`, and make the copy executable. Set `TARGET` to
the absolute adapter/script path and pass the target arguments after the wrapper.

```cron
*/5 * * * * CATY_HARNESS_ROOT=/opt/caty-agent-harness TARGET=/opt/caty-agent-harness/scripts/task-runner.sh SECRETS_ENV=/path/to/secrets/cron.env /path/to/hermes-home/profiles/example/workspace/scripts/cron-wrapper.sh /path/to/hermes-home/profiles/example/workspace >>/path/to/hermes-home/profiles/example/workspace/loop/task-runner-cron.log 2>&1
```

Adapter stdout is now captured per attempt in `attempts/NNN/model.stdout` and no longer appears in the tick log.

`SECRETS_ENV` is optional. When set and present, the wrapper sources it only if it is
owned by the cron user and has `0600` or `0400` permissions. Put environment values
such as `TR_SPAWN_STEP`, `HERMES_STEP_CMD`, `HERMES_PROBE_CMD`, and `TR_PUSH_CMD` in
that file instead of expanding secrets directly in crontab. `install.sh --check`
remains read-only: its Hermes conformance row reads and hashes the configured wrapper,
provider, probe, and evidence files without executing them.

## Destructive-command policy

Never run the denylisted destructive commands (`git reset --hard`, `git checkout -- <path>`,
`git clean -f`, `git push --force`, history rewrites, or `rm -rf` outside the task artifact
directory) without an approval file. `loop/approvals/<task-id>` must name the exact command.
Cron-driven sessions have no approver and are deny-by-default.
