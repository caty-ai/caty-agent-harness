# CLI output and exit conventions

This note records the current CLI contract. Slice #21a documents it without changing behavior; normalization decisions belong to #21b.

## Output prefixes and streams

- The warning house style is the literal lowercase prefix `warning: ` (colon and trailing space) on stderr (`install.sh:871-875`; `scripts/tr-enqueue:9-10`; `tests/check-tickprobe.test.sh:339`; `tests/check-tickprobe.test.sh:342-346`; `tests/tr-enqueue.test.sh:348-357`). OpenClaw Sentinel merges `--check` output before grepping `^(warning:|missing )`, so the leading `warning:` and `missing ` tokens are **FROZEN** consumer inputs (`adapters/openclaw/sentinel-cron.sh:65`; `adapters/openclaw/sentinel-cron.sh:69`).
- Current outliers are the uppercase `WARNING:` trio in the bounded helper, distill audit, and Hermes spawn path (`scripts/lib-bounded.sh:43-49`; `adapters/openclaw/distill-audit.sh:104-107`; `adapters/hermes/spawn_step.sh:132-135`). Those remain documented outliers because each producer has adapter self-copies, so migrating them fans out beyond this slice and is out-of-scope for #21b. The `deadman-probe:` and `cron-wrapper warning:` prefixes also remain unchanged (`scripts/deadman-probe.sh:64-66`; `templates/cron-wrapper.tmpl.sh:148-152`).

The machine row formats below are **FROZEN**:

| Row | Producer and consumer evidence |
| --- | --- |
| `missing path: ` | Emitted for absent required paths (`install.sh:882-884`) and consumed through Sentinel's `missing ` grep (`adapters/openclaw/sentinel-cron.sh:69`); its notice is pinned exactly (`tests/sentinel-cron.test.sh:40-44`). |
| `missing header: ` | Emitted for each absent required header (`install.sh:952-959`) and consumed through the same `missing ` grep (`adapters/openclaw/sentinel-cron.sh:69`). |
| `ok:` | The exact healthy terminator is emitted by the checker (`install.sh:1134`) and published as expected operator output (`docs/agent-guide.md:76`). |
| `learning path: adapter=X \| route=Y \| PASS\|FAIL` | The formatter fixes the separators and terminal status (`install.sh:707-723`); exact rows are asserted by the check and conformance suites (`tests/check-tickprobe.test.sh:252-256`; `tests/wrapper-conformance.test.sh:778-784`). |

Stdout carries machine rows beginning `state=`, `bootstrap_state=`, `check:`, `missing path:`, `missing header:`, `ok:`, and `learning path:` (`install.sh:707-712`; `install.sh:878-880`; `install.sh:952-955`; `install.sh:1134`). Human `warning:` advisories go to stderr (`install.sh:871-875`). The named regression contract is `check keeps machine tokens on stdout and human warnings on stderr` (`tests/check-tickprobe.test.sh:339-349`); the pause suite independently checks the same split (`tests/pause-contract.test.sh:207-215`).

`scripts/family-updater` captures merged `--check` output (`scripts/family-updater:229-239`), treats any non-zero result as update failure and rolls back (`scripts/family-updater:379-398`), and selects the first output line for the failure reason/headline (`scripts/family-updater:243-253`; `scripts/family-updater:388-403`). Therefore the first merged `--check` line is an observable surface: `state=` is the first stdout machine row in the enabled/healthy path (`install.sh:878-880`), but stderr advisories can precede it in that merged capture—`warning: pause state is indeterminate; ...` (`install.sh:871-872`) and `warning: pause-aware bootstrap coverage is unknown; ...` (`install.sh:874-875`)—so the first merged line is not guaranteed to be `state=`; the updater suite pins rollback plus the first-line reason (`tests/family-updater.test.sh:270-278`).

## Exit codes

