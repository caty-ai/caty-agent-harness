# t14 units ledger

Units: 8 total; covered 8/8
MECH: 5
HUMAN: 1
MOOT: 2

Anonymization mapping: the source repository is the "family map" and the
published component is the "self-growth module." Public repository identifiers
that are part of the completion criterion remain verbatim as described below.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The `self-growth-loop` registry entry has repository target `caty-ai/self-growth-loop`. | `a01` (T6 structural: parse `registry/modules.json`, require exactly one `self-growth-loop` module, and compare its `repo` value). `caty-ai/self-growth-loop` is criterion-constitutive: the source Done when names it and the pre-fix tree contains zero occurrences, so it remains verbatim in `task.md`; anonymization-sweep exemption recorded here. |
| U2 | MECH | The registry entry's status is `published`. | `a02` (T6 structural JSON field comparison). |
| U3 | MECH | The registry entry's license is `MIT`. | `a03` (T6 structural JSON field comparison). |
| U4 | MECH | The registry entry enables the family footer with `true`. | `a04` (T6 structural JSON boolean comparison). |
| U5 | HUMAN | `tools/check_registry.py` passes. | Weakened (HUMAN→MECH extraction) to the deterministic local core by `a05` (T3 command-exit: `python3 -B tools/check_registry.py --offline`). `--offline` is required by the sealed no-network environment and retains the tool's local registry/link/status checks; lost: its live anonymous-hosting reality probe, which requires external interaction unavailable in the replica. |
| U6 | MECH | The family-footer self-test passes. | `a06` (T3 command-exit: `python3 -B tools/selftest_family_footer.py`, the in-repo self-test named by the source criterion). |
| U7 | MOOT | As a follow-up, family footers are synchronized across published sibling repositories according to `docs/family-footer-contract.md`. | Dropped (MOOT: the task is an offline, single-repository history-zero replica; sibling repositories and their synchronized working trees are absent, and the source explicitly classifies this work as a follow-up rather than part of the registry change). |
| U8 | MOOT | Each sibling follow-up is a separate mechanical commit. | Dropped (MOOT: commit topology and sibling-repository process state do not exist in the history-zero replica). |

## Anonymization, needles, and timeout

- Mapping: the source repository is called the family map and the published
  component is called the self-growth module. Public identifiers named by the
  criterion remain verbatim; owner and process provenance are omitted.
- Longest T1/T4 needle: none. Registry values are parsed structurally; the
  longest fixed value, `caty-ai/self-growth-loop`, is explicitly named in the
  criterion and task sheet rather than copied from historical fix prose.
- Timeout remains the task's default 120 seconds. The two repository checks
  and four local JSON-field probes complete well within the default; no full
  suite or network check is run.
