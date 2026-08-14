# EV-005 acceptance-driven revision report REV3

## Current status

The definitive repository-code execution set is 24 tasks:
`t01,t07,t09,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30`.
The other six tasks (`t02,t03,t04,t05,t06,t08`) have no repository-code
execution and are therefore not subject to r3-3 isolation.

Fresh completed REV3 logs prove **PASS** for every edited donecheck except
t12: t01, t07, t09, t10, t11, t13, t14, t17, t18, t19, t20, t21, t22, t23,
t24, t25, t26, t27, t28, t29, and t30. The t12 log honestly proves **FAIL**.
The already isolated, untouched t15 and t16 retain their completed REV2 PASS
logs. The final sealing result is **HOLD** because t12 failed revalidation and
the P11 external-review quorum remains HOLD.

## r3-3/r4-1 isolation scan

“Isolated before” means the `donecheck.sh` at HEAD `d958aef`; only t15 and t16
already supplied fresh `HOME` and `TMPDIR`. “Isolated now” means every
repository-code invocation is wrapped in an invocation/suite-specific temporary
`HOME` and `TMPDIR` with cleanup. Exact probe names below describe the current
gate; N/A means the task executes no repository code.

| Task | Exec probe? | Exact probe / N/A | Isolated before (HEAD) | Isolated now | Revalidation verdict and evidence |
| --- | --- | --- | --- | --- | --- |
| t01 | Yes | `make test` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a25`, no `DIRTY-TREE`, [t01.log](../tools/validate-logs/t01.log). |
| t02 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t03 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t04 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t05 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t06 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t07 | Yes | `make test`; `make lint` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a39`, no `DIRTY-TREE`, [t07.log](../tools/validate-logs/t07.log). |
| t08 | No | N/A | N/A | N/A | N/A — footer-only edit; no revalidation needed. |
| t09 | Yes | `.ev005-fixtures/permission_probe.py default\|pinned-uid\|pinned-gid`; `.ev005-fixtures/test_coverage_probe.py` | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t09.log](../tools/validate-logs/t09.log). |
| t10 | Yes | `.ev005-fixtures/family_table_probe.py placement\|content\|map-row\|stale\|member-footer`; `python3 tools/render.py --check`; `python3 -B tools/check_registry.py --offline`; `python3 tools/family_footer.py lint`; `python3 tools/selftest_family_footer.py` | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t10.log](../tools/validate-logs/t10.log). |
| t11 | Yes | discovered secrets-env parity test(s); `bash tests/check-tickprobe.test.sh`; direct isolated `install.sh --check`/wrapper probes | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a11`, no `DIRTY-TREE`, [t11.log](../tools/validate-logs/t11.log). |
| t12 | Yes | Python AST probes; `python3 -S scripts/tests/run_tests.py` | No | Yes | **FAIL** — pre FAIL×5 / fix FAIL×5, [t12.log](../tools/validate-logs/t12.log). |
| t13 | Yes | four inline-Python SHA-256 probes over the generated README footer blocks | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t13.log](../tools/validate-logs/t13.log). |
| t14 | Yes | inline-Python registry-field probes; `python3 -B tools/check_registry.py --offline`; `python3 -B tools/selftest_family_footer.py` | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t14.log](../tools/validate-logs/t14.log). |
| t15 | Yes | `python3 scripts/injection-budget-check`, `python3 scripts/injection-lint`, and `python3 scripts/watchdog` with the derived fixture path/flag | Yes | Yes (unchanged) | Not rerun: gate already isolated and untouched; existing **PASS**, [t15.log](../tools/validate-logs/t15.log). |
| t16 | Yes | `.ev005-fixtures/probe_recall_env.py accept\|reject\|test-accept\|test-reject`; `python3 scripts/tests/test_recall.py` | Yes | Yes (unchanged) | Not rerun: gate already isolated and untouched; existing **PASS**, [t16.log](../tools/validate-logs/t16.log). |
| t17 | Yes | `.ev005-fixtures/t17_probe.sh push-record\|push-visible\|timeout\|metrics`; inline-Python template/test structure probes | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a07`, no `DIRTY-TREE`, [t17.log](../tools/validate-logs/t17.log). |
| t18 | Yes | inline-Python registry/document structure probes; `python3 -B tools/render.py --check`; `python3 -B tools/check_registry.py --offline` | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t18.log](../tools/validate-logs/t18.log). |
| t19 | Yes | `.ev005-fixtures/t19_probe.sh assignment\|inert\|symlink`; inline-Python regression-coverage probe | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a05`, no `DIRTY-TREE`, [t19.log](../tools/validate-logs/t19.log). |
| t20 | Yes | inline-Python evidence probes `schema\|silent\|gate\|weekly\|growth`, freshness-workflow probe, and fail-closed-contract probe | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t20.log](../tools/validate-logs/t20.log). |
| t21 | Yes | `scripts/loop-init`; `install.sh --check`; discovered targeted conditional-field regression test | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a06`, no `DIRTY-TREE`, [t21.log](../tools/validate-logs/t21.log). |
| t22 | Yes | full `tests/test_lg.sh`, `tests/test_scratch_persist.sh`, `tests/test_brief_validator.sh`, and `tests/test_safety_hooks.sh`; targeted 19/20-case `tests/test_recall.sh`; isolated Python/grep structure probes | No | Yes | **PASS** — pre nonzero×5 / fix zero×5, assertions `a01`–`a11`, [t22.log](../tools/validate-logs/t22.log). |
| t23 | Yes | `.ev005-fixtures/input-validation-probe.sh corrupt-state\|quoted-id\|copy-failure\|created-intake\|created-scheduling\|env-integers` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a07`, no `DIRTY-TREE`, [t23.log](../tools/validate-logs/t23.log). |
| t24 | Yes | `.ev005-fixtures/publication_gate_probe.py` README/retired/preparing/rejection/suffix/workflow/clean modes; `python3 -B tools/render.py --check`; `python3 -B tools/check_publication_gate.py` | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t24.log](../tools/validate-logs/t24.log). |
| t25 | Yes | inline-Python updater-order probe; `bash tests/family-updater.test.sh` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a06`, no `DIRTY-TREE`, [t25.log](../tools/validate-logs/t25.log). |
| t26 | Yes | inline-Python conventions-note inventory probe; `bash tests/cli-conventions.test.sh` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a06`, no `DIRTY-TREE`, [t26.log](../tools/validate-logs/t26.log). |
| t27 | Yes | inline-Python authority-order and registry-published-row probes | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t27.log](../tools/validate-logs/t27.log). |
| t28 | Yes | isolated `install.sh`/`scripts/tr-enqueue` probe; discovered quoted-hash test; focused `donecheck-extract`, `tr-enqueue`, `task-runner`, and `spawn-step` suites | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a10`, no `DIRTY-TREE`, [t28.log](../tools/validate-logs/t28.log). |
| t29 | Yes | `.ev005-fixtures/growth_model_probe.py canonical\|subjects\|readiness\|readme-stages\|claim-strength\|svg-labels\|svg-styles\|svg-boundary\|adjacency\|stage-one-evidence\|parity`; renderer/publication checks | No | Yes | **PASS** — pre FAIL×5 / fix PASS×5, [t29.log](../tools/validate-logs/t29.log). |
| t30 | Yes | `make test`; `make lint`; `.ev005-fixtures/workflow_probe.py common\|test-lint\|gitleaks\|pr-size\|history\|review` | No | Yes | **PASS** — pre exit 1×5 / fix exit 0×5, assertions `a01`–`a08`, no `DIRTY-TREE`, [t30.log](../tools/validate-logs/t30.log). |

