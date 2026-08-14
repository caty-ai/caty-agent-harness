# Task t24

## Goal

Bring the family map's four public READMEs into line with the module registry,
and add a fail-closed publication gate that prevents private context, unlabeled
module links, and unsupported visual state claims from reaching publication.

## Done when

- [ ] U1. `README.md` presents `caty-ai/self-growth-loop` as `published` under
  the `MIT` license, consistently with `registry/modules.json`.
- [ ] U2. `README.ja.md` presents the same registry-consistent state.
- [ ] U3. `README.zh.md` presents the same registry-consistent state.
- [ ] U4. `README.th.md` presents the same registry-consistent state.
- [ ] U5. The link-check workflow no longer excludes
  `shojikumaru/self-growth-loop`.
- [ ] U6. The link-check workflow no longer excludes
  `shojikumaru/family-memory-architecture`.
- [ ] U7. The workflow continues to exclude
  `shojikumaru/persona-growth-loop` while that module is preparing.
- [ ] U8. `registry/modules.json` records `shojikumaru/self-growth-loop` as a
  retired repository.
- [ ] U9. `README.md` renders the preparing persona-growth module as plain text
  with its visibility label, rather than as a repository link.
- [ ] U10. `README.ja.md` does the same.
- [ ] U11. `README.zh.md` does the same.
- [ ] U12. `README.th.md` does the same.
- [ ] U13. The publication gate rejects personal-name patterns.
- [ ] U14. The publication gate rejects approval-record patterns.
- [ ] U15. The publication gate rejects absolute personal home paths.
- [ ] U16. The publication gate rejects internal host addresses.
- [ ] U17. The publication gate rejects personal email addresses.
- [ ] U18. The publication gate rejects `github.com/shojikumaru/*` Markdown
  links not authorized by the registry's module, retired-repository, or
  preparing-module declarations.
- [ ] U19. Changes to that personal-repository allowlist require owner approval.
- [ ] U20. The publication gate rejects module home links without the matching
  visibility label, except for exact row-level whitelist entries.
- [ ] U21. The publication gate scans visible and metadata text in
  `assets/**/*.svg` for unsupported module-state claims.
- [ ] U22. The publication scan covers `.md`, `.json`, `.py`, `.yml`, `.yaml`,
  `.svg`, and `.sh` files.
- [ ] U23. Pull-request CI runs the publication gate and its negative-fixture
  self-test as a required dependency of the workflow's failure report.
- [ ] U24. Existing external links receive a one-time human inspection of
  destination content, comments, and attachments, with the inspected list
  recorded.
- [ ] U25. Published images receive a one-time human inspection for EXIF/XMP
  metadata.
- [ ] U26. `python3 -B tools/render.py --check` passes.
- [ ] U27. The publication gate passes on the repository and rejects bundled
  negative behavior probes for every new policy family.

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
