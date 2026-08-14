#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

ROOT=${EV005_REPO_ROOT:-$PWD}
RUNNER=$ROOT/scripts/task-runner.sh
ENQUEUE=$ROOT/scripts/tr-enqueue
MOCK=$ROOT/tests/fixtures/mock-spawn-step.sh
FIX_BASIC=$ROOT/tests/fixtures/task-basic.task.md
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t23-input-probe.XXXXXX") || exit 1

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

[ -f "$RUNNER" ] && [ -x "$ENQUEUE" ] && [ -x "$MOCK" ] && [ -f "$FIX_BASIC" ] || exit 1

make_ws() {
  local name ws
  name=$1
  ws=$TMP_ROOT/ws-$name
  mkdir -p "$ws/loop/tasks/queue" || return 1
  printf '# State\n' >"$ws/STATE.md" || return 1
  printf '%s\n' "$ws"
}

run_tick() {
  local ws
  ws=$1
  shift
  env TR_SPAWN_STEP="$MOCK" "$@" bash "$RUNNER" "$ws"
}

state_value() {
  python3 -B - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    value = value.get(part)
print("" if value is None else value)
PY
}

probe_env_integers() {
  local variable ws output rc
  for variable in TR_STEP_TIMEOUT_S TR_GRACE_S; do
    ws=$(make_ws "env-$variable") || return 1
    output=$(env TR_SPAWN_STEP="$MOCK" "$variable=not-an-integer" bash "$RUNNER" "$ws" 2>&1)
    rc=$?
    [ "$rc" -eq 2 ] || return 1
    printf '%s\n' "$output" | grep -Fq "$variable must be a non-negative integer" || return 1
    [ ! -e "$ws/loop/tasks/.tick.lock" ] || return 1
    [ ! -d "$ws/loop/artifacts" ] || return 1
  done
}

probe_corrupt_state() {
  local ws corrupt_state output rc
  ws=$(make_ws corrupt) || return 1
  ws=$(cd "$ws" && pwd -P) || return 1
  sed 's/^id: tr-basic$/id: corrupt-state/' "$FIX_BASIC" >"$ws/loop/tasks/queue/corrupt-state.task.md" || return 1
  sed 's/^id: tr-basic$/id: healthy-state/' "$FIX_BASIC" >"$ws/loop/tasks/queue/healthy-state.task.md" || return 1
  corrupt_state=$ws/loop/artifacts/corrupt-state/state.json
  mkdir -p "$(dirname "$corrupt_state")" || return 1
  printf '{not-json\n' >"$corrupt_state" || return 1
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$output" | grep -Fq 'corrupt state.json' || return 1
  printf '%s\n' "$output" | grep -Fq 'quarantined' || return 1
  [ "$(cat "$corrupt_state")" = '{not-json' ] || return 1
  [ -f "$ws/loop/tasks/queue/corrupt-state.task.md" ] || return 1
  [ ! -d "$ws/loop/artifacts/corrupt-state/attempts" ] || return 1
  [ -f "$ws/loop/tasks/delivered/healthy-state/healthy-state.task.md" ]
}

probe_quoted_id() {
  local ws task output rc artifact_count
  ws=$(make_ws quoted) || return 1
  task=$TMP_ROOT/quoted.task.md
  sed -e 's/^id: tr-basic$/id: "qt-1"/' -e 's/^time_budget_min: 5$/time_budget_min: 30/' "$FIX_BASIC" >"$task" || return 1
  "$ENQUEUE" "$task" "$ws" >/dev/null 2>&1 || return 1
  run_tick "$ws" TR_MOCK_BEHAVIOR=success >/dev/null 2>&1 || return 1
  artifact_count=$(find "$ws/loop/artifacts" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d '[:space:]')
  [ "$artifact_count" -eq 1 ] || return 1
  [ -d "$ws/loop/artifacts/qt-1" ] || return 1
  [ ! -e "$ws/loop/artifacts/\"qt-1\"" ] || return 1
  [ -f "$ws/loop/tasks/delivered/qt-1/qt-1.task.md" ] || return 1
  output=$("$ENQUEUE" "$task" "$ws" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] && printf '%s\n' "$output" | grep -Fq 'duplicate id'
}

