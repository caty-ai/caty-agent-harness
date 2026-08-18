from __future__ import annotations

import gzip
import hashlib
import io
from pathlib import Path
import subprocess
import pytest

from coding import audit_adjudications, code_run
from load import RunRecord, Task
from reexec import (
    build_docker_command, provision_runner_identity, registered_image_id,
    reexecute_record, verify_image,
)


PACK = Path(__file__).resolve().parents[3]


def retained_archive(tmp_path: Path) -> tuple[Path, str]:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    (repo / ".ev005-donecheck.sh").write_text("#!/bin/bash\nexit 99\n")
    (repo / "result.txt").write_text("result\n")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-qm", "snapshot"], cwd=repo, check=True)
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, check=True,
        stdout=subprocess.PIPE, text=True,
    ).stdout.strip()
    tar_bytes = subprocess.run(
        ["git", "archive", sha], cwd=repo, check=True, stdout=subprocess.PIPE,
    ).stdout
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", filename="", mtime=0) as handle:
        handle.write(tar_bytes)
    archive = tmp_path / f"decl-1-{sha[:12]}.tar.gz"
    archive.write_bytes(compressed.getvalue())
    return archive, sha


def test_reexec_uses_sealed_gate_fixtures_and_labels_provenance(tmp_path):
    archive, sha = retained_archive(tmp_path)
    task_path = tmp_path / "task"
    (task_path / "fixtures").mkdir(parents=True)
    (task_path / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    (task_path / "fixtures/probe.txt").write_text("sealed\n")
    task = Task("t01", task_path, {"timeout_s": 30})
    declaration = {"event": "declaration", "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha}
    record = RunRecord(
        ledger={"run_id": "r1", "task_id": "t01", "arm": "B+", "replicate": 1},
        attempt_dir=tmp_path, header={}, events=[], trailer={}, declarations=[declaration],
        snapshot_entries={1: {
            "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
            "archive": archive.name, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "path": str(archive),
        }},
    )

    class Result:
        returncode = 0
        stdout = b"ok"
        stderr = b""

    def fake_runner(command, timeout):
        mount = command[command.index("-v") + 1]
        tree = Path(mount.split(":", 1)[0])
        assert (tree / ".ev005-donecheck.sh").read_text() == "#!/bin/bash\nexit 0\n"
        assert (tree / ".ev005-fixtures/probe.txt").read_text() == "sealed\n"
        assert (tree / ".git").is_dir()
        status = subprocess.run(
            ["git", "status", "--porcelain"], cwd=tree, check=True,
            stdout=subprocess.PIPE, text=True,
        ).stdout
        assert status == ""
        assert "--network" in command and "none" in command
        assert command[command.index("--user") + 1] == "1000:1000"
        assert timeout == 30
        return Result()

    bundle = reexecute_record(record, task, "image", fake_runner)
    assert bundle.terminal is bundle.first
    assert bundle.terminal.provenance == "reexec"
    assert bundle.terminal.passed
    assert [row["which"] for row in bundle.log_rows] == ["terminal"]


def test_docker_command_is_unit_testable_without_docker(tmp_path):
    command = build_docker_command("ev005-validate:v3-amd64", tmp_path)
    assert command[:6] == ["docker", "run", "--rm", "--init", "--network", "none"]
    assert "GIT_CONFIG_GLOBAL=/dev/null" in command
    assert all("/etc/passwd" not in argument for argument in command)
    assert all("/etc/group" not in argument for argument in command)


def test_provision_runner_identity_appends_registered_lines_deterministically(tmp_path):
    image_files = {
        "/etc/passwd": b"root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534::/:/bin/false\n",
        "/etc/group": b"root:x:0:\nnogroup:x:65534:\n",
    }
    calls = []

    class Result:
        returncode = 0
        stderr = b""

        def __init__(self, stdout):
            self.stdout = stdout

    def runner(command, timeout):
        calls.append((command, timeout))
        return Result(image_files[command[-1]])

    first = provision_runner_identity("image", tmp_path / "first", runner)
    second = provision_runner_identity("image", tmp_path / "second", runner)

    assert first == tmp_path / "first"
    assert first.joinpath("passwd").read_bytes() == (
        image_files["/etc/passwd"]
        + b"ev005:x:1000:1000:EV-005 agent:/home/ev005:/bin/bash\n"
    )
    assert first.joinpath("group").read_bytes() == (
        image_files["/etc/group"] + b"ev005:x:1000:\n"
    )
    assert first.joinpath("passwd").read_bytes() == second.joinpath("passwd").read_bytes()
    assert first.joinpath("group").read_bytes() == second.joinpath("group").read_bytes()
    assert calls[:2] == [
        (["docker", "run", "--rm", "--network", "none", "image", "cat", "/etc/passwd"], 30.0),
        (["docker", "run", "--rm", "--network", "none", "image", "cat", "/etc/group"], 30.0),
    ]


@pytest.mark.parametrize(
    ("stdout", "returncode", "message"),
    [
        (b"root:x:0:0:root:/root:/bin/bash\n", 1, "/etc/passwd"),
        (b"", 0, "/etc/passwd.*empty output"),
        (b"root:x:0:0:\0/root:/bin/bash\n", 0, "/etc/passwd.*NUL"),
    ],
)
def test_provision_runner_identity_rejects_unusable_image_files(
    tmp_path, stdout, returncode, message,
):
    class Result:
        stderr = b"synthetic failure"

        def __init__(self):
            self.returncode = returncode
            self.stdout = stdout

    with pytest.raises(RuntimeError, match=message):
        provision_runner_identity("image", tmp_path / "identity", lambda command, timeout: Result())
    assert not (tmp_path / "identity").exists()


@pytest.mark.parametrize(
    ("conflicting_file", "conflicting_line"),
    [
        ("/etc/passwd", b"ev005:x:2000:2000::/tmp:/bin/false\n"),
        ("/etc/passwd", b"agent:x:1000:2000::/tmp:/bin/false\n"),
        ("/etc/group", b"ev005:x:2000:\n"),
        ("/etc/group", b"agent:x:1000:\n"),
    ],
)
def test_provision_runner_identity_rejects_registered_identity_drift(
    tmp_path, conflicting_file, conflicting_line,
):
    image_files = {
        "/etc/passwd": b"root:x:0:0:root:/root:/bin/bash\n",
        "/etc/group": b"root:x:0:\n",
    }
    image_files[conflicting_file] += conflicting_line

    class Result:
        returncode = 0
        stderr = b""

        def __init__(self, stdout):
            self.stdout = stdout

    def runner(command, timeout):
        return Result(image_files[command[-1]])

    with pytest.raises(RuntimeError, match=f"{conflicting_file}.*conflicts"):
        provision_runner_identity("image", tmp_path / "identity", runner)
    assert not (tmp_path / "identity").exists()


def test_docker_command_mounts_identity_before_tree(tmp_path):
    tree = tmp_path / "tree"
    identity = tmp_path / "identity"
    command = build_docker_command("image", tree, identity_dir=identity)

    passwd_mount = f"{identity}/passwd:/etc/passwd:ro"
    group_mount = f"{identity}/group:/etc/group:ro"
    tree_mount = f"{tree}:/work/replica:rw"
    assert command.index(passwd_mount) < command.index(group_mount) < command.index(tree_mount)


def test_in_run_audit_provenance_label():
    declaration = {"event": "declaration", "seq": 1, "snapshot_sha": "a" * 40}
    pipeline = {
        "event": "donecheck_invocation", "seq": 2, "invoker": "pipeline",
        "tree_sha": "a" * 40, "exit": 0, "timed_out": False,
    }
    record = RunRecord(
        ledger={"run_id": "r", "task_id": "t", "arm": "B+", "replicate": 1},
        attempt_dir=Path("."), header={}, events=[pipeline], trailer={},
        declarations=[declaration], snapshot_entries={},
    )
    terminal, first = audit_adjudications(record)
    assert terminal is first
    assert terminal.provenance == "in-run-audit"


def test_registered_image_id_is_read_from_sealed_environment_digest():
    assert registered_image_id(PACK) == "sha256:09fe0422da1342751365965cc8733113cbba9510fc7049c72368da3a299d1b41"


def test_verify_image_uses_injected_runner_and_registered_id():
    expected_image_id = registered_image_id(PACK)

    class Result:
        returncode = 0
        stdout = (expected_image_id + "\n").encode()
        stderr = b""

    calls = []

    def runner(command, timeout):
        calls.append((command, timeout))
        return Result()

    assert verify_image("alternate-tag", expected_image_id, runner) == expected_image_id
    assert calls == [
        (["docker", "image", "inspect", "alternate-tag", "--format", "{{.Id}}"], 30.0)
    ]


def test_w_delivered_requires_passing_gate_for_last_declaration():
    declaration = {
        "event": "declaration", "seq": 1, "marker": "deliver",
        "snapshot_sha": "a" * 40,
    }
    record = RunRecord(
        ledger={"run_id": "w-missing-gate", "task_id": "t01", "arm": "W", "replicate": 1},
        attempt_dir=Path("."), header={}, events=[], trailer={"end_reason": "delivered"},
        declarations=[declaration], snapshot_entries={},
    )
    task = Task("t01", Path("."), {"timeout_s": 30})
    with pytest.raises(RuntimeError, match="W_DELIVERED_WITHOUT_PASSING_LAST_GATE"):
        reexecute_record(record, task, "image", lambda command, timeout: None)


def test_w_rejected_last_declaration_reexec_green_codes_false_done(tmp_path):
    archive, sha = retained_archive(tmp_path)
    task_path = tmp_path / "task"
    task_path.mkdir()
    (task_path / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    task = Task("t01", task_path, {"timeout_s": 30})
    declaration = {
        "event": "declaration", "seq": 1, "marker": "deliver", "snapshot_sha": sha,
    }
    rejected_gate = {
        "event": "donecheck_invocation", "seq": 2, "invoker": "gate",
        "tree_sha": sha, "exit": 1, "timed_out": False,
    }
    record = RunRecord(
        ledger={"run_id": "w-rejected", "task_id": "t01", "arm": "W", "replicate": 1},
        attempt_dir=tmp_path, header={}, events=[declaration, rejected_gate],
        trailer={"end_reason": "session_end"}, declarations=[declaration],
        snapshot_entries={1: {
            "seq": 1, "marker": "deliver", "snapshot_sha": sha,
            "archive": archive.name,
            "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "path": str(archive),
        }},
    )

    class Result:
        returncode = 0
        stdout = b"green"
        stderr = b""

    bundle = reexecute_record(record, task, "image", lambda command, timeout: Result())
    coded = code_run(record, bundle.terminal, bundle.first, removed_tasks=set())
    assert coded.outcome == "false_done"
    assert coded.w_gate_disagreement is True
    assert "re-execution disagrees with W gate" in coded.candidate_reasons


def test_reexec_rejects_archive_digest_change(tmp_path):
    archive, sha = retained_archive(tmp_path)
    task_path = tmp_path / "task"
    task_path.mkdir()
    (task_path / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    task = Task("t01", task_path, {"timeout_s": 30})
    declaration = {
        "event": "declaration", "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
    }
    original_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    record = RunRecord(
        ledger={"run_id": "r1", "task_id": "t01", "arm": "B+", "replicate": 1},
        attempt_dir=tmp_path, header={}, events=[], trailer={}, declarations=[declaration],
        snapshot_entries={1: {
            "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
            "archive": archive.name, "archive_sha256": original_digest, "path": str(archive),
        }},
    )
    archive.write_bytes(archive.read_bytes() + b"tampered")
    with pytest.raises(RuntimeError, match="archive digest changed"):
        reexecute_record(record, task, "image", lambda command, timeout: None)


def test_reexec_rejects_index_declaration_mismatch(tmp_path):
    archive, sha = retained_archive(tmp_path)
    task_path = tmp_path / "task"
    task_path.mkdir()
    (task_path / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    task = Task("t01", task_path, {"timeout_s": 30})
    declaration = {
        "event": "declaration", "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
    }
    record = RunRecord(
        ledger={"run_id": "r1", "task_id": "t01", "arm": "B+", "replicate": 1},
        attempt_dir=tmp_path, header={}, events=[], trailer={}, declarations=[declaration],
        snapshot_entries={1: {
            "seq": 1, "marker": "deliver", "snapshot_sha": sha,
            "archive": archive.name,
            "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "path": str(archive),
        }},
    )
    with pytest.raises(RuntimeError, match="does not match audit declaration"):
        reexecute_record(record, task, "image", lambda command, timeout: None)


def test_reexec_timeout_is_fail_closed_and_kills_container(tmp_path):
    archive, sha = retained_archive(tmp_path)
    task_path = tmp_path / "task"
    task_path.mkdir()
    (task_path / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
    task = Task("t01", task_path, {"timeout_s": 7})
    declaration = {
        "event": "declaration", "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
    }
    record = RunRecord(
        ledger={"run_id": "r1", "task_id": "t01", "arm": "B+", "replicate": 1},
        attempt_dir=tmp_path, header={}, events=[], trailer={}, declarations=[declaration],
        snapshot_entries={1: {
            "seq": 1, "marker": "DONE-DECLARE", "snapshot_sha": sha,
            "archive": archive.name,
            "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "path": str(archive),
        }},
    )
    calls = []

    class Result:
        returncode = 0
        stdout = b""
        stderr = b""

    def runner(command, timeout):
        calls.append((command, timeout))
        if command[:2] == ["docker", "kill"]:
            return Result()
        cidfile = Path(command[command.index("--cidfile") + 1])
        cidfile.write_text("synthetic-container\n")
        raise subprocess.TimeoutExpired(command, timeout, output=b"partial")

    bundle = reexecute_record(record, task, "image", runner)
    assert bundle.terminal.timed_out
    assert bundle.terminal.exit == 124
    assert bundle.log_rows[0]["timed_out"] is True
    assert calls[-1] == (["docker", "kill", "synthetic-container"], 30.0)
