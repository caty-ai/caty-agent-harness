#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURES="$ROOT/tests/fixtures/overflow-sentinel"
ADAPTER="$ROOT/adapters/claude-code/spawn_step.sh"
MONITOR="$ROOT/adapters/claude-code/overflow_sentinel_monitor.py"
MOCK_CLI="$FIXTURES/mock-cli.sh"
TMP_ROOT=${TMPDIR:-/tmp}/caty-overflow-sentinel-tap.$$
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT"
passes=0
failures=0

pass() { printf 'ok - %s\n' "$1"; passes=$((passes + 1)); }
fail_case() { printf 'not ok - %s: %s\n' "$1" "$2" >&2; failures=$((failures + 1)); }

assert_python() {
  local name=$1
  local body=$2
  shift 2
  if CASE_BODY="$body" python3 -B - "$@" <<'PY'
import json
import os
import pathlib
import sys
exec(os.environ["CASE_BODY"], globals(), globals())
PY
  then
    pass "$name"
  else
    fail_case "$name" "Python assertion failed"
  fi
}

make_attempt() {
  local case_root=$1
  local number=${2:-001}
  mkdir -p "$case_root/workspace/loop" "$case_root/artifact/attempts/$number"
  printf '# State\n' >"$case_root/workspace/STATE.md"
  printf 'task body\n' >"$case_root/workspace/task.md"
  printf 'prompt line 1\nprompt line 2\n' >"$case_root/artifact/attempts/$number/prompt.md"
}

run_monitor_fixture() {
  local fixture=$1
  local attempt_dir=$2
  local mode=${3:-shadow}
  cp "$FIXTURES/$fixture" "$attempt_dir/stream.jsonl"
  printf '0\n' >"$attempt_dir/overflow-stream.eof"
  python3 -B "$MONITOR" \
    --stream "$attempt_dir/stream.jsonl" \
    --eof "$attempt_dir/overflow-stream.eof" \
    --attempt-dir "$attempt_dir" \
    --artifact-dir "$(cd "$attempt_dir/../.." && pwd)" \
    --task-id fixture-task --attempt "$(basename "$attempt_dir")" \
    --mode "$mode" --model claude-sonnet-4-5 --t-abs 80000 --w 0.50
}

run_monitor_fixture_with_args() {
  local fixture=$1
  local attempt_dir=$2
  local mode=${3:-shadow}
  shift 3
  cp "$FIXTURES/$fixture" "$attempt_dir/stream.jsonl"
  printf '0\n' >"$attempt_dir/overflow-stream.eof"
  python3 -B "$MONITOR" \
    --stream "$attempt_dir/stream.jsonl" \
    --eof "$attempt_dir/overflow-stream.eof" \
    --attempt-dir "$attempt_dir" \
    --artifact-dir "$(cd "$attempt_dir/../.." && pwd)" \
    --task-id fixture-task --attempt "$(basename "$attempt_dir")" \
    --mode "$mode" --model claude-sonnet-4-5 "$@"
}

run_unterminated_monitor_fixture() {
  local fixture=$1
  local attempt_dir=$2
  printf '%s' "$(cat "$FIXTURES/$fixture")" >"$attempt_dir/stream.jsonl"
  printf '0\n' >"$attempt_dir/overflow-stream.eof"
  python3 -B "$MONITOR" \
    --stream "$attempt_dir/stream.jsonl" \
    --eof "$attempt_dir/overflow-stream.eof" \
    --attempt-dir "$attempt_dir" \
    --artifact-dir "$(cd "$attempt_dir/../.." && pwd)" \
    --task-id fixture-task --attempt "$(basename "$attempt_dir")" \
    --mode shadow --model claude-sonnet-4-5 --t-abs 80000 --w 0.50
}

case_root="$TMP_ROOT/realistic"
make_attempt "$case_root"
run_monitor_fixture realistic.jsonl "$case_root/artifact/attempts/001"
assert_python "realistic golden preserves exclusive addition and deduplicates message.id" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
turns=[x for x in events if x["event"]=="turn"]
assert len(turns)==2
assert (turns[0]["input_tokens"],turns[0]["cache_read_tokens"],turns[0]["cache_creation_tokens"])==(100,20,10)
assert turns[0]["input_tokens"]+turns[0]["cache_read_tokens"]+turns[0]["cache_creation_tokens"]==130
assert turns[1]["tap_status"]=="no-cache-accounting"
assert not [x for x in events if x["event"]=="fire"]
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"
assert_python "unknown fields and init/keepalive noise do not create turns" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert len([x for x in events if x["event"]=="turn"])==2
assert {x["event"] for x in events}=={"turn","attempt_end"}
assert all("task_end" not in x.values() for x in events)
assert all(x["runtime"]=="claude-code" for x in events if x["event"]=="turn")
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==0
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"
assert_python "attempt.json has the complete pinned field set and non-null first_byte_at" '
p=json.loads(pathlib.Path(sys.argv[1]).read_text())
expected={"schema_version","task_id","attempt","mode","model","ctx_window","ctx_window_source","started_at","first_byte_at","cli_exit_code","tap_status_final","fired","events_path"}
assert set(p)==expected and p["first_byte_at"]=="2026-08-25T00:00:01Z"
assert p["tap_status_final"]=="no-cache-accounting" and p["attempt"]=="001"
' "$case_root/artifact/attempts/001/attempt.json"

