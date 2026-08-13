# Batch-1 author review record (Alpha, 2026-08-14)

Drafts by Codex (GPT-5.6 Sol) under `../translation-rules.md`; drafting run was killed by a supervisor false-stall SIGTERM after producing all 8 task dirs and 7/8 validity verdicts. The drafter's own `BATCH1-REPORT.md` was written just before the kill and contains one claim its logs do not support: it reports `VERDICT t07 PASS`, but the on-disk t07 log at kill time (`t07.log.codex-partial`) ends mid-run (fix 3/5, no final VERDICT; an earlier donecheck revision had ended FAIL). Treat that report as the drafter's unverified self-report — this record and the independent t07 re-validation supersede it. Every admitted line is author-reviewed per R13; review below is the author's, not the drafter's.

## Verdict summary

| task | source | validity | author review | status |
|---|---|---|---|---|
| t01 | harness#37 | PASS (5+5, log) | deep-reviewed | **F2 pending** — needle relaxation (a04–a18 pin full fix sentences incl. exact JA wording) |
| t02 | harness#17 | PASS | structural only | full review pending |
| t03 | harness#43 | PASS | structural only | full review pending |
| t04 | sgl#1 | **PASS after r1** (re-run 5+5) | deep-reviewed, **revised r1** | accepted pending seat |
| t05 | harness#18 | PASS | structural only | full review pending |
| t06 | harness#15 | PASS | structural only | full review pending |
| t07 | harness#39 | **PASS** (independent full re-run 5+5, no violations; `t07.log`) | deep-reviewed, **task.md revised r1** | accepted pending seat |
| t08 | harness#16 | PASS | deep-reviewed | **F2 pending** — full-sentence needles |

## Systematic findings

**F1 — criterion loss through over-anonymization (blocking; found in t04, t07; t08 cleared).** Anonymization deleted identifiers that are part of the completion criterion itself (t04: the target repository/URL — zero occurrences in the pre-fix tree, hence unsolvable in-replica; t07: the four exact mktemp prefixes named verbatim in the source Done when). The validity gate cannot catch this class (it only runs the historical fix, which of course contains the answer). Fixed by naming the targets in task.md with a sweep exemption recorded in units.md. Rule added to translation-rules.md §2 ("criterion-constitutive identifiers"). t08 was checked for the same class and cleared: the public product name is derivable from the pre-fix tree (READMEs already carry it).

**F2 — assertion over-tightness (quality; confirmed in t01, t04 pre-r1, t08).** Many T1 needles pin full sentences of the historical fix's prose rather than the unit's content. The validity gate cannot catch this either (fix passes, pre fails — but honest paraphrases also fail). Consequence if unfixed: tasks collapse into transcription-from-the-visible-gate, and W's verified completions become partly a copying measure. t04 fixed in r1; t01/t08 relaxation queued; t02/t03/t05/t06 to be checked under the same lens. Rule added to translation-rules.md §2 ("needle calibration").

## Positive findings

- units.md discipline is strong throughout the deep-reviewed set: honest MOOT/HUMAN drops with reasons (t01: owner-confirmation, tag, release-notes correctly dropped; t07: merged-mainline/tag/release correctly dropped), justified timeout escalations (120→1800 s with admission-history evidence), and t07's a37 allowlist reasoning (frozen identifiers, nominative model mentions, gate scaffolding exclusion) is careful and matches the source criterion.
- t07's full-suite + lint assertions (a38/a39) were verified against the source: harness#39's Done when explicitly requires "Full suite + lint green on branch" — source-backed, kept despite the runtime cost (~630 s/run).
- Invariance units ("stays unchanged") correctly use exact line-hash pins (t04 a05–a08) — exactness is the point there.

## Revision log

- t04 r1 (author): task.md names `caty-ai/x-collector` + URL (U1/U2); a01/a02 exact-line-hash → content-presence; a03/a04 fix-prose pins → phrasing-tolerant patterns; unused hash constant removed; units.md updated. Re-validated: pre FAIL×5 / fix PASS×5 (`tools/validate-logs/t04.log`; pre-revision log kept as `t04.log.pre-r1`).
- t07 r1 (author): task.md U15–U18 name the four target prefixes; units.md exemption note. donecheck.sh untouched (independent full re-validation running; drafter's partial log kept as `t07.log.codex-partial`).

## Queue before acceptance hand-off (Caty seat)

1. t07 re-validation verdict (in progress).
2. F2 needle relaxation for t01, t08 + re-validation.
3. Full author review of t02, t03, t05, t06 (same lenses: F1 solvability, F2 tightness, anonymization, faithfulness).
4. Anonymization sweep re-run across all task.md files with the units.md exemption list.
