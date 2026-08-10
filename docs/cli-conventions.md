# CLI output and exit conventions

This note records the current CLI contract. Slice #21a documents it without changing behavior; normalization decisions belong to #21b.

## Output prefixes and streams

- The warning house style is the literal lowercase prefix `warning: ` (colon and trailing space) on stderr (`install.sh:967`; `tests/check-tickprobe.test.sh:339`; `tests/check-tickprobe.test.sh:342-346`). OpenClaw Sentinel merges `--check` output before grepping `^(warning:|missing )`, so the leading `warning:` and `missing ` tokens are **FROZEN** consumer inputs (`adapters/openclaw/sentinel-cron.sh:65`; `adapters/openclaw/sentinel-cron.sh:69`).
- Current outliers are `scripts/tr-enqueue`'s `WARN:` (`scripts/tr-enqueue:9-10`), pinned by its suite (`tests/tr-enqueue.test.sh:216-219`); `WARNING:` in the bounded helper, distill audit, and Hermes spawn path (`scripts/lib-bounded.sh:43-49`; `adapters/openclaw/distill-audit.sh:104-107`; `adapters/hermes/spawn_step.sh:132-135`); and the `deadman-probe:` and `cron-wrapper warning:` prefixes (`scripts/deadman-probe.sh:64-66`; `templates/cron-wrapper.tmpl.sh:148-152`). They remain documented outliers in #21a; migration is deferred to #21b.

The machine row formats below are **FROZEN**:

| Row | Producer and consumer evidence |
| --- | --- |
| `missing path: ` | Emitted for absent required paths (`install.sh:878-880`) and consumed through Sentinel's `missing ` grep (`adapters/openclaw/sentinel-cron.sh:69`); its notice is pinned exactly (`tests/sentinel-cron.test.sh:40-44`). |
| `missing header: ` | Emitted for each absent required header (`install.sh:948-955`) and consumed through the same `missing ` grep (`adapters/openclaw/sentinel-cron.sh:69`). |
| `ok:` | The exact healthy terminator is emitted by the checker (`install.sh:1121`) and published as expected operator output (`docs/agent-guide.md:76`). |
| `learning path: adapter=X \| route=Y \| PASS\|FAIL` | The formatter fixes the separators and terminal status (`install.sh:703-719`); exact rows are asserted by the check and conformance suites (`tests/check-tickprobe.test.sh:252-256`; `tests/wrapper-conformance.test.sh:778-784`). |

Stdout carries machine rows beginning `state=`, `bootstrap_state=`, `check:`, `missing path:`, `missing header:`, `ok:`, and `learning path:` (`install.sh:703-708`; `install.sh:874-879`; `install.sh:948-951`; `install.sh:1121`). Human `warning:` advisories go to stderr (`install.sh:966-967`). The named regression contract is `check keeps machine tokens on stdout and human warnings on stderr` (`tests/check-tickprobe.test.sh:339-349`); the pause suite independently checks the same split (`tests/pause-contract.test.sh:207-215`).

`scripts/family-updater` captures merged `--check` output (`scripts/family-updater:229-239`), treats any non-zero result as update failure and rolls back (`scripts/family-updater:379-398`), and selects the first output line for the failure reason/headline (`scripts/family-updater:243-253`; `scripts/family-updater:388-403`). Therefore the first emitted `--check` line is an observable surface; the producer currently emits `state=` first (`install.sh:874-876`), and the updater suite pins rollback plus the first-line reason (`tests/family-updater.test.sh:270-278`).

## Exit codes

