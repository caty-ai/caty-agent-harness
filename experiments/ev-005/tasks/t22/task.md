# Task t22

## Goal

Turn this workspace-toolkit repository into a reproducible, documented set of
five context-hygiene tools that can be installed without a maintainer's
personal environment.

## Done when

- [ ] U1. Generalized versions of all five tools are included: proactive log
  pruning (`lg`), reactive scratch persistence, three-layer delegation-brief
  validation, the reusable safety-hook set, and multi-layer memory `recall`
  with its relationship to shared memory documented.
- [ ] U2. Personal-environment dependencies—absolute personal paths,
  usernames, private workspace/repository references, and model-specific local
  assumptions—are removed or replaced by environment variables or settings.
- [ ] U3. Setup documentation, including hook wiring through
  `examples/settings.json`, is sufficient to reproduce installation from a
  clean environment.
- [ ] U4. README creation completes the human `brief_locked`,
  `structure_locked`, and `inspection_passed` process gates and follows the
  README standard.
- [ ] U5. The eleven-item publication gate is completed, including four
  language README files, a local hero/thumbnail asset at
  `assets/readme/hero.png`, internal-information cleanup, the MIT license, and
  the three-axis issue-label setup.
- [ ] U6. The repository owner performs the public visibility flip.
- [ ] U7. Until that owner action, the live repository remains private.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `{{BUDGET}}`
- Per-run timeout: `120 s`
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
