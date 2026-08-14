# EV-005 batch-3 drafting report

Batch 3 completes the base bundle with fourteen ordinary re-enactments,
`t17`–`t30`. No pair was substituted and every metadata record has
`"synthetic": false`. The table below reports a validity verdict only when the
corresponding on-disk log contains five pre-fix runs, five fix runs, no
read-only violation, and a terminal verdict.

## Task summary

| id | source | resolved `pre_fix` | units | MECH | HUMAN | MOOT | assertions | validity |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| t17 | caty-agent-harness#22 | `19032f7067be1e96b00974d74c185fc46e5a9ee0` | 7 | 7 | 0 | 0 | 7 | [PASS](../tools/validate-logs/t17.log) |
| t18 | family-os#12 | `c48913a0b31d554e84f31714c48f3ff58c160c5e` | 16 | 14 | 1 | 1 | 14 | [PASS](../tools/validate-logs/t18.log) |
| t19 | caty-agent-harness#10 | `2bbc00a4501c7c91af988b28daa524b41b2c8b47` | 5 | 5 | 0 | 0 | 5 | [PASS](../tools/validate-logs/t19.log) |
| t20 | family-os#27 | `e6e2fa76707c6a83252739e4eca4924d3c01534d` | 22 | 18 | 4 | 0 | 9 | [PASS](../tools/validate-logs/t20.log) |
| t21 | caty-agent-harness#23 | `06b763ab6d2ac0d946ac5220a16b5e210a1251e3` | 6 | 6 | 0 | 0 | 6 | [PASS](../tools/validate-logs/t21.log) |
| t22 | context-kit#1 | `286c2a34ecfde934417f937f324272c7da154ca2` | 7 | 2 | 4 | 1 | 7 | [PASS](../tools/validate-logs/t22.log) |
| t23 | caty-agent-harness#20 | `5ae06864018abf3c1aaa3e08ec72bfa4a47241cd` | 6 | 6 | 0 | 0 | 7 | [PASS](../tools/validate-logs/t23.log) |
| t24 | family-os#26 | `f0ba28165f4c5cfb2133876d13dbac1199447926` | 27 | 24 | 3 | 0 | 25 | [PASS](../tools/validate-logs/t24.log) |
| t25 | caty-agent-harness#12 | `dfbc09466930d6e073b19faa4e203560bec39d9d` | 4 | 3 | 1 | 0 | 6 | [PASS](../tools/validate-logs/t25.log) |
| t26 | caty-agent-harness#21 | `18e897513e06e9f2e93e08920f0cdd8314472c70` | 5 | 5 | 0 | 0 | 6 | [PASS](../tools/validate-logs/t26.log) |
| t27 | family-os#29 | `5938d52d32f078f644f8e45bd6d64d5b65e2b3b9` | 15 | 12 | 2 | 1 | 12 | [PASS](../tools/validate-logs/t27.log) |
| t28 | caty-agent-harness#11 | `71555781a9f1e1625262f7fe7c442b9702e7636a` | 11 | 10 | 1 | 0 | 10 | [PASS](../tools/validate-logs/t28.log) |
| t29 | family-os#28 | `d221bd8f46f241f66e26d9c7aa31a667aa17ec94` | 19 | 17 | 2 | 0 | 13 | [PASS](../tools/validate-logs/t29.log) |
| t30 | caty-agent-harness#30 | `18e897513e06e9f2e93e08920f0cdd8314472c70` | 10 | 3 | 5 | 2 | 8 | [PASS](../tools/validate-logs/t30.log) |

For each PASS row, the linked log contains pre-fix FAIL ×5, fix PASS ×5, a
terminal `VERDICT <id> PASS`, and no `DIRTY-TREE` record.

## Pair derivation and sanity

All fixes were verified as ancestors of their clone's `origin/main` before a
donecheck was written. Except for the author-pinned t22 span, every `pre_fix`
above is exactly `fix^`. A central criterion was spot-checked as unmet at pre
and met at fix:

