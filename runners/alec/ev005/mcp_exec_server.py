#!/usr/bin/env python3
"""Minimal stdio MCP server exposing only EV-005 sandbox command execution."""

from __future__ import annotations

import json
import sys
from typing import Any

from local_exec import run_shell


TOOL = {
    "name": "sandbox_exec",
    "description": "Run a shell command in the networkless EV-005 task sandbox at /work/replica. All task file and command work must use this tool.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Shell command to run inside the task sandbox."},
            "timeout_s": {"type": "number", "minimum": 0.1, "maximum": 1800},
        },
        "required": ["command"],
        "additionalProperties": False,
    },
}


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
            result = run_shell(str(args["command"]), timeout_s=float(args.get("timeout_s", 1800)))
            text = (result.stdout + result.stderr).decode(errors="replace")
            reply(request_id, {
                "content": [{"type": "text", "text": text}],
                "isError": result.returncode != 0,
                "structuredContent": {"exit_code": result.returncode},
            })
        except Exception as exc:
            reply(request_id, {
                "content": [{"type": "text", "text": f"local-exec infrastructure error: {type(exc).__name__}: {exc}"}],
                "isError": True,
            })
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
