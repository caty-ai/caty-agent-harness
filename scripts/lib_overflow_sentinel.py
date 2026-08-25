#!/usr/bin/env python3
"""Shared overflow-sentinel v1 predicate and persistence helpers."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
N = 3
K = 3
M = 10
DEFAULT_T_ABS = 80000
DEFAULT_W = 0.50
DEFAULT_CTX_WINDOW = 200000

# Prefix catalog only.  Provider training limits are deliberately not inferred.
CTX_WINDOW_CATALOG = (
    ("claude-", 200000),
)

# Named reasoning floors are alert delays, never kill deadlines. Unknown models
# take the conservative 240-second floor in ttfb_floor_seconds().
REASONING_TTFB_FLOORS = (
    ("claude-opus", 240),
    ("deepseek-r1", 600),
    ("glm-5", 300),
    ("grok-", 300),
    ("o1", 600),
    ("o3", 600),
    ("qwen3", 180),
    ("qwq", 300),
)


def atomic_write_json(path: Path, payload: Mapping[str, Any]) -> None:
    """Write one JSON object with fsync + replace in the destination directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=True, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, str(path))
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def load_state(path: Path) -> Dict[str, Any]:
    default = {
        "schema_version": SCHEMA_VERSION,
        "last_fire_ma": {},
        "last_run_injected_ma": None,
    }
    try:
        with path.open(encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError, TypeError):
        return default
    if not isinstance(payload, dict) or payload.get("schema_version") != SCHEMA_VERSION:
        return default
    last_fire = payload.get("last_fire_ma")
    if not isinstance(last_fire, dict):
        last_fire = {}
    clean_fire = {}
    for axis in ("level", "slope"):
        value = last_fire.get(axis)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0:
            clean_fire[axis] = float(value)
    last_run = payload.get("last_run_injected_ma")
    if not isinstance(last_run, (int, float)) or isinstance(last_run, bool) or last_run < 0:
        last_run = None
    return {
        "schema_version": SCHEMA_VERSION,
        "last_fire_ma": clean_fire,
        "last_run_injected_ma": last_run,
    }


def save_state(path: Path, last_fire_ma: Mapping[str, float], last_run_injected_ma: Optional[float]) -> None:
    atomic_write_json(
        path,
        {
            "schema_version": SCHEMA_VERSION,
            "last_fire_ma": dict(last_fire_ma),
            "last_run_injected_ma": last_run_injected_ma,
        },
    )


def _threshold_hit(ma_value: float, t_abs: int, ratio_threshold: float) -> str:
    hits = []
    if ma_value > t_abs:
        hits.append("abs")
    if ma_value > ratio_threshold:
        hits.append("ratio")
    if len(hits) == 2:
        return "both"
    if hits:
        return hits[0]
    # A slope-only fire has crossed neither level threshold. The wire schema has
    # no "none" value, so identify the threshold that currently governs min().
    if t_abs == ratio_threshold:
        return "both"
    return "abs" if t_abs < ratio_threshold else "ratio"


def evaluate_series(
    series: Sequence[int],
    t_abs: int = DEFAULT_T_ABS,
    w: float = DEFAULT_W,
    ctx: int = DEFAULT_CTX_WINDOW,
) -> Dict[str, Any]:
    """Evaluate the frozen N=3/K=3/M=10 predicate over one fresh run."""
    ratio_threshold = w * ctx
    threshold = min(t_abs, ratio_threshold)
    turns = []
    ma_values = []
    for turn_idx, injected_last in enumerate(series, start=1):
        window = series[max(0, turn_idx - N) : turn_idx]
        ma_value = sum(window) / float(len(window))
        ma_values.append(ma_value)
        level_fire = ma_value > threshold
        slope = None
        projection_turns = None
        slope_fire = False
        if turn_idx >= K + 1:
            slope = (ma_value - ma_values[-1 - K]) / K
            if slope > 0:
                projection_turns = (ctx - ma_value) / slope
                slope_fire = projection_turns <= M
        axis = None
        if level_fire or slope_fire:
            axis = "both" if level_fire and slope_fire else ("level" if level_fire else "slope")
        turn = {
            "turn_idx": turn_idx,
            "injected_last": injected_last,
            "injected_ma": ma_value,
            "level_fire": level_fire,
            "slope": slope,
            "projection_turns": projection_turns,
            "slope_fire": slope_fire,
            "axis": axis,
            "threshold": threshold,
        }
        if axis is not None:
            turn["threshold_hit"] = _threshold_hit(ma_value, t_abs, ratio_threshold)
        turns.append(turn)
    return {
        "series": list(series),
        "threshold": threshold,
        "ratio_threshold": ratio_threshold,
        "turns": turns,
        "params": {"T_abs": t_abs, "w": w, "ctx_window": ctx, "N": N, "K": K, "M": M},
    }


