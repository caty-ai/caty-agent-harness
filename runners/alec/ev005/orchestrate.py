#!/usr/bin/env python3
"""Deterministic block orchestrator for the sealed EV-005 series."""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import fcntl
import json
import os
import random
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Iterable


HERE = Path(__file__).resolve().parent
RUNNER = HERE / "runner.py"
STUB_AGENT = HERE / "stub_agent.py"
SCHEDULE_SEED = 20260816
ARMS = ["B", "B+", "W"]          # canonical order, fixed by the seal
SEAT_POOL = ["seat-01", "seat-02", "seat-04", "seat-05", "seat-06"]
SERIES_TASK_COUNTS = {"main": 30, "crossover": 10, "pilot": 5}
REGISTERED_MEMORY_BYTES = 8 * 1024**3
CORES_PER_WORKER = 2
MAX_PHYSICAL_CORES = 48
VOID_EXIT_STATUS = 3


def blocks_of(task_ids: Iterable[str], k_max: int = 3) -> list[tuple[str, int]]:
    """Canonical enumeration: task id ascending lexicographically, then k ascending."""
    return [(t, k) for t in sorted(task_ids) for k in range(1, k_max + 1)]


def schedule(
    series: str, task_ids: Iterable[str], seat_pool: list[str], k_max: int = 3,
) -> list[dict[str, Any]]:
    """series is one of "main", "crossover", "pilot" — each is scheduled independently."""
    order = blocks_of(task_ids, k_max)
    random.Random(f"{SCHEDULE_SEED}:order:{series}").shuffle(order)
    rows = []
    for rank, block in enumerate(order):            # rank is the 0-based execution position
        seat = seat_pool[rank % len(seat_pool)]
        for arm in ARMS:
            slot = (ARMS.index(arm) + rank) % 3     # cyclic rotation by the block's rank
            rows.append({"block": block, "rank": rank, "arm": arm,
                         "slot": slot, "seat": seat})
    return rows


def parse_cpu_list(raw: str) -> set[int]:
    cpus: set[int] = set()
    for component in raw.strip().split(","):
        if not component:
            continue
        if "-" in component:
            left, right = component.split("-", 1)
            start, end = int(left), int(right)
            if start < 0 or end < start:
                raise ValueError(f"invalid CPU range: {component}")
            cpus.update(range(start, end + 1))
        else:
            cpu = int(component)
            if cpu < 0:
                raise ValueError(f"invalid CPU: {component}")
            cpus.add(cpu)
    return cpus


def read_physical_cores(sysfs_cpu_root: Path) -> list[tuple[int, ...]]:
    """Return online logical siblings grouped by physical core."""
    sibling_files: dict[int, Path] = {}
    for path in sysfs_cpu_root.glob("cpu[0-9]*/topology/thread_siblings_list"):
        name = path.parent.parent.name
        suffix = name.removeprefix("cpu")
        if suffix.isdigit():
            sibling_files[int(suffix)] = path
    if not sibling_files:
        raise RuntimeError(f"no CPU topology found under {sysfs_cpu_root}")
    discovered = set(sibling_files)
    online_path = sysfs_cpu_root / "online"
    online = parse_cpu_list(online_path.read_text()) if online_path.is_file() else discovered
    available = discovered & online
    if not available:
        raise RuntimeError("CPU topology contains no online CPUs")

    parent = {cpu: cpu for cpu in discovered}

    def find(cpu: int) -> int:
        parent.setdefault(cpu, cpu)
        while parent[cpu] != cpu:
            parent[cpu] = parent[parent[cpu]]
            cpu = parent[cpu]
        return cpu

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[max(left_root, right_root)] = min(left_root, right_root)

    for cpu, path in sorted(sibling_files.items()):
        siblings = parse_cpu_list(path.read_text())
        if cpu not in siblings:
            raise RuntimeError(f"{path} does not contain its own CPU {cpu}")
        for sibling in siblings:
            union(cpu, sibling)

    groups: dict[int, list[int]] = {}
    for cpu in sorted(available):
        groups.setdefault(find(cpu), []).append(cpu)
    cores = [tuple(cpus) for cpus in groups.values() if cpus]
    cores.sort(key=lambda cpus: (cpus[0], cpus))
    return cores


