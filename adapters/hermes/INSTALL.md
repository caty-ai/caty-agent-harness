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

   Two provider shapes share the same wrapper contract. The API-backed reference is
   available as three distinct, directly inspectable files:

   - `adapters/hermes/examples/verifier-wrapper.sh` validates the argv bundle and
     rejects missing, malformed, or multiple verdicts.
   - `adapters/hermes/examples/verifier-provider.py` makes one stateless API call;
     set `VERIFIER_API_KEY` through the job's protected `SECRETS_ENV`, and optionally
     set `VERIFIER_MODEL`. `ANTHROPIC_API_KEY` remains a backward-compatible fallback.
   - `adapters/hermes/examples/verifier-probe.sh` relocates and genuinely calls the
     provider through the wrapper before reporting conformance.

   The CLI-backed shape uses the unchanged `verifier-wrapper.sh` with
   `verifier-provider-cli.sh` and `verifier-probe-cli.sh`. Both shapes remain
   supported. This Hermes family deploys the CLI-backed shape by owner decision on
   2026-08-14; the API client remains available for other deployments.

   **Claude Code CLI configuration (no API key).** Authenticate the CLI as the job
   uid, then set the absolute binary path and optional model in the job environment:

   ```sh
   VERIFIER_CLI_BIN=$HOME/.local/bin/claude
   VERIFIER_MODEL=claude-sonnet-5
   ```

   `VERIFIER_CLI_BIN` defaults to `$HOME/.local/bin/claude`; the provider never uses a
   `PATH` lookup. It delivers the fenced bundle prompt on stdin from a private temporary
   file and launches the CLI with print mode, no tools, no session persistence, strict
   empty MCP configuration, and safe mode. Before launch it rebuilds the child
   environment with `/usr/bin/env -i`, keeping only `HOME` for subscription credential
   discovery, a fixed `PATH=/usr/bin:/bin`, `TMPDIR` pointed at the provider's private
   temporary work directory, and `HTTPS_PROXY`, `HTTP_PROXY`, and `ALL_PROXY` only when
   each variable is set in the parent environment. Set-but-empty proxy variables are
   forwarded as empty because they are still present; every other parent variable is
   dropped structurally by `env -i`. The CLI must therefore be authenticated through the
   login discovered via `HOME`; token/config-directory overrides such as
   `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CONFIG_DIR` are deliberately absent. This
   matters for both trust and billing: if `ANTHROPIC_API_KEY` survives, the CLI
   authenticates with that key and incurs metered API usage instead of using the
   logged-in subscription. The provider also starts the CLI in a fresh neutral
   temporary directory and removes it on exit.

   Because `PATH` is fixed, the CLI named by `VERIFIER_CLI_BIN` must be a
   self-contained executable or have its interpreter and any helper it spawns within
   `/usr/bin:/bin`; an interpreter elsewhere, such as under a home directory or
   Homebrew prefix, fails only when the production attest invokes it. Only the
   uppercase `HTTPS_PROXY`, `HTTP_PROXY`, and `ALL_PROXY` names are forwarded;
   `NO_PROXY` and lowercase `http_proxy`, `https_proxy`, and `all_proxy` are dropped,
   so any host that needs them must re-export the uppercase variables in the job
   environment.

   This is a mandatory defense against the **checkpoint stop-hook final-message
   replacement hazard**: in this family, a host checkpoint hook has replaced the final
   `claude --print` response, destroying a 36-item translation batch and swallowing two
   review-seat verdicts. Safe mode blocks custom hooks, while the neutral directory
   prevents project discovery from reintroducing workspace-local interference. No
   tools and strict empty MCP configuration close the remaining model access paths. A
   swallowed, empty, or malformed response fails the provider and wrapper checks, so it
   becomes gate noise/`needs-human`, never a false pass.

   Safe mode is not an absolute sandbox: admin-managed policy settings still apply, and
   built-in tools/permissions otherwise work normally. Tool denial here comes from
   `--tools ""` and `--allowedTools ""`; the residual policy-setting boundary is
   accepted, and every empty or malformed reply still fails closed. `--bare` is not a
   substitute because it disables OAuth/keychain credential discovery and would force
   API-key authentication, defeating this deployment's subscription-auth goal.

   The CLI attestation boundary is narrower than the API-client file boundary:
   `provider_sha256` pins only `verifier-provider-cli.sh`. It does not pin the Claude
   CLI binary, CLI settings files, or login state. `provider_version` records the model
   label plus the first 16 hex characters of the CLI binary hash that the probe
   exercised. This is an honest identity record, not enforcement: the runtime gate does
   not re-derive that value, so a later CLI auto-update does not invalidate existing
   evidence. Re-attest after changing any of those inputs and at least every three days.
   Login expiry makes the real probe fail; at runtime it fails closed to `needs-human`,
   and the three-day re-attestation cadence surfaces it even if no verifier job has run.

   Attest the CLI-backed shape with the authenticated job uid:

   ```sh
   HARNESS=/absolute/path/to/caty-agent-harness
   VERIFIER_CLI_BIN="$HOME/.local/bin/claude" \
     PROBE_PROVIDER_PATH="$HARNESS/adapters/hermes/examples/verifier-provider-cli.sh" \
     "$HARNESS/scripts/attest-wrapper" --route verifier \
       --wrapper "$HARNESS/adapters/hermes/examples/verifier-wrapper.sh" \
       --probe "$HARNESS/adapters/hermes/examples/verifier-probe-cli.sh"
   ```

   For the API-backed shape, Anthropic remains the default: set an Anthropic key in
   `VERIFIER_API_KEY`, optionally set `VERIFIER_MODEL`, and leave
   `VERIFIER_API_BASE` unset to use `https://api.anthropic.com`.

   **Z.ai GLM 5.2 configuration.** Set these values through the job's protected
   `SECRETS_ENV`:

   ```sh
   VERIFIER_API_KEY=<Z.ai member key>
   VERIFIER_MODEL=glm-5.2
   VERIFIER_API_BASE=https://api.z.ai/api/anthropic
   ```

   `SECRETS_ENV` is an additive overlay. When switching vendors, remove or overwrite
   the old key line: a leftover key for vendor A will be sent to vendor B. Prefer
   `VERIFIER_API_KEY` for both vendors; `ANTHROPIC_API_KEY` is accepted only as a
   backward-compatible fallback when the preferred variable is unset or empty.

   The conformance gate pins the staged wrapper, provider, and probe files by SHA-256,
   plus the TTL and recorded behavioral flags. It does not pin the API key,
   `VERIFIER_API_BASE`, or live `VERIFIER_MODEL`; `provider_version` is only the model
   label present at attestation time, not the model actually served. Re-attesting after
   a vendor, model, or endpoint change is therefore an operator duty the gate cannot
   enforce today; a follow-up issue tracks gating the endpoint and served model in the
   evidence record.

   Operational contract: the example providers and wrapper forward only the validated
   verdict and reason lines. They normalize each model-reply line by removing a trailing
   carriage return and trailing ASCII whitespace, and remove DEL plus all C0 controls
   except TAB from the emitted reason; a mid-line TAB is preserved. They require exactly
   one anchored allowed verdict line anywhere in the reply and exactly one `VERDICT:`
   occurrence across the entire model reply; before line parsing or normalization, they
   reject any NUL byte
   anywhere in the provider/model reply. The reason is the first line after the verdict
   that is nonempty after ignoring ASCII whitespace and the explicit U+00A0, U+3000, and
   U+200B sequences; those Unicode sequences remain byte-preserved in an accepted nonempty
   reason, while missing or ambiguous verdicts and missing reasons fail closed.
   Findings before the verdict and
   content after the selected reason are intentionally discarded to remove an injection
   surface; that body cannot be recovered from these examples. The provider prompts align
   with the bundle's last-two-lines instruction while the parser also accepts a valid
   verdict-first reply. A reply containing solely one quoted or injected anchored marker
   and a following reason, with no additional `VERDICT:` text, is indistinguishable from
   an authentic decision and is adopted; uniqueness is the defense against ambiguity, not
   proof of provenance. When using an example as a production `VERIFIER_CMD`, operators
   must monitor the `needs-human` rate for formatting flakiness and anomalous replacement.
   `VERIFIER_TEMPERATURE` is sent as given, so a model that constrains temperature may
   reject the request; this normalizes to wrapper exit 70 and `needs-human`. Model id
   and temperature are therefore coupled configuration.

   Attesting the example performs a real provider request and therefore requires a
   valid key:

   ```sh
   HARNESS=/absolute/path/to/caty-agent-harness
   ATTEST_TIMEOUT_S=180 PROBE_PROVIDER_PATH="$HARNESS/adapters/hermes/examples/verifier-provider.py" \
     "$HARNESS/scripts/attest-wrapper" --route verifier \
       --wrapper "$HARNESS/adapters/hermes/examples/verifier-wrapper.sh" \
       --probe "$HARNESS/adapters/hermes/examples/verifier-probe.sh"
   ```

   The 180-second attestation bound exceeds the provider's 120-second HTTP default,
   so a valid slow response is not cut off by the attester's shorter default.

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
      ATTEST_TIMEOUT_S=180 scripts/attest-wrapper --route verifier --wrapper /abs/verifier-wrapper.sh --probe /abs/verifier-probe.sh
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

