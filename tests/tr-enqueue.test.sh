#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/tr-enqueue
TMP_ROOT=${TMPDIR:-/tmp}/tr-enqueue-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

new_workspace() {
  name=$1
  ws=$TMP_ROOT/ws-$name
  mkdir -p "$ws/loop"
  printf '# State\n' >"$ws/STATE.md"
  printf '%s\n' "$ws"
}

write_task() {
  file=$1
  id=$2
  verify=$3
  attempts_budget=$4
  time_budget_min=$5
  step_lines=$6
  receipt_assertion=$7
  donecheck_extra=$8
  omit_section=$9
  parent_id_value=${10:-null}

  {
    printf '%s\n' '---'
    printf 'id: %s\n' "$id"
    printf '%s\n' 'title: Test task'
    printf '%s\n' 'issued_by: sho-alpha'
    printf '%s\n' 'created: 2026-07-06T00:00:00Z'
    printf 'attempts_budget: %s\n' "$attempts_budget"
    printf 'time_budget_min: %s\n' "$time_budget_min"
    printf '%s\n' 'escalate_to: sho'
    printf 'verify: %s\n' "$verify"
    printf 'parent_id: %s\n' "$parent_id_value"
    printf '%s\n' '---'
    if [ "$omit_section" != "Goal" ]; then
      printf '%s\n\n%s\n\n' '## Goal' 'Test goal.'
    fi
    if [ "$omit_section" != "Done-when" ]; then
      printf '%s\n\n' '## Done-when'
      printf '%s\n' '```donecheck'
      printf '%s\n' 'test -s "$ARTIFACT_DIR/out/image.png"'
      if [ "$receipt_assertion" = "yes" ]; then
        printf '%s\n' 'test -s "$ARTIFACT_DIR/out/delivery-receipt.json"'
      fi
      if [ -n "$donecheck_extra" ]; then
        printf '%s\n' "$donecheck_extra"
      fi
      printf '%s\n\n' '```'
    fi
    if [ "$omit_section" != "Step plan" ]; then
      printf '%s\n\n' '## Step plan'
      printf '%s\n\n' "$step_lines"
    fi
    if [ "$omit_section" != "Resources" ]; then
      printf '%s\n\n%s\n\n' '## Resources' '- ARTIFACT_DIR'
    fi
    if [ "$omit_section" != "Non-goals" ]; then
      printf '%s\n\n%s\n' '## Non-goals' '- None.'
    fi
  } > "$file"
}

