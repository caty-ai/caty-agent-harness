# EV-005 task-candidate eligibility ledger

- Normative design: caty-ai/caty-agent-harness#63 (design v2.1, frozen 2026-08-13)
- Survey input: fact table of 42 closed issues (surveyed by alec-bridge, 2026-08-13, public sources only)
- Inspection: Alpha (alpha-mbp-bridge), 2026-08-13. Every fact below was re-verified against the GitHub API by the inspector; the survey itself was never treated as authority.

## 1. Inspection method and results

| check | method | result |
|---|---|---|
| fix SHA exists | `GET /repos/{repo}/commits/{fix}` | 18/18 OK |
| pre_fix = first parent of fix | parent[0] of fix commit compared to pre_fix | 18/18 OK |
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
| caty-agent-harness#30 | no pair (multi-PR, unidentified) | YES | SYNTH-SOURCE | labels/required-checks pattern |
| caty-agent-harness#27 | OK | YES | REENACT | size-XL (25 files, +1826/−299) — flag `size-risk` |
| caty-agent-harness#23 | no pair | YES | SYNTH-SOURCE | lint/template contract pattern |
| caty-agent-harness#22 | no pair | YES | SYNTH-SOURCE | failure-visibility pattern |
| caty-agent-harness#21 | no pair | YES | SYNTH-SOURCE | conventions-note pattern |
| caty-agent-harness#20 | no pair | YES | SYNTH-SOURCE | input-validation pattern |
| caty-agent-harness#19 | no pair | NO (epic container) | INELIGIBLE | children #20–#23 are the actionable units |
| caty-agent-harness#18 | OK | YES | REENACT | 8 files +53/−29 |
| caty-agent-harness#17 | OK | YES | REENACT | 5 files +38/−17 |
| caty-agent-harness#16 | OK | YES | REENACT | 12 files +64/−59 |
| caty-agent-harness#15 | OK | YES | REENACT | 8 files +31/−40 |
| caty-agent-harness#14 | no pair | NO | INELIGIBLE | epic-style body, no own criterion |
| caty-agent-harness#12 | no pair | YES | SYNTH-SOURCE | fail-closed updater pattern |
| caty-agent-harness#11 | no pair | YES | SYNTH-SOURCE | quote-aware parsing pattern |
| caty-agent-harness#10 | no pair | YES | SYNTH-SOURCE | secrets-parsing pattern |
| family-os#31 | no pair | YES | SYNTH-SOURCE | Done when includes human/agent live tests → not mechanizable as-is |
| family-os#30 | no pair | YES | SYNTH-SOURCE | README layer work |
| family-os#29 | no pair | YES | SYNTH-SOURCE | FOR-AGENTS doc pattern |
| family-os#28 | no pair | YES | SYNTH-SOURCE | growth-model doc pattern |
| family-os#27 | no pair | YES | SYNTH-SOURCE | evidence.md pattern; fail-closed link vetting |
| family-os#26 | no pair | YES | SYNTH-SOURCE | registry-conformance pattern |
| family-os#25 | no pair | YES | SYNTH-SOURCE | Done when includes owner approval → not mechanizable as-is |
| family-os#24 | no pair | YES (epic) | SYNTH-SOURCE | epic; children are the patterns |
| family-os#21 | no pair | YES | SYNTH-SOURCE | Done when includes owner choice → not mechanizable as-is |
| family-os#19 | OK | YES | REENACT | 1 file +4/−7; no repo-wide test cmd → custom donecheck (registry checker exists in-repo) |
| family-os#15 | OK | YES | REENACT | 8 files +141/−7; custom donecheck via in-repo render/check tools |
| family-os#12 | no pair | YES | SYNTH-SOURCE | registry-entry pattern |
| family-os#10 | no pair | NO | INELIGIBLE | |
| family-os#5 | no pair | NO | INELIGIBLE | |
| family-os#2 | no pair | NO | INELIGIBLE | |
| context-kit#1 | no pair | YES | SYNTH-SOURCE | generalization/de-personalization pattern |
| family-memory-architecture#11 | OK | YES (inline; I-1) | REENACT | 4 files +4/−52; suite `python3 scripts/tests/run_tests.py` |
| family-memory-architecture#4 | OK | YES (inline; I-1) | REENACT | 10 files +134 |
| family-memory-architecture#3 | OK | YES (inline; I-1) | REENACT | 9 files +123/−14 |
| family-memory-architecture#2 | OK | YES (inline; I-1) | REENACT | 6 files +119/−17 |
| family-memory-architecture#1 | OK | YES (inline; I-1) | REENACT | 4 files +84 |
| self-growth-loop#1 | OK | YES | REENACT | 1 file +6; suite `bash tests/run.sh` |

## 4. Totals

- REENACT: **18** (10 harness / 2 family-os / 5 FMA / 1 sgl); of these, 2 flagged `size-risk` (harness#56, #27)
- SYNTH-SOURCE: **19**
- INELIGIBLE: **5**

Bundle math against the frozen decision (A′ = 30 base, up to 40): 18 re-enactments (16 if both size-risk tasks are dropped) + 12–14 synthetic type-completion tasks reach 30; extension toward 40 draws further synthetic tasks from the 19 patterns, gated by the validity tests and non-author acceptance throughput.

Every task admitted into the bundle gets a per-task row in the bundle manifest (task id ↔ source ↔ SHAs ↔ donecheck hash); this ledger is published with the manifest (design §4).
