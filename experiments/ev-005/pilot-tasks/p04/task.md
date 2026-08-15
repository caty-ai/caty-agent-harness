# Task p04

## Goal

Make the existing example verifier provider deployable against a compatible
alternate HTTPS endpoint with the smallest faithful change, keep the
Anthropic-wire-format contract intact, and align the operator documentation and
focused regression coverage with that endpoint swap.

## Done when

- [ ] U1. The provider accepts `VERIFIER_API_BASE`, defaults to
  `https://api.anthropic.com`, and sends requests to `<base>/v1/messages`.
- [ ] U2. Invalid `VERIFIER_API_BASE` values fail closed before request I/O:
  they must be HTTPS-only, reject whitespace/control characters, and normalize
  one trailing slash.
- [ ] U3. The provider keeps the existing Anthropic wire contract unchanged:
  `VERIFIER_API_KEY` supplies `x-api-key`, `ANTHROPIC_API_KEY` remains a
  backward-compatible fallback, and `anthropic-version`, the six-verdict
  first-line contract, temperature guard, and timeout guard remain intact.
- [ ] U4. The install guide adds the alternate-endpoint configuration note while
  keeping Anthropic as the default path.
- [ ] U5. The install guide states that vendor, model, and endpoint swaps
  require re-attestation because they are configuration changes rather than
  attested byte changes.
- [ ] U6. The focused example verifier suite passes with stubbed coverage for
  the default endpoint, alternate endpoint, trailing-slash normalization, and
  invalid-base fail-closed behavior.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `120 s` per `donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
