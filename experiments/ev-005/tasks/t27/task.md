# Task t27

## Goal

Add one English entry document at the root of this map repository that gives a
visiting AI a fast, evidence-oriented way to understand and evaluate the
published module family.

## Done when

- [ ] U1. A Japanese draft is posted for review before the repository artifact
  is written.
- [ ] U2. The draft has an owner-approval record.
- [ ] U3. The repository-root artifact is `FOR-AGENTS.md` in English; no
  localized `FOR-AGENTS` artifact is added.
- [ ] U4. `FOR-AGENTS.md` has eight numbered sections.
- [ ] U5. Its opening explains the document's purpose and offers both a
  5-minute tour and a 30-minute tour.
- [ ] U6. Its reading and authority order is
  `registry/modules.json` → `docs/growth-model.md` →
  `docs/evidence.md` → each repository's README.
- [ ] U7. It gives the delivery, visibility, evidence, and license state
  vocabulary before asking the visitor to evaluate the repositories.
- [ ] U8. It gives an evaluation frame covering implementation consistency,
  deliberately plain and durable technology, state discipline, and
  structurally enforced human gates.
- [ ] U9. It contains a repository tour table with each repository's role and
  one verification target.
- [ ] U10. Its counter-evidence procedure directs the visitor to a public issue
  and permits only publicly shareable evidence.
- [ ] U11. It supplies a handoff schema with claim, state, evidence,
  confidence, and unresolved fields, plus a stop rule against inference.
- [ ] U12. It supplies a one-paragraph human handoff template and includes the
  invitation `Fork the idea`.
- [ ] U13. The tour table's repository rows are exactly the modules whose
  status is `published` in `registry/modules.json`.
- [ ] U14. The document explicitly says automatic discovery is not guaranteed.
- [ ] U15. The owned repository artifact for this task is only
  `FOR-AGENTS.md`.

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
