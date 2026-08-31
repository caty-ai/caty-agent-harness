# Caty Agent Harness — Reference

[English](reference.md) | [日本語](reference.ja.md) ｜ back to the [front page](../README.md) ｜ [engineering guide](engineering.md)

Exact flags, states, and the contract documents. When this page and a design document disagree, the design document is the source of truth.

---

## install.sh command reference

```text
./install.sh [--workspace <dir>]
./install.sh --hermes <profile> [--append-bootstrap <file>]
./install.sh --openclaw <workspace-dir> [--append-bootstrap <file>]
./install.sh [--workspace <dir>] --bootstrap-runtime <runtime> --append-bootstrap <file>
./install.sh --check [--workspace <dir>]
./install.sh --disable --workspace <dir> [--dry-run]
./install.sh --enable --workspace <dir> [--dry-run]
./install.sh --help
```

| Mode | Behavior |
| --- | --- |
| no args | initialize the current directory via `scripts/loop-init --workspace "$PWD"` |
| `--workspace <dir>` | initialize `<dir>`; creates missing scaffold only, never replaces existing files |
| `--hermes <profile>` | initialize `$HOME/.hermes/profiles/<profile>/workspace`, print the Hermes bootstrap block and remaining manual wiring steps |
| `--openclaw <workspace-dir>` | initialize the workspace, print the OpenClaw bootstrap block, a cron template, and the `STAGING_DIR` relocation note |
| `--append-bootstrap <file>` | idempotently append the selected bootstrap block; prints `skip: bootstrap already present` if the marker is already in the file |
| `--bootstrap-runtime <claude-code\|codex\|kimi\|hermes\|openclaw>` | select the marker-aware block used by `--append-bootstrap`; generic mode keeps `openclaw` only as a legacy compatibility default |
| `--check [--workspace <dir>]` | read-only health check; exits `1` when required layout, `STATE.md` headers, or pause-control path safety is invalid |
| `--disable --workspace <dir> [--dry-run]` | reversible workspace pause; preserves `STATE.md`, learning records, queued work, verification history, skills, and artifacts |
| `--enable --workspace <dir> [--dry-run]` | resume a paused workspace; removes only the harness-owned regular `DISABLED` marker and never follows hostile marker objects |

The idempotency marker for appended bootstrap blocks is the literal line `# caty-agent-harness bootstrap v2` (a machine marker; it is not renamed when the product name changes).
Workspace initialization also creates `loop/.tr-interpreters`, a two-line record of
the absolute Bash and Perl executables used by both donecheck validation and execution.
Pre-existing workspaces create it on first enqueue/runner use; invalid entries fail closed.

---

## --check semantics

- A healthy required layout ends with `ok: required layout and STATE.md headers present`.
- Exit codes: `0` = required layout healthy (optional rows may still FAIL); `1` = required layout, `STATE.md` headers, or pause-control path safety invalid; `2` = usage error or rejected hostile/unsafe object.
- Optional learning-path rows (verifier availability, cron wiring, wrapper conformance) can show `FAIL` while the exit code stays `0`; a `FAIL` row means that runtime's loop is not fully operational yet.
- Learning-path conformance rows read and hash configured wrappers, probes, providers, and evidence files without executing them.
- Adapter authors should set `SKILL_DESC_MAX` (bytes) to the measured CONSULT loader budget.

<a id="pause-states"></a>

## Pause states reported by --check

| State | Meaning |
| --- | --- |
| `paused` | every registered bootstrap is current and pause-aware |
| `paused-partial-legacy-bootstrap` | a legacy bootstrap remains; current registered automated entry points are hard-paused, but the legacy instruction is only partially covered |
| `paused-soft-unknown` | no complete managed-bootstrap record is available; do not claim a full interactive pause |

---

## Flush intake consumer receipts

The flush intake consumer's accounting ledger is `loop/pending/intake-runs.log`. The deadman `distill` marker proves only that intake ran; inspect the ledger for content-level silence, dedup, deferral, eviction, rejection, and quarantine counts. The `rejected` field records content-level rejection of invalid-UTF-8 candidates. The `loop/archive/` raw layer is append-only and is never auto-pruned; see [DESIGN.md §3.1](design/DESIGN.md#31-files-per-agent-workspace) for its exact membership. See [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) for the full ledger format and scheduling.

