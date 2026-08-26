#!/usr/bin/env python3
"""Passive Claude stream-json tailer for overflow-sentinel v1."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from lib_overflow_sentinel import (  # noqa: E402
    K,
    M,
    N,
    SCHEMA_VERSION,
    atomic_write_json,
    axis_name,
    compaction_suspected,
    eligible_fire_axes,
    evaluate_series,
    load_state,
    outcome_from_result,
    resolve_ctx_window,
    save_state,
    ttfb_floor_seconds,
)


ATTEMPT_FIELDS = {
    "schema_version",
    "task_id",
    "attempt",
    "mode",
    "model",
    "ctx_window",
    "ctx_window_source",
    "started_at",
    "first_byte_at",
    "cli_exit_code",
    "tap_status_final",
    "fired",
    "events_path",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def append_event(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n")
        handle.flush()


def _read_complete_lines(path: Path, offset: int, pending: bytes) -> Tuple[List[str], int, bytes]:
    if not path.exists():
        return [], offset, pending
    with path.open("rb") as handle:
        handle.seek(offset)
        chunk = handle.read()
    offset += len(chunk)
    data = pending + chunk
    parts = data.split(b"\n")
    pending = parts.pop()
    return [part.decode("utf-8", errors="replace") for part in parts if part], offset, pending


def _usage_from_assistant(event: Dict[str, Any]) -> Optional[Tuple[Dict[str, Any], Dict[str, Any]]]:
    if event.get("type") != "assistant":
        return None
    message = event.get("message")
    if not isinstance(message, dict):
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict) or usage.get("input_tokens") is None:
        return None
    return message, usage


def _usage_int(value: Any) -> Optional[int]:
    if isinstance(value, bool):
        return None
    try:
        result = int(value or 0)
    except (TypeError, ValueError):
        return None
    return max(0, result)


def _read_eof(path: Path) -> Optional[int]:
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    try:
        return int(value)
    except ValueError:
        return 1


def _read_step_result(path: Path) -> Dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _nudge_text(turn: Dict[str, Any], ctx_window: int) -> str:
    return (
        "Overflow sentinel measured context pressure. Before continuing, write only these five delta points:\n"
        "1. Goal\n"
        "2. Current step\n"
        "3. Evidence already completed\n"
        "4. Blocker\n"
        "5. Stop rule\n"
        "Measured injected MA: {ma:.1f} tokens; last turn: {last} tokens; context window: {ctx} tokens.\n"
        "Decomposing the remaining work through task-runner is recommended.\n"
    ).format(ma=turn["injected_ma"], last=turn["injected_last"], ctx=ctx_window)


def _write_pending(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(str(temporary), str(path))


def _run_meta(mode: str, t_abs: int, w: float) -> Dict[str, Any]:
    return {
        "arm": mode,
        "seed": None,
        "shuffle_seed": None,
        "T_abs": t_abs,
        "w": w,
        "N": N,
        "M": M,
        "K": K,
    }


def monitor(args: argparse.Namespace) -> int:
    stream_path = Path(args.stream)
    eof_path = Path(args.eof)
    attempt_dir = Path(args.attempt_dir)
    artifact_dir = Path(args.artifact_dir)
    events_path = attempt_dir / "sentinel-events.jsonl"
    pending_path = attempt_dir / "overflow-nudge.pending"
    state_path = artifact_dir / "overflow-sentinel-state.json"
    started_at = now_utc()
    started_monotonic = time.monotonic()
    if os.environ.get("_CATY_TESTING") == "1" and os.environ.get("_CATY_OVF_TEST_ELAPSED_S"):
        started_monotonic -= max(0.0, float(os.environ["_CATY_OVF_TEST_ELAPSED_S"]))
    state = load_state(state_path)
    last_fire_ma = dict(state["last_fire_ma"])
    ctx_window, ctx_source = resolve_ctx_window(
        args.ctx_window,
        args.hf_config,
        args.model,
        hf_network=args.hf_network,
        hf_cache_dir=args.hf_cache_dir,
    )
    floor_s = ttfb_floor_seconds(state["last_run_injected_ma"], args.model)
    if os.environ.get("_CATY_TESTING") == "1" and os.environ.get("_CATY_OVF_TEST_TTFB_FLOOR_S"):
        floor_s = max(0, int(os.environ["_CATY_OVF_TEST_TTFB_FLOOR_S"]))
    meta = _run_meta(args.mode, args.t_abs, args.w)

    offset = 0
    pending = b""
    seen_ids = set()
    series = []
    total_tokens = 0
    model = args.model
    first_byte_at = None
    alert_written = False
    fired_turns = []
    alert_turns = []
    compaction_seen = False
    runtime_compaction_seen = False
    last_injected = None
    turn_count = 0
    blind_seen = False
    consecutive_blind = 0
    evaluation_disabled = args.tap_status == "disabled-host"
    saw_usage = False
    saw_no_cache = False

    while True:
        lines, offset, pending = _read_complete_lines(stream_path, offset, pending)
        cli_exit_code = _read_eof(eof_path)
        eof_seen = cli_exit_code is not None
        if eof_seen:
            final_lines, offset, pending = _read_complete_lines(stream_path, offset, pending)
            lines.extend(final_lines)
            if pending:
                lines.append(pending.decode("utf-8", errors="replace"))
                pending = b""
        for raw in lines:
            try:
                event = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if not isinstance(event, dict):
                continue
            if event.get("type") == "system" and event.get("subtype") == "compact_boundary":
                runtime_compaction_seen = True
                series = []
                last_injected = None
                try:
                    pending_path.unlink()
                except FileNotFoundError:
                    pass
                continue
            if event.get("type") != "assistant" or event.get("parent_tool_use_id") is not None:
                continue
            if first_byte_at is None:
                first_byte_at = str(event.get("timestamp") or now_utc())
            parsed = _usage_from_assistant(event)
            if parsed is None or args.tap_status == "disabled-host":
                continue
            message, usage = parsed
            identity = message.get("id")
            if isinstance(identity, str) and identity:
                if identity in seen_ids:
                    continue
                seen_ids.add(identity)
            saw_usage = True
            has_cache = "cache_read_input_tokens" in usage and "cache_creation_input_tokens" in usage
            input_tokens = _usage_int(usage.get("input_tokens"))
            cache_read = _usage_int(usage.get("cache_read_input_tokens", 0))
            cache_creation = _usage_int(usage.get("cache_creation_input_tokens", 0))
            output_tokens = _usage_int(usage.get("output_tokens", 0))
            if None in (input_tokens, cache_read, cache_creation, output_tokens):
                saw_no_cache = True
                continue
            injected = input_tokens + cache_read + cache_creation
            blind = has_cache and injected == 0 and output_tokens == 0
            if blind:
                turn_tap_status = "blind"
                blind_seen = True
                consecutive_blind += 1
            else:
                turn_tap_status = "ok" if has_cache else "no-cache-accounting"
                consecutive_blind = 0
                if not has_cache:
                    saw_no_cache = True
            turn_count += 1
            model = str(message.get("model") or model)
            total_tokens += injected + output_tokens
            turn_event = {
                "event": "turn",
                "schema_version": SCHEMA_VERSION,
                "ts": str(event.get("timestamp") or now_utc()),
                "task_id": args.task_id,
                "attempt": args.attempt,
                "turn_idx": turn_count,
                "input_tokens": input_tokens,
                "cache_read_tokens": cache_read,
                "cache_creation_tokens": cache_creation,
                "output_tokens": output_tokens,
                "model": model,
                "tap_status": turn_tap_status,
            }
            append_event(events_path, turn_event)
            if blind:
                if consecutive_blind >= 3:
                    evaluation_disabled = True
                continue
            if injected == 0:
                continue
            if evaluation_disabled:
                continue
            if compaction_suspected(last_injected, injected):
                compaction_seen = True
                series = []
                try:
                    pending_path.unlink()
                except FileNotFoundError:
                    pass
            series.append(injected)
            last_injected = injected
            turn = evaluate_series(series, args.t_abs, args.w, ctx_window)["turns"][-1]
            axes = eligible_fire_axes(turn["axis"], turn["injected_ma"], ctx_window, last_fire_ma)
            if not axes:
                continue
            fire_axis = axis_name(axes)
            for fire_candidate in axes:
                last_fire_ma[fire_candidate] = turn["injected_ma"]
            save_state(state_path, last_fire_ma, state["last_run_injected_ma"])
            fire_event = {
                "event": "fire",
                "schema_version": SCHEMA_VERSION,
                "ts": now_utc(),
                "started_at": started_at,
                "task_id": args.task_id,
                "attempt": args.attempt,
                "turn_idx": turn_count,
                "axis": fire_axis,
                "injected_ma": turn["injected_ma"],
                "injected_last": turn["injected_last"],
                "value_kind": "measured",
                "ctx_window": ctx_window,
                "ctx_window_source": ctx_source,
                "slope": turn["slope"],
                "projection_turns": turn["projection_turns"],
                "decision": "nudge",
                "nudge_disposition": "shadow" if args.mode == "shadow" else "suppressed",
                "model": model,
                "runtime": "claude-code",
                "tap_status": "no-cache-accounting" if saw_no_cache else "ok",
                "run_meta": meta,
            }
            if "threshold_hit" in turn:
                fire_event["threshold_hit"] = turn["threshold_hit"]
            append_event(events_path, fire_event)
            fired_turns.append(turn_count)
            if args.mode == "active":
                _write_pending(pending_path, _nudge_text(turn, ctx_window))

        elapsed = time.monotonic() - started_monotonic
        if first_byte_at is None and not alert_written and elapsed > floor_s:
            alert_turn = turn_count + 1
            append_event(
                events_path,
                {
                    "event": "alert",
                    "schema_version": SCHEMA_VERSION,
                    "ts": now_utc(),
                    "task_id": args.task_id,
                    "attempt": args.attempt,
                    "turn_idx": alert_turn,
                    "ttfb_ms": int(elapsed * 1000),
                    "floor_applied": floor_s,
                    "model": model,
                    "runtime": "claude-code",
                },
            )
            alert_written = True
            alert_turns.append(alert_turn)
        if eof_seen:
            break
        time.sleep(args.poll_interval)

    if os.environ.get("_CATY_TESTING") == "1" and os.environ.get("_CATY_OVF_TEST_HANG_FINALIZE") == "1":
        while True:
            time.sleep(1)

    if args.tap_status == "disabled-host":
        tap_status_final = "disabled-host"
    elif blind_seen:
        tap_status_final = "blind"
    elif saw_no_cache:
        tap_status_final = "no-cache-accounting"
    elif saw_usage:
        tap_status_final = "ok"
    else:
        tap_status_final = "absent"

    last_run_ma = sum(series[-N:]) / float(len(series[-N:])) if series else None
    if last_run_ma is not None:
        save_state(state_path, last_fire_ma, last_run_ma)
    result = _read_step_result(attempt_dir / "step-result.json")
    outcome = outcome_from_result(cli_exit_code, result)
    window_error = outcome == "overflowed"
    if args.nudge_shown:
        final_disposition = "shown"
    elif fired_turns:
        final_disposition = "shadow" if args.mode == "shadow" else "suppressed"
    else:
        final_disposition = "none"
    attempt_end = {
        "event": "attempt_end",
        "schema_version": SCHEMA_VERSION,
        "ts": now_utc(),
        "started_at": started_at,
        "task_id": args.task_id,
        "attempt": args.attempt,
        "outcome": outcome,
        "window_error": window_error,
        "runtime_compaction": runtime_compaction_seen,
        "compaction_suspected": compaction_seen,
        "total_tokens": total_tokens,
        "injected_summary": {
            "max": max(series) if series else 0,
            "last3_mean": last_run_ma or 0,
        },
        "fired_turns": fired_turns,
        "alert_turns": alert_turns,
        "nudge_disposition_final": final_disposition,
        "tap_status": tap_status_final,
        "run_meta": meta,
        "elapsed_s": round(time.monotonic() - started_monotonic, 3),
    }
    append_event(events_path, attempt_end)
    attempt_receipt = {
        "schema_version": SCHEMA_VERSION,
        "task_id": args.task_id,
        "attempt": args.attempt,
        "mode": args.mode,
        "model": model,
        "ctx_window": ctx_window,
        "ctx_window_source": ctx_source,
        "started_at": started_at,
        "first_byte_at": first_byte_at,
        "cli_exit_code": cli_exit_code,
        "tap_status_final": tap_status_final,
        "fired": bool(fired_turns),
        "events_path": str(events_path),
    }
    if set(attempt_receipt) != ATTEMPT_FIELDS:
        raise RuntimeError("attempt receipt field set drifted")
    atomic_write_json(attempt_dir / "attempt.json", attempt_receipt)
    return 0


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stream", required=True)
    parser.add_argument("--eof", required=True)
    parser.add_argument("--attempt-dir", required=True)
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--mode", required=True, choices=("shadow", "active"))
    parser.add_argument("--model", default="claude-unknown")
    parser.add_argument("--t-abs", required=True, type=int)
    parser.add_argument("--w", required=True, type=float)
    parser.add_argument("--ctx-window", type=int)
    parser.add_argument("--hf-config")
    parser.add_argument("--hf-network", action="store_true")
    parser.add_argument("--hf-cache-dir")
    parser.add_argument("--tap-status", default="enabled", choices=("enabled", "disabled-host"))
    parser.add_argument("--nudge-shown", action="store_true")
    parser.add_argument("--poll-interval", type=float, default=0.02)
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(monitor(parse_args()))
