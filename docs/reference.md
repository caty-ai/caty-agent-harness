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

The flush intake consumer's accounting ledger is `loop/pending/intake-runs.log`. The deadman `distill` marker proves only that intake ran; inspect the ledger for content-level silence, dedup, deferral, eviction, and quarantine counts. The `loop/archive/` raw layer is append-only and is never auto-pruned; see [DESIGN.md §3.1](design/DESIGN.md#31-files-per-agent-workspace) for its exact membership. See [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) for the full ledger format and scheduling.

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
source line after leading indentation/bullet/date/`[tag]` markers are stripped for comparison;
shorter, mid-line-only, or fabricated citations reject the complete block. The whole reviewer
call fails when fabricated blocks reach `max(fabricated_floor, ceil(fabricated_pct% of blocks))`;
`fabricated_pct` defaults to 50 and accepts values from 1 through 100.

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

## Task-runner execution boundary

- Task frontmatter requires `receipt:` matching
  `^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$`, with `.` and `..` segments forbidden.
  Delivery additionally requires that target to be a non-symlink, non-empty regular
  file resolving inside the task artifact's own non-symlink `out/` directory.
- Donecheck fences must start at column zero. A column-zero fence inside a heredoc
  terminates extraction textually and is therefore prohibited.
- Donechecks receive only `TASK_ID`, `TASK_FILE`, `ARTIFACT_DIR`, `TR_DC_CWD`, fixed
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, any set `HOME`/`LANG`/`LC_ALL`/`TZ`, and
  shell-created variables. Tools such as `python3` must be reachable in that fixed
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
| `OVF_T_ABS` | integer >= 1; default `80000` tokens |
| `OVF_W_PCT` | integer 1–99; default `50`, converted by dividing by 100 |
| `OVF_CTX_WINDOW` | optional integer >= 1; first context-window ladder rung |
| `OVF_HF_CONFIG` | optional local non-symlink HF `config.json` path (or its directory); no network lookup |
| `OVF_COMPACTION_OWNER` | `sentinel` or `host`; unset warns and selects `sentinel`; `host` records `disabled-host` |
| `OVF_STEP_CMD` | whitespace-split CLI argv; default `claude -p --output-format stream-json --verbose` |
| `OVF_FINALIZE_TIMEOUT_S` | integer >= 1; default `10`; bounded monitor join after CLI exit |
| `CLAUDE_MODEL` | actual Claude model identifier; unset records `claude-unknown`, treated as unknown rather than matching the `claude-` catalog prefix |

Context-window resolution is config, validated local HF config, a Claude-family
prefix catalog, then the 200k default. The selected source is logged as `config`,
`hf-config`, `catalog`, or `default`; the `claude-unknown` placeholder always uses
`default`.

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

Hysteresis-blocked predicate crossings intentionally append no `fire` event to
avoid event floods. They remain reconstructable from the append-only `turn`
series. On slope-only fires, `threshold_hit` is omitted because neither level
threshold crossed.

`sentinel-events.jsonl` is append-only and contains `turn`, `fire`, `alert`, and
per-run `attempt_end` records. The task-level `task_end` event is deferred to the
ledger-confluence integration. `attempt.json` is atomically finalized with exactly
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
