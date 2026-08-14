#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/input-validation-probe.sh'

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t23-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_probe() {
  check_id=$1
  mode=$2
  pass_msg=$3
  fail_msg=$4
  if [ ! -f "$PROBE" ]; then
    fail_check "$check_id" 'bundled input-validation probe is missing'
  elif run_isolated env EV005_REPO_ROOT="$PWD" bash "$PROBE" "$mode" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_regression_coverage() {
  local runner_test='tests/task-runner.test.sh'
  local enqueue_test='tests/tr-enqueue.test.sh'
  [ -f "$runner_test" ] && [ -f "$enqueue_test" ] || return 1
  grep -Fq 'TR_STEP_TIMEOUT_S' "$runner_test" || return 1
  grep -Fq 'TR_GRACE_S' "$runner_test" || return 1
  grep -Fq 'corrupt state.json' "$runner_test" || return 1
  grep -Eq 'quoted[- ]id' "$runner_test" || return 1
  grep -Eq 'invalid[- ]created' "$runner_test" || return 1
  grep -Eq 'missing[- ]created' "$enqueue_test" || return 1
  grep -Eq 'invalid[- ]created' "$enqueue_test" || return 1
  grep -Eq 'copy[- ]failure' "$enqueue_test"
}

run_probe a01 corrupt-state \
  'corrupt state is diagnosed and isolated while healthy work progresses' \
  'corrupt state crashes, is processed, or prevents healthy work'
run_probe a02 quoted-id \
  'intake and runner agree on a quoted identifier' \
  'quoted identifier is rejected or produces inconsistent artifact identity'
run_probe a03 copy-failure \
  'copy failure leaves no duplicate blocker and retry succeeds' \
  'copy failure leaves partial state or blocks a clean retry'
run_probe a04 created-intake \
  'intake clearly rejects missing and impossible created timestamps' \
  'intake accepts or unclearly rejects an invalid created timestamp'
run_probe a05 created-scheduling \
  'legacy invalid created values are warned and sorted after valid work' \
  'legacy invalid created value silently runs before valid work'
run_probe a06 env-integers \
  'runner clearly rejects bad timeout and grace values before mutation' \
  'runner does not clearly reject bad timeout or grace values'

if check_regression_coverage; then
  pass_check a07 'repository tests cover every listed validation and recovery path'
else
  fail_check a07 'repository test coverage is missing for one or more listed paths'
fi

[ "$failures" -eq 0 ]
