# t16 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `recall` rejects a credentials env file whose mode is not `0600`, with a clear error message. | `a02` (T5 behavior probe: create a temporary mode-`0644` env file outside the repository, call `recall`'s env parser, and require rejection text that identifies `0600` plus the actual mode or the word `mode`). |
| U2 | MECH | A regression test covers acceptance of a credentials env file whose mode is `0600`. | `a01` (T5 behavior probe of the accepted mode), `a03` (T6 structural probe: a `test_*` function reaches `parse_supermemory_env`, a mode-`0600` chmod, and a success assertion), and `a05` (T3 command-exit: targeted `python3 scripts/tests/test_recall.py`). The structural probe follows test-local helper calls, so it does not pin a historical test name or prose sentence. |
| U3 | MECH | A regression test covers rejection of a credentials env file whose mode is not `0600`. | `a02` (T5 rejection behavior), `a04` (T6 structural probe: a `test_*` function reaches `parse_supermemory_env`, a non-`0600` chmod, and an exception assertion), and `a05` (the same targeted T3 module exit). |
| U4 | MECH | `docs/recall-usage.md` documents that `recall` enforces mode `0600` for the credentials env file. | `a06` (T1 content-presence: one line co-locates the small needles `recall`, `0600`, and `requir`/`reject`/`enforc`; the alternatives admit natural phrasing without pinning the historical fix sentence). |

Anonymization mapping: the public source repository is referred to as “this
repository”; the public script and documentation paths remain because they are
the criterion's targets and are derivable from the pre-fix tree. Mode `0600`
is retained because it is criterion-constitutive and is also documented in the
pre-fix tree. No out-of-replica canonical content is pinned.
