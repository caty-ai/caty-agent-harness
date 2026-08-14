# t12 units ledger

Units: 13 total; covered 13/13
MECH: 13
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `scripts/content-lint` does not import `yaml`. | `a01` (T4 semantic content-absence via Python AST). |
| U2 | MECH | `scripts/injection-lint` does not import `yaml`. | `a02` (T4 semantic content-absence via Python AST). |
| U3 | MECH | `README.md` has no PyYAML dependency guidance. | `a03` (T4 case-insensitive content-absence). |
| U4 | MECH | `README.ja.md` has no PyYAML dependency guidance. | `a04` (T4 case-insensitive content-absence). |
| U5 | MECH | `README.th.md` has no PyYAML dependency guidance. | `a05` (T4 case-insensitive content-absence). |
| U6 | MECH | `README.zh.md` has no PyYAML dependency guidance. | `a06` (T4 case-insensitive content-absence). |
| U7 | MECH | `docs/repository-map.md` has no PyYAML dependency guidance. | `a07` (T4 case-insensitive content-absence). |
| U8 | MECH | `docs/getting-started.md` has no PyYAML dependency guidance. | `a08` (T4 case-insensitive content-absence). |
| U9 | MECH | `docs/agent-guide.md` has no PyYAML dependency guidance. | `a09` (T4 case-insensitive content-absence). |
| U10 | MECH | `CONTRIBUTING.md` has no PyYAML dependency guidance. | `a10` (T4 case-insensitive content-absence). |
| U11 | MECH | `SECURITY.md` has no PyYAML dependency guidance. | `a11` (T4 case-insensitive content-absence). |
| U12 | MECH | The full suite passes on clean Python. | `a12` (T3 command-exit: `python3 -S scripts/tests/run_tests.py`, explicitly required by the source criterion; `-S` excludes site-packages). |
| U13 | MECH | The full suite has no skipped tests. | `a13` (T6 output-shape assertion on the same suite run). |

## Anonymization, needles, and admission blocker

- Mapping: the source repository is rendered as “this repository”; tracker
  provenance is omitted. All file and command identifiers are criterion-
  constitutive and remain visible.
- Longest T1/T4 needle: `PyYAML` (6 characters). No assertion pins historical
  fix prose.
- The declared pre-fix tree already has both linters on
  `scripts/lib_yamlsubset.py`, contains no `PyYAML` in any of the nine named
  documents, and its full suite reports zero skips. The declared fix changes
  only generated family-footer blocks in the four READMEs. Consequently this
  source-faithful gate passes both trees and must fail the R11 pre-fix-fails
  admission requirement; it is intentionally not tightened with unrelated
  footer checks.
- Timeout remains 120 seconds. The source criterion explicitly demands the full
  suite, so the suite is retained despite the otherwise preferred narrow-probe
  rule.
