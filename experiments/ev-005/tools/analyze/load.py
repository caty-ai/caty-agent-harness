"""Fail-closed readers for EV-005 ledgers, audits, and retained snapshots."""

from __future__ import annotations

import dataclasses
import hashlib
import json
from pathlib import Path
from typing import Any


ARMS = ("W", "B+", "B")
LEDGER_FIELDS = {
    "run_id", "task_id", "arm", "replicate", "block_id", "rank", "seat",
    "slot_index", "series", "cell", "attempt", "scoring_attempt", "completed",
    "void", "void_reason", "output", "start_ts", "end_ts", "exit_status",
    "status_reason",
}
# Mirrored exactly from runners/alec/ev005/runner.py.  The analysis package stays
# runtime-stdlib-only; a regression test imports runner.py and pins equality.
HEADER_FIELDS = {
    "run_id", "task_id", "arm", "cell", "model_id", "harness_version", "operator",
    "replica_sha", "env_fingerprint", "start_ts", "worker_id", "account_id",
    "block_id", "slot_index", "agent_argv", "mcp_config_digest",
    "observation_config_digest", "controller_config_digest",
}
TRAILER_FIELDS = {
    "end_ts", "end_reason", "declarations_scored", "wallclock_s", "paused_s", "elapsed_s",
    "provider_wait_s", "provider_retry_count", "provider_throttle_count",
    "provider_longest_stall_s", "infrastructure_void",
    "infrastructure_void_reason",
}
END_REASONS = {"delivered", "wallclock", "abandon", "session_end", "operator"}
LEDGER_ABORT_AUDIT_UNAVAILABLE_REASON = (
    "infra-integrity: ledger-recorded abort, audit trailer unavailable"
)


class InputValidationError(ValueError):
    """Raised once with every input-integrity error found in a load pass."""

    def __init__(self, errors: list[str]):
        self.errors = sorted(set(errors))
        super().__init__("input validation failed:\n" + "\n".join(f"- {e}" for e in self.errors))


@dataclasses.dataclass(frozen=True)
class Task:
    task_id: str
    path: Path
    meta: dict[str, Any]


@dataclasses.dataclass
class RunRecord:
    ledger: dict[str, Any]
    attempt_dir: Path
    header: dict[str, Any]
    events: list[dict[str, Any]]
    trailer: dict[str, Any]
    declarations: list[dict[str, Any]]
    snapshot_entries: dict[int, dict[str, Any]]
    retention_failure: dict[str, Any] | None = None
    ledger_incomplete: bool = False
    audit_fallback_reason: str | None = None

    @property
    def run_id(self) -> str:
        return str(self.ledger["run_id"])

    @property
    def task_id(self) -> str:
        return str(self.ledger["task_id"])

    @property
    def arm(self) -> str:
        return str(self.ledger["arm"])


@dataclasses.dataclass
class LoadedData:
    tasks: dict[str, Task]
    runs: list[RunRecord]
    ledger_rows: list[dict[str, Any]]
    stopped_blocks: dict[str, list[str]] = dataclasses.field(default_factory=dict)
    voided_attempts: list[dict[str, Any]] = dataclasses.field(default_factory=list)


def _read_json(path: Path, label: str, errors: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"{label}: {exc}")
        return None


def _read_jsonl(path: Path, label: str, errors: list[str]) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        errors.append(f"{label}: {exc}")
        return []
    if not lines:
        errors.append(f"{label}: empty file")
        return []
    rows: list[dict[str, Any]] = []
    for number, line in enumerate(lines, 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"{label}:{number}: malformed JSON: {exc.msg}")
            continue
        if not isinstance(row, dict):
            errors.append(f"{label}:{number}: row is not an object")
            continue
        rows.append(row)
    return rows


