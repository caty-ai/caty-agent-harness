#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNNER="$ROOT/scripts/task-runner.sh"
ENQUEUE="$ROOT/scripts/tr-enqueue"
METRICS="$ROOT/scripts/tr-metrics.sh"
MOCK="$ROOT/tests/fixtures/mock-spawn-step.sh"
FIX_BASIC="$ROOT/tests/fixtures/task-basic.task.md"
FIX_TINY="$ROOT/tests/fixtures/task-tiny-budget.task.md"
FIX_ATTEMPTS="$ROOT/tests/fixtures/task-attempts-budget.task.md"
FIX_TIME_BOUNDARY="$ROOT/tests/fixtures/task-time-boundary.task.md"
FIX_FAILING_LINE="$ROOT/tests/fixtures/task-dlq-failing-line.task.md"

pass_count=0
fail_count=0

source "$ROOT/tests/lib-wrapper-conformance-fixture.sh"

log() {
  printf '%s\n' "$*"
}

pass() {
  pass_count=$(( pass_count + 1 ))
  log "PASS $1"
}

fail() {
  fail_count=$(( fail_count + 1 ))
  log "FAIL $1: $2"
}

make_ws() {
  local ws
  ws=$(mktemp -d "${TMPDIR:-/tmp}/tr-test.XXXXXX")
  mkdir -p "$ws/loop/tasks/queue"
  printf '# State\n' >"$ws/STATE.md"
  printf '%s\n' "$ws"
}

copy_task() {
  local src=$1
  local ws=$2
  local id=$3
  cp "$src" "$ws/loop/tasks/queue/$id.task.md"
}

write_runner_task() {
  local ws=$1
  local id=$2
  local receipt_value=$3
  local donecheck_body=${4:-true}
  {
    printf '%s\n' '---'
    printf 'id: %s\n' "$id"
    printf '%s\n' 'title: runner boundary fixture'
    printf '%s\n' 'issued_by: test'
    printf '%s\n' 'created: 2026-08-12T00:00:00Z'
    printf '%s\n' 'attempts_budget: 4'
    printf '%s\n' 'time_budget_min: 30'
    printf '%s\n' 'escalate_to: test'
    printf '%s\n' 'verify: mechanical'
    printf '%s\n' 'parent_id: null'
    if [[ "$receipt_value" != __missing__ ]]; then
      printf 'receipt: %s\n' "$receipt_value"
    fi
    printf '%s\n\n' '---'
    printf '%s\n\n' '## Goal' 'Exercise a runner execution boundary.'
    printf '%s\n' '## Done-when' '```donecheck'
    printf '%s\n' "$donecheck_body"
    printf '%s\n\n' '```'
    printf '%s\n' '## Step plan' '1. Produce the test artifact.' '2. Deliver + capture receipt.' ''
    printf '%s\n\n' '## Resources' 'none'
    printf '%s\n' '## Non-goals' 'none'
  } >"$ws/loop/tasks/queue/$id.task.md"
}

state_value() {
  local ws=$1
  local id=$2
  local key=$3
  python3 - "$ws/loop/artifacts/$id/state.json" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data
for part in sys.argv[2].split("."):
    value = value.get(part)
print("" if value is None else value)
PY
}

driver_value() {
  local ws=$1
  local id=$2
  local key=$3
  python3 - "$ws/loop/artifacts/$id/attempts/001/driver.json" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f).get(sys.argv[2])
print("" if value is None else value)
PY
}

infra_driver_value() {
  local ws=$1
  local id=$2
  local retry=$3
  local key=$4
  python3 - "$ws/loop/artifacts/$id/attempts-infra/001.infra-$retry/driver.json" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f).get(sys.argv[2])
print("" if value is None else value)
PY
}

file_mode() {
  # GNU first: on GNU coreutils `stat -f` does not fail — it prints filesystem
  # status — so the BSD-first order silently returns garbage on Linux.
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

run_tick() {
  local ws=$1
  shift
  env TR_SPAWN_STEP="$MOCK" "$@" bash "$RUNNER" "$ws"
}

run_tick_with_step() {
  local ws=$1
  local step_cmd=$2
  shift 2
  env TR_SPAWN_STEP="$step_cmd" "$@" bash "$RUNNER" "$ws"
}

ledger_event_count() {
  local ledger=$1
  local event=$2
  python3 - "$ledger" "$event" <<'PY'
import json, sys
count = 0
try:
    source = open(sys.argv[1], encoding="utf-8")
except OSError:
    print(0)
    raise SystemExit
with source:
    for line in source:
        try:
            record = json.loads(line)
        except ValueError:
            continue
        count += record.get("event") == sys.argv[2]
print(count)
PY
}

receipt_value() {
  local receipt_file=$1
  local key=$2
  python3 - "$receipt_file" "$key" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    value = value.get(part)
print("" if value is None else str(value).lower() if isinstance(value, bool) else value)
PY
}

write_terminal_ledger_fixture() {
  local ws=$1
  local id=$2
  local terminal_status=${3:-delivered}
  local reason=${4:-}
  local classified=${5:-}
  local artifact="$ws/loop/artifacts/$id"
  mkdir -p "$artifact/attempts/001"
  python3 - "$artifact/state.json" "$terminal_status" "$reason" <<'PY'
import json, sys
json.dump({
    "status": sys.argv[2], "current_step": 1, "attempts_used": 1,
    "active_seconds_used": 1, "infra_retries": 0, "consec_noncomplete": 0,
    "last_error_class": None, "last_gap_fingerprint": None,
    "last_gap_step": None, "lease": None,
    "terminal_reason": sys.argv[3] or None,
}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  python3 - "$artifact/attempts/001/driver.json" "$classified" <<'PY'
import json, sys
value = {"started":"2026-08-27T00:00:00Z", "ended":"2026-08-27T00:00:01Z", "dur_s":1, "outcome":"ok", "exit_code":0}
if sys.argv[2]: value["classified"] = sys.argv[2]
json.dump(value, open(sys.argv[1], "w", encoding="utf-8"))
PY
  printf '{"event":"init","ledger_schema":1,"task_id":"%s"}\n' "$id" >"$artifact/ledger.jsonl"
}

set_terminal_lease() {
  local state_file=$1
  local pid=${2:-}
  python3 - "$state_file" "$pid" <<'PY'
import json, sys
path, pid = sys.argv[1:3]
value = json.load(open(path, encoding="utf-8"))
value["lease"] = ({"pid": int(pid), "pgid": int(pid), "started": "2026-08-27T00:00:00Z"} if pid else None)
with open(path, "w", encoding="utf-8") as target:
    json.dump(value, target)
    target.write("\n")
PY
}

write_paused_step() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'status=paused workspace=%s entrypoint=%s\n' "$2" hermes-spawn-step >&2
exit 0
SH
  chmod +x "$path"
}

write_overflow_paused_step() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'status=paused workspace=%s entrypoint=%s\n' "$2" overflow-spawn-step >&2
exit 0
SH
  chmod +x "$path"
}

write_invalid_pause_label_step() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'status=paused workspace=%s entrypoint=%s\n' "$2" evil-step >&2
exit 0
SH
  chmod +x "$path"
}

write_nonpause_status_step() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'status=paused workspace=%s entrypoint=%s extra=bad\n' "$2" hermes-spawn-step >&2
exit 0
SH
  chmod +x "$path"
}

write_permission_error_step() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"type":"error","error":{"type":"permission_error","message":"Your API key does not have permission to use the specified resource."}}' >&2
exit 1
SH
  chmod +x "$path"
}

write_verify_record() {
  local path=$1
  local verdict=$2
  local step=$3
  local reason=$4
  python3 - "$path" "$verdict" "$step" "$reason" <<'PY'
import json
import sys

path, verdict, step_text, reason = sys.argv[1:5]
step = None if step_text == "null" else int(step_text)
with open(path, "w", encoding="utf-8") as f:
    json.dump(
        {
            "verdict": verdict,
            "reason": reason,
            "verifier_id": "fixture",
            "step": step,
            "ts": "2026-07-22T00:00:00Z",
        },
        f,
        indent=2,
        sort_keys=True,
    )
    f.write("\n")
PY
}

case_env_integer_validation() {
  local name=env-integer-validation
  local variable invalid_value validation_case ws output code
  for variable in TR_STEP_TIMEOUT_S TR_GRACE_S TR_DONECHECK_TIMEOUT_S TR_GATE_REPLAY_MAX_BYTES; do
    for invalid_value in abc ''; do
      ws=$(make_ws)
      set +e
      output=$(run_tick "$ws" "${variable}=$invalid_value" 2>&1)
      code=$?
      set -e
      if [[ "$code" -ne 2 ]] \
        || ! grep -F -q "$variable must be a non-negative integer: value=$invalid_value" <<<"$output" \
        || [[ -e "$ws/loop/tasks/.tick.lock" ]] \
        || [[ -d "$ws/loop/artifacts" ]]; then
        fail "$name-$variable" "value='$invalid_value' rc=$code output=$output"
        return
      fi
    done
  done

  for validation_case in TR_STEP_TIMEOUT_S=08 TR_GRACE_S=010 TR_DONECHECK_TIMEOUT_S=060 TR_GATE_REPLAY_MAX_BYTES=0600; do
    variable=${validation_case%%=*}
    invalid_value=${validation_case#*=}
    ws=$(make_ws)
    set +e
    output=$(run_tick "$ws" "$validation_case" 2>&1)
    code=$?
    set -e
    if [[ "$code" -ne 2 ]] \
      || ! grep -F -q "$variable must be a non-negative integer: value=$invalid_value" <<<"$output" \
      || [[ -e "$ws/loop/tasks/.tick.lock" ]] \
      || [[ -d "$ws/loop/artifacts" ]]; then
      fail "$name-$variable" "value='$invalid_value' rc=$code output=$output"
      return
    fi
  done

  ws=$(make_ws)
  set +e
  output=$(run_tick "$ws" TR_STEP_TIMEOUT_S=1 TR_GRACE_S=0 TR_DONECHECK_TIMEOUT_S=0 TR_GATE_REPLAY_MAX_BYTES=0 2>&1)
  code=$?
  set -e
  if [[ "$code" -ne 0 ]] || grep -F -q 'must be a non-negative integer' <<<"$output"; then
    fail "$name-zero" "rc=$code output=$output"
    return
  fi
  pass "$name"
}

case_startup_ordering_validation() {
  local name=startup-ordering-validation
  local ws output code mutated_root mutated_runner

  ws=$(make_ws)
  set +e
  output=$(run_tick "$ws" TR_STEP_TIMEOUT_S=30 TR_GRACE_S=30 2>&1)
  code=$?
  set -e
  if [[ "$code" -ne 2 ]] \
    || ! grep -Fq 'task-runner.sh: ordering invariant failed: TR_GRACE_S(value=30) < TR_STEP_TIMEOUT_S(value=30)' <<<"$output" \
    || [[ -e "$ws/loop/tasks/.tick.lock" ]] \
    || [[ -d "$ws/loop/artifacts" ]]; then
    fail "$name-TR_GRACE_S-TR_STEP_TIMEOUT_S" "rc=$code output=$output"
    return
  fi

  ws=$(make_ws)
  mutated_root=$(mktemp -d "${TMPDIR:-/tmp}/tr-mutated-root.XXXXXX")
  mkdir -p "$mutated_root/scripts"
  mutated_runner="$mutated_root/scripts/task-runner.sh"
  sed 's/^TR_PERSISTENT_FAILURE_THRESHOLD=2$/TR_PERSISTENT_FAILURE_THRESHOLD=0/' \
    "$RUNNER" >"$mutated_runner"
  chmod +x "$mutated_runner"
  set +e
  output=$(TR_SPAWN_STEP="$MOCK" bash "$mutated_runner" "$ws" 2>&1)
  code=$?
  set -e
  rm -rf "$mutated_root"
  if [[ "$code" -ne 2 ]] \
    || ! grep -Fq 'task-runner.sh: TR_PERSISTENT_FAILURE_THRESHOLD must be greater than zero: value=0' <<<"$output" \
    || [[ -e "$ws/loop/tasks/.tick.lock" ]] \
    || [[ -d "$ws/loop/artifacts" ]]; then
    fail "$name-TR_PERSISTENT_FAILURE_THRESHOLD" "rc=$code output=$output"
    return
  fi

  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success >/dev/null \
    && [[ -f "$ws/loop/tasks/delivered/tr-basic/tr-basic.task.md" ]]; then
    pass "$name"
  else
    fail "$name" 'valid defaults did not complete the entry path'
  fi
}

case_corrupt_state_quarantine_continues() {
  local name=corrupt-state-quarantine-continues
  local ws corrupt_state output code warning_count state_after
  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  sed 's/^id: tr-basic$/id: corrupt-state/' "$FIX_BASIC" >"$ws/loop/tasks/queue/corrupt-state.task.md"
  sed 's/^id: tr-basic$/id: healthy-state/' "$FIX_BASIC" >"$ws/loop/tasks/queue/healthy-state.task.md"
  corrupt_state="$ws/loop/artifacts/corrupt-state/state.json"
  mkdir -p "$(dirname "$corrupt_state")"
  printf '{not-json\n' >"$corrupt_state"

  set +e
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  code=$?
  set -e
  warning_count=$(grep -F -c "corrupt state.json, quarantined: $corrupt_state" <<<"$output" || true)
  state_after=$(cat "$corrupt_state")
  if [[ "$code" -eq 1 ]] \
    && [[ "$warning_count" -eq 4 ]] \
    && grep -F -q "warning: reconcile_terminals: corrupt state.json, quarantined: $corrupt_state" <<<"$output" \
    && grep -F -q "warning: recover_verifying: corrupt state.json, quarantined: $corrupt_state" <<<"$output" \
    && grep -F -q "warning: reap_running: corrupt state.json, quarantined: $corrupt_state" <<<"$output" \
    && grep -F -q "warning: pick_oldest_queued: corrupt state.json, quarantined: $corrupt_state" <<<"$output" \
    && [[ "$state_after" = '{not-json' ]] \
    && [[ -f "$ws/loop/tasks/queue/corrupt-state.task.md" ]] \
    && [[ ! -d "$ws/loop/artifacts/corrupt-state/attempts" ]] \
    && [[ -f "$ws/loop/tasks/delivered/healthy-state/healthy-state.task.md" ]] \
    && [[ "$(state_value "$ws" healthy-state status)" = delivered ]] \
    && [[ ! -e "$ws/loop/tasks/.tick.lock" ]]; then
    pass "$name"
  else
    fail "$name" "rc=$code warnings=$warning_count corrupt_state=$state_after output=$output"
  fi
}

case_quoted_id_intake_runner_agree() {
  local name=quoted-id-intake-runner-agree
  local ws task output code artifact_count
  ws=$(make_ws)
  task="$ws/quoted.task.md"
  sed -e 's/^id: tr-basic$/id: "qt-1"/' -e 's/^time_budget_min: 5$/time_budget_min: 30/' "$FIX_BASIC" >"$task"
  if ! "$ENQUEUE" "$task" "$ws" >/dev/null 2>&1; then
    fail "$name" "quoted id was rejected by intake"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  artifact_count=$(find "$ws/loop/artifacts" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d '[:space:]')
  set +e
  output=$("$ENQUEUE" "$task" "$ws" 2>&1)
  code=$?
  set -e
  if [[ "$artifact_count" -eq 1 ]] \
    && [[ -d "$ws/loop/artifacts/qt-1" ]] \
    && [[ ! -e "$ws/loop/artifacts/\"qt-1\"" ]] \
    && [[ -f "$ws/loop/tasks/delivered/qt-1/qt-1.task.md" ]] \
    && [[ "$code" -eq 1 ]] \
    && grep -F -q 'duplicate id' <<<"$output"; then
    pass "$name"
  else
    fail "$name" "artifacts=$artifact_count duplicate_rc=$code output=$output"
  fi
}

case_invalid_created_sorts_last() {
  local name=invalid-created-sorts-last
  local ws first_output second_output first_count second_count
  ws=$(make_ws)
  sed 's/^id: tr-basic$/id: valid-created/' "$FIX_BASIC" >"$ws/loop/tasks/queue/valid-created.task.md"
  sed -e 's/^id: tr-basic$/id: legacy-created/' -e '/^created:/d' "$FIX_BASIC" >"$ws/loop/tasks/queue/legacy-created.task.md"

  first_output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  first_count=$(grep -F -c 'warning: pick_oldest_queued: invalid created for task legacy-created:' <<<"$first_output" || true)
  if [[ "$first_count" -ne 1 ]] \
    || [[ ! -f "$ws/loop/tasks/delivered/valid-created/valid-created.task.md" ]] \
    || [[ ! -f "$ws/loop/tasks/queue/legacy-created.task.md" ]] \
    || [[ -e "$ws/loop/artifacts/legacy-created/state.json" ]]; then
    fail "$name" "legacy task did not sort after valid task: output=$first_output"
    return
  fi

  second_output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  second_count=$(grep -F -c 'warning: pick_oldest_queued: invalid created for task legacy-created:' <<<"$second_output" || true)
  if [[ "$second_count" -eq 1 ]] \
    && [[ -f "$ws/loop/tasks/delivered/legacy-created/legacy-created.task.md" ]] \
    && [[ "$(state_value "$ws" legacy-created status)" = delivered ]]; then
    pass "$name"
  else
    fail "$name" "legacy task did not run after valid task: output=$second_output"
  fi
}

case_trailing_comment_created_parity() {
  local name=trailing-comment-created-parity
  local ws older_task later_task output
  ws=$(make_ws)
  older_task="$ws/older.task.md"
  later_task="$ws/later.task.md"
  sed \
    -e 's/^id: tr-basic$/id: z-comment-created/' \
    -e 's/^created:.*/created: "2026-01-01T00:00:00Z" # ts/' \
    -e 's/^time_budget_min: 5$/time_budget_min: 30/' \
    "$FIX_BASIC" >"$older_task"
  sed \
    -e 's/^id: tr-basic$/id: a-later-created/' \
    -e 's/^created:.*/created: "2026-02-01T00:00:00Z"/' \
    -e 's/^time_budget_min: 5$/time_budget_min: 30/' \
    "$FIX_BASIC" >"$later_task"

  if ! "$ENQUEUE" "$older_task" "$ws" >/dev/null 2>&1 \
    || ! "$ENQUEUE" "$later_task" "$ws" >/dev/null 2>&1; then
    fail "$name" "intake rejected a valid commented created value"
    return
  fi

  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  if [[ -f "$ws/loop/tasks/delivered/z-comment-created/z-comment-created.task.md" ]] \
    && [[ -f "$ws/loop/tasks/queue/a-later-created.task.md" ]] \
    && ! grep -F -q 'invalid created' <<<"$output"; then
    pass "$name"
  else
    fail "$name" "commented timestamp did not sort first without warning: output=$output"
  fi
}

case_duplicate_id_scheduler_parser_parity() {
  local name=duplicate-id-scheduler-parser-parity
  local ws task
  ws=$(make_ws)

  write_runner_task "$ws" scheduler-shadow out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=success

  write_runner_task "$ws" scheduler-first out/delivery-receipt.json true
  task="$ws/loop/tasks/queue/scheduler-first.task.md"
  sed '/^id: scheduler-first$/a\
id: scheduler-shadow' "$task" >"$task.tmp"
  mv "$task.tmp" "$task"

  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" scheduler-first status)" = delivered ]] \
    && [[ "$(state_value "$ws" scheduler-first attempts_used)" = 1 ]] \
    && [[ -f "$ws/loop/tasks/delivered/scheduler-first/scheduler-first.task.md" ]] \
    && [[ ! -e "$task" ]]; then
    pass "$name"
  else
    fail "$name" 'scheduler did not use the same first id value as the runner'
  fi
}