| Code | Current meaning |
| --- | --- |
| `0` | Success for `--check`, including optional diagnostic `FAIL` rows (`docs/reference.md:40-42`). Task Runner also exits 0 without work when its workspace is paused (`scripts/task-runner.sh:53-55`). |
| `1` | `--check` contract failure for required layout, `STATE.md` headers, or pause-control path safety (`docs/reference.md:30`; `docs/reference.md:41`). `tr-enqueue` uses 1 for usage and validation rejects through its common failure path (`scripts/tr-enqueue:4-6`; `scripts/tr-enqueue:13-15`; `scripts/tr-enqueue:107-145`); usage=1 is a known deviation from sibling usage=2 and is pinned for #21b owner review (`tests/cli-conventions.test.sh:77-78`). Deadman Probe returns 1 when a new violation is found (`scripts/deadman-probe.sh:205-215`; `tests/deadman-probe.test.sh:109-117`). |
| `2` | Usage/configuration error in Task Runner (`scripts/task-runner.sh:8-10`; `scripts/task-runner.sh:58-64`), Metrics (`scripts/tr-metrics.sh:8-10`), Deadman Probe (`scripts/deadman-probe.sh:4-6`), Family Updater (`scripts/family-updater:34-44`), Loop Init (`scripts/loop-init:10-26`), Attest Wrapper (`scripts/attest-wrapper:38-71`), and `install.sh`'s `die_usage` path (`install.sh:71-77`). The previously unpinned cases are covered together in `tests/cli-conventions.test.sh:70-75`. |
| `3` | `tr-enqueue` reports a paused workspace (`scripts/tr-enqueue:120-123`), pinned by the pause suite and activation manifest (`tests/pause-contract.test.sh:217-221`; `scripts/activation-manifest.tsv:14`). Sentinel uses 3 for infrastructure errors (`adapters/openclaw/sentinel-cron.sh:52-54`; `adapters/openclaw/sentinel-cron.sh:71-74`). |
| `129`, `130`, `143` | Explicit HUP, INT, and TERM mappings where traps are installed, including Attest Wrapper, Deadman Probe, Hermes Verify Job, OpenClaw Distill Audit, Flush Intake, and Task Runner's explicit INT/TERM exits (`scripts/attest-wrapper:97-99`; `scripts/deadman-probe.sh:106-108`; `adapters/hermes/verify-job.sh:131-133`; `adapters/openclaw/distill-audit.sh:421-423`; `adapters/claude-code/flush-intake.sh:243-245`; `scripts/task-runner.sh:124-125`). |

Exit `1` is intentionally **OVERLOADED**: it can mean a rejected enqueue/check contract or a detected operational violation (`scripts/tr-enqueue:4-6`; `install.sh:1130-1131`; `scripts/deadman-probe.sh:212-215`). That overload is contractual, not accidental.

`scripts/task-runner.sh` owns the runner-side knobs `TR_SPAWN_STEP` and `TR_PUSH_CMD`, and `adapters/hermes/spawn_step.sh` owns the adapter-side knobs `HERMES_STEP_CMD` and `HERMES_PROBE_CMD`. None of them are re-expanded through a shell. `TR_SPAWN_STEP` is declared at `scripts/task-runner.sh:17` and validated as one absolute executable-file path at `scripts/task-runner.sh:58-64`. `TR_PUSH_CMD` is declared at `scripts/task-runner.sh:18`, receives the startup preflight at `scripts/task-runner.sh:69-71`, and is whitespace-split, PATH-resolved, and executed directly in the DLQ push path at `scripts/task-runner.sh:1425-1446`. `HERMES_STEP_CMD` and `HERMES_PROBE_CMD` share the same whitespace-split/PATH-resolved adapter contract (`adapters/hermes/spawn_step.sh:30-31`; `adapters/hermes/spawn_step.sh:85-107`).

## `--check` FAIL rows

Optional learning-path rows may print `FAIL` while `--check` exits 0; the reference states this explicitly (`docs/reference.md:41-43`), and the implementation says diagnostic `FAIL` does not change check semantics (`install.sh:814-820`). This behavior is **FROZEN** by consumers that assert exit 0 alongside `FAIL` or warning rows (`tests/check-tickprobe.test.sh:246-256`; `tests/skill-lint.test.sh:129-138`). Findings `d2a0fcca` and `f6442c21` are therefore resolved in #21a as “document, do not change.”

## Consumer and regression inventory

- OpenClaw Sentinel is the prefix-grep consumer (`adapters/openclaw/sentinel-cron.sh:65-69`), and Family Updater is the non-zero/rollback plus first-line-headline consumer (`scripts/family-updater:379-403`).
- `tr-enqueue` is the published plugin write API (`docs/plugin-convention.md:11-20`).
- Regression coverage is distributed across `check-tickprobe` for streams and optional `FAIL` (`tests/check-tickprobe.test.sh:246-256`; `tests/check-tickprobe.test.sh:339-349`), `pause-contract` for stream routing and paused exit 3 (`tests/pause-contract.test.sh:207-221`), `tr-enqueue` for lowercase `warning:` (`tests/tr-enqueue.test.sh:348-357`), `family-updater` for rollback/headline propagation (`tests/family-updater.test.sh:270-278`), `skill-lint` for advisory success (`tests/skill-lint.test.sh:129-138`), `wrapper-conformance` for exact learning rows (`tests/wrapper-conformance.test.sh:778-784`), and `sentinel-cron` for `missing path:` consumption (`tests/sentinel-cron.test.sh:40-44`).