probe_copy_failure() {
  local ws task shim real_cp output rc retry_output retry_rc
  ws=$(make_ws copy) || return 1
  task=$TMP_ROOT/copy-failure.task.md
  sed 's/^time_budget_min: 5$/time_budget_min: 30/' "$FIX_BASIC" >"$task" || return 1
  shim=$TMP_ROOT/cp-shim
  real_cp=$(command -v cp) || return 1
  mkdir -p "$shim" || return 1
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'if [ "${T23_FAIL_CP:-}" = 1 ]; then exit 1; fi'
    printf 'exec "%s" "$@"\n' "$real_cp"
  } >"$shim/cp" || return 1
  chmod +x "$shim/cp" || return 1
  output=$(PATH="$shim:$PATH" T23_FAIL_CP=1 "$ENQUEUE" "$task" "$ws" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$output" | grep -Fq 'failed to install task file' || return 1
  [ ! -e "$ws/loop/artifacts/tr-basic" ] || return 1
  [ ! -e "$ws/loop/tasks/queue/tr-basic.task.md" ] || return 1
  ! find "$ws/loop/tasks/queue" -name '.tr-basic.task.md.tmp.*' -print | grep -q . || return 1
  retry_output=$("$ENQUEUE" "$task" "$ws" 2>&1)
  retry_rc=$?
  [ "$retry_rc" -eq 0 ] || return 1
  [ -d "$ws/loop/artifacts/tr-basic" ] && [ -f "$ws/loop/tasks/queue/tr-basic.task.md" ]
}

probe_created_intake() {
  local ws task output rc
  ws=$(make_ws created-missing) || return 1
  task=$TMP_ROOT/missing-created.task.md
  sed '/^created:/d' "$FIX_BASIC" >"$task" || return 1
  output=$("$ENQUEUE" "$task" "$ws" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$output" | grep -Eiq 'created.*UTC|UTC.*created' || return 1

  ws=$(make_ws created-impossible) || return 1
  task=$TMP_ROOT/impossible-created.task.md
  sed 's/^created:.*/created: 2030-02-30T00:00:00Z/' "$FIX_BASIC" >"$task" || return 1
  output=$("$ENQUEUE" "$task" "$ws" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$output" | grep -Eiq 'created.*UTC|UTC.*created'
}

probe_created_scheduling() {
  local ws first_output second_output
  ws=$(make_ws created-scheduling) || return 1
  sed 's/^id: tr-basic$/id: valid-created/' "$FIX_BASIC" >"$ws/loop/tasks/queue/valid-created.task.md" || return 1
  sed -e 's/^id: tr-basic$/id: legacy-created/' -e '/^created:/d' "$FIX_BASIC" >"$ws/loop/tasks/queue/legacy-created.task.md" || return 1
  first_output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1) || return 1
  printf '%s\n' "$first_output" | grep -Fq 'invalid created' || return 1
  [ -f "$ws/loop/tasks/delivered/valid-created/valid-created.task.md" ] || return 1
  [ -f "$ws/loop/tasks/queue/legacy-created.task.md" ] || return 1
  [ ! -e "$ws/loop/artifacts/legacy-created/state.json" ] || return 1
  second_output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1) || return 1
  printf '%s\n' "$second_output" | grep -Fq 'invalid created' || return 1
  [ -f "$ws/loop/tasks/delivered/legacy-created/legacy-created.task.md" ] || return 1
  [ "$(state_value "$ws/loop/artifacts/legacy-created/state.json" status)" = delivered ]
}

case ${1:-} in
  corrupt-state) probe_corrupt_state ;;
  quoted-id) probe_quoted_id ;;
  copy-failure) probe_copy_failure ;;
  created-intake) probe_created_intake ;;
  created-scheduling) probe_created_scheduling ;;
  env-integers) probe_env_integers ;;
  *) exit 2 ;;
esac