attest_verifier_wrapper() {
  local ws=$1
  local wrapper_path=$2
  local name=$3
  local provider_path=$ws/$name-provider.sh
  local probe_path=$ws/$name-probe.sh

  conformance_write_provider "$provider_path"
  conformance_write_probe "$probe_path"
  conformance_attest_wrapper "$ROOT" verifier "$wrapper_path" "$provider_path" "$probe_path" "fixture-$name" "fixture-$name-v1"
}

case_happy_path() {
  local name=happy-path
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success && [[ -f "$ws/loop/tasks/delivered/tr-basic/tr-basic.task.md" ]] && [[ "$(state_value "$ws" tr-basic status)" = delivered ]]; then
    pass "$name"
  else
    fail "$name" "task was not delivered"
  fi
}

case_receipt_file_boundary() {
  local name=receipt-file-boundary
  local ws reason

  ws=$(make_ws)
  write_runner_task "$ws" receipt-missing out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-valid
  reason="$ws/loop/artifacts/receipt-missing/attempts/001/verify-reason"
  if [[ "$(state_value "$ws" receipt-missing status)" = queued ]] \
    && [[ -f "$reason" ]] \
    && grep -Fqx 'delivery receipt missing or invalid: out/delivery-receipt.json' "$reason" \
    && [[ ! -d "$ws/loop/tasks/delivered/receipt-missing" ]]; then
    :
  else
    fail "$name" 'donecheck rc=0 with a missing receipt was delivered or lacked verify-reason'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" receipt-symlink out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=receipt-symlink
  if [[ "$(state_value "$ws" receipt-symlink status)" != queued ]] \
    || [[ -d "$ws/loop/tasks/delivered/receipt-symlink" ]]; then
    fail "$name" 'symlink receipt passed the delivery gate'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" receipt-parent-symlink out/link/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=receipt-parent-symlink
  if [[ "$(state_value "$ws" receipt-parent-symlink status)" != queued ]] \
    || [[ -d "$ws/loop/tasks/delivered/receipt-parent-symlink" ]]; then
    fail "$name" 'resolved receipt path escaped through a parent symlink'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" receipt-out-symlink out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=receipt-out-symlink
  reason="$ws/loop/artifacts/receipt-out-symlink/attempts/001/verify-reason"
  if [[ "$(state_value "$ws" receipt-out-symlink status)" != queued ]] \
    || [[ -d "$ws/loop/tasks/delivered/receipt-out-symlink" ]] \
    || [[ ! -f "$reason" ]] \
    || ! grep -Fqx 'delivery receipt missing or invalid: out/delivery-receipt.json' "$reason"; then
    fail "$name" 'artifact out symlink moved the delivery containment root'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" receipt-directory out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=receipt-directory
  if [[ "$(state_value "$ws" receipt-directory status)" = queued ]] \
    && [[ ! -d "$ws/loop/tasks/delivered/receipt-directory" ]] \
    && grep -Fqx 'delivery receipt missing or invalid: out/delivery-receipt.json' \
      "$ws/loop/artifacts/receipt-directory/attempts/001/verify-reason"; then
    pass "$name"
  else
    fail "$name" 'directory receipt passed the regular-file delivery gate'
  fi
}

case_missing_receipt_dlq_before_spawn() {
  local name=missing-receipt-dlq-before-spawn
  local ws
  ws=$(make_ws)
  write_runner_task "$ws" missing-receipt __missing__ true
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" missing-receipt status)" = dlq ]] \
    && [[ "$(state_value "$ws" missing-receipt terminal_reason)" = missing-receipt ]] \
    && [[ -f "$ws/loop/tasks/dlq/missing-receipt/missing-receipt.task.md" ]] \
    && ! find "$ws/loop/artifacts/missing-receipt/attempts" -mindepth 1 -print | grep -q .; then
    :
  else
    fail "$name" 'missing receipt metadata did not DLQ before a model attempt'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" invalid-receipt out/../escape true
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" invalid-receipt status)" = dlq ]] \
    && [[ "$(state_value "$ws" invalid-receipt terminal_reason)" = missing-receipt ]] \
    && ! find "$ws/loop/artifacts/invalid-receipt/attempts" -mindepth 1 -print | grep -q .; then
    :
  else
    fail "$name" 'grammar-invalid receipt metadata did not DLQ before a model attempt'
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" recover-missing-receipt out/delivery-receipt.json true
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=verifying >/dev/null 2>&1
  set -e
  sed '/^receipt:/d' "$ws/loop/tasks/queue/recover-missing-receipt.task.md" \
    >"$ws/loop/tasks/queue/recover-missing-receipt.task.md.tmp"
  mv "$ws/loop/tasks/queue/recover-missing-receipt.task.md.tmp" \
    "$ws/loop/tasks/queue/recover-missing-receipt.task.md"
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" recover-missing-receipt status)" = dlq ]] \
    && [[ "$(state_value "$ws" recover-missing-receipt terminal_reason)" = missing-receipt ]] \
    && [[ ! -e "$ws/loop/artifacts/recover-missing-receipt/attempts/001/donecheck.log" ]]; then
    pass "$name"
  else
    fail "$name" 'recover_verifying reran donecheck before DLQing missing receipt metadata'
  fi
}

case_receipt_frontmatter_parser_parity() {
  local name=receipt-frontmatter-parser-parity
  local ws task
  for receipt_value in '"out/delivery-receipt.json"' 'out/delivery-receipt.json # runner parity'; do
    ws=$(make_ws)
    task="$ws/source.task.md"
    write_runner_task "$ws" receipt-parity "$receipt_value" true
    mv "$ws/loop/tasks/queue/receipt-parity.task.md" "$task"
    if ! "$ENQUEUE" "$task" "$ws" >/dev/null 2>&1; then
      fail "$name" "enqueue rejected receipt value: $receipt_value"
      return
    fi
    run_tick "$ws" TR_MOCK_BEHAVIOR=success
    if [[ "$(state_value "$ws" receipt-parity status)" != delivered ]]; then
      fail "$name" "runner disagreed with enqueue for receipt value: $receipt_value"
      return
    fi
  done
  pass "$name"
}

case_donecheck_environment_allowlist() {
  local name=donecheck-environment-allowlist
  local ws log_file unexpected_tr no_home_log
  ws=$(make_ws)
  write_runner_task "$ws" env-allow out/delivery-receipt.json 'env | sort'
  HOME="$ws/home" TR_SENTINEL_CANARY=x TR_PUSH_CMD=should-not-leak \
    run_tick "$ws" TR_MOCK_BEHAVIOR=success LANG=C LC_ALL=C TZ=UTC
  log_file="$ws/loop/artifacts/env-allow/attempts/001/donecheck.log"
  unexpected_tr=$(grep '^TR_' "$log_file" | grep -v '^TR_DC_CWD=' || true)
  if [[ "$(state_value "$ws" env-allow status)" = delivered ]] \
    && grep -Fqx 'TASK_ID=env-allow' "$log_file" \
    && grep -Fq 'TASK_FILE=' "$log_file" \
    && grep -Fq 'ARTIFACT_DIR=' "$log_file" \
    && grep -Fq 'TR_DC_CWD=' "$log_file" \
    && grep -Fqx 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$log_file" \
    && grep -Fqx "HOME=$ws/home" "$log_file" \
    && grep -Fqx 'LANG=C' "$log_file" \
    && grep -Fqx 'LC_ALL=C' "$log_file" \
    && grep -Fqx 'TZ=UTC' "$log_file" \
    && ! grep -q '^TR_SENTINEL_CANARY=' "$log_file" \
    && ! grep -q '^TR_PUSH_CMD=' "$log_file" \
    && [[ -z "$unexpected_tr" ]] \
    && grep -q '^PWD=' "$log_file" \
    && grep -q '^SHLVL=' "$log_file" \
    && grep -q '^_=' "$log_file"; then
    :
  else
    fail "$name" "allowlist or shell-created variable contract mismatch: unexpected_tr=$unexpected_tr log=$(cat "$log_file")"
    return
  fi

  ws=$(make_ws)
  write_runner_task "$ws" env-no-home out/delivery-receipt.json 'env | sort'
  env -u HOME TR_SPAWN_STEP="$MOCK" TR_MOCK_BEHAVIOR=success bash "$RUNNER" "$ws"
  no_home_log="$ws/loop/artifacts/env-no-home/attempts/001/donecheck.log"
  if [[ "$(state_value "$ws" env-no-home status)" = delivered ]] \
    && ! grep -q '^HOME=' "$no_home_log"; then
    pass "$name"
  else
    fail "$name" "unset HOME was supplied to donecheck: log=$(cat "$no_home_log")"
  fi
}

case_donecheck_uses_pinned_interpreters() {
  local name=donecheck-uses-pinned-interpreters
  local ws fake_bash fake_perl bash_marker perl_marker
  ws=$(make_ws)
  fake_bash="$ws/fake-bash"
  fake_perl="$ws/fake-perl"
  bash_marker="$ws/bash-args"
  perl_marker="$ws/perl-args"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >%q\n' "$bash_marker"
    printf 'exec %q "$@"\n' "$(command -v bash)"
  } >"$fake_bash"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >%q\n' "$perl_marker"
    printf 'exec %q "$@"\n' "$(command -v perl)"
  } >"$fake_perl"
  chmod +x "$fake_bash" "$fake_perl"
  printf 'TR_BASH=%s\nTR_PERL=%s\n' "$fake_bash" "$fake_perl" \
    >"$ws/loop/.tr-interpreters"
  write_runner_task "$ws" pinned-interpreters out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" pinned-interpreters status)" = delivered ]] \
    && grep -Fq -- '-euo pipefail' "$bash_marker" \
    && grep -Fq -- '-MPOSIX=setsid' "$perl_marker"; then
    pass "$name"
  else
    fail "$name" "pinned launch not observed: bash=$(cat "$bash_marker" 2>/dev/null) perl=$(cat "$perl_marker" 2>/dev/null)"
  fi
}

case_recover_verifying_receipt_boundary() {
  local name=recover-verifying-receipt-boundary
  local ws
  ws=$(make_ws)
  write_runner_task "$ws" recover-receipt out/delivery-receipt.json true
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-valid TR_CRASH_AFTER=verifying >/dev/null 2>&1
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-valid
  if [[ ! -d "$ws/loop/tasks/delivered/recover-receipt" ]] \
    && grep -Fqx 'delivery receipt missing or invalid: out/delivery-receipt.json' \
      "$ws/loop/artifacts/recover-receipt/attempts/001/verify-reason"; then
    pass "$name"
  else
    fail "$name" 'recover_verifying delivered without a valid regular receipt'
  fi
}

case_missing_donecheck_never_delivers() {
  local name=missing-donecheck-never-delivers
  local ws task
  ws=$(make_ws)
  write_runner_task "$ws" missing-donecheck out/delivery-receipt.json true
  task="$ws/loop/tasks/queue/missing-donecheck.task.md"
  sed 's/^```donecheck$/```donecheck extra/' "$task" >"$task.tmp"
  mv "$task.tmp" "$task"
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" missing-donecheck status)" = queued ]] \
    && [[ ! -d "$ws/loop/tasks/delivered/missing-donecheck" ]] \
    && grep -Fqx 'missing donecheck block' \
      "$ws/loop/artifacts/missing-donecheck/attempts/001/verify-reason"; then
    pass "$name"
  else
    fail "$name" 'queue-dropped task without a valid donecheck was delivered'
  fi
}

case_success_next_hint_surface() {
  local name=success-next-hint-surface
  local ws root result progress
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  result="$root/attempts/001/step-result.json"
  progress="$root/PROGRESS.md"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if grep -F -q '"next_hint": "done"' "$result" \
    && grep -F -q '## Successful-step advisory hints' "$progress" \
    && grep -F -q -- '- 001: "done"' "$progress" \
    && [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ "$(state_value "$ws" tr-basic current_step)" = 2 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ -z "$(state_value "$ws" tr-basic terminal_reason)" ]]; then
    pass "$name"
  else
    fail "$name" "successful hint exists in step-result.json but is not surfaced in PROGRESS.md"
  fi
}

case_success_next_hint_null_empty_omitted() {
  local name=success-next-hint-null-empty-omitted
  local ws_empty ws_null progress_empty progress_null
  ws_empty=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_empty" tr-basic
  run_tick "$ws_empty" TR_MOCK_BEHAVIOR=success TR_MOCK_NEXT_HINT=
  progress_empty="$ws_empty/loop/artifacts/tr-basic/PROGRESS.md"

  ws_null=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_null" tr-basic
  run_tick "$ws_null" TR_MOCK_BEHAVIOR=success TR_MOCK_NEXT_HINT_NULL=1
  progress_null="$ws_null/loop/artifacts/tr-basic/PROGRESS.md"

  if grep -F -q '"next_hint": ""' "$ws_empty/loop/artifacts/tr-basic/attempts/001/step-result.json" \
    && grep -F -q '"next_hint": null' "$ws_null/loop/artifacts/tr-basic/attempts/001/step-result.json" \
    && ! grep -F -q '## Successful-step advisory hints' "$progress_empty" \
    && ! grep -F -q '## Successful-step advisory hints' "$progress_null"; then
    pass "$name"
  else
    fail "$name" "null or empty successful hint created an advisory surface"
  fi
}

case_failed_next_hint_stays_retry_only() {
  local name=failed-next-hint-stays-retry-only
  local ws prompt progress first_error key_name hint
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  key_name=api_key
  hint="${key_name}"$'=retry-secret /home/alice/work retry carefully\nsecond line must not replay'
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth TR_MOCK_NEXT_HINT="$hint" || true
  first_error=$(state_value "$ws" tr-basic last_error_class)
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=tool-misuse TR_MOCK_NEXT_HINT=unused || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  progress="$ws/loop/artifacts/tr-basic/PROGRESS.md"
  if [[ "$first_error" = auth ]] \
    && grep -F -q 'error_class: auth' "$prompt" \
    && grep -F -q "summary: ${key_name}=<redacted> <path> retry carefully" "$prompt" \
    && grep -q 'recovery: .*credentials/auth state before retrying' "$prompt" \
    && ! grep -F -q 'second line must not replay' "$prompt" \
    && ! grep -F -q '## Successful-step advisory hints' "$progress"; then
    pass "$name"
  else
    fail "$name" "failure hint changed retry classification or leaked into the success surface"
  fi
}

case_success_next_hint_bound_and_redaction() {
  local name=success-next-hint-bound-redaction
  local ws result progress padding bidi aws_key github_key hint
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  padding=$(awk 'BEGIN { for (i = 0; i < 80; i++) printf "word " }')
  bidi=$(printf '\342\200\256')
  aws_key="AWS_SECRET_ACCESS_""KEY"
  github_key="GH_""TOKEN"
  hint="${aws_key}=surface-secret ${github_key}=github-secret /home/alice/private/file.txt ${bidi}abcdefghijklmnopqrstuvwxyz0123456789ABCD ${padding}"
  hint="${hint}"$'\nsecond line must not surface'
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_MOCK_NEXT_HINT="$hint"
  result="$ws/loop/artifacts/tr-basic/attempts/001/step-result.json"
  progress="$ws/loop/artifacts/tr-basic/PROGRESS.md"
  if grep -F -q 'surface-secret' "$result" \
    && grep -F -q 'github-secret' "$result" \
    && grep -F -q '\u202e' "$result" \
    && grep -F -q 'abcdefghijklmnopqrstuvwxyz0123456789ABCD' "$result" \
    && grep -F -q '/home/alice/private/file.txt' "$result" \
    && grep -F -q "${aws_key}=<redacted>" "$progress" \
    && grep -F -q "${github_key}=<redacted>" "$progress" \
    && grep -F -q '<path>' "$progress" \
    && ! grep -F -q 'surface-secret' "$progress" \
    && ! grep -F -q 'github-secret' "$progress" \
    && ! grep -F -q '\u202e' "$progress" \
    && ! grep -F -q 'abcdefghijklmnopqrstuvwxyz0123456789ABCD' "$progress" \
    && ! grep -F -q '/home/alice/private/file.txt' "$progress" \
    && ! grep -F -q 'second line must not surface' "$progress" \
    && python3 - "$progress" <<'PY'
import json, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
payload = next(line.split(": ", 1)[1] for line in lines if line.startswith('- 001: "'))
hint = json.loads(payload)
assert len(hint) <= 160
assert hint.endswith("...")
PY
  then
    pass "$name"
  else
    fail "$name" "successful hint was not single-line, bounded, and redacted"
  fi
}

