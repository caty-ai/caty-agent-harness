# p03 units ledger

Units: 12 total; covered 12/12
MECH: 12
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The CLI verifier provider uses the verdict-last unique-marker prompt contract and keeps the provider → wrapper interface as exactly two normalized lines. | `a01` (T1/T6 checks using short parser identifiers such as `count_exact`, `marker_count`, and `verdict_number`, plus the normalized two-line emit path); `a05` behaviorally exercises the CLI path and verifies the new verdict-last/malformed/NUL cases are present in the focused suite. |
| U2 | MECH | The Python verifier provider uses the same verdict-last unique-marker contract and position-free parser. | `a02` (T1/T6 checks using short parser identifiers such as `VERDICT_PATTERN`, `verdict_indexes`, and `normalized_lines`); `a06` behaviorally exercises the Python-provider/example path and verifies the new acceptance and rejection matrices are present in the focused suite. |
| U3 | MECH | The wrapper accepts exactly one anchored allowed verdict anywhere in provider output, uses the first following non-empty line as the reason, and keeps exit codes `64`/`65`/`69`/`70` unchanged. | `a03` (T6 structural/content check on the wrapper parser and exit-code branches). |
| U4 | MECH | The bundled verifier template and install notes describe the position-free unique-marker contract instead of the old first-line rule. | `a04` (T1 content-presence using short phrases for the anchored verdict, occurrence count, NUL rejection, and last-two-line reply instruction) plus `a09` (T4 content-absence of stale `FIRST line` wording in the touched example/docs surfaces). |
| U5 | MECH | The CLI verifier path accepts the production-shaped verdict-last reply shape. | `a05` (T3 focused CLI verifier regression suite). |
| U6 | MECH | The example wrapper/provider path accepts the production-shaped verdict-last reply shape. | `a06` (T3 focused example verifier regression suite). |
| U7 | MECH | Verdict-first replies are still accepted under the new position-free parser. | `a05` and `a06` (T3 focused regression suites cover both valid reply positions). |
| U8 | MECH | Malformed replies fail closed on the CLI verifier path: zero verdict, duplicated verdict, smuggled extra `VERDICT:`, missing reason, and malformed anchors are all rejected. | `a05` (T3 focused CLI verifier regression suite). |
| U9 | MECH | Malformed replies fail closed on the example wrapper/provider path: zero verdict, duplicated verdict, smuggled extra `VERDICT:`, missing reason, malformed anchors, and inert bundle text that only mentions verdict markers do not manufacture a pass. | `a06` (T3 focused example verifier regression suite). |
| U10 | MECH | Any NUL byte in reply output is rejected fail-closed across the wrapper, the CLI verifier provider, and the Python verifier provider. | `a10`, `a11`, `a12` (T1 structural/content checks on the merged NUL-byte guards) plus `a05` and `a06` (T3 suites exercise the fail-closed behavior). |
| U11 | MECH | The broader verifier integrations still pass with the unchanged wrapper contract. | `a07` (T3 `tests/verify-job.test.sh`) and `a08` (T3 `tests/wrapper-conformance.test.sh`), both under invocation-specific fresh `HOME` and `TMPDIR`. |
| U12 | MECH | No touched example or install surface still describes the old `FIRST line` contract. | `a09` (T4 content-absence over the touched example/docs surfaces). |

## Anonymization and needle record

- Mapping: the source repository is rendered as “this repository”; issue, PR,
  review-seat, branch, and date provenance are omitted from the task sheet.
- Anonymization-sweep exemptions: `VERDICT:`, `VERDICT: <value>`, and
  `quoted or injected anchored marker` are retained because the recovered
  source criterion names the public verifier contract itself; deleting them
  would make the replica underspecified. Repository-relative paths are
  criterion-constitutive and remain visible.
- Longest prose-like T1/T4 needle: `anchored allowed verdict` (24 characters),
  a short phrase naming the documented parser contract. Longer fixed strings
  are code identifiers or executable shell fragments, not historical prose.
- Timeout is 180 seconds. The only command assertions are the four local
  verifier suites (`hermes-verifier-cli`, `hermes-verifier-examples`,
  `verify-job`, and `wrapper-conformance`); no full repository suite is
  invoked. The margin covers an observed 120-second contention timeout during
  admission validation.

## Negative validity probe (r5-1)

- Minimal non-solution edit: append shell/Python/Markdown comments carrying the
  verdict-last, unique-marker, quoted-marker, and NUL tokens to the wrapper,
  both providers, the bundle template, and the install notes, without changing
  the live parser paths or focused tests.
- Route: `a`
- Expected result: `a05` and `a06` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; `a01`-`a03`, `a05`, `a06`, and
  `a09`-`a12` failed, `RUN p03 negprobe exit=1 dur=80s`, no `DIRTY-TREE`;
  log: `experiments/ev-005/tools/validate-logs/negprobe/p03.log`.
- Rationale: comment stuffing can satisfy the surface grep needles, but it
  cannot make either focused verifier test suite pass.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/p03.log`.
- `a07` is constant-true (PASS on all five pre runs): it is an invariance guard
  for the unchanged verify-job integration, not evidence of the parser delta.
- `a08` is constant-true (PASS on all five pre runs): it is an invariance guard
  for the unchanged wrapper-conformance integration, not evidence of the
  parser delta.
- All delta-bearing assertions (`a01`-`a06` and `a09`-`a12`) FAIL on every pre
  run and PASS on every fix run.

## Setup accounting (REV6 r5-3)

- Every command assertion creates its own isolated `HOME` and `TMPDIR`. A
  temporary-directory failure is local to that assertion, which emits FAIL;
  the remaining assertions still run and every CHECK ID is emitted once.
