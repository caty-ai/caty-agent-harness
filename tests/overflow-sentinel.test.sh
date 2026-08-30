#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/caty-overflow-sentinel-core.$$
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT"
passes=0
failures=0

pass() { printf 'ok - %s\n' "$1"; passes=$((passes + 1)); }
fail_case() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

run_python_case() {
  local name=$1
  local body=$2
  if ROOT="$ROOT" TMP_ROOT="$TMP_ROOT" CASE_BODY="$body" python3 -B - <<'PY'
import os
import sys
sys.path.insert(0, os.path.join(os.environ["ROOT"], "scripts"))
from lib_overflow_sentinel import *
exec(os.environ["CASE_BODY"], globals(), globals())
PY
  then
    pass "$name"
  else
    fail_case "$name"
  fi
}

run_python_case "level comparator is strict and min selects absolute threshold" '
at = evaluate_series([80000], t_abs=80000, w=.9, ctx=200000)["turns"][0]
above = evaluate_series([80001], t_abs=80000, w=.9, ctx=200000)["turns"][0]
assert at["axis"] is None and "threshold_hit" not in at
assert above["axis"] == "level" and above["threshold_hit"] == "abs"
'

run_python_case "min selects ratio threshold" '
at = evaluate_series([50000], t_abs=80000, w=.5, ctx=100000)["turns"][0]
above = evaluate_series([50001], t_abs=80000, w=.5, ctx=100000)["turns"][0]
assert at["axis"] is None and above["axis"] == "level"
assert above["threshold_hit"] == "ratio"
'

run_python_case "partial mean uses all available turns 1 and 2" '
turns = evaluate_series([10, 20], t_abs=1000, w=.9, ctx=10000)["turns"]
assert [turn["injected_ma"] for turn in turns] == [10.0, 15.0]
'

run_python_case "slope is undefined before turn 4 and slope fire works" '
turns = evaluate_series([10000, 20000, 30000, 40000], t_abs=90000, w=.9, ctx=50000)["turns"]
assert all(turn["slope"] is None for turn in turns[:3])
assert turns[3]["axis"] == "slope" and turns[3]["projection_turns"] <= 10
assert "threshold_hit" not in turns[3]
'

run_python_case "slope uses the moving-average series rather than raw injected values" '
turn = evaluate_series([10000, 10000, 10000, 62000], t_abs=80000, w=.5, ctx=200000)["turns"][-1]
raw_slope = (62000 - 10000) / 3.0
raw_projection = (200000 - (82000 / 3.0)) / raw_slope
assert raw_projection <= M
assert turn["injected_ma"] == 82000 / 3.0
assert turn["projection_turns"] > M and turn["axis"] is None
'

run_python_case "slope projection fires at exact M and not just above M" '
at = evaluate_series([100, 400, 400, 400], t_abs=5000, w=.99, ctx=1400)["turns"][-1]
above = evaluate_series([100, 400, 400, 399], t_abs=5000, w=.99, ctx=1400)["turns"][-1]
assert at["projection_turns"] == M and at["axis"] == "slope"
assert above["projection_turns"] > M and above["axis"] is None
'

run_python_case "axis both is emitted when level and slope fire" '
turn = evaluate_series([10000, 20000, 30000, 100000], t_abs=30000, w=.9, ctx=100000)["turns"][-1]
assert turn["axis"] == "both"
'

run_python_case "per-axis hysteresis re-arms at exact plus ten percent" '
last = {"level": 100000.0, "slope": 90000.0}
assert eligible_fire_axes("both", 109999.0, 100000, last) == ["slope"]
assert eligible_fire_axes("both", 110000.0, 100000, last) == ["level", "slope"]
'

run_python_case "compaction reset boundary is strict below sixty percent" '
assert not compaction_suspected(100, 61)
assert not compaction_suspected(100, 60)
assert compaction_suspected(100, 59)
'

run_python_case "model aliases normalize keys and values and remain single-step" '
aliases = parse_model_aliases("{\" MODEL-A \":\"Family-A\",\"family-a\":\"family-b\"}")
assert aliases == {"model-a": "family-a", "family-a": "family-b"}
assert canonical_model(" model-A ", aliases) == "family-a"
assert canonical_model(" FAMILY-A ", aliases) == "family-b"
'

run_python_case "regime comparison ignores incomplete identities and preserves the last comparable turn" '
changed, identity = compare_regime_identity(None, " Model-A ", "claude-code", {})
assert not changed and identity == {"model": "model-a", "runtime": "claude-code"}
changed, missing = compare_regime_identity(identity, None, "claude-code", {})
assert not changed and missing == identity
changed, next_identity = compare_regime_identity(missing, "MODEL-B", "claude-code", {})
assert changed and next_identity == {"model": "model-b", "runtime": "claude-code"}
'

