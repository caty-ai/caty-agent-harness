from __future__ import annotations

import json
import importlib.util
import hashlib
from pathlib import Path
import sys

import pytest

from coding import audit_adjudications, code_run
from conftest import write_jsonl
from load import (
    LEDGER_ABORT_AUDIT_UNAVAILABLE_REASON,
    InputValidationError,
    load_analysis_data,
    resolve_attempt_dir,
)


def _audit_path(fixture_tree, row: dict) -> Path:
    parts = Path(row["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    return fixture_tree["out"].joinpath(*suffix) / "audit.jsonl"


def _write_all_snapshot_indexes(fixture_tree) -> None:
    for row in fixture_tree["ledger"]:
        parts = Path(row["output"]).parts
        suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
        attempt = fixture_tree["out"].joinpath(*suffix)
        audit = [json.loads(line) for line in (attempt / "audit.jsonl").read_text().splitlines()]
        declaration = audit[1]
        snapshots = attempt / "snapshots"
        snapshots.mkdir(exist_ok=True)
        archive = snapshots / f"decl-1-{declaration['snapshot_sha'][:12]}.tar.gz"
        archive.write_bytes(b"fixture archive")
        (snapshots / "index.json").write_text(json.dumps({
            "protocol": 1,
            "run_id": row["run_id"],
            "entries": [{
                "seq": 1,
                "marker": declaration["marker"],
                "snapshot_sha": declaration["snapshot_sha"],
                "archive": archive.name,
                "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            }],
        }))


def test_portable_output_rebases_from_original_out_root(fixture_tree):
    path = resolve_attempt_dir(
        fixture_tree["out"],
        "/different/machine/original-out/runs/t01-k1/w/attempt-001",
    )
    assert path == (fixture_tree["out"] / "runs/t01-k1/w/attempt-001").resolve()


def test_relative_output_is_resolved_under_out_root(fixture_tree):
    path = resolve_attempt_dir(
        fixture_tree["out"],
        "runs/t01-k1/w/attempt-001",
    )
    assert path == (fixture_tree["out"] / "runs/t01-k1/w/attempt-001").resolve()


def test_missing_cell_aborts_with_named_complete_error(fixture_tree):
    rows = fixture_tree["ledger"][:-1]
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", rows)
    with pytest.raises(InputValidationError) as caught:
        load_analysis_data(fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False)
    assert "has 0 scoring attempts" in str(caught.value)


def test_duplicate_scoring_attempt_aborts(fixture_tree):
    duplicate = dict(fixture_tree["ledger"][0])
    duplicate["run_id"] += "-duplicate"
    duplicate["output"] = duplicate["output"].replace("attempt-001", "attempt-002")
    source = fixture_tree["out"] / "runs/t01-k1/w/attempt-001/audit.jsonl"
    target = fixture_tree["out"] / "runs/t01-k1/w/attempt-002/audit.jsonl"
    target.parent.mkdir(parents=True)
    audit = [json.loads(line) for line in source.read_text().splitlines()]
    audit[0]["run_id"] = duplicate["run_id"]
    write_jsonl(target, audit)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"] + [duplicate])
    with pytest.raises(InputValidationError) as caught:
        load_analysis_data(fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False)
    assert "has 2 scoring attempts" in str(caught.value)


def test_loader_reports_complete_sealed_schema_errors(fixture_tree):
    ledger = fixture_tree["ledger"]
    del ledger[0]["status_reason"]
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", ledger)
    second = ledger[1]
    parts = Path(second["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    audit_path = fixture_tree["out"].joinpath(*suffix) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    del audit[0]["model_id"]
    write_jsonl(audit_path, audit)
    with pytest.raises(InputValidationError) as caught:
        load_analysis_data(fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False)
    message = str(caught.value)
    assert "missing fields ['status_reason']" in message
    assert "audit header schema mismatch (missing=['model_id'], extra=[])" in message


def test_snapshot_failure_is_omitted_from_index_without_loader_abort(fixture_tree):
    attempt = fixture_tree["out"] / "runs/t01-k1/w/attempt-001"
    rows = [json.loads(line) for line in (attempt / "audit.jsonl").read_text().splitlines()]
    rows[1]["snapshot_failure"] = "commit failed"
    rows[1]["snapshot_sha"] = None
    rows[2]["tree_sha"] = None
    snapshots = attempt / "snapshots"
    snapshots.mkdir()
    (snapshots / "index.json").write_text(json.dumps({
        "protocol": 1, "run_id": rows[0]["run_id"], "entries": [],
    }))
    write_jsonl(attempt / "audit.jsonl", rows)
    # Other successful declarations need their protocol indexes in docker mode.
    for row in fixture_tree["ledger"][1:]:
        parts = Path(row["output"]).parts
        suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
        run_attempt = fixture_tree["out"].joinpath(*suffix)
        audit = [json.loads(line) for line in (run_attempt / "audit.jsonl").read_text().splitlines()]
        declaration = audit[1]
        snapshot_dir = run_attempt / "snapshots"
        snapshot_dir.mkdir()
        archive = snapshot_dir / f"decl-1-{declaration['snapshot_sha'][:12]}.tar.gz"
        archive.write_bytes(b"not used by trust mode")
        import hashlib
        (snapshot_dir / "index.json").write_text(json.dumps({
            "protocol": 1, "run_id": audit[0]["run_id"], "entries": [{
                "seq": 1, "marker": declaration["marker"],
                "snapshot_sha": declaration["snapshot_sha"], "archive": archive.name,
                "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            }],
        }))
    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=True
    )
    failed = next(run for run in loaded.runs if run.run_id == rows[0]["run_id"])
    assert failed.snapshot_entries == {}
    assert failed.declarations[0]["snapshot_failure"] == "commit failed"


def test_void_scoring_row_is_excluded_and_block_without_valid_wave_two_stops(fixture_tree):
    row = fixture_tree["ledger"][0]
    row["void"] = True
    row["void_reason"] = "INFRASTRUCTURE: synthetic first-wave void"
    assert row["scoring_attempt"] is True
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    assert row["block_id"] in loaded.stopped_blocks
    assert row["run_id"] not in {run.run_id for run in loaded.runs}
    assert len(loaded.runs) == 15


def test_trailer_infrastructure_void_also_excludes_scoring_row(fixture_tree):
    row = fixture_tree["ledger"][0]
    parts = Path(row["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    audit_path = fixture_tree["out"].joinpath(*suffix) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    audit[-1]["infrastructure_void"] = True
    audit[-1]["infrastructure_void_reason"] = "trailer-only void"
    write_jsonl(audit_path, audit)

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    assert row["block_id"] in loaded.stopped_blocks
    assert row["run_id"] not in {run.run_id for run in loaded.runs}
    assert loaded.voided_attempts[0]["reasons"] == ["trailer-only void"]


def test_void_block_does_not_mask_separate_unexplained_missing_cell(fixture_tree):
    row = fixture_tree["ledger"][0]
    row["void"] = True
    row["void_reason"] = "synthetic void"
    rows = fixture_tree["ledger"][:-1]
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", rows)
    with pytest.raises(InputValidationError) as caught:
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
        )
    message = str(caught.value)
    assert "('t02', 3, 'B') has 0 scoring attempts" in message
    assert "('t01', 1" not in message


def test_loader_schema_sets_match_runner_exactly():
    runner_path = Path(__file__).resolve().parents[5] / "runners/alec/ev005/runner.py"
    spec = importlib.util.spec_from_file_location("ev005_runner_schema_pin", runner_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    from load import HEADER_FIELDS, TRAILER_FIELDS
    assert HEADER_FIELDS == module.HEADER_FIELDS
    assert TRAILER_FIELDS == module.TRAILER_FIELDS


def test_extra_audit_header_field_aborts_exact_schema_check(fixture_tree):
    row = fixture_tree["ledger"][0]
    parts = Path(row["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    audit_path = fixture_tree["out"].joinpath(*suffix) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    audit[0]["unsealed_extra"] = True
    write_jsonl(audit_path, audit)
    with pytest.raises(InputValidationError, match="extra=\\['unsealed_extra'\\]"):
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
        )


def test_agent_null_digest_with_observation_error_is_accepted(fixture_tree):
    target = fixture_tree["ledger"][1]
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    invocation = next(row for row in audit if row.get("event") == "donecheck_invocation")
    invocation["invoker"] = "agent"
    invocation["stdout_digest"] = None
    invocation["observation_error"] = "concurrent-descendants-stdout-unattributable"
    write_jsonl(audit_path, audit)

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    assert len(loaded.runs) == 18


@pytest.mark.parametrize("invoker", ["gate", "pipeline"])
def test_runner_invoker_null_digest_still_aborts(fixture_tree, invoker):
    target = next(
        row for row in fixture_tree["ledger"]
        if row["arm"] == "W" or invoker == "pipeline"
    )
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    invocation = next(
        row for row in audit
        if row.get("event") == "donecheck_invocation" and row.get("invoker") == invoker
    )
    invocation["stdout_digest"] = None
    invocation["observation_error"] = "synthetic runner observation loss"
    write_jsonl(audit_path, audit)

    with pytest.raises(InputValidationError, match="invalid stdout_digest"):
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
        )


@pytest.mark.parametrize("observation_error", [None, ""])
def test_agent_null_digest_requires_nonempty_observation_error(
    fixture_tree, observation_error,
):
    target = fixture_tree["ledger"][1]
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    invocation = next(row for row in audit if row.get("event") == "donecheck_invocation")
    invocation["invoker"] = "agent"
    invocation["stdout_digest"] = None
    invocation["observation_error"] = observation_error
    write_jsonl(audit_path, audit)

    with pytest.raises(InputValidationError, match="invalid stdout_digest"):
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
        )


def test_incomplete_ledger_row_with_operator_trailer_is_coded_from_audit(fixture_tree):
    target = fixture_tree["ledger"][0]
    target["completed"] = False
    target["status_reason"] = "quota abort"
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    audit[-1]["end_reason"] = "operator"
    write_jsonl(audit_path, audit)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    record = next(run for run in loaded.runs if run.run_id == target["run_id"])
    terminal, first = audit_adjudications(record)
    coded = code_run(record, terminal, first, removed_tasks=set())
    assert len(loaded.runs) == 18
    assert record.ledger_incomplete is True
    assert record.audit_fallback_reason is None
    assert coded.outcome == "operator_abort"


def test_incomplete_ledger_row_with_trailer_keeps_strict_audit_validation(fixture_tree):
    target = fixture_tree["ledger"][0]
    target["completed"] = False
    target["status_reason"] = "quota abort"
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    del audit[0]["model_id"]
    write_jsonl(audit_path, audit)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    with pytest.raises(InputValidationError, match="audit header schema mismatch"):
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
        )


def test_incomplete_ledger_row_with_wallclock_trailer_is_coded_from_audit(fixture_tree):
    target = fixture_tree["ledger"][1]
    target["completed"] = False
    target["status_reason"] = "exit marker lost"
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    trailer = audit[-1]
    trailer["end_reason"] = "wallclock"
    trailer["declarations_scored"] = 0
    write_jsonl(audit_path, [
        audit[0],
        {"event": "canary_check", "seq": 1, "ts": "x", "rule_id": "r",
         "hit": False, "scope": "output"},
        trailer,
    ])
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    record = next(run for run in loaded.runs if run.run_id == target["run_id"])
    terminal, first = audit_adjudications(record)
    coded = code_run(record, terminal, first, removed_tasks=set())
    assert len(loaded.runs) == 18
    assert record.ledger_incomplete is True
    assert record.audit_fallback_reason is None
    assert coded.outcome == "timeout"


def test_incomplete_ledger_row_without_trailer_uses_operator_abort_fallback(fixture_tree):
    target = fixture_tree["ledger"][2]
    target["completed"] = False
    target["status_reason"] = "CLI crash"
    audit_path = _audit_path(fixture_tree, target)
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    write_jsonl(audit_path, audit[:-1])
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=False,
    )
    record = next(run for run in loaded.runs if run.run_id == target["run_id"])
    terminal, first = audit_adjudications(record)
    coded = code_run(record, terminal, first, removed_tasks=set())
    assert len(loaded.runs) == 18
    assert record.ledger_incomplete is True
    assert record.audit_fallback_reason == LEDGER_ABORT_AUDIT_UNAVAILABLE_REASON
    assert coded.outcome == "operator_abort"
    assert coded.operator_reason == LEDGER_ABORT_AUDIT_UNAVAILABLE_REASON


def test_retention_failure_marker_is_accepted_and_archives_are_ignored(fixture_tree):
    _write_all_snapshot_indexes(fixture_tree)
    target = fixture_tree["ledger"][0]
    parts = Path(target["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    snapshots = fixture_tree["out"].joinpath(*suffix) / "snapshots"
    (snapshots / "export-error.json").write_text(json.dumps({
        "protocol": 1,
        "run_id": target["run_id"],
        "stage": "validate",
        "error": "synthetic retention validation failure",
    }))
    # Deliberately corrupt an accompanying archive: the marker makes the whole
    # retention set untrusted, so archive contents must not be consulted.
    archive = next(snapshots.glob("*.tar.gz"))
    archive.write_bytes(b"corrupt but ignored")

    loaded = load_analysis_data(
        fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=True,
    )
    record = next(run for run in loaded.runs if run.run_id == target["run_id"])
    assert record.snapshot_entries == {}
    assert record.retention_failure == {
        "protocol": 1,
        "run_id": target["run_id"],
        "stage": "validate",
        "error": "synthetic retention validation failure",
    }


def test_docker_mode_missing_snapshot_directory_for_scored_declaration_aborts(fixture_tree):
    with pytest.raises(InputValidationError) as caught:
        load_analysis_data(
            fixture_tree["out"], fixture_tree["tasks"], "main", require_snapshots=True,
        )
    assert "snapshots/index.json missing" in str(caught.value)
