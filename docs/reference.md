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

---

## Contract documents

| Document | Contract |
| --- | --- |
| [DESIGN.md](design/DESIGN.md) | learning-loop contracts, verification seam, promotion rules, and adapter contracts |
| [DESIGN-task-runner.md](design/DESIGN-task-runner.md) | task-runner contract, budgets, DLQ, and metrics |
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
