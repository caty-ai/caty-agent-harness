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
from typing import Sequence


@dataclass(frozen=True)
class ExecResult:
    argv: list[str]
    returncode: int
    stdout: bytes
    stderr: bytes


def docker_exec_argv(container: str, argv: Sequence[str], timeout_s: float) -> list[str]:
    if not container or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-" for ch in container):
        raise ValueError("invalid EV-005 container name")
    if not argv:
        raise ValueError("empty sandbox command")
    return [
        "docker", "exec", "--user", "0", "--workdir", "/work/replica",
        container, "python3", "/runner-runtime/runner.py", "_container-supervise",
        "--timeout-s", str(timeout_s), "--", *(str(part) for part in argv),
    ]


def run_in_sandbox(
    argv: Sequence[str], *, container: str | None = None,
    timeout_s: float | None = None,
) -> ExecResult:
    name = container or os.environ.get("EV005_CONTAINER_NAME", "")
    effective_timeout = 1800.0 if timeout_s is None else timeout_s
    command = docker_exec_argv(name, argv, effective_timeout)
    try:
        cp = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            timeout=effective_timeout + 5.0,
        )
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
