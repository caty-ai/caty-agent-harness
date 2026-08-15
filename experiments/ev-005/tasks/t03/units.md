# t03 units ledger

Units: 10 total; covered 10/10
MECH: 7
HUMAN: 1
MOOT: 2

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `.github/workflows/review-labels.yml` is a mechanical copy of the bundled template fixture, with only the four risk-category declaration lines customized. | `a01` (T6 structural: equality against `fixtures/review-labels-template.yml` after normalizing every `RISK_PATHS_[A-Z_]+=...` declaration line on both files to `@@DECL@@`) |
| U2 | MECH | The workflow explicitly declares `RISK_PATHS_AUTH='none'`. | `a02` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U3 | MECH | This repository still has no tracked paths under an `auth/` directory. | `a03` (T4 content-absence via `git ls-files ':(glob,icase)**/auth/**'`) |
| U4 | MECH | Outside `tests/`, this repository still has no tracked filenames matching `auth`, `signin`, or `token`. | `a04` (T4 content-absence over tracked non-test paths). Narrowed from the broader source rationale: the fixed tree contains benign `tests/fixtures/...auth...` filenames, so the surviving mechanical core excludes `tests/`. Lost: a repo-wide zero-match claim including test fixtures. |
| U5 | MECH | The existing `none` declaration for the billing risk category is unchanged. | `a05` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U6 | MECH | The existing `none` declaration for the outbound risk category is unchanged. | `a06` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U7 | MECH | The existing `none` declaration for the gate-specific risk category is unchanged. | `a07` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U8 | MOOT | The branch CI is green. | Dropped (MOOT: branch/CI platform state is absent from the offline history-zero replica.) |
| U9 | HUMAN | The human risk-review label is present. | Dropped (HUMAN: requires a live platform label plus human action outside the replica.) |
| U10 | MOOT | The change is merged. | Dropped (MOOT: merge state does not exist inside the offline replica.) |

Notes:
- Fixture exemption: `fixtures/review-labels-template.yml` bundles the canonical workflow bytes as a criterion-constitutive in-replica fixture. The canonical source lives outside the replica, but the bundled content is the task's shipped spec per `translation-rules.md` §2 and §5 r2.
- Blob-pin removal: the prior `EXPECT_WORKFLOW_BLOB` exact hash pin was removed because it depended on an out-of-replica source and made the task unsolvable in-replica (acceptance finding B1 / §5 r2).

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, person, date, live CI, label, and merge provenance is omitted;
  the workflow path and bundled canonical fixture remain because U1 names the
  comparison surface and the fixture ships in-replica.
- Longest T1/T4 needle: `(^|/)[^/]*(auth|signin|token)[^/]*$|(^|/)auth/` (46
  characters). This small path/category expression is derived from U3/U4; the
  workflow equality itself is a T6 comparison against the bundled source.
- Timeout remains the default 120 seconds because the gate performs bounded
  file normalization, comparison, and tracked-path scans without executing
  repository code.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append the shell-comment text `RISK_PATHS_AUTH='none'` to `.github/workflows/review-labels.yml`, leaving the operative auth-path logic untouched.
- Route: `a`
- Expected result: `a01` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`; `RUN t03 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t03.log`.
- Rationale: A commented token does not create the required live auth-path handling or filename evidence.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t03.log` (current pre-leg record).
- a03 — invariance guard: The pre-fix tree already has no auth-path filenames in the prohibited location, so the gate protects against introducing them.
- a04 — invariance guard: The pre-fix tree already preserves the first `none` risk-path variable; this PASS is a deliberate no-auth-path guard.
- a05 — invariance guard: The pre-fix tree already preserves the second `none` risk-path variable, so the assertion guards non-regression.
- a06 — invariance guard: The pre-fix tree already preserves the third `none` risk-path variable, making this an intentional invariant.
- a07 — invariance guard: The pre-fix tree already avoids the retired auth-path/filename combination, so the PASS is a regression guard.
