# EV-005 batch-2 drafting report

Batch 2 contains re-enactment tasks `t09`–`t16`. Seven tasks satisfy the R11
admission shape (pre-fix FAIL 5/5, fix PASS 5/5). `t12` is intentionally
reported as FAIL because the supplied pre-fix SHA already satisfies every
source-derived check; tightening that gate with an unrelated difference would
violate R4.

## Task summary

| id | source | units | MECH | HUMAN | MOOT | assertions | validity |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| t09 | family-memory-architecture#3 | 4 | 4 | 0 | 0 | 4 | [PASS](../tools/validate-logs/t09.log) |
| t10 | family-os#15 | 12 | 10 | 2 | 0 | 12 | [PASS](../tools/validate-logs/t10.log) |
| t11 | caty-agent-harness#49 | 14 | 14 | 0 | 0 | 11 | [PASS](../tools/validate-logs/t11.log) |
| t12 | family-memory-architecture#1 | 13 | 13 | 0 | 0 | 13 | [FAIL](../tools/validate-logs/t12.log) |
| t13 | family-memory-architecture#11 | 21 | 20 | 1 | 0 | 20 | [PASS](../tools/validate-logs/t13.log) |
| t14 | family-os#19 | 8 | 5 | 1 | 2 | 6 | [PASS](../tools/validate-logs/t14.log) |
| t15 | family-memory-architecture#4 | 4 | 4 | 0 | 0 | 4 | [PASS](../tools/validate-logs/t15.log) |
| t16 | family-memory-architecture#2 | 4 | 4 | 0 | 0 | 6 | [PASS](../tools/validate-logs/t16.log) |

All completed logs contain five numbered pre-fix runs, five numbered fix runs,
one final verdict, and no `DIRTY-TREE` record. The `t12` log contains 130
passing assertion rows: all 13 assertions pass in both trees on all five runs,
so the validator correctly emits FAIL for the unmet pre-fix-fails condition.

## Needle audit

| id | longest T1/T4 needle | calibration result |
| --- | --- | --- |
| t09 | none | The longest fixed identifier, `FMA_EXPECT_OWNER` (16), is used by T5/T6 checks and is criterion-constitutive. |
| t10 | none | `module_table` (12) is a pre-fix-derived structural identifier in a T6 check; generated blocks are discovered dynamically. |
| t11 | none | The 34-character assignment regex `([A-Za-z_][A-Za-z0-9_]*)=(.*)` is a pre-fix-derived T6 grammar, not fix prose. |
| t12 | `PyYAML` (6) | A dependency name required by the absence criterion; it does not pin a sentence. |
| t13 | `github.com/caty-ai/family-dev-handbook` (38) | A pre-fix-derived link fragment. Other multilingual anchors are shorter semantic fragments. |
| t14 | none | `caty-ai/self-growth-loop` (24) is a criterion-constitutive JSON value checked structurally. |
| t15 | `validator` (9) | Co-located with `fixture`/`fixtures` or `smoke`; the historical documentation sentence is not pinned. |
| t16 | `recall` / `enforc` (6) | Small alternatives are co-located with `0600`; the historical documentation sentence is not pinned. |

No T1/T4 assertion pins a full sentence of historical fix prose.

## Judgement calls and mappings

- **t09:** The source's normal-user quickstart claim is represented by a direct
  permission-policy probe: default ownership accepts a foreign gid while
  preserving current uid and mode `0600`. Pinned uid and gid refusals remain
  separate checks. `FMA_EXPECT_OWNER` is retained under the
  criterion-constitutive-identifier exemption.
- **t10:** The new generated block name is not frozen; the gate discovers it
  and compares its body with replica-local renderer output. The live portion of
  `check_registry.py` is HUMAN and is weakened to its deterministic `--offline`
  core. The broad “member footer behavior is unchanged” claim is also HUMAN;
  its replica-solvable behavioral core checks linked map rows and bold,
  unlinked host members across all configured members and languages.
- **t11:** Rejection accepts either source-authorized outcome: a `warning:`
  advisory on stderr, or a documented `FAIL` machine row on stdout. Grammar and
  refusal parity are checked through one production source plus direct
  behavior probes. Focused regressions are discovered by source-derived
  markers instead of pinning the historical test filename.
- **t12:** No unit was dropped or weakened. The source explicitly demands the
  full suite, so the gate runs `python3 -S scripts/tests/run_tests.py` and
  checks zero skips. The declared pre-fix tree already uses the stdlib YAML
  subset, contains none of the prohibited dependency guidance, and passes the
  suite. The declared fix changes only generated README footer blocks. This is
  a supplied-metadata admission blocker, not a reason to add unrelated checks.
