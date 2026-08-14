# Task t13

## Goal

Remove the stale hand-written module tables from this repository's four
localized README family sections while preserving their prose, their
repository-specific authority boundary, and the generated family footers.

## Done when

- [ ] U1. The hand-written family section in `README.md` retains its general
  prose.
- [ ] U2. The hand-written family section in `README.ja.md` retains its general
  prose.
- [ ] U3. The hand-written family section in `README.zh.md` retains its general
  prose.
- [ ] U4. The hand-written family section in `README.th.md` retains its general
  prose.
- [ ] U5. The repository-specific authority note remains in the hand-written
  family section in `README.md`.
- [ ] U6. The repository-specific authority note remains in the hand-written
  family section in `README.ja.md`.
- [ ] U7. The repository-specific authority note remains in the hand-written
  family section in `README.zh.md`.
- [ ] U8. The repository-specific authority note remains in the hand-written
  family section in `README.th.md`.
- [ ] U9. The hand-written family section in `README.md` contains no module
  table.
- [ ] U10. The hand-written family section in `README.ja.md` contains no module
  table.
- [ ] U11. The hand-written family section in `README.zh.md` contains no module
  table.
- [ ] U12. The hand-written family section in `README.th.md` contains no module
  table.
- [ ] U13. The marker-delimited generated family footer in `README.md` is
  untouched.
- [ ] U14. The marker-delimited generated family footer in `README.ja.md` is
  untouched.
- [ ] U15. The marker-delimited generated family footer in `README.zh.md` is
  untouched.
- [ ] U16. The marker-delimited generated family footer in `README.th.md` is
  untouched.
- [ ] U17. `README.md` contains exactly one family module table: the one in the
  generated footer.
- [ ] U18. `README.ja.md` contains exactly one family module table: the one in
  the generated footer.
- [ ] U19. `README.zh.md` contains exactly one family module table: the one in
  the generated footer.
- [ ] U20. `README.th.md` contains exactly one family module table: the one in
  the generated footer.
- [ ] U21. A human inspection of all four localized README variants passes.

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
