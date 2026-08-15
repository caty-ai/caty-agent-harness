# REV5 report

Date: Saturday, August 15, 2026

Requested/actual writer target recorded for the owning lane: `gpt-5.6-sol` / `high`.

Status summary:
- All 30 `task.md` files now use the mandated attempt-budget line and the clarified donecheck-timeout wording, with no template placeholders remaining.
- Fresh t01/t07 terminal revalidation is complete and both tasks now PASS across 5 pre runs plus 5 fix runs.
- Negative validity probing is complete for all 29 route-(a) tasks; t14 is correctly recorded as route `(b)` impossibility with no negprobe log.
- Route-(a) outcome split: 26 `EXPECTED_FAIL_CONFIRMED`, 3 `UNEXPECTED_PASS_CONFIRMED` (`t01`, `t02`, `t04`).
- Bundle verdict is `HOLD`: six task-level STOP blockers remain (`t01`, `t02`, `t04`, `t11`, `t29`, `t30`).
- No REV5 file was staged or committed. During this work window, a concurrent unrelated commit advanced `HEAD` from `f91a2a8` to `92349aa`; that commit contains only `analysis-plan.md`, `runner-spec.md`, and the MDD tool artifacts, while every uncommitted REV5 path remains inside the brief's allowlist.

## Budget / timeout table

| Task | timeout_s | Placeholder clean | Note |
| --- | --- | --- | --- |
| t01 | 1800 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t02 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t03 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t04 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t05 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t06 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t07 | 1800 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t08 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t09 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t10 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t11 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t12 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t13 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t14 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t15 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t16 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t17 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t18 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t19 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t20 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t21 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t22 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t23 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t24 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t25 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t26 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t27 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t28 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t29 | 120 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |
| t30 | 1800 | yes | Current task.md is template-clean and keeps attempt budget separate from donecheck timeout. |

## Negative validity probe table (r5-1)

