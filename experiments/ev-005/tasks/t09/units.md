# t09 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The default generated-artifact permission policy accepts a current-user, mode-`0600` artifact whose gid differs from the process group. | `a01` (T5 behavior probe under an invocation-specific fresh `HOME` and `TMPDIR`: load `scripts/family-hot-generate`, simulate an unpinned expected gid different from the artifact gid while preserving uid, and require no permission issues plus mode `0600`). This extracts the deterministic permission-check core of “a normal user can run the quickstart in a group-foreign directory”; lost: exercising every quickstart command and OS-specific real group inheritance. |
| U2 | MECH | A pinned `FMA_EXPECT_OWNER` policy still rejects a uid mismatch. | `a02` (T5 behavior probe under its own fresh `HOME` and `TMPDIR`, with a non-empty pinned-owner configuration and an otherwise-correct artifact whose uid differs from the pinned uid; requires rejection). |
| U3 | MECH | A pinned `FMA_EXPECT_OWNER` policy still rejects a gid mismatch. | `a03` (T5 behavior probe under its own fresh `HOME` and `TMPDIR`, with a non-empty pinned-owner configuration and an otherwise-correct artifact whose gid differs from the pinned gid; requires rejection). |
| U4 | MECH | Repository tests cover both the default acceptance and pinned group-mismatch rejection paths. | `a04` (T6 structural Python-AST probe under its own fresh `HOME` and `TMPDIR` over test functions: requires separate test bodies that exercise `enforce_generated_artifact_permissions`, one with an unpinned gid case and an empty-issues assertion, and one with `FMA_EXPECT_OWNER`, a gid case, and a rejection assertion). The probe is phrasing- and test-name-independent; it checks the semantic test ingredients rather than historical method names. |

## Anonymization and needle record

- Mapping: the source repository is described as a shared-memory toolkit and
  its generated artifact rather than by issue/tracker provenance.
- Anonymization-sweep exemption: `FMA_EXPECT_OWNER` is retained because it is
  a criterion-constitutive public configuration identifier named by the source
  Done when and present in the pre-fix tree.
- Longest fixed structural needle: `scripts/tests/test_family_hot_generate.py`
  (41 characters). It is the tracked pre-fix test module inspected by the
  structural coverage probe, not a path introduced by the historical fix.
- Timeout remains the default 120 seconds. The gate runs three bounded behavior
  probes and one local AST probe; every invocation receives a separate fresh
  `HOME` and `TMPDIR` and is cleaned up immediately after it completes.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append two no-op test functions whose docstrings carry the asserted permission-probe AST tokens to `scripts/tests/test_family_hot_generate.py`, without changing the real permission logic.
- Route: `a`
- Expected result: `a01` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a01`; `RUN t09 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t09.log`.
- Rationale: AST-visible dead code cannot satisfy the live UID/GID mismatch invariant that the real probe enforces.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t09.log` (current pre-leg record).
- a02 — invariance guard: The pre-fix permission probe already preserves the pinned UID invariant, so this PASS is a non-regression guard.
- a03 — invariance guard: The pre-fix permission probe already preserves the pinned GID invariant, so this PASS is another deliberate guard.