| id | central pre-unmet / fix-met signal |
| --- | --- |
| t17 | `TR_DONECHECK_TIMEOUT_S` and visible failed-push handling are absent/present. |
| t18 | the unique vertical `context-kit` registry entry is absent/present. |
| t19 | data-only `SECRETS_ENV` parsing and symlink refusal are absent/present. |
| t20 | `docs/evidence.md` and its freshness job are absent/present. |
| t21 | conditional verified-skill metadata warnings and their regression are absent/present. |
| t22 | `bin/recall`, translated READMEs, and the hero asset are absent/present across the pinned two-milestone span. |
| t23 | corrupt-state quarantine and UTC `created` validation are absent/present. |
| t24 | `tools/check_publication_gate.py` and its workflow job are absent/present. |
| t25 | the signed-release verification library and pre-checkout gate are absent/present. |
| t26 | `docs/cli-conventions.md` and its focused pinning test are absent/present. |
| t27 | root `FOR-AGENTS.md` is absent/present. |
| t28 | the shared donecheck extractor, quote-aware path, and boundary tests are absent/present. |
| t29 | canonical growth-model documents and the five-stage SVG are absent/present. |
| t30 | `Makefile` and the five workflow definitions are absent/present. |

t22 deliberately uses pinned pre
`286c2a34ecfde934417f937f324272c7da154ca2`: generalized `recall` lands at
`7cc989b815c65fd08d70d42a615efcaeada6ea68`, and the README/documentation/hero
milestone lands at `90d5cfec89dd3107327418fb7030a4175358e27e`.
The pinned pre is therefore the fix's grandparent.

## Needle and replica-solvability audit

| id | longest T1/T4 needle | derivability result |
| --- | --- | --- |
| t17 | `TR_DONECHECK_TIMEOUT_S=${TR_DONECHECK_TIMEOUT_S-60}` | Task-visible public knob/default; not prose. The `B0` absence token is pre-fix-derived. |
| t18 | `context-kit` | Source-named module id; README placement is established structurally against the pre-fix harness row/section. |
| t19 | none | Behavior probes and short structural tokens only. |
| t20 | `last-reviewed` | Source-named schema field; all evidence themes are task-visible and exact claim prose/ids are not pinned. |
| t21 | `skills/_staging/SKILL.tmpl.md` | Source-target path; warning behavior is probed rather than transcribed. |
| t22 | `examples/settings.json` | Source-named setup target. T4 sweeps replica source files and excludes only validator-injected `.ev005-*` files. |
| t23 | `TR_STEP_TIMEOUT_S` | Criterion-named configuration identifier; runtime behavior is probed. |
| t24 | `github\\.com/shojikumaru/family-memory-architecture` | Exact source-named workflow exclusion. Other denylist families are exercised through temporary fixtures. |
| t25 | `allowed_signers` | Task-visible selected trust mechanism; no signature blob or historical diagnostic is pinned. |
| t26 | `tests/check-tickprobe.test.sh` | Pre-fix-derived public regression path; convention prose is checked with short tokens. |
| t27 | `automatic discovery` | Source-required concept; table rows derive from replica-local registry data. |
| t28 | `post-enqueue mutation` | Task-stated residual-risk concept; quoted-hash behavior is directly probed. |
| t29 | `Relationship Readiness` | Source-named axis. Stage labels and boundary ordering derive from replica-local canonical rows; no coordinates, full rows, or color value are pinned. |
| t30 | `risk-review-gate` | Source-required check name; hosted workflows are inspected structurally and their local test/lint core is run directly. |

No T1/T4 assertion contains a date or a sentence copied from fix prose. Every
identifier absent from the pre-fix tree but needed to solve the task is exposed
in `task.md` and recorded in `units.md`; generator/canonical comparisons use
only sources shipped inside the replica.