def _read_incomplete_audit(path: Path) -> list[dict[str, Any]] | None:
    """Return a fully parseable incomplete-run audit, without widening normal tolerance."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return None
    if not lines:
        return None
    rows: list[dict[str, Any]] = []
    for line in lines:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            return None
        if not isinstance(row, dict):
            return None
        rows.append(row)
    return rows


def _has_trailer_candidate(rows: list[dict[str, Any]]) -> bool:
    """Distinguish trailer-less audits from present-but-invalid trailers."""
    return len(rows) >= 2 and "end_reason" in rows[-1]


def load_tasks(tasks_dir: Path, errors: list[str]) -> dict[str, Task]:
    tasks: dict[str, Task] = {}
    if not tasks_dir.is_dir():
        errors.append(f"tasks directory missing: {tasks_dir}")
        return tasks
    for child in sorted(tasks_dir.iterdir(), key=lambda p: p.name):
        if not child.is_dir() or not (child / "meta.json").is_file():
            continue
        meta = _read_json(child / "meta.json", f"task {child.name} meta", errors)
        if not isinstance(meta, dict):
            continue
        task_id = meta.get("id")
        required = {"id", "source_repo", "pre_fix", "fix", "source_issue", "synthetic", "timeout_s"}
        missing = sorted(required - set(meta))
        if missing:
            errors.append(f"task {child.name}: meta missing fields {missing}")
            continue
        if not isinstance(task_id, str) or not task_id or task_id != child.name:
            errors.append(f"task {child.name}: meta id mismatch")
            continue
        if task_id in tasks:
            errors.append(f"duplicate task id: {task_id}")
            continue
        if not (child / "donecheck.sh").is_file():
            errors.append(f"task {task_id}: donecheck.sh missing")
        timeout = meta.get("timeout_s")
        if not isinstance(timeout, (int, float)) or isinstance(timeout, bool) or timeout <= 0:
            errors.append(f"task {task_id}: timeout_s must be positive")
        tasks[task_id] = Task(task_id, child.resolve(), meta)
    if not tasks:
        errors.append(f"no tasks found under {tasks_dir}")
    return tasks


def resolve_attempt_dir(out_root: Path, output: Any) -> Path:
    """Resolve the ledger's attempt suffix under the supplied out-root."""
    if not isinstance(output, str) or not output:
        raise ValueError("output is missing")
    parts = Path(output).parts
    matches = [i for i, part in enumerate(parts) if part == "runs"]
    if not matches:
        raise ValueError("output does not contain a runs/ attempt suffix")
    suffix = parts[matches[-1] :]
    valid_attempt = (
        len(suffix) == 4
        and suffix[0] == "runs"
        and suffix[3].startswith("attempt-")
        and suffix[3][len("attempt-"):].isdigit()
    )
    if not valid_attempt or any(part in {"", ".", ".."} for part in suffix):
        raise ValueError("output suffix must be runs/<block>/<arm>/attempt-NNN")
    candidate = out_root.joinpath(*suffix).resolve()
    try:
        candidate.relative_to(out_root.resolve())
    except ValueError as exc:
        raise ValueError("rebased output escapes out-root") from exc
    return candidate