## Raw-layer cross-model review

```text
scripts/raw-review.sh --workspace <path> [--week <YYYY-Www>] [--dry-run]
```

Without `--week`, the command reviews whole raw files from the current UTC ISO week and
the preceding configured weeks, plus files arriving after the last successful nightly
snapshot. `--week` selects a retroactive window ending at that week. `--dry-run` builds
and byte-counts the same prompt and lists its files without calling a reviewer or
advancing the late-arrival watermark, and never writes or dispatches a notification.
Exit `0` means a validated run, `NO_GROUPS`, or a
pause skip; `1` means attempted review failed closed; `2` means usage/configuration did
not permit review. Every reachable workspace exit writes `loop/promotions/runs.log`;
its `error=` field uses `none`, `skipped-paused`, `lock-busy`, `chain-exhausted`,
`config`, `prompt-too-large`, or `source-normalization` (a cited raw file could not be
normalized for citation validation — fails closed like the chain classes).
THEME blocks may be separated by blank lines, but blank lines inside a block are invalid.
Each member citation must normalize to 8–200 characters and match the start of a normalized
source line after leading indentation, one bullet marker, an ISO date prefix, conservative
machine tags with no internal whitespace that contain at least one ASCII digit or `-` and are
followed by space or tab, and paired emphasis markers such as `**bold**` / word-adjacent
`*bold*` are stripped for comparison. Human warning tags such as `[IMPORTANT]` or `[NEVER]`,
and meaningful lone/glob `*` tokens, remain significant. Shorter, mid-line-only,
or fabricated citations reject the complete block. The whole reviewer call fails when fabricated
blocks reach `max(fabricated_floor, ceil(fabricated_pct% of blocks))`; `fabricated_pct`
defaults to 50 and accepts values from 1 through 100. Numeric `loop/review.conf` values are
parsed as decimal, so values such as `08` and `0100` mean 8 and 100.

Configure the reviewer route with enough output tokens for about 30 THEME blocks; for
claude-CLI-wrapped chains, size `CLAUDE_CODE_MAX_OUTPUT_TOKENS` accordingly. An output-capped
route can print one unfenced `API Error: ...` line, which fails the call as invalid grammar
(fail-closed); correct the route configuration rather than the harness.

The shipped `loop/review.conf` is fully commented and therefore informationally unwired;
`review-config` is reserved for partial or malformed wiring. Enabling an
uncommented `producer=` and `reviewer` line is explicit consent for each scheduled run
to send the selected raw lesson files **whole** to that reviewer's configured provider
(the example reviewer name is GLM). The declared producer and reviewer must differ.
Schedule one nightly invocation in the runtime-neutral scheduler of your choice. On
macOS, use a LaunchAgent whenever any configured reviewer command invokes `claude`;
cron is suitable only for chains that do not need Claude CLI Keychain access.

`notify_cmd` is optional argv, never shell-evaluated, and receives the appended
notification file path as `$1` (before any configured fixed arguments). `install.sh --check` reports
`review-config` for partial or malformed wiring, unread review notifications, a wired review silent for over 48 hours,
and a zero-candidate streak at its configured threshold.

## Promotion apply consumer

```text
scripts/apply-promotions.sh --workspace <path> [--auto-capability-facts]
  [--approve <theme-id>]... [--approve-file <manifest>]...
scripts/apply-promotions.sh --workspace <path> --rollback <theme-id> --reason <ref>
```

The consumer accepts only anchored `candidates-<UTC-runid>-<pid>.md` names and
never consumes `.rejects.md`. A bare run leaves `STATE.md` unchanged, reports
approval-pending facts and rules, and creates draft skill stubs. Explicit approval
promotes a named fact or rule; `--auto-capability-facts` enables the separately
bounded capability-fact path. `APPLY_MAX_PER_SECTION` defaults to 20 and
`APPLY_MAX_AUTO` defaults to 10. It also honors `APPLY_LOCK_ATTEMPTS`,
`APPLY_PROMOTIONS_LOCK_ATTEMPTS`, `APPLY_STATE_LOCK_ATTEMPTS`,
`APPLY_LOCK_SLEEP_S`, `APPLY_STATE_LOCK_SLEEP_S`, `APPLY_LOCK_STALE_S`, and the
test-only seams `APPLY_TEST_CRASH_AFTER_STUB_MKDIR`,
`APPLY_TEST_CRASH_BETWEEN_STATE_AND_INDEX`, `APPLY_TEST_CRASH_AFTER_PHASE2`, and
`APPLY_TEST_FORCE_PHASE3_LOCK_BUSY`. Durable-section caps come from
`lib-state-fold.sh` and are enforced by refusal. `loop/promotions/apply-index.tsv`
is the idempotency authority, while append-only `apply.log` carries run-start,
transition, and summary receipts. Rollback invalidates only an apply-stamped entry
or an unchanged apply-generated staging stub. Exit codes are `0` for success or a
paused skip, `1` for an operational refusal, and `2` for usage or invalid numeric
configuration.

