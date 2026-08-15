# p05 units ledger

Units: 8 total; covered 8/8
MECH: 8
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The repository ships an `Agent`/`Task` brief validator with the canonical three-section contract and documented `CK_*` knobs. | `a01` (T6 structural: require the launcher/body/suite paths, exact `Agent`/`Task` support, the canonical section-token list, and the documented env-var names in the Python body). |
| U2 | MECH | A substantial incomplete prompt is blocked with the corrective contract. | `a02` (T5 behavior probe: run a long incomplete `Agent` payload and require exit `2`, missing-token reporting, skeleton guidance, handbook links, and launcher-environment bypass wording). |
| U3 | MECH | A compliant canonical prompt passes silently. | `a03` (T5 behavior probe: run a long prompt with the three canonical headings and require silent exit `0`). |
| U4 | MECH | Default threshold, default skip semantics, and `Task`/non-`Task` tool routing behave exactly as documented. | `a04` (T5 behavior probe: require `499`-char pass-through, `500`-char blocking, default `writer` skip, exact-match rejection of `writer2`, `Task` acceptance, and non-`Agent`/`Task` pass-through). |
| U5 | MECH | The required-sections, skip-list, and minimum-length environment variables honor the documented override/fallback contract, and malformed inputs fail open. | `a05` (T5 behavior probe: require custom sections to pass, malformed section config to fall back, numeric threshold override to take effect, non-numeric threshold to fall back, skip-list override to replace rather than extend defaults, and malformed stdin/input shapes to exit `0`). |
| U6 | MECH | The shell launcher stays fail-open on missing-body/interpreter paths, the guarded placeholder wiring exits `0`, and shim noise before the sentinel does not suppress a real block. | `a06` (T5 behavior probe: copy the launcher without its body, inject a fake `python3`, run the guarded `<CONTEXT_KIT_DIR>` placeholder command, and inject shim noise before a real blocked run). |
| U7 | MECH | Public docs and example settings describe guarded wiring, local verification, heading-match semantics, and the public env vars, with no personal-residue strings in the new public surface. | `a07` (T6 structural/T4 content-absence: parse `examples/settings.json` for the guarded `Agent|Task` `PreToolUse` wiring, require `docs/brief-validator.md` to name the local verify path, heading-match note, and all env vars, and require absence of personal-residue markers in the new validator files). |
| U8 | MECH | The repository regression suite, shell syntax, Python AST parse, and JSON parse all pass. | `a08` (T3/T6: run `bash tests/test_brief_validator.sh`, `bash -n` on the two scripts, Python AST parse on the body, and `python3 -m json.tool` on `examples/settings.json`, all in an isolated environment). |

## Anonymization and needle record

- Mapping: the source repository is rendered as “this repository”; tracker
  numbers, branch names, people, and dates are omitted from `task.md`.
  Public filenames, env vars, and heading tokens stay visible because they are
  criterion-constitutive identifiers in the landed contract.
- Longest T1/T4 needle: `CK_BRIEF_MIN_PROMPT_CHARS` (25 characters), a public
  configuration knob documented and exercised by the source contract. The other
  content checks are similarly identifier-sized; the behavioral core stays in
  T5 probes rather than full-sentence prose pins.
- Timeout remains the default 120 seconds. The bundled probe runs a handful of
  narrow hook invocations plus one local shell suite; no network, no full repo
  build, and no wall-clock logic are involved.

## Negative validity probe (r5-1)

- Minimal non-solution edit plan: add the documented strings to the public docs
  and example settings, plus a no-op launcher/body pair that always exits `0`
  and never emits the blocking contract or honors the env-driven enforcement
  rules.
- Route: `a`
- Expected result: `a02`, `a04`, `a05`, `a06`, and `a08` should still FAIL;
  the surface strings alone do not recreate the live validator, the guarded
  placeholder behavior, or its regression suite.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; `a01`, `a02`, `a04`, `a05`,
  `a06`, and `a08` failed, `RUN p05 negprobe exit=1 dur=0s`, no
  `DIRTY-TREE`; log:
  `experiments/ev-005/tools/validate-logs/negprobe/p05.log`.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/p05.log` shows no
  constant-true assertions; all eight assertions FAIL on every pre run and PASS
  on every fix run.

## Setup accounting (REV6 r5-3)

- Missing `.ev005-fixtures/p05_probe.sh` is reported independently by `a02`–`a06`;
  `a01`, `a07`, and `a08` still run. Each isolated-command setup failure is
  local to its assertion, and all eight CHECK IDs are emitted exactly once.
