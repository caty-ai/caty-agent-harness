#!/usr/bin/env python3
"""Host-only local exec channel into an EV-005 task sandbox.

The container name is supplied by the trusted runner environment.  The task
agent receives command results, but no Docker socket, container identifier, or
runner-private path is mounted into the sandbox.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from dataclasses import dataclass
from typing import Mapping, Sequence


SANDBOX_ENV = {
    "HOME": "/home/ev005",
    "TMPDIR": "/home/ev005/tmp",
    "PATH": "/runner-bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
    "EV005_IPC_DIR": "/agent-ipc",
    "EV005_REAL_BASH": "/runner-runtime/real-bash",
    "EV005_REPLICA": "/work/replica",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
}


@dataclass(frozen=True)
class ExecResult:
    argv: list[str]
    returncode: int
    stdout: bytes
    stderr: bytes


def docker_exec_argv(container: str, argv: Sequence[str], extra_env: Mapping[str, str] | None = None) -> list[str]:
    if not container or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-" for ch in container):
        raise ValueError("invalid EV-005 container name")
    if not argv:
        raise ValueError("empty sandbox command")
    env = dict(SANDBOX_ENV)
    timeout_value = os.environ.get("EV005_DONECHECK_TIMEOUT_S")
    if timeout_value:
        env["EV005_DONECHECK_TIMEOUT_S"] = timeout_value
    if extra_env:
        env.update({str(k): str(v) for k, v in extra_env.items()})
    command = ["docker", "exec", "--user", "ev005", "--workdir", "/work/replica"]
    for key, value in sorted(env.items()):
        command.extend(["--env", f"{key}={value}"])
    command.append(container)
    command.extend(str(part) for part in argv)
    return command


def run_in_sandbox(
    argv: Sequence[str], *, container: str | None = None,
    timeout_s: float | None = None, extra_env: Mapping[str, str] | None = None,
) -> ExecResult:
    name = container or os.environ.get("EV005_CONTAINER_NAME", "")
    command = docker_exec_argv(name, argv, extra_env)
    try:
        cp = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=timeout_s)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"sandbox local-exec timeout after {timeout_s}s") from exc
    return ExecResult(command, cp.returncode, cp.stdout, cp.stderr)


def run_shell(command: str, *, timeout_s: float | None = None) -> ExecResult:
    return run_in_sandbox(["/bin/bash", "-lc", command], timeout_s=timeout_s)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout-s", type=float)
    ap.add_argument("--shell")
    ap.add_argument("command", nargs=argparse.REMAINDER)
    ns = ap.parse_args(argv)
    result = run_shell(ns.shell, timeout_s=ns.timeout_s) if ns.shell is not None else run_in_sandbox(ns.command, timeout_s=ns.timeout_s)
    os.write(1, result.stdout)
    os.write(2, result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