case_root="$TMP_ROOT/cache-boundary"
make_attempt "$case_root"
run_monitor_fixture cache-boundary.jsonl "$case_root/artifact/attempts/001"
assert_python "cache-heavy boundary fires only above the true exclusive-sum threshold" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
turns=[x for x in events if x["event"]=="turn"]
end=next(x for x in events if x["event"]=="attempt_end")
assert len(turns)==2
assert [x["input_tokens"]+x["cache_read_tokens"]+x["cache_creation_tokens"] for x in turns]==[80000,80001]
assert end["fired_turns"]==[2]
assert end["injected_summary"]=={"max":80001,"last3_mean":80000.5}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/subagent-interleave"
make_attempt "$case_root"
run_monitor_fixture subagent-interleave.jsonl "$case_root/artifact/attempts/001" active
assert_python "sub-agent assistant events do not enter or compact the main-session series" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
turns=[x for x in events if x["event"]=="turn"]
end=next(x for x in events if x["event"]=="attempt_end")
assert [x["input_tokens"] for x in turns]==[90000,90001]
assert end["compaction_suspected"] is False and end["runtime_compaction"] is False
assert end["injected_summary"]=={"max":90001,"last3_mean":90000.5}
assert end["fired_turns"]==[1] and pathlib.Path(sys.argv[2]).is_file()
' "$case_root/artifact/attempts/001/sentinel-events.jsonl" "$case_root/artifact/attempts/001/overflow-nudge.pending"

case_root="$TMP_ROOT/compact-boundary"
make_attempt "$case_root"
run_monitor_fixture compact-boundary.jsonl "$case_root/artifact/attempts/001" active
assert_python "runtime compact_boundary resets the series and withdraws a pending nudge" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=next(x for x in events if x["event"]=="attempt_end")
assert end["runtime_compaction"] is True and end["compaction_suspected"] is False
assert end["injected_summary"]=={"max":50000,"last3_mean":50000.0}
assert not pathlib.Path(sys.argv[2]).exists()
' "$case_root/artifact/attempts/001/sentinel-events.jsonl" "$case_root/artifact/attempts/001/overflow-nudge.pending"

case_root="$TMP_ROOT/regime-switch"
make_attempt "$case_root"
run_monitor_fixture_with_args regime-switch.jsonl "$case_root/artifact/attempts/001" shadow \
  --t-abs 100000 --w 0.90
assert_python "model switch resets before fire and starts a fresh slope epoch" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
changes=[x for x in events if x["event"]=="regime_change"]
fires=[x for x in events if x["event"]=="fire"]
end=next(x for x in events if x["event"]=="attempt_end")
assert len(changes)==1
change=changes[0]
assert change["turn_idx"]==4
assert (change["from_model"],change["to_model"])==("model-a","model-b")
assert (change["from_runtime"],change["to_runtime"])==("claude-code","claude-code")
assert change["resolved"]=={"ctx_window":200000,"T_abs":100000,"w":0.9,"ttfb_floor":240}
assert change["sources"]=={"ctx_window_source":"default","threshold_sources":{"T_abs":"config","w":"config"}}
assert change["drift_reference"]=={"from":"none","to":"none"}
assert change["attempt"]=="001" and change["schema_version"]==1
assert not [x for x in fires if x["turn_idx"]==4]
assert [(x["turn_idx"],x["slope"] is None) for x in fires]==[(6,True),(7,False)]
assert end["regime_change_resets"]==1
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/alias-version-sway"
make_attempt "$case_root"
run_monitor_fixture_with_args alias-version-sway.jsonl "$case_root/artifact/attempts/001" shadow \
  --model-aliases '{" model-a-v1 ":"family-a","MODEL-A-V2":"family-a"}'
assert_python "alias case whitespace and version sway stay in one regime" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not [x for x in events if x["event"]=="regime_change"]
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==0
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/regime-compact-boundary"
make_attempt "$case_root"
run_monitor_fixture regime-compact-boundary.jsonl "$case_root/artifact/attempts/001" active
assert_python "same-turn runtime compaction and model switch reset exactly once" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
changes=[x for x in events if x["event"]=="regime_change"]
fires=[x for x in events if x["event"]=="fire"]
end=next(x for x in events if x["event"]=="attempt_end")
assert len(changes)==1 and end["regime_change_resets"]==1
assert end["runtime_compaction"] is True and end["compaction_suspected"] is False
assert end["injected_summary"]=={"max":30000,"last3_mean":30000.0}
assert [(x["turn_idx"],x["slope"]) for x in fires]==[(1,None)]
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/identity-missing-noop"
make_attempt "$case_root"
run_monitor_fixture identity-missing-noop.jsonl "$case_root/artifact/attempts/001"
assert_python "missing model identity does not compare or reset" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not [x for x in events if x["event"]=="regime_change"]
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==0
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/identity-missing-before-switch"
make_attempt "$case_root"
run_monitor_fixture identity-missing-before-switch.jsonl "$case_root/artifact/attempts/001"
assert_python "complete identity after a missing-model turn compares with the last complete turn" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
changes=[x for x in events if x["event"]=="regime_change"]
assert len(changes)==1 and changes[0]["turn_idx"]==3
assert (changes[0]["from_model"],changes[0]["to_model"])==("model-a","model-b")
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==1
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/hysteresis-regime-rearm"
make_attempt "$case_root"
run_monitor_fixture hysteresis-regime-rearm.jsonl "$case_root/artifact/attempts/001" shadow
assert_python "per-axis hysteresis is re-armed by a regime switch" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
fires=[x for x in events if x["event"]=="fire"]
assert [(x["turn_idx"],x["axis"],x["injected_ma"]) for x in fires]==[(1,"level",90000.0),(2,"level",85000.0)]
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==1
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/regime-ctx-override"
make_attempt "$case_root"
_CATY_TESTING=1 _CATY_OVF_TEST_TTFB_FLOOR_S=7 \
run_monitor_fixture_with_args hysteresis-regime-rearm.jsonl "$case_root/artifact/attempts/001" shadow \
  --ctx-window 123456 --t-abs 80000 --w 0.50
