#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TASK_RUNNER="$ROOT/scripts/task-runner.sh"
METRICS="$ROOT/scripts/tr-metrics.sh"
DEADMAN="$ROOT/scripts/deadman-probe.sh"
INSTALL="$ROOT/install.sh"
ENQUEUE="$ROOT/scripts/tr-enqueue"

pass_count=0
fail_count=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cli-conventions-test.XXXXXX")

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

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

CASE_WS="$TMP/workspace"
TEST_HOME="$TMP/home"
COMMAND_TMP="$TMP/command-tmp"
mkdir -p "$CASE_WS" "$TEST_HOME" "$COMMAND_TMP"

snapshot_repo_paths() {
  find "$ROOT" -path "$ROOT/.git" -prune -o -print | LC_ALL=C sort
}

run_expect_exit() {
  local name=$1
  local expected=$2
  shift 2

  local stdout_file="$TMP/$name.stdout"
  local stderr_file="$TMP/$name.stderr"
  local rc
  if (cd "$CASE_WS" && env HOME="$TEST_HOME" TMPDIR="$COMMAND_TMP" "$@") \
    >"$stdout_file" 2>"$stderr_file"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "$rc" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $rc; stderr=$(cat "$stderr_file")"
  fi
}

snapshot_repo_paths >"$TMP/repo-paths.before"
git -C "$ROOT" status --porcelain --untracked-files=all >"$TMP/git-status.before"

run_expect_exit task-runner-no-args 2 env -u TR_SPAWN_STEP "$TASK_RUNNER"
run_expect_exit tr-metrics-bad-usage 2 "$METRICS"
run_expect_exit deadman-probe-bad-usage 2 "$DEADMAN"
run_expect_exit install-unknown-flag 2 "$INSTALL" --not-a-real-option

# #21b may migrate this with owner approval — update this pin in the same PR.
run_expect_exit tr-enqueue-usage-error 1 "$ENQUEUE"

snapshot_repo_paths >"$TMP/repo-paths.after"
git -C "$ROOT" status --porcelain --untracked-files=all >"$TMP/git-status.after"
if cmp -s "$TMP/repo-paths.before" "$TMP/repo-paths.after" \
  && cmp -s "$TMP/git-status.before" "$TMP/git-status.after" \
  && [[ -z "$(find "$CASE_WS" -mindepth 1 -print)" ]]; then
  pass invocations-are-side-effect-free
else
  fail invocations-are-side-effect-free "repository or throwaway workspace changed"
fi

log "TOTAL pass=$pass_count fail=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
