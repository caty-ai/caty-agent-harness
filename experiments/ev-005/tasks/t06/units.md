# t06 faithfulness record

Units: 16 total; covered 16/16
MECH: 12
HUMAN: 2
MOOT: 2

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The agent guide presents a public clone flow and drops the old missing-access diagnosis. | `a01`, `a02`, `a03` (T1 + T4 in `docs/agent-guide.md`). |
| U2 | MECH | The self-contradictory forthcoming-home note is deleted from the agent guide. | `a04` (T4 in `docs/agent-guide.md`). |
| U3 | MECH | The Hermes install guide uses the public clone path and drops invite/deploy-key access wording. | `a05`–`a08` (T1 + T4 in `adapters/hermes/INSTALL.md`). |
| U4 | MECH | The OpenClaw install guide uses the public clone path and drops invite/deploy-key access wording. | `a09`–`a12` (T1 + T4 in `adapters/openclaw/INSTALL.md`). |
| U5 | MECH | The Claude adapter gives a self-contained macOS scheduling explanation in place of an old numbered citation. | `a13`, `a15` (T1 + T4 in `adapters/claude-code/INSTALL.md`). Needle discipline: the positive check uses small criterion-derived fragments (`Keychain`, `LaunchAgent`) rather than fix-sentence wording. |
| U6 | MECH | The Claude adapter gives a self-contained hook-isolation explanation in place of an old numbered citation. | `a14`, `a15` (T1 + T4 in `adapters/claude-code/INSTALL.md`). The positive check uses minimal behavioral fragments (`PreToolUse`, `isolate`, `hooks`) instead of the historical sentence. |
| U7 | MECH | The named historical design-record docs are explicitly fenced as historical before they preserve older tracker context, and the fifth named policy doc participates in the repo-wide public/policy sweep rather than escaping it. | `a16`–`a19` (T1 in `DESIGN.md`, `DESIGN-task-runner.md`, `docs/governance-rules.md`, `docs/updater-rollout.md`) plus `a21` (the dynamic Markdown scope explicitly includes `docs/plugin-convention.md`). This is the mechanized handling of the five named docs from the adopted scope. |
| U8 | MECH | The updater rollout inventory satisfies the original `genericize OR mark as dated internal record` disjunction. | `a20` (T6 structural disjunction over `docs/updater-rollout.md`). The genericized branch is defined structurally: deployment-inventory section/table present, placeholder-shaped data rows present, and no non-placeholder data row remains. The alternate branch is an inventory-local dated/internal/historical callout. No fix-prose placeholders or concrete host identities are pinned. |
| U9 | MECH | The release-model exception allowlist is bundled explicitly and records the four exact English/Japanese exception lines. | `a22`–`a26` (T1 over `.ev005-fixtures/release-model-allowlist.tsv`, with exact `path<TAB>line` matching and existence verification against the named files). This covers both mirrored scope-boundary statements and both public-release/private-development status statements. |
| U10 | MECH | Across tracked Markdown in the replica, no private-access wording remains outside the recorded allowlist. | `a27` (T4 content-absence over `git ls-files '*.md'`, excluding only `tests/fixtures/**` and the four separately header-verified historical-design records: `DESIGN.md`, `DESIGN-task-runner.md`, `docs/governance-rules.md`, and `docs/updater-rollout.md`). `docs/plugin-convention.md` is intentionally part of this repo-wide sweep. |
| U11 | MECH | Across the same repo-wide sweep, no invite-or-deploy-key onboarding wording remains outside the recorded allowlist. | `a28` (T4 over the same dynamic file set and exact-line allowlist). |
| U12 | MECH | Across the same repo-wide sweep, no private citation framing or forthcoming-home note remains outside the recorded allowlist; the surviving troubleshooting rows are keyed to concrete observed literals rather than guessed diagnoses. | `a29`, `a30` (T4 + T6 in `docs/agent-guide.md`). Weakening recorded: the full evidence gate is not reducible to an exact troubleshooting row inventory, so the mechanizable core is a repo-wide absence sweep plus a structural table rule: every troubleshooting data row whose Meaning cell is not an em dash must carry a backtick-delimited observed literal in the Symptom cell. |
| U13 | HUMAN | The updater inventory branch choice is surfaced in owner-review process records. | Dropped (HUMAN: owner-visibility or review-record state is not present in the offline replica). The mechanized core is U8's structural disjunction. |
| U14 | HUMAN | Every allowed exception line is recorded in owner-facing review material. | Dropped (HUMAN: the external review record is unavailable in the offline replica). Extracted behavioral core: the task ships `fixtures/release-model-allowlist.tsv` as the visible exact-line exception ledger (U9). |
| U15 | MOOT | The serial blocked-by ordering across sibling tasks is respected. | Dropped (MOOT: the offline replica carries only the content state, not the live issue queue or serial execution context). |
| U16 | MOOT | The adopted-scope review event itself exists as a linked process record. | Dropped (MOOT: the offline replica does not contain the live review thread; only the resulting content criterion is testable here). |

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, person, date, and live publication provenance is omitted.
  Public project names and the four release-model exception lines remain only
  where the criterion makes them the exact allowlist-backed scope boundary.
- Longest T1/T4 needle: the 476-character English scope-boundary catalog line
  in `.ev005-fixtures/release-model-allowlist.tsv`. Exactness is required by
  U9/U10 and is derivable because the same line ships in the in-replica catalog
  and exists in both pair legs; the longest ordinary non-catalog needle is the
  59-character public clone command.
- Timeout remains the default 120 seconds because the gate performs bounded
  tracked-Markdown enumeration and exact-line/regex sweeps without executing
  repository code.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Add positive-needle HTML comments to `docs/agent-guide.md` and the Hermes/OpenClaw/Claude INSTALL files; wrap the existing `Clone fails with auth error` symptom in backticks; append `Historical design record.` comments to `DESIGN.md`, `DESIGN-task-runner.md`, `docs/governance-rules.md`, and `docs/updater-rollout.md`; and append a `## Deployment inventory` section containing `historical record` to `docs/updater-rollout.md`, without removing private-era wording.
- Route: `a`
- Expected result: `a03`, `a04`, `a07`, `a08`, `a11`, `a12`, `a15`, and `a27`-`a29` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a03`, `a04`, `a07`, `a08`, `a11`, `a12`, `a15`, `a27`, `a28`, `a29`; `RUN t06 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t06.log`.
- Rationale: The guard set still checks live explanation parity, allowlist counts, and status-line behavior that comments do not repair.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t06.log` (current pre-leg record).
- a13 — invariance guard: The pre-fix tree already contains the existing Keychain/LaunchAgent explanation, so the PASS protects source parity.
- a21 — invariance guard: The policy-sweep inclusion already holds on the pre tree, so the PASS guards against removing it.
- a22 — invariance guard: The allowlist-count expectation already holds pre-fix and intentionally stays constant-true.
- a23 — invariance guard: The documentation parity around the allowlist count already holds before the fix, so this PASS is a deliberate guard.
- a24 — invariance guard: The status-line wording already exists on the pre tree and is being protected, not discriminated.
- a25 — invariance guard: The paired status-line wording already holds on the pre tree, so the PASS is another source-parity guard.
- a26 — invariance guard: The final status-line/document parity already holds pre-fix; this PASS intentionally prevents regression.
