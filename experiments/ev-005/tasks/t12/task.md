# Task t12

## Goal

Keep both repository linters on the constrained standard-library parser and
remove obsolete third-party YAML dependency guidance from every named public
document.

## Done when

- [ ] U1. `scripts/content-lint` does not import `yaml`.
- [ ] U2. `scripts/injection-lint` does not import `yaml`.
- [ ] U3. `README.md` contains no PyYAML dependency row or note.
- [ ] U4. `README.ja.md` contains no PyYAML dependency row or note.
- [ ] U5. `README.th.md` contains no PyYAML dependency row or note.
- [ ] U6. `README.zh.md` contains no PyYAML dependency row or note.
- [ ] U7. `docs/repository-map.md` contains no PyYAML dependency row or note.
- [ ] U8. `docs/getting-started.md` contains no PyYAML dependency row or note.
- [ ] U9. `docs/agent-guide.md` contains no PyYAML dependency row or note.
- [ ] U10. `CONTRIBUTING.md` contains no PyYAML dependency row or note.
- [ ] U11. `SECURITY.md` contains no PyYAML dependency row or note.
- [ ] U12. The full repository test suite passes on a clean Python environment.
- [ ] U13. The full repository test suite reports no skipped tests.

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