assert_python "run-level context override survives a regime switch" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
change=next(x for x in events if x["event"]=="regime_change")
assert change["resolved"]["ctx_window"]==123456
assert change["sources"]["ctx_window_source"]=="config"
assert change["resolved"]["ttfb_floor"]==7
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/regime-threshold-defaults"
make_attempt "$case_root"
run_monitor_fixture_with_args hysteresis-regime-rearm.jsonl "$case_root/artifact/attempts/001" shadow
assert_python "omitted thresholds report product-default provenance" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
change=next(x for x in events if x["event"]=="regime_change")
end=next(x for x in events if x["event"]=="attempt_end")
assert change["resolved"]["T_abs"]==80000 and change["resolved"]["w"]==0.5
assert change["sources"]["threshold_sources"]=={"T_abs":"default","w":"default"}
assert end["run_meta"]["threshold_sources"]=={"T_abs":"default","w":"default"}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/regime-threshold-config"
make_attempt "$case_root"
run_monitor_fixture hysteresis-regime-rearm.jsonl "$case_root/artifact/attempts/001"
assert_python "explicit thresholds report config provenance" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
change=next(x for x in events if x["event"]=="regime_change")
assert change["sources"]["threshold_sources"]=={"T_abs":"config","w":"config"}
assert next(x for x in events if x["event"]=="attempt_end")["run_meta"]["threshold_sources"]=={"T_abs":"config","w":"config"}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/regime-retry-switch"
make_attempt "$case_root" 001
run_monitor_fixture fire.jsonl "$case_root/artifact/attempts/001" shadow
make_attempt "$case_root" 002
run_monitor_fixture model-b-fire.jsonl "$case_root/artifact/attempts/002" shadow
make_attempt "$case_root" 003
run_monitor_fixture model-b-fire.jsonl "$case_root/artifact/attempts/003" shadow
make_attempt "$case_root" 004
_CATY_TESTING=1 _CATY_OVF_TEST_ELAPSED_S=241 \
run_monitor_fixture absent.jsonl "$case_root/artifact/attempts/004" shadow
assert_python "model-changing retry compares persisted identity and re-arms hysteresis" '
first=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
second=[json.loads(x) for x in pathlib.Path(sys.argv[2]).read_text().splitlines()]
third=[json.loads(x) for x in pathlib.Path(sys.argv[3]).read_text().splitlines()]
fourth=[json.loads(x) for x in pathlib.Path(sys.argv[4]).read_text().splitlines()]
state=json.loads(pathlib.Path(sys.argv[5]).read_text())
assert next(x for x in first if x["event"]=="attempt_end")["regime_change_resets"]==0
changes=[x for x in second if x["event"]=="regime_change"]
fires=[x for x in second if x["event"]=="fire"]
assert len(changes)==1 and changes[0]["turn_idx"]==1
assert (changes[0]["from_model"],changes[0]["to_model"])==("claude-sonnet-4-5","model-b")
assert len(fires)==1 and fires[0]["injected_ma"]==85000.0
assert next(x for x in second if x["event"]=="attempt_end")["regime_change_resets"]==1
assert not [x for x in third if x["event"] in {"regime_change","fire"}]
assert next(x for x in third if x["event"]=="attempt_end")["regime_change_resets"]==0
assert next(x for x in fourth if x["event"]=="alert")["floor_applied"]==240
assert state["regime_identity"]=={"model":"model-b","runtime":"claude-code"}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl" \
  "$case_root/artifact/attempts/002/sentinel-events.jsonl" \
  "$case_root/artifact/attempts/003/sentinel-events.jsonl" \
  "$case_root/artifact/attempts/004/sentinel-events.jsonl" \
  "$case_root/artifact/overflow-sentinel-state.json"

case_root="$TMP_ROOT/no-trailing-newline"
make_attempt "$case_root"
run_unterminated_monitor_fixture no-trailing-newline.jsonl "$case_root/artifact/attempts/001"
assert_python "post-EOF drain parses an unterminated final assistant line" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert len([x for x in events if x["event"]=="turn"])==1
end=next(x for x in events if x["event"]=="attempt_end")
assert end["fired_turns"]==[1] and end["injected_summary"]=={"max":90000,"last3_mean":90000.0}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/zero-and-invalid"
make_attempt "$case_root"
run_monitor_fixture zero-and-invalid.jsonl "$case_root/artifact/attempts/001"
assert_python "zero-injected and unparsable usage never corrupt the measured series" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
turns=[x for x in events if x["event"]=="turn"]
end=next(x for x in events if x["event"]=="attempt_end")
assert [x["input_tokens"] for x in turns]==[90000,0,90001]
assert not any(x.get("cache_read_tokens")=="garbage" for x in turns)
assert end["compaction_suspected"] is False
assert end["injected_summary"]=={"max":90001,"last3_mean":90000.5}
assert end["tap_status"]=="no-cache-accounting"
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/slope-only"
make_attempt "$case_root"
run_monitor_fixture slope-only.jsonl "$case_root/artifact/attempts/001"
assert_python "slope-only fire omits the level threshold_hit field" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
fires=[x for x in events if x["event"]=="fire"]
assert len(fires)==1 and fires[0]["axis"]=="slope"
assert fires[0]["projection_turns"] <= 10 and "threshold_hit" not in fires[0]
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/blind-three"
make_attempt "$case_root"
run_monitor_fixture blind-three.jsonl "$case_root/artifact/attempts/001"
assert_python "three consecutive blind turns disable evaluation and stay out of series" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
turns=[x for x in events if x["event"]=="turn"]
end=[x for x in events if x["event"]=="attempt_end"][0]
assert len(turns)==4 and [x["tap_status"] for x in turns[:3]]==["blind"]*3
assert not [x for x in events if x["event"]=="fire"]
assert end["tap_status"]=="blind" and end["injected_summary"]=={"max":0,"last3_mean":0}
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"

