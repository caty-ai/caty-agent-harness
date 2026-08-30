#!/usr/bin/env python3
"""Shared overflow-sentinel v1 predicate and persistence helpers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import queue
import re
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
N = 3
K = 3
M = 10
DEFAULT_T_ABS = 80000
DEFAULT_W = 0.50
DEFAULT_CTX_WINDOW = 200000
# Placeholders pending calibration from the #218 drift-telemetry lane.
DEFAULT_N_DRIFT = 5
DEFAULT_THETA_DRIFT = 0.10
DRIFT_REFERENCE_RANK = {"none": 0, "derived": 1, "independent": 2}
HF_CACHE_SCHEMA_VERSION = 1
HF_NETWORK_TIMEOUT_S = 5
HF_NETWORK_MAX_BYTES = 1024 * 1024
HF_MODEL_ID_RE = re.compile(r"^(?:[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$")
HF_CTX_WINDOW_KEYS = ("max_position_embeddings", "n_positions", "max_seq_len", "model_max_length")

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


class _JsonObjectPairs(list):
    """Distinguish a decoded JSON object from an ordinary JSON array."""


def parse_model_aliases(raw: Optional[str]) -> Dict[str, str]:
    """Parse and normalize the optional single-step model alias map."""
    if raw is None or not str(raw).strip():
        return {}
    try:
        payload = json.loads(raw, object_pairs_hook=_JsonObjectPairs)
    except (TypeError, ValueError) as exc:
        raise ValueError("model aliases must be valid JSON") from exc
    if not isinstance(payload, _JsonObjectPairs):
        raise ValueError("model aliases must be a JSON object")
    aliases: Dict[str, str] = {}
    for alias, canonical in payload:
        if not isinstance(alias, str) or not isinstance(canonical, str):
            raise ValueError("model alias keys and values must be strings")
        normalized_alias = alias.strip().lower()
        normalized_canonical = canonical.strip().lower()
        if not normalized_alias or not normalized_canonical:
            raise ValueError("model alias keys and values must be non-empty")
        if normalized_alias in aliases:
            raise ValueError(f"duplicate model alias after normalization: {normalized_alias}")
        aliases[normalized_alias] = normalized_canonical
    return aliases


def parse_model_thresholds(
    raw: Optional[str],
) -> Tuple[Dict[str, Dict[str, Any]], int, float]:
    """Parse the optional per-model threshold surface.

    Model ids and glob patterns are canonicalized by trimming whitespace and
    lowercasing, exactly like runtime model identities. Only ``*`` is treated
    as glob syntax.
    """
    if raw is None or not str(raw).strip():
        return {}, DEFAULT_N_DRIFT, DEFAULT_THETA_DRIFT

    def reject_non_json_constant(value: str) -> None:
        raise ValueError(f"non-standard JSON numeric constant: {value}")

    try:
        payload = json.loads(
            raw,
            object_pairs_hook=_JsonObjectPairs,
            parse_constant=reject_non_json_constant,
        )
    except (TypeError, ValueError) as exc:
        raise ValueError("model thresholds must be valid JSON") from exc
    if not isinstance(payload, _JsonObjectPairs):
        raise ValueError("model thresholds must be a JSON object")

    top_level: Dict[str, Any] = {}
    allowed_top_level = {"models", "N_drift", "theta_drift"}
    for key, value in payload:
        if key in top_level:
            raise ValueError(f"duplicate model-thresholds top-level key: {key}")
        if key not in allowed_top_level:
            raise ValueError(f"unknown model-thresholds top-level key: {key}")
        top_level[key] = value

    raw_models = top_level.get("models", _JsonObjectPairs())
    if not isinstance(raw_models, _JsonObjectPairs):
        raise ValueError("model thresholds models must be a JSON object")

    table: Dict[str, Dict[str, Any]] = {}
    raw_keys = set()
    pattern_prefixes: Dict[str, str] = {}
    for raw_key, raw_entry in raw_models:
        normalized_key = raw_key.strip().lower()
        is_pattern = "*" in normalized_key
        if raw_key in raw_keys:
            if is_pattern:
                raise ValueError(f"duplicate model threshold pattern: {normalized_key}")
            raise ValueError(f"duplicate JSON model threshold key: {raw_key}")
        raw_keys.add(raw_key)
        if not normalized_key:
            raise ValueError("model threshold pattern must be non-empty")
        if any(marker in normalized_key for marker in ("?", "[", "{")):
            raise ValueError(
                f"model threshold pattern contains unsupported glob syntax: {normalized_key}"
            )
        if normalized_key in table:
            if is_pattern:
                raise ValueError(f"duplicate model threshold pattern: {normalized_key}")
            raise ValueError(
                f"duplicate exact model threshold key after canonicalization: {normalized_key}"
            )
        if is_pattern:
            literal_prefix = normalized_key.split("*", 1)[0]
            previous_pattern = pattern_prefixes.get(literal_prefix)
            if previous_pattern is not None:
                raise ValueError(
                    "same-specificity model threshold patterns share literal prefix "
                    f"{literal_prefix!r}: {previous_pattern}, {normalized_key}"
                )
            pattern_prefixes[literal_prefix] = normalized_key
        if not isinstance(raw_entry, _JsonObjectPairs):
            raise ValueError(f"model threshold entry must be a JSON object: {normalized_key}")
        if not raw_entry:
            raise ValueError(
                f"model threshold entry must contain T_abs or w: {normalized_key}"
            )

        entry: Dict[str, Any] = {}
        for entry_key, value in raw_entry:
            if entry_key in entry:
                raise ValueError(
                    f"duplicate model threshold entry key for {normalized_key}: {entry_key}"
                )
            if entry_key not in {"T_abs", "w"}:
                raise ValueError(
                    f"unknown model threshold entry key for {normalized_key}: {entry_key}"
                )
            if entry_key == "T_abs":
                if not isinstance(value, int) or isinstance(value, bool) or value < 1:
                    raise ValueError(
                        f"model threshold T_abs must be an integer >= 1: {normalized_key}"
                    )
                entry[entry_key] = value
            else:
                if (
                    not isinstance(value, (int, float))
                    or isinstance(value, bool)
                    or not 0 < value < 1
                ):
                    raise ValueError(
                        f"model threshold w must be greater than 0 and less than 1: {normalized_key}"
                    )
                entry[entry_key] = float(value)
        table[normalized_key] = entry

    n_drift = top_level.get("N_drift", DEFAULT_N_DRIFT)
    if not isinstance(n_drift, int) or isinstance(n_drift, bool) or n_drift < 1:
        raise ValueError("model thresholds N_drift must be an integer >= 1")
    theta_drift = top_level.get("theta_drift", DEFAULT_THETA_DRIFT)
    if not isinstance(theta_drift, float) or theta_drift <= 0:
        raise ValueError("model thresholds theta_drift must be a float greater than 0")
    return table, n_drift, theta_drift


def match_threshold_entry(
    identity: Any, table: Optional[Mapping[str, Mapping[str, Any]]]
) -> Optional[Mapping[str, Any]]:
    """Return the exact or longest-literal-prefix threshold entry."""
    normalized_identity = canonical_model(identity)
    if normalized_identity is None or not table:
        return None
    exact = table.get(normalized_identity)
    if exact is not None and "*" not in normalized_identity:
        return exact

    matches = []
    for pattern, entry in table.items():
        if "*" not in pattern:
            continue
        expression = "".join(".*" if char == "*" else re.escape(char) for char in pattern)
        if re.fullmatch(expression, normalized_identity):
            matches.append((len(pattern.split("*", 1)[0]), pattern, entry))
    if not matches:
        return None
    longest = max(item[0] for item in matches)
    winners = [item for item in matches if item[0] == longest]
    if len(winners) != 1:
        raise ValueError("same-specificity model threshold patterns matched at runtime")
    return winners[0][2]


def canonical_model(model: Any, aliases: Optional[Mapping[str, str]] = None) -> Optional[str]:
    """Return the lowercase/trimmed model identity with one alias lookup."""
    if not isinstance(model, str):
        return None
    normalized = model.strip().lower()
    if not normalized:
        return None
    return (aliases or {}).get(normalized, normalized)


def compare_regime_identity(
    previous: Optional[Mapping[str, str]],
    model: Any,
    runtime: Any,
    aliases: Optional[Mapping[str, str]] = None,
) -> Tuple[bool, Optional[Dict[str, str]]]:
    """Compare complete turn identities, preserving the last complete identity."""
    model_identity = canonical_model(model, aliases)
    if model_identity is None or not isinstance(runtime, str) or not runtime:
        return False, dict(previous) if previous is not None else None
    current = {"model": model_identity, "runtime": runtime}
    changed = previous is not None and (
        current["model"] != previous.get("model") or current["runtime"] != previous.get("runtime")
    )
    return changed, current


def reset_regime_state() -> Dict[str, Any]:
    """Return cleared per-regime predicate state, including the #218 seams."""
    return {
        "series": [],
        "last_injected": None,
        "last_fire_ma": {},
        "drift_accumulator": None,
        "cadence_counter": 0,
    }


