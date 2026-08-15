# p02 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | A Claude-Code flush consumer exists and folds a real pending flush corpus into `Lessons learned` with duplicate suppression and the shared lock-backed fold path. | `a01` (T5 behavior probe: initialize an isolated workspace, run the intake on a real `flush-*.md` file with one `outcome=ok` bullet and one `outcome=no_reply` block, then re-stage an archived duplicate after deleting the folded STATE line and require `deduped=1` with no refold). `a04` adds the structural half of the unit by requiring the intake to source `scripts/lib-state-fold.sh`, call `take_state_lock`, and rewrite `STATE.md` through `append_state_sections`. |
| U2 | MECH | Consumed flush files leave `loop/pending/` and are archived. | `a02` (T5 behavior probe on the same intake path: after a successful run, require the old `flush-*.md` file to be absent from `loop/pending/` and present under `loop/archive/`). |
| U3 | MECH | Successful intake touches the distill deadman marker and the install guide documents the consumer/probe wiring. | `a02` covers the runtime marker touch (`loop/.deadman/distill.marker` plus `marker=touched` in the receipt). `a03` (T1 content-presence) requires the install guide to name the flush-intake consumer, `distill.marker`, and `intake-runs.log` under the dedicated flush-consumer section. |
| U4 | MECH | The intake and openclaw distillation adapters share one fold implementation instead of duplicating adapter-local helpers. | `a04` (T6 structural: require `scripts/lib-state-fold.sh` to define the shared fold helpers, require `adapters/openclaw/distill-audit.sh` to source that helper and call its exported functions, and require the old helper definitions to be absent from the adapter script itself). |

## Anonymization and needle record

- Mapping: the source repository remains “this repository”; issue, PR, branch,
  date, and operator provenance are omitted. The adapter paths, `STATE.md`,
  `loop/pending/`, `loop/archive/`, and `distill.marker` remain because the source criterion names those concrete
  targets.
- Longest T1/T4 needle: `## Flush intake consumer` (23 characters), a section
  heading introduced by the source criterion's documentation unit, not a
  sentence of fix prose. The structural checks otherwise pin only file paths,
  helper names, and marker names already derivable from the replica tree.
- Timeout remains the default 120 seconds. The behavioral probe exercises only
  narrow isolated workspaces created by `scripts/loop-init`; no full repository
  suite is used because the source criterion is about the consumer path itself,
  not repository-wide health.

## Negative validity probe (r5-1)

- Minimal non-solution edit: on the pre-fix tree, add a stub
  `adapters/claude-code/flush-intake.sh` that only moves `flush-*.md` files to
  `loop/archive/` and touches `loop/.deadman/distill.marker`, while leaving the
  install guide unchanged and never sourcing `scripts/lib-state-fold.sh` or
  folding any lesson into `STATE.md`.
- Route: `a`
- Expected result: `a01`, `a03`, and `a04` should still FAIL even if `a02`
  can be spoofed by the archive/marker shell stub.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; `a01`-`a04` all failed,
  `RUN p02 negprobe exit=1 dur=1s`, no `DIRTY-TREE`; log:
  `experiments/ev-005/tools/validate-logs/negprobe/p02.log`.
- Rationale: a marker-touch/archive stub can mimic the surface motion of one
  unit, but it cannot fabricate the governed lessons fold, the documented
  wiring section, or the shared helper contract.

## Setup accounting (REV6 r5-3)

- Shared-fixture setup is accounted per assertion: if `.ev005-fixtures/p02_probe.sh`
  is missing or non-executable, dependent checks `a01` and `a02` each emit
  their own explicit FAIL, while independent structural/doc checks `a03` and
  `a04` still run. Each CHECK ID is emitted exactly once.
- An author-local setup probe removed the bundled fixture before one
  run and observed exactly four CHECK lines: `a01` and `a02` FAILed for missing
  probe setup, `a03` and `a04` remained independently discriminative, and the
  script exited 1 with a clean tree.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/p02.log` shows no
  constant-true assertions; all four assertions FAIL on every pre run and PASS
  on every fix run.