| Code | Current meaning |
| --- | --- |
| `0` | Success for `--check`, including optional diagnostic `FAIL` rows (`docs/reference.md:40-42`). Task Runner also exits 0 without work when its workspace is paused (`scripts/task-runner.sh:38-41`). |
| `1` | `--check` contract failure for required layout, `STATE.md` headers, or pause-control path safety (`docs/reference.md:30`; `docs/reference.md:41`). `tr-enqueue` uses 1 for usage and validation rejects through its common failure path (`scripts/tr-enqueue:4-6`; `scripts/tr-enqueue:13-15`; `scripts/tr-enqueue:107-134`); usage=1 is a known deviation from sibling usage=2 and is pinned for #21b owner review (`tests/cli-conventions.test.sh:73-74`). Deadman Probe returns 1 when a new violation is found (`scripts/deadman-probe.sh:205-215`; `tests/deadman-probe.test.sh:97-104`). |
| `2` | Usage/configuration error in Task Runner (`scripts/task-runner.sh:8-10`), Metrics (`scripts/tr-metrics.sh:8-10`), Deadman Probe (`scripts/deadman-probe.sh:4-6`), Family Updater (`scripts/family-updater:34-44`), Loop Init (`scripts/loop-init:10-26`), Attest Wrapper (`scripts/attest-wrapper:38-71`), and `install.sh`'s `die_usage` path (`install.sh:71-73`). The currently unpinned cases are covered together in `tests/cli-conventions.test.sh:68-71`. |
| `3` | `tr-enqueue` reports a paused workspace (`scripts/tr-enqueue:101-104`), pinned by the pause suite and activation manifest (`tests/pause-contract.test.sh:217-221`; `scripts/activation-manifest.tsv:14`). Sentinel uses 3 for infrastructure errors (`adapters/openclaw/sentinel-cron.sh:52-54`; `adapters/openclaw/sentinel-cron.sh:71-74`). |
| `129`, `130`, `143` | Explicit HUP, INT, and TERM mappings where traps are installed, including Attest Wrapper, Deadman Probe, Hermes Verify Job, OpenClaw Distill Audit, and Flush Intake (`scripts/attest-wrapper:97-99`; `scripts/deadman-probe.sh:106-108`; `adapters/hermes/verify-job.sh:131-133`; `adapters/openclaw/distill-audit.sh:421-423`; `adapters/claude-code/flush-intake.sh:243-245`). |

Exit `1` is intentionally **OVERLOADED**: it can mean a rejected enqueue/check contract or a detected operational violation (`scripts/tr-enqueue:4-6`; `install.sh:1117-1118`; `scripts/deadman-probe.sh:212-215`). That overload is contractual, not accidental.

## `--check` FAIL rows

Optional learning-path rows may print `FAIL` while `--check` exits 0; the reference states this explicitly (`docs/reference.md:41-43`), and the implementation says diagnostic `FAIL` does not change check semantics (`install.sh:810-816`). This behavior is **FROZEN** by consumers that assert exit 0 alongside `FAIL` or warning rows (`tests/check-tickprobe.test.sh:246-256`; `tests/skill-lint.test.sh:96-105`). Findings `d2a0fcca` and `f6442c21` are therefore resolved in #21a as “document, do not change.”

## Consumer and regression inventory

- OpenClaw Sentinel is the prefix-grep consumer (`adapters/openclaw/sentinel-cron.sh:65-69`), and Family Updater is the non-zero/rollback plus first-line-headline consumer (`scripts/family-updater:379-403`).
- `tr-enqueue` is the published plugin write API (`docs/plugin-convention.md:11-20`).
- Regression coverage is distributed across `check-tickprobe` for streams and optional `FAIL` (`tests/check-tickprobe.test.sh:246-256`; `tests/check-tickprobe.test.sh:339-349`), `pause-contract` for stream routing and paused exit 3 (`tests/pause-contract.test.sh:207-221`), `tr-enqueue` for `WARN:` (`tests/tr-enqueue.test.sh:216-219`), `family-updater` for rollback/headline propagation (`tests/family-updater.test.sh:270-278`), `skill-lint` for advisory success (`tests/skill-lint.test.sh:96-105`), `wrapper-conformance` for exact learning rows (`tests/wrapper-conformance.test.sh:778-784`), and `sentinel-cron` for `missing path:` consumption (`tests/sentinel-cron.test.sh:40-44`).
