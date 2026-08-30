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
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from lib_overflow_sentinel import (  # noqa: E402
    K,
    M,
    N,
    SCHEMA_VERSION,
    atomic_write_json,
    axis_name,
    canonical_model,
    compaction_suspected,
    compare_regime_identity,
    eligible_fire_axes,
    evaluate_drift_turn,
    evaluate_series,
    load_state,
    new_drift_accumulator,
    outcome_from_result,
    parse_model_aliases,
    parse_model_thresholds,
    reset_regime_state,
    raw_usage_signature,
    resolve_ctx_window,
    resolve_thresholds,
    save_state,
    ttfb_floor_seconds,
    weakest_drift_reference,
)


DRIFT_REFERENCE = "derived"
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


def _drift_reference_for_model(model_identity: str) -> str:
    """Return this adapter's capability, with a test-only regime override."""
    if os.environ.get("_CATY_TESTING") != "1":
        return DRIFT_REFERENCE
    raw = os.environ.get("_CATY_OVF_TEST_DRIFT_REFERENCES")
    if not raw:
        return DRIFT_REFERENCE
    try:
        overrides = json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError("test drift references must be valid JSON") from exc
    if not isinstance(overrides, dict):
        raise ValueError("test drift references must be a JSON object")
    value = overrides.get(model_identity, overrides.get("*", DRIFT_REFERENCE))
    if value not in {"independent", "derived", "none"}:
        raise ValueError("test drift reference must be independent, derived, or none")
    return value


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


def _run_meta(mode: str, t_abs: int, w: float, threshold_sources: Mapping[str, str]) -> Dict[str, Any]:
    return {
        "arm": mode,
        "seed": None,
        "shuffle_seed": None,
        "T_abs": t_abs,
        "w": w,
        "N": N,
        "M": M,
        "K": K,
        "threshold_sources": dict(threshold_sources),
    }


def _resolve_regime_config(
    args: argparse.Namespace, model_identity: str, previous_injected_ma: Optional[float]
) -> Tuple[int, str, int, float, Dict[str, str], int]:
    ctx_window, ctx_source = resolve_ctx_window(
        args.ctx_window,
        args.hf_config,
        model_identity,
        hf_network=args.hf_network,
        hf_cache_dir=args.hf_cache_dir,
    )
    threshold_table, _, _ = args.model_thresholds
    t_abs, w, threshold_sources = resolve_thresholds(
        args.t_abs, args.w, model_identity, threshold_table
    )
    floor_s = ttfb_floor_seconds(previous_injected_ma, model_identity)
    if os.environ.get("_CATY_TESTING") == "1" and os.environ.get("_CATY_OVF_TEST_TTFB_FLOOR_S"):
        floor_s = max(0, int(os.environ["_CATY_OVF_TEST_TTFB_FLOOR_S"]))
    return ctx_window, ctx_source, t_abs, w, threshold_sources, floor_s


