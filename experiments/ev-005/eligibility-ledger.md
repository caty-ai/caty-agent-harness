# EV-005 task-candidate eligibility ledger

- Normative design: caty-ai/caty-agent-harness#63 (design v2.1, frozen 2026-08-13)
- Survey input: fact table of 42 closed issues (surveyed by alec-bridge, 2026-08-13, public sources only)
- Inspection: Alpha (alpha-mbp-bridge), 2026-08-13. Every fact below was re-verified against the GitHub API by the inspector; the survey itself was never treated as authority.

## 1. Inspection method and results

| check | method | result |
|---|---|---|
| fix SHA exists | `GET /repos/{repo}/commits/{fix}` | 18/18 OK |
| pre_fix = first parent of fix | parent[0] of fix commit compared to pre_fix | 18/18 structurally OK — **semantically falsified for FMA#1 by I-2** (reverse-merge parent-order; corrected pair in row and t12 meta) |
| PR merge SHA = fix | `GET /repos/{repo}/pulls/{pr}` `.merge_commit_sha` (merged=true) | 18/18 OK |
| Done when quotes | spot re-read of issue bodies (#49 heading, #19/#14 epic tables, all rows marked NO) | 1 systematic finding (below) |
| test_cmd claims | harness Makefile `test` target, FMA README run_tests line, sgl README `tests/run.sh` | OK as quoted |
| fact/judgement separation | survey contains only facts + UNKNOWN cells with evidence | OK |

**Finding I-2 (pair correction, batch-2 authoring 2026-08-14):** family-memory-architecture#1's PR #8 was merged by reverse-merge-then-fast-forward: the recorded merge commit `8676d838` was created **on the feature branch** ("Merge main into issue-1-stdlib-port"), so its parent[0] is the feature tip `a55397b5` — which already contains the port. The survey convention `pre_fix = parent[0] of fix` therefore yielded a pre-tree that satisfies the criterion, caught mechanically by the batch-2 drafter's honest validity FAIL (all derived checks pass on the wrong pre-tree). Corrected pair: `pre_fix = 25b426bb` (parent[1], main before the port landed; `import yaml` present in both scripts), `fix = 8676d838` (unchanged). Row updated below. The other 17 re-enactment pairs are functionally confirmed by their validity runs (pre FAIL×5 / fix PASS×5), which this failure mode cannot survive.

**Finding I-3 (SYNTH-SOURCE re-classification, batch-3 authoring 2026-08-14):** local git archaeology (`git log -S` + issue-referencing commit subjects) identified concrete fix commits for 13 of the SYNTH-SOURCE patterns plus a milestone span for context-kit#1 — the survey's "no pair" verdicts reflected missing *GitHub PR linkage*, not missing fixes. All 14 are re-classified **REENACT** with the pairs recorded in the batch-3 report (t17–t30): harness#22 `1db3a71`, #10 `723acbd`, #23 `875acb9`, #20 `1aa6bda`, #12 `870fca5`, #21 `157855c`, #11 `3a3e845`, #30 `d81202b`; family-os#12 `e830a0e`, #27 `a7b0c20`, #26 `7478c35`, #29 `3b79945`, #28 `d66aefe`; context-kit#1 span `286c2a3..90d5cfe` (kickoff completed over two milestone commits; pre = grandparent, recorded explicitly). Provenance for these pairs is commit-subject issue references verified by content inspection; the R11 validity gate arbitrates each pair mechanically (pre FAIL×5 / fix PASS×5). Consequence: the bundle reaches 30 as **30 re-enactments / 0 synthetic** — strictly better external validity than the pre-registered 16+14 fallback math (synthetic type-completion was the fallback for missing pairs, which no longer applies).

**Finding I-1 (survey correction, adopted):** the survey's `done_when` column detected *headings* only (`## Done when` / `完了条件`). Five family-memory-architecture issues (#1 #2 #3 #4 #11) carry an inline `Done when:` sentence in the body prose — substantively a completion criterion. Their `done_when` is corrected NO → **YES (inline)**. All other NO rows were re-read and stay NO (harness#19 and #14 are epic bodies whose only "Done when" occurrences are checkpoint-table references; family-os#10/#5/#2 have none).

## 2. Verdict vocabulary

- **REENACT** — eligible for re-enactment: verified fix/pre_fix pair + Done when (heading or inline). Task = pre_fix checkout, anonymized task.md derived from the issue, donecheck derived per translation-rules.md.
- **SYNTH-SOURCE** — Done when exists but no identifiable fix commit pair; usable as a *pattern source* for synthetic (type-completion) tasks, never as a re-enactment.
- **INELIGIBLE** — no Done when and no fix pair (or epic-level container). Excluded.

## 3. Ledger (42 candidates)

| candidate | pair verified | done_when | verdict | notes |
|---|---|---|---|---|
| caty-agent-harness#56 | OK | YES | REENACT | size-XL (16 files, +1258/−412) — expect decomposition or exclusion at bundle authoring; flag `size-risk` |
| caty-agent-harness#49 | OK | YES | REENACT | size-L (+461/−102) |
| caty-agent-harness#43 | OK | YES | REENACT | 1 file, CI template regeneration |
| caty-agent-harness#39 | OK | YES | REENACT | rename sweep, 8 files ±18 |
| caty-agent-harness#37 | OK | YES | REENACT | docs 4 files +32 |
| caty-agent-harness#30 | OK (I-3: fix `d81202b`, pre `18e8975`) | YES | REENACT | admitted as t30; CI-gates deployment |
| caty-agent-harness#27 | OK | YES | REENACT | size-XL (25 files, +1826/−299) — flag `size-risk` |
| caty-agent-harness#23 | OK (I-3: fix `875acb9`, pre `06b763a`) | YES | REENACT | admitted as t21; skill-lint contract |
| caty-agent-harness#22 | OK (I-3: fix `1db3a71`, pre `19032f7`) | YES | REENACT | admitted as t17; failure visibility |
| caty-agent-harness#21 | OK (I-3: fix `157855c`, pre `18e8975`) | YES | REENACT | admitted as t26; conventions note |
| caty-agent-harness#20 | OK (I-3: fix `1aa6bda`, pre `5ae0686`) | YES | REENACT | admitted as t23; input validation |
| caty-agent-harness#19 | no pair | NO (epic container) | INELIGIBLE | children #20–#23 are the actionable units |
| caty-agent-harness#18 | OK | YES | REENACT | 8 files +53/−29 |
| caty-agent-harness#17 | OK | YES | REENACT | 5 files +38/−17 |
| caty-agent-harness#16 | OK | YES | REENACT | 12 files +64/−59 |
| caty-agent-harness#15 | OK | YES | REENACT | 8 files +31/−40 |
| caty-agent-harness#14 | no pair | NO | INELIGIBLE | epic-style body, no own criterion |
| caty-agent-harness#12 | OK (I-3: fix `870fca5`, pre `dfbc094`) | YES | REENACT | admitted as t25; updater verification |
| caty-agent-harness#11 | OK (I-3: fix `3a3e845`, pre `7155578`) | YES | REENACT | admitted as t28; donecheck boundary |
| caty-agent-harness#10 | OK (I-3: fix `723acbd`, pre `2bbc00a`) | YES | REENACT | admitted as t19; SECRETS_ENV hardening |
| family-os#31 | no pair | YES | SYNTH-SOURCE | Done when includes human/agent live tests → not mechanizable as-is |
| family-os#30 | no pair | YES | SYNTH-SOURCE | README layer work — not re-classified (HUMAN-dominant, not admitted) |
| family-os#29 | OK (I-3: fix `3b79945`, pre `5938d52`) | YES | REENACT | admitted as t27; FOR-AGENTS doc |
| family-os#28 | OK (I-3: fix `d66aefe`, pre `d221bd8`) | YES | REENACT | admitted as t29; growth-model doc |
| family-os#27 | OK (I-3: fix `a7b0c20`, pre `e6e2fa7`) | YES | REENACT | admitted as t20; evidence.md |
| family-os#26 | OK (I-3: fix `7478c35`, pre `f0ba281`) | YES | REENACT | admitted as t24; publication gate |
| family-os#25 | no pair | YES | SYNTH-SOURCE | Done when includes owner approval → not mechanizable as-is |
| family-os#24 | no pair | YES (epic) | SYNTH-SOURCE | epic; children are the patterns |
| family-os#21 | no pair | YES | SYNTH-SOURCE | Done when includes owner choice → not mechanizable as-is |
| family-os#19 | OK | YES | REENACT | 1 file +4/−7; no repo-wide test cmd → custom donecheck (registry checker exists in-repo) |
| family-os#15 | OK | YES | REENACT | 8 files +141/−7; custom donecheck via in-repo render/check tools |
| family-os#12 | OK (I-3: fix `e830a0e`, pre `c48913a`) | YES | REENACT | admitted as t18; registry entry |
| family-os#10 | no pair | NO | INELIGIBLE | |
| family-os#5 | no pair | NO | INELIGIBLE | |
| family-os#2 | no pair | NO | INELIGIBLE | |
| context-kit#1 | OK (I-3: span `286c2a3`..`90d5cfe`, pre = grandparent) | YES | REENACT | admitted as t22; kickoff completion (two-milestone span, declared per r4-3) |
| family-memory-architecture#11 | OK | YES (inline; I-1) | REENACT | 4 files +4/−52; suite `python3 scripts/tests/run_tests.py` |
| family-memory-architecture#4 | OK | YES (inline; I-1) | REENACT | 10 files +134 |
| family-memory-architecture#3 | OK | YES (inline; I-1) | REENACT | 9 files +123/−14 |
| family-memory-architecture#2 | OK | YES (inline; I-1) | REENACT | 6 files +119/−17 |
| family-memory-architecture#1 | OK (I-2 corrected: fix `8676d838`, pre `25b426bb` = parent[1]; reverse-merge-then-ff) | YES (inline; I-1) | REENACT | admitted as t12; 4 files +84 refers to the surveyed (wrong) pair — the corrected pair's delta is the stdlib port |
| self-growth-loop#1 | OK | YES | REENACT | 1 file +6; suite `bash tests/run.sh` |

## 4. Totals

- REENACT: **32** after I-3 (18 surveyed + 14 re-classified); of the surveyed 18, 2 flagged `size-risk` (harness#56, #27)
- **Admitted bundle: 30 of the 32 REENACT candidates.** Selection rule (recorded per panel finding): the two `size-risk` rows (harness#56, #27) are excluded, exercising this ledger's pre-registered option ("16 if both size-risk tasks are dropped"); every other REENACT candidate is admitted. Task-id mapping is in the batch reports (t01–t30).
- Provenance is two-tier and published as a limitation: the surveyed 18 pairs are GitHub-API-verified (merge SHA, parent linkage); the 14 I-3 pairs rest on issue-referencing commit subjects verified by content inspection, with the R11 validity gate as the mechanical backstop (I-2 is the recorded example of a wrong pre-tree failing loudly there).
- SYNTH-SOURCE: **5 remaining** (post-I-3: family-os#31/#30/#25/#24/#21 — HUMAN-dominant or epic; none admitted)
- INELIGIBLE: **5**

Bundle math against the frozen decision (A′ = 30 base, up to 40): **30 re-enactments / 0 synthetic** (I-3). The pre-I-3 math ("18 re-enactments + 12–14 synthetic reach 30") is superseded; synthetic type-completion remains available only as the documented fallback if a §5-class task swap is ever needed post-sealing (amendment procedure).

Every task admitted into the bundle gets a per-task row in the bundle manifest (task id ↔ source ↔ SHAs ↔ donecheck hash); this ledger is published with the manifest (design §4).
