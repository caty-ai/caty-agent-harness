#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNNER="$ROOT/scripts/task-runner.sh"
MOCK="$ROOT/tests/fixtures/mock-spawn-step.sh"
FIXTURE="$ROOT/tests/fixtures/task-no-progress.task.md"

pass_count=0
fail_count=0

pass() { pass_count=$((pass_count + 1)); printf 'PASS %s\n' "$1"; }
fail() { fail_count=$((fail_count + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

make_ws() {
  local ws
  ws=$(mktemp -d "${TMPDIR:-/tmp}/tr-no-progress.XXXXXX")
  mkdir -p "$ws/loop/tasks/queue"
  printf '# State\n' >"$ws/STATE.md"
  cp "$FIXTURE" "$ws/loop/tasks/queue/tr-no-progress.task.md"
  printf '%s\n' "$ws"
}

run_tick() {
  local ws=$1
  shift
  env TR_SPAWN_STEP="$MOCK" "$@" bash "$RUNNER" "$ws"
}

write_inspect_only_task() {
  local ws=$1
  cat >"$ws/loop/tasks/queue/tr-no-progress.task.md" <<'EOF'
---
id: tr-no-progress
title: inspect-only step no-progress regression
issued_by: test
created: 2026-07-19T00:00:00Z
attempts_budget: 6
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Exercise a completed inspect-only step with a silent gate.

## Done-when
```donecheck
test -s "$ARTIFACT_DIR/out/delivery-receipt.json"
grep -q '"step":4' "$ARTIFACT_DIR/out/delivery-receipt.json"
```

## Step plan
1. Prepare.
2. Continue.
3. Inspect existing state only.
4. Deliver.

## Resources
none

## Non-goals
none
EOF
}

state_value() {
  local ws=$1
  local key=$2
  python3 - "$ws/loop/artifacts/tr-no-progress/state.json" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f).get(sys.argv[2])
print("" if value is None else value)
PY
}

write_donecheck_task() {
  local ws=$1
  {
    cat <<'EOF'
---
id: tr-no-progress
title: donecheck instrumentation regression
issued_by: test
created: 2026-07-19T00:00:00Z
attempts_budget: 8
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Exercise the real donecheck wrapper.

## Done-when
```donecheck
EOF
    cat
    cat <<'EOF'
```

## Step plan
1. Prepare.
2. Continue.
3. Inspect.
4. Retry.
5. Verify.
6. Deliver.

## Resources
none

## Non-goals
none
EOF
  } >"$ws/loop/tasks/queue/tr-no-progress.task.md"
}

run_unwrapped_donecheck() {
  local ws=$1
  local check_file=$2
  local output_file=$3
  (
    cd "$ws"
    TASK_ID=tr-no-progress \
      TASK_FILE="$ws/loop/tasks/queue/tr-no-progress.task.md" \
      ARTIFACT_DIR="$ws/loop/artifacts/tr-no-progress" \
      bash -euo pipefail "$check_file"
  ) >"$output_file" 2>&1
}

case_identical_failures_stop() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'assertion failed at %s/run-one on 2026-07-19T01:02:03.456Z\n' "$ws" \
    >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  printf 'assertion failed at %s/run-two on 2026-07-20T04:05:06+07:00\n' "$ws/another-path" \
    >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ -f "$ws/loop/tasks/dlq/tr-no-progress/tr-no-progress.task.md" ]] \
    && [[ ! -d "$ws/loop/artifacts/tr-no-progress/attempts/003" ]]; then
    pass identical-failures-stop
  else
    fail identical-failures-stop "identical normalized failures did not DLQ on attempt 2"
  fi
}

