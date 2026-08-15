# t13 units ledger

Units: 21 total; covered 21/21
MECH: 20
HUMAN: 1
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The hand-written family section in `README.md` retains its general prose. | `a01` (T1 content-presence of four small prose anchors spanning the family-map introduction, standalone-use claim, handbook link, and closing thanks). |
| U2 | MECH | The hand-written family section in `README.ja.md` retains its general prose. | `a02` (T1 content-presence of the corresponding four Japanese prose anchors). |
| U3 | MECH | The hand-written family section in `README.zh.md` retains its general prose. | `a03` (T1 content-presence of the corresponding four Chinese prose anchors). |
| U4 | MECH | The hand-written family section in `README.th.md` retains its general prose. | `a04` (T1 content-presence of the corresponding four Thai prose anchors). |
| U5 | MECH | The repository-specific authority note remains in `README.md`. | `a05` (T1 content-presence of three short semantic anchors: connection does not move authority; the repository shares information; it does not drive other agents). |
| U6 | MECH | The repository-specific authority note remains in `README.ja.md`. | `a06` (T1 content-presence of the corresponding three Japanese authority anchors). |
| U7 | MECH | The repository-specific authority note remains in `README.zh.md`. | `a07` (T1 content-presence of the corresponding three Chinese authority anchors). |
| U8 | MECH | The repository-specific authority note remains in `README.th.md`. | `a08` (T1 content-presence of the corresponding three Thai authority anchors). |
| U9 | MECH | The hand-written family section in `README.md` drops its module table. | `a09` (T4 content-absence of Markdown table rows inside the anchor-bounded hand-written section). |
| U10 | MECH | The hand-written family section in `README.ja.md` drops its module table. | `a10` (T4 content-absence of Markdown table rows inside that section). |
| U11 | MECH | The hand-written family section in `README.zh.md` drops its module table. | `a11` (T4 content-absence of Markdown table rows inside that section). |
| U12 | MECH | The hand-written family section in `README.th.md` drops its module table. | `a12` (T4 content-absence of Markdown table rows inside that section). |
| U13 | MECH | The marker-delimited generated family footer in `README.md` is untouched. | `a13` (T6 structural Python probe under an invocation-specific fresh `HOME` and `TMPDIR`: exactly one start/end marker pair and exact SHA-256 of the pre-fix generated block). Exactness is source-required invariance, not historical prose pinning. |
| U14 | MECH | The marker-delimited generated family footer in `README.ja.md` is untouched. | `a14` (T6 structural Python probe under its own fresh `HOME` and `TMPDIR`: unique marker pair and exact pre-fix generated-block SHA-256). |
| U15 | MECH | The marker-delimited generated family footer in `README.zh.md` is untouched. | `a15` (T6 structural Python probe under its own fresh `HOME` and `TMPDIR`: unique marker pair and exact pre-fix generated-block SHA-256). |
| U16 | MECH | The marker-delimited generated family footer in `README.th.md` is untouched. | `a16` (T6 structural Python probe under its own fresh `HOME` and `TMPDIR`: unique marker pair and exact pre-fix generated-block SHA-256). |
| U17 | MECH | `README.md` leaves the generated footer as its single family module table. | `a17` (T6 structural: the distinctive English family-module table header occurs exactly once in the file; `a13` separately proves that occurrence is inside the unchanged generated block). |
| U18 | MECH | `README.ja.md` leaves the generated footer as its single family module table. | `a18` (T6 structural: the corresponding Japanese table header occurs exactly once; `a14` locates it in the unchanged generated block). |
| U19 | MECH | `README.zh.md` leaves the generated footer as its single family module table. | `a19` (T6 structural: the corresponding Chinese table header occurs exactly once; `a15` locates it in the unchanged generated block). |
| U20 | MECH | `README.th.md` leaves the generated footer as its single family module table. | `a20` (T6 structural: the corresponding Thai table header occurs exactly once; `a16` locates it in the unchanged generated block). |
| U21 | HUMAN | A four-language inspection passes. | Dropped (HUMAN: a holistic multilingual prose-quality judgment requires a reader). The mechanical core—presence of prose and authority anchors, absence of the duplicate tables, exactly one family module table, and byte-identical generated blocks in all four files—is covered by `a01`–`a20`; lost: fluency and semantic-quality judgment beyond those anchors. |

## Anonymization and needle record

- Mapping: the source repository is “this repository,” and its family-map
  section is the “hand-written family section.” The source's named architecture
  abbreviation remains only in the executable gate as content already present
  in the replica, not as issue provenance in `task.md`.
- Longest T1/T4 prose needle: `github.com/caty-ai/family-dev-handbook`
  (38 characters). It is a surviving link in each pre-fix hand-written family
  section and is pinned because the criterion requires that prose to remain.
  The generated-block digests are T6 invariants derived from the pre-fix
  blocks, not prose needles copied from the historical fix.
- Timeout remains the default 120 seconds. The gate performs bounded local
  text checks plus four structural Python hash probes; every Python invocation
  receives a separate fresh `HOME` and `TMPDIR` and is cleaned up immediately
  after it completes.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Replace the leading `|` with `¦` on the eleven duplicate family-table rows so they still read similarly but no longer parse as Markdown table rows.
- Route: `a`
- Expected result: `a10`-`a12` and `a18`-`a20` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a10`, `a11`, `a12`, `a18`, `a19`, `a20`; `RUN t13 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t13.log`.
- Rationale: The duplicate-table removal and single-footer-table checks remain structural; visually similar fake rows do not satisfy them.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t13.log` (current pre-leg record).
- a01 — invariance guard: The English hand-written family-section prose anchors already exist in the pre tree, so this PASS protects them.
- a02 — invariance guard: The Japanese hand-written family-section prose anchors already exist pre-fix.
- a03 — invariance guard: The Chinese hand-written family-section prose anchors already exist pre-fix.
- a04 — invariance guard: The Thai hand-written family-section prose anchors already exist pre-fix.
- a05 — invariance guard: The English authority note already exists pre-fix and is intentionally guarded.
- a06 — invariance guard: The Japanese authority note already exists pre-fix and is intentionally guarded.
- a07 — invariance guard: The Chinese authority note already exists pre-fix and is intentionally guarded.
- a08 — invariance guard: The Thai authority note already exists pre-fix and is intentionally guarded.
- a13 — invariance guard: The English generated footer block already matches the pinned SHA-256 on the pre tree.
- a14 — invariance guard: The Japanese generated footer block already matches the pinned SHA-256 on the pre tree.
- a15 — invariance guard: The Chinese generated footer block already matches the pinned SHA-256 on the pre tree.
- a16 — invariance guard: The Thai generated footer block already matches the pinned SHA-256 on the pre tree.

## r4-2 waiver record

- The broad suite `python3 scripts/tests/run_tests.py` exercises unrelated script subsystems, not the README footer-block criterion units for this task.
- The byte-exact SHA-256 plus marker-structure probes in `a13`-`a20` are stronger than the broad suite for this criterion because they prove exact correspondence of the generated footer blocks.
- The same suite also carries the FMA#18 coupling risk: `scripts/tests/test_recall.py` clears environment state and can diverge between passwd-home resolution and restored caller `HOME`, so using it here would add unrelated noise instead of stronger evidence.
