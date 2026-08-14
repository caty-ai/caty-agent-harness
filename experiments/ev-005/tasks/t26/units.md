# t26 units ledger

Units: 5 total; covered 5/5
MECH: 5
HUMAN: 0
MOOT: 0

Anonymization mapping: the public source repository is “this repository.”
Public CLI names and paths remain because the completion criterion targets
those surfaces and every identifier is present in the pre-fix replica. Tracker
numbers, commit fingerprints, dates, and person or agent names are omitted.

Frozen-deviation interpretation: “every listed surface conforms” means each
surface either follows the documented house convention or is explicitly
recorded as a frozen/current deviation with a named regression pin. The fix is
documentation-and-pinning work; it intentionally does not normalize all
producers. In particular, warning-prefix outliers remain deferred,
`tr-enqueue` usage remains exit `1` while sibling usage errors use `2`, and
optional diagnostic `FAIL` rows remain compatible with exit `0`. Assertions
must preserve these documented contracts rather than demand behavior changes.

Seven-defect source split: normalized by this fix — none; frozen/documented without producer behavior changes — offending-path omission, reasonless `install.sh` argument usage, `task-runner` usage omitting mandatory `TR_SPAWN_STEP`, `tr-enqueue` usage exit `1`, three warning-prefix styles, `--check` failure rows on stdout while warnings use stderr, and optional `FAIL` rows with exit `0`; the actual pre/fix diff adds only the conventions note and its pinning test.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | A conventions note defines the warning prefix and records current outliers as frozen/deferred deviations. | `a01` (T1 content-presence with small semantic anchors: the output-prefix section, `warning:`, `WARN:`, `WARNING:`, `FROZEN`, and an outlier/defer/deviation term). The variant prefixes are source-listed behavior, not historical prose. |
| U2 | MECH | The note defines exit codes and records deliberate deviations, including enqueue usage `1` and optional `FAIL` with exit `0`. | `a02` (T1/T6: exit-code table rows exist, the enqueue deviation is named, and short semantic fragments record deviation/overload plus optional-FAIL success). Exact exit numbers and CLI name are criterion-constitutive. |
| U3 | MECH | Machine rows use stdout and human warnings use stderr. | `a03` (T1 paragraph-level co-location of the small concepts `stdout`, `stderr`, `machine`, and `warning:`). This admits alternative explanatory prose. |
| U4 | MECH | Every listed surface is conforming or a recorded deviation, with regression pins inventoried. | `a04` (T1: short pre-fix-derived producer and test-path identifiers cover missing-path rows, enqueue/task-runner/updater surfaces, stream/prefix tests, optional-FAIL tests, and the new conventions pin). This mechanizes the author ruling through the note rather than requiring the intentionally deferred normalizations. |
| U5 | MECH | Focused tests pin the conventions and pass without side effects. | `a05` (T6 structural: the focused test pins sibling usage exit `2`, enqueue's recorded exit `1`, and its side-effect-free assertion) plus `a06` (T3 command-exit: `bash tests/cli-conventions.test.sh`). The source criterion explicitly requires pinning tests, so the focused module is the narrowest named runnable check. |

Needle and solvability audit: all needles are short convention tokens, public
paths, or exact exit codes stated in `task.md` and derivable from the replica.
No full historical prose sentence or out-of-replica canonical blob is pinned.
Default timeout remains 120 seconds.

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, person, date, and tracker provenance is omitted. Public CLI
  names, paths, prefixes, and exit values remain because U1–U5 target them and
  they are present in the pre-fix replica.
- Longest T1/T4 needle: `tests/check-tickprobe.test.sh` (30 characters). It is
  a tracked public regression path already present in the pre-fix replica;
  convention prose is checked with shorter tokens.
- Timeout remains the default 120 seconds because the gate runs one focused
  conventions regression plus a bounded structural Python check, not the full
  repository suite.
