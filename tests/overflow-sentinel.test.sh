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
state=new_drift_accumulator()
turn={"input_tokens":120,"cache_read_tokens":0,"cache_creation_tokens":0,
      "raw_usage":{"input_tokens":100},"runtime":"claude-code"}
assert evaluate_drift_turn(state,turn,"derived",3,.1)==[]
assert evaluate_drift_turn(state,turn,"derived",3,.1)==[]
fresh=new_drift_accumulator()
assert evaluate_drift_turn(fresh,turn,"derived",3,.1)==[]
assert fresh["cadence_counter"]==1
assert (fresh["reported_cum_tokens"],fresh["reference_cum_tokens"])==(120,100)
'

run_python_case "core reconciliation detects both bias directions and stamps reference capability" '
def turn(reported, raw, idx=1, reference=None):
    value={"schema_version":1,"ts":"2026-08-30T00:00:00Z","task_id":"t",
           "attempt":"001","turn_idx":idx,"input_tokens":reported,
           "cache_read_tokens":0,"cache_creation_tokens":0,"output_tokens":0,
           "raw_usage":raw,"model":"m","runtime":"claude-code"}
    if reference is not None: value["reference_injected_tokens"]=reference
    return value
high=evaluate_drift_turn(new_drift_accumulator(),turn(120,{"input_tokens":100}),"derived",1,.1)
low=evaluate_drift_turn(new_drift_accumulator(),turn(80,{"input_tokens":100}),"derived",1,.1)
independent=evaluate_drift_turn(
    new_drift_accumulator(),turn(120,{"input_tokens":100},reference=100),"independent",1,.1
)
assert [(x[0]["signed_bias"],x[0]["drift_reference"]) for x in (high,low,independent)] == [
    (20,"derived"),(-20,"derived"),(20,"independent")
]
assert all(x[0]["drift_kind"]=="bias" for x in (high,low,independent))
'

run_python_case "sub-threshold derived replay emits no drift and never claims independent PASS" '
state=new_drift_accumulator()
turn={"turn_idx":1,"input_tokens":105,"cache_read_tokens":0,"cache_creation_tokens":0,
      "raw_usage":{"input_tokens":100},"runtime":"claude-code"}
assert evaluate_drift_turn(state,turn,"derived",1,.1)==[]
assert state["reported_cum_tokens"]==105 and state["reference_cum_tokens"]==100
assert "independent" not in state and "verified" not in state
'

run_python_case "persistent bias is one episode and recovery re-arms a second episode" '
state=new_drift_accumulator(); events=[]
for idx,(reported,reference) in enumerate([(120,100),(120,100),(60,100),(120,100),(200,100)],1):
    turn={"turn_idx":idx,"input_tokens":reported,"cache_read_tokens":0,
          "cache_creation_tokens":0,"raw_usage":{"input_tokens":reference},
          "runtime":"claude-code"}
    events.extend(evaluate_drift_turn(state,turn,"derived",1,.1))
assert [event["turn_idx"] for event in events if event["drift_kind"]=="bias"]==[1,5]
'

run_python_case "regime reset starts a fresh bias epoch without cumulative bleed" '
def turn(idx, reported, reference):
    return {"turn_idx":idx,"input_tokens":reported,"cache_read_tokens":0,
            "cache_creation_tokens":0,"raw_usage":{"input_tokens":reference},
            "runtime":"claude-code"}
state=new_drift_accumulator(); events=[]
for idx in range(1,5):
    events.extend(evaluate_drift_turn(state,turn(idx,120,100),"derived",2,.1))
assert [(event["turn_idx"],abs(event["bias_ratio"])>event["threshold"])
        for event in events if event["drift_kind"]=="bias"]==[(2,True)]
assert state["bias_active"] is True
assert (state["reported_cum_tokens"],state["reference_cum_tokens"])==(480,400)
state=new_drift_accumulator()
assert state["bias_active"] is False
assert (state["reported_cum_tokens"],state["reference_cum_tokens"])==(0,0)
epoch_two=[]
for idx in range(1,3):
    epoch_two.extend(evaluate_drift_turn(state,turn(idx,105,100),"derived",2,.1))
events.extend(epoch_two)
assert epoch_two==[]
assert len([event for event in events if event["drift_kind"]=="bias"])==1
assert (state["reported_cum_tokens"],state["reference_cum_tokens"])==(210,200)
assert state["bias_active"] is False
'

run_python_case "zero reference uses the denominator guard and returns a sane ratio" '
state=new_drift_accumulator()
turn={"turn_idx":1,"input_tokens":1,"cache_read_tokens":0,"cache_creation_tokens":0,
      "raw_usage":{"input_tokens":0},"runtime":"claude-code"}
event=evaluate_drift_turn(state,turn,"derived",1,.1)[0]
assert event["reference_cum_tokens"]==0 and event["signed_bias"]==1
assert event["bias_ratio"]==1.0
'

