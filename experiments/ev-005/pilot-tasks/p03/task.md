# Task p03

## Goal

Reconcile the example verifier contract structurally: make the wrapper and both
example providers accept the bundle-compliant verdict-last reply shape without
weakening fail-closed behavior, keep verdict-first replies valid, preserve the
wrapper exit-code table, and reject ambiguous or NUL-bearing replies.

## Done when

- [ ] U1. The CLI verifier provider uses the verdict-last unique-marker prompt
  contract and a position-free verdict parser while keeping the provider →
  wrapper interface as exactly two normalized lines.
- [ ] U2. The Python verifier provider uses the same verdict-last unique-marker
  prompt contract and position-free parser.
- [ ] U3. The wrapper accepts exactly one anchored allowed verdict anywhere in
  provider output, uses the first following non-empty line as the reason, and
  keeps exit codes `64`/`65`/`69`/`70` unchanged.
- [ ] U4. The bundled verifier template and operator-facing install notes
  describe the position-free unique-marker contract instead of the old
  first-line rule.
- [ ] U5. The CLI verifier path accepts the production-shaped verdict-last
  reply shape.
- [ ] U6. The example wrapper/provider path accepts the production-shaped
  verdict-last reply shape.
- [ ] U7. Verdict-first replies are still accepted under the new position-free
  parser.
- [ ] U8. Malformed replies fail closed on the CLI verifier path: zero verdict,
  duplicated verdict, smuggled extra `VERDICT:`, missing reason, and malformed
  anchors are all rejected.
- [ ] U9. Malformed replies fail closed on the example wrapper/provider path:
  zero verdict, duplicated verdict, smuggled extra `VERDICT:`, missing reason,
  malformed anchors, and inert bundle text that only mentions verdict markers
  do not manufacture a pass.
- [ ] U10. Any NUL byte in reply output is rejected fail-closed across the
  wrapper, the CLI verifier provider, and the Python verifier provider.
- [ ] U11. The broader verifier integrations still pass with the unchanged
  wrapper contract.
- [ ] U12. No touched example or install surface still describes the old
  `FIRST line` contract.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `180 s` per `.ev005-donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `.ev005-donecheck.sh` ships with this task at the repository root; it is
  readable and executable.
