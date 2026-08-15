# Task t04

## Goal

Clarify this repository's T2 isolation documentation by naming the public
collection pipeline behind the prerequisite, without changing the gate
semantics or the related functional strings.

## Done when

- [ ] U1. `docs/trial-isolation.md` names the public collection-pipeline
  repository behind the first T2 prerequisite: `caty-ai/x-collector`.
- [ ] U2. `docs/trial-isolation.md` links that repository
  (`https://github.com/caty-ai/x-collector`).
- [ ] U3. `docs/trial-isolation.md` states that qualifying trials go through
  that pipeline.
- [ ] U4. `docs/trial-isolation.md` states that those trials inherit the
  pipeline's collection controls.
- [ ] U5. The first T2 condition remains that the collection-controls
  prerequisite is closed.
- [ ] U6. The second T2 condition remains explicit owner pre-approval of the
  concrete trial plan.
- [ ] U7. The T2 isolation string in `scripts/trial-enqueue.sh` stays
  unchanged.
- [ ] U8. The T2 row in the normative tier table in
  `docs/adoption-wiring.md` stays unchanged.
- [ ] U9. No other private-reference wording is introduced.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `120 s` per `.ev005-donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `.ev005-donecheck.sh` ships with this task at the repository root; it is
  readable and executable.