run_python_case "missing references advance cadence and are pairwise excluded from both sums" '
state=new_drift_accumulator(); events=[]
turns=[
 {"input_tokens":120,"cache_read_tokens":0,"cache_creation_tokens":0,"raw_usage":{"input_tokens":100}},
 {"input_tokens":None,"cache_read_tokens":None,"cache_creation_tokens":None,"raw_usage":None},
 {"input_tokens":80,"cache_read_tokens":0,"cache_creation_tokens":0,"raw_usage":{"input_tokens":100}},
 {"input_tokens":100,"cache_read_tokens":0,"cache_creation_tokens":0,"raw_usage":{"input_tokens":100}},
]
for idx,turn in enumerate(turns,1):
    turn.update({"turn_idx":idx,"runtime":"claude-code"})
    events.extend(evaluate_drift_turn(state,turn,"derived",2,.1))
assert events==[] and state["cadence_counter"]==4
assert state["reported_cum_tokens"]==300 and state["reference_cum_tokens"]==300
'

run_python_case "cache-inclusive replay shares one normalization basis and detects tampering" '
raw={"input_tokens":100,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}
clean={"turn_idx":1,"input_tokens":100,"cache_read_tokens":20,"cache_creation_tokens":10,
       "raw_usage":raw,"runtime":"claude-code"}
assert evaluate_drift_turn(new_drift_accumulator(),clean,"derived",1,.1)==[]
tampered=dict(clean); tampered["cache_read_tokens"]=0
event=evaluate_drift_turn(new_drift_accumulator(),tampered,"derived",1,.1)[0]
assert event["reported_cum_tokens"]==110 and event["reference_cum_tokens"]==130
assert event["signed_bias"]==-20
'

run_python_case "weakest drift capability ordering is none then derived then independent" '
assert weakest_drift_reference(["independent","derived"])=="derived"
assert weakest_drift_reference(["independent","none","derived"])=="none"
assert weakest_drift_reference(["independent"])=="independent"
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

run_python_case "threshold resolution applies config then per-model then default per key" '
table, _, _ = parse_model_thresholds(
    "{\"models\":{\"model-a\":{\"T_abs\":70000,\"w\":0.4}}}"
)
assert resolve_thresholds(90000, None, "model-a", table) == (
    90000, 0.4, {"T_abs": "config", "w": "per-model"}
)
assert resolve_thresholds(None, 0.7, "model-a", table) == (
    70000, 0.7, {"T_abs": "per-model", "w": "config"}
)
'

run_python_case "partial per-model T_abs falls through to default w with per-key attribution" '
table, _, _ = parse_model_thresholds("{\"models\":{\"model-a\":{\"T_abs\":70000}}}")
assert resolve_thresholds(None, None, " MODEL-A ", table) == (
    70000, 0.50, {"T_abs": "per-model", "w": "default"}
)
'

run_python_case "partial per-model w falls through to default T_abs with per-key attribution" '
table, _, _ = parse_model_thresholds("{\"models\":{\"model-a\":{\"w\":0.25}}}")
assert resolve_thresholds(None, None, "model-a", table) == (
    80000, 0.25, {"T_abs": "default", "w": "per-model"}
)
'

run_python_case "exact threshold key beats a matching glob" '
table, _, _ = parse_model_thresholds(
    "{\"models\":{\"claude-sonnet-4-5\":{\"T_abs\":91000},"
    "\"claude-*\":{\"T_abs\":72000}}}"
)
assert match_threshold_entry("claude-sonnet-4-5", table)["T_abs"] == 91000
assert match_threshold_entry("claude-opus-x", table)["T_abs"] == 72000
'

run_python_case "longest literal prefix selects the most specific matching glob" '
table, _, _ = parse_model_thresholds(
    "{\"models\":{\"claude-*\":{\"w\":0.3},"
    "\"claude-sonnet-*\":{\"w\":0.4}}}"
)
assert match_threshold_entry("claude-sonnet-4-5", table)["w"] == 0.4
'

run_python_case "glob matching escapes regex metacharacters and no match uses defaults" '
table, _, _ = parse_model_thresholds(
    "{\"models\":{\"model.v1+*\":{\"T_abs\":1}}}"
)
assert match_threshold_entry("model.v1+x", table)["T_abs"] == 1
assert match_threshold_entry("modelXv11x", table) is None
assert resolve_thresholds(None, None, "unlisted", table) == (
    80000, 0.50, {"T_abs": "default", "w": "default"}
)
'

run_python_case "empty threshold surface exposes the placeholder drift defaults" '
assert parse_model_thresholds(None) == ({}, DEFAULT_N_DRIFT, DEFAULT_THETA_DRIFT)
assert parse_model_thresholds("") == ({}, 5, 0.10)
assert parse_model_thresholds("{}") == ({}, 5, 0.10)
table, n_drift, theta_drift = parse_model_thresholds(
    "{\"N_drift\":7,\"theta_drift\":0.2}"
)
assert table == {} and n_drift == 7 and theta_drift == 0.2
'

