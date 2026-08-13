# Task t06

## Goal

Purge pre-publication wording from public-facing documentation, align the
diagnostic and install flow with the public repository, and rewrite
legacy references so public readers get self-contained explanations or clearly
labeled historical context.

## Done when

- [ ] U1. `docs/agent-guide.md` states that the repository is public.
- [ ] U2. `docs/agent-guide.md` states that no invitation is needed.
- [ ] U3. `docs/agent-guide.md` no longer claims that the public home is still
  forthcoming.
- [ ] U4. `adapters/hermes/INSTALL.md` says to clone the public repository.
- [ ] U5. `adapters/hermes/INSTALL.md` includes the public clone command.
- [ ] U6. `adapters/hermes/INSTALL.md` no longer says the repository is private.
- [ ] U7. `adapters/hermes/INSTALL.md` no longer says access is by invitation or
  deploy key.
- [ ] U8. `adapters/openclaw/INSTALL.md` says to clone the public repository.
- [ ] U9. `adapters/openclaw/INSTALL.md` includes the public clone command.
- [ ] U10. `adapters/openclaw/INSTALL.md` no longer says the repository is
  private.
- [ ] U11. `adapters/openclaw/INSTALL.md` no longer says access is by invitation
  or deploy key.
- [ ] U12. `docs/agent-guide.md` no longer tells users that clone auth failures
  mean the repository is private.
- [ ] U13. `adapters/claude-code/INSTALL.md` includes the self-contained macOS
  scheduling explanation.
- [ ] U14. `adapters/claude-code/INSTALL.md` includes the self-contained
  host-hook explanation.
- [ ] U15. `adapters/claude-code/INSTALL.md` no longer cites the old tracker
  number in those explanations.
- [ ] U16. `DESIGN.md` labels itself as a historical design record.
- [ ] U17. `DESIGN.md` says its legacy issue references point to the
  pre-publication private tracker.
- [ ] U18. `DESIGN-task-runner.md` labels itself as a historical design record.
- [ ] U19. `DESIGN-task-runner.md` says its legacy issue references point to the
  pre-publication private tracker.
- [ ] U20. `docs/governance-rules.md` labels itself as a historical design
  record.
- [ ] U21. `docs/governance-rules.md` says its legacy references point to the
  pre-publication private trackers and working repositories.
- [ ] U22. `docs/updater-rollout.md` labels itself as a historical design
  record.
- [ ] U23. `docs/updater-rollout.md` uses the placeholder deployment-inventory
  heading.
- [ ] U24. `docs/updater-rollout.md` uses the placeholder deployment-inventory
  row.
- [ ] U25. `docs/updater-rollout.md` no longer uses the old verified-deployments
  heading.
- [ ] U26. `docs/updater-rollout.md` no longer includes the old concrete
  deployment row.

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
