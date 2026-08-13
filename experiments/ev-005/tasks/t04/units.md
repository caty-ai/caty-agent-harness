# t04 units ledger

Units: 9 total; covered 9/9
MECH: 8
HUMAN: 1
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `docs/trial-isolation.md` names the public collection-pipeline repository behind the first T2 prerequisite. | `a01` (T1 content-presence of `caty-ai/x-collector` in `docs/trial-isolation.md`). Author revision r1: the target repository is named in task.md — it is criterion-constitutive (the source Done when names it; the pre-fix tree contains zero occurrences, so it is not derivable in-replica). Anonymization-sweep exemption recorded here per brief rule. |
| U2 | MECH | `docs/trial-isolation.md` links that repository. | `a02` (T1 content-presence of the full URL). Author revision r1: was a T6 exact-line hash of the historical fix line (included line-wrap context "Trials that"), which asserted formatting beyond the unit and was unsatisfiable without knowing the redacted target — replaced by URL presence. |
| U3 | MECH | `docs/trial-isolation.md` states that qualifying trials go through that pipeline. | `a03` (T1 content-presence in `docs/trial-isolation.md`). Author revision r1: was an exact fix-prose sentence pin; relaxed to a phrasing-tolerant pattern (`(through|via) (that|the|this) (collection )?pipeline`, case-insensitive) so honest paraphrases pass. |
| U4 | MECH | `docs/trial-isolation.md` states that those trials inherit the pipeline's collection controls. | `a04` (T1 content-presence in `docs/trial-isolation.md`). Author revision r1: relaxed from two exact fix-prose fragments to co-presence of `inherit` + `collection controls`. |
| U5 | MECH | The first T2 condition remains that the collection-controls prerequisite is closed. | `a05` (T1 content-presence in `docs/trial-isolation.md`) |
| U6 | MECH | The second T2 condition remains explicit owner pre-approval of the concrete trial plan. | `a06` (T6 structural: exact condition line hash in `docs/trial-isolation.md`) |
| U7 | MECH | The T2 isolation string in `scripts/trial-enqueue.sh` stays unchanged. | `a07` (T6 structural: exact T2 string line hash in `scripts/trial-enqueue.sh`) |
| U8 | MECH | The T2 row in the normative tier table in `docs/adoption-wiring.md` stays unchanged. | `a08` (T6 structural: exact T2 row line hash in `docs/adoption-wiring.md`) |
| U9 | HUMAN | No other private-reference wording is introduced. | Weakened (HUMAN→MECH extraction): keep a narrow textual proxy by requiring `docs/trial-isolation.md` to contain no more `private` occurrences than the two pre-existing ones. Lost: semantic judgment about whether a newly introduced phrase is effectively a private-reference concern even without the literal word `private`, and diff/provenance judgment outside this file. Covered by `a09` (T4 content-absence proxy). |
