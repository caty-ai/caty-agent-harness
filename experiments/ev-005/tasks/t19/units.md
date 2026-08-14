# t19 units ledger

Units: 5 total; covered 5/5
MECH: 5
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | A valid `KEY=VALUE` assignment is exported to the scheduler target. | `a01` (T5 behavior probe: copy the production wrapper to a temporary location, provide a mode-`0600` env file, run an isolated target, and require the target to observe the assigned value). |
| U2 | MECH | Shell syntax in a value remains inert data. | `a02` (T5 behavior probe with a syntactically valid value containing `$(touch ...)`; require no side-effect file and require the target to receive the literal value). This instantiates the source criterion's first allowed resolution—data parsing with no shell execution. The alternative “explicitly documented and constrained shell-source contract” was a mutually exclusive design option, not an additional claim; the historical fix selected the safer data-only contract exposed in this task sheet. |
| U3 | MECH | A `SECRETS_ENV` symlink is refused before the target runs. | `a03` (T5 behavior probe: point the configured path at a mode-`0600` regular-file target through a symlink; require wrapper failure, no target marker, and a diagnostic identifying `SECRETS_ENV` and the symlink). |
| U4 | MECH | Regression coverage exercises data-only loading. | `a04` (T6 structural discovery across `tests/*.test.sh`: require a wrapper/`SECRETS_ENV` test to combine a would-be `touch` side effect, the `KEY=VALUE` contract, and protected file mode). Test filename, function name, and historical assertion prose are not pinned. |
| U5 | MECH | Regression coverage exercises symlink refusal. | `a05` (T6 structural discovery: require a wrapper/`SECRETS_ENV` test with an `ln -s` fixture, symlink expectation, and protected file mode). `a03` independently proves the production behavior. |

## Anonymization and needle record

- Mapping: the source repository is “this repository,” and the scheduler
  template is described by function; issue, parent issue, commit, person, and
  date provenance is omitted.
- `SECRETS_ENV` and `KEY=VALUE` remain because the source criterion names these
  public contracts and the pre-fix tree already contains them.
- Longest T1/T4 needle: none. T6 test discovery uses only short functional
  tokens (`cron-wrapper.tmpl.sh`, `SECRETS_ENV`, `KEY=VALUE`, `ln -s`,
  `symlink`, and `touch`) rather than historical test names or prose.
- Timeout remains the default 120 seconds. The direct wrapper probes are local
  and isolated; the repository's broader deadman suite is not run.