@dataclasses.dataclass(frozen=True)
class WorkerAllocation:
    worker_id: str
    physical_cores: tuple[tuple[int, ...], ...]
    logical_cpus: tuple[int, ...]

    @property
    def cpuset(self) -> str:
        return ",".join(str(cpu) for cpu in self.logical_cpus)


def allocate_workers(
    physical_cores: list[tuple[int, ...]], worker_count: int,
) -> list[WorkerAllocation]:
    required = worker_count * CORES_PER_WORKER
    if required > MAX_PHYSICAL_CORES:
        raise RuntimeError(
            f"worker allocation requires {required} physical cores; sealed maximum is 48"
        )
    if required > len(physical_cores):
        raise RuntimeError(
            f"worker allocation requires {required} physical cores; only {len(physical_cores)} available"
        )
    selected = physical_cores[:required]
    assert len(selected) <= MAX_PHYSICAL_CORES
    allocations: list[WorkerAllocation] = []
    seen_logical: set[int] = set()
    for index in range(worker_count):
        worker_cores = tuple(selected[index * 2:index * 2 + 2])
        logical = tuple(sorted(cpu for core in worker_cores for cpu in core))
        if seen_logical.intersection(logical):
            raise AssertionError("logical CPU assigned to multiple workers")
        seen_logical.update(logical)
        allocations.append(WorkerAllocation(f"worker-{index:02d}", worker_cores, logical))
    assigned_cores = [core for worker in allocations for core in worker.physical_cores]
    assert len(assigned_cores) == len(set(assigned_cores))
    assert len(assigned_cores) <= MAX_PHYSICAL_CORES
    return allocations


@dataclasses.dataclass(frozen=True)
class BlockAssignment:
    series: str
    task_id: str
    replicate: int
    rank: int
    seat: str
    arms: tuple[tuple[str, int], ...]

    @property
    def block_id(self) -> str:
        return f"{self.task_id}-k{self.replicate}"


def block_assignments(rows: list[dict[str, Any]], series: str) -> list[BlockAssignment]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(int(row["rank"]), []).append(row)
    assignments: list[BlockAssignment] = []
    for rank in sorted(grouped):
        group = grouped[rank]
        block = tuple(group[0]["block"])
        if len(group) != 3 or {row["arm"] for row in group} != set(ARMS):
            raise RuntimeError(f"invalid schedule group at rank {rank}")
        if len({row["seat"] for row in group}) != 1:
            raise RuntimeError(f"block at rank {rank} spans seats")
        assignments.append(BlockAssignment(
            series=series, task_id=str(block[0]), replicate=int(block[1]), rank=rank,
            seat=str(group[0]["seat"]),
            arms=tuple((str(row["arm"]), int(row["slot"])) for row in group),
        ))
    return assignments


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def append_ledger(path: Path, row: dict[str, Any], lock: threading.Lock) -> None:
    payload = json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock:
        fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            data = payload.encode()
            written = os.write(fd, data)
            if written != len(data):
                raise OSError(f"short ledger append: {written}/{len(data)}")
            os.fsync(fd)
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)