## Task-runner execution boundary

- Task frontmatter requires `receipt:` matching
  `^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$`, with `.` and `..` segments forbidden.
  Delivery additionally requires that target to be a non-symlink, non-empty regular
  file resolving inside the task artifact's own non-symlink `out/` directory.
- Donecheck fences must start at column zero. A column-zero fence inside a heredoc
  terminates extraction textually and is therefore prohibited.
- Donechecks receive only `TASK_ID`, `TASK_FILE`, `ARTIFACT_DIR`, `TR_DC_CWD`, fixed
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, any set `HOME`/`LANG`/`LC_ALL`/`TZ`, and
  shell-created variables. Tools such as `python3` (3.9+) must be reachable in that fixed
  `PATH` or invoked by absolute path. The bundled `templates/examples/img-pilot.task.md`
  donecheck depends on `python3` there; macOS ships `/usr/bin/python3`, while Linux
  distributions may not. Other inherited variables disappear and dependent checks
  fail loudly.
- `TR_SPAWN_STEP`, `HERMES_STEP_CMD`, `HERMES_PROBE_CMD`, and `TR_PUSH_CMD` are
  executed directly as argv with no shell re-expansion. `TR_SPAWN_STEP` remains one
  absolute argv word and still additionally must be an absolute executable-file
  path, so relative or PATH-resolved `TR_SPAWN_STEP` configurations must migrate
  before running the runner. `HERMES_STEP_CMD`, `HERMES_PROBE_CMD`, and
  `TR_PUSH_CMD` are whitespace-split into argv arrays and may use PATH-resolved
  regular executable names.
- `TR_LEDGER_FOLD_TOTAL_MAX_BYTES` is the per-attempt sentinel fold budget
  (default 16 MiB). `TR_LEDGER_FOLD_MAX_BYTES` is the bounded fold loop chunk
  size (default 4 MiB), not a per-pass ceiling. When the total budget is
  exhausted, that attempt becomes permanently fold-quiescent and its receipt
  remains `fold_complete:false`.

Each feature-era task artifact has an append-only `ledger.jsonl`. The task
runner is its sole writer: it adds the `init` record, folds complete lines from
each attempt's `sentinel-events.jsonl` under driver-owned task/attempt/run/seq
identity, and projects versioned task-level `task_end` records. Malformed source
lines are retained with `schema:"raw"` and `parse_error:true`; budget or
oversize loss is explicit in `fold_done`, `fold_oversize_line`, and the terminal
`fold_exhausted` record. Ledger failures are fail-open telemetry failures and do
not roll back a delivered/DLQ transition.

`task-end.json` is the atomic task-level receipt. Its first `ts`, `started_at`,
`outcome`, and `terminal_reason` are immutable. Reconciliation increments
`receipt_version` only when the folded-state fingerprint changes, repairs the
evidence aggregates, recomputes `fold_complete`, and independently ensures one
valid ledger projection for the current receipt version. `delivered` always
maps to `completed`; a DLQ maps to `overflowed` only when the final driver
classification is `window-error`, otherwise to `aborted`. Sentinel
`window_error` is evidence and never controls that outcome.

### Claude Code overflow sentinel environment

The Claude Code adapter validates these values before spawning the CLI. Invalid
values exit 2. With `OVF_SENTINEL` unset or empty, sentinel settings other than
the CLI selector `OVF_STEP_CMD` are ignored and sentinel behavior is off: the CLI
receives `prompt.md` on stdin directly, keeps the full exported
`TR_STEP_TIMEOUT_S` budget, stdout remains unchanged, and no sentinel artifact
is created.