| Task | Route | Minimal non-solution edit | Expected failing IDs / impossibility | Evidence |
| --- | --- | --- | --- | --- |
| t01 | a (UNEXPECTED_PASS blocker) | Insert HTML comment blocks carrying the asserted producer-only, consumer, schedule window, LaunchAgent, marker, archive, and INSTALL-path needles into `docs/engineering.md`, `docs/reference.md`, `docs/engineering.ja.md`, and `docs/reference.ja.md` without changing the live prose or running the suite. | No trustworthy failing IDs to cite: the strongest surface cheat produces `UNEXPECTED_PASS`. | `UNEXPECTED_PASS_CONFIRMED`; no failing CHECK IDs; `RUN t01 negprobe exit=0 dur=668s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t01.log`. |
| t02 | a (UNEXPECTED_PASS blocker) | Insert HTML comments carrying the asserted footer prose into `README.md`, `README.ja.md`, `README.zh.md`, `README.th.md`, and `docs/agent-guide.md` without changing rendered body text. | No trustworthy failing IDs to cite: the strongest surface cheat produces `UNEXPECTED_PASS`. | `UNEXPECTED_PASS_CONFIRMED`; no failing CHECK IDs; `RUN t02 negprobe exit=0 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t02.log`. |
| t03 | a | Append `# RISK_PATHS_AUTH='none'` to `.github/workflows/review-labels.yml` while leaving the real auth-path logic untouched. | `a01` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`; `RUN t03 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t03.log`. |
| t04 | a (UNEXPECTED_PASS blocker) | Insert one HTML comment containing the `x-collector` URL, pipeline, inherit, and collection-controls needles into `docs/trial-isolation.md` without changing the live wiring or isolation behavior. | No trustworthy failing IDs to cite: the strongest surface cheat produces `UNEXPECTED_PASS`. | `UNEXPECTED_PASS_CONFIRMED`; no failing CHECK IDs; `RUN t04 negprobe exit=0 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t04.log`. |
| t05 | a | Append only missing positive needles as comments to `templates/examples/img-pilot.task.md`, the Codex/Kimi/Hermes INSTALL files, `templates/TASK.tmpl.md`, `scripts/family-updater`, `templates/updater-cron.tmpl.sh`, and `install.sh`, leaving operative legacy content unchanged. | `a06`-`a09`, `a18`, `a19`, `a22`, `a23`, `a27`, `a30`, `a31`, `a33`, and `a37` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a06`, `a07`, `a08`, `a09`, `a18`, `a19`, `a22`, `a23`, `a27`, `a30`, `a31`, `a33`, `a37`; `RUN t05 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t05.log`. |
| t06 | a | Add positive comments to `docs/agent-guide.md` and the Hermes/OpenClaw/Claude INSTALL files, backtick the existing auth-error symptom, add historical-record comments to the four asserted design/governance documents, and append a superficial deployment-inventory section to `docs/updater-rollout.md`, without removing private-era wording. | `a03`, `a04`, `a07`, `a08`, `a11`, `a12`, `a15`, and `a27`-`a29` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a03`, `a04`, `a07`, `a08`, `a11`, `a12`, `a15`, `a27`, `a28`, `a29`; `RUN t06 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t06.log`. |
| t07 | a | Append public-name needles as comments to `DESIGN.md`, `DESIGN-task-runner.md`, `SYNTHESIS.md`, `SYNTHESIS-task-runner.md`, `docs/governance-rules.md`, `docs/updater-rollout.md`, `scripts/lib-wrapper-conformance.sh`, and `scripts/attest-wrapper`, leaving retired live strings present. | The even content-absence IDs `a02`-`a36` plus `a37` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a04`, `a06`, `a08`, `a10`, `a12`, `a14`, `a16`, `a18`, `a20`, `a22`, `a24`, `a26`, `a28`, `a30`, `a32`, `a34`, `a36`, `a37`; `RUN t07 negprobe exit=1 dur=664s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t07.log`. |
| t08 | a | Append public-name needles only as comments to the Claude/Codex/Kimi INSTALL and hook files, `docs/plugin-convention.md`, the three scheduler templates, and `tests/pause-contract.test.sh`, leaving all retired live strings intact. | `a02`, `a04`, `a06`, `a08`, `a10`, `a12`, `a14`, `a16`, `a18`, `a20`, `a22`, `a24`, `a26`, `a28`, `a30`, `a34`, `a36`, `a38`, `a40`, `a42`, `a44`, `a46`, `a48`, `a50`, `a52`, `a54`, `a56`, `a58`, `a60`, and `a62` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a04`, `a06`, `a08`, `a10`, `a12`, `a14`, `a16`, `a18`, `a20`, `a22`, `a24`, `a26`, `a28`, `a30`, `a34`, `a36`, `a38`, `a40`, `a42`, `a44`, `a46`, `a48`, `a50`, `a52`, `a54`, `a56`, `a58`, `a60`, `a62`; `RUN t08 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t08.log`. |
| t09 | a | Add two top-level no-op test functions or docstrings carrying the asserted coverage tokens to `scripts/tests/test_family_hot_generate.py` without changing the real permission-probe logic. | `a01` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`; `RUN t09 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t09.log`. |
| t10 | a | Insert one empty unknown generated block in `README.md` only, immediately before the license footer, without touching the localized READMEs. | `a02`-`a06` and `a08` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a03`, `a04`, `a05`, `a06`, `a08`; `RUN t10 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t10.log`. |
| t11 | a | Create executable `tests/surface-secrets.test.sh` with only the asserted discovery tokens in a comment and `exit 0`, leaving shared-source, missing-prefix, and stdout-row behavior untouched. | `a04`-`a07` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a04`, `a05`, `a06`, `a07`; `RUN t11 negprobe exit=1 dur=10s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t11.log`. |
| t12 | a | Replace `import yaml` with a dynamic import inside `scripts/content-lint` while leaving the rest of the linter and document corpus unchanged. | `a02`-`a11` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a03`, `a04`, `a05`, `a06`, `a07`, `a08`, `a09`, `a10`, `a11`; `RUN t12 negprobe exit=1 dur=22s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t12.log`. |
| t13 | a | Replace the leading table-pipe marker with `¦` on the eleven duplicate family-table rows so they still read similarly but no longer parse as Markdown table rows. | `a10`-`a12` and `a18`-`a20` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a10`, `a11`, `a12`, `a18`, `a19`, `a20`; `RUN t13 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t13.log`. |
| t14 | b | No honest route-(a) surface cheat exists short of writing the real singleton JSON object with the correct typed fields and passing both named repository checks. | Impossibility class: strict JSON singleton and typed-equality probes leave no superficial text-only substitute. | Route `(b)` record only; no negprobe log is required by the brief for impossibility cases. |
| t15 | a | Append exactly ``Validator smoke fixture: `docs/`.`` to the root `README.md` only while leaving the real repository-map fix absent. | `a01`-`a03` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`, `a02`, `a03`; `RUN t15 negprobe exit=1 dur=1s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t15.log`. |
| t16 | a | Append two unreachable `if False:` test functions carrying the 0600-accept and 0644-reject recall AST tokens to `scripts/tests/test_recall.py`. | `a02` and `a06` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a06`; `RUN t16 negprobe exit=1 dur=2s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t16.log`. |
| t17 | a | Append a comment carrying the deadman/template/check/marker/exit tokens to `tests/deadman-probe.test.sh`, without wiring the real deadman behavior. | `a01`-`a03` and `a05`-`a07` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`, `a02`, `a03`, `a05`, `a06`, `a07`; `RUN t17 negprobe exit=1 dur=9s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t17.log`. |
| t18 | a | Relabel the `self-growth-loop` registry entry so the identifier becomes `context-kit`, keeping the surrounding published metadata superficially similar. | `a07`-`a14` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a07`, `a08`, `a09`, `a10`, `a11`, `a12`, `a13`, `a14`; `RUN t18 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t18.log`. |
| t19 | a | Append a comment carrying the cron-wrapper, secrets-env, touch, mode, and symlink tokens to `tests/deadman-probe.test.sh`, without restoring the wrapper structure. | `a01`-`a03` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`, `a02`, `a03`; `RUN t19 negprobe exit=1 dur=1s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t19.log`. |
| t20 | a | Create an empty `docs/evidence.md` while leaving the real evidence content and workflow changes absent. | `a02`-`a09` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a03`, `a04`, `a05`, `a06`, `a07`, `a08`, `a09`; `RUN t20 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t20.log`. |
| t21 | a | Expand the first `verifier_id` token in `DESIGN.md` and append a `verified_at: verifier_id: promotion` comment to `skills/_staging/SKILL.tmpl.md`, without fixing the verifier contract. | `a03` and `a06` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a03`, `a06`; `RUN t21 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t21.log`. |
| t22 | a | Replace `assets/readme/hero.png` with a one-byte placeholder while leaving the README/docs/test corpus untouched. | `a05`, `a06`, `a08`, and `a09` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a05`, `a06`, `a08`, `a09`; `RUN t22 negprobe exit=1 dur=7s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t22.log`. |
| t23 | a | Add token-only comments to `tests/task-runner.test.sh` and `tests/tr-enqueue.test.sh` without changing live input-validation logic. | `a01`-`a06` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`, `a02`, `a03`, `a04`, `a05`, `a06`; `RUN t23 negprobe exit=1 dur=6s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t23.log`. |
| t24 | a | Create an empty `tools/check_publication_gate.py` while leaving the real gate implementation and renderer behavior absent. | `a05`, `a06`, `a08`, and `a13`-`a22` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a05`, `a06`, `a08`, `a13`, `a14`, `a15`, `a16`, `a17`, `a18`, `a19`, `a20`, `a21`, `a22`; `RUN t24 negprobe exit=1 dur=1s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t24.log`. |
| t25 | a | Append `SSH signing uses allowed_signers outside the repository.` to `docs/updater-rollout.md` without changing `scripts/lib-updater-verify.sh` or `tests/family-updater.test.sh`. | `a02` and `a04`-`a06` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a04`, `a05`, `a06`; `RUN t25 negprobe exit=1 dur=14s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t25.log`. |
| t26 | a | Replace `docs/cli-conventions.md` with a token-only conventions stub while leaving the runner and tests unchanged. | `a05` and `a06` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a05`, `a06`; `RUN t26 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t26.log`. |
| t27 | a | Create only an eight-section `FOR-AGENTS.md` skeleton and give it a bogus `caty-ai/not-real` tour row, without changing any registry or growth-model source. | `a08` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a08`; `RUN t27 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t27.log`. |
| t28 | a | Append a trust-boundary sentence naming arbitrary shell, privilege, sandbox, post-enqueue mutation, `setsid`, and provider-attestation risks to `DESIGN-task-runner.md`, without updating the runner, receipts, or tests. | `a02`-`a08` and `a10` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a03`, `a04`, `a05`, `a06`, `a07`, `a08`, `a10`; `RUN t28 negprobe exit=1 dur=1s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t28.log`. |
| t29 | a | Replace the shared growth SVG with exactly `<svg role="img"></svg>`. | `a01`-`a10` and `a13` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`, `a02`, `a03`, `a04`, `a05`, `a06`, `a07`, `a08`, `a09`, `a10`, `a13`; `RUN t29 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t29.log`. |
| t30 | a | Add a fake `Makefile` with no-op `test` and `lint` targets while leaving the workflow definitions unchanged. | `a03`-`a08` should still FAIL. | `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a03`, `a04`, `a05`, `a06`, `a07`, `a08`; `RUN t30 negprobe exit=1 dur=2s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t30.log`. |

## Constant-true totals and by-task ledger (r5-2)

- Bundle totals from the current first-pre assertion inventory: `466` assertions / `104` declared constant-true assertions.
- `t01`: fresh terminal log records `a15`, `a18`, and `a19`-`a25` as constant-true after the a25 unshort-circuit fix.
- `t07`: fresh first pre leg records `a38` and `a39` as invariance guards after the a38/a39 unshort-circuit fix.

| Task | Assertion count | Constant-true count | Oversight IDs | Guard IDs | Notes |
| --- | --- | --- | --- | --- | --- |
| t01 | 25 | 9 | a15, a18 | a19, a20, a21, a22, a23, a24, a25 | Fresh terminal log recorded; pre runs 1-5 exit=1, fix runs 1-5 exit=0. |
| t02 | 25 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t03 | 7 | 5 | - | a03, a04, a05, a06, a07 | Current pre-leg log reflected in ledger. |
| t04 | 9 | 6 | a04 | a05, a06, a07, a08, a09 | Current pre-leg log reflected in ledger. |
| t05 | 39 | 3 | - | a36, a40, a41 | Current pre-leg log reflected in ledger. |
| t06 | 30 | 7 | - | a13, a21, a22, a23, a24, a25, a26 | Current pre-leg log reflected in ledger. |
| t07 | 39 | 2 | - | a38, a39 | Fresh first-pre recount recorded; full 5+5 revalidation PASS is logged separately below. |
| t08 | 77 | 17 | a03, a32 | a63, a64, a65, a66, a67, a68, a69, a70, a71, a72, a73, a74, a75, a76, a77 | Current pre-leg log reflected in ledger. |
| t09 | 4 | 2 | - | a02, a03 | Current pre-leg log reflected in ledger. |
| t10 | 12 | 5 | - | a08, a09, a10, a11, a12 | Current pre-leg log reflected in ledger. |
| t11 | 11 | 6 | - | a02, a03, a08, a09, a10, a11 | Current pre-leg log reflected in ledger. |
| t12 | 13 | 2 | - | a12, a13 | Current pre-leg log reflected in ledger. |
| t13 | 20 | 12 | - | a01, a02, a03, a04, a05, a06, a07, a08, a13, a14, a15, a16 | Current pre-leg log reflected in ledger. |
| t14 | 6 | 2 | - | a05, a06 | Current pre-leg log reflected in ledger. |
| t15 | 4 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t16 | 6 | 2 | - | a01, a05 | Current pre-leg log reflected in ledger. |
| t17 | 7 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t18 | 14 | 2 | - | a05, a06 | Current pre-leg log reflected in ledger. |
| t19 | 5 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t20 | 9 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t21 | 6 | 2 | - | a04, a05 | Current pre-leg log reflected in ledger. |
| t22 | 11 | 6 | - | a01, a02, a03, a04, a07, a11 | Current pre-leg log reflected in ledger. |
| t23 | 7 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t24 | 25 | 11 | a01, a02, a03, a04, a09, a10, a11, a12, a21 | a07, a23 | Current pre-leg log reflected in ledger. |
| t25 | 6 | 1 | - | a03 | Current pre-leg log reflected in ledger. |
| t26 | 6 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t27 | 12 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t28 | 10 | 0 | - | - | Current pre-leg log reflected in ledger. |
| t29 | 13 | 2 | - | a11, a12 | Current pre-leg log reflected in ledger. |
| t30 | 8 | 0 | - | - | Current pre-leg log reflected in ledger. |

## Short-circuit scan / revalidation table (r5-3)

| Task | Status | Note |
| --- | --- | --- |
| t01 | revalidated PASS | Fresh terminal evidence in `experiments/ev-005/tools/validate-logs/t01.log`: pre runs 1-5 exit=`1`, fix runs 1-5 exit=`0`, durations pre `678/662/658/672/670`s and fix `663/666/654/660/670`s, with no `DIRTY-TREE`. |
| t02 | clean | No conditional assertion skipping found in the current donecheck. |
| t03 | clean | No conditional assertion skipping found in the current donecheck. |
| t04 | clean | No conditional assertion skipping found in the current donecheck. |
| t05 | clean | No conditional assertion skipping found in the current donecheck. |
| t06 | clean | No conditional assertion skipping found in the current donecheck. |
| t07 | revalidated PASS | Fresh terminal evidence in `experiments/ev-005/tools/validate-logs/t07.log`: pre FAIL x5 / fix PASS x5, pre runs 1-5 exit=`1` with durations `668/668/678/663/664`s, fix runs 1-5 exit=`0` with durations `673/669/668/665/687`s, and no `DIRTY-TREE`. |
| t08 | clean | No conditional assertion skipping found in the current donecheck. |
| t09 | clean | No conditional assertion skipping found in the current donecheck. |
| t10 | clean | No conditional assertion skipping found in the current donecheck. |
| t11 | STOP blocker | Frozen setup-exit block at `experiments/ev-005/tasks/t11/donecheck.sh:228-237` exits before ordinary assertion flow when bundled fixtures are missing. Out of scope for this pass because only t01/t07 donechecks were open. |
| t12 | clean | No conditional assertion skipping found in the current donecheck. |
| t13 | clean | No conditional assertion skipping found in the current donecheck. |
| t14 | clean | No conditional assertion skipping found in the current donecheck. |
| t15 | clean | No conditional assertion skipping found in the current donecheck. |
| t16 | clean | No conditional assertion skipping found in the current donecheck. |
| t17 | clean | No conditional assertion skipping found in the current donecheck. |
| t18 | clean | No conditional assertion skipping found in the current donecheck. |
| t19 | clean | No conditional assertion skipping found in the current donecheck. |
| t20 | clean | No conditional assertion skipping found in the current donecheck. |
| t21 | clean | No conditional assertion skipping found in the current donecheck. |
| t22 | clean | No conditional assertion skipping found in the current donecheck. |
| t23 | clean | No conditional assertion skipping found in the current donecheck. |
| t24 | clean | No conditional assertion skipping found in the current donecheck. |
| t25 | clean | No conditional assertion skipping found in the current donecheck. |
| t26 | clean | No conditional assertion skipping found in the current donecheck. |
| t27 | clean | No conditional assertion skipping found in the current donecheck. |
| t28 | clean | No conditional assertion skipping found in the current donecheck. |
| t29 | STOP blocker | Frozen setup-exit block at `experiments/ev-005/tasks/t29/donecheck.sh:53-56` exits before ordinary assertion flow if the bundled structural probe is missing. Out of scope for this pass. |
| t30 | STOP blocker | Frozen setup-exit block at `experiments/ev-005/tasks/t30/donecheck.sh:64-67` exits before ordinary assertion flow if the bundled workflow probe is missing. Out of scope for this pass. |

## t13 r4-2 disposition

- Recorded in `experiments/ev-005/tasks/t13/units.md`: the broad in-repo suite exercises unrelated script subsystems, not the README footer-block criterion units; the byte-exact SHA-256 plus structure probes are stronger here, and `scripts/tests/test_recall.py` also carries the FMA#18 passwd-home / restored-`HOME` coupling risk.

## STOP blockers

- `t01`: negative validity probe surface cheat still yields `UNEXPECTED_PASS_CONFIRMED`.
- `t02`: negative validity probe surface cheat still yields `UNEXPECTED_PASS_CONFIRMED`.
- `t04`: negative validity probe surface cheat still yields `UNEXPECTED_PASS_CONFIRMED`.
- `t11`: frozen setup-exit block at `donecheck.sh:228-237`.
- `t29`: frozen setup-exit block at `donecheck.sh:53-56`.
- `t30`: frozen setup-exit block at `donecheck.sh:64-67`.
