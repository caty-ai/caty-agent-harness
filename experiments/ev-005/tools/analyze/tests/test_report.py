from pathlib import Path

from coding import Adjudication, CodedRun
from load import RunRecord
from report import _adjudication_provenance, _material_change_firings, _subset_result


def _coded(task_id, replicate, arm, verified, *, declarations=True, terminal=True):
    declaration_rows = [{"seq": 1}] if declarations else []
    record = RunRecord(
        ledger={
            "run_id": f"{task_id}-{replicate}-{arm}", "task_id": task_id,
            "arm": arm, "replicate": replicate,
        },
        attempt_dir=Path("."), header={}, events=[], trailer={},
        declarations=declaration_rows, snapshot_entries={},
    )
    adjudication = Adjudication(0, False, "in-run-audit", {}) if terminal else None
    return CodedRun(
        record, "verified_pass" if verified else "false_done", adjudication, adjudication,
        [], None, False, False, False,
    )


def test_material_change_requires_at_least_ten_blocks_and_strict_opposite_sign():
    seats = {
        "opposite": {"blocks": 10, "estimate": -0.1},
        "too-small": {"blocks": 9, "estimate": -1.0},
        "same": {"blocks": 20, "estimate": 0.2},
        "zero": {"blocks": 20, "estimate": 0.0},
    }
    rotations = {"2": {"blocks": 12, "estimate": -0.2}}
    assert _material_change_firings(0.1, seats, rotations) == [
        "seat:opposite", "rotation:2",
    ]


def test_zero_full_estimate_has_no_opposite_sign():
    seats = {"negative": {"blocks": 30, "estimate": -0.5}}
    assert _material_change_firings(0.0, seats, {}) == []


def test_infrastructure_subset_recomputes_task_level_statistic():
    runs = []
    for replicate in (1, 2, 3):
        runs += [
            _coded("t01", replicate, "W", True),
            _coded("t01", replicate, "B+", False),
        ]
    runs += [_coded("t02", 1, "W", False), _coded("t02", 1, "B+", True)]
    result = _subset_result(runs, lambda _: True)
    assert result == {"blocks": 4, "tasks": 2, "estimate": 0.0, "sign": "zero"}


def test_adjudication_provenance_distinguishes_missing_and_not_applicable():
    observed = _coded("t01", 1, "W", True)
    unavailable = _coded("t01", 2, "W", False, terminal=False)
    not_applicable = _coded(
        "t01", 3, "W", False, declarations=False, terminal=False,
    )
    assert _adjudication_provenance(observed) == "in-run-audit"
    assert _adjudication_provenance(unavailable) == "unavailable"
    assert _adjudication_provenance(not_applicable) == "not-applicable"
