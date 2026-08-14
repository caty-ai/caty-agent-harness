# t20 units ledger

Units: 22 total; covered 22/22
MECH: 18
HUMAN: 4
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `docs/evidence.md` exists. | `a01` (T2 path existence). |
| U2 | MECH | Every claim records `believe`. | `a02` (T6 table-schema parse). |
| U3 | MECH | Every claim records `built`. | `a02` (T6 table-schema parse). |
| U4 | MECH | Every claim records `actually happened`. | `a02` (T6 table-schema parse). |
| U5 | MECH | Every claim records `still don't know`. | `a02` (T6 table-schema parse). |
| U6 | MECH | Every claim has a unique stable claim id. | `a02` (T6: unique nonempty identifiers matching the task-visible stable form of a capitalized namespace and at least three digits; prose and exact ids are not pinned). |
| U7 | MECH | Every claim records delivery, visibility, and evidence state. | `a02` (T6: the named state row exists and contains three nonempty dot-separated axes). |
| U8 | MECH | Every claim cites evidence while distinguishing mechanism-only evidence from a primary record. | `a02` requires a nonempty evidence row containing a local HTTP(S) citation; `a06` requires the growth entry to expose `unverified` when no primary record exists. The gate does not claim that an offline URL is reachable. |
| U9 | MECH | Every claim records `observed-at`. | `a02` (T6 nonempty ISO-date parse). |
| U10 | MECH | Every claim records `last-reviewed`. | `a02` (T6 nonempty ISO-date parse). |
| U11 | MECH | Every claim records an owner. | `a02` (T6 nonempty field). |
| U12 | MECH | Every claim records counter-evidence, with `none` allowed. | `a02` (T6 nonempty field; `none` is accepted rather than requiring fabricated counter-evidence). |
| U13 | MECH | Initial evidence includes silent-failure discovery and repair. | `a03` (T6 semantic anchors across one claim entry: `silent` plus a repair/fail-closed term). These are small criterion phrases, not a fix-prose sentence. |
| U14 | MECH | Initial evidence includes a deliberately broken CI gate and red/green recovery. | `a04` (T6 semantic anchors in one entry: gate, deliberate/mutation, and failure/red). |
| U15 | MECH | Initial evidence includes an observed weekly reality-check run. | `a05` (T6 semantic anchors in one entry: weekly/scheduled, run, and pass). |
| U16 | HUMAN | Initial evidence includes a real governed growth cycle from proposal through adoption. | Weakened (HUMAN→MECH extraction) to `a06`: require one entry containing propose, trial, council, owner, and adopt, plus either primary evidence or an explicit `unverified` state. The historical fix truthfully says no public primary record exists; the deterministic core therefore verifies honest representation rather than fabricating or externally judging a private record. Lost: confirming a real private-to-public cycle and its approval authenticity. |
| U17 | HUMAN | A person checks linked bodies, comments, attachments, and the denylist before accepting a link, records the review date, and excludes unverified links. | Dropped (HUMAN: content review and denylist judgment require live external pages and a reviewer). Mechanical residue is covered by `a02`'s required `last-reviewed` date and `a07`–`a09`'s fail-closed staleness contract; the gate intentionally does not equate a date field with proof the review occurred. |
| U18 | MECH | Evidence older than 90 days becomes unknown until reverified. | `a07` (T1 co-location of the source-derived short needles `last-reviewed`, `90 days`, and unknown/reverify in the register's policy line). |
| U19 | MECH | A weekly workflow job parses exact review dates and rejects ages over 90 days. | `a08` (T6 workflow structure: scheduled workflow, `docs/evidence.md`, exact `last-reviewed`, required-field parsing, an age comparison greater than 90, and a nonzero failure path). GitHub Actions itself is unavailable in-replica, so the workflow file is inspected rather than claimed as executed. |
| U20 | MECH | Staleness fails closed and automation does not rewrite the evidence file. | `a09` (T6 combined contract: policy says stale means unknown/reverify; workflow collects or compares stale ages, has a nonzero path, and contains no write call targeting `docs/evidence.md`). |
| U21 | HUMAN | Every evidence link is anonymously readable. | Dropped (HUMAN: anonymous reachability is a live external fact; R5 forbids network access and the workflow's separate anonymous-link job cannot execute in the replica). |
| U22 | HUMAN | Every evidence link is publicly safe. | Dropped (HUMAN: disclosure safety requires inspecting external content, comments, and attachments, not merely checking URL syntax). |

## Anonymization, needles, and timeout

- Mapping: the source repository is the family map and the new document is the
  evidence register. Epic, issue/PR, person, session, branch, date, and internal
  contract-reference provenance are removed from `task.md`. The four evidence
  themes remain because they are the completion criterion itself.
- `claim-id`, the four evidence-field labels, the three state-axis labels,
  `observed-at`, `last-reviewed`, `owner`, `counter-evidence`, and the 90-day
  threshold are criterion-constitutive public schema and remain visible.
- Longest T1/T4 needle: `last-reviewed` (13 characters). The semantic T6 probes
  use short theme tokens and never pin a complete historical claim sentence,
  URL, claim title, or exact claim id.
- Timeout remains the default 120 seconds. All checks are local structural
  parses; no links or GitHub Actions jobs are executed.
