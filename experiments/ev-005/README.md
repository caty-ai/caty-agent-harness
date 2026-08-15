# EV-005 — does a fail-closed completion gate increase *verified* completions?

A pre-registered, sealed experiment. Three arms run the same 30 software tasks under the same
budget; they differ only in whether a machine gate enforces the task's completion check.

- **W** — self-verification instructed **and** enforced: delivery only through a fail-closed gate.
- **B+** — self-verification instructed, no enforcement.
- **B** — minimal instruction.

The confirmatory comparison is **W vs B+** (single factor: enforcement). W vs B and B+ vs B are
descriptive. Everything that could move an outcome — the arm texts, the budget, the replicate
count, the seeds, the environment, the analysis rules — was frozen before any run.

## Verify the seal yourself

    python3 tools/seal-manifest.py . --check       # from this directory
    ots verify MANIFEST.sha256.ots                 # third-party timestamp

`MANIFEST.sha256` lists a SHA-256 for every sealed file. `--check` exits non-zero if any sealed
file was added, removed, or modified. The OpenTimestamps proof commits the manifest digest to
the Bitcoin blockchain, so the sealing date does not depend on trusting this repository. CI runs
the same check on every push that touches this directory.

This README, `MANIFEST.sha256`, `MANIFEST-META.md` and the `.ots` proof are **outside** the
sealed scope — navigation and verification material, not pre-registration content. (A manifest
cannot hash itself, and reader-facing prose should be improvable without an amendment.)

## What is here

| path | what it is |
| --- | --- |
| `analysis-plan.md` | the pre-registration: hypotheses, outcome coding, the single confirmatory test, exclusions, sensitivity analyses, stopping rules, sealing scope, amendment procedure |
| `translation-rules.md` | how a historical bug-fix becomes a task (R1–R15 plus the r1–r5 rule追補), including the negative-validity rule r5-1 |
| `eligibility-ledger.md` | every candidate considered, why each was admitted or excluded, and the two-tier provenance limitation |
| `arm-instructions.md` | the three arm texts and the declaration matcher — the treatment definition itself |
| `runner-spec.md` | the harness: snapshot-before-adjudication, the sealed-bytes gate, budget accounting, audit-log schema, environment requirements |
| `sealed-parameters.md` | every frozen number: seeds and their draw procedures, crossover list, budgets, k |
| `canary-rule.md` | leak detection, with its scope limits stated |
| `source-provenance.md` | source repositories vs model training cutoffs |
| `environment-digest.md` | both run cells, by image digest, verified by their operators |
| `tasks/t01…t30` | the analysis set: task sheet, machine gate, unit ledger, metadata |
| `pilot-tasks/p01…p05` | the pilot set, outside the analysis set |
| `tools/` | the validator, the MDD simulation, the manifest generator |
| `tools/validate-logs/` | the evidence: every validity run, negative probe, and setup probe |

## How the tasks were checked

Each task is a real fix from a real repository, replayed against a history-zero replica. To be
admitted, its gate had to **fail five times on the pre-fix tree and pass five times on the fix
tree** — and, under r5-1, to **reject a deliberate cheat**: the smallest edit that satisfies the
assertions' surface form without doing the work. That last rule found three real holes on its
first run (gates that accepted the asserted strings hidden in HTML comments); they were reported
and fixed rather than re-scoped, and the probe corpus is sealed alongside the tasks.

Four non-author reviewers examined the pack before sealing. Their conditions, the author's
rulings, and the one owner decision are recorded in caty-ai/caty-agent-harness#63.

## Status

Sealed 2026-08-16 (tag `ev-005-sealed-v1`). Next: the pilot (5 tasks × 3 arms × 3 replicates),
whose ceiling/floor band decides whether the main series starts. No outcome data exists yet.