def _withdraw_pending(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


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
    last_run_injected_ma = state["last_run_injected_ma"]
    persisted_identity = state["regime_identity"]
    startup_model_identity = (
        persisted_identity["model"]
        if persisted_identity is not None
        else canonical_model(args.model, args.model_aliases) or "claude-unknown"
    )
    ctx_window, ctx_source, t_abs, w, threshold_sources, floor_s = _resolve_regime_config(
        args, startup_model_identity, last_run_injected_ma
    )
    meta = _run_meta(args.mode, t_abs, w, threshold_sources)
    _, n_drift, theta_drift = args.model_thresholds

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
    runtime_compaction_pending = False
    regime_change_resets = 0
    tap_drift_count = 0
    previous_identity: Optional[Dict[str, str]] = persisted_identity
    current_drift_reference = _drift_reference_for_model(startup_model_identity)
    drift_references = [current_drift_reference] if persisted_identity is not None else []
    drift_accumulator = new_drift_accumulator()
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
                runtime_compaction_pending = True
                _withdraw_pending(pending_path)
                continue
            if event.get("type") != "assistant" or event.get("parent_tool_use_id") is not None:
                continue
            if first_byte_at is None:
                first_byte_at = str(event.get("timestamp") or now_utc())
            message = event.get("message")
            if not isinstance(message, dict) or args.tap_status == "disabled-host":
                continue
            identity = message.get("id")
            if isinstance(identity, str) and identity:
                if identity in seen_ids:
                    continue
                seen_ids.add(identity)
            usage_value = message.get("usage")
            usage = usage_value if isinstance(usage_value, dict) else None
            if usage is not None and usage.get("input_tokens") is not None:
                saw_usage = True
            has_cache = usage is not None and (
                "cache_read_input_tokens" in usage
                and "cache_creation_input_tokens" in usage
            )
            input_tokens = (
                _usage_int(usage.get("input_tokens"))
                if usage is not None and usage.get("input_tokens") is not None
                else None
            )
            cache_read = (
                _usage_int(usage.get("cache_read_input_tokens", 0))
                if usage is not None
                else None
            )
            cache_creation = (
                _usage_int(usage.get("cache_creation_input_tokens", 0))
                if usage is not None
                else None
            )
            output_tokens = (
                _usage_int(usage.get("output_tokens", 0)) if usage is not None else None
            )
            normalized = None not in (input_tokens, cache_read, cache_creation, output_tokens)
            injected = (
                int(input_tokens) + int(cache_read) + int(cache_creation) if normalized else None
            )
            blind = bool(
                normalized and has_cache and injected == 0 and output_tokens == 0
            )
            if blind:
                turn_tap_status = "blind"
                blind_seen = True
                consecutive_blind += 1
            elif normalized:
                turn_tap_status = "ok" if has_cache else "no-cache-accounting"
                consecutive_blind = 0
                if not has_cache:
                    saw_no_cache = True
            else:
                turn_tap_status = "absent" if usage is None else "no-cache-accounting"
                consecutive_blind = 0
                saw_no_cache = saw_no_cache or usage is not None
            turn_count += 1
            raw_model = message.get("model") if "model" in message else None
            regime_changed, current_identity = compare_regime_identity(
                previous_identity, raw_model, "claude-code", args.model_aliases
            )
            identity_established = previous_identity is None and current_identity is not None
            if regime_changed:
                old_identity = previous_identity
                cleared = reset_regime_state()
                series = cleared["series"]
                last_injected = cleared["last_injected"]
                last_fire_ma = cleared["last_fire_ma"]
                drift_accumulator = new_drift_accumulator()
                _withdraw_pending(pending_path)
                last_run_injected_ma = None
                save_state(state_path, last_fire_ma, None, current_identity)
                ctx_window, ctx_source, t_abs, w, threshold_sources, floor_s = _resolve_regime_config(
                    args, current_identity["model"], None
                )
                meta = _run_meta(args.mode, t_abs, w, threshold_sources)
                regime_change_resets += 1
                old_drift_reference = current_drift_reference
                current_drift_reference = _drift_reference_for_model(
                    current_identity["model"]
                )
                drift_references.append(current_drift_reference)
                append_event(
                    events_path,
                    {
                        "event": "regime_change",
                        "schema_version": SCHEMA_VERSION,
                        "ts": str(event.get("timestamp") or now_utc()),
                        "task_id": args.task_id,
                        "attempt": args.attempt,
                        "turn_idx": turn_count,
                        "from_model": old_identity["model"],
                        "to_model": current_identity["model"],
                        "from_runtime": old_identity["runtime"],
                        "to_runtime": current_identity["runtime"],
                        "resolved": {
                            "ctx_window": ctx_window,
                            "T_abs": t_abs,
                            "w": w,
                            "ttfb_floor": floor_s,
                        },
                        "sources": {
                            "ctx_window_source": ctx_source,
                            "threshold_sources": dict(threshold_sources),
                        },
                        "drift_reference": {
                            "from": old_drift_reference,
                            "to": current_drift_reference,
                        },
                    },
                )
                runtime_compaction_pending = False
            elif runtime_compaction_pending:
                series = []
                last_injected = None
                runtime_compaction_pending = False
            if identity_established:
                current_drift_reference = _drift_reference_for_model(
                    current_identity["model"]
                )
                drift_references.append(current_drift_reference)
                save_state(state_path, last_fire_ma, last_run_injected_ma, current_identity)
            previous_identity = current_identity
            model = str(raw_model or model)
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
                "runtime": "claude-code",
                "tap_status": turn_tap_status,
            }
            if current_drift_reference != "none":
                turn_event["raw_usage"] = usage
                turn_event["raw_usage_schema"] = raw_usage_signature(usage)
            append_event(events_path, turn_event)
            drift_events = evaluate_drift_turn(
                drift_accumulator,
                turn_event,
                current_drift_reference,
                n_drift,
                theta_drift,
            )
            for drift_event in drift_events:
                append_event(events_path, drift_event)
            tap_drift_count += len(drift_events)
            if not normalized:
                continue
            total_tokens += int(injected) + int(output_tokens)
            if blind:
                if consecutive_blind >= 3:
                    evaluation_disabled = True
                continue
            if injected == 0:
                continue
            if evaluation_disabled:
                continue
            if not regime_changed and compaction_suspected(last_injected, injected):
                compaction_seen = True
                series = []
                _withdraw_pending(pending_path)
            series.append(injected)
            last_injected = injected
            turn = evaluate_series(series, t_abs, w, ctx_window)["turns"][-1]
            axes = eligible_fire_axes(turn["axis"], turn["injected_ma"], ctx_window, last_fire_ma)
            if not axes:
                continue
            fire_axis = axis_name(axes)
            for fire_candidate in axes:
                last_fire_ma[fire_candidate] = turn["injected_ma"]
            save_state(state_path, last_fire_ma, last_run_injected_ma, previous_identity)
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

    if runtime_compaction_pending:
        series = []
        last_injected = None

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
        save_state(state_path, last_fire_ma, last_run_ma, previous_identity)
    result = _read_step_result(attempt_dir / "step-result.json")
    outcome = outcome_from_result(cli_exit_code, result)
    window_error = outcome == "overflowed"
    if args.nudge_shown:
        final_disposition = "shown"
    elif fired_turns:
        final_disposition = "shadow" if args.mode == "shadow" else "suppressed"
    else:
        final_disposition = "none"
    drift_reference_status = weakest_drift_reference(
        drift_references or [current_drift_reference]
    )
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
        "regime_change_resets": regime_change_resets,
        "tap_drift_count": tap_drift_count,
        "drift_reference_status": drift_reference_status,
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
    parser.add_argument("--t-abs", type=int)
    parser.add_argument("--w", type=float)
    parser.add_argument("--model-aliases", type=parse_model_aliases, default={})
    parser.add_argument(
        "--model-thresholds",
        type=parse_model_thresholds,
        default=parse_model_thresholds(None),
    )
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