case_root="$TMP_ROOT/blind-short"
make_attempt "$case_root"
printf '%s\n' '{"last_fire_ma":{"level":91000.0},"last_run_injected_ma":87000.0,"schema_version":1}' \
  >"$case_root/artifact/overflow-sentinel-state.json"
blind_state_before=$(shasum -a 256 "$case_root/artifact/overflow-sentinel-state.json" | awk '{print $1}')
run_monitor_fixture blind-short.jsonl "$case_root/artifact/attempts/001"
assert_python "short all-zero run is reported blind immediately" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert [x for x in events if x["event"]=="attempt_end"][0]["tap_status"]=="blind"
assert all(x["tap_status"]=="blind" for x in events if x["event"]=="turn")
' "$case_root/artifact/attempts/001/sentinel-events.jsonl"
blind_state_after=$(shasum -a 256 "$case_root/artifact/overflow-sentinel-state.json" | awk '{print $1}')
[[ "$blind_state_before" == "$blind_state_after" ]] \
  && pass "blind run preserves prior hysteresis state bytes" \
  || fail_case "blind run preserves prior hysteresis state bytes" "digest changed"

case_root="$TMP_ROOT/absent"
make_attempt "$case_root"
printf '%s\n' '{"last_fire_ma":{"slope":70000.0},"last_run_injected_ma":65000.0,"schema_version":1}' \
  >"$case_root/artifact/overflow-sentinel-state.json"
absent_state_before=$(shasum -a 256 "$case_root/artifact/overflow-sentinel-state.json" | awk '{print $1}')
run_monitor_fixture absent.jsonl "$case_root/artifact/attempts/001"
assert_python "absent usage remains distinct and first_byte_at is null" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=[x for x in events if x["event"]=="attempt_end"][0]
receipt=json.loads(pathlib.Path(sys.argv[2]).read_text())
assert end["tap_status"]=="absent" and not [x for x in events if x["event"]=="turn"]
assert receipt["first_byte_at"] is None
' "$case_root/artifact/attempts/001/sentinel-events.jsonl" "$case_root/artifact/attempts/001/attempt.json"
absent_state_after=$(shasum -a 256 "$case_root/artifact/overflow-sentinel-state.json" | awk '{print $1}')
[[ "$absent_state_before" == "$absent_state_after" ]] \
  && pass "absent run preserves prior hysteresis state bytes" \
  || fail_case "absent run preserves prior hysteresis state bytes" "digest changed"

case_root="$TMP_ROOT/compaction"
make_attempt "$case_root"
run_monitor_fixture compaction.jsonl "$case_root/artifact/attempts/001" active
assert_python "compaction reset excludes pre-drop series and withdraws pending nudge" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=[x for x in events if x["event"]=="attempt_end"][0]
assert end["compaction_suspected"] is True
assert end["injected_summary"]=={"max":50000,"last3_mean":50000.0}
assert not pathlib.Path(sys.argv[2]).exists()
' "$case_root/artifact/attempts/001/sentinel-events.jsonl" "$case_root/artifact/attempts/001/overflow-nudge.pending"

# Claude's cache fields are disjoint, so cached-inclusion normalization is N/A.
# The exclusive-addition golden above is the oracle for the double-count mutant.
pass "cached-inclusion removal is N/A for Claude; exclusive-addition mutant oracle is active"

adapter_root="$TMP_ROOT/e2e"
make_attempt "$adapter_root"
attempt="$adapter_root/artifact/attempts/001"
capture="$adapter_root/stdin.capture"
cwd_capture="$adapter_root/cwd.capture"
env_capture="$adapter_root/env.capture"
printf '{"sentinel":"driver-owned"}\n' >"$attempt/step-result.json"
step_result_before=$(shasum -a 256 "$attempt/step-result.json" | awk '{print $1}')
set +e
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STDIN_PATH="$capture" MOCK_CWD_PATH="$cwd_capture" MOCK_ENV_PATH="$env_capture" \
MOCK_MARKER=passed-through MOCK_STREAM_FILE="$FIXTURES/realistic.jsonl" MOCK_STDERR='mock stderr exact' \
  "$ADAPTER" "$adapter_root/workspace/task.md" "$adapter_root/workspace" "$attempt" 1 \
  >"$adapter_root/stdout" 2>"$adapter_root/stderr"
adapter_rc=$?
set -e
[[ "$adapter_rc" -eq 0 ]] && pass "mock CLI exit zero propagates" || fail_case "mock CLI exit zero propagates" "$adapter_rc"
cmp -s "$attempt/prompt.md" "$capture" && pass "prompt reaches CLI stdin verbatim" || fail_case "prompt reaches CLI stdin verbatim" "bytes differ"
expected_cwd=$(cd "$adapter_root/workspace" && pwd -P)
[[ "$(cat "$cwd_capture")" == "$expected_cwd" ]] && pass "CLI cwd is workspace" || fail_case "CLI cwd is workspace" "$(cat "$cwd_capture")"
[[ "$(cat "$env_capture")" == passed-through ]] && pass "CLI environment passes marker through" || fail_case "CLI environment passes marker through" "missing marker"
grep -Fqx 'mock stderr exact' "$adapter_root/stderr" && pass "CLI stderr passes through adapter stderr" || fail_case "CLI stderr passes through adapter stderr" "$(cat "$adapter_root/stderr")"
cmp -s "$adapter_root/stdout" "$attempt/stream.jsonl" && pass "model.stdout tee is byte-identical to stream.jsonl" || fail_case "model.stdout tee is byte-identical to stream.jsonl" "bytes differ"
[[ -f "$attempt/overflow-stream.eof" ]] && pass "EOF marker is written" || fail_case "EOF marker is written" "missing"
grep -Fq '"event": "attempt_end"' "$attempt/sentinel-events.jsonl" && pass "attempt_end is finalized before adapter exit" || fail_case "attempt_end is finalized before adapter exit" "missing"
assert_python "spawn-step omits unset threshold flags so defaults retain provenance" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=next(x for x in events if x["event"]=="attempt_end")
assert end["run_meta"]["threshold_sources"]=={"T_abs":"default","w":"default"}
' "$attempt/sentinel-events.jsonl"
step_result_after=$(shasum -a 256 "$attempt/step-result.json" | awk '{print $1}')
[[ "$step_result_before" == "$step_result_after" ]] && pass "adapter never touches step-result.json" || fail_case "adapter never touches step-result.json" "digest changed"