case_different_failures_rearm() {
  local ws first_fp second_fp
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'test alpha failed at %s/alpha 01:02:03\n' "$ws" >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  first_fp=$(state_value "$ws" last_gap_fingerprint)
  printf 'test beta failed at %s/beta 04:05:06\n' "$ws" >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  second_fp=$(state_value "$ws" last_gap_fingerprint)
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ -n "$second_fp" ]] && [[ "$second_fp" != "$first_fp" ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass different-failures-rearm
  else
    fail different-failures-rearm "different failure did not replace the fingerprint and requeue"
  fi
}

case_failure_then_pass_delivers() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'single failure at %s/first 01:02:03\n' "$ws" >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  touch "$ws/loop/artifacts/tr-no-progress/gate-pass"
  mkdir -p "$ws/loop/artifacts/tr-no-progress/out"
  printf '{"task_id":"tr-no-progress"}\n' \
    >"$ws/loop/artifacts/tr-no-progress/out/delivery-receipt.json"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  if [[ "$(state_value "$ws" status)" = delivered ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ -f "$ws/loop/tasks/delivered/tr-no-progress/tr-no-progress.task.md" ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass failure-then-pass-delivers
  else
    fail failure-then-pass-delivers "a later passing gate did not deliver"
  fi
}

case_ratio_and_non_epoch_ids_do_not_collide() {
  local ws first_fp second_fp
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'ratio 1/2 failed for job 1234567890\n' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  first_fp=$(state_value "$ws" last_gap_fingerprint)
  printf 'ratio 1/3 failed for job 9876543210\n' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  second_fp=$(state_value "$ws" last_gap_fingerprint)
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ -n "$second_fp" ]] && [[ "$second_fp" != "$first_fp" ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass ratio-and-non-epoch-ids-do-not-collide
  else
    fail ratio-and-non-epoch-ids-do-not-collide "ratio or non-epoch IDs caused a false no-progress collision"
  fi
}

case_crash_verifying_rederives_no_progress() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'same failure at %s/run 2026-07-19T01:02:03Z\n' "$ws" >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  set +e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error TR_CRASH_AFTER=verifying
  set -e
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]]; then
    pass crash-verifying-rederives-no-progress
  else
    fail crash-verifying-rederives-no-progress "recovery did not derive no-progress after the verifying-window crash"
  fi
}

case_no_progress_outranks_persistent_failure() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf 'same noncomplete gate failure\n' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]]; then
    pass no-progress-outranks-persistent-failure
  else
    fail no-progress-outranks-persistent-failure "no-progress did not override persistent-failure"
  fi
}

case_silent_failures_with_different_exit_codes_rearm() {
  local ws first_fp second_fp
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  : >"$ws/loop/artifacts/tr-no-progress/gate-output"
  printf '%s\n' 3 >"$ws/loop/artifacts/tr-no-progress/gate-exit"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  first_fp=$(state_value "$ws" last_gap_fingerprint)
  printf '%s\n' 5 >"$ws/loop/artifacts/tr-no-progress/gate-exit"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  second_fp=$(state_value "$ws" last_gap_fingerprint)
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ -n "$second_fp" ]] && [[ "$second_fp" != "$first_fp" ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass silent-failures-with-different-exit-codes-rearm
  else
    fail silent-failures-with-different-exit-codes-rearm "different silent-failure exit codes collided"
  fi
}

case_identical_silent_failures_stop() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  : >"$ws/loop/artifacts/tr-no-progress/gate-output"
  printf '%s\n' 3 >"$ws/loop/artifacts/tr-no-progress/gate-exit"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]]; then
    pass identical-silent-failures-stop
  else
    fail identical-silent-failures-stop "identical silent failures did not DLQ on attempt 2"
  fi
}

case_advancing_failure_clears_armed_window() {
  local ws armed_fp armed_step
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf '%s\n' 'identical gate failure' >"$ws/loop/artifacts/tr-no-progress/gate-output"

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  armed_fp=$(state_value "$ws" last_gap_fingerprint)
  armed_step=$(state_value "$ws" last_gap_step)
  if [[ -z "$armed_fp" ]] || [[ -z "$armed_step" ]]; then
    fail advancing-failure-clears-armed-window "initial non-advancing failure did not arm the window"
    return
  fi

  run_tick "$ws"
  if [[ "$(state_value "$ws" status)" != queued ]] \
    || [[ "$(state_value "$ws" last_gap_fingerprint)" != '' ]] \
    || [[ "$(state_value "$ws" last_gap_step)" != '' ]]; then
    fail advancing-failure-clears-armed-window "advancing failed gate did not clear both armed fields"
    return
  fi

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" != queued ]] \
    || [[ -z "$(state_value "$ws" last_gap_fingerprint)" ]] \
    || [[ -z "$(state_value "$ws" last_gap_step)" ]] \
    || [[ -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    fail advancing-failure-clears-armed-window "first post-progress failure DLQed instead of rearming"
    return
  fi

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 4 ]]; then
    pass advancing-failure-clears-armed-window
  else
    fail advancing-failure-clears-armed-window "second post-progress failure did not DLQ for no progress"
  fi
}

