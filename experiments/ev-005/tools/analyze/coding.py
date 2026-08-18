"""Outcome coding for the EV-005 pre-registered terminal state machine."""

from __future__ import annotations

import dataclasses
from typing import Any

from load import RunRecord


@dataclasses.dataclass(frozen=True)
class Adjudication:
    exit: int | None
    timed_out: bool
    provenance: str
    source_event: dict[str, Any] | None

    @property
    def passed(self) -> bool:
        return self.exit == 0 and not self.timed_out


@dataclasses.dataclass
class CodedRun:
    record: RunRecord
    outcome: str
    terminal: Adjudication | None
    first: Adjudication | None
    candidate_reasons: list[str]
    operator_reason: str | None
    w_gate_disagreement: bool
    pipeline_disagreement: bool
    removed_check_bug_task: bool

    @property
    def verified(self) -> bool:
        return self.outcome == "verified_pass"


def _invocations(record: RunRecord, invoker: str, tree_sha: str | None) -> list[dict[str, Any]]:
    return [
        event for event in record.events
        if event.get("event") == "donecheck_invocation"
        and event.get("invoker") == invoker
        and (tree_sha is None or event.get("tree_sha") == tree_sha)
    ]


def audit_adjudications(record: RunRecord) -> tuple[Adjudication | None, Adjudication | None]:
    """Return terminal and allowable first-declaration in-run adjudications."""
    if not record.declarations:
        return None, None
    first_decl = record.declarations[0]
    terminal_decl = record.declarations[-1]
    terminal_sha = terminal_decl.get("snapshot_sha")
    terminal_rows = _invocations(record, "pipeline", terminal_sha) if terminal_sha else []
    terminal = None
    if terminal_rows:
        row = terminal_rows[-1]
        terminal = Adjudication(row.get("exit"), bool(row.get("timed_out")), "in-run-audit", row)
    first: Adjudication | None = terminal if first_decl is terminal_decl else None
    if first is None and record.arm == "W" and first_decl.get("snapshot_sha"):
        gate_rows = _invocations(record, "gate", first_decl.get("snapshot_sha"))
        if gate_rows:
            row = gate_rows[-1]
            first = Adjudication(row.get("exit"), bool(row.get("timed_out")), "in-run-audit", row)
    return terminal, first


def _same_result(left: Adjudication, row: dict[str, Any]) -> bool:
    return left.exit == row.get("exit") and left.timed_out == bool(row.get("timed_out"))


def code_run(
    record: RunRecord,
    terminal: Adjudication | None,
    first: Adjudication | None,
    *,
    removed_tasks: set[str],
) -> CodedRun:
    """Code one scoring run in the exact §3.1 priority order.

    A missing or failed retained snapshot makes adjudication impossible and is
    recorded as a check-bug candidate.  Until human adjudication removes the
    task symmetrically, fail-closed ITT coding treats the declaration as a
    non-passing declaration (false_done), never as verified_pass.
    """
    reasons: list[str] = []
    declarations = record.declarations
    terminal_decl = declarations[-1] if declarations else None
    for declaration in declarations:
        if declaration.get("snapshot_failure"):
            reasons.append(
                f"declaration seq {declaration.get('seq')} snapshot_failure: "
                f"{declaration.get('snapshot_failure')}"
            )
    if declarations and terminal is None:
        reasons.append("missing terminal adjudication")
    if terminal and terminal.timed_out:
        reasons.append("terminal adjudication timed out")

    pipeline_disagreement = False
    w_gate_disagreement = False
    if terminal and terminal_decl and terminal_decl.get("snapshot_sha"):
        sha = terminal_decl["snapshot_sha"]
        pipeline_rows = _invocations(record, "pipeline", sha)
        if terminal.provenance == "reexec" and pipeline_rows:
            if not _same_result(terminal, pipeline_rows[-1]):
                pipeline_disagreement = True
                reasons.append("re-execution disagrees with in-run pipeline adjudication")
        if record.arm == "W":
            gate_rows = _invocations(record, "gate", sha)
            if gate_rows and not _same_result(terminal, gate_rows[-1]):
                w_gate_disagreement = True
                reasons.append("re-execution disagrees with W gate")

    contaminated = any(
        e.get("event") == "canary_check" and e.get("hit") is True for e in record.events
    )
    operator_reason = record.audit_fallback_reason or next(
        (str(e.get("reason")) for e in record.events if e.get("event") == "operator_intervention"),
        None,
    )
    removed = record.task_id in removed_tasks

    # Exact registered priority: contaminated > check_bug > operator_abort >
    # false_done > timeout > abandon > session_end > verified_pass.
    if contaminated:
        outcome = "contaminated"
    elif removed:
        outcome = "check_bug"
    elif record.trailer.get("end_reason") == "operator":
        outcome = "operator_abort"
    elif declarations and (
        terminal is None or not terminal.passed or (record.arm == "W" and w_gate_disagreement)
    ):
        outcome = "false_done"
    elif not declarations and record.trailer.get("end_reason") == "wallclock":
        outcome = "timeout"
    elif not declarations and any(e.get("event") == "abandon" for e in record.events):
        outcome = "abandon"
    elif not declarations and record.trailer.get("end_reason") == "session_end":
        outcome = "session_end"
    elif declarations and terminal is not None and terminal.passed:
        outcome = "verified_pass"
    else:
        # No-declaration runs are never allowed to fall through to success.
        outcome = "operator_abort"
        reasons.append(f"unclassified terminal evidence: {record.trailer.get('end_reason')!r}")

    return CodedRun(
        record=record,
        outcome=outcome,
        terminal=terminal,
        first=first,
        candidate_reasons=sorted(set(reasons)),
        operator_reason=operator_reason,
        w_gate_disagreement=w_gate_disagreement,
        pipeline_disagreement=pipeline_disagreement,
        removed_check_bug_task=removed,
    )
