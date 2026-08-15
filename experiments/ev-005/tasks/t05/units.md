# t05 units ledger

Units: 39 total; covered 39/39
MECH: 39
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | The bundled example task uses a local SVG artifact path. | `a01` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U2 | MECH | The bundled example task checks for an SVG root element. | `a02` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U3 | MECH | The bundled example task declares the SVG artifact path in the receipt payload. | `a03` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U4 | MECH | The bundled example task lists `bash` as a resource. | `a04` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U5 | MECH | The bundled example task lists `python3` standard library as a resource. | `a05` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U6 | MECH | The bundled example task no longer uses the old backend dependency name. | `a06` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U7 | MECH | The bundled example task no longer uses the old push channel dependency name. | `a07` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U8 | MECH | The bundled example task no longer uses the old PNG artifact path. | `a08` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U9 | MECH | The bundled example task no longer mentions the old scoring step. | `a09` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U10 | MECH | The Codex install guide uses a placeholder operator-charter path. | `a10` (T1 content-presence in `adapters/codex/INSTALL.md`) |
| U11 | MECH | The Codex install guide includes setup guidance for that placeholder path. | `a11` (T1 content-presence in `adapters/codex/INSTALL.md`) |
| U12 | MECH | The Kimi install guide uses a placeholder operator-charter path. | `a12` (T1 content-presence in `adapters/kimi/INSTALL.md`) |
| U13 | MECH | The Kimi install guide includes setup guidance for that placeholder path. | `a13` (T1 content-presence in `adapters/kimi/INSTALL.md`) |
| U14 | MECH | The Hermes cron example uses a placeholder secrets path. | `a14` (T1 content-presence in `adapters/hermes/INSTALL.md`) |
| U15 | MECH | The Hermes cron example uses a placeholder workspace path. | `a15` (T1 content-presence in `adapters/hermes/INSTALL.md`) |
| U16 | MECH | The task template uses the generic `issued_by` value. | `a16` (T1 content-presence in `templates/TASK.tmpl.md`) |
| U17 | MECH | The task template uses the generic `escalate_to` value. | `a17` (T1 content-presence in `templates/TASK.tmpl.md`) |
| U18 | MECH | The task template no longer uses the old `issued_by` value. | `a18` (T4 content-absence in `templates/TASK.tmpl.md`) |
| U19 | MECH | The task template no longer uses the old `escalate_to` value. | `a19` (T4 content-absence in `templates/TASK.tmpl.md`) |
| U20 | MECH | The bundled example task uses the generic `issued_by` value. | `a20` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U21 | MECH | The bundled example task uses the generic `escalate_to` value. | `a21` (T1 content-presence in `templates/examples/img-pilot.task.md`) |
| U22 | MECH | The bundled example task no longer uses the old `issued_by` value. | `a22` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U23 | MECH | The bundled example task no longer uses the old `escalate_to` value. | `a23` (T4 content-absence in `templates/examples/img-pilot.task.md`) |
| U24 | MECH | The updater script removes the implicit default reporter path. | `a24` (T1 content-presence in `scripts/family-updater`) |
| U25 | MECH | The updater script warns that reporting is disabled when the reporter path is omitted. | `a25` (T1 content-presence in `scripts/family-updater`) |
| U26 | MECH | The updater script documents the explicit override flag or env var for the reporter path. | `a26` (T1 content-presence in `scripts/family-updater`) |
| U27 | MECH | The updater script no longer embeds the old private default reporter path. | `a27` (T4 content-absence in `scripts/family-updater`) |
| U28 | MECH | The updater cron template requires an explicit reporter-path setting. | `a28` (T1 content-presence in `templates/updater-cron.tmpl.sh`) |
| U29 | MECH | The updater cron template shows a placeholder reporter path. | `a29` (T1 content-presence in `templates/updater-cron.tmpl.sh`) |
| U30 | MECH | The updater cron template no longer uses the old `HOME`-based failure text. | `a30` (T4 content-absence in `templates/updater-cron.tmpl.sh`) |
| U31 | MECH | The updater cron template no longer derives the reporter path from `HOME`. | `a31` (T4 content-absence in `templates/updater-cron.tmpl.sh`) |
| U32 | MECH | The installer comment uses generic remote-home wording. | `a32` (T1 content-presence in `install.sh`) |
| U33 | MECH | The installer comment no longer uses the old person-specific remote-home wording. | `a33` (T4 content-absence in `install.sh`) |
| U34 | MECH | The probe note says it inspects configured adapter paths. | `a34` (T1 content-presence in `install.sh`) |
| U35 | MECH | The probe note says it also reads env-supplied external paths. | `a35` (T1 content-presence in `install.sh`) |
| U36 | MECH | The probe note says it does not mutate the checked workspace. | `a36` (T1 content-presence in `install.sh`) |
| U37 | MECH | The probe note no longer uses the old installer-local inspection wording. | `a37` (T4 content-absence in `install.sh`) |
| U38 | MECH | The wrapper-conformance library remains unchanged. | `a40` (T6 structural: exact blob pin of `scripts/lib-wrapper-conformance.sh`). Author revision r1: restores the binding fence from the source adopted scope that was previously dropped, using an in-replica invariance pin per the accepted exactness pattern for untouched files. |
| U39 | MECH | The wrapper-conformance test expectations remain unchanged. | `a41` (T6 structural: exact blob pin of `tests/wrapper-conformance.test.sh`). Author revision r1: restores the second half of the binding fence from the source adopted scope; the blob is identical in pre-fix and fix, so the validity legs remain unchanged while the "do not touch this" constraint becomes explicit. |

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, person, date, and private operator-path provenance is omitted
  from the task sheet. Old operator-specific values remain only as
  pre-fix-derived T4 negative baselines; replacement placeholders and public
  paths are criterion targets.
- Longest T1/T4 needle:
  `FMA_SCRIPTS_DIR=${FMA_SCRIPTS_DIR:-"$HOME/claude-workspace/family-memory-architecture/scripts"}`
  (95 characters). It is a pre-fix-derived forbidden baseline, not historical
  replacement prose; the a40/a41 equality pins are T6 invariance checks.
- Timeout remains the default 120 seconds because the gate performs bounded
  content checks and Git blob comparisons and executes no repository code.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append only the missing positive needles as comments to `templates/examples/img-pilot.task.md`, `adapters/codex/INSTALL.md`, `adapters/kimi/INSTALL.md`, `adapters/hermes/INSTALL.md`, `templates/TASK.tmpl.md`, `scripts/family-updater`, `templates/updater-cron.tmpl.sh`, and `install.sh`, leaving all operative legacy content unchanged.
- Route: `a`
- Expected result: `a06`-`a09`, `a18`, `a19`, `a22`, `a23`, `a27`, `a30`, `a31`, `a33`, and `a37` should still FAIL.
- Evidence status: `EXPECTED_FAIL_CONFIRMED`; failing CHECK IDs: `a06`, `a07`, `a08`, `a09`, `a18`, `a19`, `a22`, `a23`, `a27`, `a30`, `a31`, `a33`, `a37`; `RUN t05 negprobe exit=1 dur=0s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t05.log`.
- Rationale: Comment-only needles cannot satisfy the non-mutation and untouched-hash checks that bind the real behavior.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t05.log` (current pre-leg record).
- a36 — invariance guard: The pre-fix gate already proves the non-mutation claim, guarding against accidental edits outside the target surface.
- a40 — invariance guard: The untouched-file hash for the first protected file already matches pre-fix, so the PASS is deliberate.
- a41 — invariance guard: The untouched-file hash for the second protected file already matches pre-fix, giving another intentional non-regression guard.
