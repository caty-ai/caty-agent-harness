# Batch-1 author review record (Alpha, 2026-08-14)

Drafts by Codex (GPT-5.6 Sol) under `../translation-rules.md`; drafting run was killed by a supervisor false-stall SIGTERM after producing all 8 task dirs and 7/8 validity verdicts. The drafter's own `BATCH1-REPORT.md` was written just before the kill and contains one claim its logs do not support: it reports `VERDICT t07 PASS`, but the on-disk t07 log at kill time (`t07.log.codex-partial`) ends mid-run (fix 3/5, no final VERDICT; an earlier donecheck revision had ended FAIL). Treat that report as the drafter's unverified self-report — this record and the independent t07 re-validation supersede it. Every admitted line is author-reviewed per R13; review below is the author's, not the drafter's.

## Verdict summary

| task | source | validity | author review | status |
|---|---|---|---|---|
| t01 | harness#37 | **PASS after r2** (re-run 5+5) | deep-reviewed, **F2 r2 applied** (12 needles relaxed, Codex, author-verified) | accepted pending seat |
| t02 | harness#17 | r2 re-validation running | deep-reviewed, **F2 r2 applied** (author: a01–a08 row-pins → `check_pair` fragments, a21 relaxed; a09–a20/a22–a25 functional strings kept) | accepted pending r2 validity + seat |
| t03 | harness#43 | PASS | deep-reviewed (needle audit: no fragment >60 chars; structural/`none`-declaration checks; targets in-repo derivable) | accepted pending seat |
| t04 | sgl#1 | **PASS after r1** (re-run 5+5) | deep-reviewed, **revised r1** | accepted pending seat |
| t05 | harness#18 | PASS | deep-reviewed (needle audit: long strings are functional env-var/path lines from the tree itself, incl. the pre-fix private paths being removed — not fix prose) | accepted pending seat |
| t06 | harness#15 | PASS | deep-reviewed (needle audit clean; see provenance note below) | accepted pending seat |
| t07 | harness#39 | **PASS** (independent full re-run 5+5, no violations; `t07.log`) | deep-reviewed, **task.md revised r1** | accepted pending seat |
| t08 | harness#16 | **PASS after r2** (re-run 5+5) | deep-reviewed, **F2 r2 applied** (17 needles relaxed, Codex, author-verified) | accepted pending seat |

**Provenance note (t06 and all harness re-enactments):** t06's needles legitimately contain the real public repo URL and public deploy-fleet table content (agent names, hosts) — that is the fix's own published content and the criterion itself. More generally, the replica tree self-identifies (post-rename trees carry the public product name throughout), so anonymization for this bundle means *issue/PR/tracker provenance removal*, not repo-identity concealment — the latter is impossible for re-enactments and is not what the leak canaries target (they target fix-history leakage).

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

1. ~~t07 re-validation~~ done (PASS).
2. ~~F2 relaxation t01/t08~~ done (r2, both PASS).
3. ~~Author review t02/t03/t05/t06~~ done (t02 F2 r2 applied; t03/t05/t06 clean).
4. t02 r2 re-validation verdict (running).
5. ~~Anonymization sweep~~ done: 6/8 task.md zero hits; t04 = 2 hits, t07 = 4 hits — both exactly the criterion-constitutive identifiers exempted in their units.md rows. GREEN.

Once item 4 lands PASS, batch 1 is author-complete and hands off to the non-author acceptance seat (Caty) + the 10–20% second-author re-derivation sample.
