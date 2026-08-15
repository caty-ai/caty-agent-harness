# t02 units ledger

Units: 25 total; covered 25/25
MECH: 25
HUMAN: 0
MOOT: 0

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `README.md` states tested macOS evidence and expected Linux evidence in the support matrix. | `a01` (T1 content-presence in `README.md`) |
| U2 | MECH | `README.md` states the Windows status in the support matrix. | `a02` (T1 content-presence in `README.md`) |
| U3 | MECH | `README.ja.md` states tested macOS evidence and expected Linux evidence in the support matrix. | `a03` (T1 content-presence in `README.ja.md`) |
| U4 | MECH | `README.ja.md` states the Windows status in the support matrix. | `a04` (T1 content-presence in `README.ja.md`) |
| U5 | MECH | `README.zh.md` states tested macOS evidence and expected Linux evidence in the support matrix. | `a05` (T1 content-presence in `README.zh.md`) |
| U6 | MECH | `README.zh.md` states the Windows status in the support matrix. | `a06` (T1 content-presence in `README.zh.md`) |
| U7 | MECH | `README.th.md` states tested macOS evidence and expected Linux evidence in the support matrix. | `a07` (T1 content-presence in `README.th.md`) |
| U8 | MECH | `README.th.md` states the Windows status in the support matrix. | `a08` (T1 content-presence in `README.th.md`) |
| U9 | MECH | `README.md` gives the runtime badge alt the badge payload. | `a09` (T1 content-presence in `README.md`) |
| U10 | MECH | `README.md` gives the platform badge alt the badge payload. | `a10` (T1 content-presence in `README.md`) |
| U11 | MECH | `README.md` gives the status badge alt the badge payload. | `a11` (T1 content-presence in `README.md`) |
| U12 | MECH | `README.ja.md` gives the runtime badge alt the badge payload. | `a12` (T1 content-presence in `README.ja.md`) |
| U13 | MECH | `README.ja.md` gives the platform badge alt the badge payload. | `a13` (T1 content-presence in `README.ja.md`) |
| U14 | MECH | `README.ja.md` gives the status badge alt the badge payload. | `a14` (T1 content-presence in `README.ja.md`) |
| U15 | MECH | `README.zh.md` gives the runtime badge alt the badge payload. | `a15` (T1 content-presence in `README.zh.md`) |
| U16 | MECH | `README.zh.md` gives the platform badge alt the badge payload. | `a16` (T1 content-presence in `README.zh.md`) |
| U17 | MECH | `README.zh.md` gives the status badge alt the badge payload. | `a17` (T1 content-presence in `README.zh.md`) |
| U18 | MECH | `README.th.md` gives the runtime badge alt the badge payload. | `a18` (T1 content-presence in `README.th.md`) |
| U19 | MECH | `README.th.md` gives the platform badge alt the badge payload. | `a19` (T1 content-presence in `README.th.md`) |
| U20 | MECH | `README.th.md` gives the status badge alt the badge payload. | `a20` (T1 content-presence in `README.th.md`) |
| U21 | MECH | `docs/agent-guide.md` names one concrete bundled demo task for the first run. | `a21` (T1 content-presence in `docs/agent-guide.md`) |
| U22 | MECH | `docs/agent-guide.md` points that first run at `templates/examples/img-pilot.task.md`. | `a22` (T1 content-presence in `docs/agent-guide.md`) |
| U23 | MECH | `docs/agent-guide.md` includes the workspace initialization command for that demo. | `a23` (T1 content-presence in `docs/agent-guide.md`) |
| U24 | MECH | `docs/agent-guide.md` includes the enqueue command for that demo. | `a24` (T1 content-presence in `docs/agent-guide.md`) |
| U25 | MECH | `docs/agent-guide.md` includes the task-runner command for that demo. | `a25` (T1 content-presence in `docs/agent-guide.md`) |

## Author revision r2 (F2 needle calibration, 2026-08-14)

- a01–a08: were full 4-language table-row pins (up to 372 chars of fix prose); relaxed to co-presence of two distinctive fragments per row (`check_pair`: OS status cell + Windows/WSL or Linux-expectation cell). Unit mapping unchanged.
- a21: was a 107-char guide-prose pin; relaxed to the key phrase `run the bundled example`.
- a09–a20 (badge alts) and a22–a25 (exact paths/commands) kept: functional payload strings, already fragment-level.

## Anonymization and needle record

- Mapping: the public harness repository is rendered as “this repository.”
  Issue, commit, person, date, and publication provenance is omitted; public
  README paths, tool names, and the bundled example path remain as criterion
  targets.
- Longest T1/T4 needle: `scripts/tr-enqueue
  templates/examples/img-pilot.task.md "$WORKSPACE"` (68 characters). Its
  command, bundled task path, and workspace placeholder are all exposed by
  U22/U24 and the task sheet rather than hidden historical provenance.
- Timeout remains the default 120 seconds because the gate performs bounded
  fixed-string checks only and executes no repository code.

## REV6 validation evidence (r3-4)

- Fresh 5+5 history-zero validation: pre exit/duration pairs were `1/1s` five times; fix pairs were `0/1s`, `0/0s`, `0/1s`, `0/1s`, `0/1s`. `VERDICT PASS`, no `DIRTY-TREE`; log: `experiments/ev-005/tools/validate-logs/t02.log`.

## Negative validity probe (r5-1)

- Minimal non-solution edit: Append HTML comments containing the asserted platform, badge, and demo-command strings to `README.md`, `README.ja.md`, `README.zh.md`, `README.th.md`, and `docs/agent-guide.md`, without changing rendered text or behavior.
- Route: `a`.
- Expected and measured result after REV6: `a01`–`a25` FAIL because the injected strings occur only inside HTML comments.
- Evidence status: REV5 recorded `UNEXPECTED_PASS_CONFIRMED` (`exit=0`, `dur=0s`); the fresh REV6 run records `EXPECTED_FAIL_CONFIRMED` with all 25 IDs (`exit=1`, `dur=0s`, no `DIRTY_TREE`) in `experiments/ev-005/tools/validate-logs/negprobe/t02.log`.
- REV6 r4-1-style tightening: every fixed-string and co-presence assertion now matches visible content after non-greedy, multiline HTML-comment stripping, with all needles and IDs unchanged.
- Route-b visible-prose record: Visibly inserting the asserted support, badge, and walkthrough content is indistinguishable from doing the documentation work itself, so there is no honest superficial-edit FAIL claim and no separate visible-prose run.
- Rationale: REV6 rejects comment-only stuffing while preserving visible documentation as the intended completion surface.

## Constant-true declaration (r5-2)

- Source log: `experiments/ev-005/tools/validate-logs/t02.log` shows no constant-true assertions.
