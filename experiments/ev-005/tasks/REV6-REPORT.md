# EV-005 REV6 report — six REV5 STOP blockers

## Outcome

REV6 closes all six task-level blockers recorded by REV5. Each edited gate now discriminates its pre/fix history-zero replicas in five consecutive runs, each negative probe has fresh post-edit evidence, and the three setup-sensitive gates account for every assertion when their bundled fixture/probe is absent.

Implementation writer metadata: requested `gpt-5.6-sol` / `high`; actual `gpt-5.6-sol` / `high`. External implementation review is not claimed in this report.

## Blocker dispositions

| Task | REV5 blocker and REV6 change | Fresh 5+5 validation | Negative probe, REV5 → REV6 |
| --- | --- | --- | --- |
| t01 | Raw-file grep accepted HTML-comment needle injection. All documentation needles now use non-greedy multiline HTML-comment stripping before matching; needles, IDs, and `make test` remain unchanged. | `VERDICT PASS`; pre `1/684s, 1/682s, 1/695s, 1/689s, 1/684s`; fix `0/678s, 0/689s, 0/694s, 0/716s, 0/691s`; [log](../tools/validate-logs/t01.log). | REV5 `UNEXPECTED_PASS`, exit 0/668s → REV6 `EXPECTED_FAIL_CONFIRMED`, exit 1/687s, `a01`–`a14`, `a16`, `a17`; [log](../tools/validate-logs/negprobe/t01.log). |
| t02 | Fixed/co-presence checks read raw Markdown and accepted comment stuffing. Both surfaces now read comment-stripped visible content; needles and IDs remain unchanged. | `VERDICT PASS`; pre `1/1s` ×5; fix `0/1s, 0/0s, 0/1s, 0/1s, 0/1s`; [log](../tools/validate-logs/t02.log). | REV5 `UNEXPECTED_PASS`, exit 0/0s → REV6 `EXPECTED_FAIL_CONFIRMED`, exit 1/0s, `a01`–`a25`; [log](../tools/validate-logs/negprobe/t02.log). |
| t04 | Fixed, regex, co-presence, line-hash, and count surfaces could consume HTML comments. All now consume comment-stripped visible content without changing patterns, hashes, counts, or IDs. | `VERDICT PASS`; pre `1/0s` ×5; fix `0/0s, 0/1s, 0/0s, 0/1s, 0/0s`; [log](../tools/validate-logs/t04.log). | REV5 `UNEXPECTED_PASS`, exit 0/0s → REV6 `EXPECTED_FAIL_CONFIRMED`, exit 1/0s, `a01`–`a03`; [log](../tools/validate-logs/negprobe/t04.log). |
| t11 | A missing bundled fixture exited at a01 and suppressed later CHECK rows. Fixture-dependent assertions now prepare/check their own file and explicitly fail in place; unrelated assertions continue. | `VERDICT PASS`; pre `1/10s, 1/10s, 1/10s, 1/10s, 1/9s`; fix `0/16s, 0/15s, 0/15s, 0/15s, 0/15s`; [log](../tools/validate-logs/t11.log). | REV5 and REV6 both `EXPECTED_FAIL_CONFIRMED` for `a04`–`a07`; exit 1/10s → exit 1/11s; fresh edited-gate [log](../tools/validate-logs/negprobe/t11.log). |
| t29 | A missing structural PROBE exited after one a01 row. Each dependent assertion now fails explicitly if PROBE is absent; a11/a12 still run. | `VERDICT PASS`; pre `1/1s, 1/0s, 1/0s, 1/0s, 1/1s`; fix `0/1s, 0/1s, 0/1s, 0/0s, 0/0s`; [log](../tools/validate-logs/t29.log). | REV5 and REV6 both `EXPECTED_FAIL_CONFIRMED` for `a01`–`a10`, `a13`; exit 1/0s → exit 1/0s; fresh edited-gate [log](../tools/validate-logs/negprobe/t29.log). |
| t30 | A missing workflow PROBE exited after an incorrectly attributed a01 row. a03–a08 now fail separately if PROBE is absent; independent a01/a02 still run. | `VERDICT PASS`; pre `1/2s, 1/2s, 1/2s, 1/1s, 1/2s`; fix `0/671s, 0/667s, 0/664s, 0/666s, 0/664s`; [log](../tools/validate-logs/t30.log). | REV5 and REV6 both `EXPECTED_FAIL_CONFIRMED` for `a03`–`a08`; exit 1/2s → exit 1/2s; fresh edited-gate [log](../tools/validate-logs/negprobe/t30.log). |

All six validation logs have `VERDICT PASS` and no `DIRTY-TREE`. All six negative-probe logs are fresh, record the expected failing IDs, and have no `DIRTY_TREE`.

## Missing-bundle setup accounting

| Task | Fixtures-omitted history-zero result |
| --- | --- |
| t11 | All 11 IDs emitted exactly once; a03/a04/a05/a07 explicitly failed for their missing fixtures; exit 1/7s, clean tree, `SETUP_PROBE_RESULT PASS`; [log](../tools/validate-logs/setup-probe/t11.log). |
| t29 | All 13 IDs emitted exactly once; a01–a10/a13 explicitly failed for the missing structural probe while a11/a12 ran; exit 1/0s, clean tree, `SETUP_PROBE_RESULT PASS`; [log](../tools/validate-logs/setup-probe/t29.log). |
| t30 | All 8 IDs emitted exactly once; a03–a08 explicitly failed for the missing workflow probe while a01/a02 ran; exit 1/2s, clean tree, `SETUP_PROBE_RESULT PASS`; [log](../tools/validate-logs/setup-probe/t30.log). |

## Visible-prose route-b records

- t01: Visibly inserting the asserted engineering/reference documentation is indistinguishable from doing the documentation work. No honest superficial-edit FAIL claim exists, so no separate visible-prose run was performed.
- t02: Visibly inserting the asserted support, badge, and bundled-example walkthrough content is indistinguishable from doing the documentation work. No honest superficial-edit FAIL claim exists, so no separate visible-prose run was performed.
- t04: Visibly inserting the asserted public-pipeline documentation is indistinguishable from doing the documentation work. No honest superficial-edit FAIL claim exists, so no separate visible-prose run was performed.

## Scope and evidence integrity

- Exactly six donechecks were edited: `t01`, `t02`, `t04`, `t11`, `t29`, and `t30`. The other 24 donechecks are untouched.
- All six corresponding `units.md` ledgers were updated.
- Every cited validation, negative-probe, and setup-probe log mtime postdates its edited donecheck.
- Expected nonzero pre-leg, negative-probe, and missing-bundle exits are evidence of discrimination/fail-closed behavior, not absorbed validation failures. Honest failures remain findings; only the 5+5 validation's fix legs are required to exit 0, and all 30 fix runs did.
- No files are staged and no commits were created for REV6.
