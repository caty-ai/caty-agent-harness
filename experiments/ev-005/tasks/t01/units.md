# t01 units ledger

Units: 25 total; covered 25/25
MECH: 19
HUMAN: 3
MOOT: 3

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `docs/engineering.md` states that the existing hook outputs are producers only. | `a01` (T1 content-presence in `docs/engineering.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `producers only` key phrase. |
| U2 | MECH | `docs/engineering.md` states that a workspace using either producer must also schedule the flush-intake consumer. | `a02` (T1 content-presence in `docs/engineering.md`) |
| U3 | MECH | `docs/engineering.md` records the flush-intake schedule window. | `a03` (T1 content-presence in `docs/engineering.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `two to four times per day` schedule phrase. |
| U4 | MECH | `docs/engineering.md` records the macOS LaunchAgent scheduler surface. | `a04` (T1 content-presence in `docs/engineering.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the LaunchAgent + `gui/<uid>` domain fragment. |
| U5 | MECH | `docs/engineering.md` records the deadman self-marking caveat. | `a05` (T1 content-presence in `docs/engineering.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `touches` + `loop/.deadman/distill.marker` fragment. |
| U6 | MECH | `docs/engineering.md` points to `adapters/claude-code/INSTALL.md` as the normative setup procedure. | `a06` (T1 content-presence in `docs/engineering.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `adapters/claude-code/INSTALL.md` path + `full setup steps` phrase. |
| U7 | MECH | `docs/reference.md` names `loop/pending/intake-runs.log` as the flush-intake ledger. | `a07` (T1 content-presence in `docs/reference.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `loop/pending/intake-runs.log` path identifier. |
| U8 | MECH | `docs/reference.md` states the archive semantics. | `a08` (T1 content-presence in `docs/reference.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `append-only` key phrase. |
| U9 | MECH | `docs/reference.md` points to `adapters/claude-code/INSTALL.md` as the normative setup procedure. | `a09` (T1 content-presence in `docs/reference.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `adapters/claude-code/INSTALL.md` path + `full ledger format` phrase. |
| U10 | MECH | `docs/engineering.ja.md` states that the existing hook outputs are producers only. | `a10` (T1 content-presence in `docs/engineering.ja.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `producer に過ぎません` key phrase. |
| U11 | MECH | `docs/engineering.ja.md` states that a workspace using either producer must also schedule the flush-intake consumer. | `a11` (T1 content-presence in `docs/engineering.ja.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the consumer path + `定期実行` fragment. |
| U12 | MECH | `docs/engineering.ja.md` records the flush-intake schedule window. | `a12` (T1 content-presence in `docs/engineering.ja.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `21600`–`43200` numeric range. |
| U13 | MECH | `docs/engineering.ja.md` records the macOS LaunchAgent scheduler surface. | `a13` (T1 content-presence in `docs/engineering.ja.md`). Author-directed revision r2 (F2): was full-sentence fix-prose pin; relaxed to the `gui/<uid>` domain + LaunchAgent fragment. |
| U14 | MECH | `docs/engineering.ja.md` records the deadman self-marking caveat. | `a14` (T1 content-presence in `docs/engineering.ja.md`) |
| U15 | MECH | `docs/engineering.ja.md` points to `adapters/claude-code/INSTALL.md` as the normative setup procedure. | `a15` (T1 content-presence in `docs/engineering.ja.md`) |
| U16 | MECH | `docs/reference.ja.md` names `loop/pending/intake-runs.log` as the flush-intake ledger. | `a16` (T1 content-presence in `docs/reference.ja.md`) |
| U17 | MECH | `docs/reference.ja.md` states the archive semantics. | `a17` (T1 content-presence in `docs/reference.ja.md`) |
| U18 | MECH | `docs/reference.ja.md` points to `adapters/claude-code/INSTALL.md` as the normative setup procedure. | `a18` (T1 content-presence in `docs/reference.ja.md`) |
| U19 | HUMAN | The engineering-layer additions do not make claims beyond the repository's existing source documentation for this feature. | Weakened (HUMAN→MECH extraction): keep source-backed coverage for the engineering additions by requiring the normative source document `adapters/claude-code/INSTALL.md` to contain the same consumer requirement, schedule window, LaunchAgent guidance, and self-marking statement. Lost: human judgment about whether the wording is broader in tone or emphasis. Covered by `a19`–`a22` (T1 content-presence in `adapters/claude-code/INSTALL.md`). |
| U20 | HUMAN | The reference-layer additions do not make claims beyond the repository's existing source documentation for this feature. | Weakened (HUMAN→MECH extraction): keep source-backed coverage for the reference additions by requiring the normative source document `adapters/claude-code/INSTALL.md` to contain the same ledger and archive statements. Lost: human judgment about whether the wording is broader in tone or emphasis. Covered by `a23`–`a24` (T1 content-presence in `adapters/claude-code/INSTALL.md`). |
| U21 | MECH | The full repository test suite is green on the branch-equivalent tree. | `a25` (T3 command-exit: `make test`). `timeout_s` is raised to `1800` because the source-required fix-tree suite exceeded `120 s`, `300 s`, and `600 s` in history-zero replicas during admission. REV5 removes the earlier status gate, so `a25` now runs and reports its own CHECK line unconditionally. |
| U22 | MOOT | The full repository test suite is green on the post-merge mainline state. | Dropped (MOOT: the offline replica has no live merged-mainline destination). |
| U23 | HUMAN | Owner confirmation is obtained before publication. | Dropped (HUMAN: requires an external owner decision outside the offline replica). |
| U24 | MOOT | A tag is published for this documentation update. | Dropped (MOOT: tag-publication state is not represented inside the history-zero replica). |
| U25 | MOOT | Release notes are published for this documentation update together with the already-landed feature batches they summarize. | Dropped (MOOT: external release-note publication is not represented inside the history-zero replica). |

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, owner, date, tag, release, and publication provenance is
  omitted; repository-local documentation and runtime paths remain because the
  criterion names them or they are present in the pre-fix replica.
- Longest T1/T4 needle: `` `loop/pending/intake-runs.log` for content-level
  silence, dedup, deferral, eviction, and`` (88 characters). It is present in
  the pre-fix normative install document and supports U20's source-parity
  extraction; the ledger path itself is also named by U7.
- Timeout is 1800 seconds because the source-required full `make test` suite
  exceeded 120, 300, and 600 seconds in history-zero admission replicas.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append one HTML comment containing each missing assertion needle to `docs/engineering.md`, `docs/reference.md`, `docs/engineering.ja.md`, and `docs/reference.ja.md`, leaving the rendered prose and normative source unchanged.
- Route: `a (UNEXPECTED_PASS blocker)`
- Expected result: No trustworthy failing IDs to cite: the strongest surface cheat is expected, and may already be observed, to produce `UNEXPECTED_PASS`.
- Evidence status: `UNEXPECTED_PASS_CONFIRMED`; failing CHECK IDs: none; `RUN t01 negprobe exit=0 dur=668s`; no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/negprobe/t01.log`.
- Rationale: The current gate is vulnerable to comment-only needle injection across all four asserted docs, so recording a FAIL without fresh contrary evidence would be dishonest.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t01.log` (current pre-leg record).
- a15 — oversight: The generic INSTALL link already present in `docs/engineering.ja.md` does not prove the new normative setup pointer, so the pre leg still passes.
- a18 — oversight: The generic INSTALL link already present in `docs/reference.ja.md` does not prove the new normative setup pointer, so the pre leg still passes.
- a19 — invariance guard: The pre-fix `adapters/claude-code/INSTALL.md` already contains the consumer requirement, guarding against a regression that would remove it.
- a20 — invariance guard: The pre-fix normative install doc already carries the schedule-window statement, so this PASS is deliberate parity protection.
- a21 — invariance guard: The pre-fix normative install doc already carries the LaunchAgent guidance; the assertion guards source parity rather than discriminating the fix.
- a22 — invariance guard: The pre-fix normative install doc already carries the deadman marker caveat; this PASS intentionally prevents regression.
- a23 — invariance guard: The pre-fix normative install doc already names `loop/pending/intake-runs.log`, so the reference-layer source-parity check is intentionally constant-true.
- a24 — invariance guard: The pre-fix normative install doc already describes the append-only archive semantics, so this PASS is an intentional guard.
- a25 — invariance guard: The full repository suite already passes on the pre tree and must remain passing after this docs-only change; fresh terminal evidence in `experiments/ev-005/tools/validate-logs/t01.log` shows pre runs 1-5 exiting `1` at the gate level while `a25` itself remains a pre-leg PASS, and fix runs 1-5 exit `0` with no `DIRTY-TREE`.