alias_adapter_root="$TMP_ROOT/alias-adapter"
make_attempt "$alias_adapter_root"
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel \
OVF_MODEL_ALIASES='{"model-a-v1":"family-a","model-a-v2":"family-a"}' \
OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/alias-version-sway.jsonl" \
  "$ADAPTER" "$alias_adapter_root/workspace/task.md" "$alias_adapter_root/workspace" \
  "$alias_adapter_root/artifact/attempts/001" 1 >"$alias_adapter_root/out" 2>"$alias_adapter_root/err"
assert_python "spawn-step validates and forwards OVF_MODEL_ALIASES" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not [x for x in events if x["event"]=="regime_change"]
assert next(x for x in events if x["event"]=="attempt_end")["regime_change_resets"]==0
' "$alias_adapter_root/artifact/attempts/001/sentinel-events.jsonl"

off_root="$TMP_ROOT/off"
make_attempt "$off_root"
off_attempt="$off_root/artifact/attempts/001"
set +e
OVF_T_ABS=garbage OVF_W_PCT=garbage OVF_CTX_WINDOW=garbage \
OVF_COMPACTION_OWNER=garbage OVF_FINALIZE_TIMEOUT_S=garbage OVF_HF_CONFIG="$TMP_ROOT/missing.json" \
OVF_STEP_CMD="$MOCK_CLI" MOCK_STDOUT='raw model stdout' MOCK_STDERR='off stderr' \
  "$ADAPTER" "$off_root/workspace/task.md" "$off_root/workspace" "$off_attempt" 1 \
  >"$off_root/stdout" 2>"$off_root/stderr"
off_rc=$?
set -e
[[ "$off_rc" -eq 0 && "$(cat "$off_root/stdout")" == 'raw model stdout' ]] \
  && pass "OVF_SENTINEL unset ignores stray OVF configuration and preserves direct stdout" \
  || fail_case "OVF_SENTINEL unset ignores stray OVF configuration and preserves direct stdout" "rc=$off_rc stdout=$(cat "$off_root/stdout")"
if find "$off_root/artifact" -name 'sentinel-events.jsonl' -o -name 'overflow-nudge.pending' \
  -o -name 'attempt.json' -o -name 'stream.jsonl' -o -name 'overflow-stream.eof' \
  -o -name 'overflow-sentinel-state.json' | grep -q .; then
  fail_case "OVF_SENTINEL unset creates zero sentinel artifacts" "unexpected artifact"
else
  pass "OVF_SENTINEL unset creates zero sentinel artifacts"
fi

# Measured bound for #204 from ci-matrix macOS run 33007204524: adapter overhead
# (elapsed minus the 1.2s mock sleep) was 0.92-1.16s, so the old 2s budget left
# only 0.8s headroom and flaked intermittently. 12s leaves 10.8s headroom while
# staying <= finalize(10)+2, so a wrongly shaved sentinel budget is still 1s < 1.2s.
off_budget_root="$TMP_ROOT/off-budget"
make_attempt "$off_budget_root"
set +e
TR_STEP_TIMEOUT_S=12 OVF_FINALIZE_TIMEOUT_S=garbage OVF_T_ABS=garbage \
OVF_STEP_CMD="$MOCK_CLI" MOCK_SLEEP_S=1.2 MOCK_STDOUT='budget preserved' \
  "$ADAPTER" "$off_budget_root/workspace/task.md" "$off_budget_root/workspace" \
  "$off_budget_root/artifact/attempts/001" 1 >"$off_budget_root/out" 2>"$off_budget_root/err"
off_budget_rc=$?
set -e
[[ "$off_budget_rc" -eq 0 && "$(cat "$off_budget_root/out")" == 'budget preserved' ]] \
  && pass "OVF_SENTINEL unset retains the full exported TR step budget" \
  || fail_case "OVF_SENTINEL unset retains the full exported TR step budget" "rc=$off_budget_rc"