| Variable | Contract |
| --- | --- |
| `OVF_SENTINEL` | unset/empty = off; otherwise exactly `shadow` or `active` |
| `OVF_T_ABS` | optional integer >= 1; forwarded only when set — unset resolves through the threshold order (explicit override, then the per-model table, then the product default `80000`), and the winning tier is recorded per key in `run_meta.threshold_sources` |
| `OVF_W_PCT` | optional integer 1–99, converted by dividing by 100; forwarded only when set — unset resolves like `OVF_T_ABS` (product default `0.50`) |
| `OVF_MODEL_ALIASES` | optional JSON object mapping model-id aliases to canonical ids (strings; trimmed and lowercased; single-step, no chains); invalid values exit 2 before spawn |
| `OVF_MODEL_THRESHOLDS` | optional JSON object `{"models": {"<exact-id-or-glob>": {"T_abs"?, "w"?}}, "N_drift"?, "theta_drift"?}`; entries are partial per-key overrides; matching is canonical exact id, then longest-literal-prefix glob (`*` only); duplicate or unknown keys, two patterns whose literal prefixes are identical, and out-of-range values exit 2 before spawn; placeholder defaults `N_drift` `5` / `theta_drift` `0.10`; ships empty, so every model uses the explicit/default tiers until values are written back |
| `OVF_CTX_WINDOW` | optional integer >= 1; first context-window ladder rung |
| `OVF_HF_CONFIG` | optional local non-symlink HF `config.json` path (or its directory); no network lookup |
| `OVF_HF_NETWORK` | unset/empty/`0` = disabled; `1` enables one best-effort HF network rung |
| `OVF_HF_CACHE_DIR` | required when `OVF_HF_NETWORK=1`; writable cache dir whose leaf path is not a symlink, with a non-symlink cache-entry file leaf as well (symlinked ancestors allowed), created/forced as mode `0700` |
| `OVF_COMPACTION_OWNER` | `sentinel` or `host`; unset warns and selects `sentinel`; `host` records `disabled-host` |
| `OVF_STEP_CMD` | whitespace-split CLI argv; default `claude -p --output-format stream-json --verbose` |
| `OVF_FINALIZE_TIMEOUT_S` | integer >= 1; default `10`; bounded monitor join after CLI exit |
| `CLAUDE_MODEL` | actual model identifier; unset records `claude-unknown`, which is short-circuited to `default` before catalog lookup rather than matching the `claude-` catalog prefix |

Context-window resolution is config, validated local HF config, an opt-in HF
network cache rung, a Claude-family prefix catalog, then the 200k default. The
network rung validates `CLAUDE_MODEL` as a plain HF repo id, performs one
stdlib `urllib` fetch against
`https://huggingface.co/<model>/resolve/main/config.json` with a hard 5-second
timeout, writes a flat `sha256(model).json` cache entry under `OVF_HF_CACHE_DIR`,
then re-reads that cache entry with the same 1 MiB limit before accepting it.
Both the cache directory leaf and the cache entry file leaf must not be
symlinks, while symlinked ancestors are accepted. Both the network payload and
cached entry accept bytes up to that exact limit and reject anything larger. The
selected source is
logged as `config`, `hf-config`, `hf-network-cached`, `catalog`, or `default`;
the `claude-unknown` placeholder is short-circuited to `default` before catalog
lookup. Any HF id validation, cache validation, cache I/O, or fetch failure emits
one warning to stderr and
falls through to the catalog/default ladder without changing the model-step exit
status.

TTFB is run start to the first `assistant` stream line. The token tiers are 90s,
150s when the prior attempt's last injected MA is strictly above 50k, and 240s
when strictly above 100k. No prior state and unlisted models use 240s. Named
reasoning floors are: `claude-opus*` 240s, `qwen3*` 180s, `qwq*` 300s,
`glm-5*` 300s, `grok-*` 300s, `deepseek-r1*` 600s, and `o1*`/`o3*` 600s.
These floors create `alert` records only; they never terminate the CLI.

