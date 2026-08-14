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