def new_drift_accumulator() -> Dict[str, Any]:
    """Return the empty core state for one model/runtime regime epoch."""
    return {
        "reported_cum_tokens": 0,
        "reference_cum_tokens": 0,
        "cadence_counter": 0,
        "bias_active": False,
        "schema_signature": None,
    }


def weakest_drift_reference(values: Sequence[str]) -> str:
    """Return the weakest declared capability using none < derived < independent."""
    valid = [value for value in values if value in DRIFT_REFERENCE_RANK]
    if not valid:
        return "none"
    return min(valid, key=lambda value: DRIFT_REFERENCE_RANK[value])


def raw_usage_signature(raw_usage: Any) -> Optional[List[str]]:
    """Return the sorted field-set signature for a raw usage object."""
    if not isinstance(raw_usage, dict):
        return None
    return sorted(str(key) for key in raw_usage)


def _usage_token(value: Any) -> Optional[int]:
    if value is None or isinstance(value, bool):
        return None
    try:
        token_count = int(value or 0)
    except (TypeError, ValueError):
        return None
    return max(0, token_count)


def normalize_raw_usage(raw_usage: Any, runtime: Any) -> Optional[int]:
    """Replay the runtime normalization rule over a ledger-held raw usage object."""
    if runtime != "claude-code" or not isinstance(raw_usage, dict):
        return None
    if raw_usage.get("input_tokens") is None:
        return None
    parts = (
        _usage_token(raw_usage.get("input_tokens")),
        _usage_token(raw_usage.get("cache_read_input_tokens", 0)),
        _usage_token(raw_usage.get("cache_creation_input_tokens", 0)),
    )
    if any(part is None for part in parts):
        return None
    return sum(int(part) for part in parts if part is not None)