case_advance_then_single_identical_failure_does_not_dlq() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf '%s\n' 'identical gate failure' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ "$(state_value "$ws" current_step)" = 2 ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass advance-then-single-identical-failure-does-not-dlq
  else
    fail advance-then-single-identical-failure-does-not-dlq "an advancing attempt armed a threshold-1 no-progress DLQ"
  fi
}

case_advance_then_two_identical_nonadvancing_failures_dlq() {
  local ws
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf '%s\n' 'identical gate failure' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=stable-error
  if [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 3 ]]; then
    pass advance-then-two-identical-nonadvancing-failures-dlq
  else
    fail advance-then-two-identical-nonadvancing-failures-dlq "two identical non-advancing failures did not DLQ"
  fi
}

case_step_progress_suppresses_silent_no_progress() {
  local ws
  ws=$(make_ws)
  write_inspect_only_task "$ws"
  run_tick "$ws"
  run_tick "$ws"
  run_tick "$ws"
  run_tick "$ws"
  if [[ "$(state_value "$ws" status)" = delivered ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 4 ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass step-progress-suppresses-silent-no-progress
  else
    fail step-progress-suppresses-silent-no-progress "completed inspect-only step caused a no-progress DLQ"
  fi
}

case_crash_verifying_rederives_suppressed_no_progress() {
  local ws
  ws=$(make_ws)
  write_inspect_only_task "$ws"
  run_tick "$ws"
  set +e
  run_tick "$ws" TR_CRASH_AFTER=verifying
  set -e
  run_tick "$ws"
  run_tick "$ws"
  if [[ "$(state_value "$ws" status)" = delivered ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 4 ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass crash-verifying-rederives-suppressed-no-progress
  else
    fail crash-verifying-rederives-suppressed-no-progress "recovery did not suppress no-progress after step advance"
  fi
}

case_legacy_state_without_gap_step_fails_open() {
  local ws
  ws=$(make_ws)
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  python3 - "$ws/loop/artifacts/tr-no-progress/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    state = json.load(f)
state.pop("last_gap_step", None)
with open(path, "w", encoding="utf-8") as f:
    json.dump(state, f)
    f.write("\n")
PY
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 2 ]] \
    && [[ -n "$(state_value "$ws" last_gap_step)" ]]; then
    pass legacy-state-without-gap-step-fails-open
  else
    fail legacy-state-without-gap-step-fails-open "old state did not round-trip safely"
  fi
}

case_compute_failure_resets_consecutive_window() {
  local ws middle_fp
  ws=$(make_ws)
  mkdir -p "$ws/loop/artifacts/tr-no-progress"
  printf '%s\n' 'stable gate failure' >"$ws/loop/artifacts/tr-no-progress/gate-output"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  touch "$ws/loop/artifacts/tr-no-progress/gate-remove-log"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  middle_fp=$(state_value "$ws" last_gap_fingerprint)
  rm "$ws/loop/artifacts/tr-no-progress/gate-remove-log"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=gamma-error
  if [[ "$(state_value "$ws" status)" = queued ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = '' ]] \
    && [[ "$(state_value "$ws" attempts_used)" = 3 ]] \
    && [[ "$middle_fp" = '' ]] \
    && [[ -n "$(state_value "$ws" last_gap_fingerprint)" ]] \
    && [[ ! -d "$ws/loop/tasks/dlq/tr-no-progress" ]]; then
    pass compute-failure-resets-consecutive-window
  else
    fail compute-failure-resets-consecutive-window "a stale fingerprint crossed a compute-failure attempt"
  fi
}

case_silent_assertions_have_distinct_attribution() {
  local ws fp_a fp_b failing_a failing_b
  ws=$(make_ws)
  write_donecheck_task "$ws" <<'EOF'
test -f "$ARTIFACT_DIR/assertion-a"
test -f "$ARTIFACT_DIR/assertion-b"
EOF

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  fp_a=$(state_value "$ws" last_gap_fingerprint)
  failing_a=$(cat "$ws/loop/artifacts/tr-no-progress/attempts/001/donecheck.failing")
  touch "$ws/loop/artifacts/tr-no-progress/assertion-a"
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  fp_b=$(state_value "$ws" last_gap_fingerprint)
  failing_b=$(cat "$ws/loop/artifacts/tr-no-progress/attempts/002/donecheck.failing")

  if [[ "$failing_a" = '1: test -f "$ARTIFACT_DIR/assertion-a"' ]] \
    && [[ "$failing_b" = '2: test -f "$ARTIFACT_DIR/assertion-b"' ]] \
    && [[ -n "$fp_a" ]] && [[ -n "$fp_b" ]] && [[ "$fp_a" != "$fp_b" ]] \
    && [[ ! -s "$ws/loop/artifacts/tr-no-progress/attempts/001/donecheck.log" ]] \
    && [[ ! -s "$ws/loop/artifacts/tr-no-progress/attempts/002/donecheck.log" ]] \
    && [[ "$(state_value "$ws" status)" = queued ]]; then
    pass silent-assertions-have-distinct-attribution
  else
    fail silent-assertions-have-distinct-attribution "silent assertion identity or relative line attribution was lost"
  fi
}

case_pipeline_attribution_is_one_physical_line() {
  local ws failing_file ws_backslash failing_backslash
  ws=$(make_ws)
  write_donecheck_task "$ws" <<'EOF'
printf 'left side\n' |
  grep -q 'right side'
EOF

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=pipeline-error
  failing_file="$ws/loop/artifacts/tr-no-progress/attempts/001/donecheck.failing"
  if [[ "$(wc -l <"$failing_file" | tr -d '[:space:]')" != 1 ]] \
    || ! grep -Fq "2: printf 'left side\n' |   grep -q 'right side'" "$failing_file"; then
    fail pipeline-attribution-is-one-physical-line "failing pipeline was split or reduced to its final command"
    return
  fi

  ws_backslash=$(make_ws)
  write_donecheck_task "$ws_backslash" <<'EOF'
printf 'left side\n' \
  | grep -q 'right side' \
  | cat
EOF
  run_tick "$ws_backslash" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=pipeline-error
  failing_backslash="$ws_backslash/loop/artifacts/tr-no-progress/attempts/001/donecheck.failing"
  if [[ "$(wc -l <"$failing_backslash" | tr -d '[:space:]')" = 1 ]] \
    && grep -Fq "3: printf 'left side\n'" "$failing_backslash" \
    && grep -Fq "| grep -q 'right side'" "$failing_backslash" \
    && grep -Fq '| cat' "$failing_backslash"; then
    pass pipeline-attribution-is-one-physical-line
  else
    fail pipeline-attribution-is-one-physical-line "backslash-continued pipeline lost its earlier stages"
  fi
}

case_fd3_is_owned_by_donecheck() {
  local ws attempt1 attempt2 fail_unwrapped pass_unwrapped unwrapped_rc
  ws=$(make_ws)
  write_donecheck_task "$ws" <<'EOF'
printf 'fd3 visible output\n'
exec 3>&-
exec 3>"$ARTIFACT_DIR/fd3-own"
printf 'owned by donecheck\n' >&3
test -f "$ARTIFACT_DIR/fd3-pass"
EOF

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  attempt1="$ws/loop/artifacts/tr-no-progress/attempts/001"
  fail_unwrapped="$ws/fd3-fail.unwrapped.log"
  unwrapped_rc=0
  run_unwrapped_donecheck "$ws" "$attempt1/donecheck.sh" "$fail_unwrapped" || unwrapped_rc=$?
  if [[ "$unwrapped_rc" != 1 ]] \
    || ! cmp -s "$attempt1/donecheck.log" "$fail_unwrapped" \
    || [[ "$(cat "$attempt1/donecheck.failing")" != '5: test -f "$ARTIFACT_DIR/fd3-pass"' ]] \
    || [[ "$(cat "$ws/loop/artifacts/tr-no-progress/fd3-own")" != 'owned by donecheck' ]]; then
    fail fd3-is-owned-by-donecheck "fd 3 changed failing behavior, output, or attribution"
    return
  fi

  touch "$ws/loop/artifacts/tr-no-progress/fd3-pass"
  pass_unwrapped="$ws/fd3-pass.unwrapped.log"
  unwrapped_rc=0
  run_unwrapped_donecheck "$ws" "$attempt1/donecheck.sh" "$pass_unwrapped" || unwrapped_rc=$?
  if [[ "$unwrapped_rc" != 0 ]]; then
    fail fd3-is-owned-by-donecheck "unwrapped fd 3 donecheck did not pass"
    return
  fi

  run_tick "$ws"
  attempt2="$ws/loop/artifacts/tr-no-progress/attempts/002"
  if [[ "$(state_value "$ws" status)" = delivered ]] \
    && cmp -s "$attempt2/donecheck.log" "$pass_unwrapped" \
    && [[ ! -s "$attempt2/donecheck.trace" ]] \
    && [[ ! -e "$attempt2/donecheck.failing" ]]; then
    pass fd3-is-owned-by-donecheck
  else
    fail fd3-is-owned-by-donecheck "fd 3 changed passing behavior or donecheck.log bytes"
  fi
}

case_failing_absolute_paths_are_masked() {
  local ws attempt1_path attempt2_path fp1 fp2
  ws=$(make_ws)
  attempt1_path="$ws/loop/artifacts/tr-no-progress/attempts/001"
  attempt2_path="$ws/loop/artifacts/tr-no-progress/attempts/002"
  write_donecheck_task "$ws" <<EOF
test -f "$attempt1_path/missing"
EOF

  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=alpha-error
  fp1=$(state_value "$ws" last_gap_fingerprint)
  if ! grep -Fq "$attempt1_path/missing" "$attempt1_path/donecheck.failing"; then
    fail failing-absolute-paths-are-masked "first attribution did not contain its absolute attempt path"
    return
  fi

  write_donecheck_task "$ws" <<EOF
test -f "$attempt2_path/missing"
EOF
  run_tick "$ws" TR_MOCK_BEHAVIOR=noncomplete TR_MOCK_ERROR_CLASS=beta-error
  fp2=$(state_value "$ws" last_gap_fingerprint)
  if grep -Fq "$attempt2_path/missing" "$attempt2_path/donecheck.failing" \
    && [[ -n "$fp1" ]] && [[ "$fp1" = "$fp2" ]] \
    && [[ "$(state_value "$ws" status)" = dlq ]] \
    && [[ "$(state_value "$ws" terminal_reason)" = no-progress ]]; then
    pass failing-absolute-paths-are-masked
  else
    fail failing-absolute-paths-are-masked "attempt-directory paths produced different gap fingerprints"
  fi
}

case_identical_failures_stop
case_different_failures_rearm
case_failure_then_pass_delivers
case_ratio_and_non_epoch_ids_do_not_collide
case_crash_verifying_rederives_no_progress
case_no_progress_outranks_persistent_failure
case_silent_failures_with_different_exit_codes_rearm
case_identical_silent_failures_stop
case_advancing_failure_clears_armed_window
case_compute_failure_resets_consecutive_window
case_advance_then_single_identical_failure_does_not_dlq
case_advance_then_two_identical_nonadvancing_failures_dlq
case_step_progress_suppresses_silent_no_progress
case_crash_verifying_rederives_suppressed_no_progress
case_legacy_state_without_gap_step_fails_open
case_silent_assertions_have_distinct_attribution
case_pipeline_attribution_is_one_physical_line
case_fd3_is_owned_by_donecheck
case_failing_absolute_paths_are_masked

printf '%s passed, %s failed\n' "$pass_count" "$fail_count"
[[ "$fail_count" -eq 0 ]]
