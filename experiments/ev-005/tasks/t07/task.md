# Task t07

## Goal

Retire a pre-publication working name from the repository's public prose,
historical tracker references, and cosmetic temporary-file prefixes while
preserving the frozen compatibility identifiers and nominative model mentions
that are explicitly allowed to remain.

## Done when

- [ ] U1. `DESIGN.md` uses the public product name in its title.
- [ ] U2. `DESIGN-task-runner.md` uses the public product name in the companion
  note that names `DESIGN.md`.
- [ ] U3. `DESIGN-task-runner.md` uses the public product name in the loop
  description sentence.
- [ ] U4. `DESIGN-task-runner.md` uses the public product name in the
  verification-promotion sentence.
- [ ] U5. `SYNTHESIS.md` uses the public product name in its title.
- [ ] U6. `SYNTHESIS.md` uses the public product name in the namespace note.
- [ ] U7. `SYNTHESIS-task-runner.md` uses the public product name in the
  verification-promotion sentence.
- [ ] U8. `SYNTHESIS-task-runner.md` uses the public product name in the verify
  retry wording.
- [ ] U9. `docs/governance-rules.md` rewrites the historical-source prose line
  as a neutral pre-publication private-tracker reference.
- [ ] U10. `docs/governance-rules.md` rewrites the synthesis-scope table row
  with the public product name.
- [ ] U11. `docs/governance-rules.md` rewrites the `v1.0 source` table row as a
  neutral pre-publication private-tracker reference.
- [ ] U12. `docs/governance-rules.md` rewrites the `Amendment issue` table row
  as a neutral pre-publication private-tracker reference.
- [ ] U13. `docs/updater-rollout.md` rewrites the source-of-truth line as a
  neutral pre-publication private-tracker reference.
- [ ] U14. `docs/updater-rollout.md` rewrites the path-correction note as a
  neutral pre-publication private-tracker reference.
- [ ] U15. `scripts/lib-wrapper-conformance.sh` uses the public temporary-stage
  prefix `caty-wrapper-stage`.
- [ ] U16. `scripts/attest-wrapper` uses the public attest scratch-directory
  prefix `caty-attest-wrapper`.
- [ ] U17. `scripts/attest-wrapper` uses the public attest stdout temporary-file
  prefix `caty-attest-wrapper.stdout`.
- [ ] U18. `scripts/attest-wrapper` uses the public attest stderr temporary-file
  prefix `caty-attest-wrapper.stderr`.
- [ ] U19. No case-insensitive `fable` occurrence remains outside lines that
  contain a frozen compatibility identifier or a nominative model mention.
- [ ] U20. The full repository test suite is green on the branch-equivalent
  tree.
- [ ] U21. Repository lint is green on the branch-equivalent tree.
- [ ] U22. The full repository test suite is green on the merged-mainline tree.
- [ ] U23. Repository lint is green on the merged-mainline tree.
- [ ] U24. A new tag is published after merge for this cleanup.
- [ ] U25. A release is published after merge for this cleanup.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `1800 s` per `donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
