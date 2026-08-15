# t10 units ledger

Units: 12 total; covered 12/12
MECH: 10
HUMAN: 2
MOOT: 0

Anonymization mapping: the source repository is called the map repository and
related repositories are called member repositories; owner, session, branch,
date, issue/PR, and generator-attribution provenance are omitted. Repository
paths and tool commands remain because they are criterion-constitutive and
derivable from the pre-fix tree. The source's example block name is not frozen:
the probes discover the added generated block dynamically, so an honest
alternative block identifier can pass.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `README.md` contains the new generated family table near its bottom. | `a01` (T6 structural: exactly one non-footer generated block is immediately before the existing license section). |
| U2 | MECH | `README.ja.md` contains the new generated family table near its bottom. | `a02` (same T6 structural check). |
| U3 | MECH | `README.zh.md` contains the new generated family table near its bottom. | `a03` (same T6 structural check). |
| U4 | MECH | `README.th.md` contains the new generated family table near its bottom. | `a04` (same T6 structural check). |
| U5 | MECH | Each block is the localized module/state table produced from `registry/modules.json` through the existing table builder. | `a05` (T6 structural: dynamically discover each block, compare its complete body with `tools/render.py`'s render result for that path and registry, and require use of the pre-existing `module_table` builder identifier). `module_table` is derivable from the pre-fix tree and is therefore not a fix-prose needle. |
| U6 | MECH | The map row is bold and not self-linked in every localized generated table. | `a06` (T6 structural: derive localized map names and the map repository URL from the registry, inspect the first data row, require bold name and absence of the self-link). |
| U7 | MECH | `tools/render.py --check` detects stale content in the new generated block. | `a07` (T5 behavior probe: copy the tree to a temporary directory, alter the discovered English generated-block body there, and require the named check command to exit nonzero; tracked source remains untouched). |
| U8 | MECH | `tools/render.py --check` passes. | `a08` (T3 command-exit: exact command named by the source criterion). |
| U9 | HUMAN | `tools/check_registry.py` passes. | Weakened (HUMAN→MECH extraction) to the deterministic offline core: `a09` (T3 command-exit: `python3 -B tools/check_registry.py --offline`, covering local registry structure, links, and status consistency without network access or bytecode writes). Lost: the tool's live GitHub repository reality checks, which require external interaction forbidden by R5. |
| U10 | MECH | `tools/family_footer.py lint` passes. | `a10` (T3 command-exit: exact command named by the source criterion). |
| U11 | MECH | The family-footer self-test passes. | `a11` (T3 command-exit: `python3 tools/selftest_family_footer.py`, the repository's existing self-test entry point). |
| U12 | HUMAN | Member-repository footer behavior is unchanged. | Weakened (HUMAN→MECH extraction) to the change-sensitive, replica-solvable behavioral core: default rendering must still link the map row and render the host member bold and unlinked. `a12` (T5 behavior probe: render every footer-enabled member in all four registry languages through the default API and require those two canonical behaviors, which are documented and derivable in-replica). Lost: full diff/provenance judgment and byte-for-byte comparison with the pre-fix implementation, whose historical baseline is unavailable to an honest solver in the history-zero replica. |

## Anonymization, needles, and timeout

- Mapping: the source repository is called the map repository and related
  repositories are called member repositories. Owner, session, branch, date,
  issue/PR, and generator-attribution provenance are omitted. Repository paths
  and tool commands remain because they are criterion-constitutive and
  derivable from the pre-fix tree.
- Longest T1/T4 needle: none. The gate uses structural, command-exit, and
  behavior probes; identifiers such as `module_table` are derived from the
  replica, and the added generated-block name is discovered dynamically.
- Timeout remains the task's default 120 seconds. The repository checks and
  bundled probes are local; the stale-block probe's temporary tree copy is the
  heaviest operation and completes within the default.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Insert an empty `family:generated:unknown` start/end comment block plus separator in `README.md` immediately before `<a id="license"></a>`, leaving every localized README untouched.
- Route: `a`
- Expected result: `a02`-`a06` and `a08` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a02`, `a03`, `a04`, `a05`, `a06`, `a08`; `RUN t10 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t10.log`.
- Rationale: An empty extra block does not satisfy the current generated-content, offline-registry, or footer-placement invariants.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t10.log` (current pre-leg record).
- a08 — invariance guard: The generated-content freshness guard already holds pre-fix and intentionally stays constant-true.
- a09 — invariance guard: The offline-registry guard already holds on the pre tree and is deliberate.
- a10 — invariance guard: The first footer/lint rendering invariant already holds pre-fix and guards against regression.
- a11 — invariance guard: The second footer/lint rendering invariant already holds on the pre tree.
- a12 — invariance guard: The default-member rendering invariant already holds pre-fix and intentionally remains constant-true.