run_python_case "threshold parser rejects every frozen invalid shape with a precise message" '
cases = [
    ("[]", "model thresholds must be a JSON object"),
    ("{\"theta_drift\":NaN}", "model thresholds must be valid JSON"),
    ("{\"theta_drift\":Infinity}", "model thresholds must be valid JSON"),
    ("{\"theta_drift\":-Infinity}", "model thresholds must be valid JSON"),
    ("{\"extra\":1}", "unknown model-thresholds top-level key: extra"),
    ("{\"models\":{},\"models\":{}}", "duplicate model-thresholds top-level key"),
    ("{\"models\":{\"m\":{\"extra\":1}}}", "unknown model threshold entry key"),
    ("{\"models\":{\"m\":{\"T_abs\":0}}}", "T_abs must be an integer >= 1"),
    ("{\"models\":{\"m\":{\"T_abs\":true}}}", "T_abs must be an integer >= 1"),
    ("{\"models\":{\"m\":{\"T_abs\":1,\"T_abs\":2}}}",
     "duplicate model threshold entry key"),
    ("{\"models\":{\"m\":{\"w\":0}}}", "w must be greater than 0 and less than 1"),
    ("{\"models\":{\"m\":{\"w\":1}}}", "w must be greater than 0 and less than 1"),
    ("{\"models\":{\"m\":{\"w\":1.5}}}", "w must be greater than 0 and less than 1"),
    ("{\"models\":{\"bad?\":{\"w\":0.5}}}", "unsupported glob syntax"),
    ("{\"models\":{\"bad[\":{\"w\":0.5}}}", "unsupported glob syntax"),
    ("{\"models\":{\"bad{\":{\"w\":0.5}}}", "unsupported glob syntax"),
    ("{\"models\":{\"model-a\":{\"T_abs\":1},\"model-a\":{\"w\":0.5}}}",
     "duplicate JSON model threshold key"),
    ("{\"models\":{\" Model-A \":{\"T_abs\":1},\"model-a\":{\"w\":0.5}}}",
     "duplicate exact model threshold key after canonicalization"),
    ("{\"models\":{\"claude-*\":{\"T_abs\":1},\"claude-*\":{\"w\":0.5}}}",
     "duplicate model threshold pattern"),
    ("{\"models\":{\"claude-*a\":{\"T_abs\":1},\"claude-*b\":{\"w\":0.5}}}",
     "same-specificity model threshold patterns share literal prefix"),
    ("{\"models\":{\"\":{\"T_abs\":1}}}", "pattern must be non-empty"),
    ("{\"models\":{\"m\":{}}}", "entry must contain T_abs or w"),
    ("{\"models\":{\"m\":1}}", "entry must be a JSON object"),
    ("{\"models\":[]}", "models must be a JSON object"),
    ("{\"N_drift\":0}", "N_drift must be an integer >= 1"),
    ("{\"N_drift\":true}", "N_drift must be an integer >= 1"),
    ("{\"theta_drift\":0}", "theta_drift must be a float greater than 0"),
    ("{\"theta_drift\":1}", "theta_drift must be a float greater than 0"),
    ("{\"theta_drift\":true}", "theta_drift must be a float greater than 0"),
    ("{\"theta_drift\":\"x\"}", "theta_drift must be a float greater than 0"),
]
for raw, expected in cases:
    try:
        parse_model_thresholds(raw)
    except ValueError as exc:
        assert expected in str(exc), (raw, str(exc))
    else:
        raise AssertionError("invalid threshold surface accepted: " + raw)
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

set +e
python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-thresholds \
  '{"models":{"model-a":{"T_abs":70000}},"N_drift":5,"theta_drift":0.1}' \
  >"$TMP_ROOT/thresholds.out" 2>"$TMP_ROOT/thresholds.err"
thresholds_valid_rc=$?
set -e
if [[ "$thresholds_valid_rc" -eq 0 && ! -s "$TMP_ROOT/thresholds.err" ]]; then
  pass "validate-thresholds accepts a valid threshold surface"
else
  fail_case "validate-thresholds accepts a valid threshold surface"
fi

set +e
python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-thresholds \
  '{"models":{"model-a":{"w":1}}}' \
  >"$TMP_ROOT/thresholds.out" 2>"$TMP_ROOT/thresholds.err"
thresholds_invalid_rc=$?
set -e
if [[ "$thresholds_invalid_rc" -eq 2 ]] \
  && grep -Fq 'model threshold w must be greater than 0 and less than 1' "$TMP_ROOT/thresholds.err"; then
  pass "validate-thresholds exits 2 with the validation message"
else
  fail_case "validate-thresholds exits 2 with the validation message"
fi

if (( failures )); then
  printf '%s overflow sentinel core test(s) failed; %s passed\n' "$failures" "$passes" >&2
  exit 1
fi
printf '%s overflow sentinel core tests passed\n' "$passes"
