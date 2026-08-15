# t30 units ledger

Units: 10 total; covered 10/10
MECH: 3
HUMAN: 5
MOOT: 2

Anonymization mapping: the source repository is "this repository"; upstream
repository and parent-work identifiers, issue/PR numbers, owner identity,
dates, commit/template provenance, and branch-lane history are omitted. Local
workflow paths, Make targets, and required-check names remain because the
source completion criterion makes them functional targets.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MOOT | The roster change is merged before the workflow change. | Dropped (MOOT: the history-zero replica has no pull-request or merge-order topology). The roster itself belongs to the earlier change and is not in this task's supplied fix snapshot. |
| U2 | MOOT | The workflow/Makefile change is merged. | Dropped (MOOT: merge state is absent from the history-zero replica). |
| U3 | MECH | The Makefile and five pull-request workflow definitions exist. | `a03` (T2/T6: require the five named files and common pull-request workflow structure) plus `a04`–`a08` (T6 semantic structure checks). Workflow YAML cannot execute as hosted Actions in-replica, so its structure and fail-closed content are mechanized directly. |
| U4 | MECH | `make test` runs all repository shell suites and passes. | `a01` (T3 direct command-exit: `make test`). `a04` additionally proves the test-lint workflow invokes that same target and fails closed when it is unavailable. The full command is source-required, so it is not replaced by YAML grep. |
| U5 | MECH | `make lint` syntax-checks every tracked shell file and passes. | `a02` (T3 direct command-exit: `make lint`) plus `a04` (T6 workflow binding). The full command is source-required. |
| U6 | HUMAN | Three repository labels exist on the hosting platform. | Dropped (HUMAN: live label objects require external platform interaction unavailable in the sealed replica). |
| U7 | HUMAN | Five named checks are registered as required, the external audit is green, and `pr-size` is advisory. | Weakened (HUMAN→MECH extraction): `a03` requires the corresponding local job/check names and keeps `pr-size` outside the required-name set. Lost: live branch-protection registration and the network-backed external audit. |
| U8 | HUMAN | An unmerged verification change exercises all red/green gates, the label cycle, size rejection, and blocked merge state. | Weakened (HUMAN→MECH extraction): `a04`–`a08` inspect the local fail-closed mechanisms for test/lint, secret scanning, size, history, and risk review; `a01`/`a02` run the available underlying commands. Lost: hosted event execution, label mutation, server-side secret fixture, platform check conclusions, and branch-protection BLOCKED state. |
| U9 | HUMAN | Reusable learning is filed upstream or a no-learning record exists. | Dropped (HUMAN: deciding whether a learning is reusable and recording it on an external tracker requires judgment and network state). |
| U10 | HUMAN | The parent rollout checklist links to this deployment. | Dropped (HUMAN: the parent tracker and link target are outside the single-repository replica). |

Workflow structural mappings:
- `a03`: all five files are pull-request workflows with explicit permissions,
  jobs, runners, and the criterion-named required job names; none uses
  `pull_request_target`.
- `a04`: test/lint jobs invoke `make test`/`make lint` under strict shell and
  fail when their targets are unconfigured.
- `a05`: the secret gate resolves a merge base, verifies its downloaded scanner
  checksum, scans the range, and has explicit failure exits.
- `a06`: the size gate has a numeric limit, rejects totals over it, and handles
  its human exemption label separately.
- `a07`: the history gate resolves the base and fails when no common ancestor
  can be judged.
- `a08`: the risk workflow detects paths, reads the base-branch roster,
  requires human review for risky changes, invalidates approval on a new head,
  and treats visibility labels as non-authoritative.

Needle calibration and solvability:
- Longest fixed T1/T4 phrase is `risk-review-gate` (16 characters), a
  source-required check name. Other tokens are workflow paths, commands, job
  names, or fail-closed primitives stated in task.md or visible in the pre-fix
  repository conventions; no historical prose sentence is pinned.
- Timeout is escalated from 120 to 1800 seconds because the source criterion
  explicitly requires the complete shell suite and a local fix-snapshot sanity
  run exceeded the default budget; that local run was then terminated to avoid
  resource contention once the escalation evidence was established. The
  syntax sweep passed separately in under one second. The fresh serialized
  REV6 validation below provides the authoritative full-suite durations.

## REV6 validation evidence (r3-4)

- Fresh 5+5 history-zero validation: pre exit/duration pairs were `1/2s`, `1/2s`, `1/2s`, `1/1s`, `1/2s`; fix pairs were `0/671s`, `0/667s`, `0/664s`, `0/666s`, `0/664s`. `VERDICT PASS`, no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/t30.log`.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Add a fake `Makefile` with no-op `test` and `lint` targets while leaving the workflow definitions unchanged.
- Route: `a`
- Expected result: `a03`-`a08` should still FAIL.
- Evidence status: REV5 recorded `EXPECTED_FAIL_CONFIRMED` for `a03`–`a08` (`exit=1`, `dur=2s`); the fresh REV6 run confirms the same failing IDs after the setup-accounting edit (`exit=1`, `dur=2s`, no `DIRTY_TREE`) in `experiments/ev-005/tools/validate-logs/negprobe/t30.log`.
- Rationale: Stub targets do not satisfy the workflow-shape and gate-authority checks behind the remaining assertions.

## Setup accounting (REV6 r5-3)

- Workflow-probe setup is accounted per assertion: if `workflow_probe.py` is missing, each dependent ID (`a03`–`a08`) emits its own explicit FAIL while independent `make test`/`make lint` checks `a01` and `a02` still run; every ID emits exactly one CHECK. A history-zero, fixtures-omitted setup probe emitted `a01`–`a08` exactly once, exited 1 in 2s, left a clean tree, and recorded `SETUP_PROBE_RESULT PASS` in `experiments/ev-005/tools/validate-logs/setup-probe/t30.log`.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t30.log` shows no constant-true assertions.
