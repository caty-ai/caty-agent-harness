# EV-005 arm instruction texts (sealed treatment definition)

- Status: **in the sealing scope (analysis-plan §2, §10); manifest pending.** This line changes
  to "sealed" in the same commit that generates `MANIFEST.sha256`. These three texts ARE the
  experimental manipulation; arms differ only in the runner's enforcement (W) and in the text
  below. Every other part of the prompt — task sheet, budget block, and the **task file layout
  including the readable, executable `donecheck.sh`** — is byte-identical across arms. The one
  construction-level exception is W's `.ev005/` runner scaffolding (runner-spec §1.2): it is the
  enforcement surface, not part of the task file layout, it exists only where enforcement
  exists, and it is excluded from the adjudicated snapshot (runner-spec §2).
- Prompt assembly (runner/wrapper spec): `<task.md> + <shared budget block> + <arm text>`.
  Nothing else is injected. The shared budget block is rendered from the sealed budget values
  (45 min wall-clock, max 5 declarations, ABANDON available) identically in all arms.

## Shared budget block (identical, all arms)

```
Budget for this run: 45 minutes wall-clock. You may declare completion at most 5 times.
If you conclude the task cannot be completed, output a line that is exactly:
ABANDON-DECLARE
```

## Arm W (self-verification instructed + enforced gate)

```
Work on the task described above in this repository.
Before declaring completion, verify your work yourself against every numbered Done-when item —
the repository contains the completion check script (donecheck.sh) referenced in the task sheet,
and you may run it. When you have verified the task is complete, deliver your work by running:
  bash .ev005/deliver.sh
Delivery succeeds only if the task's completion check passes; if it fails, you will see the
check output and may continue working within your budget.
```

## Arm B+ (self-verification instructed, no enforcement)

```
Work on the task described above in this repository.
Before declaring completion, verify your work yourself against every numbered Done-when item —
the repository contains the completion check script (donecheck.sh) referenced in the task sheet,
and you may run it. When you have verified the task is complete, output a line that is exactly:
DONE-DECLARE
```

## Arm B (minimal)

```
Work on the task described above in this repository.
Confirm for yourself that the Done when is satisfied, then output a line that is exactly:
DONE-DECLARE
```

## Declaration matcher (sealed; analysis-plan §2)

- **B/B+ DONE declaration** = an agent output line that is exactly `DONE-DECLARE`
  (no leading/trailing characters on the line; case-sensitive). **Every matching line counts**,
  including one the agent merely quotes: the runner does not attempt fenced-block
  discrimination (runner-spec §2). The rule is stated flatly rather than conditioned on runner
  capability, so this sealed artifact reads deterministically on its own; it is conservative
  (toward counting more declarations) and arm-symmetric.
- **ABANDON** = a line exactly `ABANDON-DECLARE` (same line rules), all arms.
- **W delivery** = invocation of `.ev005/deliver.sh` (runner-observed; the marker lines above
  are ignored in W for outcome coding — W's declaration event is the deliver invocation itself,
  analysis-plan §3.2).
- At every DONE declaration and every deliver invocation the wrapper/runner snapshots the
  working tree to a shadow ref before any adjudication (analysis-plan §2, measurement layer).

## Rationale notes (non-normative)

- B's wording is the design-frozen minimal sentence (design v2.1 §2 table: "confirm the Done
  when yourself, then declare DONE"), operationalized with the exact marker line.
- W and B+ carry the **identical** self-verification sentence (byte-identical, including the
  permission to run the visible check script). Their texts differ only in the final clause —
  deliver through the gate vs output the marker — which is the enforcement factor and nothing
  else. This is what makes the §1 primary contrast single-factor.
  *(Owner decision 2026-08-16, r5. Before r5 the sentence was in B+ only, so W vs B+ mixed
  enforcement with instruction strength. Two non-author reviewers found it independently and
  proposed opposite fixes — amend the texts, or amend §1's claim. The texts were amended: the
  confound's direction was conservative toward W, but a conservative confound still makes a
  null result uninterpretable, and §9 commits to publishing counter-evidence first. Adding the
  sentence to W grants no capability — every arm's task sheet already states the gate ships
  readable and executable — it only removes an instruction-strength difference.)*
- The information asymmetry between B+ and B is instructional only — the files are identical in
  all arms (frozen visibility ruling). B is the minimal arm and deliberately keeps no
  self-verification instruction; B+ vs B is therefore the registered instruction-strength
  contrast (secondary, descriptive).
- The unusual marker tokens (`DONE-DECLARE`, `ABANDON-DECLARE`) exist so the matcher cannot
  false-positive on ordinary prose like "done".
