# t03 units ledger

Units: 10 total; covered 10/10
MECH: 7
HUMAN: 1
MOOT: 2

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `.github/workflows/review-labels.yml` matches the required regenerated workflow snapshot for this repository. | `a01` (T6 structural: exact workflow snapshot) |
| U2 | MECH | The workflow explicitly declares `RISK_PATHS_AUTH='none'`. | `a02` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U3 | MECH | This repository still has no tracked paths under an `auth/` directory. | `a03` (T4 content-absence via `git ls-files ':(glob,icase)**/auth/**'`) |
| U4 | MECH | Outside `tests/`, this repository still has no tracked filenames matching `auth`, `signin`, or `token`. | `a04` (T4 content-absence over tracked non-test paths). Narrowed from the broader source rationale: the fixed tree contains benign `tests/fixtures/...auth...` filenames, so the surviving mechanical core excludes `tests/`. Lost: a repo-wide zero-match claim including test fixtures. |
| U5 | MECH | The existing `none` declaration for the billing risk category is unchanged. | `a05` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U6 | MECH | The existing `none` declaration for the outbound risk category is unchanged. | `a06` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U7 | MECH | The existing `none` declaration for the gate-specific risk category is unchanged. | `a07` (T1 content-presence in `.github/workflows/review-labels.yml`) |
| U8 | MOOT | The branch CI is green. | Dropped (MOOT: branch/CI platform state is absent from the offline history-zero replica.) |
| U9 | HUMAN | The human risk-review label is present. | Dropped (HUMAN: requires a live platform label plus human action outside the replica.) |
| U10 | MOOT | The change is merged. | Dropped (MOOT: merge state does not exist inside the offline replica.) |