Each completed fresh log postdates its corresponding donecheck edit, contains
five numbered pre runs and five numbered fix runs, and contains no
`DIRTY-TREE` record. The PASS logs have five pre exits of 1 and five fix exits
of 0; t12 has five pre exits of 1 and five fix exits of 1.

## r3-5/r4-1 footer backfill

The original missing-footer set was exactly
`t01,t02,t03,t04,t05,t06,t07,t08,t09,t10,t13,t14,t24,t25,t26`. All fifteen
now record the anonymization mapping, longest needle and derivability basis,
and timeout rationale.

| Task | Footer disposition | Revalidation disposition |
| --- | --- | --- |
| t01 | Backfilled | Covered by isolation rerun: **PASS**, [t01.log](../tools/validate-logs/t01.log). |
| t02 | Backfilled | No executable probe; no revalidation needed. |
| t03 | Backfilled | No executable probe; no revalidation needed. |
| t04 | Backfilled | No executable probe; no revalidation needed. |
| t05 | Backfilled | No executable probe; no revalidation needed. |
| t06 | Backfilled | No executable probe; no revalidation needed. |
| t07 | Backfilled | Covered by isolation rerun: **PASS**, [t07.log](../tools/validate-logs/t07.log). |
| t08 | Backfilled | No executable probe; no revalidation needed. |
| t09 | Backfilled | Covered by isolation rerun: **PASS**, [t09.log](../tools/validate-logs/t09.log). |
| t10 | Backfilled | Covered by isolation rerun: **PASS**, [t10.log](../tools/validate-logs/t10.log). |
| t13 | Backfilled | Covered by isolation rerun: **PASS**, [t13.log](../tools/validate-logs/t13.log). |
| t14 | Backfilled | Covered by isolation rerun: **PASS**, [t14.log](../tools/validate-logs/t14.log). |
| t24 | Backfilled | Covered by isolation rerun: **PASS**, [t24.log](../tools/validate-logs/t24.log). |
| t25 | Backfilled | Covered by isolation rerun: **PASS**, [t25.log](../tools/validate-logs/t25.log). |
| t26 | Backfilled | Covered by isolation rerun: **PASS**, [t26.log](../tools/validate-logs/t26.log). |

