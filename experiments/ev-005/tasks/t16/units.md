# t16 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `recall` rejects a credentials env file whose mode is not `0600`, with a clear error message. | `a02` (T5 behavior probe under invocation-specific fresh `HOME` and `TMPDIR`: create a temporary mode-`0644` env file outside the repository, call `recall`'s env parser, and require rejection text that identifies `0600` plus the actual mode or the word `mode`). |
| U2 | MECH | A regression test covers acceptance of a credentials env file whose mode is `0600`. | `a01` (T5 behavior probe of the accepted mode under its own fresh `HOME` and `TMPDIR`), `a03` (T6 structural probe under a separate fresh `HOME` and `TMPDIR`: a `test_*` function reaches `parse_supermemory_env`, a mode-`0600` chmod, and a success assertion), and `a05` (T3 command-exit: the complete `python3 scripts/tests/test_recall.py` module under fresh `HOME` and `TMPDIR`). A temporary `sitecustomize` makes the current user's passwd-home fallback equal that isolated `HOME`, keeping `~` expansion coherent even when a test clears `os.environ`; no test is skipped or filtered. The structural probe follows test-local helper calls, so it does not pin a historical test name or prose sentence. |
| U3 | MECH | A regression test covers rejection of a credentials env file whose mode is not `0600`. | `a02` (T5 rejection behavior under its own fresh `HOME` and `TMPDIR`), `a04` (T6 structural probe under a separate fresh `HOME` and `TMPDIR`: a `test_*` function reaches `parse_supermemory_env`, a non-`0600` chmod, and an exception assertion), and `a05` (the same complete targeted T3 module under fresh `HOME` and `TMPDIR`, with the isolated passwd fallback described for U2). |
| U4 | MECH | `docs/recall-usage.md` documents that `recall` enforces mode `0600` for the credentials env file. | `a06` (T1 content-presence: one line co-locates the small needles `recall`, `0600`, and `requir`/`reject`/`enforc`; the alternatives admit natural phrasing without pinning the historical fix sentence). |

## Anonymization and needle record

- Mapping: the public source repository is rendered as “this repository”;
  tracker, review-seat, and scheduling-time provenance is omitted.
- Anonymization-sweep exemptions: `recall` and mode `0600` remain because they
  are criterion-constitutive. The public script, targeted test, and usage-doc
  paths remain because they are derivable from the pre-fix tree.
- Longest fixed structural needle: `scripts/tests/test_recall.py` (28
  characters). It is a tracked pre-fix targeted module, not a filename
  introduced by the historical fix; the behavior probes avoid pinning any
  historical regression-test function name or prose.
- Timeout remains the default 120 seconds. One targeted test module plus four
  bounded local probes complete well within the default. Every probe invocation
  and the targeted module receive separate fresh `HOME` and `TMPDIR` values to
  remove workstation-state and concurrency dependence. The module's temporary
  Python startup hook changes only the current user's passwd-home fallback to
  the same fresh home, preventing an environment-clearing test from
  reintroducing the ambient account home.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append two unreachable `if False:` test functions to `scripts/tests/test_recall.py`, one carrying the `chmod(..., 0o600)`/parse/accept tokens and one carrying the `chmod(..., 0o644)`/parse/`assertRaisesRegex(..., "0600")` tokens.
- Route: `a`
- Expected result: `a02` and `a06` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a06`; `RUN t16 negprobe exit=1 dur=2s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t16.log`.
- Rationale: Dead test code cannot satisfy the live 0600 and broader recall-environment behavior checks.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t16.log` (current pre-leg record).
- a01 — invariance guard: The pre-fix tree already preserves the valid `0600` mode, so this PASS protects the permission invariant.
- a05 — invariance guard: The broader recall-environment behavior already holds pre-fix, so this PASS is a deliberate non-regression guard.
