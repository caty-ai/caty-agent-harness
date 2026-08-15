# Task t05

## Goal

Generalize the bundled example task and the surrounding installer/template
wording so the shipped example is local and generic, operator-specific paths
become placeholders with setup guidance, and the verification note matches
what the probe actually inspects.

## Done when

- [ ] U1. `templates/examples/img-pilot.task.md` uses a local SVG artifact path.
- [ ] U2. `templates/examples/img-pilot.task.md` checks for an SVG root element.
- [ ] U3. `templates/examples/img-pilot.task.md` declares the SVG artifact path
  in the receipt payload.
- [ ] U4. `templates/examples/img-pilot.task.md` lists `bash` as a resource.
- [ ] U5. `templates/examples/img-pilot.task.md` lists `python3` standard
  library as a resource.
- [ ] U6. `templates/examples/img-pilot.task.md` no longer uses the old backend
  dependency name.
- [ ] U7. `templates/examples/img-pilot.task.md` no longer uses the old push
  channel dependency name.
- [ ] U8. `templates/examples/img-pilot.task.md` no longer uses the old PNG
  artifact path.
- [ ] U9. `templates/examples/img-pilot.task.md` no longer mentions the old
  scoring step.
- [ ] U10. `adapters/codex/INSTALL.md` uses a placeholder operator-charter path.
- [ ] U11. `adapters/codex/INSTALL.md` includes setup guidance for that
  placeholder path.
- [ ] U12. `adapters/kimi/INSTALL.md` uses a placeholder operator-charter path.
- [ ] U13. `adapters/kimi/INSTALL.md` includes setup guidance for that
  placeholder path.
- [ ] U14. `adapters/hermes/INSTALL.md` uses a placeholder secrets path in the
  cron example.
- [ ] U15. `adapters/hermes/INSTALL.md` uses a placeholder workspace path in the
  cron example.
- [ ] U16. `templates/TASK.tmpl.md` uses the generic `issued_by` value.
- [ ] U17. `templates/TASK.tmpl.md` uses the generic `escalate_to` value.
- [ ] U18. `templates/TASK.tmpl.md` no longer uses the old `issued_by` value.
- [ ] U19. `templates/TASK.tmpl.md` no longer uses the old `escalate_to` value.
- [ ] U20. `templates/examples/img-pilot.task.md` uses the generic `issued_by`
  value.
- [ ] U21. `templates/examples/img-pilot.task.md` uses the generic `escalate_to`
  value.
- [ ] U22. `templates/examples/img-pilot.task.md` no longer uses the old
  `issued_by` value.
- [ ] U23. `templates/examples/img-pilot.task.md` no longer uses the old
  `escalate_to` value.
- [ ] U24. `scripts/family-updater` removes the implicit default reporter path.
- [ ] U25. `scripts/family-updater` warns that reporting is disabled when the
  reporter path is omitted.
- [ ] U26. `scripts/family-updater` documents the explicit override flag or env
  var for the reporter path.
- [ ] U27. `scripts/family-updater` no longer embeds the old private default
  reporter path.
- [ ] U28. `templates/updater-cron.tmpl.sh` requires an explicit reporter-path
  setting.
- [ ] U29. `templates/updater-cron.tmpl.sh` contains a placeholder reporter path.
- [ ] U30. `templates/updater-cron.tmpl.sh` no longer uses the old
  `HOME`-based failure text.
- [ ] U31. `templates/updater-cron.tmpl.sh` no longer derives the reporter path
  from `HOME`.
- [ ] U32. `install.sh` uses generic remote-home wording.
- [ ] U33. `install.sh` no longer uses the old person-specific remote-home
  wording.
- [ ] U34. `install.sh` says the probe inspects configured adapter paths.
- [ ] U35. `install.sh` says the probe also reads env-supplied external paths.
- [ ] U36. `install.sh` says the probe does not mutate the checked workspace.
- [ ] U37. `install.sh` no longer uses the old installer-local inspection
  wording.
- [ ] U38. `scripts/lib-wrapper-conformance.sh` remains unchanged.
- [ ] U39. `tests/wrapper-conformance.test.sh` expectations remain unchanged.

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