case_success_next_hint_dedup_and_cap() {
  local name=success-next-hint-dedup-cap
  local ws progress hint advisory_count
  local hints=(old-one old-two old-three repeated repeated newest)
  ws=$(make_ws)
  sed 's/^attempts_budget: 4$/attempts_budget: 6/' "$FIX_BASIC" >"$ws/loop/tasks/queue/tr-basic.task.md"
  for hint in "${hints[@]}"; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=claim-valid TR_MOCK_NEXT_HINT="$hint" || true
  done
  progress="$ws/loop/artifacts/tr-basic/PROGRESS.md"
  advisory_count=$(awk '
    /^## Successful-step advisory hints$/ { inside=1; next }
    /^## / { inside=0 }
    inside && /^- / { count++ }
    END { print count + 0 }
  ' "$progress")
  if [[ "$advisory_count" = 3 ]] \
    && grep -F -q -- '- 005: "repeated" (repeated 2 times)' "$progress" \
    && grep -F -q -- '- 006: "newest"' "$progress" \
    && grep -F -q -- '- 003: "old-three"' "$progress" \
    && ! grep -F -q '"old-one"' "$progress" \
    && ! grep -F -q '"old-two"' "$progress"; then
    pass "$name"
  else
    fail "$name" "successful hints were not deduplicated and capped to the three most recent unique values"
  fi
}

case_next_hint_is_not_deviation_control() {
  local name=next-hint-is-not-deviation-control
  local ws_hint ws_deviation report i
  ws_hint=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_hint" tr-basic
  for i in 1 2 3; do
    run_tick "$ws_hint" TR_MOCK_BEHAVIOR=claim-valid TR_MOCK_NEXT_HINT=plan-mismatch || true
  done
  if [[ "$(state_value "$ws_hint" tr-basic status)" != queued ]] \
    || [[ -n "$(state_value "$ws_hint" tr-basic terminal_reason)" ]]; then
    fail "$name" "three next_hint values altered deviation control"
    return
  fi
  run_tick "$ws_hint" TR_MOCK_BEHAVIOR=claim-valid TR_MOCK_NEXT_HINT=report-exclusion-sentinel || true
  report="$ws_hint/loop/tasks/dlq/tr-basic/REPORT.md"
  if [[ "$(state_value "$ws_hint" tr-basic status)" != dlq ]] \
    || [[ "$(state_value "$ws_hint" tr-basic terminal_reason)" != attempts-budget ]] \
    || ! grep -F -q 'report-exclusion-sentinel' "$ws_hint/loop/artifacts/tr-basic/PROGRESS.md" \
    || grep -F -q 'report-exclusion-sentinel' "$report"; then
    fail "$name" "successful hint altered terminal control or leaked into REPORT.md"
    return
  fi

  ws_deviation=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_deviation" tr-basic
  for i in 1 2 3; do
    run_tick "$ws_deviation" TR_MOCK_BEHAVIOR=claim-valid TR_MOCK_NEXT_HINT=advisory TR_MOCK_DEVIATION="drift-$i" || true
  done
  if [[ "$(state_value "$ws_deviation" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws_deviation" tr-basic terminal_reason)" = plan-mismatch ]]; then
    pass "$name"
  else
    fail "$name" "next_hint changed the cumulative three-deviation plan-mismatch contract"
  fi
}

case_success_next_hint_crash_recovery_is_idempotent() {
  local name=success-next-hint-crash-recovery-idempotent
  local ws root code occurrences
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_MOCK_NEXT_HINT=crash-advisory TR_CRASH_AFTER=donecheck-pass >/dev/null 2>&1
  code=$?
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete
  occurrences=$(grep -F -c -- '- 001: "crash-advisory"' "$root/PROGRESS.md" || true)
  if [[ "$code" -eq 137 ]] \
    && [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic current_step)" = 2 ]] \
    && [[ ! -d "$root/attempts/002" ]] \
    && [[ "$occurrences" = 1 ]] \
    && ! find "$root/attempts" -name prompt.md -type f -exec grep -F -q 'crash-advisory' {} +; then
    pass "$name"
  else
    fail "$name" "crash recovery duplicated the advisory or introduced another attempt/control input"
  fi
}

case_crash_spawn() {
  local name=crash-spawn-recovery
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=spawn >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success && [[ "$(state_value "$ws" tr-basic status)" = delivered ]] && [[ -f "$ws/loop/artifacts/tr-basic/attempts/001/driver.json" ]]; then
    pass "$name"
  else
    fail "$name" "recovery tick did not deliver with stamped prior outcome"
  fi
}

case_crash_stamp() {
  local name=crash-stamp-recovery
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=stamp >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success && [[ "$(state_value "$ws" tr-basic status)" = delivered ]] && [[ ! -d "$ws/loop/artifacts/tr-basic/attempts/002" ]]; then
    pass "$name"
  else
    fail "$name" "recovery did not reuse stamped attempt"
  fi
}

case_crash_stamp_invalid_receipt_dlq() {
  local name=crash-stamp-invalid-receipt-dlq
  local ws task code
  ws=$(make_ws)
  write_runner_task "$ws" reap-invalid-receipt out/delivery-receipt.json true
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=stamp >/dev/null 2>&1
  code=$?
  set -e
  task="$ws/loop/tasks/queue/reap-invalid-receipt.task.md"
  sed 's|^receipt:.*|receipt: out/../escape|' "$task" >"$task.tmp"
  mv "$task.tmp" "$task"
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$code" -eq 137 ]] \
    && [[ "$(state_value "$ws" reap-invalid-receipt status)" = dlq ]] \
    && [[ "$(state_value "$ws" reap-invalid-receipt terminal_reason)" = missing-receipt ]] \
    && [[ "$(state_value "$ws" reap-invalid-receipt attempts_used)" = 0 ]] \
    && [[ -f "$ws/loop/tasks/dlq/reap-invalid-receipt/reap-invalid-receipt.task.md" ]] \
    && [[ ! -e "$ws/loop/artifacts/reap-invalid-receipt/attempts/001/donecheck.log" ]]; then
    pass "$name"
  else
    fail "$name" 'reap finalize did not DLQ the mutated receipt before charging or verification'
  fi
}

case_crash_stamp_infra_neutral() {
  local name=crash-stamp-infra-neutral
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra TR_CRASH_AFTER=stamp >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ -f "$ws/loop/artifacts/tr-basic/attempts-infra/001.infra-1/driver.json" ]] \
    && [[ ! -d "$ws/loop/artifacts/tr-basic/attempts/002" ]]; then
    pass "$name"
  else
    fail "$name" "infra stamp recovery did not stay budget-neutral before success"
  fi
}

case_crash_infra_requeue_recovery() {
  local name=crash-infra-requeue-recovery
  local ws root code
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra TR_CRASH_AFTER=infra-requeue >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -ne 137 ]] \
    || [[ "$(state_value "$ws" tr-basic status)" != queued ]] \
    || [[ "$(state_value "$ws" tr-basic infra_retries)" != 1 ]] \
    || [[ ! -f "$root/attempts/001/driver.json" ]]; then
    fail "$name" "crash did not leave durable queued state and the source attempt in place"
    return
  fi

  # Fail-open by design: this narrow post-commit/pre-quarantine window retains
  # pre-#60 overwrite behavior, so recovery reuses attempts/001.
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ -f "$ws/loop/tasks/delivered/tr-basic/tr-basic.task.md" ]]; then
    pass "$name"
  else
    fail "$name" "queued recovery did not proceed normally to delivery"
  fi
}

case_crash_infra_terminal_recovery() {
  local name=crash-infra-terminal-recovery
  local ws root code quarantine_count
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for _ in 1 2 3; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra TR_CRASH_AFTER=infra-terminal >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -ne 137 ]] || [[ ! -f "$root/attempts/001/driver.json" ]]; then
    fail "$name" "fourth infra tick did not crash with stamped terminal evidence"
    return
  fi
  cp "$root/attempts/001/driver.json" "$ws/terminal-driver.before"

  # The mock is intentionally successful: if recovery respawns, it would
  # overwrite the terminal attempt and deliver, making this regression obvious.
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  quarantine_count=$(find "$root/attempts-infra" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d '[:space:]')
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = infra ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 4 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && cmp -s "$ws/terminal-driver.before" "$root/attempts/001/driver.json" \
    && [[ "$quarantine_count" = 3 ]] \
    && [[ ! -e "$ws/loop/tasks/delivered/tr-basic" ]]; then
    pass "$name"
  else
    fail "$name" "recovery respawned or failed to preserve the retry-4 terminal evidence"
  fi
}

case_infra_requeues_quarantine_evidence() {
  local name=infra-requeues-quarantine-evidence
  local ws root progress
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  progress="$root/PROGRESS.md"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  if [[ -d "$root/attempts/001" ]]; then
    fail "$name" "first quarantine copied evidence instead of moving the source attempt"
    return
  fi
  if ! grep -F -q '## Infra retries' "$progress" \
    || ! grep -F -q -- '- 001.infra-1: outcome=error classified=infra dur_s=' "$progress"; then
    fail "$name" "PROGRESS.md did not expose the first quarantined retry"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  if [[ -f "$root/attempts-infra/001.infra-1/driver.json" ]] \
    && [[ -f "$root/attempts-infra/001.infra-2/driver.json" ]] \
    && grep -F -q '"classified": "infra"' "$root/attempts-infra/001.infra-1/driver.json" \
    && grep -F -q '"outcome": "error"' "$root/attempts-infra/001.infra-2/driver.json" \
    && [[ ! -d "$root/attempts/001" ]]; then
    pass "$name"
  else
    fail "$name" "requeued infra attempts did not retain separate stamped evidence"
  fi
}

case_infra_then_success_keeps_failed_evidence() {
  local name=infra-then-success-keeps-failed-evidence
  local ws root
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=unknown-error
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ -f "$root/attempts-infra/001.infra-1/driver.json" ]] \
    && grep -F -q 'unexpected upstream failure xyz123' "$root/attempts-infra/001.infra-1/model.stderr" \
    && grep -F -q '"outcome": "ok"' "$root/attempts/001/driver.json"; then
    pass "$name"
  else
    fail "$name" "success overwrote or failed to replace the prior infra evidence"
  fi
}

case_infra_exhaustion_keeps_final_attempt() {
  local name=infra-exhaustion-keeps-final-attempt
  local ws i root report
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if [[ "$(state_value "$ws" tr-basic infra_retries)" = 4 ]] \
    && [[ -f "$root/attempts-infra/001.infra-1/driver.json" ]] \
    && [[ -f "$root/attempts-infra/001.infra-2/driver.json" ]] \
    && [[ -f "$root/attempts-infra/001.infra-3/driver.json" ]] \
    && [[ -f "$root/attempts/001/driver.json" ]] \
    && [[ -f "$report" ]] \
    && grep -F -q '## Infra retry summaries' "$report" \
    && awk '/^## Infra retry summaries/{in_section=1; next} /^## /{in_section=0} in_section {print}' "$report" | grep -F -q -- '- 001.infra-3:'; then
    pass "$name"
  else
    fail "$name" "infra DLQ did not retain three quarantines and the final attempt"
  fi
}

case_crash_stamp_deterministic_auth_recovery() {
  local name=crash-stamp-deterministic-auth-recovery
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_CRASH_AFTER=stamp >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  if [[ "$(driver_value "$ws" tr-basic classified)" != deterministic-auth ]]; then
    fail "$name" "crashed attempt was not stamped deterministic-auth"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = deterministic-auth ]] \
    && [[ -d "$ws/loop/tasks/dlq/tr-basic" ]] \
    && [[ ! -d "$ws/loop/artifacts/tr-basic/attempts/002" ]]; then
    pass "$name"
  else
    fail "$name" "reap did not DLQ the stamped deterministic auth failure"
  fi
}

case_crash_donecheck() {
  local name=crash-donecheck-pass-recovery
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=donecheck-pass >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success && [[ "$(state_value "$ws" tr-basic status)" = delivered ]] && [[ ! -d "$ws/loop/artifacts/tr-basic/attempts/002" ]]; then
    pass "$name"
  else
    fail "$name" "verifying recovery did not deliver without another attempt"
  fi
}

case_crash_deliver_terminal_reconcile() {
  local name=crash-deliver-terminal-reconcile
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=deliver-terminal >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "first tick did not crash with 137"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  bash "$METRICS" "$ws"
  if [[ -f "$ws/loop/tasks/delivered/tr-basic/tr-basic.task.md" ]] \
    && [[ -f "$ws/loop/tasks/delivered/tr-basic/state.json" ]] \
    && grep -q '| delivered | 1 |' "$ws/METRICS.md"; then
    pass "$name"
  else
    fail "$name" "terminal delivered layout was not reconciled"
  fi
}

case_crash_dlq_terminal_reconcile() {
  local name=crash-dlq-terminal-reconcile
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth TR_CRASH_AFTER=dlq-terminal >/dev/null 2>&1
  local code=$?
  set -e
  if [[ "$code" -ne 137 ]]; then
    fail "$name" "second tick did not crash with 137"
    return
  fi
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  bash "$METRICS" "$ws"
  if [[ -f "$ws/loop/tasks/dlq/tr-basic/tr-basic.task.md" ]] \
    && [[ -f "$ws/loop/tasks/dlq/tr-basic/state.json" ]] \
    && [[ -f "$ws/loop/tasks/dlq/tr-basic/REPORT.md" ]] \
    && grep -q '| dlq | 1 |' "$ws/METRICS.md"; then
    pass "$name"
  else
    fail "$name" "terminal dlq layout was not reconciled"
  fi
}

case_push_refusal_standalone_operator() {
  local name=push-refusal-standalone-operator
  local baseline_ws ws helper push_command dest report push_log baseline_rc rc output
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  helper="$ws/plain-push-helper.sh"
  push_command="$helper | $helper"
  cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected push helper invocation\n' >>"$PUSH_MARKER"
exit 0
SH
  chmod +x "$helper"

  set +e
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="$push_command" PUSH_MARKER="$ws/push-marker" 2>&1)
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ -f "$dest/push-failed" ]] \
    && grep -Fq 'push: TR_PUSH_CMD refused: standalone-operator' "$push_log" \
    && grep -Eq '^push: rc=126 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z dest=' "$push_log" \
    && grep -Eq '^push: failed rc=126 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$report" \
    && ! grep -Fq "$push_command" "$push_log" \
    && ! grep -Fq "$push_command" "$report" \
    && ! grep -Fq "$push_command" <<<"$output" \
    && [[ ! -e "$ws/push-marker" ]]; then
    pass "$name"
  else
    fail "$name" "expected push-time standalone-operator refusal without helper execution: baseline_rc=$baseline_rc rc=$rc output=$output"
  fi
}

case_dlq_push_failure_visible_and_retried() {
  local name=dlq-push-failure-visible-and-retried
  local baseline_ws ws push_helper allow_file credential push_command dest report push_log
  local baseline_rc failure_rc retry_rc output retry_output warning_count
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  push_helper="$ws/push-helper.sh"
  allow_file="$ws/push-allowed"
  credential='credential-sentinel-22'
  push_command="$push_helper $credential"
  cat >"$push_helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ! -e "$PUSH_ALLOW_FILE" ]]; then
  printf 'push helper stdout\n'
  printf 'push helper stderr\n' >&2
  exit 7
fi
printf 'push helper success for %s\n' "$2"
SH
  chmod +x "$push_helper"

  set +e
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="$push_command" PUSH_ALLOW_FILE="$allow_file" 2>&1)
  failure_rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  warning_count=$(grep -Fxc "warning: push failed rc=7: $dest" <<<"$output" || true)
  if [[ "$baseline_rc" -ne 0 || "$failure_rc" -ne "$baseline_rc" ]] \
    || [[ "$warning_count" -ne 1 ]] \
    || [[ ! -f "$dest/push-failed" || ! -f "$push_log" ]] \
    || ! grep -Fq 'push helper stdout' "$push_log" \
    || ! grep -Fq 'push helper stderr' "$push_log" \
    || ! grep -Eq '^push: failed rc=7 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$report" \
    || grep -R -Fq -- "$credential" "$ws"; then
    fail "$name" "failed push contract mismatch: baseline_rc=$baseline_rc failure_rc=$failure_rc warnings=$warning_count output=$output"
    return
  fi

  : >"$allow_file"
  set +e
  retry_output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=success \
    TR_PUSH_CMD="$push_command" PUSH_ALLOW_FILE="$allow_file" 2>&1)
  retry_rc=$?
  set -e
  if [[ "$retry_rc" -eq 0 ]] \
    && [[ ! -e "$dest/push-failed" ]] \
    && [[ "$(grep -Fc '== push attempt ' "$push_log")" -eq 2 ]] \
    && grep -Fq "push helper success for $report" "$push_log" \
    && ! grep -Fq 'warning: push failed' <<<"$retry_output" \
    && ! grep -R -Fq -- "$credential" "$ws" \
    && [[ "$(state_value "$ws" tr-basic status)" = dlq ]]; then
    pass "$name"
  else
    fail "$name" "retry contract mismatch: rc=$retry_rc marker=$([[ -e "$dest/push-failed" ]] && printf present || printf absent) output=$retry_output"
  fi
}

case_push_accepts_credential_metacharacters() {
  local name=push-accepts-credential-metacharacters
  local ws helper credential dest report push_log rc
  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  helper="$ws/push-helper.sh"
  credential='p@ssw0rd!#$*?'
  cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "$EXPECTED_CREDENTIAL" ]]; then
  printf 'wrong credential\n' >&2
  exit 8