def _load_snapshot_index(
    record_label: str,
    attempt_dir: Path,
    run_id: str,
    declarations: list[dict[str, Any]],
    require_snapshots: bool,
    errors: list[str],
) -> tuple[dict[int, dict[str, Any]], dict[str, Any] | None]:
    snapshots = attempt_dir / "snapshots"
    index_path = snapshots / "index.json"
    error_path = snapshots / "export-error.json"
    successful = [d for d in declarations if d.get("snapshot_sha") is not None]
    if snapshots.is_symlink():
        errors.append(f"{record_label}: snapshots directory is a symlink")
        return {}, None
    if error_path.exists():
        if error_path.is_symlink() or not error_path.is_file():
            errors.append(f"{record_label}: snapshot retention error marker is unsafe")
            return {}, None
        failure = _read_json(error_path, f"{record_label} retention failure", errors)
        if not isinstance(failure, dict):
            return {}, None
        if set(failure) != {"protocol", "run_id", "stage", "error"}:
            errors.append(f"{record_label}: retention failure schema mismatch")
        if failure.get("protocol") != 1 or failure.get("run_id") != run_id:
            errors.append(f"{record_label}: retention failure protocol/run_id mismatch")
        if failure.get("stage") not in {"export", "copy", "validate"}:
            errors.append(f"{record_label}: retention failure stage is invalid")
        if not isinstance(failure.get("error"), str) or not failure.get("error"):
            errors.append(f"{record_label}: retention failure error is empty")
        # Any archives beside the marker are explicitly untrusted and ignored.
        return {}, failure
    if not index_path.is_file():
        if require_snapshots and declarations:
            errors.append(f"{record_label}: snapshots/index.json missing")
        return {}, None
    if index_path.is_symlink():
        errors.append(f"{record_label}: snapshot index is a symlink")
        return {}, None
    index = _read_json(index_path, f"{record_label} snapshot index", errors)
    if not isinstance(index, dict):
        return {}, None
    if set(index) != {"protocol", "run_id", "entries"}:
        errors.append(f"{record_label}: snapshot index schema mismatch")
        return {}, None
    if index.get("protocol") != 1 or index.get("run_id") != run_id:
        errors.append(f"{record_label}: snapshot index protocol/run_id mismatch")
    entries = index.get("entries")
    if not isinstance(entries, list):
        errors.append(f"{record_label}: snapshot entries is not a list")
        return {}, None
    expected = {
        int(d["seq"]): (d.get("marker"), d.get("snapshot_sha"))
        for d in successful
        if type(d.get("seq")) is int
    }
    by_seq: dict[int, dict[str, Any]] = {}
    previous = -1
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {
            "seq", "marker", "snapshot_sha", "archive", "archive_sha256"
        }:
            errors.append(f"{record_label}: snapshot entry schema mismatch")
            continue
        seq = entry.get("seq")
        if type(seq) is not int or seq <= previous:
            errors.append(f"{record_label}: snapshot entry seq not strictly increasing")
            continue
        previous = seq
        if seq in by_seq:
            errors.append(f"{record_label}: duplicate snapshot seq {seq}")
            continue
        if expected.get(seq) != (entry.get("marker"), entry.get("snapshot_sha")):
            errors.append(f"{record_label}: snapshot entry {seq} does not exactly match audit declaration")
        sha = entry.get("snapshot_sha")
        archive = entry.get("archive")
        digest = entry.get("archive_sha256")
        expected_name = f"decl-{seq}-{str(sha)[:12]}.tar.gz"
        if archive != expected_name:
            errors.append(f"{record_label}: snapshot archive name mismatch at seq {seq}")
        if (
            not isinstance(sha, str) or len(sha) != 40
            or any(character not in "0123456789abcdef" for character in sha)
        ):
            errors.append(f"{record_label}: invalid snapshot SHA at seq {seq}")
        if (
            not isinstance(digest, str) or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            errors.append(f"{record_label}: invalid archive digest at seq {seq}")
        archive_path = snapshots / str(archive)
        if archive_path.is_symlink() or not archive_path.is_file():
            errors.append(f"{record_label}: snapshot archive missing/unsafe at seq {seq}")
        else:
            actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            if actual != digest:
                errors.append(f"{record_label}: snapshot archive digest mismatch at seq {seq}")
        by_seq[seq] = {**entry, "path": str(archive_path)}
    if set(by_seq) != set(expected):
        errors.append(
            f"{record_label}: snapshot entries must exactly equal successful scored declarations "
            f"(entries={sorted(by_seq)}, declarations={sorted(expected)})"
        )
    if snapshots.is_dir():
        expected_names = {"index.json"} | {str(entry.get("archive")) for entry in entries if isinstance(entry, dict)}
        actual_names = {path.name for path in snapshots.iterdir()}
        if actual_names != expected_names:
            errors.append(
                f"{record_label}: snapshot directory files differ from index "
                f"(actual={sorted(actual_names)}, expected={sorted(expected_names)})"
            )
    return by_seq, None


def load_analysis_data(
    out_root: Path, tasks_dir: Path, series: str, *, require_snapshots: bool
) -> LoadedData:
    errors: list[str] = []
    out_root = out_root.resolve()
    tasks = load_tasks(tasks_dir.resolve(), errors)
    ledger_path = out_root / "ledger.jsonl"
    ledger_rows = _read_jsonl(ledger_path, "ledger.jsonl", errors) if ledger_path.is_file() else []
    if not ledger_path.is_file():
        errors.append(f"ledger missing: {ledger_path}")
    relevant: list[dict[str, Any]] = []
    seen_run_ids: set[str] = set()
    for index, row in enumerate(ledger_rows, 1):
        missing = sorted(LEDGER_FIELDS - set(row))
        if missing:
            errors.append(f"ledger row {index}: missing fields {missing}")
            continue
        if row.get("series") != series:
            continue
        run_id = row.get("run_id")
        if not isinstance(run_id, str) or not run_id:
            errors.append(f"series {series} ledger row {index}: invalid run_id")
        elif run_id in seen_run_ids:
            errors.append(f"series {series} ledger row {index}: duplicate run_id {run_id!r}")
        else:
            seen_run_ids.add(run_id)
        relevant.append(row)
    expected = {(task, replicate, arm) for task in tasks for replicate in (1, 2, 3) for arm in ARMS}
    audit_cache: dict[str, tuple[Path, list[dict[str, Any]]]] = {}
    unavailable_incomplete_audits: set[str] = set()
    void_run_ids: set[str] = set()
    voided_attempts: list[dict[str, Any]] = []
    by_block: dict[str, list[dict[str, Any]]] = {}
    for index, row in enumerate(relevant, 1):
        task_id, replicate, arm = row.get("task_id"), row.get("replicate"), row.get("arm")
        if task_id not in tasks:
            errors.append(f"series {series} ledger row {index}: unknown task {task_id!r}")
        if arm not in ARMS:
            errors.append(f"series {series} ledger row {index}: invalid arm {arm!r}")
        if replicate not in (1, 2, 3):
            errors.append(f"series {series} ledger row {index}: invalid replicate {replicate!r}")
        for boolean_field in ("scoring_attempt", "completed", "void"):
            if type(row.get(boolean_field)) is not bool:
                errors.append(
                    f"series {series} ledger row {index}: {boolean_field} is not boolean"
                )
        attempt = row.get("attempt")
        if type(attempt) is not int or attempt < 1:
            errors.append(f"series {series} ledger row {index}: invalid attempt {attempt!r}")
        block_id = row.get("block_id")
        if not isinstance(block_id, str) or not block_id:
            errors.append(f"series {series} ledger row {index}: invalid block_id")
            continue
        by_block.setdefault(block_id, []).append(row)

        run_id = row.get("run_id")
        trailer_void = False
        trailer_reason = None
        # Completed non-void rows remain strictly inspectable.  A scoring row
        # whose ledger completion marker was lost may use the evidence-backed
        # incomplete-audit fallback, but only when its audit/trailer cannot be
        # parsed coherently.
        inspect_incomplete = (
            row.get("scoring_attempt") is True and row.get("completed") is False
        )
        if (
            row.get("void") is not True
            and (row.get("completed") is True or inspect_incomplete)
            and isinstance(run_id, str)
        ):
            label = f"run {run_id}"
            try:
                attempt_dir = resolve_attempt_dir(out_root, row.get("output"))
            except ValueError as exc:
                errors.append(f"{label}: {exc}")
            else:
                audit_path = attempt_dir / "audit.jsonl"
                if inspect_incomplete:
                    audit_rows = (
                        _read_incomplete_audit(audit_path) if audit_path.is_file() else None
                    )
                    if audit_rows is None or not _has_trailer_candidate(audit_rows):
                        unavailable_incomplete_audits.add(run_id)
                    else:
                        audit_cache[run_id] = (attempt_dir, audit_rows)
                elif not audit_path.is_file():
                    errors.append(f"{label}: completed attempt audit.jsonl missing at {attempt_dir}")
                else:
                    audit_rows = _read_jsonl(audit_path, f"{label} audit", errors)
                    audit_cache[run_id] = (attempt_dir, audit_rows)
                cached_audit = audit_cache.get(run_id)
                if cached_audit is not None and len(cached_audit[1]) >= 2:
                    trailer_void = cached_audit[1][-1].get("infrastructure_void") is True
                    trailer_reason = cached_audit[1][-1].get("infrastructure_void_reason")
        if row.get("void") is True or trailer_void:
            if isinstance(run_id, str):
                void_run_ids.add(run_id)
            reasons = []
            if row.get("void_reason"):
                reasons.append(str(row["void_reason"]))
            if trailer_reason and str(trailer_reason) not in reasons:
                reasons.append(str(trailer_reason))
            voided_attempts.append({
                "run_id": run_id,
                "task_id": task_id,
                "arm": arm,
                "replicate": replicate,
                "block_id": block_id,
                "attempt": attempt,
                "reasons": reasons or ["infrastructure void; no reason recorded"],
            })

    stopped_blocks: dict[str, list[str]] = {}
    for block_id, rows in sorted(by_block.items()):
        void_rows = [row for row in rows if row.get("run_id") in void_run_ids]
        if not void_rows:
            continue
        attempt_two_void = any(row.get("attempt") == 2 for row in void_rows)
        valid_wave_two_arms = {
            str(row.get("arm")) for row in rows
            if row.get("attempt") == 2
            and row.get("scoring_attempt") is True
            and row.get("completed") is True
            and row.get("run_id") not in void_run_ids
        }
        if attempt_two_void or valid_wave_two_arms != set(ARMS):
            reasons = [
                f"{item['run_id']} ({item['arm']}, attempt {item['attempt']}): "
                + "; ".join(item["reasons"])
                for item in voided_attempts if item["block_id"] == block_id
            ]
            stopped_blocks[block_id] = sorted(reasons)

    stopped_cells: set[tuple[str, int, str]] = set()
    for block_id in sorted(stopped_blocks):
        coordinates = {
            (row.get("task_id"), row.get("replicate")) for row in by_block[block_id]
        }
        if len(coordinates) != 1:
            errors.append(f"stopped block {block_id}: inconsistent task/replicate coordinates")
            continue
        task_id, replicate = next(iter(coordinates))
        stopped_cells.update((task_id, replicate, arm) for arm in ARMS)

    scoring_expected = expected - stopped_cells
    scoring: dict[tuple[str, int, str], list[dict[str, Any]]] = {
        key: [] for key in scoring_expected
    }
    for row in relevant:
        key = (row.get("task_id"), row.get("replicate"), row.get("arm"))
        if (
            key in scoring
            and row.get("scoring_attempt") is True
            and type(row.get("completed")) is bool
            and row.get("run_id") not in void_run_ids
        ):
            scoring[key].append(row)
    for key in sorted(scoring_expected):
        count = len(scoring[key])
        if count != 1:
            errors.append(f"scoring cell {key} has {count} scoring attempts; expected exactly 1")

    records: list[RunRecord] = []
    for key in sorted(scoring_expected):
        if len(scoring[key]) != 1:
            continue
        row = scoring[key][0]
        label = f"run {row.get('run_id')}"
        ledger_incomplete = row.get("completed") is False
        cached = audit_cache.get(str(row.get("run_id")))
        if cached is None:
            if ledger_incomplete and str(row.get("run_id")) in unavailable_incomplete_audits:
                try:
                    attempt_dir = resolve_attempt_dir(out_root, row.get("output"))
                except ValueError as exc:
                    errors.append(f"{label}: {exc}")
                    continue
                records.append(RunRecord(
                    row, attempt_dir, {}, [], {"end_reason": "operator"}, [], {},
                    None, True, LEDGER_ABORT_AUDIT_UNAVAILABLE_REASON,
                ))
                continue
            errors.append(f"{label}: scoring attempt audit was not loaded")
            continue
        attempt_dir, audit_rows = cached
        if len(audit_rows) < 2:
            errors.append(f"{label}: audit missing header or trailer")
            continue
        header, trailer = audit_rows[0], audit_rows[-1]
        events = audit_rows[1:-1]
        if set(header) != HEADER_FIELDS:
            errors.append(
                f"{label}: audit header schema mismatch "
                f"(missing={sorted(HEADER_FIELDS - set(header))}, "
                f"extra={sorted(set(header) - HEADER_FIELDS)})"
            )
        if set(trailer) != TRAILER_FIELDS:
            errors.append(
                f"{label}: audit trailer schema mismatch "
                f"(missing={sorted(TRAILER_FIELDS - set(trailer))}, "
                f"extra={sorted(set(trailer) - TRAILER_FIELDS)})"
            )
        if trailer.get("end_reason") not in END_REASONS:
            errors.append(f"{label}: invalid trailer end_reason {trailer.get('end_reason')!r}")
        for field in ("run_id", "task_id", "arm", "cell"):
            if header.get(field) != row.get(field):
                errors.append(f"{label}: header {field} mismatch vs ledger")
        previous_seq: int | None = None
        for event_index, event in enumerate(events, 1):
            if not isinstance(event.get("event"), str) or "ts" not in event:
                errors.append(f"{label}: event {event_index} missing event or ts")
            seq = event.get("seq")
            if type(seq) is not int:
                errors.append(f"{label}: event {event_index} missing integer seq")
            elif previous_seq is not None and seq <= previous_seq:
                errors.append(f"{label}: event seq is non-monotonic at {seq}")
            else:
                previous_seq = seq
            event_name = event.get("event")
            if event_name == "donecheck_invocation":
                if event.get("invoker") not in {"agent", "gate", "pipeline"}:
                    errors.append(f"{label}: donecheck event {seq} has invalid invoker")
                if type(event.get("exit")) is not int:
                    errors.append(f"{label}: donecheck event {seq} has non-integer exit")
                if type(event.get("timed_out")) is not bool:
                    errors.append(f"{label}: donecheck event {seq} has non-boolean timed_out")
                digest = event.get("stdout_digest")
                degraded_agent_observation = (
                    digest is None
                    and event.get("invoker") == "agent"
                    and isinstance(event.get("observation_error"), str)
                    and bool(event.get("observation_error"))
                )
                if not degraded_agent_observation and (
                    not isinstance(digest, str) or len(digest) != 64
                    or any(character not in "0123456789abcdef" for character in digest)
                ):
                    errors.append(f"{label}: donecheck event {seq} has invalid stdout_digest")
                duration = event.get("duration_ms")
                if not isinstance(duration, (int, float)) or isinstance(duration, bool) or duration < 0:
                    errors.append(f"{label}: donecheck event {seq} has invalid duration_ms")
        all_declarations = [e for e in events if e.get("event") == "declaration"]
        if any(e.get("scored") is not True for e in all_declarations):
            errors.append(f"{label}: declaration event is not scored=true")
        declarations = [e for e in all_declarations if e.get("scored") is True]
        for declaration in declarations:
            if declaration.get("marker") not in {"DONE-DECLARE", "deliver"}:
                errors.append(f"{label}: declaration {declaration.get('seq')} has invalid marker")
            if type(declaration.get("count_after")) is not int or declaration.get("count_after") < 1:
                errors.append(f"{label}: declaration {declaration.get('seq')} has invalid count_after")
            sha, failure = declaration.get("snapshot_sha"), declaration.get("snapshot_failure")
            if failure is None:
                if (
                    not isinstance(sha, str) or len(sha) != 40
                    or any(character not in "0123456789abcdef" for character in sha)
                ):
                    errors.append(f"{label}: declaration {declaration.get('seq')} has invalid snapshot_sha")
            elif not isinstance(failure, str) or not failure or sha is not None:
                errors.append(f"{label}: declaration {declaration.get('seq')} has invalid snapshot_failure")
        if trailer.get("declarations_scored") != len(declarations):
            errors.append(f"{label}: trailer declarations_scored mismatch")
        entries, retention_failure = _load_snapshot_index(
            label, attempt_dir, str(row.get("run_id")), declarations,
            require_snapshots, errors,
        )
        records.append(RunRecord(
            row, attempt_dir, header, events, trailer, declarations, entries,
            retention_failure, ledger_incomplete,
        ))
    if errors:
        raise InputValidationError(errors)
    return LoadedData(
        tasks, sorted(records, key=lambda r: r.run_id), relevant,
        stopped_blocks, sorted(
            voided_attempts,
            key=lambda item: (str(item["block_id"]), int(item["attempt"] or 0), str(item["arm"])),
        ),
    )
