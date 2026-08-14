# t22 units ledger

Units: 7 total; covered 7/7
MECH: 2
HUMAN: 4
MOOT: 1

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | Generalized versions of the five context-hygiene tools are included, and `recall` documents its relationship to shared memory. | `a01` (T2 existence of the seven implementation surfaces representing `lg`, scratch persistence, brief validation, three safety hooks, and `recall`) plus `a02` (T1 content-presence in `docs/recall.md`, using the small alternative stems `individual`/`single-agent`, `shared`/`multi-agent`, and `local-only`/`local only`). |
| U2 | HUMAN | Personal-environment dependencies are removed or made configurable. | Weakened (HUMAN→MECH extraction): `a03` is a T4 sweep over tracked repository source text for literal personal absolute paths, the source username, and private workspace/repository identifiers. Validator-injected `.ev005-*` gate/fixture files are excluded because they are bundle scaffolding, not candidate repository source. Lost: semantic judgment about every possible model-specific assumption and whether every configuration boundary is ideally designed. The fixed-string sweep intentionally does not match the bracket-escaped self-test guard in `tests/test_recall.sh` (for example `[s]hojikumaru` and `/[U]sers`), so the repository's own forbidden-pattern test does not become a false positive. |
| U3 | MECH | Setup documentation and settings hook wiring reproduce installation from a clean environment. | `a04` (T1/T6: README names the settings example, placeholder replacement, and local test loop; `examples/settings.json` parses after replacing its checkout placeholder and contains nonempty pre/post-tool hook lists). This checks the deterministic offline core, not a live installation in a third-party application. |
| U4 | HUMAN | README creation passes the three named readme-craft process gates and follows the README standard. | Weakened (HUMAN→MECH extraction): `a05` requires the four language README files and their shared seven-part user-facing structure (`pain`, `what`, `requirements`, `install`, `safety`, `docs`, `license`). Lost: evidence that the human process gates were performed and aesthetic/editorial inspection of the result. |
| U5 | HUMAN | The eleven-item publication gate passes, including four README languages, hero/thumbnail, internal cleanup, MIT, and three-axis labels. | Weakened to the replica-visible behavioral core: `a03` (T4 internal-information cleanup), `a05` (T2/T1 four structured README files), `a06` (T2 nonempty `assets/readme/hero.png`, the local hero/thumbnail asset named in the task), and `a07` (T2/T1 MIT license). Lost: the unenumerated remainder of the eleven-item gate, visual quality of the image, and live hosting-platform issue-label state, all HUMAN or unavailable offline. |
| U6 | HUMAN | The repository owner performs the public visibility flip. | Dropped (HUMAN: requires a named owner's approval and live external account action; it has no deterministic local behavioral core). |
| U7 | MOOT | Until the owner flip, the live repository remains private. | Dropped (MOOT: live hosting visibility is absent from the offline history-zero replica). |

## Pair span, anonymization, and needle record

- Pair: pinned pre-fix `286c2a34ecfde934417f937f324272c7da154ca2`; fix `90d5cfec89dd3107327418fb7030a4175358e27e`. The fix is an ancestor of `origin/main`.
- This is deliberately a two-milestone span: `7cc989b815c65fd08d70d42a615efcaeada6ea68` adds generalized `recall`, then `90d5cfe` adds the four-language README/documentation and hero. The pinned pre is the fix's grandparent, not `fix^`; no SHA was substituted.
- Central spot check before authoring: `bin/recall`, three translated README files, and `assets/readme/hero.png` are absent at the pinned pre and present at the fix.
- New stand-in mapping: source repository `caty-ai/context-kit` → “workspace-toolkit repository.” Public tool names and in-repository paths remain because they are functional targets; the source repo identity is not used in task prose.
- T4 guard detail: `tests/test_recall.sh` intentionally stores its own forbidden tokens in bracket-escaped form. `a03` searches literal fixed strings, so `[s]hojikumaru`, `[a]lpha-wiki`, `[c]laude-workspace`, and `/[U]sers` do not false-positive. Validator-injected tracked paths beginning `.ev005-` are skipped so the visible gate does not inspect its own literal pattern table.
- Longest T1/T4 needle: `examples/settings.json` (22 characters, a source-named setup target). No T1/T4 assertion pins historical fix prose.
- Timeout remains the default 120 seconds; checks are structural and do not run the repository's broad test set.
