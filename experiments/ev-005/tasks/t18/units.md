# t18 units ledger

Units: 16 total; covered 16/16
MECH: 14
HUMAN: 1
MOOT: 1

Anonymization mapping: the source repository is the family map and related
repositories are modules. Person, owner-session, branch, date, issue/PR,
generator-attribution, and tracker provenance are omitted. `context-kit` is
retained because it is the public module identifier named by the completion
criterion and is therefore criterion-constitutive.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The registry gains exactly one `context-kit` entry. | `a01` (T6 structural JSON parse and unique-id check). |
| U2 | MECH | The entry is on the vertical axis. | `a02` (T6 nested JSON field comparison). |
| U3 | MECH | The entry is non-foundation. | `a03` (T6 JSON boolean comparison). |
| U4 | MECH | The entry stays in preparing status until the public flip. | `a04` (T6 JSON field comparison against `preparing`, the state explicitly required for this task stage). |
| U5 | MECH | Registry-driven generated blocks are committed and current. | `a05` (T3 command-exit: the repository's named `python3 -B tools/render.py --check` idempotence gate). |
| U6 | HUMAN | The registry checker passes. | Weakened (HUMAN→MECH extraction) to `a06` (T3 command-exit: `python3 -B tools/check_registry.py --offline`). This preserves deterministic local registry, link-shape, and status checks; lost: anonymous-hosting reality checks, which require forbidden external interaction. |
| U7 | MECH | `README.md`'s vertical layer-table row mentions the module. | `a07` (T6 structural: exactly one Markdown table row contains both the pre-fix-derivable vertical-foundation URL `github.com/caty-ai/caty-agent-harness` and the criterion-constitutive id `context-kit`; no localized row prose is pinned). |
| U8 | MECH | `README.ja.md`'s vertical layer-table row mentions the module. | `a08` (same T6 structural check). |
| U9 | MECH | `README.zh.md`'s vertical layer-table row mentions the module. | `a09` (same T6 structural check). |
| U10 | MECH | `README.th.md`'s vertical layer-table row mentions the module. | `a10` (same T6 structural check). |
| U11 | MECH | `README.md` has a desk-equipment category with a module bullet. | `a11` (T6 structural: find the smallest Markdown section containing the pre-fix-derivable vertical-foundation URL, then require a `context-kit` list item immediately after a bold category heading inside that same section). The heading text is not pinned, so honest paraphrases remain admissible. |
| U12 | MECH | `README.ja.md` has the localized equipment category and module bullet. | `a12` (same phrasing-tolerant T6 check). |
| U13 | MECH | `README.zh.md` has the localized equipment category and module bullet. | `a13` (same phrasing-tolerant T6 check). |
| U14 | MECH | `README.th.md` has the localized equipment category and module bullet. | `a14` (same phrasing-tolerant T6 check). |
| U15 | HUMAN | The owner decides that the external module has flipped public. | Dropped (HUMAN: publication state and owner approval are live external facts unavailable in the offline history-zero replica). |
| U16 | MOOT | After the flip, update the registry status and all localized labels to published. | Dropped (MOOT for this pre-flip task stage: U4 requires `preparing`; the follow-up becomes meaningful only after U15's external event and would contradict the admitted historical fix if enforced now). |

## Needle and timeout record

- Longest T1/T4 needle: none; all content assertions are structural JSON or
  Markdown checks, and the only fixed content token is the short public id
  `context-kit` (11 characters) from the source criterion.
- The README checks do not pin any localized historical sentence or translated
  category label. The public module id, the pre-fix vertical-foundation URL,
  and Markdown structure are all derivable from the task sheet and replica.
- Timeout remains the default 120 seconds. The two repository tools and local
  structural checks complete well within the default; no full suite is run.