run_expect_reject() {
  name=$1
  expected=$2
  task=$3
  ws=$4

  output=$("$SCRIPT" "$task" "$ws" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$output" | grep -q "$expected"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

run_expect_accept() {
  name=$1
  task=$2
  ws=$3
  id=$4

  output=$("$SCRIPT" "$task" "$ws" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$ws/loop/tasks/queue/$id.task.md" ] && [ ! -e "$ws/loop/artifacts/$id/state.json" ]; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

valid_steps='1. Produce "$ARTIFACT_DIR/out/image.png".
2. deliver + capture receipt in "$ARTIFACT_DIR/out/delivery-receipt.json".'

task=$TMP_ROOT/missing-id.task.md
ws=$(new_workspace missing-id)
write_task "$task" "" mechanical 8 30 "$valid_steps" yes "" none
run_expect_reject "reject missing/empty id" "missing/empty id" "$task" "$ws"

task=$TMP_ROOT/missing-created.task.md
ws=$(new_workspace missing-created)
write_task "$task" missing-created mechanical 8 30 "$valid_steps" yes "" none
grep -v '^created:' "$task" >"$task.tmp"
mv "$task.tmp" "$task"
output=$("$SCRIPT" "$task" "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$output" | grep -F -q "created must be UTC ISO-8601 with seconds: value='' file='$task'"; then
  pass "reject missing created"
else
  fail_case "reject missing created" "rc=$rc output=$output"
fi

task=$TMP_ROOT/invalid-created.task.md
ws=$(new_workspace invalid-created)
write_task "$task" invalid-created mechanical 8 30 "$valid_steps" yes "" none
sed 's/^created:.*/created: 2026-02-30T00:00:00Z/' "$task" >"$task.tmp"
mv "$task.tmp" "$task"
output=$("$SCRIPT" "$task" "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$output" | grep -F -q "created must be UTC ISO-8601 with seconds: value='2026-02-30T00:00:00Z' file='$task'"; then
  pass "reject invalid created"
else
  fail_case "reject invalid created" "rc=$rc output=$output"
fi

task=$TMP_ROOT/duplicate.task.md
ws=$(new_workspace duplicate)
write_task "$task" dup-task mechanical 8 30 "$valid_steps" yes "" none
mkdir -p "$ws/loop/tasks/queue"
cp "$task" "$ws/loop/tasks/queue/dup-task.task.md"
run_expect_reject "reject duplicate id" "duplicate id" "$task" "$ws"

task=$TMP_ROOT/bad-dotdot-id.task.md
ws=$(new_workspace bad-dotdot-id)
write_task "$task" "../pwn" mechanical 8 30 "$valid_steps" yes "" none
run_expect_reject "reject dotdot id" "invalid id" "$task" "$ws"

task=$TMP_ROOT/bad-slash-id.task.md
ws=$(new_workspace bad-slash-id)
write_task "$task" "bad/id" mechanical 8 30 "$valid_steps" yes "" none
run_expect_reject "reject slash id" "invalid id" "$task" "$ws"

task=$TMP_ROOT/bad-space-id.task.md
ws=$(new_workspace bad-space-id)
write_task "$task" "bad id" mechanical 8 30 "$valid_steps" yes "" none
run_expect_reject "reject whitespace id" "invalid id" "$task" "$ws"

task=$TMP_ROOT/bad-parent-id.task.md
ws=$(new_workspace bad-parent-id)
write_task "$task" "good-parent-child" mechanical 8 30 "$valid_steps" yes "" none "../pwn"
run_expect_reject "reject unsafe parent_id" "invalid parent_id" "$task" "$ws"

task=$TMP_ROOT/stale-artifact-duplicate.task.md
ws=$(new_workspace stale-artifact-duplicate)
write_task "$task" stale-artifact mechanical 8 30 "$valid_steps" yes "" none
mkdir -p "$ws/loop/artifacts/stale-artifact"
run_expect_reject "reject stale artifact duplicate" "duplicate id" "$task" "$ws"

task=$TMP_ROOT/copy-failure.task.md
ws=$(new_workspace copy-failure)
write_task "$task" copy-failure mechanical 8 30 "$valid_steps" yes "" none
cp_shim=$TMP_ROOT/cp-shim
real_cp=$(command -v cp)
mkdir -p "$cp_shim"
{
  printf '%s\n' '#!/bin/sh'
  printf '%s\n' 'if [ "${TR_ENQUEUE_FAIL_CP:-}" = 1 ]; then exit 1; fi'
  printf 'exec "%s" "$@"\n' "$real_cp"
} >"$cp_shim/cp"
chmod +x "$cp_shim/cp"
output=$(PATH="$cp_shim:$PATH" TR_ENQUEUE_FAIL_CP=1 "$SCRIPT" "$task" "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$output" | grep -F -q 'failed to install task file' \
  && [ ! -e "$ws/loop/artifacts/copy-failure" ] \
  && [ ! -e "$ws/loop/tasks/queue/copy-failure.task.md" ] \
  && ! find "$ws/loop/tasks/queue" -name '.copy-failure.task.md.tmp.*' -print | grep -q .; then
  retry_output=$("$SCRIPT" "$task" "$ws" 2>&1)
  retry_rc=$?
  if [ "$retry_rc" -eq 0 ] \
    && [ -d "$ws/loop/artifacts/copy-failure" ] \
    && [ -f "$ws/loop/tasks/queue/copy-failure.task.md" ]; then
    pass "copy failure leaves no artifact and retry succeeds"
  else
    fail_case "copy failure leaves no artifact and retry succeeds" "retry_rc=$retry_rc output=$retry_output"
  fi
else
  fail_case "copy failure leaves no artifact and retry succeeds" "rc=$rc output=$output"
fi

task=$TMP_ROOT/missing-section.task.md
ws=$(new_workspace missing-section)
write_task "$task" missing-section mechanical 8 30 "$valid_steps" yes "" Resources
run_expect_reject "reject missing body section" "missing required body section: Resources" "$task" "$ws"

task=$TMP_ROOT/no-delivery-step.task.md
ws=$(new_workspace no-delivery-step)
bad_steps='1. Produce "$ARTIFACT_DIR/out/image.png".
2. Stop after local inspection.'
write_task "$task" no-delivery-step mechanical 8 30 "$bad_steps" yes "" none
run_expect_reject "reject last step without deliver/receipt" "last Step-plan step does not mention deliver/receipt" "$task" "$ws"

task=$TMP_ROOT/no-receipt-assertion.task.md
ws=$(new_workspace no-receipt-assertion)
write_task "$task" no-receipt-assertion mechanical 8 30 "$valid_steps" no "" none
run_expect_reject "reject donecheck without receipt assertion" "donecheck has no delivery receipt assertion" "$task" "$ws"

task=$TMP_ROOT/comment-only-receipt.task.md
ws=$(new_workspace comment-only-receipt)
write_task "$task" comment-only-receipt mechanical 8 30 "$valid_steps" no '# test -s "$ARTIFACT_DIR/out/delivery-receipt.json"' none
run_expect_reject "reject comment-only receipt assertion" "donecheck has no delivery receipt assertion" "$task" "$ws"

task=$TMP_ROOT/bad-verify.task.md
ws=$(new_workspace bad-verify)
write_task "$task" bad-verify vision 8 30 "$valid_steps" yes "" none
run_expect_reject "reject non-mechanical verify" "verify must be mechanical" "$task" "$ws"

task=$TMP_ROOT/too-many-steps.task.md
ws=$(new_workspace too-many-steps)
many_steps='1. Step one.
2. Step two.
3. deliver + capture receipt in "$ARTIFACT_DIR/out/delivery-receipt.json".'
write_task "$task" too-many-steps mechanical 2 30 "$many_steps" yes "" none
run_expect_reject "reject plan steps over attempts_budget" "plan-step count exceeds attempts_budget" "$task" "$ws"

task=$TMP_ROOT/timeout-over-budget.task.md
ws=$(new_workspace timeout-over-budget)
write_task "$task" timeout-over-budget mechanical 8 9 "$valid_steps" yes "" none
run_expect_reject "reject step_timeout over time_budget" "global step_timeout exceeds time_budget_min" "$task" "$ws"

task=$TMP_ROOT/bad-donecheck.task.md
ws=$(new_workspace bad-donecheck)
write_task "$task" bad-donecheck mechanical 8 30 "$valid_steps" yes "if then" none
run_expect_reject "reject invalid donecheck syntax" "donecheck fails bash -n" "$task" "$ws"

task=$TMP_ROOT/unwritable-artifacts.task.md
ws=$(new_workspace unwritable-artifacts)
write_task "$task" unwritable-artifacts mechanical 8 30 "$valid_steps" yes "" none
mkdir -p "$ws/loop"
printf '%s\n' "not a dir" > "$ws/loop/artifacts"
run_expect_reject "reject unwritable artifacts dir" "artifacts dir not writable" "$task" "$ws"

task=$TMP_ROOT/warn-low-budget.task.md
ws=$(new_workspace warn-low-budget)
warn_steps='1. Step one.
2. Step two.
3. deliver + capture receipt in "$ARTIFACT_DIR/out/delivery-receipt.json".'
write_task "$task" warn-low-budget mechanical 8 20 "$warn_steps" yes "" none
output=$("$SCRIPT" "$task" "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$output" | grep -q "WARN: time_budget_min is less than plan_steps x 8" && [ -f "$ws/loop/tasks/queue/warn-low-budget.task.md" ]; then
  pass "warn low time budget"
else
  fail_case "warn low time budget" "rc=$rc output=$output"
fi

ws=$(new_workspace pilot)
run_expect_accept "accept pilot example" "$ROOT/templates/examples/img-pilot.task.md" "$ws" "img-pilot-20260706-001"

task=$TMP_ROOT/grep-receipt.task.md
ws=$(new_workspace grep-receipt)
write_task "$task" grep-receipt mechanical 8 30 "$valid_steps" no 'grep -q "\"task_id\"" "$ARTIFACT_DIR/out/delivery-receipt.json"' none
run_expect_accept "accept grep receipt assertion" "$task" "$ws" "grep-receipt"

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