def fire_axes(axis: Optional[str]) -> List[str]:
    if axis == "both":
        return ["level", "slope"]
    if axis in ("level", "slope"):
        return [axis]
    return []


def eligible_fire_axes(
    axis: Optional[str], ma_value: float, ctx_window: int, last_fire_ma: Mapping[str, float]
) -> List[str]:
    """Apply task-scoped per-axis hysteresis; exact +10% re-arms (>=)."""
    eligible = []
    increment = 0.10 * ctx_window
    for candidate in fire_axes(axis):
        previous = last_fire_ma.get(candidate)
        if previous is None or ma_value >= previous + increment:
            eligible.append(candidate)
    return eligible


def axis_name(axes: Sequence[str]) -> Optional[str]:
    if "level" in axes and "slope" in axes:
        return "both"
    return axes[0] if axes else None


def compaction_suspected(previous: Optional[int], current: int) -> bool:
    return previous is not None and current < 0.60 * previous


def _hf_window(config_path: Path) -> int:
    candidate = config_path / "config.json" if config_path.is_dir() else config_path
    if not candidate.is_file() or candidate.is_symlink():
        raise ValueError("HF config must be a non-symlink regular config.json file")
    try:
        with candidate.open(encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ValueError("HF config is not readable JSON") from exc
    if not isinstance(payload, dict):
        raise ValueError("HF config must contain a JSON object")
    for key in ("max_position_embeddings", "n_positions", "max_seq_len", "model_max_length"):
        value = payload.get(key)
        if isinstance(value, int) and not isinstance(value, bool) and value >= 1:
            return value
    raise ValueError("HF config has no positive supported context-window field")


def resolve_ctx_window(
    configured: Optional[int], hf_config: Optional[str], model: str
) -> Tuple[int, str]:
    if configured is not None:
        if configured < 1:
            raise ValueError("configured context window must be positive")
        return configured, "config"
    if hf_config:
        return _hf_window(Path(hf_config)), "hf-config"
    normalized = model.lower().split("/")[-1]
    for prefix, window in CTX_WINDOW_CATALOG:
        if normalized.startswith(prefix):
            return window, "catalog"
    return DEFAULT_CTX_WINDOW, "default"


def ttfb_floor_seconds(previous_injected_ma: Optional[float], model: str) -> int:
    normalized = model.lower().split("/")[-1]
    for prefix, floor in REASONING_TTFB_FLOORS:
        if normalized.startswith(prefix):
            return floor
    if not normalized.startswith("claude-"):
        return 240
    if previous_injected_ma is None:
        return 240
    if previous_injected_ma > 100000:
        return 240
    if previous_injected_ma > 50000:
        return 150
    return 90


def outcome_from_result(cli_exit_code: int, result: Mapping[str, Any]) -> str:
    error_class = str(result.get("error_class") or "")
    window_error = bool(result.get("window_error")) or error_class == "window-error"
    if window_error:
        return "overflowed"
    if cli_exit_code == 0 and result.get("step_complete") is True:
        return "step_completed"
    return "aborted"


def _main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    evaluate = sub.add_parser("eval-series")
    evaluate.add_argument("--series", required=True)
    evaluate.add_argument("--t-abs", type=int, default=DEFAULT_T_ABS)
    evaluate.add_argument("--w", type=float, default=DEFAULT_W)
    evaluate.add_argument("--ctx", type=int, default=DEFAULT_CTX_WINDOW)
    validate_hf = sub.add_parser("validate-hf")
    validate_hf.add_argument("path")
    args = parser.parse_args(argv)
    if args.command == "eval-series":
        values = [int(part) for part in args.series.split(",") if part]
        print(json.dumps(evaluate_series(values, args.t_abs, args.w, args.ctx), sort_keys=True))
        return 0
    try:
        print(_hf_window(Path(args.path)))
    except ValueError as exc:
        print(str(exc), file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