An observed `system/compact_boundary` resets the measured series, withdraws a
pending nudge, and sets `runtime_compaction=true`. When that event is absent, the
strict greater-than-40% injected drop remains the fallback heuristic. This
mixed-magnitude heuristic can suppress one otherwise valid nudge; that bounded
false positive is an accepted v1 cost.

A model or runtime change between turns triggers exactly one regime reset on
the switch turn (canonical model identity is trimmed and lowercased with one
`OVF_MODEL_ALIASES` lookup; a turn without an identity field neither compares
nor resets). The reset clears the measured series, the pending nudge, the
per-axis nudge hysteresis, and the drift accumulators, then re-resolves all
model-keyed config — the context window (a run-level `OVF_CTX_WINDOW` override
still wins), `T_abs`/`w` through the threshold order, and the TTFB floor —
records a `regime_change` event with the from/to identities, resolved values,
and per-key sources, and evaluates the switch turn as the first sample of the
new regime. The compaction drop heuristic is never evaluated across a regime
boundary, and the persisted regime identity also detects a model-changing retry
at the attempt boundary.

Each regime's tap is additionally reconciled (the third instrument state: "the
tap lied", alongside "didn't fire" and "couldn't see"). The Claude Code adapter
declares `drift_reference: derived` and persists each turn's verbatim raw usage
object; core replays the normalization over the ledger each turn and, every
`N_drift` turns, compares the paired cumulative sums — reference-missing turns advance the
cadence but drop out of both sums — recording an episode-triggered,
direction-agnostic `tap_drift` event when `|bias_ratio| > theta_drift`, and a
`schema-change` episode when the raw-usage field set changes within a regime.
v1 is log-only: `tap_drift` never fires, nudges, or disables anything, and
derived counts are never evidence of provider drift.

Hysteresis-blocked predicate crossings intentionally append no `fire` event to
avoid event floods. They remain reconstructable from the append-only `turn`
series. On slope-only fires, `threshold_hit` is omitted because neither level
threshold crossed.

`sentinel-events.jsonl` is append-only and contains `turn`, `fire`, `alert`,
`regime_change`, `tap_drift`, and per-run `attempt_end` records. Turn records
carry `runtime` and, whenever the drift capability is not `none`, the verbatim
`raw_usage` object; `attempt_end` and the folded task-level receipt carry
`regime_change_resets`, `tap_drift_count` (episodes), and
`drift_reference_status` (the weakest capability across the task's regimes).
The task runner folds those records into the
per-task ledger and emits the distinct task-level `task_end` described above.
`attempt.json` is atomically finalized with exactly
these fields: `schema_version`, `task_id`, `attempt`, `mode`, `model`,
`ctx_window`, `ctx_window_source`, `started_at`, nullable `first_byte_at`,
`cli_exit_code`, `tap_status_final`, `fired`, and `events_path`. Attempt identity
is the zero-padded attempt-directory basename string. A timeout or signal death
quarantines a model-written `step-result.json` as `step-result.json.partial`.
See §3–§6 of the
[overflow sentinel DESIGN](design/159-overflow-sentinel/DESIGN.md) for the
event-field contracts.

---

## Contract documents

| Document | Contract |
| --- | --- |
| [DESIGN.md](design/DESIGN.md) | learning-loop contracts, verification seam, promotion rules, and adapter contracts |
| [DESIGN-task-runner.md](design/DESIGN-task-runner.md) | task-runner contract, budgets, DLQ, and metrics |
| [159 overflow sentinel DESIGN](design/159-overflow-sentinel/DESIGN.md) | overflow predicate, tap, TTFB, event, and nudge contracts |
| [governance-rules.md](governance-rules.md) | family adoption governance canon (governance R1–R14; amendment status and effectiveness gates) |
| [plugin-convention.md](plugin-convention.md) | plugin seam contract and extraction policy |
| [plugins.md](plugins.md) | known plugin registry and attachment status |
| [updater-rollout.md](updater-rollout.md) | release-tag updater rollout and operational constraints |

## Adapter installation documents

| Runtime | Document |
| --- | --- |
| Claude Code | [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) |
| Codex CLI | [adapters/codex/INSTALL.md](../adapters/codex/INSTALL.md) |
| Kimi Code CLI | [adapters/kimi/INSTALL.md](../adapters/kimi/INSTALL.md) |
| Hermes Agent | [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) |
| OpenClaw | [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) |
