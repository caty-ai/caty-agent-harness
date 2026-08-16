#!/usr/bin/env python3
"""Transparent /usr/bin/bash shim for reliable agent donecheck observation."""

import hashlib
import json
import os
import selectors
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path


def is_donecheck(argv: list[str]) -> bool:
    for arg in argv:
        name = Path(arg).name
        if name in {"donecheck.sh", ".ev005-donecheck.sh"}:
            return True
    return False


def atomic_json(path: Path, row: dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(row, sort_keys=True) + "\n")
    os.replace(tmp, path)


def main() -> int:
    real = os.environ.get("EV005_REAL_BASH", "/runner-private/real-bash")
    argv = [real, *sys.argv[1:]]
    if not is_donecheck(sys.argv[1:]) or not os.environ.get("EV005_IPC_DIR"):
        os.execv(real, argv)
    ipc = Path(os.environ["EV005_IPC_DIR"])
    key = f"{os.getpid()}-{uuid.uuid4().hex}"
    start = time.monotonic()
    atomic_json(ipc / f"start-{key}.json", {
        "start_monotonic_s": start,
        "argv": sys.argv[1:],
    })
    h = hashlib.sha256()
    proc = subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=None,
        preexec_fn=os.setsid,
    )
    assert proc.stdout is not None
    os.set_blocking(proc.stdout.fileno(), False)
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    timeout_s = float(os.environ.get("EV005_DONECHECK_TIMEOUT_S", "120"))
    deadline = start + timeout_s
    timed_out = False
    while proc.poll() is None:
        for key_obj, _ in sel.select(timeout=0.02):
            chunk = os.read(key_obj.fileobj.fileno(), 65536)
            if chunk:
                h.update(chunk)
                os.write(1, chunk)
        if time.monotonic() >= deadline:
            timed_out = True
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            break
    proc.wait()
    while True:
        chunk = os.read(proc.stdout.fileno(), 65536)
        if not chunk:
            break
        h.update(chunk)
        os.write(1, chunk)
    end = time.monotonic()
    rc = 124 if timed_out else proc.returncode
    atomic_json(ipc / f"done-{key}.json", {
        "start_monotonic_s": start,
        "end_monotonic_s": end,
        "exit": rc,
        "stdout_digest": h.hexdigest(),
        "timed_out": timed_out,
    })
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
