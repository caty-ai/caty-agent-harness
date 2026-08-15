# Task t08

## Goal

Finish the public rename across user-facing install documentation, hook-facing
reminder copy, and template examples while preserving the frozen compatibility
identifiers that still require the older prefix.

## Done when

- [ ] U1. `adapters/claude-code/INSTALL.md` uses the public product name in the
  stop-hook description.
- [ ] U2. `adapters/claude-code/INSTALL.md` uses the public product name in the
  precompact-hook description.
- [ ] U3. `adapters/claude-code/checkpoint-stop-hook.sh` uses the public product
  name in the banner line.
- [ ] U4. `adapters/claude-code/checkpoint-stop-hook.sh` uses the public
  product name in the workspace comment line.
- [ ] U5. `adapters/claude-code/checkpoint-stop-hook.sh` uses the public guard
  directory prefix.
- [ ] U6. `adapters/claude-code/checkpoint-stop-hook.sh` uses the public
  CHECKPOINT prefix in the reminder message.
- [ ] U7. `adapters/claude-code/precompact-flush-hook.sh` uses the public
  product name in the banner line.
- [ ] U8. `adapters/claude-code/precompact-flush-hook.sh` uses the public guard
  directory prefix.
- [ ] U9. `adapters/claude-code/precompact-flush-hook.sh` uses the public
  product name in the extractor prompt.
- [ ] U10. `adapters/codex/INSTALL.md` uses the public product name in the
  introductory paragraph.
- [ ] U11. `adapters/codex/INSTALL.md` uses the public product name in the
  stop-hook description.
- [ ] U12. `adapters/codex/checkpoint-stop-hook.sh` uses the public product
  name in the banner line.
- [ ] U13. `adapters/codex/checkpoint-stop-hook.sh` uses the public product
  name in the workspace comment line.
- [ ] U14. `adapters/codex/checkpoint-stop-hook.sh` uses the public guard
  directory prefix.
- [ ] U15. `adapters/codex/checkpoint-stop-hook.sh` uses the public CHECKPOINT
  prefix in the reminder message.
- [ ] U16. `adapters/kimi/INSTALL.md` uses the public product name in the
  introductory paragraph.
- [ ] U17. `adapters/kimi/INSTALL.md` uses the public product name in the
  stop-hook description.
- [ ] U18. `adapters/kimi/checkpoint-stop-hook.sh` uses the public product name
  in the banner line.
- [ ] U19. `adapters/kimi/checkpoint-stop-hook.sh` uses the public product name
  in the workspace comment line.
- [ ] U20. `adapters/kimi/checkpoint-stop-hook.sh` uses the public guard
  directory prefix.
- [ ] U21. `adapters/kimi/checkpoint-stop-hook.sh` uses the public CHECKPOINT
  prefix in the reminder message.
- [ ] U22. `docs/plugin-convention.md` uses the public product name.
- [ ] U23. `templates/cron-wrapper.tmpl.sh` uses the public target-path
  example.
- [ ] U24. `templates/launchd.tmpl.plist` uses the public product name in the
  banner comment.
- [ ] U25. `templates/launchd.tmpl.plist` uses the public label example.
- [ ] U26. `templates/launchd.tmpl.plist` uses the public target-path example.
- [ ] U27. `templates/updater-cron.tmpl.sh` uses the public product name in the
  banner comment.
- [ ] U28. `templates/updater-cron.tmpl.sh` uses the public repository-path
  example.
- [ ] U29. `tests/pause-contract.test.sh` expects the public CHECKPOINT prefix
  in the enabled-hook stderr assertion.
- [ ] U30. `tests/pause-contract.test.sh` expects the public CHECKPOINT prefix
  in the JSON block assertion.
- [ ] U31. `tests/pause-contract.test.sh` expects the public CHECKPOINT prefix
  in the multiworkspace stderr assertion.
- [ ] U32. `templates/cron-wrapper.tmpl.sh` keeps the frozen cron-wrapper marker
  with the older prefix.
- [ ] U33. `install.sh` keeps the frozen bootstrap marker with the older prefix.
- [ ] U34. `adapters/openclaw/sentinel-cron.sh` keeps the frozen sentinel-notice
  marker with the older prefix.
- [ ] U35. The `fable-wrapper-conformance/v1` contract schema identifier stays
  verbatim in its contract and implementations.
- [ ] U36. The `FABLE_CONFORMING_PROVIDER_PATH` contract environment variable
  stays verbatim in its contract, adapter documentation, implementations, and
  contract test.
- [ ] U37. The `FABLE_WRAPPER_ROUTE` contract environment variable stays
  verbatim.
- [ ] U38. The `FABLE_WRAPPER_PATH` contract environment variable stays
  verbatim.
- [ ] U39. The `FABLE_ATTEST_SCRATCH_DIR` contract environment variable stays
  verbatim.

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
