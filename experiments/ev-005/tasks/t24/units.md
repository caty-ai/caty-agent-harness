# t24 units ledger

Units: 27 total; covered 27/27
MECH: 24
HUMAN: 3
MOOT: 0

Anonymization mapping: the source repository is the “family map,” and its
public modules retain their public repository identifiers. The identifiers
`caty-ai/self-growth-loop`, `shojikumaru/self-growth-loop`,
`shojikumaru/family-memory-architecture`, and
`shojikumaru/persona-growth-loop` are criterion-constitutive and remain
verbatim in `task.md`. The account slug is public repository provenance needed
to implement the allowlist and link-check units; this is the anonymization-sweep
exemption for those strings.

Author-layout ruling: the source predicted additions to `tools/check_registry.py`,
but the fix implements the criterion in `tools/check_publication_gate.py` and a
dedicated workflow job. The mappings below test the criterion through that
runnable gate. Workflow text is inspected only for CI enforcement and the
link-check exclusions that live solely in workflow configuration.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The English README presents the self-growth module at its published MIT registry target. | `a01` (T5/T6: parse the replica-local registry and require one README line to co-locate its `caty-ai/self-growth-loop` target with the registry-derived English published label). |
| U2 | MECH | The Japanese README presents the same state. | `a02` (same structural/behavior probe with the registry-derived Japanese label). |
| U3 | MECH | The Chinese README presents the same state. | `a03` (same probe with the registry-derived Chinese label). |
| U4 | MECH | The Thai README presents the same state. | `a04` (same probe with the registry-derived Thai label). |
| U5 | MECH | The link checker no longer excludes the retired personal self-growth URL. | `a05` (T4 content-absence in the workflow's link-check configuration; the short URL fragment is named by the criterion). |
| U6 | MECH | The link checker no longer excludes the retired personal memory URL. | `a06` (T4 content-absence in the same configuration). |
| U7 | MECH | The preparing persona URL remains excluded. | `a07` (T1 content-presence in the link-check configuration). |
| U8 | MECH | The former self-growth repository is listed in `retired_repos`. | `a08` (T6 JSON parse, exact one-entry cardinality). |
| U9 | MECH | The English README renders the preparing persona module as labeled plain text. | `a09` (T5/T6: derive the preparing label from the registry, find the module line, and reject `github.com` or Markdown HTTP-link syntax on that line). |
| U10 | MECH | The Japanese README does the same. | `a10` (same registry-derived probe). |
| U11 | MECH | The Chinese README does the same. | `a11` (same registry-derived probe). |
| U12 | MECH | The Thai README does the same. | `a12` (same registry-derived probe). |
| U13 | MECH | The publication denylist rejects personal-name patterns. | `a13` (T5: run the production gate against a temporary tracked negative fixture assembled without embedding a personal name in the task source). |
| U14 | MECH | The denylist rejects approval-record patterns. | `a14` (T5 negative behavior probe). |
| U15 | MECH | The denylist rejects absolute personal home paths. | `a15` (T5 negative behavior probe). |
| U16 | MECH | The denylist rejects internal host addresses. | `a16` (T5 negative behavior probe). |
| U17 | MECH | The denylist rejects personal email addresses. | `a17` (T5 negative behavior probe). |
| U18 | MECH | Unlisted personal-account repository links fail against the registry-derived allowlist. | `a18` (T5: a temporary Markdown link outside module and retired declarations must make the production gate fail). Preparing declarations are already module declarations in the replica registry, so they are part of the same mechanically derived set. |
| U19 | HUMAN | Changes to the personal-repository allowlist require owner approval. | Dropped (HUMAN: approval identity and authorization cannot be established in the offline history-zero replica). Mechanical core extracted through `a18`: the current allowlist is derived from registry declarations rather than an open-ended match. |
| U20 | MECH | Missing visibility labels fail, with exact row-level whitelist exemptions. | `a19` (T5 negative behavior probe through the production gate). The shipped repository gate run in `a24` simultaneously proves its exact whitelist accepts the current tree. |
| U21 | MECH | SVG visible/metadata text is scanned for unsupported state claims. | `a20` (T5 negative SVG behavior probe through the production gate). |
| U22 | MECH | The scan covers the seven named source suffixes. | `a21` (T5: independently place a denylisted path in temporary tracked files with `.md`, `.json`, `.py`, `.yml`, `.yaml`, `.svg`, and `.sh` suffixes and require failure for each). |
| U23 | MECH | Pull-request CI enforces the gate and its negative-fixture self-test. | `a22` (T6 workflow structure: dedicated job, direct gate command, direct self-test command, and downstream `needs` dependency). GitHub Actions itself is unavailable in-replica; gate behavior is exercised directly by `a13`–`a21`, `a24`, and `a25`. |
| U24 | HUMAN | Existing external destinations, comments, and attachments receive a one-time deep review with a recorded list. | Dropped (HUMAN: requires live external interaction and review judgement; no destination content or review record is present in the history-zero replica). |
| U25 | HUMAN | Images receive a one-time EXIF/XMP review. | Dropped (HUMAN: the criterion is a human acceptance audit, and the fix introduces no replica-local audit record or canonical inspection command to mechanize it faithfully). |
| U26 | MECH | Generated README blocks are current. | `a23` (T3 command-exit: the exact source-named `python3 -B tools/render.py --check`). |
| U27 | MECH | All new publication checks are green. | `a13`–`a21` (T5 negative behavior families), `a24` (T3 command-exit of the production publication gate on repository sources), and `a25` (T5 clean fixture accepted). |

## Anonymization, needles, and timeout

- Mapping: the source repository is called the family map. Public module and
  retired-repository identifiers remain verbatim because the criterion names
  them and the publication allowlist requires them; owner-approval identity
  and issue/process provenance are omitted.
- Longest T1/T4 needle:
  `github\.com/shojikumaru/family-memory-architecture` (50 characters). The
  repository slug is named in the criterion and task sheet, while the escaped
  `github\.com/` form is derivable from the pre-fix workflow configuration.
  Labels and registry fields are derived from `registry/modules.json`; no
  historical prose or out-of-replica blob is pinned.
- Timeout remains the task's default 120 seconds. The gate and bundled fixture
  use only local source scans and temporary repositories, and do not mutate
  tracked task content.