fi
if [[ ! -f "$2" ]]; then
  printf 'missing report\n' >&2
  exit 9
fi
printf 'push accepted %s\n' "$2"
SH
  chmod +x "$helper"

  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="$helper $credential" EXPECTED_CREDENTIAL="$credential" >/dev/null 2>&1
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  if [[ "$rc" -eq 0 ]] \
    && [[ ! -e "$dest/push-failed" ]] \
    && grep -Fq "push accepted $report" "$push_log" \
    && grep -Eq '^push: rc=0 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z dest=' "$push_log" \
    && ! grep -Fq 'push: failed rc=' "$report"; then
    pass "$name"
  else
    fail "$name" "expected credential-bearing argv push to succeed: rc=$rc"
  fi
}

case_push_leak_redacts_credential_and_records_failure() {
  local name=push-leak-redacts-credential-and-records-failure
  local baseline_ws ws credential dest report push_log output baseline_rc rc push_log_mode
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  credential='credential!#sentinel$*?'
  set +e
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="missing-push-helper $credential" 2>&1)
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  push_log_mode=$(file_mode "$push_log")
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ -f "$dest/push-failed" ]] \
    && [[ "$push_log_mode" = 600 ]] \
    && grep -Fqx '[push command refused before exec]' "$push_log" \
    && grep -Eq '^push: rc=127 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$push_log" \
    && grep -Eq '^push: failed rc=127 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$report" \
    && ! grep -Fq "$credential" <<<"$output" \
    && ! grep -R -Fq -- "$credential" "$ws"; then
    pass "$name"
  else
    fail "$name" "expected redacted push failure without credential leakage: baseline_rc=$baseline_rc rc=$rc mode=$push_log_mode output=$output"
  fi
}

case_push_redaction_unit_suppresses_runner_shell_diagnostics() {
  local name=push-redaction-unit-suppresses-runner-shell-diagnostics
  local ws src dest
  ws=$(make_ws)
  src="$ws/push-output"
  dest="$ws/push-log"
  {
    printf '%s\n' '_: /x/y'
    printf '%s\n' 'task-runner.sh: line 11: /x/y: command not found'
    printf '%s\n' '/tmp/task-runner.sh: line 12: /x/y: command not found'
    printf '%s\n' '/tmp/task-runner.sh: line 12: /x/y: Permission denied'
    printf '%s\n' '/tmp/task-runner.sh: line 12: /x/y: No such file or directory'
    printf '%s\n' '/tmp/task-runner.sh: line 12: /x/y: is a directory'
    printf '%s\n' '/tmp/task-runner.sh: line 12: /x/y: cannot execute binary file: Exec format error'
    printf '%s\n' '/tmp/my-task-runner.sh: line 12: helper context should survive'
    printf '%s\n' 'ordinary helper prose survives unchanged'
  } >"$src"
  : >"$dest"

  (
    source "$ROOT/scripts/lib-command-argv.sh"
    append_redacted_push_output "$src" "$dest"
  )

  if [[ "$(grep -Fxc '[bash-level error suppressed]' "$dest")" = 1 ]] \
    && [[ "$(grep -Fxc '[task-runner shell diagnostic redacted]' "$dest")" = 6 ]] \
    && grep -Fqx '/tmp/my-task-runner.sh: line 12: helper context should survive' "$dest" \
    && grep -Fqx 'ordinary helper prose survives unchanged' "$dest" \
    && [[ "$(wc -l <"$dest" | tr -d '[:space:]')" = 9 ]]; then
    pass "$name"
  else
    fail "$name" "expected all synthetic shell diagnostics to redact: $(cat "$dest")"
  fi
}

case_resolve_cmd_argv0_allow_empty_strict_mode_safe() {
  local name=resolve-cmd-argv0-allow-empty-strict-mode-safe
  local output rc
  set +e
  output=$(
    bash -c '
      set -euo pipefail
      source "$1/scripts/lib-command-argv.sh"
      validate_cmd_argv TEST_CMD $'"'"' \t '"'"' allow-empty
      if resolve_cmd_argv0 TEST_CMD; then
        resolve_rc=0
      else
        resolve_rc=$?
      fi
      printf "resolve_rc=%s\nreason=%s\n" "$resolve_rc" "$_validated_reason"
    ' _ "$ROOT" 2>&1
  )
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] \
    && grep -Fqx 'resolve_rc=1' <<<"$output" \
    && grep -Fqx 'reason=empty-after-split' <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected strict-mode empty argv0 guard to return normally: rc=$rc output=$output"
  fi
}

case_push_exec_format_error_redacts_argv0_e2e() {
  local name=push-exec-format-error-redacts-argv0-e2e
  local baseline_ws ws bad_bin dest report push_log output baseline_rc rc
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  bad_bin="$ws/bad-push-bin"
  # NUL bytes are required: without them bash 3.2's ENOEXEC fallback runs the
  # stub as a shell script (rc 127, child-shell diagnostic) instead of the
  # invoking shell's rc-126 "cannot execute binary file" — measured on 3.2.57
  # vs 5.3. The NUL trips bash's binary detection on both.
  printf '\177ELF\0\0\0\0' >"$bad_bin"
  chmod 0755 "$bad_bin"

  set +e
  output=$(run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD="$bad_bin" 2>&1)
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ -f "$dest/push-failed" ]] \
    && grep -Fqx '[task-runner shell diagnostic redacted]' "$push_log" \
    && grep -Eq '^push: rc=126 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$push_log" \
    && grep -Eq '^push: failed rc=126 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$report" \
    && ! grep -Fq "$bad_bin" "$push_log" \
    && ! grep -Fq "$bad_bin" "$report" \
    && ! grep -Fq "$bad_bin" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exec-format push failure to redact argv0: baseline_rc=$baseline_rc rc=$rc output=$output"
  fi
}

case_push_refuses_raw_newline_and_carriage_return() {
  local name=push-refuses-raw-newline-and-carriage-return
  local ws_lf ws_cr helper dest_lf dest_cr push_log_lf push_log_cr rc_lf rc_cr
  ws_lf=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_lf" tr-basic
  helper="$ws_lf/push-helper.sh"
  cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected helper invocation\n' >>"$PUSH_MARKER"
exit 0
SH
  chmod +x "$helper"
  set +e
  run_tick "$ws_lf" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="$helper"$'\n'"$helper" PUSH_MARKER="$ws_lf/push-marker" >/dev/null 2>&1
  rc_lf=$?
  set -e
  dest_lf="$ws_lf/loop/tasks/dlq/tr-basic"
  push_log_lf="$dest_lf/push.log"

  ws_cr=$(make_ws)
  copy_task "$FIX_BASIC" "$ws_cr" tr-basic
  set +e
  run_tick "$ws_cr" TR_MOCK_BEHAVIOR=auth-error \
    TR_PUSH_CMD="$helper"$'\r'" --flag" PUSH_MARKER="$ws_cr/push-marker" >/dev/null 2>&1
  rc_cr=$?
  set -e
  dest_cr="$ws_cr/loop/tasks/dlq/tr-basic"
  push_log_cr="$dest_cr/push.log"

  if [[ "$rc_lf" -eq 0 ]] \
    && [[ "$rc_cr" -eq 0 ]] \
    && grep -Fq 'push: TR_PUSH_CMD refused: raw-newline-or-carriage-return' "$push_log_lf" \
    && grep -Fq 'push: TR_PUSH_CMD refused: raw-newline-or-carriage-return' "$push_log_cr" \
    && [[ ! -e "$ws_lf/push-marker" ]] \
    && [[ ! -e "$ws_cr/push-marker" ]]; then
    pass "$name"
  else
    fail "$name" "expected raw LF/CR refusal before splitting: rc_lf=$rc_lf rc_cr=$rc_cr"
  fi
}

case_push_whitespace_only_is_noop() {
  local name=push-whitespace-only-is-noop
  local baseline_ws ws dest baseline_rc rc
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD=$' \t ' >/dev/null 2>&1
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ ! -e "$dest/push-failed" ]] \
    && [[ ! -e "$dest/push.log" ]]; then
    pass "$name"
  else
    fail "$name" "expected whitespace-only push command to be treated as unset: baseline_rc=$baseline_rc rc=$rc"
  fi
}

case_push_does_not_expand_tilde() {
  local name=push-does-not-expand-tilde
  local baseline_ws ws dest push_log output baseline_rc rc shell_expanded_rc literal_argv_rc literal_tilde
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  literal_tilde="$ws/~"
  if [[ -e "$literal_tilde" ]]; then
    fail "$name" "expected no literal tilde entry in workspace before push"
    return
  fi
  set +e
  (
    cd "$ws"
    sh -c '/bin/ls ~ >/dev/null 2>&1'
  )
  shell_expanded_rc=$?
  (
    cd "$ws"
    /bin/ls '~' >/dev/null 2>&1
  )
  literal_argv_rc=$?
  output=$(cd "$ws" && run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD='/bin/ls ~' 2>&1)
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  push_log="$dest/push.log"
  # Portability: BSD ls exits 1 on a missing operand, GNU ls exits 2 — require
  # nonzero, and require the recorded push rc to equal the directly measured one.
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$shell_expanded_rc" -eq 0 ]] \
    && [[ "$literal_argv_rc" -ne 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ -f "$dest/push-failed" ]] \
    && grep -Eq "^push: rc=$literal_argv_rc [0-9]{4}-[0-9]{2}-[0-9]{2}T" "$push_log" \
    && ! grep -Fq "$literal_tilde" "$push_log" \
    && ! grep -Fq "$literal_tilde" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected shell-tilde rc0, literal-argv nonzero rc, and matching recorded push rc without literal-tilde artifacts: baseline=$baseline_rc shell=$shell_expanded_rc literal=$literal_argv_rc rc=$rc output=$output"
  fi
}

case_push_env_assignment_prefix_reports_127() {
  local name=push-env-assignment-prefix-reports-127
  local baseline_ws ws helper marker dest push_log output baseline_rc rc
  baseline_ws=$(make_ws)
  copy_task "$FIX_BASIC" "$baseline_ws" tr-basic
  set +e
  run_tick "$baseline_ws" TR_MOCK_BEHAVIOR=auth-error >/dev/null 2>&1
  baseline_rc=$?
  set -e

  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  helper="$ws/helper"
  marker="$ws/helper-invoked"
  cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FOO:-missing}" >"$HELPER_MARKER"
exit 0
SH
  chmod +x "$helper"
  set +e
  output=$(PATH="$ws:$PATH" HELPER_MARKER="$marker" \
    run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD='FOO=bar helper' 2>&1)
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  push_log="$dest/push.log"
  if [[ "$baseline_rc" -eq 0 ]] \
    && [[ "$rc" -eq "$baseline_rc" ]] \
    && [[ -f "$dest/push-failed" ]] \
    && grep -Fq 'push: TR_PUSH_CMD refused: not-found' "$push_log" \
    && grep -Eq '^push: rc=127 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$push_log" \
    && ! grep -Fq 'FOO=bar helper' "$push_log" \
    && ! grep -Fq 'FOO=bar helper' <<<"$output" \
    && [[ ! -e "$marker" ]]; then
    pass "$name"
  else
    fail "$name" "expected env-assignment prefix to be unresolved argv0 with rc=127: baseline=$baseline_rc rc=$rc output=$output"
  fi
}

case_push_multiword_command_succeeds() {
  local name=push-multiword-command-succeeds
  local ws helper dest report push_log rc
  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  helper="$ws/push-helper.sh"
  cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != upload ]]; then
  printf 'wrong subcommand\n' >&2
  exit 8
fi
printf 'multiword push %s\n' "$2"
SH
  chmod +x "$helper"

  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD="$helper upload" >/dev/null 2>&1
  rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  push_log="$dest/push.log"
  if [[ "$rc" -eq 0 ]] \
    && [[ ! -e "$dest/push-failed" ]] \
    && grep -Fq "multiword push $report" "$push_log" \
    && grep -Eq '^push: rc=0 [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$push_log"; then
    pass "$name"
  else
    fail "$name" "expected multiword argv push command to succeed: rc=$rc"
  fi
}

case_probe_resolution_failure_does_not_leak_value() {
  local name=probe-resolution-failure-does-not-leak-value
  local ws output rc stderr_file marker true_bin i
  ws=$(make_ws)
  ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  marker='probe-leak-sentinel-77'
  true_bin=$(command -v true)
  output=''
  rc=0
  for i in 1 2 3 4; do
    set +e
    output="$output"$'\n'"$(env TR_SPAWN_STEP="$ROOT/adapters/hermes/spawn_step.sh" \
      HERMES_STEP_CMD="$true_bin" \
      HERMES_PROBE_CMD="$ws/missing-probe-$marker" \
      bash "$RUNNER" "$ws" 2>&1)"
    rc=$?
    set -e
  done
  stderr_file="$ws/loop/artifacts/tr-basic/attempts/001/model.stderr"
  if [[ "$rc" -eq 0 ]] \
    && [[ -f "$stderr_file" ]] \
    && [[ "$(driver_value "$ws" tr-basic exit_code)" = 111 ]] \
    && grep -Fq 'HERMES_PROBE_CMD: not-found' "$stderr_file" \
    && ! grep -Fq "$marker" "$stderr_file" \
    && ! grep -Fq "$marker" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected probe resolution failure without value leak: rc=$rc output=$output stderr=$(cat "$stderr_file" 2>/dev/null)"
  fi
}

case_stale_lease_reap() {
  local name=stale-lease-reap
  local ws pgid
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=hang TR_CRASH_AFTER=spawn TR_STEP_TIMEOUT_S=1 TR_GRACE_S=0 >/dev/null 2>&1
  set -e
  pgid=$(state_value "$ws" tr-basic lease.pgid)
  sleep 3
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_STEP_TIMEOUT_S=1 TR_GRACE_S=0
  if kill -0 "-$pgid" 2>/dev/null; then
    fail "$name" "orphaned process group still alive"
  elif [[ "$(state_value "$ws" tr-basic status)" = delivered ]]; then
    pass "$name"
  else
    fail "$name" "task did not recover after stale reap"
  fi
}

case_future_lease_reap_bounded() {
  local name=future-lease-reap-bounded
  local ws pgid
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=hang TR_CRASH_AFTER=spawn TR_STEP_TIMEOUT_S=60 TR_GRACE_S=1 >/dev/null 2>&1
  set -e
  pgid=$(state_value "$ws" tr-basic lease.pgid)
  python3 - "$ws/loop/artifacts/tr-basic/state.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["lease"]["started"] = "2999-01-01T00:00:00Z"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_STEP_TIMEOUT_S=60 TR_GRACE_S=1
  if kill -0 "-$pgid" 2>/dev/null; then
    fail "$name" "future-dated lease skipped recovery"
  elif [[ "$(state_value "$ws" tr-basic status)" = delivered ]]; then
    pass "$name"
  else
    fail "$name" "future-dated lease did not recover to delivered"
  fi
}

case_attempts_exhaustion() {
  local name=attempts-exhaustion
  local ws i
  ws=$(make_ws)
  copy_task "$FIX_ATTEMPTS" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic"
  for i in 1 2 3 4; do
    printf 'attempt %s failed\n' "$i" >"$ws/loop/artifacts/tr-basic/gate-output"
    run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS="err$i"
  done
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] && [[ "$(state_value "$ws" tr-basic terminal_reason)" = attempts-budget ]] && [[ -f "$ws/loop/tasks/dlq/tr-basic/REPORT.md" ]]; then
    pass "$name"
  else
    fail "$name" "expected dlq attempts-budget"
  fi
}

case_attempts_exhaustion_reports_actual_failing_donecheck_line() {
  local name=attempts-exhaustion-reports-actual-failing-donecheck-line
  local ws i report failing
  ws=$(make_ws)
  copy_task "$FIX_FAILING_LINE" "$ws" tr-failing-line
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=success
  done
  report="$ws/loop/tasks/dlq/tr-failing-line/REPORT.md"
  failing="$ws/loop/artifacts/tr-failing-line/attempts/004/donecheck.failing"
  if [[ "$(state_value "$ws" tr-failing-line status)" = dlq ]] \
    && grep -Eq '^2: ' "$failing" \
    && grep -F -q 'test -s "$ARTIFACT_DIR/out/missing-receipt.json"' "$report" \
    && ! grep -F -q 'test -s "$ARTIFACT_DIR/out/delivery-receipt.json"' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not identify only the second assertion"
  fi
}

case_time_exhaustion() {
  local name=time-exhaustion
  local ws
  ws=$(make_ws)
  copy_task "$FIX_TINY" "$ws" tr-tiny-budget
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=time-one TR_STEP_TIMEOUT_S=1 TR_GRACE_S=0
  if [[ "$(state_value "$ws" tr-tiny-budget status)" = dlq ]] && [[ "$(state_value "$ws" tr-tiny-budget terminal_reason)" = time-budget ]]; then
    pass "$name"
  else
    fail "$name" "expected dlq time-budget"
  fi
}

case_donecheck_timeout_is_tunable() {
  local name=donecheck-timeout-is-tunable
  local ws started elapsed code log_file reason_file
  ws=$(make_ws)
  cat >"$ws/loop/tasks/queue/tr-donecheck-timeout.task.md" <<'EOF'
---
id: tr-donecheck-timeout
title: tunable donecheck timeout fixture
issued_by: test
created: 2026-08-10T00:00:00Z
attempts_budget: 4
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Exercise the configurable donecheck timeout.

## Done-when
```donecheck
sleep 10
test -e "$ARTIFACT_DIR/out/never-created"
```

## Step plan
1. Wait for the donecheck timeout.
EOF
  started=$SECONDS
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_DONECHECK_TIMEOUT_S=1 >/dev/null 2>&1
  code=$?
  set -e
  elapsed=$(( SECONDS - started ))
  log_file="$ws/loop/artifacts/tr-donecheck-timeout/attempts/001/donecheck.log"
  reason_file="$ws/loop/artifacts/tr-donecheck-timeout/attempts/001/verify-reason"
  if [[ "$code" -eq 0 && "$elapsed" -ge 1 && "$elapsed" -lt 8 ]] \
    && grep -Fqx 'donecheck timed out after 1s' "$reason_file" \
    && grep -Fqx 'donecheck timed out after 1s' "$log_file"; then
    pass "$name"
  else
    fail "$name" "custom timeout did not fire near 1s: rc=$code elapsed=$elapsed"
  fi
}

