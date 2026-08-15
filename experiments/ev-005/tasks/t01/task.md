# Task t01

## Goal

Update this repository's documentation so the runtime setup and reference layers
surface the scheduled flush-intake consumer that belongs with the existing hook
producers, while keeping the localized documentation aligned.

## Done when

- [ ] U1. `docs/engineering.md` states that the existing hook outputs are
  producers only.
- [ ] U2. `docs/engineering.md` states that a workspace using either producer
  must also schedule the flush-intake consumer.
- [ ] U3. `docs/engineering.md` records the flush-intake schedule window.
- [ ] U4. `docs/engineering.md` records the macOS LaunchAgent scheduler surface.
- [ ] U5. `docs/engineering.md` records the deadman self-marking caveat.
- [ ] U6. `docs/engineering.md` points to
  `adapters/claude-code/INSTALL.md` as the normative setup procedure.
- [ ] U7. `docs/reference.md` names `loop/pending/intake-runs.log` as the
  flush-intake ledger.
- [ ] U8. `docs/reference.md` states the archive semantics.
- [ ] U9. `docs/reference.md` points to
  `adapters/claude-code/INSTALL.md` as the normative setup procedure.
- [ ] U10. `docs/engineering.ja.md` states that the existing hook outputs are
  producers only.
- [ ] U11. `docs/engineering.ja.md` states that a workspace using either
  producer must also schedule the flush-intake consumer.
- [ ] U12. `docs/engineering.ja.md` records the flush-intake schedule window.
- [ ] U13. `docs/engineering.ja.md` records the macOS LaunchAgent scheduler
  surface.
- [ ] U14. `docs/engineering.ja.md` records the deadman self-marking caveat.
- [ ] U15. `docs/engineering.ja.md` points to
  `adapters/claude-code/INSTALL.md` as the normative setup procedure.
- [ ] U16. `docs/reference.ja.md` names `loop/pending/intake-runs.log` as the
  flush-intake ledger.
- [ ] U17. `docs/reference.ja.md` states the archive semantics.
- [ ] U18. `docs/reference.ja.md` points to
  `adapters/claude-code/INSTALL.md` as the normative setup procedure.
- [ ] U19. The engineering-layer additions do not make claims beyond the
  repository's existing source documentation for this feature.
- [ ] U20. The reference-layer additions do not make claims beyond the
  repository's existing source documentation for this feature.
- [ ] U21. The full repository test suite is green on the branch-equivalent
  tree.
- [ ] U22. The full repository test suite is green on the post-merge mainline
  state.
- [ ] U23. Owner confirmation is obtained before publication.
- [ ] U24. A tag is published for this documentation update.
- [ ] U25. Release notes are published for this documentation update together
  with the already-landed feature batches they summarize.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `1800 s` per `.ev005-donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `.ev005-donecheck.sh` ships with this task at the repository root; it is
  readable and executable.
