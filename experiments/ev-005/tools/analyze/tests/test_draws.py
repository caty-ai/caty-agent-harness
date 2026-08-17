from __future__ import annotations

from pathlib import Path

from coding import Adjudication, CodedRun
from draws import crosscheck_draw, gaming_audit_draw, write_json
from load import RunRecord


def coded_run(run_id: str, arm: str) -> CodedRun:
    declaration = {"seq": 1, "snapshot_sha": "a" * 40}
    record = RunRecord(
        ledger={"run_id": run_id, "task_id": "t01", "arm": arm, "replicate": 1},
        attempt_dir=Path("."), header={}, events=[], trailer={}, declarations=[declaration],
        snapshot_entries={1: {"path": f"/archive/{run_id}.tar.gz"}},
    )
    adjudication = Adjudication(0, False, "reexec", {})
    return CodedRun(record, "verified_pass", adjudication, adjudication, [], None, False, False, False)


def test_gaming_draw_golden_vectors_and_byte_identity(tmp_path):
    coded = [coded_run(f"r{i:02}", arm) for arm in ("W", "B+", "B") for i in range(10)]
    draw = gaming_audit_draw(coded)
    assert [row["run_id"] for row in draw["W"]["runs"]] == ["r01", "r00", "r07", "r02", "r08"]
    assert [row["run_id"] for row in draw["B+"]["runs"]] == ["r09", "r07", "r05", "r06", "r03"]
    assert [row["run_id"] for row in draw["B"]["runs"]] == ["r00", "r05", "r09", "r08", "r07"]
    first, second = tmp_path / "first.json", tmp_path / "second.json"
    write_json(first, draw)
    write_json(second, gaming_audit_draw(list(reversed(coded))))
    assert first.read_bytes() == second.read_bytes()


def test_crosscheck_draw_golden_vector():
    draw = crosscheck_draw([f"run-{i:02}" for i in reversed(range(20))])
    assert draw["run_ids"] == [
        "run-01", "run-10", "run-19", "run-17", "run-04",
        "run-08", "run-03", "run-11", "run-02", "run-18",
    ]