case_timeout_is_chargeable_not_quarantined() {
  local name=timeout-is-chargeable-not-quarantined
  local ws root
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=hang TR_STEP_TIMEOUT_S=1 TR_GRACE_S=0
  if [[ ! -e "$root/attempts-infra" ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = timeout ]]; then
    pass "$name"
  else
    fail "$name" "timeout entered the infra quarantine path or was not charged"
  fi
}

case_infra_retries() {
  local name=infra-retries
  local ws i
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] && [[ "$(state_value "$ws" tr-basic terminal_reason)" = infra ]] && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]]; then
    pass "$name"
  else
    fail "$name" "expected infra dlq with attempts_used=0"
  fi
}

case_infra_quarantine_collision_fails_open() {
  local name=infra-quarantine-collision-fails-open
  local ws root stderr_file
  ws=$(make_ws)
  root="$ws/loop/artifacts/tr-basic"
  stderr_file="$ws/infra-collision.stderr"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$root/attempts-infra/001.infra-1"
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra >/dev/null 2>"$stderr_file"
  if [[ -f "$root/attempts/001/driver.json" ]] \
    && grep -F -q 'quarantine_infra_attempt:' "$stderr_file" \
    && [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 1 ]]; then
    pass "$name"
  else
    fail "$name" "collision did not preserve the source, warn, and leave the task queued"
  fi
}

case_infra_exhaustion_reports_no_donecheck_line() {
  local name=infra-exhaustion-reports-no-donecheck-line
  local ws i report
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && grep -F -q '(no failing donecheck line recorded)' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md misquoted a donecheck that never ran"
  fi
}

case_infra_exhaustion_falls_back_to_donecheck_log() {
  local name=infra-exhaustion-falls-back-to-donecheck-log
  local ws i report attempt_dir
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for i in 1 2 3; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  attempt_dir="$ws/loop/artifacts/tr-basic/attempts/001"
  mkdir -p "$attempt_dir"
  printf '%s\n' 'PASS one' 'FAIL two' >"$attempt_dir/donecheck.log"
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q 'FAIL two' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not use the verbose-gate fallback"
  fi
}

case_infra_exhaustion_prefers_donecheck_failing() {
  local name=infra-exhaustion-prefers-donecheck-failing
  local ws i report attempt_dir
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  for i in 1 2 3; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  attempt_dir="$ws/loop/artifacts/tr-basic/attempts/001"
  mkdir -p "$attempt_dir"
  printf '%s\n' 'FAIL log line' >"$attempt_dir/donecheck.log"
  printf '%s\n' '2: test -s missing' >"$attempt_dir/donecheck.failing"
  run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q '2: test -s missing' "$report" \
    && ! grep -F -q 'FAIL log line' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not prefer donecheck.failing"
  fi
}

case_infra_exhaustion_newest_failing_line_wins() {
  local name=infra-exhaustion-newest-failing-line-wins
  local ws i report
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/001" "$ws/loop/artifacts/tr-basic/attempts/003"
  printf '%s\n' '1: stale old' >"$ws/loop/artifacts/tr-basic/attempts/001/donecheck.failing"
  printf '%s\n' '2: newest wins' >"$ws/loop/artifacts/tr-basic/attempts/003/donecheck.failing"
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q '2: newest wins' "$report" && ! grep -F -q '1: stale old' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not prefer the newest structured failing line"
  fi
}

case_infra_exhaustion_newest_log_beats_old_failing_line() {
  local name=infra-exhaustion-newest-log-beats-old-failing-line
  local ws i report
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/001" "$ws/loop/artifacts/tr-basic/attempts/002"
  printf '%s\n' '1: stale structured' >"$ws/loop/artifacts/tr-basic/attempts/001/donecheck.failing"
  printf '%s\n' 'FAIL latest assertion' >"$ws/loop/artifacts/tr-basic/attempts/002/donecheck.log"
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q 'FAIL latest assertion' "$report" && ! grep -F -q '1: stale structured' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md let an older structured line beat the newest log failure"
  fi
}

case_infra_exhaustion_wide_attempt_number() {
  local name=infra-exhaustion-wide-attempt-number
  local ws i report
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/001" "$ws/loop/artifacts/tr-basic/attempts/1000"
  printf '%s\n' '1: three digits' >"$ws/loop/artifacts/tr-basic/attempts/001/donecheck.failing"
  printf '%s\n' '9: four digits' >"$ws/loop/artifacts/tr-basic/attempts/1000/donecheck.failing"
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q '9: four digits' "$report" && ! grep -F -q '1: three digits' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not recognize four-digit attempt numbering"
  fi
}

case_infra_exhaustion_ignores_malformed_failing_lines() {
  local name=infra-exhaustion-ignores-malformed-failing-lines
  local ws i report
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/002"
  printf '%s\n' '   ' $'\t' >"$ws/loop/artifacts/tr-basic/attempts/002/donecheck.failing"
  printf '%s\n' 'FAIL from log' >"$ws/loop/artifacts/tr-basic/attempts/002/donecheck.log"
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if ! grep -F -q 'FAIL from log' "$report"; then
    fail "$name" "REPORT.md emitted a blank section instead of the same attempt's log failure"
    return
  fi

  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/003"
  printf '%s\n' 'junk line' '3: real line' >"$ws/loop/artifacts/tr-basic/attempts/003/donecheck.failing"
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  if grep -F -q '3: real line' "$report" && ! grep -F -q 'junk line' "$report"; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not select only the final usable physical line"
  fi
}

case_infra_exhaustion_summaries_use_numeric_order() {
  local name=infra-exhaustion-summaries-use-numeric-order
  local ws i report summaries
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  # 998..1001 crosses the digit-width boundary: lexical sort would keep 998
  # in the last three ([1001, 998, 999]); numeric must yield 999, 1000, 1001.
  for i in 998 999 1000 1001; do
    mkdir -p "$ws/loop/artifacts/tr-basic/attempts/$i"
    printf '%s\n' '{"outcome":"error","dur_s":1}' >"$ws/loop/artifacts/tr-basic/attempts/$i/driver.json"
  done
  for i in 1 2 3 4; do
    run_tick "$ws" TR_MOCK_BEHAVIOR=infra
  done
  report="$ws/loop/tasks/dlq/tr-basic/REPORT.md"
  summaries=$(awk '/^## Last 3 attempt summaries/{in_section=1; next} /^## /{in_section=0} in_section {print}' "$report")
  if [[ "$summaries" == *'- 999:'* && "$summaries" == *'- 1000:'* && "$summaries" == *'- 1001:'* ]] \
    && [[ "$summaries" != *'- 998:'* ]] \
    && [[ "${summaries%%- 1000:*}" == *'- 999:'* ]] \
    && [[ "${summaries%%- 1001:*}" == *'- 1000:'* ]]; then
    pass "$name"
  else
    fail "$name" "REPORT.md did not list only 999, 1000, 1001 in numeric order"
  fi
}

case_non111_deterministic_auth_dlq() {
  local name=non111-deterministic-auth-dlq
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = deterministic-auth ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ -f "$ws/loop/tasks/dlq/tr-basic/REPORT.md" ]] \
    && grep -q 'deterministic-auth' "$ws/loop/tasks/dlq/tr-basic/REPORT.md" \
    && [[ ! -d "$ws/loop/artifacts/tr-basic/attempts/002" ]]; then
    pass "$name"
  else
    fail "$name" "exit=1 auth error did not DLQ without a retry"
  fi
}

case_non111_permission_error_deterministic_auth_dlq() {
  local name=non111-permission-error-deterministic-auth-dlq
  local ws permission_step
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  permission_step="$ws/permission-error-step.sh"
  write_permission_error_step "$permission_step"
  run_tick_with_step "$ws" "$permission_step"
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = deterministic-auth ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]]; then
    pass "$name"
  else
    fail "$name" "exit=1 permission error did not DLQ without a retry"
  fi
}

case_stdout_cli_login_deterministic_auth_dlq() {
  local name=stdout-cli-login-deterministic-auth-dlq
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=cli-not-logged-in
  if [[ "$(driver_value "$ws" tr-basic classified)" = deterministic-auth ]] \
    && [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = deterministic-auth ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ -d "$ws/loop/tasks/dlq/tr-basic" ]] \
    && [[ -f "$ws/loop/artifacts/tr-basic/attempts/001/model.stdout" ]] \
    && grep -F -q 'Not logged in · Please run /login' "$ws/loop/artifacts/tr-basic/attempts/001/model.stdout"; then
    pass "$name"
  else
    fail "$name" "stdout-only CLI login failure did not DLQ with captured attempt evidence"
  fi
}

case_non111_unknown_error_uses_infra_retries() {
  local name=non111-unknown-error-uses-infra-retries
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=unknown-error
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(infra_driver_value "$ws" tr-basic 1 classified)" = transient ]] \
    && [[ "$(infra_driver_value "$ws" tr-basic 1 exit_code)" = 1 ]]; then
    pass "$name"
  else
    fail "$name" "exit=1 unknown error did not take the transient infra retry path"
  fi
}

case_empty_stderr_is_degenerate_and_retries() {
  local name=empty-stderr-degenerate-uses-infra-retries
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=empty-error
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(infra_driver_value "$ws" tr-basic 1 classified)" = degenerate ]] \
    && [[ "$(infra_driver_value "$ws" tr-basic 1 exit_code)" = 1 ]]; then
    pass "$name"
  else
    fail "$name" "empty stderr did not take the degenerate infra retry path"
  fi
}

case_metrics_idempotent() {
  local name=metrics-idempotent
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  bash "$METRICS" "$ws"
  cp "$ws/METRICS.md" "$ws/METRICS.one"
  bash "$METRICS" "$ws"
  if cmp -s "$ws/METRICS.md" "$ws/METRICS.one"; then
    pass "$name"
  else
    fail "$name" "METRICS.md changed between runs"
  fi
}

case_prompt_render_integration() {
  # Regression guard for the #9/#10 seam: with the REAL templates installed,
  # every placeholder must be filled (v0.1 shipped mismatched contracts).
  local name=prompt-render-integration
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/templates"
  printf '# stale workspace template {{TASK_FILE_CONTENT}}\n' >"$ws/templates/STEP-PROMPT.tmpl.md"
  printf '# STATE\n\ntest state\n' >"$ws/STATE.md"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  local prompt="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  local expected_artifact
  expected_artifact=$(cd "$ws" && pwd)/loop/artifacts/tr-basic
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success \
    && [[ -f "$prompt" ]] \
    && ! grep -q '{{' "$prompt" \
    && ! grep -F -q '$ARTIFACT_DIR' "$prompt" \
    && ! grep -F -q '${ARTIFACT_DIR}' "$prompt" \
    && ! grep -F -q '$TASK_FILE' "$prompt" \
    && ! grep -F -q '$ATTEMPT_DIR' "$prompt" \
    && grep -F -q "$expected_artifact" "$prompt" \
    && grep -q 'Execute ONLY plan step 1' "$prompt" \
    && grep -q 'test state' "$prompt" \
    && grep -F -q "Current UTC date: $(date -u '+%Y-%m-%d')" "$prompt" \
    && grep -q 'Do not stop at analysis' "$prompt" \
    && grep -q 'denied by default' "$prompt"; then
    pass "$name"
  else
    fail "$name" "prompt.md missing or has unfilled placeholders"
  fi
}

case_prompt_consult_skill_dir_index() {
  local name=prompt-consult-skill-dir-index
  local ws prompt skill_dir
  ws=$(make_ws)
  skill_dir="$ws/skills/release-helper"
  mkdir -p "$skill_dir/references" "$ws/skills/_staging/unverified"
  skill_dir=$(cd "$skill_dir" && pwd -P)
  printf '%s\n' 'private skill body sentinel' >"$skill_dir/SKILL.md"
  printf '%s\n' 'support file body sentinel' >"$skill_dir/references/checklist.md"
  printf '%s\n' 'staging body sentinel' >"$ws/skills/_staging/unverified/SKILL.md"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  prompt="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  if [[ -f "$prompt" ]] \
    && grep -F -q "Skill dir: \"$skill_dir\"" "$prompt" \
    && grep -F -q -- '- "SKILL.md"' "$prompt" \
    && grep -F -q -- '- "references/checklist.md"' "$prompt" \
    && ! grep -F -q 'private skill body sentinel' "$prompt" \
    && ! grep -F -q 'support file body sentinel' "$prompt" \
    && ! grep -F -q "$ws/skills/_staging/unverified" "$prompt" \
    && ! grep -F -q 'staging body sentinel' "$prompt"; then
    pass "$name"
  else
    fail "$name" "prompt did not list only promoted skill paths and support file names"
  fi
}

case_prompt_budget_normal() {
  local name=prompt-budget-normal
  local ws prompt
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=success
  prompt="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  if [[ -f "$prompt" ]] \
    && grep -F -q 'Attempts used: 0 / 4 (remaining: 4)' "$prompt" \
    && grep -F -q 'Time used: 0 min / 5 min (remaining: 5 min)' "$prompt" \
    && ! grep -q 'Budget wind-down' "$prompt"; then
    pass "$name"
  else
    fail "$name" "normal prompt did not render the expected budget without wind-down"
  fi
}

case_prompt_budget_final_attempt_wind_down() {
  local name=prompt-budget-final-attempt-wind-down
  local ws i prompt
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  for i in 1 2 3 4; do
    printf 'noncomplete\n' >"$ws/mock-cases/$(printf '%03d' "$i")"
  done
  copy_task "$FIX_ATTEMPTS" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic"
  for i in 1 2 3 4; do
    printf 'attempt %s failed\n' "$i" >"$ws/loop/artifacts/tr-basic/gate-output"
    printf 'error-%s\n' "$i" >"$ws/mock-error-class"
    run_tick "$ws" || true
  done
  if ! grep -q 'Budget wind-down' "$ws/loop/artifacts/tr-basic/attempts/001/prompt.md" \
    && ! grep -q 'Budget wind-down' "$ws/loop/artifacts/tr-basic/attempts/002/prompt.md" \
    && ! grep -q 'Budget wind-down' "$ws/loop/artifacts/tr-basic/attempts/003/prompt.md" \
    && grep -q 'Budget wind-down' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md" \
    && grep -qi 'do NOT start new work' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md" \
    && grep -qi 'summarize the progress' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md" \
    && grep -qi 'next step' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md" \
    && grep -F -q 'Attempts used: 3 / 4 (remaining: 1)' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md" \
    && grep -qE 'Time used: [0-9]+ min / 5 min \(remaining: [0-9]+ min\)' "$ws/loop/artifacts/tr-basic/attempts/004/prompt.md"; then
    pass "$name"
  else
    fail "$name" "wind-down was not rendered only for the final attempt with its required instructions"
  fi
}

case_prompt_budget_mid_budget_no_wind_down() {
  local name=prompt-budget-mid-budget-no-wind-down
  local ws i prompt
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  for i in 1 2; do
    printf 'noncomplete\n' >"$ws/mock-cases/$(printf '%03d' "$i")"
  done
  copy_task "$FIX_ATTEMPTS" "$ws" tr-basic
  for i in 1 2; do
    printf 'error-%s\n' "$i" >"$ws/mock-error-class"
    run_tick "$ws" || true
  done
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if [[ -f "$prompt" ]] \
    && grep -F -q 'Attempts used: 1 / 4 (remaining: 3)' "$prompt" \
    && ! grep -q 'Budget wind-down' "$prompt" \
    && ! grep -q '{{' "$prompt"; then
    pass "$name"
  else
    fail "$name" "mid-budget prompt rendered wind-down or left an unsubstituted token"
  fi
}

case_prompt_budget_time_exhaustion_wind_down() {
  local name=prompt-budget-time-exhaustion-wind-down
  local ws prompt
  ws=$(make_ws)
  copy_task "$FIX_TINY" "$ws" tr-tiny-budget
  # This wind-down is triggered by the zero-time-budget fixture, not elapsed active time.
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=fixture-case || true
  prompt="$ws/loop/artifacts/tr-tiny-budget/attempts/001/prompt.md"
  if [[ -f "$prompt" ]] && grep -q 'Budget wind-down' "$prompt"; then
    pass "$name"
  else
    fail "$name" "zero time budget did not render wind-down"
  fi
}