## Flush intake consumer

Hermes CHECKPOINT flushes use the shared deterministic fold through
`adapters/hermes/flush-intake.sh`. Schedule it as a LaunchAgent every eight hours by
copying `templates/cron-wrapper.tmpl.sh` into the workspace and setting the plist's
`ProgramArguments` to `/bin/bash`, the copied wrapper path, and the absolute workspace
path as the wrapper's single positional target argument. Set these environment values:

```text
TARGET=/absolute/path/to/caty-agent-harness/adapters/hermes/flush-intake.sh
CATY_HARNESS_ROOT=/absolute/path/to/caty-agent-harness
INTAKE_MAX_FOLD=5
```

Set the LaunchAgent `StartInterval` to `28800`. Hermes jobs use
`INTAKE_MAX_FOLD=5` so the cap-60 Lessons FIFO has a bounded, gradual eviction rate
instead of replacing a large share in one run.

Leave `DEADMAN_MARKER` unset for this Hermes target. The cron wrapper's self-marking
allowlist recognizes only the Claude Code intake entry path; setting a marker for the
Hermes path would pre-touch it before intake and could mask lock starvation or an
intake failure. The Hermes intake writes its own successful-run receipt and distill
marker after the guarded fold completes.

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

For cron-driven verifier, watchdog, or task-runner jobs, copy
`templates/cron-wrapper.tmpl.sh` into the profile workspace, for example
`<workspace>/scripts/cron-wrapper.sh`, and make the copy executable. Set `TARGET` to
the absolute adapter/script path and pass the target arguments after the wrapper.