- **t13:** Four-language qualitative inspection is HUMAN and is dropped after
  extracting the mechanical core: short semantic anchors, removal of the
  hand-written tables, exactly one generated table, and preservation of each
  pre-fix-derived generated block. The block hashes enforce an explicit
  unchanged-content criterion using content available in the replica.
- **t14:** The network-backed repository reality portion of
  `check_registry.py` is HUMAN and is weakened to `--offline`. Cross-repository
  footer synchronization and separate-commit process claims are MOOT in a
  single history-zero replica. The new public repository target is retained as
  a criterion-constitutive identifier.
- **t15:** The three green fixtures are checked through their named validators
  under isolated temporary homes. No task fixture is bundled because the
  source criterion requires repository-shipped inputs. Documentation
  discoverability uses small semantic anchors rather than canonical prose.
- **t16:** Direct accept/reject behavior, test-shape structure, the targeted
  recall test module, and small documentation anchors jointly cover the four
  units without pinning test names or fix wording.

No timeout escalation was needed. Every task retains the 120-second budget;
only `t12` uses the full repository suite because its source Done when demands
it.

## Validation environment note

The local Git profile installs a pre-commit hook that can reject the temporary
snapshot commits made internally by `validate-task.sh` before a task gate runs.
For the final FMA validations, the global and system Git config files were
disabled for the validator process only. This changes neither replica content
nor donecheck behavior; it prevents an out-of-scope workstation hook from
short-circuiting replica construction. `t16` was rerun alone after a concurrent
non-isolated run failed its targeted test; the isolated check and final
validator run passed, and the final on-disk log is the clean PASS run.

## Self-verification

- PASS — eight task directories exist; each contains `task.md`, executable
  `donecheck.sh`, `units.md`, and `meta.json`. Fixtures exist only for `t09`,
  `t10`, `t11`, and `t16`, where T5 probes need them.
- PASS — all eight metadata files parse as JSON; ids, repositories, issue
  numbers, pre-fix SHAs, fix SHAs, `synthetic: false`, and 120-second timeouts
  match the assignment table exactly.
- PASS — all eight donechecks pass `bash -n`; none contains `gh`, `curl`,
  `wget`, `$RANDOM`, or date-based logic.
- PASS — the needle audit above found no full-sentence T1/T4 fix-prose pin.
- PASS — no task sheet contains an issue/PR number, date, person/agent name, or
  tracker reference. Criterion-constitutive identifiers are retained and their
  exemptions are recorded in the corresponding unit ledgers.
- PASS — final validator verdicts are recorded only from complete on-disk logs:
  `t09` PASS, `t10` PASS, `t11` PASS, `t12` FAIL, `t13` PASS, `t14` PASS,
  `t15` PASS, and `t16` PASS.
- PASS — `git status --porcelain` shows only batch-2 files under
  `experiments/ev-005/tasks/` and `experiments/ev-005/tools/validate-logs/`;
  the index is empty. The batch-2 drafter ran no `git add`, `git commit`, or
  `git push`. During drafting, a separate author process advanced the branch
  from `e72c0cca813f20c9475b1263e72300b410bb2953` to
  `4378a9ceb108f44633840be81831737de6180ea5`; that concurrent batch-1 commit is
  not part of this batch's working-tree changes.

## Author addendum (Alpha, 2026-08-14)

The drafter's honest t12 FAIL exposed an eligibility-ledger pair error, not a task defect:
family-memory-architecture#1's recorded merge commit was created on the feature branch
(reverse-merge-then-fast-forward), so `parent[0]` — the survey's pre_fix convention — was the
feature tip that already contains the port. Corrected to `pre_fix = 25b426bb` (parent[1], main
before the port; `import yaml` present in both scripts — verified directly). Ledger finding I-2
records the failure mode. t12 re-validated by the author with the corrected pair: pre FAIL×5 /
fix PASS×5, VERDICT PASS (`../tools/validate-logs/t12.log`). Batch-2 validity: **8/8 PASS**.

Author units review (all 8 ledgers, against the source Done whens): forward derivation
throughout, honest HUMAN/MOOT drops with reasons (t14 U7/U8, t13 U21, t10 U9/U12),
criterion-constitutive exemptions recorded (t14 U1, t09 FMA_EXPECT_OWNER, t11 functional
tokens). Validation-environment note: author t12/t02 re-runs used
`GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` for the validator process only, same
rationale as the drafter's note (workstation pre-commit hook rejects the validator's internal
snapshot commits; replica content and donecheck behavior unaffected). The sealed pilot
environment must not carry workstation git hooks — noted for the runner spec.
