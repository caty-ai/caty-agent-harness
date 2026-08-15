# Task t10

## Goal

Add a registry-generated module/state table near the bottom of the map
repository's four localized READMEs, while preserving the generated footers
used by member repositories.

## Done when

- [ ] U1. `README.md` contains the new generated family table near its bottom.
- [ ] U2. `README.ja.md` contains the new generated family table near its bottom.
- [ ] U3. `README.zh.md` contains the new generated family table near its bottom.
- [ ] U4. `README.th.md` contains the new generated family table near its bottom.
- [ ] U5. Each generated block is the localized module/state table built from
  `registry/modules.json` by the existing table builder.
- [ ] U6. In each generated table, the map row is bold and is not self-linked.
- [ ] U7. `tools/render.py --check` detects stale content in any such block.
- [ ] U8. `tools/render.py --check` passes.
- [ ] U9. `tools/check_registry.py` passes.
- [ ] U10. `tools/family_footer.py lint` passes.
- [ ] U11. The family-footer self-test passes.
- [ ] U12. Default member-repository footer rendering still links the map row
  and renders each host module bold and unlinked.

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
