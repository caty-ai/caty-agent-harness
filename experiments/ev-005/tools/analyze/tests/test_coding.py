from __future__ import annotations

from pathlib import Path

import pytest

from coding import Adjudication, code_run
from load import RunRecord


def record(
    *, arm="B+", declarations=True, end="delivered", events=None,
    snapshot_failure=None,
) -> RunRecord:
    event_rows = list(events or [])
    decls = []
    if declarations:
        declaration = {
            "event": "declaration", "seq": 2, "marker": "deliver" if arm == "W" else "DONE-DECLARE",
            "snapshot_sha": None if snapshot_failure else "a" * 40,
            "snapshot_failure": snapshot_failure, "scored": True,
        }
        event_rows.insert(0, declaration)
        decls = [declaration]
    return RunRecord(
        ledger={"run_id": f"run-{arm}", "task_id": "t01", "arm": arm, "replicate": 1},
        attempt_dir=Path("."), header={}, events=event_rows,
        trailer={"end_reason": end, "declarations_scored": len(decls)},
        declarations=decls, snapshot_entries={},
    )


@pytest.mark.parametrize(
    ("run", "adjudication", "removed", "expected"),
    [
        (record(events=[{"event": "canary_check", "seq": 3, "hit": True}]), Adjudication(0, False, "reexec", {}), set(), "contaminated"),
        (record(snapshot_failure="archive failure"), None, {"t01"}, "check_bug"),
        (record(end="operator"), Adjudication(0, False, "reexec", {}), set(), "operator_abort"),
        (record(), Adjudication(1, False, "reexec", {}), set(), "false_done"),
        (record(declarations=False, end="wallclock"), None, set(), "timeout"),
        (record(declarations=False, end="abandon", events=[{"event": "abandon", "seq": 1}]), None, set(), "abandon"),
        (record(declarations=False, end="session_end"), None, set(), "session_end"),
        (record(), Adjudication(0, False, "reexec", {}), set(), "verified_pass"),
    ],
)
def test_registered_outcomes(run, adjudication, removed, expected):
    assert code_run(run, adjudication, adjudication, removed_tasks=removed).outcome == expected


def test_contaminated_beats_check_bug_and_verified_pass():
    run = record(
        snapshot_failure="failed",
        events=[{"event": "canary_check", "seq": 3, "hit": True}],
    )
    assert code_run(run, None, None, removed_tasks={"t01"}).outcome == "contaminated"


def test_session_end_with_declaration_is_adjudicated():
    run = record(end="session_end")
    passed = Adjudication(0, False, "reexec", {})
    assert code_run(run, passed, passed, removed_tasks=set()).outcome == "verified_pass"


def test_no_declaration_can_never_be_verified_pass():
    run = record(declarations=False, end="delivered")
    passed = Adjudication(0, False, "reexec", {})
    assert code_run(run, passed, passed, removed_tasks=set()).outcome != "verified_pass"


def test_w_gate_pass_reexecution_fail_is_false_done():
    run = record(
        arm="W",
        events=[{
            "event": "donecheck_invocation", "seq": 3, "invoker": "gate",
            "tree_sha": "a" * 40, "exit": 0, "timed_out": False,
        }],
    )
    failed = Adjudication(1, False, "reexec", {})
    coded = code_run(run, failed, failed, removed_tasks=set())
    assert coded.outcome == "false_done"
    assert coded.w_gate_disagreement


def test_operator_abort_beats_false_done_and_false_done_beats_timeout():
    failed = Adjudication(1, False, "reexec", {})
    operator = record(end="operator")
    assert code_run(operator, failed, failed, removed_tasks=set()).outcome == "operator_abort"
    declared_wallclock = record(end="wallclock")
    assert code_run(declared_wallclock, failed, failed, removed_tasks=set()).outcome == "false_done"


def test_snapshot_failure_is_a_candidate_but_not_auto_check_bug():
    run = record(snapshot_failure="commit failed")
    coded = code_run(run, None, None, removed_tasks=set())
    assert coded.outcome == "false_done"
    assert any("snapshot_failure" in reason for reason in coded.candidate_reasons)


def test_upheld_removed_task_codes_clean_sibling_runs_check_bug():
    passed = Adjudication(0, False, "reexec", {})
    siblings = [record(arm=arm) for arm in ("W", "B+", "B")]
    coded = [
        code_run(run, passed, passed, removed_tasks={"t01"})
        for run in siblings
    ]
    assert {run.outcome for run in coded} == {"check_bug"}
    assert all(run.removed_check_bug_task for run in coded)
    assert all(run.candidate_reasons == [] for run in coded)
