# Task p05

## Goal

Generalize the delegation-brief validator into a public, fail-open
`PreToolUse` hook for substantial `Agent` and `Task` delegations, matching the
repository's existing hook/doc/test conventions.

## Done when

- [ ] U1. The repository ships a `PreToolUse` brief-validator launcher and body
  for `Agent` and `Task`, with the canonical three required section tokens and
  the documented `CK_*` configuration surface.
- [ ] U2. A substantial incomplete prompt exits `2` with an English corrective
  message that names the missing tokens, prints a minimal skeleton from the
  active heading set, links to the public rulebook, and explains the
  launcher-environment bypass.
- [ ] U3. A compliant canonical prompt passes silently.
- [ ] U4. Validation triggers at `500` characters by default, skips shorter
  prompts and the documented lightweight subagent types, accepts `Task`, passes
  non-`Agent`/`Task` tools through, and exact matching means `writer2` does not
  inherit `writer`'s default skip.
- [ ] U5. `CK_BRIEF_REQUIRED_SECTIONS`, `CK_BRIEF_SKIP_SUBAGENT_TYPES`, and
  `CK_BRIEF_MIN_PROMPT_CHARS` are honored with the documented
  fallback/override behavior, and malformed inputs fail open.
- [ ] U6. The shell launcher fails open when its body or interpreter is
  unavailable, the guarded placeholder wiring exits `0` silently, and a genuine
  block still surfaces even if unrelated stderr noise appears before the
  validator sentinel.
- [ ] U7. The public docs and example settings document the guarded
  `PreToolUse` wiring, local verification path, plain-substring heading match,
  and the four public env vars.
- [ ] U8. The repository regression suite, shell syntax, Python AST parse, JSON
  parse, and residue scan for the new public surface all pass.

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