```cron
*/5 * * * * CATY_HARNESS_ROOT=/opt/caty-agent-harness TARGET=/opt/caty-agent-harness/scripts/task-runner.sh SECRETS_ENV=/path/to/secrets/cron.env /path/to/hermes-home/profiles/example/workspace/scripts/cron-wrapper.sh /path/to/hermes-home/profiles/example/workspace >>/path/to/hermes-home/profiles/example/workspace/loop/task-runner-cron.log 2>&1
```

Adapter stdout is now captured per attempt in `attempts/NNN/model.stdout` and no longer appears in the tick log.

`SECRETS_ENV` is optional. When set and present, the wrapper parses it as data-only
`KEY=VALUE`, one assignment per physical line; it does not source or execute the file.
The file must be owned by the cron user, have `0600` or `0400` permissions, and not be
a symlink. Interpreter- and loader-control names are refused by a deliberately
non-exhaustive hazard guard. Store a multi-line secret in its own file and put that
file's path in `SECRETS_ENV`. Put ordinary values such as `TR_SPAWN_STEP`,
`HERMES_STEP_CMD`, `HERMES_PROBE_CMD`, and `TR_PUSH_CMD` in the env file instead of
expanding secrets directly in crontab. Portable Bash 3.2 cannot open with
`O_NOFOLLOW`; pre/post-open identity checks narrow, but do not eliminate, a residual
path replacement race. `install.sh --check` remains read-only: its Hermes conformance
row reads and hashes the configured wrapper, provider, probe, and evidence files
without executing them.

When configured, `push.log` persists the push command's combined output; bash-level
errors are redacted. Keep secrets out of command-name position and out of helper output.
`push.log` is append-only, with one block per tick while failing, and operator-trimmed.

## Destructive-command policy

Never run the denylisted destructive commands (`git reset --hard`, `git checkout -- <path>`,
`git clean -f`, `git push --force`, history rewrites, or `rm -rf` outside the task artifact
directory) without an approval file. `loop/approvals/<task-id>` must name the exact command.
Cron-driven sessions have no approver and are deny-by-default.
