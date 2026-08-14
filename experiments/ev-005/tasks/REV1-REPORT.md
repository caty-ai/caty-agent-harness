# EV-005 acceptance-driven revision report REV1

## Summary

| Task | Acceptance findings addressed | Revision | Validity |
| --- | --- | --- | --- |
| t03 | B1, Q1 ruling | Replaced the out-of-replica workflow blob pin with equality against a bundled canonical fixture after normalizing the four risk declarations on both sides. | [PASS](../tools/validate-logs/t03.log): pre-fix FAIL 5/5; fix PASS 5/5 |
| t05 | B3 | Restored the two silently dropped binding-fence units and pinned both unchanged in-replica files. | [PASS](../tools/validate-logs/t05.log): pre-fix FAIL 5/5; fix PASS 5/5 |
| t06 | B4, M1, M2, m7, Q2 ruling | Re-derived the task forward from the headline plus adopted scope, added the exact allowlist-backed repo sweep, restored the inventory disjunction, and recorded HUMAN/MOOT process units. | [PASS](../tools/validate-logs/t06.log): pre-fix FAIL 5/5; fix PASS 5/5 |

Every completed run left its replica clean; none of the three logs contains a
`DIRTY-TREE` record.

## t03 — replica-solvable template equality

- Added `fixtures/review-labels-template.yml` from the author-specified fix-tree
  source. Its local blob hash and the source blob hash are both
  `f8957a9ab7d2b2b69bf30505f329350d14b725c2`.
- Removed `EXPECT_WORKFLOW_BLOB` and `check_workflow_blob` (B1). `a01` now uses
  T6 equality against the bundled fixture, with every
  `RISK_PATHS_[A-Z_]+=...` declaration normalized to `@@DECL@@` on both sides.
  Temporary files live under `${TMPDIR:-/tmp}` and are removed by the exit trap.
- Reworded only U1 in `task.md` to make the bundled fixture the visible spec and
  to permit customization only on the four declaration lines.
- Updated U1 and the ledger notes to record the criterion-constitutive fixture
  exemption and why the inadmissible blob pin was removed.
- Validity verdict: **PASS**, supported by
  `experiments/ev-005/tools/validate-logs/t03.log` (five `pre exit=1`, five
  `fix exit=0`, final `VERDICT t03 PASS`).

## t05 — binding wrapper-conformance fence

- Added visible Done when units U38 and U39 for the source's binding fence
  (B3): `scripts/lib-wrapper-conformance.sh` stays byte-identical and
  `tests/wrapper-conformance.test.sh` expectations stay untouched.
- Added ledger mappings U38 to `a40` and U39 to `a41`; the ledger now records
  39 MECH units covered 39/39.
- Added fail-closed exact blob checks using the author-provided, in-replica
  invariance hashes:
  `a4a51b6e8070c5516607c0081b0beef1e44ba8ce` and
  `530091f9034e7873647ac3fbf633f452dac2c994`.
- Validity verdict: **PASS**, supported by
  `experiments/ev-005/tools/validate-logs/t05.log` (five `pre exit=1`, five
  `fix exit=0`, final `VERDICT t05 PASS`). Both new invariance assertions pass
  on both validity legs, as intended.

## t06 — forward derivation and central T4 catalog

- Replaced the reverse-derived 26-unit transcription (B4) with 16 forward units:
  12 MECH, 2 HUMAN, and 2 MOOT. Owner visibility and external review records are
  HUMAN; serial ordering and the live adopted-scope record are MOOT.
- Replaced dated/full-sentence fix needles (M1/M2) with small, replica-derived
  identifiers and behavioral fragments. `task.md` and `donecheck.sh` contain no
  four-digit year and no literal issue/PR number.
- Bundled `fixtures/release-model-allowlist.tsv` as an exact `path<TAB>line`
  catalog. It records the four English/Japanese scope-boundary and release-status
  exceptions. Each entry must exist exactly in its named file; T4 subtraction
  also requires exact path-and-line equality.
- Implemented the criterion's repo-wide mechanism over tracked Markdown. The
  sweep is case-insensitive, includes language variants and
  `docs/plugin-convention.md`, excludes test fixtures, and excludes only the four
  separately asserted historical-design records.
- Preserved the source disjunction for deployment inventory: T6 accepts either
  a placeholder-shaped generic table or an inventory-local dated/internal or
  historical-record marker. It does not require the branch chosen by the
  historical fix.
- Mechanized the troubleshooting evidence core structurally: every diagnostic
  table row whose Meaning is not an em dash must carry a backtick-delimited
  observed literal in its Symptom cell. This permits evidence-backed rewriting
  or deletion without pinning the fix's sentences.
- Validity verdict: **PASS**, supported by
  `experiments/ev-005/tools/validate-logs/t06.log` (five `pre exit=1`, five
  `fix exit=0`, final `VERDICT t06 PASS`).

## Needle audit

| Task | Longest T1/T4 needle | Calibration |
| --- | --- | --- |
| t03 | `(^|/)[^/]*(auth|signin|token)[^/]*$|(^|/)auth/` (46 characters) | Small path/category ERE derived from the visible unit; the template comparison itself is T6 against the bundled source. |
| t05 | `FMA_SCRIPTS_DIR=${FMA_SCRIPTS_DIR:-"$HOME/claude-workspace/family-memory-architecture/scripts"}` (95 characters) | Pre-fix-derived T4 baseline text, not replacement prose. The new a40/a41 checks are T6 invariance hashes, not content needles. |
| t06 | The English scope-boundary catalog line (476 characters) | Deliberately exact only because the source makes recorded allowlist lines the sole exceptions; the line exists in both replica trees and ships in the catalog. The longest ordinary non-catalog needle is the public clone command (59 characters), a replica-derived identifier rather than fix prose. |

No T1/T4 needle contains a date or a sentence introduced by the historical t06
fix. The long t06 exception is pre-existing, criterion-constitutive catalog
content and is exact by design.

## Anonymization and provenance sweep

No dedicated anonymization tool exists under `experiments/ev-005/tools/`, so a
manual recursive grep was run over `t03`, `t05`, and `t06` for issue/PR numbers,
dates, and person/agent names.

- The six arm-visible `task.md`/`donecheck.sh` files contain zero issue/PR-number
  or date hits.
- The byte-exact t03 canonical fixture intentionally retains its source header
  date and internal numbered comments. This is the shipped-spec exemption
  required by B1/Q1; none appears in `task.md` or as an assertion needle.
- t05 retains pre-existing negative baseline needles for `sho-alpha`, `sho`, and
  `Claire's STATE.md`. They identify text that must be removed from the replica;
  this REV1 changed only B3's binding fence.
- t06 hits for `Caty`/`caty-ai` are the public product and repository identifiers
  already self-identified by the replica, plus the four exact release-model
  catalog lines. No historical issue/PR/fix provenance is exposed.

## Review availability

The requested independent external seats were invoked read-only after the diff
was frozen, but none returned a countable review in this sandbox:

| Reviewer | Requested model | Requested effort | Actual model | Result |
| --- | --- | --- | --- | --- |
| Kimi | Kimi K3 | high | no model response | OAuth refresh endpoint DNS resolution failed. |
| Opus | Opus 5 | high | no model response | The standalone Claude CLI had no active login. |
| GLM | GLM 5.2 | high | no model response | The API endpoint could not be resolved. |
| Grok fallback | Grok 4.5 | high | no model response | The CLI produced no output and was stopped after bounded polling. |

These failures do not alter the completed R11 validity verdicts above, but
external review quorum remains unavailable for any later merge/release decision.