def write_atomic_json(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    data = json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
    with temporary.open("w") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def read_ledger(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    lines = path.read_text().splitlines()
    rows: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            if index == len(lines) - 1:
                break
            raise RuntimeError(f"malformed ledger line {index + 1}")
        if not isinstance(row, dict):
            raise RuntimeError(f"non-object ledger line {index + 1}")
        rows.append(row)
    return rows


def audit_trailer(path: Path) -> dict[str, Any] | None:
    try:
        rows = [json.loads(line) for line in path.read_text().splitlines()]
    except (OSError, json.JSONDecodeError):
        return None
    if not rows:
        return None
    trailer = rows[-1]
    return trailer if isinstance(trailer, dict) and "end_ts" in trailer else None


def successful(row: dict[str, Any]) -> bool:
    return bool(
        row.get("completed") is True
        and row.get("exit_status") == 0
        and row.get("void") is False
    )


def logical_history(
    rows: list[dict[str, Any]], block_id: str, arm: str,
) -> list[dict[str, Any]]:
    return [row for row in rows if row.get("block_id") == block_id and row.get("arm") == arm]


def arm_slug(arm: str) -> str:
    return {"B": "b", "B+": "bplus", "W": "w"}[arm]


def next_attempt_directory(root: Path, initial_attempt: int) -> tuple[int, Path]:
    attempt = initial_attempt
    while True:
        path = root / f"attempt-{attempt:03d}"
        if not path.exists():
            return attempt, path
        attempt += 1


def build_runner_command(
    *, assignment: BlockAssignment, arm: str, slot: int,
    task_dir: Path, source_repo: Path, output: Path, cell: str,
    worker: WorkerAllocation, run_id: str,
) -> list[str]:
    return [
        sys.executable, str(RUNNER), "run",
        "--run-id", run_id,
        "--arm", arm,
        "--task-dir", str(task_dir),
        "--source-repo", str(source_repo),
        "--output", str(output),
        "--cell", cell,
        "--worker-id", worker.worker_id,
        "--account-id", assignment.seat,
        "--block-id", assignment.block_id,
        "--slot-index", str(slot),
        "--cpuset-cpus", worker.cpuset,
        "--memory-bytes", str(REGISTERED_MEMORY_BYTES),
    ]


def run_process(
    command: list[str], env: dict[str, str], output: Path, *, dry_run: bool,
    dry_run_delay_s: float, run_id: str, started_ts: str,
    attempt_identity: dict[str, Any],
) -> int:
    if dry_run:
        output.mkdir(parents=True)
        stub_env = dict(env)
        stub_env.update({
            "EV005_STUB_SCENARIO": "orchestrator-smoke",
            "EV005_STUB_AUDIT": str(output / "audit.jsonl"),
            "EV005_STUB_DELAY_S": str(dry_run_delay_s),
        })
        command = [sys.executable, str(STUB_AGENT)]
        cp = subprocess.run(command, env=stub_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    else:
        cp = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output.mkdir(parents=True, exist_ok=True)
    (output / "orchestrator-runner.log").write_bytes(cp.stdout)
    write_atomic_json(output / "orchestrator-exit-status.json", {
        "run_id": run_id,
        "start_ts": started_ts,
        "end_ts": utc_now(),
        "exit_status": cp.returncode,
        "dry_run": dry_run,
        "attempt_identity": attempt_identity,
    })
    return cp.returncode


def make_ledger_row(
    *, assignment: BlockAssignment, arm: str, slot: int, cell: str,
    blocks_concurrent: int, worker: WorkerAllocation, run_id: str,
    attempt: int, started: str, ended: str, exit_status: int | None,
    trailer: dict[str, Any] | None, output: Path, dry_run: bool,
    is_void_retry: bool, recovered_after_restart: bool,
) -> dict[str, Any]:
    void = bool(
        (trailer or {}).get("infrastructure_void") is True
        or exit_status == VOID_EXIT_STATUS
    )
    void_reason = (trailer or {}).get("infrastructure_void_reason")
    if void and not void_reason:
        void_reason = "INFRASTRUCTURE: runner returned the registered void exit status"
    completed = trailer is not None and exit_status in {0, VOID_EXIT_STATUS}
    status_reason = None
    if not completed:
        status_reason = "incomplete run: missing audit trailer or terminal exit marker"
    return {
        "series": assignment.series,
        "cell": cell,
        "blocks_concurrent": blocks_concurrent,
        "block_id": assignment.block_id,
        "rank": assignment.rank,
        "task_id": assignment.task_id,
        "replicate": assignment.replicate,
        "arm": arm,
        "slot_index": slot,
        "seat": assignment.seat,
        "worker_id": worker.worker_id,
        "worker_cores": {
            "physical": [list(core) for core in worker.physical_cores],
            "logical": list(worker.logical_cpus),
            "cpuset": worker.cpuset,
        },
        "memory_bytes": REGISTERED_MEMORY_BYTES,
        "run_id": run_id,
        "attempt": attempt,
        "start_ts": started,
        "end_ts": ended,
        "exit_status": exit_status,
        "completed": completed,
        "void": void,
        "void_reason": void_reason if void else None,
        "status_reason": status_reason,
        "scoring_attempt": is_void_retry or not void,
        "output": str(output),
        "dry_run": dry_run,
        "recovered_after_restart": recovered_after_restart,
    }


def recover_unledgered_outputs(
    *, assignment: BlockAssignment, arm: str, slot: int, cell: str,
    blocks_concurrent: int, worker: WorkerAllocation, out_root: Path,
    ledger_path: Path, ledger_lock: threading.Lock, history: list[dict[str, Any]],
) -> None:
    attempts_root = out_root / "runs" / assignment.block_id / arm_slug(arm)
    if not attempts_root.is_dir():
        return
    known_run_ids = {str(row.get("run_id")) for row in history}
    for output in sorted(attempts_root.glob("attempt-[0-9][0-9][0-9]")):
        try:
            attempt = int(output.name.removeprefix("attempt-"))
        except ValueError:
            continue
        run_id = (
            f"ev005-{assignment.rank:03d}-{assignment.task_id}-k{assignment.replicate}-"
            f"{arm_slug(arm)}-a{attempt}"
        )
        if run_id in known_run_ids:
            continue
        status_path = output / "orchestrator-exit-status.json"
        if status_path.is_file():
            try:
                status = json.loads(status_path.read_text())
                if status.get("run_id") != run_id:
                    raise ValueError("exit marker run id mismatch")
                identity = status["attempt_identity"]
                expected_identity = {
                    "series": assignment.series,
                    "cell": cell,
                    "blocks_concurrent": blocks_concurrent,
                    "block_id": assignment.block_id,
                    "arm": arm,
                    "slot_index": slot,
                    "seat": assignment.seat,
                }
                if not isinstance(identity, dict) or any(
                    identity.get(key) != value for key, value in expected_identity.items()
                ):
                    raise ValueError("attempt identity mismatch")
                actual_worker = WorkerAllocation(
                    str(identity["worker_id"]),
                    tuple(tuple(int(cpu) for cpu in core) for core in identity["physical_cores"]),
                    tuple(int(cpu) for cpu in identity["logical_cpus"]),
                )
                if actual_worker.cpuset != identity["cpuset"]:
                    raise ValueError("attempt cpuset mismatch")
                exit_status = int(status["exit_status"])
                started = str(status["start_ts"])
                ended = str(status["end_ts"])
                dry_run = bool(status.get("dry_run"))
            except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
                raise RuntimeError(f"invalid orphan exit marker {status_path}: {exc}") from exc
        else:
            actual_worker = worker
            exit_status = None
            started = utc_now()
            ended = utc_now()
            dry_run = False
        trailer = audit_trailer(output / "audit.jsonl")
        is_void_retry = any(bool(row.get("void")) for row in history)
        row = make_ledger_row(
            assignment=assignment, arm=arm, slot=slot, cell=cell,
            blocks_concurrent=blocks_concurrent, worker=actual_worker,
            run_id=run_id, attempt=attempt, started=started, ended=ended,
            exit_status=exit_status, trailer=trailer, output=output,
            dry_run=dry_run, is_void_retry=is_void_retry,
            recovered_after_restart=True,
        )
        append_ledger(ledger_path, row, ledger_lock)
        history.append(row)
        known_run_ids.add(run_id)


def run_arm(
    *, assignment: BlockAssignment, arm: str, slot: int,
    task_dir: Path, source_repo: Path, seat_dir: Path, cell: str,
    worker: WorkerAllocation, out_root: Path, ledger_path: Path,
    ledger_lock: threading.Lock, history: list[dict[str, Any]],
    blocks_concurrent: int, dry_run: bool, dry_run_delay_s: float,
) -> bool:
    recover_unledgered_outputs(
        assignment=assignment, arm=arm, slot=slot, cell=cell,
        blocks_concurrent=blocks_concurrent, worker=worker, out_root=out_root,
        ledger_path=ledger_path, ledger_lock=ledger_lock, history=history,
    )
    if any(successful(row) for row in history):
        return True
    void_attempts = sum(bool(row.get("void")) for row in history)
    if void_attempts >= 2:
        return False
    attempts_to_run = 2 if void_attempts == 0 else 1
    for _ in range(attempts_to_run):
        attempt, output = next_attempt_directory(
            out_root / "runs" / assignment.block_id / arm_slug(arm),
            len(history) + 1,
        )
        is_void_retry = void_attempts > 0
        run_id = (
            f"ev005-{assignment.rank:03d}-{assignment.task_id}-k{assignment.replicate}-"
            f"{arm_slug(arm)}-a{attempt}"
        )
        command = build_runner_command(
            assignment=assignment, arm=arm, slot=slot,
            task_dir=task_dir, source_repo=source_repo, output=output,
            cell=cell, worker=worker, run_id=run_id,
        )
        env = os.environ.copy()
        env["CLAUDE_CONFIG_DIR"] = str(seat_dir)
        started = utc_now()
        exit_status = run_process(
            command, env, output, dry_run=dry_run,
            dry_run_delay_s=dry_run_delay_s, run_id=run_id,
            started_ts=started,
            attempt_identity={
                "series": assignment.series,
                "cell": cell,
                "blocks_concurrent": blocks_concurrent,
                "block_id": assignment.block_id,
                "arm": arm,
                "slot_index": slot,
                "seat": assignment.seat,
                "worker_id": worker.worker_id,
                "physical_cores": [list(core) for core in worker.physical_cores],
                "logical_cpus": list(worker.logical_cpus),
                "cpuset": worker.cpuset,
            },
        )
        ended = utc_now()
        trailer = audit_trailer(output / "audit.jsonl")
        row = make_ledger_row(
            assignment=assignment, arm=arm, slot=slot, cell=cell,
            blocks_concurrent=blocks_concurrent, worker=worker,
            run_id=run_id, attempt=attempt, started=started, ended=ended,
            exit_status=exit_status, trailer=trailer, output=output,
            dry_run=dry_run, is_void_retry=is_void_retry,
            recovered_after_restart=False,
        )
        append_ledger(ledger_path, row, ledger_lock)
        history.append(row)
        if row["completed"] and not row["void"] and exit_status == 0:
            return True
        if not row["void"]:
            return False
        void_attempts += 1
        if void_attempts >= 2:
            return False
    return False


def run_block(
    *, assignment: BlockAssignment, workers: tuple[WorkerAllocation, ...],
    task_dirs: dict[str, Path], source_repos: dict[str, Path], seats: dict[str, Path],
    cell: str, out_root: Path, ledger_path: Path, ledger_lock: threading.Lock,
    ledger_rows: list[dict[str, Any]], dry_run: bool, dry_run_delay_s: float,
    blocks_concurrent: int,
) -> bool:
    futures: list[concurrent.futures.Future[bool]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for arm, slot in assignment.arms:
            worker = workers[slot]
            history = logical_history(ledger_rows, assignment.block_id, arm)
            futures.append(pool.submit(
                run_arm,
                assignment=assignment, arm=arm, slot=slot,
                task_dir=task_dirs[assignment.task_id],
                source_repo=source_repos[assignment.task_id],
                seat_dir=seats[assignment.seat], cell=cell,
                worker=worker, out_root=out_root, ledger_path=ledger_path,
                ledger_lock=ledger_lock, history=history,
                blocks_concurrent=blocks_concurrent,
                dry_run=dry_run, dry_run_delay_s=dry_run_delay_s,
            ))
    return all(future.result() for future in futures)


def load_json_map(path: Path, description: str) -> dict[str, Path]:
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot load {description}: {exc}") from exc
    if not isinstance(raw, dict) or any(
        not isinstance(key, str) or not isinstance(value, str) for key, value in raw.items()
    ):
        raise RuntimeError(f"{description} must be a JSON object mapping strings to paths")
    return {key: Path(value).expanduser().resolve() for key, value in raw.items()}


def load_tasks(tasks_dir: Path, series: str, repos: dict[str, Path]) -> tuple[dict[str, Path], dict[str, Path]]:
    task_dirs: dict[str, Path] = {}
    source_repos: dict[str, Path] = {}
    for task_dir in sorted(path for path in tasks_dir.iterdir() if path.is_dir()):
        meta_path = task_dir / "meta.json"
        if not meta_path.is_file():
            continue
        meta = json.loads(meta_path.read_text())
        task_id = str(meta["id"])
        source_name = str(meta["source_repo"])
        if task_dir.name != task_id:
            raise RuntimeError(f"task directory {task_dir.name} disagrees with meta id {task_id}")
        if source_name not in repos:
            raise RuntimeError(f"no local repository mapping for {source_name}")
        if not (repos[source_name] / ".git").exists():
            raise RuntimeError(f"mapped source repository is not a local clone: {repos[source_name]}")
        task_dirs[task_id] = task_dir.resolve()
        source_repos[task_id] = repos[source_name]
    expected = SERIES_TASK_COUNTS[series]
    if len(task_dirs) != expected:
        raise RuntimeError(f"{series} requires exactly {expected} tasks; found {len(task_dirs)}")
    return task_dirs, source_repos


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--series", choices=("pilot", "main", "crossover"), required=True)
    parser.add_argument("--tasks-dir", type=Path, required=True)
    parser.add_argument("--cell", required=True)
    parser.add_argument("--repos-json", type=Path, required=True)
    parser.add_argument("--seats-json", type=Path, required=True)
    parser.add_argument("--out-root", type=Path, required=True)
    parser.add_argument("--blocks-concurrent", type=int, required=True)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="exercise scheduling with stub_agent.py; never scores")
    parser.add_argument("--dry-run-delay-s", type=float, default=0.05, help=argparse.SUPPRESS)
    parser.add_argument(
        "--sysfs-cpu-root", type=Path,
        default=Path("/sys/devices/system/cpu"), help=argparse.SUPPRESS,
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    ns = parse_args(argv)
    if not 1 <= ns.blocks_concurrent <= 5:
        raise RuntimeError("--blocks-concurrent must be in the registered range 1..5")
    out_root = ns.out_root.resolve()
    ledger_path = out_root / "ledger.jsonl"
    if ledger_path.exists() and not ns.resume:
        raise RuntimeError(f"ledger already exists; use --resume: {ledger_path}")
    out_root.mkdir(parents=True, exist_ok=True)
    ledger_rows = read_ledger(ledger_path)
    if ledger_rows and any(
        row.get("series") != ns.series
        or row.get("cell") != ns.cell
        or row.get("blocks_concurrent") != ns.blocks_concurrent
        for row in ledger_rows
    ):
        raise RuntimeError(
            "resume ledger series, cell, or blocks-concurrent differs from this invocation"
        )
    repos = load_json_map(ns.repos_json, "repository map")
    seats = load_json_map(ns.seats_json, "seat map")
    if list(sorted(seats)) != list(sorted(SEAT_POOL)):
        raise RuntimeError(f"seat map must contain exactly the sealed pool: {SEAT_POOL}")
    for label, path in seats.items():
        if not path.is_dir():
            raise RuntimeError(f"seat configuration directory is missing for {label}: {path}")
    task_dirs, source_repos = load_tasks(ns.tasks_dir.resolve(), ns.series, repos)
    rows = schedule(ns.series, task_dirs, SEAT_POOL)
    assignments = block_assignments(rows, ns.series)
    physical_cores = read_physical_cores(ns.sysfs_cpu_root)
    allocations = allocate_workers(physical_cores, ns.blocks_concurrent * 3)
    bundles = [tuple(allocations[index * 3:index * 3 + 3]) for index in range(ns.blocks_concurrent)]
    ledger_lock = threading.Lock()
    pending = iter(assignments)
    next_assignment = next(pending, None)
    free_bundle_indexes = list(range(ns.blocks_concurrent))
    active: dict[concurrent.futures.Future[bool], tuple[int, str]] = {}
    results: list[bool] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=ns.blocks_concurrent) as pool:
        while next_assignment is not None or active:
            active_seats = {seat for _, seat in active.values()}
            while (
                next_assignment is not None
                and free_bundle_indexes
                and next_assignment.seat not in active_seats
            ):
                bundle_index = free_bundle_indexes.pop(0)
                assignment = next_assignment
                future = pool.submit(
                    run_block,
                    assignment=assignment, workers=bundles[bundle_index],
                    task_dirs=task_dirs, source_repos=source_repos, seats=seats,
                    cell=ns.cell, out_root=out_root, ledger_path=ledger_path,
                    ledger_lock=ledger_lock, ledger_rows=ledger_rows,
                    blocks_concurrent=ns.blocks_concurrent,
                    dry_run=ns.dry_run, dry_run_delay_s=ns.dry_run_delay_s,
                )
                active[future] = (bundle_index, assignment.seat)
                active_seats.add(assignment.seat)
                next_assignment = next(pending, None)
            if not active:
                raise RuntimeError("scheduler deadlock with no active block")
            done, _ = concurrent.futures.wait(
                active, return_when=concurrent.futures.FIRST_COMPLETED,
            )
            for future in done:
                bundle_index, _ = active.pop(future)
                free_bundle_indexes.append(bundle_index)
                free_bundle_indexes.sort()
                results.append(future.result())
    return 0 if all(results) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"EV005 orchestrator failure: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(2)
