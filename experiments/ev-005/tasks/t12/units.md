# t12 units ledger

Units: 13 total; covered 13/13
MECH: 13
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `scripts/content-lint` does not import `yaml`. | `a01` (T4 semantic content-absence via Python AST under an invocation-specific fresh `HOME` and `TMPDIR`). |
| U2 | MECH | `scripts/injection-lint` does not import `yaml`. | `a02` (T4 semantic content-absence via Python AST under an invocation-specific fresh `HOME` and `TMPDIR`). |
| U3 | MECH | `README.md` has no PyYAML dependency guidance. | `a03` (T4 case-insensitive content-absence). |
| U4 | MECH | `README.ja.md` has no PyYAML dependency guidance. | `a04` (T4 case-insensitive content-absence). |
| U5 | MECH | `README.th.md` has no PyYAML dependency guidance. | `a05` (T4 case-insensitive content-absence). |
| U6 | MECH | `README.zh.md` has no PyYAML dependency guidance. | `a06` (T4 case-insensitive content-absence). |
| U7 | MECH | `docs/repository-map.md` has no PyYAML dependency guidance. | `a07` (T4 case-insensitive content-absence). |
| U8 | MECH | `docs/getting-started.md` has no PyYAML dependency guidance. | `a08` (T4 case-insensitive content-absence). |
| U9 | MECH | `docs/agent-guide.md` has no PyYAML dependency guidance. | `a09` (T4 case-insensitive content-absence). |
| U10 | MECH | `CONTRIBUTING.md` has no PyYAML dependency guidance. | `a10` (T4 case-insensitive content-absence). |
| U11 | MECH | `SECURITY.md` has no PyYAML dependency guidance. | `a11` (T4 case-insensitive content-absence). |
| U12 | MECH | The full suite passes on clean Python. | `a12` (T3 command-exit: `python3 -S scripts/tests/run_tests.py`, explicitly required by the source criterion; `-S` excludes site-packages). The suite invocation receives a fresh `HOME` and `TMPDIR` and is cleaned up before the gate exits. |
| U13 | MECH | The full suite has no skipped tests. | `a13` (T6 output-shape assertion on the same isolated suite run). |

## Anonymization and needles

- Mapping: the source repository is rendered as “this repository”; tracker
  provenance is omitted. All file and command identifiers are criterion-
  constitutive and remain visible.
- Longest T1/T4 needle: `PyYAML` (6 characters). No assertion pins historical
  fix prose.
- Pair note (superseding the drafter's original R11-fail paragraph; author
  correction under ledger finding I-2, seat finding N1): the originally
  surveyed pre_fix (`a55397b5`, the feature-branch tip of a
  reverse-merge-then-fast-forward) already satisfied every check, which is why
  the first validity run honestly FAILed. The corrected `pre_fix = 25b426bb`
  (main before the port landed) has `import yaml` in both linters and PyYAML
  guidance in the named documents. Before the r4 probe-isolation backfill, the
  corrected pair validated pre FAIL×5 / fix PASS×5. The authoritative isolated
  REV3 rerun now records pre FAIL×5 / fix FAIL×5
  (`../../tools/validate-logs/t12.log`): every fix run fails `a12` because
  `test_recall.RecallTests.test_search_adapters_guard_leading_dash_query`
  observes the account passwd-home after clearing the process environment,
  while its post-context expectation expands against the fresh `HOME`; `a13`
  still confirms `skipped=0`. A canonical `pwd -P` isolated root reproduced
  the same single-test failure, ruling out a double-slash or noncanonical temp
  path. This is an admission finding, not a gate weakening.
- Timeout remains 120 seconds. The source criterion explicitly demands the full
  suite, so the suite is retained despite the otherwise preferred narrow-probe
  rule. The fresh `HOME`/`TMPDIR` suite runs completed in 23–25 seconds.