def _reported_injected_tokens(turn: Mapping[str, Any]) -> Optional[int]:
    parts = tuple(
        _usage_token(turn.get(field))
        for field in ("input_tokens", "cache_read_tokens", "cache_creation_tokens")
    )
    if any(part is None for part in parts):
        return None
    return sum(int(part) for part in parts if part is not None)


def _drift_event(
    turn: Mapping[str, Any],
    accumulator: Mapping[str, Any],
    drift_kind: str,
    drift_reference: str,
    n_drift: int,
    theta_drift: float,
) -> Dict[str, Any]:
    reported = int(accumulator["reported_cum_tokens"])
    reference = int(accumulator["reference_cum_tokens"])
    signed_bias = reported - reference
    event = {
        "event": "tap_drift",
        "schema_version": turn.get("schema_version", SCHEMA_VERSION),
        "ts": turn.get("ts"),
        "task_id": turn.get("task_id"),
        "turn_idx": turn.get("turn_idx"),
        "drift_kind": drift_kind,
        "drift_reference": drift_reference,
        "reported_cum_tokens": reported,
        "reference_cum_tokens": reference,
        "signed_bias": signed_bias,
        "bias_ratio": signed_bias / float(max(reference, 1)),
        "threshold": theta_drift,
        "cadence_turns": n_drift,
        "model": turn.get("model"),
        "runtime": turn.get("runtime"),
    }
    if "attempt" in turn:
        event["attempt"] = turn.get("attempt")
    return event


