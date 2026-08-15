# t04 units ledger

Units: 9 total; covered 9/9
MECH: 8
HUMAN: 1
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `docs/trial-isolation.md` names the public collection-pipeline repository behind the first T2 prerequisite. | `a01` (T1 content-presence of `caty-ai/x-collector` in `docs/trial-isolation.md`). Author revision r1: the target repository is named in task.md — it is criterion-constitutive (the source Done when names it; the pre-fix tree contains zero occurrences, so it is not derivable in-replica). Anonymization-sweep exemption recorded here per brief rule. |
| U2 | MECH | `docs/trial-isolation.md` links that repository. | `a02` (T1 content-presence of the full URL). Author revision r1: was a T6 exact-line hash of the historical fix line (included line-wrap context "Trials that"), which asserted formatting beyond the unit and was unsatisfiable without knowing the redacted target — replaced by URL presence. |
| U3 | MECH | `docs/trial-isolation.md` states that qualifying trials go through that pipeline. | `a03` (T1 content-presence in `docs/trial-isolation.md`). Author revision r1: was an exact fix-prose sentence pin; relaxed to a phrasing-tolerant pattern (`(through|via) (that|the|this) (collection )?pipeline`, case-insensitive) so honest paraphrases pass. |
| U4 | MECH | `docs/trial-isolation.md` states that those trials inherit the pipeline's collection controls. | `a04` (T1 content-presence in `docs/trial-isolation.md`). Author revision r1: relaxed from two exact fix-prose fragments to co-presence of `inherit` + `collection controls`. |
| U5 | MECH | The first T2 condition remains that the collection-controls prerequisite is closed. | `a05` (T1 content-presence in `docs/trial-isolation.md`) |
| U6 | MECH | The second T2 condition remains explicit owner pre-approval of the concrete trial plan. | `a06` (T6 structural: exact condition line hash in `docs/trial-isolation.md`) |
| U7 | MECH | The T2 isolation string in `scripts/trial-enqueue.sh` stays unchanged. | `a07` (T6 structural: exact T2 string line hash in `scripts/trial-enqueue.sh`) |
| U8 | MECH | The T2 row in the normative tier table in `docs/adoption-wiring.md` stays unchanged. | `a08` (T6 structural: exact T2 row line hash in `docs/adoption-wiring.md`) |
| U9 | HUMAN | No other private-reference wording is introduced. | Weakened (HUMAN→MECH extraction): keep a narrow textual proxy by requiring `docs/trial-isolation.md` to contain no more `private` occurrences than the two pre-existing ones. Lost: semantic judgment about whether a newly introduced phrase is effectively a private-reference concern even without the literal word `private`, and diff/provenance judgment outside this file. Covered by `a09` (T4 content-absence proxy). |

## Anonymization and needle record

- Mapping: the source repository is rendered as “this repository”, the named
  owner is rendered as “the owner” in the task sheet, and issue/tracker
  provenance is omitted. `caty-ai/x-collector` and its public URL remain because
  the source criterion names that exact dependency; the legacy `Sho` token
  remains only inside the pre-fix-derived lines that U6–U8 require to stay
  unchanged.
- Longest structural needle: the complete 205-character T2 table row
  in `docs/adoption-wiring.md`, checked by `a08` through its line hash. The row
  exists verbatim in the pre-fix tree and U8 explicitly requires it to stay
  unchanged, so it is replica-derivable rather than historical-fix prose.
- Timeout remains the default 120 seconds. The gate performs only bounded local
  file-presence, grep/count, and line-hash checks and executes no repository
  code, so no escalation is needed.

## REV6 validation evidence (r3-4)

- Fresh 5+5 history-zero validation: pre exit/duration pairs were `1/0s` five times; fix pairs were `0/0s`, `0/1s`, `0/0s`, `0/1s`, `0/0s`. `VERDICT PASS`, no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/t04.log`.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append one HTML comment containing `caty-ai/x-collector`, its GitHub URL, `through that pipeline`, and `inherit collection controls` to `docs/trial-isolation.md`, without changing the live wiring or isolation behavior.
- Route: `a`.
- Expected and measured result after REV6: `a01`–`a03` FAIL because the injected repository, URL, and routing strings occur only inside the HTML comment.
- Evidence status: REV5 recorded `UNEXPECTED_PASS_CONFIRMED` (`exit=0`, `dur=0s`); the fresh REV6 run records `EXPECTED_FAIL_CONFIRMED` with `a01`–`a03` (`exit=1`, `dur=0s`, no `DIRTY_TREE`) in `experiments/ev-005/tools/validate-logs/negprobe/t04.log`.
- REV6 r4-1-style tightening: fixed, regex, co-presence, line-hash, and count surfaces now consume visible content after non-greedy, multiline HTML-comment stripping, with hashes, patterns, counts, and IDs unchanged.
- Route-b visible-prose record: Visibly inserting the asserted public-pipeline documentation is indistinguishable from doing the documentation work itself, so there is no honest superficial-edit FAIL claim and no separate visible-prose run.
- Rationale: REV6 closes the demonstrated comment-only surface without changing the documented public-pipeline criterion.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t04.log` (current pre-leg record).
- a04 — oversight: File-wide inherited/collection-controls wording elsewhere in the asserted doc lets this PASS without proving the specific wiring fix.
- a05 — invariance guard: The pre-fix tree already keeps the closed prerequisite wording, so the PASS guards against reopening it.
- a06 — invariance guard: The owner-preapproval SHA requirement already holds on the pre tree, so the PASS is a deliberate guard.
- a07 — invariance guard: The T2 isolation wording already exists pre-fix, so the PASS protects that invariant.
- a08 — invariance guard: The row-level constraint already holds pre-fix, so the PASS is guarding against regression.
- a09 — invariance guard: The private-count constraint already holds on the pre tree and is intentionally constant-true.
