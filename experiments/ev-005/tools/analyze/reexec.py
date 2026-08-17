"""Isolated re-execution of retained EV-005 declaration snapshots."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from typing import Callable, Any

from coding import Adjudication
from load import RunRecord, Task


CommandRunner = Callable[[list[str], float], Any]
GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
    "GIT_AUTHOR_NAME": "ev005",
    "GIT_AUTHOR_EMAIL": "ev005@local",
    "GIT_COMMITTER_NAME": "ev005",
    "GIT_COMMITTER_EMAIL": "ev005@local",
}


def subprocess_runner(command: list[str], timeout_s: float) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout_s, check=False,
    )


def build_docker_command(image: str, tree: Path, cidfile: Path | None = None) -> list[str]:
    """Construct the registered networkless, unprivileged adjudication command."""
    command = [
        "docker", "run", "--rm", "--init", "--network", "none",
        "--user", "1000:1000", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--tmpfs", "/home/ev005:rw,nosuid,nodev,size=128m,uid=1000,gid=1000,mode=0700",
        "--tmpfs", "/tmp/ev005:rw,exec,nosuid,nodev,size=1g,uid=1000,gid=1000,mode=0700",
        "-e", "HOME=/home/ev005", "-e", "TMPDIR=/tmp/ev005",
        "-e", "GIT_CONFIG_GLOBAL=/dev/null", "-e", "GIT_CONFIG_SYSTEM=/dev/null",
        "-v", f"{tree}:/work/replica:rw", "-w", "/work/replica",
    ]
    if cidfile is not None:
        command += ["--cidfile", str(cidfile)]
    return command + [image, "/usr/bin/bash", "./.ev005-donecheck.sh"]


def registered_image_id(pack: Path) -> str:
    """Read the registered amd64 image ID from the sealed environment digest."""
    digest_path = pack / "environment-digest.md"
    try:
        lines = digest_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise RuntimeError(f"cannot read registered image ID from {digest_path}: {exc}") from exc
    value = None
    for line in lines:
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) == 2 and columns[0] == "image ID (sha256)":
            value = columns[1].strip("`")
            break
    if (
        not isinstance(value, str) or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise RuntimeError(f"registered image ID is missing or malformed in {digest_path}")
    return f"sha256:{value}"


def verify_image(
    image: str,
    expected_image_id: str,
    runner: CommandRunner = subprocess_runner,
) -> str:
    result = runner(
        ["docker", "image", "inspect", image, "--format", "{{.Id}}"], 30.0
    )
    if result.returncode != 0:
        raise RuntimeError(f"container image unavailable: {result.stderr.decode(errors='replace').strip()}")
    actual = result.stdout.decode(errors="replace").strip()
    if actual != expected_image_id:
        raise RuntimeError(f"image ID mismatch: expected {expected_image_id}, got {actual}")
    return actual


def _safe_extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as handle:
        for member in handle.getmembers():
            target = (destination / member.name).resolve()
            try:
                target.relative_to(destination.resolve())
            except ValueError as exc:
                raise RuntimeError(f"unsafe archive member: {member.name}") from exc
        handle.extractall(destination, filter="data")


def _make_writable(tree: Path) -> None:
    for root, directories, files in os.walk(tree):
        os.chmod(root, 0o777)
        for name in directories:
            path = Path(root) / name
            if not path.is_symlink():
                os.chmod(path, 0o777)
        for name in files:
            path = Path(root) / name
            if not path.is_symlink():
                mode = path.stat().st_mode
                os.chmod(path, 0o777 if mode & 0o111 else 0o666)


def materialize_tree(archive: Path, task: Task, destination: Path) -> None:
    _safe_extract(archive, destination)
    gate = destination / ".ev005-donecheck.sh"
    if gate.is_dir() and not gate.is_symlink():
        shutil.rmtree(gate)
    else:
        gate.unlink(missing_ok=True)
    gate.write_bytes((task.path / "donecheck.sh").read_bytes())
    gate.chmod(0o755)
    fixtures = destination / ".ev005-fixtures"
    if fixtures.is_dir() and not fixtures.is_symlink():
        shutil.rmtree(fixtures)
    else:
        fixtures.unlink(missing_ok=True)
    sealed_fixtures = task.path / "fixtures"
    if sealed_fixtures.is_dir():
        shutil.copytree(sealed_fixtures, fixtures)
    git_env = {**os.environ, **GIT_ENV}
    for arguments in (("init", "-q"), ("add", "-A"), ("commit", "-qm", "adjudication snapshot")):
        completed = subprocess.run(
            ["git", *arguments], cwd=destination, env=git_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if completed.returncode != 0:
            error = completed.stderr.decode(errors="replace").strip()
            raise RuntimeError(f"cannot materialize adjudication Git tree ({' '.join(arguments)}): {error}")
    _make_writable(destination)


@dataclasses.dataclass
class ReexecutionBundle:
    terminal: Adjudication | None
    first: Adjudication | None
    log_rows: list[dict[str, Any]]


def _execute_entry(
    record: RunRecord,
    task: Task,
    entry: dict[str, Any],
    which: str,
    image: str,
    runner: CommandRunner,
) -> tuple[Adjudication, dict[str, Any]]:
    archive = Path(entry["path"])
    if archive.is_symlink() or not archive.is_file():
        raise RuntimeError(f"snapshot archive is missing or unsafe: {archive}")
    expected_digest = entry["archive_sha256"]
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_digest:
        raise RuntimeError(f"archive digest changed after load: {archive}")
    with tempfile.TemporaryDirectory(prefix="ev005-analysis-") as temp:
        tree = Path(temp) / "tree"
        tree.mkdir()
        materialize_tree(archive, task, tree)
        cidfile = Path(temp) / "container.cid"
        command = build_docker_command(image, tree, cidfile)
        try:
            result = runner(command, float(task.meta["timeout_s"]))
            exit_code = int(result.returncode)
            stdout = bytes(result.stdout or b"")
            timed_out = False
        except subprocess.TimeoutExpired as exc:
            exit_code = 124
            stdout = bytes(exc.stdout or b"")
            timed_out = True
            if cidfile.is_file():
                container_id = cidfile.read_text(encoding="utf-8").strip()
                if container_id:
                    try:
                        runner(["docker", "kill", container_id], 30.0)
                    except (OSError, subprocess.TimeoutExpired):
                        pass
    row = {
        "event": "donecheck_invocation",
        "invoker": "pipeline",
        "tree_sha": entry["snapshot_sha"],
        "exit": exit_code,
        "stdout_digest": hashlib.sha256(stdout).hexdigest(),
        # Wall-clock duration is intentionally not sampled here: it is not an
        # analysis input and would make otherwise identical pipeline artifacts
        # vary across reruns.  The field remains present to match the audit row
        # shape, with the reason made explicit rather than fabricating zero.
        "duration_ms": None,
        "timed_out": timed_out,
        "observation_error": "duration not recorded in deterministic analysis artifact",
        "run_id": record.run_id,
        "which": which,
        "snapshot_sha": entry["snapshot_sha"],
    }
    return Adjudication(exit_code, timed_out, "reexec", row), row


def reexecute_record(
    record: RunRecord,
    task: Task,
    image: str,
    runner: CommandRunner = subprocess_runner,
) -> ReexecutionBundle:
    if not record.declarations:
        return ReexecutionBundle(None, None, [])
    first_decl, terminal_decl = record.declarations[0], record.declarations[-1]
    if record.arm == "W" and record.trailer.get("end_reason") == "delivered":
        terminal_sha = terminal_decl.get("snapshot_sha")
        passing_gate = any(
            event.get("event") == "donecheck_invocation"
            and event.get("invoker") == "gate"
            and event.get("tree_sha") == terminal_sha
            and event.get("exit") == 0
            and event.get("timed_out") is False
            for event in record.events
        )
        if not passing_gate:
            raise RuntimeError(
                "W_DELIVERED_WITHOUT_PASSING_LAST_GATE: "
                f"run {record.run_id} has no passing gate invocation for its last declaration"
            )
    terminal_entry = record.snapshot_entries.get(terminal_decl.get("seq"))
    first_entry = record.snapshot_entries.get(first_decl.get("seq"))
    for declaration, entry in ((terminal_decl, terminal_entry), (first_decl, first_entry)):
        if entry is not None and (
            entry.get("seq") != declaration.get("seq")
            or entry.get("marker") != declaration.get("marker")
            or entry.get("snapshot_sha") != declaration.get("snapshot_sha")
        ):
            raise RuntimeError(
                f"snapshot entry does not match audit declaration for run {record.run_id} "
                f"seq {declaration.get('seq')}"
            )
    rows: list[dict[str, Any]] = []
    terminal: Adjudication | None = None
    first: Adjudication | None = None
    if terminal_entry:
        terminal, row = _execute_entry(record, task, terminal_entry, "terminal", image, runner)
        rows.append(row)
    if first_decl is terminal_decl:
        first = terminal
    elif first_entry:
        first, row = _execute_entry(record, task, first_entry, "first", image, runner)
        rows.append(row)
    return ReexecutionBundle(terminal, first, rows)


def write_reexecution_log(path: Path, rows: list[dict[str, Any]]) -> None:
    payload = "".join(
        json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
        for row in sorted(rows, key=lambda r: (r["run_id"], r["which"]))
    )
    path.write_text(payload, encoding="utf-8")