Thus footer-only t02, t03, t04, t05, t06, and t08 require no revalidation.
For executable tasks, the listed rerun is required by the donecheck isolation
edit, not by the footer edit.

## t22 strengthening (P1/P4/P10)

The original aggregate tool unit is split into five independently falsifiable
tool units. The current 11-unit map is:

| Unit | Class | Surviving mapping |
| --- | --- | --- |
| U1 | MECH | `lg` → `a01` (executable, `bash -n`, full bundled suite). |
| U2 | MECH | Scratch persistence → `a02` (executable, AST shape, full bundled suite). |
| U3 | MECH | Delegation-brief validation → `a03` (executable, AST shape, full bundled suite). |
| U4 | MECH | Safety-hook set → `a04` (executables, Python/JavaScript structure, full bundled suite). |
| U5 | MECH | `recall` plus shared-memory relationship → `a05` functional suite and `a06` documentation anchors. |
| U6 | MECH (weakened) | Personal-environment removal/configurability → `a07` tracked-text absence sweep; semantic completeness is the recorded loss. |
| U7 | MECH | Clean setup/wiring → `a08` README/settings structure. |
| U8 | MECH (weakened) | README process/standard → `a09` four-language structure; human process and editorial quality are the recorded loss. |
| U9 | MECH (weakened) | Eleven-item publication gate → `a07`, `a09`, `a10`, `a11`; unenumerated/live/aesthetic remainder is the recorded loss. |
| U10 | HUMAN | Owner visibility flip → dropped as external human/account action. |
| U11 | MOOT | Private-until-flip state → dropped because live hosting state is absent from the replica. |

Counts are 11 total: 9 MECH (including three weakened-MECH), 1 HUMAN, and 1
MOOT. This corrects the former HUMAN inflation for personal-environment and
publication-gate units.

