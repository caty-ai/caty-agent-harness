# Task t21

## Goal

Align this repository's skill lint, staging template, and design contract for
verified-skill metadata while preserving the lint's advisory exit semantics.

## Done when

- [ ] U1. The design contract defines the six fields required for a verified
  skill: `name`, `description`, `trigger`, `status`, `verified_at`, and
  `verifier_id`, while drafts may omit the two verification fields.
- [ ] U2. The staging skill template carries the draft fields and explains
  that `verified_at` and `verifier_id` are added when a skill is promoted.
- [ ] U3. A `status: verified` skill that omits `verified_at` and
  `verifier_id` produces a skill-lint warning for each missing field.
- [ ] U4. Draft skills may omit those verification fields, and verified skills
  that provide them do not receive missing-verification-field warnings.
- [ ] U5. These skill-lint warnings are advisory: adding the invalid verified
  skill does not change the exit status of `install.sh --check`.
- [ ] U6. A targeted regression test covers the conditional verification-field
  warnings and the unchanged `--check` exit status.

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
