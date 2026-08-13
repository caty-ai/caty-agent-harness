# EV-005 task bundle

Layout per task (`tasks/<id>/`, ids `t01`–`t40`, order-shuffled, no relation to source order):

- `task.md` — the anonymized task sheet every arm sees (goal, unit-numbered Done when, allowed tools, budget, pointer to `donecheck.sh`). Identical across arms (design #63 §2).
- `donecheck.sh` — fail-closed gate derived under `../translation-rules.md`. Emits `CHECK <unit> PASS|FAIL <reason>` lines; exit 0 iff all pass.
- `fixtures/` — optional probe inputs (T5 assertions).
- `meta.json` — bundle-repo-only metadata (never copied into replicas): `{"id","source_repo","source_issue","pre_fix","fix","synthetic":false,"timeout_s"}`. For synthetic tasks: `"synthetic":true`, `"pattern_source"` instead of SHAs, and `"base_sha"` for the replica base.
- `units.md` — the R4 faithfulness record: every Done when unit → assertion id(s), or dropped/weakened with reason and class label (MECH/HUMAN/MOOT).

Admission gate: `tools/validate-task.sh <task-dir> --repo <local-clone>` must show pre_fix FAIL×5 / fix PASS×5, all runs read-only. Logs land in `tools/validate-logs/` (manifest input).

Author of record: Alpha (drafts may come from Codex; every admitted line is author-reviewed). Non-author acceptance per translation-rules.md §6.
