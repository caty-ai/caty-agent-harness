# Task t18

## Goal

Add `context-kit` to the family map's vertical axis as a non-foundation desk-
equipment module, while keeping the registry-generated content and all four
localized README views synchronized.

## Done when

- [ ] U1. `registry/modules.json` contains exactly one `context-kit` entry.
- [ ] U2. The entry belongs to the vertical axis.
- [ ] U3. The entry is not a foundation module.
- [ ] U4. The entry remains in `preparing` status until the public flip.
- [ ] U5. `tools/render.py --check` passes for the committed generated blocks.
- [ ] U6. `tools/check_registry.py` passes in the offline task environment.
- [ ] U7. The vertical layer-table row in `README.md` mentions `context-kit`.
- [ ] U8. The vertical layer-table row in `README.ja.md` mentions
  `context-kit`.
- [ ] U9. The vertical layer-table row in `README.zh.md` mentions
  `context-kit`.
- [ ] U10. The vertical layer-table row in `README.th.md` mentions
  `context-kit`.
- [ ] U11. The vertical section in `README.md` has a desk-equipment category
  with a `context-kit` bullet.
- [ ] U12. The vertical section in `README.ja.md` has the corresponding
  localized equipment category and `context-kit` bullet.
- [ ] U13. The vertical section in `README.zh.md` has the corresponding
  localized equipment category and `context-kit` bullet.
- [ ] U14. The vertical section in `README.th.md` has the corresponding
  localized equipment category and `context-kit` bullet.
- [ ] U15. The owner decides when the external module has flipped public.
- [ ] U16. After that public flip, a follow-up changes the registry status and
  localized README labels from preparing to published.

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
