# t27 units ledger

Units: 15 total; covered 15/15
MECH: 12
HUMAN: 2
MOOT: 1

Anonymization mapping: the source repository is called the "map repository";
the organization name, parent-work item, issue references, drafting checkpoint,
owner identity, and dates are omitted. Repository-local paths and the exact
`Fork the idea` phrase remain because the source completion criterion makes
them part of the required artifact.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | HUMAN | A Japanese draft is posted before the repository artifact is written. | Dropped (HUMAN: issue-comment publication and its ordering require live tracker history outside the replica). |
| U2 | HUMAN | The draft has an owner-approval record. | Dropped (HUMAN: approval is an external human decision and live-platform record). |
| U3 | MECH | The root artifact is English `FOR-AGENTS.md`, with no localized sibling artifact. | `a01` (T2 path existence/absence: require `FOR-AGENTS.md` and reject root `FOR-AGENTS.*.md` siblings). English prose quality beyond the structural and semantic checks below remains a human-language judgment. |
| U4 | MECH | `FOR-AGENTS.md` has eight numbered sections. | `a02` (T6 structural: the level-two numbered headings are exactly 1 through 8). |
| U5 | MECH | The opening explains the file's purpose and provides 5-minute and 30-minute tours. | `a03` (T1 content-presence inside section 1 of the two criterion-constitutive time-budget labels plus visitor/purpose language). |
| U6 | MECH | The authority order is registry, growth model, evidence, then repository READMEs. | `a04` (T6 structural: extract the four ordered-list path targets in section 2 and compare their order). The paths are named by the source criterion and exist in the replica. |
| U7 | MECH | The four independent state axes and their vocabulary are introduced. | `a05` (T1 content-presence inside section 3 of the four axis names and the replica-derived state values). |
| U8 | MECH | The evaluation frame covers consistency, plain/durable technology, state discipline, and structural human gates. | `a06` (T1 content-presence inside section 4 using small semantic fragments for the four required topics). |
| U9 | MECH | A repository tour table gives a role and verification target per row. | `a07` (T6 structural: section 5 contains a Markdown table with repository, role, and verification columns). |
| U10 | MECH | Counter-evidence goes to a public issue and uses only publicly shareable evidence. | `a09` (T1 content-presence inside section 6 using short `public issue` and public-evidence fragments). |
| U11 | MECH | The handoff schema has five named fields and a stop rule against inference. | `a10` (T6/T1: section 7 contains each field label and co-locates the stop rule with `inference` and `unresolved`). The field names are criterion-constitutive. |
| U12 | MECH | A human handoff paragraph and `Fork the idea` invitation are supplied. | `a11` (T6/T1: section 8 contains a Markdown blockquote and the exact source-required phrase). `Fork the idea` is exempt from the anonymization sweep because the source Done when quotes it. |
| U13 | MECH | Tour rows equal the registry's complete `published` module set. | `a08` (T6 structural: parse `registry/modules.json`, extract repository URLs from section 5 table rows, and compare exact sets). The registry is the in-replica canonical source, satisfying r2. |
| U14 | MECH | Automatic discovery is explicitly not guaranteed. | `a12` (T1 content-presence inside section 1, requiring `automatic discovery` and a nearby negative guarantee). |
| U15 | MOOT | The task owns only `FOR-AGENTS.md`. | Dropped (MOOT: the history-zero fix snapshot contains no source diff or issue-lane ownership record from which to prove which files this task changed). The gate remains scoped to `FOR-AGENTS.md` and the registry source it reads. |

Needle calibration and solvability:
- Longest fixed T1/T4 phrase is `automatic discovery` (19 characters); it is
  source-required wording, not a historical prose sentence.
- The authority paths, schema fields, time budgets, and `Fork the idea` are
  named in task.md. State values and the published-module set are derived from
  replica-local canonical sources.
- Timeout remains the default 120 seconds; all checks are local parsing only.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Create only an eight-section `FOR-AGENTS.md` skeleton and give it a bogus `caty-ai/not-real` tour row, without changing any registry or growth-model source.
- Route: `a`
- Expected result: `a08` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a08`; `RUN t27 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t27.log`.
- Rationale: The bogus repository target leaves the criterion-defining registry linkage unsatisfied.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t27.log` shows no constant-true assertions.
