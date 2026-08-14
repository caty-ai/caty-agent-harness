# t13 units ledger

Units: 21 total; covered 21/21
MECH: 20
HUMAN: 1
MOOT: 0

Anonymization mapping: the source repository is "this repository"; its
family-map section is the "hand-written family section"; the source's named
architecture abbreviation remains only in the executable gate as content
already present in the replica, not as issue provenance in `task.md`.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The hand-written family section in `README.md` retains its general prose. | `a01` (T1 content-presence of four small prose anchors spanning the family-map introduction, standalone-use claim, handbook link, and closing thanks). |
| U2 | MECH | The hand-written family section in `README.ja.md` retains its general prose. | `a02` (T1 content-presence of the corresponding four Japanese prose anchors). |
| U3 | MECH | The hand-written family section in `README.zh.md` retains its general prose. | `a03` (T1 content-presence of the corresponding four Chinese prose anchors). |
| U4 | MECH | The hand-written family section in `README.th.md` retains its general prose. | `a04` (T1 content-presence of the corresponding four Thai prose anchors). |
| U5 | MECH | The repository-specific authority note remains in `README.md`. | `a05` (T1 content-presence of three short semantic anchors: connection does not move authority; the repository shares information; it does not drive other agents). |
| U6 | MECH | The repository-specific authority note remains in `README.ja.md`. | `a06` (T1 content-presence of the corresponding three Japanese authority anchors). |
| U7 | MECH | The repository-specific authority note remains in `README.zh.md`. | `a07` (T1 content-presence of the corresponding three Chinese authority anchors). |
| U8 | MECH | The repository-specific authority note remains in `README.th.md`. | `a08` (T1 content-presence of the corresponding three Thai authority anchors). |
| U9 | MECH | The hand-written family section in `README.md` drops its module table. | `a09` (T4 content-absence of Markdown table rows inside the anchor-bounded hand-written section). |
| U10 | MECH | The hand-written family section in `README.ja.md` drops its module table. | `a10` (T4 content-absence of Markdown table rows inside that section). |
| U11 | MECH | The hand-written family section in `README.zh.md` drops its module table. | `a11` (T4 content-absence of Markdown table rows inside that section). |
| U12 | MECH | The hand-written family section in `README.th.md` drops its module table. | `a12` (T4 content-absence of Markdown table rows inside that section). |
| U13 | MECH | The marker-delimited generated family footer in `README.md` is untouched. | `a13` (T6 structural: exactly one start/end marker pair and exact SHA-256 of the pre-fix generated block). Exactness is source-required invariance, not historical prose pinning. |
| U14 | MECH | The marker-delimited generated family footer in `README.ja.md` is untouched. | `a14` (T6 structural: unique marker pair and exact pre-fix generated-block SHA-256). |
| U15 | MECH | The marker-delimited generated family footer in `README.zh.md` is untouched. | `a15` (T6 structural: unique marker pair and exact pre-fix generated-block SHA-256). |
| U16 | MECH | The marker-delimited generated family footer in `README.th.md` is untouched. | `a16` (T6 structural: unique marker pair and exact pre-fix generated-block SHA-256). |
| U17 | MECH | `README.md` leaves the generated footer as its single family module table. | `a17` (T6 structural: the distinctive English family-module table header occurs exactly once in the file; `a13` separately proves that occurrence is inside the unchanged generated block). |
| U18 | MECH | `README.ja.md` leaves the generated footer as its single family module table. | `a18` (T6 structural: the corresponding Japanese table header occurs exactly once; `a14` locates it in the unchanged generated block). |
| U19 | MECH | `README.zh.md` leaves the generated footer as its single family module table. | `a19` (T6 structural: the corresponding Chinese table header occurs exactly once; `a15` locates it in the unchanged generated block). |
| U20 | MECH | `README.th.md` leaves the generated footer as its single family module table. | `a20` (T6 structural: the corresponding Thai table header occurs exactly once; `a16` locates it in the unchanged generated block). |
| U21 | HUMAN | A four-language inspection passes. | Dropped (HUMAN: a holistic multilingual prose-quality judgment requires a reader). The mechanical core—presence of prose and authority anchors, absence of the duplicate tables, exactly one family module table, and byte-identical generated blocks in all four files—is covered by `a01`–`a20`; lost: fluency and semantic-quality judgment beyond those anchors. |
