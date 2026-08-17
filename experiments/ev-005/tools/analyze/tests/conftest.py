from __future__ import annotations

import json
from pathlib import Path
import sys

import pytest


ANALYZE_DIR = Path(__file__).resolve().parents[1]
if str(ANALYZE_DIR) not in sys.path:
    sys.path.insert(0, str(ANALYZE_DIR))


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))


@pytest.fixture
def fixture_tree(tmp_path: Path):
    tasks = tmp_path / "tasks"
    for task_id in ("t01", "t02"):
        task = tasks / task_id
        task.mkdir(parents=True)
        (task / "meta.json").write_text(json.dumps({
            "id": task_id, "source_repo": f"example/{task_id}", "pre_fix": "a" * 40,
            "fix": "b" * 40, "source_issue": 1, "synthetic": False, "timeout_s": 30,
        }))
        (task / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    out = tmp_path / "copied-out"
    out.mkdir()
    rows = []
    for task_id in ("t01", "t02"):
      for replicate in (1, 2, 3):
        for arm_index, arm in enumerate(("W", "B+", "B")):
            slug = {"W": "w", "B+": "b-plus", "B": "b"}[arm]
            run_id = f"main-{task_id}-k{replicate}-{slug}"
            block = f"{task_id}-k{replicate}"
            suffix = Path("runs") / block / slug / "attempt-001"
            attempt = out / suffix
            sha = f"{replicate}{arm_index}".ljust(40, "a")
            marker = "deliver" if arm == "W" else "DONE-DECLARE"
            audit = [
                {
                    "run_id": run_id, "task_id": task_id, "arm": arm, "cell": "main",
                    "model_id": "fixture-model", "harness_version": "fixture-harness",
                    "operator": "fixture", "replica_sha": "f" * 40,
                    "env_fingerprint": "fixture-env", "start_ts": "x",
                    "worker_id": "worker-1", "account_id": "seat-01",
                    "block_id": block, "slot_index": arm_index,
                    "agent_argv": ["fixture"], "mcp_config_digest": "1" * 64,
                    "observation_config_digest": "2" * 64,
                    "controller_config_digest": "3" * 64,
                },
                {"event": "declaration", "seq": 1, "ts": "x", "marker": marker,
                 "snapshot_sha": sha, "snapshot_failure": None, "scored": True, "count_after": 1},
            ]
            seq = 2
            if arm == "W":
                audit += [
                    {"event": "donecheck_invocation", "seq": seq, "ts": "x", "invoker": "gate",
                     "tree_sha": sha, "exit": 0, "stdout_digest": "1" * 64,
                     "duration_ms": 3000, "timed_out": False},
                    {"event": "gate_resource_sample", "seq": seq + 1, "ts": "x", "invoker": "gate",
                     "wallclock_s": 3.0},
                ]
                seq += 2
            audit += [
                {"event": "donecheck_invocation", "seq": seq, "ts": "x", "invoker": "pipeline",
                 "tree_sha": sha, "exit": 0, "stdout_digest": "0" * 64,
                 "duration_ms": 9000, "timed_out": False},
                {"event": "gate_resource_sample", "seq": seq + 1, "ts": "x", "invoker": "pipeline",
                 "wallclock_s": 9.0},
                {"event": "gate_resource_sample", "seq": seq + 2, "ts": "x", "invoker": "agent",
                 "wallclock_s": 6.0},
                {"event": "canary_check", "seq": seq + 3, "ts": "x", "rule_id": "r", "hit": False,
                 "scope": "output"},
                {"end_ts": "y", "end_reason": "delivered", "declarations_scored": 1, "provider_wait_s": 0,
                 "provider_retry_count": 0, "provider_throttle_count": 0,
                 "provider_longest_stall_s": 0, "wallclock_s": 1, "paused_s": 0,
                 "elapsed_s": 1, "infrastructure_void": False,
                 "infrastructure_void_reason": None},
            ]
            write_jsonl(attempt / "audit.jsonl", audit)
            rows.append({
                "run_id": run_id, "task_id": task_id, "arm": arm, "replicate": replicate,
                "block_id": block, "rank": replicate - 1, "seat": "seat-01",
                "slot_index": arm_index, "series": "main", "cell": "main", "attempt": 1,
                "scoring_attempt": True, "completed": True, "void": False,
                "void_reason": None, "output": f"/execution/host/{out.name}/{suffix}",
                "start_ts": "x", "end_ts": "y", "exit_status": 0, "status_reason": "ok",
            })
    write_jsonl(out / "ledger.jsonl", rows)
    return {"out": out, "tasks": tasks, "ledger": rows}
