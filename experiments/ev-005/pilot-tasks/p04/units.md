# p04 units ledger

Units: 6 total; covered 6/6
MECH: 6
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The provider accepts a configurable base, keeps the Anthropic default, and joins `/v1/messages`. | `a01` (T5 offline provider probe through the bundled opener stub: default Anthropic request plus exact-base and one-trailing-slash alternate-base requests). |
| U2 | MECH | Invalid bases fail closed before I/O, reject whitespace/control characters, and base joining normalizes a trailing slash. | `a01` covers trailing-slash normalization; `a02` (T5 offline provider probe) covers HTTPS-only and embedded-space/tab rejection with the stable `provider API base is invalid` diagnostic and no verdict output. |
| U3 | MECH | The provider keeps the existing Anthropic wire-format behavior while adding a preferred generic key variable and retaining the old key as fallback. | `a03` (T5/T6 hybrid: probe both preferred-key precedence and legacy-key fallback, require the existing verdict shape and `x-api-key`, and retain the `anthropic-version`, temperature, and timeout guards); `a06` runs the focused suite that preserves the six-verdict contract. |
| U4 | MECH | The install guide adds the alternate-endpoint note while leaving Anthropic as the default path. | `a04` (T1 co-presence in `adapters/hermes/INSTALL.md` using public configuration identifiers and short phrases for the default and alternate endpoint blocks). |
| U5 | MECH | The install guide states the re-attest rule for vendor/model/endpoint swaps. | `a05` (T1 co-presence using the short phrases `vendor, model, or endpoint change`, `Re-run the attester`, and `provider configuration`). |
| U6 | MECH | The focused example verifier regression suite covers and passes the base-parameterization cases without regressing prior contract checks. | `a06` (T3/T6: require stable case identifiers for default base, alternate base, trailing-slash normalization, and invalid-base rejection, run `bash tests/hermes-verifier-examples.test.sh`, and require its aggregate zero-failure summary without pinning individual prose labels). |

## Anonymization and needle record

- Mapping: the source repository remains “this repository”; issue, PR, commit,
  review-seat, and date provenance are removed from the task sheet. Public
  configuration names and repository-relative paths remain visible because the
  source criterion depends on them.
- Criterion-constitutive identifiers retained: `VERIFIER_API_BASE`,
  `ANTHROPIC_API_KEY`, `VERIFIER_MODEL`, and `provider_version`. These are
  public knobs or emitted labels, not hidden provenance.
- Longest T1 needle:
  `VERIFIER_API_BASE=https://api.z.ai/api/anthropic` (49 characters). It is a
  criterion-constitutive configuration line, not historical prose; all prose
  needles are short phrases of four words or fewer.
- Timeout remains the default 120 seconds. The T5 probes are offline, stubbed,
  and bounded to the provider entrypoint; the single T3 suite is the focused
  repository example test named by the source contract rather than a broad
  project-wide run.

## Negative validity probe (r5-1)

- Minimal non-solution edit: append visible pass-label echoes for `[11]`–`[15]`
  to `tests/hermes-verifier-examples.test.sh` and paste the alternate-endpoint
  prose into `adapters/hermes/INSTALL.md`, while leaving
  `adapters/hermes/examples/verifier-provider.py` unchanged.
- Route: `a`
- Expected result: `a01`, `a02`, and `a03` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; `a01`, `a02`, `a03`, and `a06`
  failed, `RUN p04 negprobe exit=1 dur=0s`, no `DIRTY-TREE`; log:
  `experiments/ev-005/tools/validate-logs/negprobe/p04.log`.
- Rationale: copied labels and docs can satisfy the surface suite/doc text, but
  they do not change the live provider behavior that the direct offline probes
  exercise.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/p04.log` shows no
  constant-true assertions; all six assertions FAIL on every pre run and PASS
  on every fix run.

## Setup accounting (REV6 r5-3)

- Each assertion creates its own isolated `HOME` and `TMPDIR`. Missing fixture,
  temporary-directory, or interpreter setup makes the dependent assertion FAIL;
  subsequent assertions still run and every CHECK ID is emitted exactly once.
