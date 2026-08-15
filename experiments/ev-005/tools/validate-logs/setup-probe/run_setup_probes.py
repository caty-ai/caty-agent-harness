#!/usr/bin/env python3
"""Verify full CHECK accounting when EV-005 bundled probes are absent."""

import collections
import importlib.util
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time


EV005_ROOT = pathlib.Path(__file__).resolve().parents[3]
TASKS_ROOT = EV005_ROOT / "tasks"
LOG_DIR = pathlib.Path(__file__).resolve().parent
NEGPROBE_RUNNER = EV005_ROOT / "tools/validate-logs/negprobe/run_negprobes.py"

EXPECTED_IDS = {
    "t11": tuple(f"a{index:02d}" for index in range(1, 12)),
    "t29": tuple(f"a{index:02d}" for index in range(1, 14)),
    "t30": tuple(f"a{index:02d}" for index in range(1, 9)),
}
DEPENDENT_IDS = {
    "t11": ("a03", "a04", "a05", "a07"),
    "t29": (*tuple(f"a{index:02d}" for index in range(1, 11)), "a13"),
    "t30": tuple(f"a{index:02d}" for index in range(3, 9)),
}


def load_replica_helpers():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("ev005_negprobe_runner", NEGPROBE_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load replica helpers from {NEGPROBE_RUNNER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def format_ids(ids):
    return ",".join(ids) if ids else "none"


def run_setup_probe(task_id, helpers):
    task_dir = TASKS_ROOT / task_id
    log_path = LOG_DIR / f"{task_id}.log"
    work_root = pathlib.Path(
        tempfile.mkdtemp(prefix=f"ev005-setup-probe-{task_id}-", dir=os.environ.get("TMPDIR", "/tmp"))
    )
    try:
        replica = work_root / "repo"
        helpers.build_replica(task_dir, replica)
        shutil.copy2(task_dir / "donecheck.sh", replica / ".ev005-donecheck.sh")
        git_env = {
            **os.environ,
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
        }
        subprocess.run(
            ["git", "-C", str(replica), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "add", ".ev005-donecheck.sh"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=git_env,
        )
        subprocess.run(
            ["git", "-C", str(replica), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "commit", "-qm", "inject donecheck only"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=git_env,
        )

        isolation_root = work_root / "isolation"
        probe_home = isolation_root / "home"
        probe_tmp = isolation_root / "tmp"
        probe_home.mkdir(parents=True)
        probe_tmp.mkdir()
        env = {
            **git_env,
            "HOME": str(probe_home),
            "TMPDIR": str(probe_tmp),
            "LC_ALL": "C",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        timeout_s = helpers.task_timeout(task_dir)
        started = time.time()
        timeout_hit = False
        try:
            proc = subprocess.run(
                ["bash", ".ev005-donecheck.sh"],
                cwd=replica,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=timeout_s,
            )
            output = proc.stdout
            rc = proc.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            rc = 124
            timeout_hit = True
        duration = int(time.time() - started)

        check_rows = re.findall(r"^CHECK (a\d\d) (PASS|FAIL)(?: .*)?$", output, flags=re.M)
        counts = collections.Counter(check_id for check_id, _ in check_rows)
        statuses = {check_id: status for check_id, status in check_rows if counts[check_id] == 1}
        expected = EXPECTED_IDS[task_id]
        missing = tuple(check_id for check_id in expected if counts[check_id] == 0)
        duplicate = tuple(check_id for check_id in expected if counts[check_id] > 1)
        unexpected = tuple(sorted(check_id for check_id in counts if check_id not in expected))
        coverage_ok = not missing and not duplicate and not unexpected
        dependent_ok = all(statuses.get(check_id) == "FAIL" for check_id in DEPENDENT_IDS[task_id])
        dirty = subprocess.run(
            ["git", "-C", str(replica), "status", "--porcelain"],
            env=git_env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        result_ok = coverage_ok and dependent_ok and rc != 0 and not timeout_hit and not dirty

        with log_path.open("w", encoding="utf-8") as handle:
            handle.write(
                f"== setup-probe {task_id} repo={helpers.task_repo(task_dir)} "
                f"pre={helpers.task_pre_sha(task_dir)} timeout_s={timeout_s} fixtures=omitted ==\n"
            )
            handle.write(output)
            if output and not output.endswith("\n"):
                handle.write("\n")
            handle.write(f"RUN {task_id} setup-probe exit={rc} dur={duration}s timeout={str(timeout_hit).lower()}\n")
            handle.write(f"DIRTY_TREE {dirty.replace(chr(10), ' | ') if dirty else 'clean'}\n")
            handle.write(
                f"CHECK_COVERAGE expected={format_ids(expected)} observed={format_ids(tuple(check_id for check_id, _ in check_rows))} "
                f"missing={format_ids(missing)} duplicate={format_ids(duplicate)} unexpected={format_ids(unexpected)} "
                f"verdict={'PASS' if coverage_ok else 'FAIL'}\n"
            )
            handle.write(
                f"DEPENDENT_FAILS expected={format_ids(DEPENDENT_IDS[task_id])} "
                f"verdict={'PASS' if dependent_ok else 'FAIL'}\n"
            )
            handle.write(f"SETUP_PROBE_RESULT {'PASS' if result_ok else 'FAIL'}\n")
        return result_ok
    finally:
        shutil.rmtree(work_root, ignore_errors=True)


def main(argv):
    tasks = argv[1:] or list(EXPECTED_IDS)
    unknown = [task_id for task_id in tasks if task_id not in EXPECTED_IDS]
    if unknown:
        print(f"unsupported setup-probe task(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    helpers = load_replica_helpers()
    ok = True
    for task_id in tasks:
        print(f"START {task_id}", flush=True)
        task_ok = run_setup_probe(task_id, helpers)
        print(f"DONE {task_id} {'PASS' if task_ok else 'FAIL'}", flush=True)
        ok = task_ok and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
