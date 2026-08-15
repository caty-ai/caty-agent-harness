# t21 units ledger

Units: 6 total; covered 6/6
MECH: 6
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The design contract defines six fields for verified skills while allowing drafts to omit verification metadata. | `a01` (T1 content-presence: the `Skill frontmatter` section co-locates the six field identifiers and the `verified skills` condition). |
| U2 | MECH | The staging template carries draft metadata and explains that verification fields are added at promotion. | `a02` (T1 content-presence in `skills/_staging/SKILL.tmpl.md` using only the field identifiers, `status: draft`, `source:`, and the short `promot` stem). |
| U3 | MECH | A verified skill missing `verified_at` and `verifier_id` emits one skill-lint warning for each field. | `a03` (T5 behavior probe: initialize a temporary workspace, add a verified skill without the two fields, and require both warning rows). The source phrase “fails the lint” is interpreted under its own “or the contract is amended” alternative and the implemented amended contract: this lint is advisory, so a warning row is the failure signal. |
| U4 | MECH | Draft skills may omit verification metadata, and complete verified skills do not receive missing-field warnings. | `a04` (T5 behavior probe of one draft and one complete verified skill). |
| U5 | MECH | Verification-field warnings do not change `install.sh --check` exit semantics. | `a05` (T5 behavior probe: compare the same initialized workspace before and after adding the invalid verified skill and require equal exit status). This explicitly preserves the advisory lint contract rather than turning the warning into a command failure. |
| U6 | MECH | A targeted regression test covers the conditional warnings and unchanged exit status. | `a06` (T6/T3: discover a tracked `tests/*.test.sh` containing the criterion tokens `status: verified`, `missing verified_at`, `missing verifier_id`, and `exit status`, then execute it). The test filename is not pinned, so an honest alternative test layout remains admissible. |

## Pair sanity, anonymization, and needle record

- Pair: fix `875acb9071e366530efce45fdbb4dc8d22605e17`; resolved parent pre-fix `06b763ab6d2ac0d946ac5220a16b5e210a1251e3`. The fix is an ancestor of `origin/main`.
- Central spot check before authoring: neither conditional-warning string nor the matching regression case exists at pre-fix; both missing-field warning checks and the unchanged-exit regression case exist at the fix.
- Interpretation ruling: the six-field lint is advisory. A verified skill missing verification fields produces warnings, and `--check` retains its prior exit status. This is the source criterion's amended-contract branch, not a silent weakening.
- Warning-row-over-`FAIL`-row ruling: the warning form wins over the available `FAIL`-row form because the fix's actual amended contract pins warnings plus unchanged `install.sh --check` exit semantics; the acceptance seat's dissent is acknowledged.
- Mapping: the source harness repository is rendered as “this repository,” matching the established harness stand-in. Paths and field names remain because they are criterion targets or are derivable from the pre-fix tree.
- Longest fixed T1/T4 needle: `skills/_staging/SKILL.tmpl.md` (31 characters, a criterion target path). No T1/T4 assertion pins a sentence of historical fix prose.
- Timeout remains the default 120 seconds; only one focused repository test and temporary-workspace probes run.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Replace the first `verifier_id` in `DESIGN.md` with `verifier_id for verified skills` and append the shell comment `verified_at: verifier_id: promotion` to `skills/_staging/SKILL.tmpl.md`, without fixing the verifier contract.
- Route: `a`
- Expected result: `a03` and `a06` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a03`, `a06`; `RUN t21 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t21.log`.
- Rationale: Surface wording alone does not satisfy the clean conditional-warning path or the required nonfatal exit behavior.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t21.log` (current pre-leg record).
- a04 — invariance guard: The pre-fix tree already keeps the warning path clean, so this PASS protects the nonfatal warning contract.
- a05 — invariance guard: The pre-fix tree already exits non-fatally on the expected path, so this PASS is a deliberate guard.
