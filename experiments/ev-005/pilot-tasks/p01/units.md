# p01 units ledger

Units: 13 total; covered 13/13
MECH: 13
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The intake core is extracted to `scripts/flush-intake.sh`, and both adapter entry scripts stay guarded, canonicalize the workspace, derive adapter identity, and source the core only after the pause guard. | `a01` (T6 structural: verify the shared core guard, the one-level `repo_root` resolution inside `scripts/flush-intake.sh`, the two-level adapter `repo_root` resolution, the guarded-entry sentinel, and the ordered pause-guard handoff in both adapter entry scripts). |
| U2 | MECH | Pause-status output and lock caller share the adapter-derived `<adapter>-flush-intake` identity. | `a02` (T5 behavior probe plus T1/T6 structural binding: run both entry points on paused workspaces to require exact `claude-code-flush-intake` / `hermes-flush-intake` status lines and zero mutation, and require the shared core to pass `adapter_identity` into `take_state_lock`). |
| U3 | MECH | The claude-code intake entry remains the load-bearing scheduler target with the same one-argument / paused-exit contract and exact cron-wrapper self-mark path. | `a03` (T6 structural: require the cron wrapper's exact self-mark target to stay `adapters/claude-code/flush-intake.sh`, and require `install.sh` to probe the shared core through the claude-code entry instead of hollowing the entry into a dead shim). |
| U4 | MECH | The Hermes bootstrap block stays at `v2`, and both flush-facing texts encode the Lessons-only/Open-failures/persona/no-self-fold rules. | `a04` (T1 content-presence: require the `v2` bootstrap sentinel plus short, criterion-derived identifiers for FLUSH, Lessons-only, Open failures, the persona guard, and the no-self-fold rule in the Hermes bootstrap and claude-code stop-hook text). |
| U5 | MECH | The shared core strips control characters before parsing, drops oversize bullets at `INTAKE_MAX_BULLET_BYTES`, and surfaces `dropped_oversize`. | `a05` (T5 behavior probe: create isolated loop workspaces, exercise oversize-bullet dropping and control-character dedup, and require the sanitized STATE fold plus the `dropped_oversize`/`deduped` receipt fields). |
| U6 | MECH | STATE-cap evictions are archived and surfaced in receipts. | `a06` (T5 behavior probe: seed a cap-full STATE, run intake, and require `evicted_by_cap=1`, `eviction_archive=loop/archive/intake-evictions-<UTC-date>.md`, the archived oldest lesson, and a preserved cap count). |
| U7 | MECH | The example verifier provider uses env-held credentials, a single stateless request, an unguessable delimiter, and configurable model selection. | `a07` (T6 structural: require `ANTHROPIC_API_KEY` from environment, `VERIFIER_MODEL`, `VERIFIER_HTTP_TIMEOUT_S`, `VERIFIER_TEMPERATURE`, the Anthropic Messages endpoint, `secrets.token_hex`, and the first-line-verdict system-prompt rule in `adapters/hermes/examples/verifier-provider.py`); `a12` and `a13` execute the focused and full behavioral suites that cover the single-call provider path. |
| U8 | MECH | The example verifier wrapper takes `argv[1]`, enforces a byte floor, launches exactly `FABLE_CONFORMING_PROVIDER_PATH`, and rejects malformed or repeated verdict lines. | `a08` (T5 behavior probe: exercise the wrapper with staged fake providers to require empty/short-bundle failure, exact `argv[1]` forwarding, two-line success forwarding, repeated-verdict rejection, and provider relocation through the probe script). |
| U9 | MECH | The example verifier probe genuinely exercises the wrapper/provider path instead of echoing a constant verdict. | `a08` (same T5 probe: require the probe to copy the provider, launch the wrapper against the relocated path, and emit `provider_relocatable=pass` after the fake provider receives the real bundle). |
| U10 | MECH | The activation manifest registers the shared intake core, both adapter entries, and the Hermes example files with the correct guarded/exempt classes. | `a09` (T6 structural TSV parse of `scripts/activation-manifest.tsv`). |
| U11 | MECH | Hermes install docs explain the flush-intake LaunchAgent wiring, `INTAKE_MAX_FOLD=5`, and the need to leave `DEADMAN_MARKER` unset for Hermes. | `a10` (T1 content-presence: require the dedicated `## Flush intake consumer` section, the environment block, `StartInterval` `28800`, and the explicit `DEADMAN_MARKER` unset guidance). |
| U12 | MECH | Repository tests include substantive Hermes coverage for the shared intake entry path and the verifier examples. | `a11`, `a12` (T1 content-presence: require the dedicated Hermes intake coverage file plus the paused/core/self-mark/full-suite passthrough coverage needles, and require the dedicated verifier-example coverage file plus the fake-provider, timeout, temperature, and relocation coverage needles). |
| U13 | MECH | The full repository shell test suite passes. | `a13` (T3 command-exit: run every `tests/*.test.sh` script under a fresh `HOME` and `TMPDIR`, exactly as required by the source criterion). |

## Anonymization and needle record

- Mapping: tracker IDs, dates, design-section references, owner/persona references,
  and issue provenance are removed. Repository paths, adapter names, environment
  variables, and public script names remain because the replica contains them and
  the source criterion names them directly.
- Criterion-constitutive identifiers retained verbatim: `claude-code`,
  `Hermes`, `scripts/flush-intake.sh`, `FABLE_CONFORMING_PROVIDER_PATH`,
  `VERIFIER_MODEL`, `INTAKE_MAX_FOLD`, `DEADMAN_MARKER`, and `tests/*.test.sh`.
- Longest prose-like T1 needle: `Never fold flush entries into` (29 characters),
  a short criterion-derived phrase for the no-self-fold rule. Longer checks are
  stable paths, environment-variable names, or structural identifiers already
  present in the replica.
- Timeout is `1800` seconds. The source criterion explicitly requires the full
  `tests/*.test.sh` suite, so this task keeps a generous whole-script timeout
  separate from the attempt budget instead of weakening the suite check.

## Negative validity probe (r5-1)

- Minimal non-solution edit: On the pre-fix tree, add token-only or no-op stubs for
  `scripts/flush-intake.sh`, `adapters/hermes/flush-intake.sh`,
  `adapters/hermes/examples/*`, the Hermes install/bootstrap text, the manifest
  rows, and the two Hermes test files, without implementing the shared intake
  behavior or the wrapper/provider/probe contract.
- Route: `a`
- Expected result: `a01`, `a02`, `a03`, `a05`, `a06`, and `a08` should still FAIL.
- Evidence status: `PENDING`
- Rationale: Surface-text stubs can satisfy names and prose, but they cannot make
  the guarded-entry fold, hardening behavior, wrapper/provider relocation probe,
  or full suite succeed.

## Constant-true declaration (r5-2)

- Source log: pending first validation run.

## Setup accounting (REV6 r5-3)

- Temporary-root creation is non-fatal at script scope. If it fails, every
  assertion is still invoked exactly once; checks that require an isolated
  workspace report their own FAIL, while independent static checks still run.
