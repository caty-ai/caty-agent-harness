#!/usr/bin/env python3
"""Minimal stdio MCP server exposing only EV-005 sandbox command execution."""

from __future__ import annotations

import json
import base64
import hashlib
import os
import sys
from pathlib import Path
from typing import Any

from local_exec import ExecInfrastructureError, run_shell, validate_timeout_s


TOOL = {
    "name": "sandbox_exec",
    "description": "Run a shell command in the networkless EV-005 task sandbox at /work/replica. All task file and command work must use this tool.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Shell command to run inside the task sandbox."},
            "timeout_s": {"type": "number", "exclusiveMinimum": 0, "maximum": 1800},
        },
        "required": ["command"],
        "additionalProperties": False,
    },
}


def _append_private_jsonl(env_name: str, row: dict[str, Any]) -> None:
    raw_path = os.environ.get(env_name)
    if not raw_path:
        return
    path = Path(raw_path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = json.dumps(row, sort_keys=True, separators=(",", ":")).encode() + b"\n"
    fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        if os.write(fd, payload) != len(payload):
            raise OSError("short private audit write")
        os.fsync(fd)
    finally:
        os.close(fd)


def audit_exec_result(stdout: bytes, stderr: bytes) -> None:
    payload = stdout + stderr
    _append_private_jsonl("EV005_EXEC_AUDIT_PATH", {
        "stdout_b64": base64.b64encode(stdout).decode(),
        "stderr_b64": base64.b64encode(stderr).decode(),
        "byte_count": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    })


def signal_infrastructure(error_text: str) -> None:
    _append_private_jsonl("EV005_INFRA_SIGNAL_PATH", {"error": error_text})


def send(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def reply(request_id: Any, result: Any) -> None:
    send({"jsonrpc": "2.0", "id": request_id, "result": result})


def error(request_id: Any, code: int, message: str) -> None:
    send({"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}})


def handle(row: dict[str, Any]) -> None:
    method = row.get("method")
    request_id = row.get("id")
    if method == "initialize":
        reply(request_id, {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "ev005-local-exec", "version": "1"},
        })
    elif method == "notifications/initialized":
        return
    elif method == "ping":
        reply(request_id, {})
    elif method == "tools/list":
        reply(request_id, {"tools": [TOOL]})
    elif method == "tools/call":
        params = row.get("params") or {}
        if params.get("name") != TOOL["name"]:
            error(request_id, -32602, "unknown tool")
            return
        args = params.get("arguments") or {}
        try:
            if not isinstance(args, dict) or set(args) - {"command", "timeout_s"}:
                raise ValueError("tool arguments contain unregistered fields")
            if not isinstance(args.get("command"), str):
                raise ValueError("command must be a string")
            timeout = validate_timeout_s(args.get("timeout_s", 1800))
            result = run_shell(args["command"], timeout_s=timeout)
            audit_exec_result(result.stdout, result.stderr)
            text = (result.stdout + result.stderr).decode(errors="replace")
            reply(request_id, {
                "content": [{"type": "text", "text": text}],
                "isError": result.returncode != 0,
                "structuredContent": {"exit_code": result.returncode},
            })
        except (KeyError, TypeError, ValueError) as exc:
            error(request_id, -32602, f"invalid sandbox_exec arguments: {exc}")
        except ExecInfrastructureError as exc:
            message = f"{type(exc).__name__}: {exc}"
            signal_infrastructure(message)
            error(request_id, -32001, "sandbox_exec infrastructure channel failed")
        except OSError as exc:
            message = f"{type(exc).__name__}: {exc}"
            signal_infrastructure(message)
            error(request_id, -32001, "sandbox_exec audit/infrastructure channel failed")
    elif request_id is not None:
        error(request_id, -32601, "method not found")


def main() -> int:
    for line in sys.stdin:
        row: Any = None
        try:
            row = json.loads(line)
            if isinstance(row, dict):
                handle(row)
        except Exception as exc:
            request_id = row.get("id") if isinstance(row, dict) else None
            error(request_id, -32700, f"parse/dispatch error: {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
