# Task t06

## Goal

Purge private-era publication-transition wording from public install and
policy-facing Markdown, keep troubleshooting self-contained and evidence-shaped,
preserve older tracker context only behind explicit historical labels where the
source permits it, and express the remaining release-model exceptions through an
exact-line allowlist-backed repo-wide sweep.

## Done when

- [ ] U1. `docs/agent-guide.md` states that the repository is public, says no
  invitation is needed, and no longer guesses that clone reachability failures
  are caused by missing private access.
- [ ] U2. `docs/agent-guide.md` no longer contains the transitional
  forthcoming-home note.
- [ ] U3. `adapters/hermes/INSTALL.md` uses the public clone flow and no longer
  instructs invite-or-deploy-key access.
- [ ] U4. `adapters/openclaw/INSTALL.md` uses the public clone flow and no
  longer instructs invite-or-deploy-key access.
- [ ] U5. `adapters/claude-code/INSTALL.md` gives a self-contained macOS
  scheduling explanation instead of an old numbered citation.
- [ ] U6. `adapters/claude-code/INSTALL.md` gives a self-contained hook-isolation
  explanation instead of an old numbered citation.
- [ ] U7. `DESIGN.md`, `DESIGN-task-runner.md`,
  `docs/governance-rules.md`, and `docs/updater-rollout.md` are explicitly
  marked as historical design records before preserving older tracker context,
  while `docs/plugin-convention.md` remains part of the repo-wide public/policy
  sweep.
- [ ] U8. `docs/updater-rollout.md` satisfies the source disjunction for the
  deployment inventory: it is genericized by placeholder-like shape, or it is
  explicitly labeled as a dated internal or historical record.
- [ ] U9. `fixtures/release-model-allowlist.tsv` exists and records the only
  four exact release-model exception lines: the English and Japanese
  scope-boundary statements, and the English and Japanese
  public-release/private-development status statements.
- [ ] U10. A repo-wide grep over tracked user-facing Markdown finds no
  private-access wording outside the recorded allowlist.
- [ ] U11. The same repo-wide sweep finds no invite-or-deploy-key onboarding
  wording outside the recorded allowlist.
- [ ] U12. The same repo-wide sweep finds no private-tracker framing or
  forthcoming-home note outside the recorded allowlist, and
  `docs/agent-guide.md` troubleshooting is keyed to concrete observed strings
  instead of the guessed clone-auth/private-access row.

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