case_prompt_budget_time_boundary_wind_down() {
  local name=prompt-budget-time-boundary-wind-down
  local ws prompt
  ws=$(make_ws)
  copy_task "$FIX_TIME_BOUNDARY" "$ws" tr-time-boundary
  mkdir -p "$ws/loop/artifacts/tr-time-boundary"
  python3 - "$ws/loop/artifacts/tr-time-boundary/state.json" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({
        "status": "queued",
        "current_step": 1,
        "attempts_used": 0,
        "active_seconds_used": 480,
        "infra_retries": 0,
        "consec_noncomplete": 0,
        "last_error_class": None,
        "last_gap_fingerprint": None,
        "last_gap_step": None,
        "lease": None,
        "terminal_reason": None,
    }, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=threshold || true
  prompt="$ws/loop/artifacts/tr-time-boundary/attempts/001/prompt.md"
  if [[ -f "$prompt" ]] && grep -q 'Budget wind-down' "$prompt"; then
    pass "$name"
  else
    fail "$name" "wind-down did not render at the 120-second threshold"
  fi
}

case_prompt_budget_time_above_boundary_no_wind_down() {
  local name=prompt-budget-time-above-boundary-no-wind-down
  local ws prompt
  ws=$(make_ws)
  copy_task "$FIX_TIME_BOUNDARY" "$ws" tr-time-boundary
  mkdir -p "$ws/loop/artifacts/tr-time-boundary"
  python3 - "$ws/loop/artifacts/tr-time-boundary/state.json" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({
        "status": "queued",
        "current_step": 1,
        "attempts_used": 0,
        "active_seconds_used": 479,
        "infra_retries": 0,
        "consec_noncomplete": 0,
        "last_error_class": None,
        "last_gap_fingerprint": None,
        "last_gap_step": None,
        "lease": None,
        "terminal_reason": None,
    }, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=above-threshold || true
  prompt="$ws/loop/artifacts/tr-time-boundary/attempts/001/prompt.md"
  if [[ -f "$prompt" ]] && ! grep -q 'Budget wind-down' "$prompt"; then
    pass "$name"
  else
    fail "$name" "wind-down rendered above the 120-second threshold"
  fi
}

case_paused_step_old_behavior_red() {
  local name=paused-step-old-behavior-red
  local ws paused_step
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  paused_step="$ws/paused-step-old-behavior-red.sh"
  write_paused_step "$paused_step"
  run_tick_with_step "$ws" "$paused_step" >/dev/null 2>&1 || true
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic active_seconds_used)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = paused ]] \
    && [[ ! -f "$ws/loop/artifacts/tr-basic/attempts/001/step-result.json" ]]; then
    pass "$name"
  else
    fail "$name" "pause record was charged like the old behavior: status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) active=$(state_value "$ws" tr-basic active_seconds_used)"
  fi
}

case_paused_step_requeues_without_charge() {
  local name=paused-step-requeues-without-charge
  local ws paused_step
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  paused_step="$ws/paused-step.sh"
  write_paused_step "$paused_step"
  run_tick_with_step "$ws" "$paused_step" >/dev/null 2>&1
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic active_seconds_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = paused ]] \
    && [[ "$(driver_value "$ws" tr-basic classified)" = paused ]] \
    && [[ "$(driver_value "$ws" tr-basic exit_code)" = 0 ]] \
    && [[ -f "$ws/loop/tasks/queue/tr-basic.task.md" ]] \
    && grep -Fq 'status=paused workspace=' "$ws/loop/artifacts/tr-basic/attempts/001/model.stderr"; then
    pass "$name"
  else
    fail "$name" "paused step did not requeue cleanly: status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) active=$(state_value "$ws" tr-basic active_seconds_used)"
  fi
}

case_overflow_paused_step_requeues_without_charge() {
  local name=overflow-paused-step-requeues-without-charge
  local ws canonical_ws paused_step
  ws=$(make_ws)
  canonical_ws=$(cd "$ws" && pwd -P)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  paused_step="$ws/overflow-paused-step.sh"
  write_overflow_paused_step "$paused_step"
  run_tick_with_step "$ws" "$paused_step" >/dev/null 2>&1
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic active_seconds_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = paused ]] \
    && [[ "$(driver_value "$ws" tr-basic classified)" = paused ]] \
    && [[ "$(driver_value "$ws" tr-basic exit_code)" = 0 ]] \
    && [[ -f "$ws/loop/tasks/queue/tr-basic.task.md" ]] \
    && grep -Fqx "status=paused workspace=$canonical_ws entrypoint=overflow-spawn-step" "$ws/loop/artifacts/tr-basic/attempts/001/model.stderr"; then
    pass "$name"
  else
    fail "$name" "overflow pause did not requeue cleanly: status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) active=$(state_value "$ws" tr-basic active_seconds_used) outcome=$(driver_value "$ws" tr-basic outcome)"
  fi
}

case_paused_step_crash_recovery() {
  local name=paused-step-crash-recovery
  local ws paused_step first_rc
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  paused_step="$ws/paused-step.sh"
  write_paused_step "$paused_step"
  set +e
  run_tick_with_step "$ws" "$paused_step" TR_CRASH_AFTER=stamp >/dev/null 2>&1
  first_rc=$?
  set -e
  run_tick_with_step "$ws" "$paused_step" >/dev/null 2>&1
  if [[ "$first_rc" -eq 137 ]] \
    && [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic active_seconds_used)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic classified)" = paused ]]; then
    pass "$name"
  else
    fail "$name" "paused recovery did not restore queued/uncharged state: rc=$first_rc status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) active=$(state_value "$ws" tr-basic active_seconds_used)"
  fi
}

case_paused_step_crash_before_stamp_recovery() {
  local name=paused-step-crash-before-stamp-recovery
  local ws paused_step first_rc tries stderr_path sentinel_path
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  paused_step="$ws/paused-step.sh"
  write_paused_step "$paused_step"
  set +e
  run_tick_with_step "$ws" "$paused_step" TR_CRASH_AFTER=spawn >/dev/null 2>&1
  first_rc=$?
  set -e
  stderr_path="$ws/loop/artifacts/tr-basic/attempts/001/model.stderr"
  sentinel_path="$ws/loop/artifacts/tr-basic/attempts/001/owner.sentinel"
  tries=0
  while [[ "$tries" -lt 50 ]]; do
    if [[ -f "$stderr_path" ]] \
      && grep -Fqx "status=paused workspace=$ws entrypoint=hermes-spawn-step" "$stderr_path" \
      && [[ ! -e "$sentinel_path" ]]; then
      break
    fi
    sleep 0.1
    tries=$(( tries + 1 ))
  done
  run_tick_with_step "$ws" "$paused_step" >/dev/null 2>&1
  if [[ "$first_rc" -eq 137 ]] \
    && [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 0 ]] \
    && [[ "$(state_value "$ws" tr-basic active_seconds_used)" = 0 ]]; then
    pass "$name"
  else
    fail "$name" "pre-stamp paused recovery did not restore queued/uncharged state: rc=$first_rc status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) active=$(state_value "$ws" tr-basic active_seconds_used)"
  fi
}

case_nonpause_status_record_is_not_paused() {
  local name=nonpause-status-record-is-not-paused
  local ws nonpause_step
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  nonpause_step="$ws/nonpause-status-step.sh"
  write_nonpause_status_step "$nonpause_step"
  run_tick_with_step "$ws" "$nonpause_step" >/dev/null 2>&1 || true
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = ok ]] \
    && [[ "$(driver_value "$ws" tr-basic classified)" = '' ]]; then
    pass "$name"
  else
    fail "$name" "malformed paused record was misclassified as paused: status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) infra=$(state_value "$ws" tr-basic infra_retries) classified=$(driver_value "$ws" tr-basic classified)"
  fi
}

case_invalid_pause_label_is_not_paused() {
  local name=invalid-pause-label-is-not-paused
  local ws invalid_pause_step
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  invalid_pause_step="$ws/invalid-pause-label-step.sh"
  write_invalid_pause_label_step "$invalid_pause_step"
  run_tick_with_step "$ws" "$invalid_pause_step" >/dev/null 2>&1 || true
  if [[ "$(state_value "$ws" tr-basic status)" = queued ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 1 ]] \
    && [[ "$(state_value "$ws" tr-basic infra_retries)" = 0 ]] \
    && [[ "$(driver_value "$ws" tr-basic outcome)" = ok ]] \
    && [[ "$(driver_value "$ws" tr-basic classified)" = '' ]]; then
    pass "$name"
  else
    fail "$name" "invalid pause label was misclassified as paused: status=$(state_value "$ws" tr-basic status) attempts=$(state_value "$ws" tr-basic attempts_used) infra=$(state_value "$ws" tr-basic infra_retries) outcome=$(driver_value "$ws" tr-basic outcome) classified=$(driver_value "$ws" tr-basic classified)"
  fi
}

case_prior_verifier_finding() {
  local name=prior-verifier-finding
  local ws prompt_one prompt_two
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'noncomplete\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  write_verify_record \
    "$ws/loop/artifacts/tr-basic/attempts/001/verify.json" \
    fail 1 'rubric item x: evidence.md:3 missing proof | second reason segment'
  printf 'tool-misuse\n' >"$ws/mock-error-class"
  run_tick "$ws" || true
  prompt_one="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  prompt_two="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if grep -A4 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt_one" | grep -q '^none$' \
    && grep -q 'verdict: fail' "$prompt_two" \
    && grep -q 'rubric item x: evidence.md:3 missing proof | second reason segment' "$prompt_two"; then
    pass "$name"
  else
    fail "$name" "finding was not first-attempt-gated and re-injected on retry"
  fi
}

case_prior_verifier_pass_is_none() {
  local name=prior-verifier-pass-is-none
  local ws prompt
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'noncomplete\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  write_verify_record \
    "$ws/loop/artifacts/tr-basic/attempts/001/verify.json" \
    fail 1 'stale finding that must be suppressed'
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/002"
  write_verify_record \
    "$ws/loop/artifacts/tr-basic/attempts/002/verify.json" \
    pass 1 'no-findings residual risk: none'
  printf 'tool-misuse\n' >"$ws/mock-error-class"
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if grep -A4 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q '^none$' \
    && ! grep -A8 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q 'stale finding that must be suppressed'; then
    pass "$name"
  else
    fail "$name" "pass verdict was re-injected or older fail entry leaked (last-wins violated)"
  fi
}

case_prior_verifier_step_scoped() {
  local name=prior-verifier-step-scoped
  local ws prompt
  # Finding recorded for a DIFFERENT step (step=2) while the task is on step 1:
  # it must not surface. Root-level verify.json is not canonical either.
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'noncomplete\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  write_verify_record \
    "$ws/loop/artifacts/tr-basic/attempts/001/verify.json" \
    fail 2 'wrong-step finding'
  printf 'tool-misuse\n' >"$ws/mock-error-class"
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if ! grep -A4 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q '^none$' \
    || grep -A8 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q 'wrong-step finding'; then
    fail "$name" "finding for another step was re-injected"
    return
  fi

  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'noncomplete\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  write_verify_record \
    "$ws/loop/artifacts/tr-basic/verify.json" \
    fail 1 'root-level verify.json must be ignored'
  printf 'tool-misuse\n' >"$ws/mock-error-class"
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if grep -A4 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q '^none$' \
    && ! grep -q 'root-level verify.json must be ignored' "$prompt"; then
    pass "$name"
  else
    fail "$name" "non-attempt verify.json was re-injected"
  fi
}

case_verify_job_derived_step_reinjects_finding() {
  local name=verify-job-derived-step-reinjects-finding
  local ws artifact_dir verifier prompt rc
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth || true
  artifact_dir="$ws/loop/artifacts/tr-basic"
  for file in request.md rubric.md result.md manifest.md evidence.md; do
    printf '%s\n' "$file fixture" >"$artifact_dir/$file"
  done
  printf '{}\n' >"$artifact_dir/metadata.json"
  verifier="$ws/fail-verifier.sh"
  cat >"$verifier" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: fail'
printf '%s\n' 'fixture verifier finding: evidence.md:1 is missing proof'
SH
  chmod 0755 "$verifier"
  attest_verifier_wrapper "$ws" "$verifier" verify-job-derived-step
  set +e
  env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$ROOT/adapters/hermes/verify-job.sh" "$artifact_dir" >/dev/null 2>&1
  rc=$?
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth || true
  prompt="$artifact_dir/attempts/002/prompt.md"
  if [[ "$rc" -eq 1 ]] \
    && grep -q 'step=1' "$ws/loop/VERIFY.log.md" \
    && grep -A8 'BEGIN PRIOR VERIFIER FINDING DATA' "$prompt" | grep -q 'fixture verifier finding: evidence.md:1 is missing proof'; then
    pass "$name"
  else
    fail "$name" "derived verifier finding was not re-injected (rc=$rc)"
  fi
}

case_prior_attempt_failure() {
  local name=prior-attempt-failure
  local ws prompt_one prompt_two
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'noncomplete\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  printf 'tool-misuse\n' >"$ws/mock-error-class"
  run_tick "$ws" || true
  prompt_one="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  prompt_two="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if grep -A5 '## Prior attempt failure' "$prompt_one" | grep -q '^none$' \
    && grep -q 'error_class: auth' "$prompt_two" \
    && grep -q 'recovery: .*credentials/auth state before retrying' "$prompt_two" \
    && ! cmp -s "$prompt_one" "$prompt_two"; then
    pass "$name"
  else
    fail "$name" "prior failure was not rendered as a differing retry"
  fi
}

case_prior_attempt_success_not_injected() {
  local name=prior-attempt-success-not-injected
  local ws prompt
  # Attempt 001 completes step 1 (claim-valid) but the donecheck still fails,
  # so the task advances to step 2 and retries. The successful prior attempt
  # must NOT be re-injected as a failure.
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'claim-valid\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_NEXT_HINT=success-advisory-sentinel || true
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if [[ "$(state_value "$ws" tr-basic current_step)" = 2 ]] \
    && grep -A5 '## Prior attempt failure' "$prompt" | grep -q '^none$' \
    && ! grep -q 'error_class: no-step-result' "$prompt" \
    && ! grep -F -q 'success-advisory-sentinel' "$prompt" \
    && grep -F -q -- '- 001: "success-advisory-sentinel"' "$ws/loop/artifacts/tr-basic/PROGRESS.md"; then
    pass "$name"
  else
    fail "$name" "prior successful attempt was injected as a failure (step=$(state_value "$ws" tr-basic current_step))"
  fi
}

case_prior_attempt_result_edge_classes() {
  local name=prior-attempt-result-edge-classes
  local ws prompt
  # Non-dict (but valid) JSON step-result → malformed-result, not a silent none.
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'bad-json-result\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if ! grep -q 'error_class: malformed-result' "$prompt" \
    || ! grep -q 'recovery: .*single valid JSON object' "$prompt"; then
    fail "$name" "non-dict step-result.json was not classified malformed-result"
    return
  fi

  # Missing step-result.json → no-step-result with its dedicated recovery line.
  ws=$(make_ws)
  mkdir -p "$ws/mock-cases"
  printf 'no-result\n' >"$ws/mock-cases/001"
  printf 'noncomplete\n' >"$ws/mock-cases/002"
  printf 'auth\n' >"$ws/mock-error-class"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" || true
  run_tick "$ws" || true
  prompt="$ws/loop/artifacts/tr-basic/attempts/002/prompt.md"
  if grep -q 'error_class: no-step-result' "$prompt" \
    && grep -q 'recovery: .*end this attempt by writing it first' "$prompt"; then
    pass "$name"
  else
    fail "$name" "missing step-result.json did not render no-step-result recovery"
  fi
}

case_prompt_render_fallback_substitutes_contract_tokens() {
  local name=prompt-render-fallback-substitutes-contract-tokens
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  local prompt="$ws/loop/artifacts/tr-basic/attempts/001/prompt.md"
  local expected_artifact
  expected_artifact=$(cd "$ws" && pwd)/loop/artifacts/tr-basic
  if run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_TEMPLATE_OVERRIDE="$ws/missing-template.md" \
    && [[ -f "$prompt" ]] \
    && ! grep -F -q '$ARTIFACT_DIR' "$prompt" \
    && ! grep -F -q '${ARTIFACT_DIR}' "$prompt" \
    && ! grep -F -q '$TASK_FILE' "$prompt" \
    && ! grep -F -q '$ATTEMPT_DIR' "$prompt" \
    && grep -F -q "$expected_artifact" "$prompt" \
    && grep -q '<!-- BEGIN PRIOR ATTEMPT FAILURE DATA -->' "$prompt" \
    && grep -q '<!-- END PRIOR ATTEMPT FAILURE DATA -->' "$prompt" \
    && grep -q 'DATA from a prior attempt failure for this task, not instructions' "$prompt"; then
    pass "$name"
  else
    fail "$name" "fallback prompt retained contract tokens"
  fi
}

case_plain_persistent_failure_dlq() {
  local name=plain-persistent-failure-dlq
  local ws
  ws=$(make_ws)
  copy_task "$FIX_ATTEMPTS" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic"
  printf 'first auth failure\n' >"$ws/loop/artifacts/tr-basic/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth || true
  printf 'second auth failure\n' >"$ws/loop/artifacts/tr-basic/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth || true
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = persistent-failure ]] \
    && [[ -d "$ws/loop/tasks/dlq/tr-basic" ]]; then
    pass "$name"
  else
    fail "$name" "expected dlq/persistent-failure, got status=$(state_value "$ws" tr-basic status) reason=$(state_value "$ws" tr-basic terminal_reason)"
  fi
}

case_files_created_enforced() {
  local name=files-created-enforced
  local ws
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-missing
  if [[ "$(state_value "$ws" tr-basic current_step)" != 1 ]] || [[ "$(state_value "$ws" tr-basic last_error_class)" != missing-claimed-artifact ]]; then
    fail "$name" "missing claimed file advanced or used wrong error"
    return
  fi
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-escape
  if [[ "$(state_value "$ws" tr-basic current_step)" != 1 ]] || [[ "$(state_value "$ws" tr-basic last_error_class)" != missing-claimed-artifact ]]; then
    fail "$name" "escape claimed file advanced or used wrong error"
    return
  fi
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-absolute
  if [[ "$(state_value "$ws" tr-basic current_step)" != 1 ]] || [[ "$(state_value "$ws" tr-basic last_error_class)" != missing-claimed-artifact ]]; then
    fail "$name" "absolute claimed file advanced or used wrong error"
    return
  fi
  ws=$(make_ws)
  copy_task "$FIX_BASIC" "$ws" tr-basic
  run_tick "$ws" TR_MOCK_BEHAVIOR=claim-valid
  if [[ "$(state_value "$ws" tr-basic current_step)" = 2 ]]; then
    pass "$name"
  else
    fail "$name" "valid claimed file did not advance"
  fi
}