invalid_root="$TMP_ROOT/invalid"
make_attempt "$invalid_root"
invalid_attempt="$invalid_root/artifact/attempts/001"
invalid_cases='OVF_SENTINEL=bad
OVF_T_ABS=0
OVF_T_ABS=x
OVF_W_PCT=0
OVF_W_PCT=100
OVF_W_PCT=x
OVF_CTX_WINDOW=0
OVF_CTX_WINDOW=x
OVF_MODEL_ALIASES=[]
OVF_COMPACTION_OWNER=bad
OVF_FINALIZE_TIMEOUT_S=0
OVF_FINALIZE_TIMEOUT_S=x
OVF_STEP_CMD=missing-overflow-command'
while IFS= read -r invalid_case; do
  invalid_name=${invalid_case%%=*}
  invalid_value=${invalid_case#*=}
  rm -f "$invalid_root/called"
  set +e
  env OVF_SENTINEL=active OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" \
    MOCK_STDIN_PATH="$invalid_root/called" "$invalid_name=$invalid_value" \
    "$ADAPTER" "$invalid_root/workspace/task.md" "$invalid_root/workspace" "$invalid_attempt" 1 \
    >"$invalid_root/out" 2>"$invalid_root/err"
  invalid_rc=$?
  set -e
  if [[ "$invalid_rc" -eq 2 && ! -e "$invalid_root/called" ]]; then
    pass "invalid $invalid_name=$invalid_value exits 2 before spawn"
  else
    fail_case "invalid $invalid_name=$invalid_value exits 2 before spawn" "rc=$invalid_rc called=$([[ -e "$invalid_root/called" ]] && printf yes || printf no)"
  fi
done <<<"$invalid_cases"

set +e
OVF_SENTINEL=active OVF_COMPACTION_OWNER=sentinel OVF_HF_CONFIG="$TMP_ROOT/missing-hf.json" \
OVF_STEP_CMD="$MOCK_CLI" MOCK_STDIN_PATH="$invalid_root/called-hf" \
  "$ADAPTER" "$invalid_root/workspace/task.md" "$invalid_root/workspace" "$invalid_attempt" 1 \
  >"$invalid_root/out" 2>"$invalid_root/err"
invalid_hf_rc=$?
set -e
[[ "$invalid_hf_rc" -eq 2 && ! -e "$invalid_root/called-hf" ]] \
  && pass "invalid OVF_HF_CONFIG exits 2 before spawn" \
  || fail_case "invalid OVF_HF_CONFIG exits 2 before spawn" "rc=$invalid_hf_rc"

warning_root="$TMP_ROOT/warning"
make_attempt "$warning_root"
OVF_SENTINEL=shadow OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
  "$ADAPTER" "$warning_root/workspace/task.md" "$warning_root/workspace" \
  "$warning_root/artifact/attempts/001" 1 >"$warning_root/out" 2>"$warning_root/err"
grep -Fqx 'warning: OVF_COMPACTION_OWNER is unset; overflow sentinel owns compaction detection' "$warning_root/err" \
  && pass "unset compaction owner emits exact lowercase warning" \
  || fail_case "unset compaction owner emits exact lowercase warning" "$(cat "$warning_root/err")"

small_budget_root="$TMP_ROOT/small-budget"
make_attempt "$small_budget_root"
TR_STEP_TIMEOUT_S=20 OVF_FINALIZE_TIMEOUT_S=10 OVF_SENTINEL=shadow \
OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
  "$ADAPTER" "$small_budget_root/workspace/task.md" "$small_budget_root/workspace" \
  "$small_budget_root/artifact/attempts/001" 1 >"$small_budget_root/out" 2>"$small_budget_root/err"
grep -Fqx 'warning: overflow sentinel derived CLI budget is only 9s after finalize reservation' \
  "$small_budget_root/err" \
  && pass "implausibly small derived CLI budget emits a warning" \
  || fail_case "implausibly small derived CLI budget emits a warning" "$(cat "$small_budget_root/err")"

host_root="$TMP_ROOT/host"
make_attempt "$host_root"
OVF_SENTINEL=active OVF_COMPACTION_OWNER=host OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" \
  "$ADAPTER" "$host_root/workspace/task.md" "$host_root/workspace" \
  "$host_root/artifact/attempts/001" 1 >"$host_root/out" 2>"$host_root/err"
assert_python "host compaction owner records disabled-host attempt_end" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert {x["event"] for x in events}=={"attempt_end"}
assert events[0]["tap_status"]=="disabled-host"
' "$host_root/artifact/attempts/001/sentinel-events.jsonl"

shadow_root="$TMP_ROOT/shadow"
make_attempt "$shadow_root"
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" \
  "$ADAPTER" "$shadow_root/workspace/task.md" "$shadow_root/workspace" \
  "$shadow_root/artifact/attempts/001" 1 >"$shadow_root/out" 2>"$shadow_root/err"
[[ ! -e "$shadow_root/artifact/attempts/001/overflow-nudge.pending" ]] \
  && pass "shadow fire writes no pending nudge" || fail_case "shadow fire writes no pending nudge" "pending exists"

lifecycle_root="$TMP_ROOT/lifecycle"
make_attempt "$lifecycle_root" 001
first_attempt="$lifecycle_root/artifact/attempts/001"
OVF_SENTINEL=active OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" MOCK_STEP_RESULT='{"step_complete":true}' \
  "$ADAPTER" "$lifecycle_root/workspace/task.md" "$lifecycle_root/workspace" "$first_attempt" 1 \
  >"$lifecycle_root/one.out" 2>"$lifecycle_root/one.err"
[[ -f "$first_attempt/overflow-nudge.pending" ]] && pass "run N fire leaves pending nudge" || fail_case "run N fire leaves pending nudge" "missing"
assert_python "terminal firing attempt records suppressed disposition" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=[x for x in events if x["event"]=="attempt_end"][0]
assert end["nudge_disposition_final"]=="suppressed"
' "$first_attempt/sentinel-events.jsonl"
make_attempt "$lifecycle_root" 002
second_attempt="$lifecycle_root/artifact/attempts/002"
shown_capture="$lifecycle_root/shown.prompt"
OVF_SENTINEL=active OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" MOCK_STDIN_PATH="$shown_capture" MOCK_STEP_RESULT='{"step_complete":true}' \
  "$ADAPTER" "$lifecycle_root/workspace/task.md" "$lifecycle_root/workspace" "$second_attempt" 2 \
  >"$lifecycle_root/two.out" 2>"$lifecycle_root/two.err"
grep -Fq '1. Goal' "$shown_capture" && pass "run N+1 prepends pending nudge" || fail_case "run N+1 prepends pending nudge" "missing text"
[[ ! -e "$first_attempt/overflow-nudge.pending" && ! -e "$second_attempt/overflow-nudge.pending" ]] \
  && pass "shown nudge is deleted and cross-attempt hysteresis suppresses repeat" \
  || fail_case "shown nudge is deleted and cross-attempt hysteresis suppresses repeat" "pending remains"
assert_python "run N+1 attempt_end records shown disposition" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
end=[x for x in events if x["event"]=="attempt_end"][0]
assert end["nudge_disposition_final"]=="shown" and not end["fired_turns"]
assert end["regime_change_resets"]==0
' "$second_attempt/sentinel-events.jsonl"

numeric_root="$TMP_ROOT/numeric-pending"
make_attempt "$numeric_root" 011
mkdir -p "$numeric_root/artifact/attempts/9" "$numeric_root/artifact/attempts/010"
printf 'older numeric pending\n' >"$numeric_root/artifact/attempts/9/overflow-nudge.pending"
printf 'newer numeric pending\n' >"$numeric_root/artifact/attempts/010/overflow-nudge.pending"
numeric_capture="$numeric_root/numeric.prompt"
OVF_SENTINEL=active OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" MOCK_STDIN_PATH="$numeric_capture" \
  "$ADAPTER" "$numeric_root/workspace/task.md" "$numeric_root/workspace" \
  "$numeric_root/artifact/attempts/011" 1 >"$numeric_root/out" 2>"$numeric_root/err"
if grep -Fq 'newer numeric pending' "$numeric_capture" \
  && ! grep -Fq 'older numeric pending' "$numeric_capture" \
  && [[ -f "$numeric_root/artifact/attempts/9/overflow-nudge.pending" ]] \
  && [[ ! -e "$numeric_root/artifact/attempts/010/overflow-nudge.pending" ]]; then
  pass "pending nudge selection orders attempt basenames numerically"
else
  fail_case "pending nudge selection orders attempt basenames numerically" "wrong pending selected"
fi

w_root="$TMP_ROOT/w-pct"
make_attempt "$w_root"
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel OVF_W_PCT=5 OVF_CTX_WINDOW=10000 \
OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" \
  "$ADAPTER" "$w_root/workspace/task.md" "$w_root/workspace" "$w_root/artifact/attempts/001" 1 \
  >"$w_root/out" 2>"$w_root/err"
assert_python "OVF_W_PCT converts through division by one hundred" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
fire=[x for x in events if x["event"]=="fire"][0]
assert fire["run_meta"]["w"]==0.05
assert fire["run_meta"]["threshold_sources"]=={"T_abs":"default","w":"config"}
' "$w_root/artifact/attempts/001/sentinel-events.jsonl"
exit_root="$TMP_ROOT/exit"
make_attempt "$exit_root"
set +e
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_EXIT=7 \
MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
  "$ADAPTER" "$exit_root/workspace/task.md" "$exit_root/workspace" "$exit_root/artifact/attempts/001" 1 \
  >"$exit_root/out" 2>"$exit_root/err"
exit_rc=$?
set -e
[[ "$exit_rc" -eq 7 ]] && pass "mock CLI exit code N propagates exactly" || fail_case "mock CLI exit code N propagates exactly" "$exit_rc"

partial_timeout_root="$TMP_ROOT/partial-timeout"
make_attempt "$partial_timeout_root"
set +e
TR_STEP_TIMEOUT_S=4 OVF_FINALIZE_TIMEOUT_S=1 OVF_SENTINEL=shadow \
OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
MOCK_STEP_RESULT='{"step_comp"' MOCK_SLEEP_S=60 \
  "$ADAPTER" "$partial_timeout_root/workspace/task.md" "$partial_timeout_root/workspace" \
  "$partial_timeout_root/artifact/attempts/001" 1 >"$partial_timeout_root/out" 2>"$partial_timeout_root/err"
partial_timeout_rc=$?
set -e
if [[ "$partial_timeout_rc" -eq 124 ]] \
  && [[ ! -e "$partial_timeout_root/artifact/attempts/001/step-result.json" ]] \
  && [[ -f "$partial_timeout_root/artifact/attempts/001/step-result.json.partial" ]]; then
  pass "timed-out model output is quarantined as step-result.json.partial"
else
  fail_case "timed-out model output is quarantined as step-result.json.partial" "rc=$partial_timeout_rc"
fi

partial_signal_root="$TMP_ROOT/partial-signal"
make_attempt "$partial_signal_root"
TR_STEP_TIMEOUT_S=30 OVF_FINALIZE_TIMEOUT_S=1 OVF_SENTINEL=shadow \
OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
MOCK_STEP_RESULT='{"step_comp"' MOCK_SLEEP_S=60 \
  "$ADAPTER" "$partial_signal_root/workspace/task.md" "$partial_signal_root/workspace" \
  "$partial_signal_root/artifact/attempts/001" 1 >"$partial_signal_root/out" 2>"$partial_signal_root/err" &
partial_signal_pid=$!
partial_signal_tries=0
while [[ ! -f "$partial_signal_root/artifact/attempts/001/step-result.json" ]] \
  && (( partial_signal_tries < 50 )); do
  sleep 0.1
  partial_signal_tries=$((partial_signal_tries + 1))
done
kill -TERM "$partial_signal_pid" 2>/dev/null || true
set +e
wait "$partial_signal_pid"
partial_signal_rc=$?
set -e
if [[ "$partial_signal_rc" -eq 143 ]] \
  && [[ ! -e "$partial_signal_root/artifact/attempts/001/step-result.json" ]] \
  && [[ -f "$partial_signal_root/artifact/attempts/001/step-result.json.partial" ]]; then
  pass "signal-killed model output is quarantined as step-result.json.partial"
else
  fail_case "signal-killed model output is quarantined as step-result.json.partial" "rc=$partial_signal_rc"
fi

hang_root="$TMP_ROOT/hang"
make_attempt "$hang_root"
alive_marker="$hang_root/child-alive"
_CATY_TESTING=1 _CATY_OVF_TEST_TTFB_FLOOR_S=0 OVF_SENTINEL=active \
OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
MOCK_SLEEP_S=0.2 MOCK_ALIVE_PATH="$alive_marker" \
  "$ADAPTER" "$hang_root/workspace/task.md" "$hang_root/workspace" "$hang_root/artifact/attempts/001" 1 \
  >"$hang_root/out" 2>"$hang_root/err"
assert_python "hang fixture writes one alert, zero fire, and leaves child alive" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert len([x for x in events if x["event"]=="alert"])==1
assert len([x for x in events if x["event"]=="fire"])==0
assert pathlib.Path(sys.argv[2]).read_text().strip()=="alive"
' "$hang_root/artifact/attempts/001/sentinel-events.jsonl" "$alive_marker"

tier_root="$TMP_ROOT/ttfb-tier"
make_attempt "$tier_root"
printf '%s\n' '{"last_fire_ma":{},"last_run_injected_ma":60000,"schema_version":1}' \
  >"$tier_root/artifact/overflow-sentinel-state.json"
_CATY_TESTING=1 _CATY_OVF_TEST_ELAPSED_S=151 OVF_SENTINEL=shadow \
OVF_COMPACTION_OWNER=sentinel CLAUDE_MODEL=claude-sonnet-4-5 OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
  "$ADAPTER" "$tier_root/workspace/task.md" "$tier_root/workspace" "$tier_root/artifact/attempts/001" 1 \
  >"$tier_root/out" 2>"$tier_root/err"
assert_python "prior-attempt 60k MA makes the live alert use the 150-second tier" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
alerts=[x for x in events if x["event"]=="alert"]
assert len(alerts)==1 and alerts[0]["floor_applied"]==150
' "$tier_root/artifact/attempts/001/sentinel-events.jsonl"

unknown_tier_root="$TMP_ROOT/ttfb-unknown"
make_attempt "$unknown_tier_root"
_CATY_TESTING=1 _CATY_OVF_TEST_ELAPSED_S=241 OVF_SENTINEL=shadow \
OVF_COMPACTION_OWNER=sentinel CLAUDE_MODEL=claude-sonnet-4-5 OVF_STEP_CMD="$MOCK_CLI" \
MOCK_STREAM_FILE="$FIXTURES/absent.jsonl" \
  "$ADAPTER" "$unknown_tier_root/workspace/task.md" "$unknown_tier_root/workspace" \
  "$unknown_tier_root/artifact/attempts/001" 1 >"$unknown_tier_root/out" 2>"$unknown_tier_root/err"
assert_python "no prior state makes the live alert use the unknown 240-second tier" '
events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
alerts=[x for x in events if x["event"]=="alert"]
assert len(alerts)==1 and alerts[0]["floor_applied"]==240
' "$unknown_tier_root/artifact/attempts/001/sentinel-events.jsonl"
assert_python "turn fire alert and attempt_end use the complete DESIGN wire names" '
fire_events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
alert_events=[json.loads(x) for x in pathlib.Path(sys.argv[2]).read_text().splitlines()]
turn=next(x for x in fire_events if x["event"]=="turn")
fire=next(x for x in fire_events if x["event"]=="fire")
end=next(x for x in fire_events if x["event"]=="attempt_end")
alert=next(x for x in alert_events if x["event"]=="alert")
assert {"event","schema_version","ts","task_id","attempt","turn_idx","input_tokens","cache_read_tokens","cache_creation_tokens","output_tokens","model","runtime","tap_status"} <= set(turn)
assert {"event","schema_version","ts","started_at","task_id","attempt","turn_idx","axis","injected_ma","injected_last","value_kind","threshold_hit","ctx_window","ctx_window_source","slope","projection_turns","decision","nudge_disposition","model","runtime","tap_status","run_meta"} <= set(fire)
assert {"event","schema_version","ts","task_id","attempt","turn_idx","ttfb_ms","floor_applied","model","runtime"} <= set(alert)
assert {"event","schema_version","ts","started_at","task_id","attempt","outcome","window_error","runtime_compaction","compaction_suspected","regime_change_resets","total_tokens","injected_summary","fired_turns","alert_turns","nudge_disposition_final","tap_status","run_meta","elapsed_s"} <= set(end)
assert end["outcome"] in {"step_completed","aborted","overflowed"}
' "$w_root/artifact/attempts/001/sentinel-events.jsonl" "$tier_root/artifact/attempts/001/sentinel-events.jsonl"

timeout_root="$TMP_ROOT/finalize-timeout"
make_attempt "$timeout_root"
set +e
_CATY_TESTING=1 _CATY_OVF_TEST_HANG_FINALIZE=1 OVF_FINALIZE_TIMEOUT_S=1 \
OVF_SENTINEL=shadow OVF_COMPACTION_OWNER=sentinel OVF_STEP_CMD="$MOCK_CLI" MOCK_EXIT=7 \
MOCK_STREAM_FILE="$FIXTURES/fire.jsonl" \
  "$ADAPTER" "$timeout_root/workspace/task.md" "$timeout_root/workspace" \
  "$timeout_root/artifact/attempts/001" 1 >"$timeout_root/out" 2>"$timeout_root/err"
timeout_rc=$?
set -e
if [[ "$timeout_rc" -eq 7 ]] && grep -Fqx 'warning: overflow sentinel finalize timeout; records may be incomplete' "$timeout_root/err"; then
  pass "hung monitor timeout warns without changing CLI exit code"
else
  fail_case "hung monitor timeout warns without changing CLI exit code" "rc=$timeout_rc stderr=$(cat "$timeout_root/err")"
fi
assert_python "fire-time state survives a monitor finalize timeout" '
state=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert state["last_fire_ma"]=={"level":90000.0}
' "$timeout_root/artifact/overflow-sentinel-state.json"

if (( failures )); then
  printf '%s overflow sentinel tap test(s) failed; %s passed\n' "$failures" "$passes" >&2
  exit 1
fi
printf '%s overflow sentinel tap tests passed\n' "$passes"