def evaluate_drift_turn(
    accumulator: Dict[str, Any],
    turn: Mapping[str, Any],
    drift_reference: str,
    n_drift: int,
    theta_drift: float,
) -> List[Dict[str, Any]]:
    """Evaluate one ledger turn and mutate the regime-scoped drift state.

    Missing observations advance cadence but are excluded from both cumulative
    sums. Derived references are recomputed from ``raw_usage`` in core. Future
    independent adapters may persist ``reference_injected_tokens`` on the turn.
    """
    if drift_reference not in DRIFT_REFERENCE_RANK:
        raise ValueError(f"unknown drift reference capability: {drift_reference}")
    if not isinstance(n_drift, int) or isinstance(n_drift, bool) or n_drift < 1:
        raise ValueError("N_drift must be an integer >= 1")
    if not isinstance(theta_drift, (int, float)) or isinstance(theta_drift, bool):
        raise ValueError("theta_drift must be numeric")

    accumulator["cadence_counter"] = int(accumulator.get("cadence_counter", 0)) + 1
    if drift_reference == "none":
        return []

    events: List[Dict[str, Any]] = []
    raw_usage = turn.get("raw_usage")
    signature = raw_usage_signature(raw_usage)
    previous_signature = accumulator.get("schema_signature")
    schema_changed = (
        signature is not None
        and previous_signature is not None
        and signature != previous_signature
    )
    if signature is not None:
        accumulator["schema_signature"] = signature

    reported = _reported_injected_tokens(turn)
    if drift_reference == "derived":
        reference = normalize_raw_usage(raw_usage, turn.get("runtime"))
    else:
        reference = _usage_token(turn.get("reference_injected_tokens"))
    observation_exists = reported is not None and reference is not None
    if observation_exists:
        accumulator["reported_cum_tokens"] = int(
            accumulator.get("reported_cum_tokens", 0)
        ) + int(reported)
        accumulator["reference_cum_tokens"] = int(
            accumulator.get("reference_cum_tokens", 0)
        ) + int(reference)

    if schema_changed:
        events.append(
            _drift_event(
                turn,
                accumulator,
                "schema-change",
                drift_reference,
                n_drift,
                float(theta_drift),
            )
        )

    cadence = int(accumulator["cadence_counter"])
    if cadence % n_drift != 0 or not observation_exists:
        return events

    reported_cum = int(accumulator["reported_cum_tokens"])
    reference_cum = int(accumulator["reference_cum_tokens"])
    bias_ratio = (reported_cum - reference_cum) / float(max(reference_cum, 1))
    in_drift = abs(bias_ratio) > float(theta_drift)
    was_in_drift = bool(accumulator.get("bias_active"))
    if in_drift and not was_in_drift:
        events.append(
            _drift_event(
                turn,
                accumulator,
                "bias",
                drift_reference,
                n_drift,
                float(theta_drift),
            )
        )
    accumulator["bias_active"] = in_drift
    return events


def resolve_thresholds(
    explicit_t_abs: Optional[int],
    explicit_w: Optional[float],
    model_identity: Any = None,
    table: Optional[Mapping[str, Mapping[str, Any]]] = None,
) -> Tuple[int, float, Dict[str, str]]:
    """Resolve config, per-model, then product-default thresholds per key."""
    entry = match_threshold_entry(model_identity, table)
    table_t_abs = entry.get("T_abs") if entry is not None else None
    table_w = entry.get("w") if entry is not None else None
    t_abs = (
        explicit_t_abs
        if explicit_t_abs is not None
        else table_t_abs if table_t_abs is not None else DEFAULT_T_ABS
    )
    w = explicit_w if explicit_w is not None else table_w if table_w is not None else DEFAULT_W
    if not isinstance(t_abs, int) or isinstance(t_abs, bool) or t_abs < 1:
        raise ValueError("T_abs must be an integer >= 1")
    if not isinstance(w, (int, float)) or isinstance(w, bool) or not 0 < w < 1:
        raise ValueError("w must be greater than 0 and less than 1")
    sources = {
        "T_abs": (
            "config"
            if explicit_t_abs is not None
            else "per-model" if table_t_abs is not None else "default"
        ),
        "w": (
            "config"
            if explicit_w is not None
            else "per-model" if table_w is not None else "default"
        ),
    }
    return t_abs, w, sources


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