For r4-2, `a05` uses the bundled `tests/test_recall.sh` rather than accepting
an empty `bin/recall`. It runs a deterministic 19/20 targeted subset. The sole
excluded invocation is `case_colon_path_survives_rg_and_grep_fallback`, whose
implementation unconditionally evaluates `rg_path=$(command -v rg)` under
`set -e` although host `rg` is outside the sealed standard toolchain. The
included `case_rg_preferred_and_grep_fallback` supplies its own shims and still
exercises both command-selection branches. No failure among the other 19 cases
is filtered. This rationale is recorded in `t22/units.md`; the final
[t22.log](../tools/validate-logs/t22.log) records pre nonzero×5, fix zero×5,
`a01`–`a11`, no `DIRTY-TREE`, and `VERDICT t22 PASS`.

For r4-3, the declared constant-true assertions on both span legs are exactly
`a01`, `a02`, `a03`, `a04`, `a07`, and `a11` (6/11). The assertions expected
to discriminate pre from fix are `a05`, `a06`, `a08`, `a09`, and `a10`.

## P5/P6/P7 ledger records

P5, exact t21 line:

```text
Warning-row-over-`FAIL`-row ruling: the warning form wins over the available `FAIL`-row form because the fix's actual amended contract pins warnings plus unchanged `install.sh --check` exit semantics; the acceptance seat's dissent is acknowledged.
```

P6, exact t26 line:

```text
Seven-defect source split: normalized by this fix — none; frozen/documented without producer behavior changes — offending-path omission, reasonless `install.sh` argument usage, `task-runner` usage omitting mandatory `TR_SPAWN_STEP`, `tr-enqueue` usage exit `1`, three warning-prefix styles, `--check` failure rows on stdout while warnings use stderr, and optional `FAIL` rows with exit `0`; the actual pre/fix diff adds only the conventions note and its pinning test.
```

P7, exact corrected t12 heading:

```text
## Anonymization and needles
```

## Completed revalidation failures

Exactly one completed fresh rerun fails: **t12**. Its authoritative
[log](../tools/validate-logs/t12.log) records pre FAIL×5 and fix FAIL×5. On
each fix run, `a12` fails while `a13` confirms `skipped=0`. The detailed
reproduction recorded in `t12/units.md` identifies
`test_recall.RecallTests.test_search_adapters_guard_leading_dash_query`: after
the test clears the process environment, one expansion observes the account
passwd-home while the post-context expectation expands against the fresh
`HOME`. A canonical `pwd -P` isolated root reproduced the same single-test
failure, excluding noncanonical or double-slash temporary paths. This is an
admission finding; the gate was not weakened to absorb it.

All edited donechecks now have completed post-edit logs. The donecheck result is
21 PASS and 1 FAIL among the 22 edited gates; t15 and t16 are unchanged existing
PASS tasks. The bundle remains **HOLD** rather than sealed because t12 fails on
the fix leg and P11 remains HOLD.

## External review quorum (P11)

- Kimi was requested as `kimi-code/k3`, but its OAuth endpoint failed with
  `ENOTFOUND`; no model response was returned, so no actual model/version could
  be confirmed.
- GLM was requested as `glm-5.2`, but its API failed with `ENOTFOUND`; no model
  response was returned, so no actual model/version could be confirmed.
- Neither request supplies an independent review vote. The required external
  review quorum remains unavailable and **P11 remains HOLD**.

## Scope and Git checks

- REV3 began at baseline HEAD `d958aef`. During the run, HEAD advanced to
  `89e370e` through a concurrent owner commit touching only `analysis-plan.md`,
  `arm-instructions.md`, `eligibility-ledger.md`, and `translation-rules.md`;
  it does not overlap the REV3 task/report edits.
- The index is empty (`git diff --cached --name-only` has zero entries); no
  REV3 `git add`, commit, or push was performed.
- `git status --porcelain` is confined to the authorized
  `experiments/ev-005/tasks/t*/` files, `experiments/ev-005/tools/validate-logs/`,
  and this report. No file outside the REV3 allowlist is modified.