case_artifact_modes_restrictive() {
  local name=artifact-modes-restrictive
  local ws root task_dir attempt_dir root_mode task_mode attempt_mode stdout_mode stderr_mode prompt_mode
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-basic/attempts/001"
  chmod 0755 "$ws/loop/artifacts" "$ws/loop/artifacts/tr-basic" "$ws/loop/artifacts/tr-basic/attempts/001"
  copy_task "$FIX_BASIC" "$ws" tr-basic
  (
    umask 022
    run_tick "$ws" TR_MOCK_BEHAVIOR=success
  )
  root="$ws/loop/artifacts"
  task_dir="$root/tr-basic"
  attempt_dir="$task_dir/attempts/001"
  root_mode=$(file_mode "$root")
  task_mode=$(file_mode "$task_dir")
  attempt_mode=$(file_mode "$attempt_dir")
  stdout_mode=$(file_mode "$attempt_dir/model.stdout")
  stderr_mode=$(file_mode "$attempt_dir/model.stderr")
  prompt_mode=$(file_mode "$attempt_dir/prompt.md")
  if [[ "$(state_value "$ws" tr-basic status)" = delivered ]] \
    && [[ "$root_mode" = 755 ]] \
    && [[ "$task_mode" = 700 ]] \
    && [[ "$attempt_mode" = 700 ]] \
    && [[ "$stdout_mode" = 600 ]] \
    && [[ "$stderr_mode" = 600 ]] \
    && [[ "$prompt_mode" = 600 ]]; then
    pass "$name"
  else
    fail "$name" "expected restrictive artifact modes: root=$root_mode task=$task_mode attempt=$attempt_mode stdout=$stdout_mode stderr=$stderr_mode prompt=$prompt_mode"
  fi
}

case_crash_verifying_terminal_rederive() {
  # Regression guard (GLM review 2026-07-04, defect 1): a crash inside the
  # verifying window must not lose persistent-failure — recovery re-derives
  # terminals from persisted state instead of granting extra attempts. Vary
  # gate output so this isolates persistent-failure from no-progress.
  local name=crash-verifying-rederive
  local ws
  ws=$(make_ws)
  copy_task "$FIX_ATTEMPTS" "$ws" tr-basic
  mkdir -p "$ws/loop/artifacts/tr-basic"
  printf 'first auth failure\n' >"$ws/loop/artifacts/tr-basic/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth || true
  printf 'second auth failure\n' >"$ws/loop/artifacts/tr-basic/gate-output"
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth TR_CRASH_AFTER=verifying
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=auth
  if [[ "$(state_value "$ws" tr-basic status)" = dlq ]] \
    && [[ "$(state_value "$ws" tr-basic terminal_reason)" = persistent-failure ]] \
    && [[ "$(state_value "$ws" tr-basic attempts_used)" = 2 ]] \
    && [[ -d "$ws/loop/tasks/dlq/tr-basic" ]]; then
    pass "$name"
  else
    fail "$name" "expected dlq/persistent-failure with attempts_used=2, got status=$(state_value "$ws" tr-basic status) reason=$(state_value "$ws" tr-basic terminal_reason) attempts=$(state_value "$ws" tr-basic attempts_used)"
  fi
}

case_ledger_terminal_pre_projection_reconcile() {
  local name=ledger-terminal-pre-projection-reconcile ws artifact rc
  ws=$(make_ws)
  write_runner_task "$ws" ledger-crash out/delivery-receipt.json true
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success TR_CRASH_AFTER=terminal-pre-ledger >/dev/null 2>&1
  rc=$?
  set -e
  artifact="$ws/loop/artifacts/ledger-crash"
  run_tick "$ws" >/dev/null
  run_tick "$ws" >/dev/null
  if [[ "$rc" -eq 137 && -f "$artifact/task-end.json" ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]]; then
    pass "$name"
  else
    fail "$name" "terminal-pre-ledger recovery did not emit one task_end"
  fi
}

case_ledger_fired_delivered_is_completed() {
  local name=ledger-fired-delivered-is-completed ws artifact
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" fired-delivered delivered
  artifact="$ws/loop/artifacts/fired-delivered"
  printf '%s\n' \
    '{"event":"fire","task_id":"fired-delivered","attempt":"001","turn_idx":2}' \
    '{"event":"attempt_end","task_id":"fired-delivered","attempt":"001","started_at":"2026-08-27T00:00:00Z","window_error":true,"runtime_compaction":false,"compaction_suspected":false,"total_tokens":9,"injected_summary":{"max":9,"last3_mean":9},"fired_turns":[2],"alert_turns":[],"nudge_disposition_final":"shown","tap_status":"ok","run_meta":{}}' \
    >"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  if [[ "$(receipt_value "$artifact/task-end.json" outcome)" = completed ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" window_error)" = true ]]; then
    pass "$name"
  else
    fail "$name" "monitor evidence changed delivered outcome"
  fi
}

case_ledger_direct_dlq_reap_folds_once() {
  local name=ledger-direct-dlq-reap-folds-once ws artifact
  ws=$(make_ws)
  write_runner_task "$ws" reap-window out/delivery-receipt.json true
  run_tick "$ws" TR_MOCK_BEHAVIOR=auth-error TR_CRASH_AFTER=stamp >/dev/null 2>&1 || true
  artifact="$ws/loop/artifacts/reap-window"
  printf '%s\n' '{"event":"turn","task_id":"wrong","attempt":"999","turn_idx":1,"input_tokens":1,"cache_read_tokens":0,"cache_creation_tokens":0}' 'not-json' \
    >"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  if [[ "$(state_value "$ws" reap-window status)" = dlq ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" turn)" -eq 1 ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]] \
    && python3 - "$artifact/ledger.jsonl" <<'PY'
import json, sys
rows=[json.loads(line) for line in open(sys.argv[1],encoding="utf-8")]
turn=next(row for row in rows if row.get("event")=="turn")
raw=next(row for row in rows if row.get("parse_error"))
assert turn["task_id"]=="reap-window" and turn["attempt"]=="001"
assert turn["source_task_id"]=="wrong" and turn["source_attempt"]=="999"
assert raw["schema"]=="raw" and raw["task_id"]=="reap-window"
PY
  then
    pass "$name"
  else
    fail "$name" "direct reap DLQ did not fold and emit once"
  fi
}

case_ledger_torn_tail_repair() {
  local name=ledger-torn-tail-repair ws artifact
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" torn delivered
  artifact="$ws/loop/artifacts/torn"
  printf '%s' '{"partial":' >>"$artifact/ledger.jsonl"
  run_tick "$ws" >/dev/null
  if [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]] \
    && [[ "$(tail -c 1 "$artifact/ledger.jsonl")" = '' ]]; then
    pass "$name"
  else
    fail "$name" "torn tail was not isolated before task_end append"
  fi
}

case_ledger_zero_attempt_dlq() {
  local name=ledger-zero-attempt-dlq ws artifact
  ws=$(make_ws)
  write_runner_task "$ws" zero-attempt __missing__ true
  run_tick "$ws" >/dev/null
  artifact="$ws/loop/artifacts/zero-attempt"
  if [[ "$(state_value "$ws" zero-attempt status)" = dlq ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" init)" -eq 1 ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]] \
    && python3 - "$artifact/task-end.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1],encoding="utf-8"))
assert r["total_tokens"] is None and r["window_error"] is None
assert r["runtime_compaction"] is None and r["compaction_suspected"] is None
assert r["fired_turns"] is None and r["alert_turns"] is None
assert r["tap_status"] == "never-ran"
PY
  then
    pass "$name"
  else
    fail "$name" "zero-attempt terminal lacked init/task_end"
  fi
}

case_ledger_driver_outcome_mapping() {
  local name=ledger-driver-outcome-mapping ws root
  ws=$(make_ws); root="$ws/loop/artifacts"
  write_terminal_ledger_fixture "$ws" driver-window dlq attempts-budget window-error
  write_terminal_ledger_fixture "$ws" monitor-only dlq time-budget transient
  printf '%s\n' '{"event":"attempt_end","started_at":"2026-08-27T00:00:00Z","window_error":true,"runtime_compaction":false,"compaction_suspected":false,"total_tokens":1,"injected_summary":{"max":1,"last3_mean":1},"fired_turns":[],"alert_turns":[],"nudge_disposition_final":"none","tap_status":"ok","run_meta":null}' \
    >"$root/monitor-only/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  if [[ "$(receipt_value "$root/driver-window/task-end.json" outcome)" = overflowed ]] \
    && [[ "$(receipt_value "$root/driver-window/task-end.json" terminal_reason)" = attempts-budget ]] \
    && [[ "$(receipt_value "$root/monitor-only/task-end.json" outcome)" = aborted ]] \
    && [[ "$(receipt_value "$root/monitor-only/task-end.json" window_error)" = true ]]; then
    pass "$name"
  else fail "$name" "driver/monitor outcome ownership was violated"; fi
}

case_ledger_window_error_retries_then_overflows() {
  local name=ledger-window-error-retries-then-overflows ws step artifact i
  ws=$(make_ws); write_runner_task "$ws" window-overflow out/delivery-receipt.json true
  step="$ws/window-error-step.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "API Error 400: maximum context length exceeded for this request" >&2' \
    'exit 1' >"$step"
  chmod +x "$step"
  for i in 1 2 3 4; do
    run_tick_with_step "$ws" "$step" >/dev/null 2>&1
  done
  artifact="$ws/loop/artifacts/window-overflow"
  if [[ "$(state_value "$ws" window-overflow status)" = dlq ]] \
    && [[ "$(state_value "$ws" window-overflow terminal_reason)" = infra ]] \
    && [[ "$(state_value "$ws" window-overflow infra_retries)" -eq 4 ]] \
    && [[ "$(state_value "$ws" window-overflow attempts_used)" -eq 0 ]] \
    && [[ "$(driver_value "$ws" window-overflow classified)" = window-error ]] \
    && [[ "$(infra_driver_value "$ws" window-overflow 1 classified)" = window-error ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" outcome)" = overflowed ]]; then
    pass "$name"
  else fail "$name" "window-error did not exhaust infra retries with an overflowed receipt"; fi
}

case_ledger_window_error_recovers_completed() {
  local name=ledger-window-error-recovers-completed ws step artifact rc
  ws=$(make_ws); write_runner_task "$ws" window-recovery out/delivery-receipt.json true
  step="$ws/window-error-step.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "API Error: Prompt is too long for this model" >&2' \
    'exit 1' >"$step"
  chmod +x "$step"
  set +e
  run_tick_with_step "$ws" "$step" TR_CRASH_AFTER=stamp >/dev/null 2>&1
  rc=$?
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=success >/dev/null
  artifact="$ws/loop/artifacts/window-recovery"
  if [[ "$rc" -eq 137 ]] \
    && [[ "$(state_value "$ws" window-recovery status)" = delivered ]] \
    && [[ "$(state_value "$ws" window-recovery infra_retries)" -eq 1 ]] \
    && [[ "$(state_value "$ws" window-recovery attempts_used)" -eq 1 ]] \
    && [[ "$(infra_driver_value "$ws" window-recovery 1 classified)" = window-error ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" outcome)" = completed ]]; then
    pass "$name"
  else fail "$name" "window-error stamp crash/reap recovery did not complete: first_rc=$rc"; fi
}

case_ledger_io_failure_is_fail_open() {
  local name=ledger-io-failure-is-fail-open ws artifact bin real_python marker output warning
  ws=$(make_ws); write_runner_task "$ws" io-fail out/delivery-receipt.json true
  artifact="$ws/loop/artifacts/io-fail"; bin="$ws/python-bin"; marker="$ws/python-failed-once"
  mkdir -p "$bin"; real_python=$(command -v python3)
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [[ "${3:-}" = fold && ! -e "$TR_FAIL_ONCE_MARKER" ]]; then' \
    '  : >"$TR_FAIL_ONCE_MARKER"' \
    '  printf "%s\n" simulated-EROFS' \
    '  exit 1' \
    'fi' \
    'exec "$TR_REAL_PYTHON" "$@"' >"$bin/python3"
  chmod +x "$bin/python3"
  output=$(PATH="$bin:$PATH" TR_REAL_PYTHON="$real_python" TR_FAIL_ONCE_MARKER="$marker" \
    run_tick "$ws" TR_MOCK_BEHAVIOR=success 2>&1)
  warning='task-runner.sh: ledger write failed (simulated-EROFS) — telemetry degraded'
  if [[ "$(state_value "$ws" io-fail status)" = delivered ]] \
    && [[ -f "$ws/loop/tasks/delivered/io-fail/io-fail.task.md" ]] \
    && [[ "$(grep -F -x -c "$warning" <<<"$output")" -eq 1 ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]]; then
    pass "$name"
  else fail "$name" "one ledger error stalled delivery or warning contract drifted: $output"; fi
}

case_ledger_orphan_tail_converges() {
  local name=ledger-orphan-tail-converges ws artifact version1 source_bytes marker_bytes
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" orphan delivered
  artifact="$ws/loop/artifacts/orphan"
  printf '%s\n' '{"event":"turn","turn_idx":1,"input_tokens":1,"cache_read_tokens":0,"cache_creation_tokens":0}' \
    >"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  version1=$(receipt_value "$artifact/task-end.json" receipt_version)
  printf '%s\n' '{"event":"turn","turn_idx":2,"input_tokens":2,"cache_read_tokens":0,"cache_creation_tokens":0}' \
    >>"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  source_bytes=$(wc -c <"$artifact/attempts/001/sentinel-events.jsonl" | tr -d ' ')
  marker_bytes=$(python3 - "$artifact/ledger.jsonl" <<'PY'
import json, sys
values=[]
for line in open(sys.argv[1], encoding="utf-8"):
    try: row=json.loads(line)
    except ValueError: continue
    if row.get("event")=="fold_done": values.append(row["source_bytes_at_fold"])
print(values[-1])
PY
)
  if [[ "$(ledger_event_count "$artifact/ledger.jsonl" turn)" -eq 2 ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" receipt_version)" -gt "$version1" ]] \
    && [[ "$marker_bytes" -eq "$source_bytes" ]]; then
    pass "$name"
  else
    fail "$name" "supplementary tail did not converge"
  fi
}