run_python_case "regime reset clears predicate hysteresis and exposes the future drift seams" '
cleared = reset_regime_state()
assert cleared == {"series": [], "last_injected": None, "last_fire_ma": {},
                   "drift_accumulator": None, "cadence_counter": 0}
'

run_python_case "threshold resolution preserves per-key explicit/default provenance" '
assert resolve_thresholds(None, None) == (80000, 0.50, {"T_abs": "default", "w": "default"})
assert resolve_thresholds(90000, None) == (90000, 0.50, {"T_abs": "config", "w": "default"})
assert resolve_thresholds(None, 0.75) == (80000, 0.75, {"T_abs": "default", "w": "config"})
try:
    resolve_thresholds(1.5, 0.5)
except ValueError:
    pass
else:
    raise AssertionError("non-integer T_abs accepted")
'

run_python_case "context-window ladder resolves all four sources offline" '
import json
from pathlib import Path
root = Path(os.environ["TMP_ROOT"])
hf = root / "hf-config.json"
hf.write_text(json.dumps({"max_position_embeddings": 131072}), encoding="utf-8")
assert resolve_ctx_window(64000, str(hf), "claude-x") == (64000, "config")
assert resolve_ctx_window(None, str(hf), "claude-x") == (131072, "hf-config")
assert resolve_ctx_window(None, None, "claude-sonnet-4-5") == (200000, "catalog")
assert resolve_ctx_window(None, None, "claude-unknown") == (200000, "default")
assert resolve_ctx_window(None, None, "unlisted") == (200000, "default")
'

run_python_case "TTFB tiers use strict token boundaries and conservative unknowns" '
assert ttfb_floor_seconds(None, "claude-sonnet-4-5") == 240
assert ttfb_floor_seconds(50000, "claude-sonnet-4-5") == 90
assert ttfb_floor_seconds(50001, "claude-sonnet-4-5") == 150
assert ttfb_floor_seconds(100000, "claude-sonnet-4-5") == 150
assert ttfb_floor_seconds(100001, "claude-sonnet-4-5") == 240
assert ttfb_floor_seconds(100, "unknown-model") == 240
assert ttfb_floor_seconds(100, "claude-unknown") == 240
assert ttfb_floor_seconds(100, "glm-5.3") == 300
'

run_python_case "outcome vocabulary maps completion overflow and abort" '
assert outcome_from_result(0, {"step_complete": True}) == "step_completed"
assert outcome_from_result(1, {"step_complete": True}) == "aborted"
assert outcome_from_result(0, {"window_error": True}) == "overflowed"
assert outcome_from_result(124, {"error_class": "timeout"}) == "aborted"
'

run_python_case "state load and atomic write preserve task-scoped hysteresis" '
from pathlib import Path
path = Path(os.environ["TMP_ROOT"]) / "state" / "overflow-sentinel-state.json"
save_state(path, {"level": 90000.0}, 85000.0, {"model": "model-a", "runtime": "claude-code"})
state = load_state(path)
assert state["last_fire_ma"] == {"level": 90000.0}
assert state["last_run_injected_ma"] == 85000.0
assert state["regime_identity"] == {"model": "model-a", "runtime": "claude-code"}
assert eligible_fire_axes("level", 99999.0, 100000, state["last_fire_ma"]) == []
assert eligible_fire_axes("level", 100000.0, 100000, state["last_fire_ma"]) == ["level"]
assert list(path.parent.glob("overflow-sentinel-state.json.*")) == []
'

run_python_case "non-firing turn omits threshold_hit" '
turn = evaluate_series([1], t_abs=100, w=.5, ctx=1000)["turns"][0]
assert turn["axis"] is None and "threshold_hit" not in turn
'

run_alias_cli_rejection() {
  local name=$1
  local aliases=$2
  local stderr_path="$TMP_ROOT/aliases.err"
  set +e
  python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-aliases "$aliases" \
    >"$TMP_ROOT/aliases.out" 2>"$stderr_path"
  local rc=$?
  set -e
  if [[ "$rc" -eq 2 && -s "$stderr_path" ]]; then
    pass "$name"
  else
    fail_case "$name"
  fi
}

run_alias_cli_rejection "validate-aliases rejects non-object JSON" '["model-a"]'
run_alias_cli_rejection "validate-aliases rejects non-string values" '{"model-a":1}'
run_alias_cli_rejection "validate-aliases rejects duplicate normalized keys" '{" Model-A ":"one","model-a":"two"}'

if (( failures )); then
  printf '%s overflow sentinel core test(s) failed; %s passed\n' "$failures" "$passes" >&2
  exit 1
fi
printf '%s overflow sentinel core tests passed\n' "$passes"