def atomic_write_private_json(path: Path, payload: Mapping[str, Any]) -> None:
    """Write private JSON data atomically with a 0600 file mode."""
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        os.fchmod(fd, 0o600)
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


def warn_ctx_window_fallback(message: str) -> None:
    print(f"warning: overflow sentinel HF fallback: {message}", file=os.sys.stderr)


def load_state(path: Path) -> Dict[str, Any]:
    default = {
        "schema_version": SCHEMA_VERSION,
        "last_fire_ma": {},
        "last_run_injected_ma": None,
        "regime_identity": None,
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
    regime_identity = payload.get("regime_identity")
    if not isinstance(regime_identity, dict):
        regime_identity = None
    else:
        identity_model = regime_identity.get("model")
        identity_runtime = regime_identity.get("runtime")
        if (
            not isinstance(identity_model, str)
            or not identity_model
            or not isinstance(identity_runtime, str)
            or not identity_runtime
        ):
            regime_identity = None
        else:
            regime_identity = {"model": identity_model, "runtime": identity_runtime}
    return {
        "schema_version": SCHEMA_VERSION,
        "last_fire_ma": clean_fire,
        "last_run_injected_ma": last_run,
        "regime_identity": regime_identity,
    }


def save_state(
    path: Path,
    last_fire_ma: Mapping[str, float],
    last_run_injected_ma: Optional[float],
    regime_identity: Optional[Mapping[str, str]] = None,
) -> None:
    atomic_write_json(
        path,
        {
            "schema_version": SCHEMA_VERSION,
            "last_fire_ma": dict(last_fire_ma),
            "last_run_injected_ma": last_run_injected_ma,
            "regime_identity": dict(regime_identity) if regime_identity is not None else None,
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
    raise ValueError("threshold_hit requested without a level crossing")


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
        if level_fire:
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
    """Apply regime-scoped per-axis hysteresis; exact +10% re-arms (>=)."""
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


def _window_from_payload(payload: Any, source_name: str) -> int:
    if not isinstance(payload, dict):
        raise ValueError(f"{source_name} must contain a JSON object")
    for key in HF_CTX_WINDOW_KEYS:
        value = payload.get(key)
        if isinstance(value, int) and not isinstance(value, bool) and value >= 1:
            return value
    raise ValueError(f"{source_name} has no positive supported context-window field")


def _hf_window(config_path: Path) -> int:
    candidate = config_path / "config.json" if config_path.is_dir() else config_path
    if not candidate.is_file() or candidate.is_symlink():
        raise ValueError("HF config must be a non-symlink regular config.json file")
    try:
        with candidate.open(encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ValueError("HF config is not readable JSON") from exc
    return _window_from_payload(payload, "HF config")


def validate_hf_model_id(model_id: str) -> str:
    normalized = str(model_id or "").strip()
    if not normalized:
        raise ValueError("HF model id must be non-empty")
    if HF_MODEL_ID_RE.fullmatch(normalized) is None:
        raise ValueError("HF model id must be a plain repo id such as namespace/name")
    return normalized


def _validate_non_symlink_leaf(path: Path, label: str) -> None:
    if path.is_symlink():
        raise ValueError(f"{label} must not be a symlink: {path}")


def prepare_hf_cache_dir(cache_dir: str) -> Path:
    raw_cache_dir = str(cache_dir or "").strip()
    if not raw_cache_dir:
        raise ValueError("HF cache dir must be non-empty")
    candidate = Path(raw_cache_dir)
    _validate_non_symlink_leaf(candidate, "HF cache dir")
    try:
        candidate.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ValueError(f"HF cache dir is not writable: {candidate}") from exc
    if candidate.is_symlink() or not candidate.is_dir():
        raise ValueError(f"HF cache dir must be a non-symlink directory: {candidate}")
    try:
        os.chmod(candidate, 0o700)
    except OSError as exc:
        raise ValueError(f"HF cache dir mode cannot be set: {candidate}") from exc
    return candidate


def _hf_cache_file(cache_dir: Path, model_id: str) -> Path:
    digest = hashlib.sha256(model_id.encode("utf-8")).hexdigest()
    return cache_dir / f"{digest}.json"


def _read_hf_network_cache(cache_path: Path, model_id: str) -> int:
    if not cache_path.exists():
        raise ValueError("cache miss")
    if cache_path.is_symlink() or not cache_path.is_file():
        raise ValueError("cache entry must be a non-symlink regular file")
    _validate_non_symlink_leaf(cache_path.parent, "HF cache dir")
    if not cache_path.parent.is_dir():
        raise ValueError("cache dir must be a directory")
    if cache_path.parent.stat().st_mode & 0o077:
        raise ValueError("cache dir must be mode 0700")
    try:
        with cache_path.open("rb") as handle:
            raw_payload = handle.read(HF_NETWORK_MAX_BYTES + 1)
    except (OSError, ValueError, TypeError) as exc:
        raise ValueError("cache entry is not readable JSON") from exc
    if len(raw_payload) > HF_NETWORK_MAX_BYTES:
        raise ValueError("cache entry exceeds size limit")
    try:
        payload = json.loads(raw_payload)
    except (ValueError, TypeError) as exc:
        raise ValueError("cache entry is not readable JSON") from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != HF_CACHE_SCHEMA_VERSION:
        raise ValueError("cache entry schema mismatch")
    if payload.get("model_id") != model_id:
        raise ValueError("cache entry model mismatch")
    return _window_from_payload(payload, "HF network cache")


def _read_cached_hf_window(cache_path: Path, model_id: str) -> Optional[int]:
    try:
        return _read_hf_network_cache(cache_path, model_id)
    except Exception as exc:
        if str(exc) != "cache miss":
            raise
        return None


def _write_hf_network_cache(cache_path: Path, model_id: str, ctx_window: int) -> None:
    payload = {
        "schema_version": HF_CACHE_SCHEMA_VERSION,
        "model_id": model_id,
        "fetched_at": time.time(),
        "max_position_embeddings": ctx_window,
    }
    atomic_write_private_json(cache_path, payload)


def _hf_network_url(model_id: str) -> str:
    segments = [urllib.parse.quote(part, safe="._-") for part in model_id.split("/")]
    return "https://huggingface.co/{}/resolve/main/config.json".format("/".join(segments))


def _fetch_hf_window(model_id: str) -> int:
    request = urllib.request.Request(
        _hf_network_url(model_id),
        headers={"Accept": "application/json", "User-Agent": "caty-overflow-sentinel/1"},
    )
    with urllib.request.urlopen(request, timeout=HF_NETWORK_TIMEOUT_S) as response:
        raw_payload = response.read(HF_NETWORK_MAX_BYTES + 1)
    if len(raw_payload) > HF_NETWORK_MAX_BYTES:
        raise ValueError("HF network config exceeds size limit")
    payload = json.loads(raw_payload)
    return _window_from_payload(payload, "HF network config")


def _fetch_hf_window_with_deadline(model_id: str, fetcher: Any, timeout_s: float) -> int:
    result_queue: "queue.Queue[Tuple[bool, Any]]" = queue.Queue(maxsize=1)

    def run_fetch() -> None:
        try:
            result_queue.put((True, fetcher(model_id)))
        except Exception as exc:
            result_queue.put((False, exc))

    thread = threading.Thread(target=run_fetch, daemon=True)
    thread.start()
    try:
        ok, payload = result_queue.get(timeout=timeout_s)
    except queue.Empty as exc:
        raise TimeoutError("HF network fetch exceeded hard timeout") from exc
    if ok:
        return payload
    raise payload


def _resolve_hf_network_ctx_window(
    hf_model_id: str,
    hf_cache_dir: str,
    fetcher: Any = None,
    fetch_timeout_s: float = HF_NETWORK_TIMEOUT_S,
) -> Optional[Tuple[int, str]]:
    try:
        try:
            model_id = validate_hf_model_id(hf_model_id)
            cache_dir = prepare_hf_cache_dir(hf_cache_dir)
            cache_path = _hf_cache_file(cache_dir, model_id)
        except Exception as exc:
            warn_ctx_window_fallback(str(exc) or exc.__class__.__name__)
            return None
        try:
            cached_window = _read_cached_hf_window(cache_path, model_id)
        except Exception as exc:
            warn_ctx_window_fallback(str(exc) or exc.__class__.__name__)
            cached_window = None
        if cached_window is not None:
            return cached_window, "hf-network-cached"
        fetch = _fetch_hf_window if fetcher is None else fetcher
        try:
            ctx_window = _fetch_hf_window_with_deadline(model_id, fetch, fetch_timeout_s)
            _write_hf_network_cache(cache_path, model_id, ctx_window)
            cached_window = _read_hf_network_cache(cache_path, model_id)
        except Exception as exc:
            warn_ctx_window_fallback(str(exc) or exc.__class__.__name__)
            return None
        return cached_window, "hf-network-cached"
    except Exception as exc:
        warn_ctx_window_fallback(str(exc) or exc.__class__.__name__)
        return None


def resolve_ctx_window(
    configured: Optional[int],
    hf_config: Optional[str],
    model: str,
    hf_network: bool = False,
    hf_cache_dir: Optional[str] = None,
    hf_fetcher: Any = None,
    hf_fetch_timeout_s: float = HF_NETWORK_TIMEOUT_S,
) -> Tuple[int, str]:
    if configured is not None:
        if configured < 1:
            raise ValueError("configured context window must be positive")
        return configured, "config"
    if hf_config:
        return _hf_window(Path(hf_config)), "hf-config"
    if hf_network:
        network_window = _resolve_hf_network_ctx_window(
            model,
            hf_cache_dir or "",
            fetcher=hf_fetcher,
            fetch_timeout_s=hf_fetch_timeout_s,
        )
        if network_window is not None:
            return network_window
    normalized = model.lower().split("/")[-1]
    if normalized == "claude-unknown":
        return DEFAULT_CTX_WINDOW, "default"
    for prefix, window in CTX_WINDOW_CATALOG:
        if normalized.startswith(prefix):
            return window, "catalog"
    return DEFAULT_CTX_WINDOW, "default"


def ttfb_floor_seconds(previous_injected_ma: Optional[float], model: str) -> int:
    normalized = model.lower().split("/")[-1]
    if normalized == "claude-unknown":
        return 240
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
    validate_aliases = sub.add_parser("validate-aliases")
    validate_aliases.add_argument("aliases")
    validate_thresholds = sub.add_parser("validate-thresholds")
    validate_thresholds.add_argument("thresholds")
    prepare_hf_cache = sub.add_parser("prepare-hf-cache")
    prepare_hf_cache.add_argument("path")
    args = parser.parse_args(argv)
    if args.command == "eval-series":
        values = [int(part) for part in args.series.split(",") if part]
        print(json.dumps(evaluate_series(values, args.t_abs, args.w, args.ctx), sort_keys=True))
        return 0
    if args.command == "prepare-hf-cache":
        try:
            print(prepare_hf_cache_dir(args.path))
        except ValueError as exc:
            print(str(exc), file=os.sys.stderr)
            return 2
        return 0
    if args.command == "validate-aliases":
        try:
            print(json.dumps(parse_model_aliases(args.aliases), sort_keys=True))
        except ValueError as exc:
            print(str(exc), file=os.sys.stderr)
            return 2
        return 0
    if args.command == "validate-thresholds":
        try:
            table, n_drift, theta_drift = parse_model_thresholds(args.thresholds)
            print(
                json.dumps(
                    {
                        "models": table,
                        "N_drift": n_drift,
                        "theta_drift": theta_drift,
                    },
                    sort_keys=True,
                )
            )
        except ValueError as exc:
            print(str(exc), file=os.sys.stderr)
            return 2
        return 0
    try:
        print(_hf_window(Path(args.path)))
    except ValueError as exc:
        print(str(exc), file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