case_ledger_reconcile_post_race_cache_self_heals() {
  local name=ledger-reconcile-post-race-cache-self-heals ws artifact source fold cache first final i
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" post-race delivered
  artifact="$ws/loop/artifacts/post-race"
  source="$artifact/attempts/001/sentinel-events.jsonl"
  fold="$artifact/attempts/001/.ledger-fold.json"
  cache="$artifact/.ledger-reconcile.json"
  printf '%s\n' '{"event":"turn","turn_idx":1,"input_tokens":1,"cache_read_tokens":0,"cache_creation_tokens":0}' >"$source"
  run_tick "$ws" >/dev/null
  printf '%s\n' '{"event":"turn","turn_idx":2,"input_tokens":2,"cache_read_tokens":0,"cache_creation_tokens":0}' >>"$source"
  python3 - "$source" "$fold" "$cache" <<'PY'
import json, os, sys
source_path, fold_path, cache_path = sys.argv[1:]
source_stat = os.stat(source_path)
fold = json.load(open(fold_path, encoding="utf-8"))
cache = json.load(open(cache_path, encoding="utf-8"))
assert fold["source_bytes_at_fold"] < source_stat.st_size
attempt = cache["signature"]["attempts"][0]
attempt["source_size"] = source_stat.st_size
attempt["source_mtime_ns"] = source_stat.st_mtime_ns
tmp = cache_path + ".tmp-test"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(cache, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
os.replace(tmp, cache_path)
PY
  run_tick "$ws" >/dev/null
  first=$(python3 - "$source" "$fold" "$artifact/task-end.json" "$artifact/ledger.jsonl" <<'PY'
import json, os, sys
source_path, fold_path, receipt_path, ledger_path = sys.argv[1:]
source_size = os.path.getsize(source_path)
folded_size = json.load(open(fold_path, encoding="utf-8"))["source_bytes_at_fold"]
complete = json.load(open(receipt_path, encoding="utf-8"))["fold_complete"]
turns = sum(1 for row in map(json.loads, open(ledger_path, encoding="utf-8")) if row.get("event") == "turn")
print("%s:%s:%s:%s" % (source_size, folded_size, str(complete).lower(), turns))
PY
)
  for i in 2 3 4 5; do run_tick "$ws" >/dev/null; done
  final=$(python3 - "$source" "$fold" "$artifact/task-end.json" "$artifact/ledger.jsonl" <<'PY'
import json, os, sys
source_path, fold_path, receipt_path, ledger_path = sys.argv[1:]
source_size = os.path.getsize(source_path)
folded_size = json.load(open(fold_path, encoding="utf-8"))["source_bytes_at_fold"]
complete = json.load(open(receipt_path, encoding="utf-8"))["fold_complete"]
turns = sum(1 for row in map(json.loads, open(ledger_path, encoding="utf-8")) if row.get("event") == "turn")
print("%s:%s:%s:%s" % (source_size, folded_size, str(complete).lower(), turns))
PY
)
  if [[ "$first" = "$final" ]] \
    && [[ "${first%%:*}" = "$(cut -d: -f2 <<<"$first")" ]] \
    && [[ "$(cut -d: -f3-4 <<<"$first")" = "true:2" ]]; then
    pass "$name"
  else
    fail "$name" "poisoned reconcile cache did not heal on the next tick: first=$first after_5=$final"
  fi
}

case_ledger_receipt_tmp_crash_recovery() {
  local name=ledger-receipt-tmp-crash-recovery ws artifact
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" receipt-tmp delivered
  artifact="$ws/loop/artifacts/receipt-tmp"
  printf '%s\n' '{"receipt_version":1' >"$artifact/task-end.json.tmp.99999"
  run_tick "$ws" >/dev/null
  if [[ -f "$artifact/task-end.json" ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" task_end)" -eq 1 ]]; then
    pass "$name"
  else
    fail "$name" "orphan tmp prevented receipt recovery"
  fi
}

case_ledger_fingerprint_repair_after_emit_failure() {
  local name=ledger-fingerprint-repair-after-emit-failure ws artifact old_version
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" fingerprint delivered
  artifact="$ws/loop/artifacts/fingerprint"
  run_tick "$ws" >/dev/null
  old_version=$(receipt_value "$artifact/task-end.json" receipt_version)
  mv "$artifact/task-end.json" "$artifact/task-end.saved"
  mkdir "$artifact/task-end.json"
  printf '%s\n' '{"event":"turn","turn_idx":1,"input_tokens":3,"cache_read_tokens":0,"cache_creation_tokens":0}' \
    >"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null 2>&1 || true
  rmdir "$artifact/task-end.json"
  mv "$artifact/task-end.saved" "$artifact/task-end.json"
  run_tick "$ws" >/dev/null
  if [[ "$(receipt_value "$artifact/task-end.json" receipt_version)" -gt "$old_version" ]] \
    && [[ "$(ledger_event_count "$artifact/ledger.jsonl" turn)" -eq 1 ]]; then
    pass "$name"
  else
    fail "$name" "fingerprint mismatch did not repair receipt"
  fi
}

case_ledger_quiescence_only_repairs_receipt() {
  local name=ledger-quiescence-only-repairs-receipt ws artifact old_version
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" quiescence delivered
  artifact="$ws/loop/artifacts/quiescence"
  printf '%s\n' '{"event":"turn","turn_idx":1,"input_tokens":1,"cache_read_tokens":0,"cache_creation_tokens":0}' \
    >"$artifact/attempts/001/sentinel-events.jsonl"
  set_terminal_lease "$artifact/state.json" "$$"
  run_tick "$ws" >/dev/null
  old_version=$(receipt_value "$artifact/task-end.json" receipt_version)
  if [[ "$(receipt_value "$artifact/task-end.json" fold_complete)" != false ]]; then
    fail "$name" "live lease was treated as quiescent"
    return
  fi
  set_terminal_lease "$artifact/state.json"
  run_tick "$ws" >/dev/null
  if [[ "$(receipt_value "$artifact/task-end.json" fold_complete)" = true ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" receipt_version)" -gt "$old_version" ]]; then
    pass "$name"
  else
    fail "$name" "quiescence-only fingerprint change was not repaired"
  fi
}

case_ledger_receipt_projection_independent() {
  local name=ledger-receipt-projection-independent ws artifact version
  ws=$(make_ws)
  write_terminal_ledger_fixture "$ws" projection delivered
  artifact="$ws/loop/artifacts/projection"
  run_tick "$ws" >/dev/null
  python3 - "$artifact/task-end.json" <<'PY'
import json, os, sys
path=sys.argv[1]
value=json.load(open(path, encoding="utf-8")); value["receipt_version"] += 1
tmp=path+".tmp-test"
with open(tmp,"w",encoding="utf-8") as f: json.dump(value,f); f.write("\n")
os.replace(tmp,path)
PY
  version=$(receipt_value "$artifact/task-end.json" receipt_version)
  run_tick "$ws" >/dev/null
  if python3 - "$artifact/ledger.jsonl" "$version" <<'PY'
import json, sys
rows=[]
for line in open(sys.argv[1],encoding="utf-8"):
    try: row=json.loads(line)
    except ValueError: continue
    if row.get("event")=="task_end" and row.get("receipt_version")==int(sys.argv[2]): rows.append(row)
raise SystemExit(0 if len(rows)==1 else 1)
PY
  then pass "$name"; else fail "$name" "stale receipt version was not independently projected"; fi
}

write_exact_json_lines() {
  local path=$1 line_bytes=$2 count=$3 partial=${4:-0}
  python3 - "$path" "$line_bytes" "$count" "$partial" <<'PY'
import sys
path, width, count, partial = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
line = b"{}" + b" " * (width - 3) + b"\n"
data = line * count
if partial: data = b'{"event":"turn"'
open(path,"wb").write(data)
PY
}

case_ledger_fold_worked_cases() {
  local name=ledger-fold-worked-cases ws id artifact
  ws=$(make_ws)
  for id in fold64 fold20 fold8; do write_terminal_ledger_fixture "$ws" "$id" delivered; done
  write_exact_json_lines "$ws/loop/artifacts/fold64/attempts/001/sentinel-events.jsonl" 8 8
  write_exact_json_lines "$ws/loop/artifacts/fold20/attempts/001/sentinel-events.jsonl" 5 4
  write_exact_json_lines "$ws/loop/artifacts/fold8/attempts/001/sentinel-events.jsonl" 8 1
  run_tick "$ws" TR_LEDGER_FOLD_TOTAL_MAX_BYTES=16 TR_LEDGER_FOLD_MAX_BYTES=8 >/dev/null
  if python3 - "$ws/loop/artifacts" <<'PY'
import json, os, sys
root=sys.argv[1]
states={name:json.load(open(os.path.join(root,name,"attempts/001/.ledger-fold.json"),encoding="utf-8")) for name in ("fold64","fold20","fold8")}
assert (states["fold64"]["folded_bytes"],states["fold64"]["dropped_bytes"],states["fold64"]["source_bytes_at_fold"],states["fold64"]["budget_remaining"],states["fold64"]["exhausted"]) == (16,48,64,0,True)
assert (states["fold20"]["folded_bytes"],states["fold20"]["dropped_bytes"],states["fold20"]["source_bytes_at_fold"],states["fold20"]["budget_remaining"],states["fold20"]["exhausted"]) == (15,5,20,0,True)
assert (states["fold8"]["folded_bytes"],states["fold8"]["dropped_bytes"],states["fold8"]["source_bytes_at_fold"],states["fold8"]["budget_remaining"],states["fold8"]["exhausted"]) == (8,0,8,8,False)
for name in ("fold64","fold20"): assert sum(1 for row in map(json.loads,open(os.path.join(root,name,"ledger.jsonl"),encoding="utf-8")) if row.get("event")=="fold_exhausted") == 1
PY
  then pass "$name"; else fail "$name" "64/16, 20/16, or 8/16 accounting mismatch"; fi
}

case_ledger_post_exhaustion_is_quiescent() {
  local name=ledger-post-exhaustion-is-quiescent ws artifact bytes version i
  ws=$(make_ws); write_terminal_ledger_fixture "$ws" exhausted delivered
  artifact="$ws/loop/artifacts/exhausted"
  write_exact_json_lines "$artifact/attempts/001/sentinel-events.jsonl" 8 8
  run_tick "$ws" TR_LEDGER_FOLD_TOTAL_MAX_BYTES=16 TR_LEDGER_FOLD_MAX_BYTES=8 >/dev/null
  bytes=$(wc -c <"$artifact/ledger.jsonl" | tr -d ' '); version=$(receipt_value "$artifact/task-end.json" receipt_version)
  for i in 1 2 3; do
    printf '{}\n' >>"$artifact/attempts/001/sentinel-events.jsonl"
    run_tick "$ws" TR_LEDGER_FOLD_TOTAL_MAX_BYTES=16 TR_LEDGER_FOLD_MAX_BYTES=8 >/dev/null
  done
  if [[ "$(wc -c <"$artifact/ledger.jsonl" | tr -d ' ')" -eq "$bytes" ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" receipt_version)" -eq "$version" ]] \
    && [[ "$(receipt_value "$artifact/task-end.json" fold_complete)" = false ]]; then
    pass "$name"
  else fail "$name" "exhausted attempt emitted after adversarial appends"; fi
}

case_ledger_oversize_lines_are_accounted() {
  local name=ledger-oversize-lines-are-accounted ws root
  ws=$(make_ws); root="$ws/loop/artifacts"
  write_terminal_ledger_fixture "$ws" storm delivered; write_terminal_ledger_fixture "$ws" single delivered
  write_exact_json_lines "$root/storm/attempts/001/sentinel-events.jsonl" 8 3
  write_exact_json_lines "$root/single/attempts/001/sentinel-events.jsonl" 8 1
  run_tick "$ws" TR_LEDGER_FOLD_TOTAL_MAX_BYTES=16 TR_LEDGER_FOLD_MAX_BYTES=4 >/dev/null
  if python3 - "$root" <<'PY'
import json, os, sys
root=sys.argv[1]
storm=json.load(open(os.path.join(root,"storm/attempts/001/.ledger-fold.json"),encoding="utf-8"))
single=json.load(open(os.path.join(root,"single/attempts/001/.ledger-fold.json"),encoding="utf-8"))
assert storm["exhausted"] and storm["truncated"] and storm["dropped_bytes"] == 24
assert not single["exhausted"] and single["truncated"] and single["dropped_bytes"] == 8
assert not json.load(open(os.path.join(root,"single/task-end.json"),encoding="utf-8"))["fold_complete"]
assert sum(1 for row in map(json.loads,open(os.path.join(root,"single/ledger.jsonl"),encoding="utf-8")) if row.get("event")=="fold_oversize_line") == 1
PY
  then pass "$name"; else fail "$name" "oversize line truncation totals mismatch"; fi
}

case_ledger_partial_line_completed_once() {
  local name=ledger-partial-line-completed-once ws artifact
  ws=$(make_ws); write_terminal_ledger_fixture "$ws" partial-line delivered
  artifact="$ws/loop/artifacts/partial-line"
  printf '%s' '{"event":"turn","turn_idx":1' >"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  printf '%s\n' '}' >>"$artifact/attempts/001/sentinel-events.jsonl"
  run_tick "$ws" >/dev/null
  if [[ "$(ledger_event_count "$artifact/ledger.jsonl" turn)" -eq 1 ]] \
    && [[ "$(python3 - "$artifact/ledger.jsonl" <<'PY'
import json,sys
print([r["seq"] for r in map(json.loads,open(sys.argv[1],encoding="utf-8")) if r.get("event")=="turn"][-1])
PY
)" -eq 1 ]]; then
    pass "$name"
  else fail "$name" "newline-anchored cursor duplicated or lost completed record"; fi
}

case_ledger_pre_feature_terminal_gate() {
  local name=ledger-pre-feature-terminal-gate ws artifact
  ws=$(make_ws); write_terminal_ledger_fixture "$ws" legacy delivered
  artifact="$ws/loop/artifacts/legacy"; rm "$artifact/ledger.jsonl"
  run_tick "$ws" >/dev/null
  if [[ ! -e "$artifact/task-end.json" && ! -e "$artifact/ledger.jsonl" ]]; then
    pass "$name"
  else fail "$name" "reconcile fabricated telemetry for pre-feature artifact"; fi
}

case_ledger_reconcile_steady_state_is_stat_only() {
  local name=ledger-reconcile-steady-state-is-stat-only ws root trace ops bin real_python before after i
  ws=$(make_ws); root="$ws/loop/artifacts"
  i=1
  while (( i <= 20 )); do
    write_terminal_ledger_fixture "$ws" "steady-$(printf '%02d' "$i")" delivered
    i=$(( i + 1 ))
  done
  trace="$ws/full-parse.trace"
  run_tick "$ws" TR_LEDGER_TEST_FULL_PARSE_MARKER="$trace" >/dev/null
  rm -f "$trace"
  before=$(python3 - "$root" <<'PY'
import glob, os, sys
root=sys.argv[1]
for artifact in sorted(glob.glob(os.path.join(root, "steady-*"))):
    for name in ("ledger.jsonl", "task-end.json", ".ledger-reconcile.json"):
        stat=os.stat(os.path.join(artifact,name))
        print("%s/%s:%s:%s" % (os.path.basename(artifact), name, stat.st_size, stat.st_mtime_ns))
PY
)
  ops="$ws/ledger-ops.trace"; bin="$ws/python-bin"; real_python=$(command -v python3)
  mkdir -p "$bin"
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "${3:-}" in init|fold|catchup|receipt|project|reconcile) printf "%s\n" "$3" >>"$TR_LEDGER_OP_TRACE" ;; esac' \
    'exec "$TR_REAL_PYTHON" "$@"' >"$bin/python3"
  chmod +x "$bin/python3"
  PATH="$bin:$PATH" TR_REAL_PYTHON="$real_python" TR_LEDGER_OP_TRACE="$ops" \
    run_tick "$ws" TR_LEDGER_TEST_FULL_PARSE_MARKER="$trace" >/dev/null
  after=$(python3 - "$root" <<'PY'
import glob, os, sys
root=sys.argv[1]
for artifact in sorted(glob.glob(os.path.join(root, "steady-*"))):
    for name in ("ledger.jsonl", "task-end.json", ".ledger-reconcile.json"):
        stat=os.stat(os.path.join(artifact,name))
        print("%s/%s:%s:%s" % (os.path.basename(artifact), name, stat.st_size, stat.st_mtime_ns))
PY
)
  if [[ "$before" = "$after" ]] \
    && [[ ! -e "$trace" ]] \
    && [[ "$(grep -c '^reconcile$' "$ops")" -eq 20 ]] \
    && ! grep -Eq '^(init|fold|catchup|receipt|project)$' "$ops"; then
    pass "$name"
  else fail "$name" "steady reconcile parsed/wrote telemetry or used split Python operations"; fi
}

case_env_integer_validation
case_startup_ordering_validation
case_corrupt_state_quarantine_continues
case_quoted_id_intake_runner_agree
case_invalid_created_sorts_last
case_trailing_comment_created_parity
case_duplicate_id_scheduler_parser_parity
case_happy_path
case_receipt_file_boundary
case_missing_receipt_dlq_before_spawn
case_receipt_frontmatter_parser_parity
case_donecheck_environment_allowlist
case_donecheck_uses_pinned_interpreters
case_recover_verifying_receipt_boundary
case_missing_donecheck_never_delivers
case_success_next_hint_surface
case_success_next_hint_null_empty_omitted
case_failed_next_hint_stays_retry_only
case_success_next_hint_bound_and_redaction
case_success_next_hint_dedup_and_cap
case_next_hint_is_not_deviation_control
case_success_next_hint_crash_recovery_is_idempotent
case_prompt_render_integration
case_prompt_consult_skill_dir_index
case_prompt_budget_normal
case_prompt_budget_final_attempt_wind_down
case_prompt_budget_mid_budget_no_wind_down
case_prompt_budget_time_exhaustion_wind_down
case_prompt_budget_time_boundary_wind_down
case_prompt_budget_time_above_boundary_no_wind_down
case_paused_step_old_behavior_red
case_paused_step_requeues_without_charge
case_overflow_paused_step_requeues_without_charge
case_paused_step_crash_recovery
case_paused_step_crash_before_stamp_recovery
case_nonpause_status_record_is_not_paused
case_invalid_pause_label_is_not_paused
case_prior_verifier_finding
case_prior_verifier_pass_is_none
case_prior_verifier_step_scoped
case_verify_job_derived_step_reinjects_finding
case_prior_attempt_failure
case_prior_attempt_success_not_injected
case_prior_attempt_result_edge_classes
case_prompt_render_fallback_substitutes_contract_tokens
case_files_created_enforced
case_plain_persistent_failure_dlq
case_artifact_modes_restrictive
case_crash_verifying_terminal_rederive
case_crash_spawn
case_crash_stamp
case_crash_stamp_invalid_receipt_dlq
case_crash_stamp_infra_neutral
case_crash_infra_requeue_recovery
case_crash_infra_terminal_recovery
case_crash_stamp_deterministic_auth_recovery
case_crash_donecheck
case_crash_deliver_terminal_reconcile
case_crash_dlq_terminal_reconcile
case_push_refusal_standalone_operator
case_dlq_push_failure_visible_and_retried
case_push_accepts_credential_metacharacters
case_push_leak_redacts_credential_and_records_failure
case_push_redaction_unit_suppresses_runner_shell_diagnostics
case_resolve_cmd_argv0_allow_empty_strict_mode_safe
case_push_exec_format_error_redacts_argv0_e2e
case_push_refuses_raw_newline_and_carriage_return
case_push_whitespace_only_is_noop
case_push_does_not_expand_tilde
case_push_env_assignment_prefix_reports_127
case_push_multiword_command_succeeds
case_probe_resolution_failure_does_not_leak_value
case_stale_lease_reap
case_future_lease_reap_bounded
case_attempts_exhaustion
case_attempts_exhaustion_reports_actual_failing_donecheck_line
case_time_exhaustion
case_donecheck_timeout_is_tunable
case_timeout_is_chargeable_not_quarantined
case_infra_retries
case_infra_quarantine_collision_fails_open
case_infra_requeues_quarantine_evidence
case_infra_then_success_keeps_failed_evidence
case_infra_exhaustion_keeps_final_attempt
case_infra_exhaustion_reports_no_donecheck_line
case_infra_exhaustion_falls_back_to_donecheck_log
case_infra_exhaustion_prefers_donecheck_failing
case_infra_exhaustion_newest_failing_line_wins
case_infra_exhaustion_newest_log_beats_old_failing_line
case_infra_exhaustion_wide_attempt_number
case_infra_exhaustion_ignores_malformed_failing_lines
case_infra_exhaustion_summaries_use_numeric_order
case_non111_deterministic_auth_dlq
case_non111_permission_error_deterministic_auth_dlq
case_stdout_cli_login_deterministic_auth_dlq
case_non111_unknown_error_uses_infra_retries
case_empty_stderr_is_degenerate_and_retries
case_metrics_idempotent
case_ledger_terminal_pre_projection_reconcile
case_ledger_fired_delivered_is_completed
case_ledger_direct_dlq_reap_folds_once
case_ledger_torn_tail_repair
case_ledger_zero_attempt_dlq
case_ledger_driver_outcome_mapping
case_ledger_window_error_retries_then_overflows
case_ledger_window_error_recovers_completed
case_ledger_io_failure_is_fail_open
case_ledger_orphan_tail_converges
case_ledger_reconcile_post_race_cache_self_heals
case_ledger_receipt_tmp_crash_recovery
case_ledger_fingerprint_repair_after_emit_failure
case_ledger_quiescence_only_repairs_receipt
case_ledger_receipt_projection_independent
case_ledger_fold_worked_cases
case_ledger_post_exhaustion_is_quiescent
case_ledger_oversize_lines_are_accounted
case_ledger_partial_line_completed_once
case_ledger_pre_feature_terminal_gate
case_ledger_reconcile_steady_state_is_stat_only

log "TOTAL pass=$pass_count fail=$fail_count"
if (( fail_count > 0 )); then
  exit 1
fi
