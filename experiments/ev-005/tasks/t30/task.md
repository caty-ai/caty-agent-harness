# Task t30

## Goal

Install the repository's first local CI gate set and wire its test/lint gate to
the real shell test suite and a tracked-shell syntax sweep.

## Done when

- [ ] U1. The risk-reviewer roster change is merged before the workflow change.
- [ ] U2. The workflow and Makefile change is merged.
- [ ] U3. `Makefile` and these five pull-request workflow definitions exist:
  `.github/workflows/test-lint.yml`, `.github/workflows/gitleaks.yml`,
  `.github/workflows/pr-size.yml`, `.github/workflows/history-check.yml`, and
  `.github/workflows/review-labels.yml`.
- [ ] U4. `make test` runs the repository's complete `tests/*.test.sh` shell
  suite and passes.
- [ ] U5. `make lint` syntax-checks every tracked `*.sh` file with Bash and
  passes.
- [ ] U6. The three repository labels used by the review workflows exist on the
  hosting platform.
- [ ] U7. The required checks named `test`, `lint`, `gitleaks`,
  `history-check`, and `risk-review-gate` are registered on the main branch and
  an external required-check audit passes; `pr-size` remains advisory.
- [ ] U8. One unmerged verification change exercises every gate's red/green
  behavior, a complete risk-label invalidation/reapproval cycle, an oversized
  change rejection, and the merge-blocked state.
- [ ] U9. Any reusable learning is filed upstream; otherwise a no-learning
  record exists.
- [ ] U10. The parent rollout checklist links to this completed deployment.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `{{BUDGET}}`
- Per-run timeout: `1800 s`
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
