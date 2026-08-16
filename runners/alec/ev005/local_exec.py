#!/usr/bin/env python3
"""Host-only local exec channel into an EV-005 task sandbox.

The container name is supplied by the trusted runner environment.  The task
agent receives command results, but no Docker socket, container identifier, or
runner-private path is mounted into the sandbox.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from dataclasses import dataclass
from typing import Sequence


SUPERVISOR_READY = b"EV005_SUPERVISOR_READY_v1\n"
SUPERVISOR_RESULT_PREFIX = b"\0EV005_SUPERVISOR_RESULT_v1 "
SUPERVISOR_INFRA_PREFIX = b"\0EV005_SUPERVISOR_INFRA_v1 "


@dataclass(frozen=True)
class ExecResult:
    argv: list[str]
    returncode: int
    stdout: bytes
    stderr: bytes


class ExecInfrastructureError(RuntimeError):
    """The Docker/supervisor channel failed; this is not task-command output."""


def validate_timeout_s(timeout_s: float | int) -> float:
    if isinstance(timeout_s, bool) or not isinstance(timeout_s, (int, float)):
        raise ValueError("timeout_s must be a number")
    value = float(timeout_s)
    if not math.isfinite(value) or value <= 0 or value > 1800:
        raise ValueError("timeout_s must be finite and satisfy 0 < timeout_s <= 1800")
    return value


def docker_exec_argv(container: str, argv: Sequence[str], timeout_s: float) -> list[str]:
    if not container or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-" for ch in container):
        raise ValueError("invalid EV-005 container name")
    if not argv:
        raise ValueError("empty sandbox command")
    timeout_s = validate_timeout_s(timeout_s)
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
    effective_timeout = validate_timeout_s(1800.0 if timeout_s is None else timeout_s)
    command = docker_exec_argv(name, argv, effective_timeout)
    try:
        cp = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            timeout=effective_timeout + 5.0,
        )
    except subprocess.TimeoutExpired as exc:
        raise ExecInfrastructureError(
            f"sandbox local-exec channel timeout after {effective_timeout}s"
        ) from exc
    except OSError as exc:
        raise ExecInfrastructureError(f"docker exec channel unavailable: {exc}") from exc
    if not cp.stderr.startswith(SUPERVISOR_READY):
        detail = cp.stderr.decode(errors="replace").strip()
        raise ExecInfrastructureError(
            f"docker exec channel failed before trusted supervisor start rc={cp.returncode}: {detail}"
        )
    stderr = cp.stderr[len(SUPERVISOR_READY):]
    infra_at = stderr.rfind(SUPERVISOR_INFRA_PREFIX)
    result_at = stderr.rfind(SUPERVISOR_RESULT_PREFIX)
    if infra_at > result_at and stderr[infra_at:].endswith(b"\n"):
        detail = stderr[infra_at + len(SUPERVISOR_INFRA_PREFIX):].decode(errors="replace").strip()
        raise ExecInfrastructureError(f"sandbox supervisor failed: {detail}")
    if result_at < 0 or not stderr[result_at:].endswith(b"\n"):
        raise ExecInfrastructureError("docker exec channel ended without trusted supervisor result")
    try:
        supervised_returncode = int(
            stderr[result_at + len(SUPERVISOR_RESULT_PREFIX):].strip()
        )
    except ValueError as exc:
        raise ExecInfrastructureError("malformed trusted supervisor result") from exc
    if supervised_returncode != cp.returncode:
        raise ExecInfrastructureError(
            f"docker exec status mismatch: supervisor={supervised_returncode} docker={cp.returncode}"
        )
    task_stderr = stderr[:result_at]
    return ExecResult(command, cp.returncode, cp.stdout, task_stderr)


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
