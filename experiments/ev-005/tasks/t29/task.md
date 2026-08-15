# Task t29

## Goal

Replace the map repository's four-stage growth presentation with a five-stage
model whose canonical documents, localized README summaries, and shared figure
separate implemented claims from planned ones and mark the I-to-WE boundary.

## Done when

- [ ] U1. `docs/growth-model.md` and `docs/growth-model.ja.md` exist.
- [ ] U2. Both canonical documents contain an operational five-stage table.
- [ ] U3. Both canonical documents map stages 1–4 to I, stage 5 to WE, and
  inheritance to THEY outside the five stages.
- [ ] U4. Both canonical documents describe Relationship Readiness as a second
  axis.
- [ ] U5. The canonical English and Japanese documents form a complete,
  coherent explanation of the model.
- [ ] U6. The growth section in `README.md` presents five stages.
- [ ] U7. The growth section in `README.ja.md` presents five stages.
- [ ] U8. The growth section in `README.zh.md` presents five stages.
- [ ] U9. The growth section in `README.th.md` presents five stages.
- [ ] U10. In all four README growth sections, stage 3 is presented as
  implemented with its `docs/evidence.md` claim still unverified, while stage 4
  is presented as planned.
- [ ] U11. `assets/readme/growth-stages.svg` exists.
- [ ] U12. The figure is language-independent, uses English stage names with
  minimal visible vocabulary, and remains understandable as a five-stage
  diagram.
- [ ] U13. The figure uses solid styling for implemented stages, dashed styling
  for planned stages, and orange for focus, with a legend saying focus is not a
  state.
- [ ] U14. The figure explicitly marks the I → WE boundary between stages 4
  and 5.
- [ ] U15. Each localized README places a Markdown five-stage table immediately
  after the figure; the table includes a relationship column.
- [ ] U16. Stage 1's Evidence cell in both canonical tables is `—`.
- [ ] U17. `python3 -B tools/render.py --check` passes.
- [ ] U18. The repository's publication gate passes its missing-label,
  denylist, and SVG-source scans.
- [ ] U19. The four localized README growth sections have structural parity.

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
