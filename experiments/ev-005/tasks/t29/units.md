# t29 units ledger

Units: 19 total; covered 19/19
MECH: 17
HUMAN: 2
MOOT: 0

Anonymization mapping: the source repository is the "map repository"; epic and
issue references, owner identity, dates, dependency ordering, and review-lane
provenance are omitted. The named repository paths, I/WE/THEY terms,
Relationship Readiness, and check commands remain because they are
criterion-constitutive.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The English and Japanese canonical growth-model documents exist. | `a01` (T2 path existence). |
| U2 | MECH | Both canonical documents contain an operational five-stage table. | `a01` (T6 structural: each document has one table with stage rows 1 through 5 and the operational decision/delivery/evidence columns). |
| U3 | MECH | Both canonical documents map stages 1–4 to I, stage 5 to WE, and inheritance to THEY outside the model. | `a02` (T6 structural: parse the I/WE/THEY rows, check their stage-range/beyond semantics, and require the outside-model statement without pinning any complete row). |
| U4 | MECH | Both canonical documents describe Relationship Readiness as a second axis. | `a03` (T1 content-presence of the source-named axis plus nearby second-axis semantics; no historical five-step sentence is pinned). |
| U5 | HUMAN | The English and Japanese documents are complete and coherent. | Weakened (HUMAN→MECH extraction): `a01`–`a03` and `a10` cover the required tables, subject model, second axis, and stage-1 evidence. Lost: holistic editorial quality, translation fidelity, and whether every useful nuance of a "complete" account is present. |
| U6 | MECH | The English README growth section presents five stages. | `a04` (T6 structural: the anchor-bounded growth section contains exactly stage rows 1 through 5). |
| U7 | MECH | The Japanese README growth section presents five stages. | `a04` (same structural check). |
| U8 | MECH | The Chinese README growth section presents five stages. | `a04` (same structural check). |
| U9 | MECH | The Thai README growth section presents five stages. | `a04` (same structural check). |
| U10 | MECH | All four summaries separate stage-3 implemented/unverified evidence from stage-4 planned status. | `a05` (T6 structural: localized state tokens already derivable from each pre-fix README, a `docs/evidence.md#...` link in stage 3, and distinct stage 3/4 rows). The historical claim-id suffix is intentionally not pinned. |
| U11 | MECH | The growth-stage SVG exists. | `a06` (T2 path existence plus XML parsing). |
| U12 | HUMAN | The SVG is language-independent, minimal, and understandable. | Weakened (HUMAN→MECH extraction): `a06` requires valid accessible SVG, ASCII-only visible labels, stage numbers 1–5, and a distinctive word dynamically derived from each replica-local canonical English stage name. Lost: aesthetic clarity and a reader's holistic judgment of minimality. |
| U13 | MECH | Solid, dashed, and orange encodings mean implemented, planned, and focus-not-state. | `a07` (T6 structural: planned/focus style classes plus semantic legend-token co-presence; no historical color value is pinned). |
| U14 | MECH | The I → WE boundary is explicit between stages 4 and 5. | `a08` (T6 structural: derive distinctive stage-4/5 tokens from the replica-local canonical table, then require the visible I→WE boundary element to occur between those labels in SVG source order; historical labels and coordinates are not pinned). |
| U15 | MECH | Each README places a five-stage relationship table immediately after the figure. | `a09` (T6 structural: next nonblank line after the shared image is a six-column table header containing the localized relationship label, followed by rows 1–5). |
| U16 | MECH | Stage 1 Evidence is `—` in both canonical tables. | `a10` (T6 structural row/cell comparison). |
| U17 | MECH | The renderer check passes. | `a11` (T3 command-exit: exact source-named command). |
| U18 | MECH | The publication gate's missing-label, denylist, and SVG scans pass. | `a12` (T3 command-exit: `python3 -B tools/check_publication_gate.py`, whose replica-local implementation runs those scans). |
| U19 | MECH | The four localized growth sections have structural parity. | `a13` (T6 structural: common image path, six table columns, row set 1–5, and the same figure→table ordering in every localized section). |

Needle calibration and solvability:
- Longest fixed T1/T4 phrase is `Relationship Readiness` (22 characters), the
  source-named axis, not historical fix prose.
- Localized implemented/planned tokens are already present in the corresponding
  pre-fix README. All other structural targets are stated in task.md or derived
  from the replica-local documents and tools; no full sentence or historical
  claim-id is pinned.
- Timeout remains the default 120 seconds; both named repository checks are
  local and the structural probe is read-only.

## REV6 validation evidence (r3-4)

- Fresh 5+5 history-zero validation: pre exit/duration pairs were `1/1s`, `1/0s`, `1/0s`, `1/0s`, `1/1s`; fix pairs were `0/1s`, `0/1s`, `0/1s`, `0/0s`, `0/0s`. `VERDICT PASS`, no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/t29.log`.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Replace the shared growth SVG with exactly `<svg role="img"></svg>`.
- Route: `a`
- Expected result: `a01`-`a10` and `a13` should still FAIL.
- Evidence status: REV5 recorded `EXPECTED_FAIL_CONFIRMED` for `a01`–`a10` and `a13` (`exit=1`, `dur=0s`); the fresh REV6 run confirms the same failing IDs after the setup-accounting edit (`exit=1`, `dur=0s`, no `DIRTY_TREE`) in `experiments/ev-005/tools/validate-logs/negprobe/t29.log`.
- Rationale: A tiny accessible SVG still fails the structural legend, boundary, placement, and renderer-backed checks.

## Setup accounting (REV6 r5-3)

- Structural-probe setup is accounted per assertion: if `growth_model_probe.py` is missing, each dependent ID (`a01`–`a10`, `a13`) emits its own explicit FAIL while independent renderer/publication checks `a11` and `a12` still run; every ID emits exactly one CHECK. A history-zero, fixtures-omitted setup probe emitted `a01`–`a13` exactly once, exited 1 in 0s, left a clean tree, and recorded `SETUP_PROBE_RESULT PASS` in `experiments/ev-005/tools/validate-logs/setup-probe/t29.log`.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t29.log` (current pre-leg record).
- a11 — invariance guard: The first renderer/publication-gate check already passes on the pre tree and intentionally guards that invariant.
- a12 — invariance guard: The second renderer/publication-gate check already passes pre-fix and is an intentional guard.