## Judgement calls

- **t18:** The owner-driven public flip is HUMAN and the post-flip status
  change is MOOT for this preparing-stage snapshot. The live portion of the
  registry checker is weakened to its deterministic `--offline` core.
- **t20:** Live link review, anonymous readability, and public-safety judgment
  are HUMAN. The unavailable governed self-growth record is represented
  honestly as unverified rather than fabricated.
- **t21:** The six-field requirement follows the source's amended-contract
  branch: missing verification metadata emits advisory warnings and does not
  change `install.sh --check` exit semantics.
- **t22:** README process gates, label setup, and publication are HUMAN/MOOT;
  their replica-visible cores are the four structured READMEs, local hero,
  cleanup sweep, MIT license, setup wiring, and five tool surfaces. The new
  stand-in is “workspace-toolkit repository.”
- **t24:** The source-predicted `check_registry.py` location was not enforced.
  The historical fix's actual `tools/check_publication_gate.py` is exercised
  with negative/clean behavior probes, while workflow inspection is limited
  to CI enforcement and link-check configuration. Human link/image audits are
  dropped explicitly.
- **t25:** Owner selection is HUMAN; the chosen, task-visible mechanism is
  SSH-signed annotated tags against an out-of-repository `allowed_signers`
  pin. The focused updater regression is run directly.
- **t26:** “Conforms” means conforms or is an explicitly recorded frozen
  deviation. Prefix outliers, enqueue usage exit 1, and optional `FAIL` rows
  with exit 0 remain documented and regression-pinned.
- **t27:** Draft posting/approval are HUMAN and change-lane ownership is MOOT.
  The published-module tour rows are derived exactly from the replica registry.
- **t28:** Human checkpoint approval is dropped. Every mechanical commitment
  selected by the design note is represented through direct behavior,
  structural checks, and focused suites; residual risks remain explicit.
- **t29:** Editorial coherence and visual understandability are HUMAN. Their
  structural cores use task-visible semantics and replica-local canonical
  sources; an initial coordinate/wording over-pin was removed before final
  validation.
- **t30:** Hosted label, branch-protection, red/green PR, upstream-record, and
  merge-order facts are HUMAN/MOOT. Workflow content is inspected, but the
  runnable core is not reduced to YAML inspection: `make test` and `make lint`
  execute directly. Timeout is escalated to 1800 seconds because the
  source-required full shell suite exceeded the 120-second default in local
  fix-snapshot sanity; the five authoritative fix runs completed in 654–711
  seconds each.

No task was STOPPED and no SHA was silently changed.

## Validation environment and self-verification

Validators were run with
`GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` so workstation Git
hooks could not block the validator's internal history-zero snapshot commits.
This does not change replica contents or donecheck behavior.

- Fourteen task directories exist with `task.md`, executable `donecheck.sh`,
  `units.md`, and `meta.json`; fixtures exist only where a T5/structural probe
  needs them.
- Every metadata file parses, uses the resolved pair above, and records
  `synthetic: false`.
- Every shell gate/fixture passes `bash -n`; Python fixtures parse. No gate
  invokes `gh`, `curl`, `wget`, randomness, or wall-clock-dependent logic.
- Task-sheet provenance sweep found no issue/PR number, date, person/agent
  name, or internal tracker reference. Public account/repository ids retained
  by t24 and other task-visible functional ids are documented
  criterion-constitutive exemptions.
- No file was staged and this drafting run issued no `git add`, commit, push,
  fetch, or reset.
- During the run, a separate author process advanced the branch from
  `14a4fea` through `b0b919` to `0cb5a04`. Transient unrelated modifications
  under `tasks/t11`, `tasks/t15`, `tasks/t16`, and their validation logs were
  observed and left untouched; they were no longer uncommitted at the final
  audit. Batch-3 writes are confined to `tasks/t17`–`t30`, their
  `tools/validate-logs/` files, and this report.
