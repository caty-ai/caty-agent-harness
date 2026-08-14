# t15 units ledger

Units: 4 total; covered 4/4
MECH: 4
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `injection-budget-check` has one bundled input that exits 0 on a clean clone. | `a01` (T3 command-exit: run the validator against `manifests/fixtures/fixed-injection.yaml` with an isolated temporary `HOME`). The command names a replica-local path visible in `donecheck.sh`; an honest solver can create or revise that input without any out-of-replica canonical source. |
| U2 | MECH | `injection-lint` has one bundled input that exits 0 on a clean clone. | `a02` (T3 command-exit: run the validator against `manifests/fixtures/injection --all` with an isolated temporary `HOME`). The probe uses only replica-local validator contracts and input files. |
| U3 | MECH | `watchdog` has one bundled input that exits 0 on a clean clone. | `a03` (T3 command-exit: run the validator against `manifests/fixtures/jobs.yaml` with an isolated temporary `HOME`). The probe uses only replica-local validator contracts and input files. |
| U4 | MECH | A README or the repository map points to the green fixture set in one line. | `a04` (T1 content-presence: one line in a root README or `docs/repository-map.md` contains `fixture`/`fixtures` together with `validator` or `smoke`). The small needles pin the discoverability claim, not the historical fix sentence. |

Anonymization mapping: the public source repository is referred to as “this
repository”; the three validator names and their repository-local paths remain
because they are the criterion's targets and are already derivable from the
pre-fix tree. No criterion-constitutive out-of-replica identifier was removed.
