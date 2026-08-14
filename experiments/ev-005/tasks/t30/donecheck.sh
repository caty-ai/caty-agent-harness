#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

PROBE='.ev005-fixtures/workflow_probe.py'
failures=0
ACTIVE_PROBE_ROOT=''

cleanup_active_probe() {
  if [ -n "$ACTIVE_PROBE_ROOT" ]; then
    rm -rf -- "$ACTIVE_PROBE_ROOT"
    ACTIVE_PROBE_ROOT=''
  fi
}

trap cleanup_active_probe EXIT
trap 'cleanup_active_probe; exit 1' HUP INT TERM

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_isolated_command() {
  local probe_root probe_home probe_tmp rc
  ACTIVE_PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t30-probe.XXXXXX") || {
    ACTIVE_PROBE_ROOT=''
    return 1
  }
  probe_root=$ACTIVE_PROBE_ROOT
  probe_home="$probe_root/home"
  probe_tmp="$probe_root/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    cleanup_active_probe
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@" >/dev/null 2>&1
  rc=$?
  if ! rm -rf -- "$probe_root"; then
    return 1
  fi
  ACTIVE_PROBE_ROOT=''
  return "$rc"
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if run_isolated_command "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

[ -f "$PROBE" ] || {
  fail_check a01 'the bundled workflow probe is missing'
  exit 1
}

# These underlying commands are deliberately executed directly. Hosted Actions
# cannot run in the offline replica, and YAML inspection alone would not prove
# the source-required repository tests or syntax sweep.
run_check a01 'the complete repository shell suite passes' 'make test fails or is not configured' make test
run_check a02 'all tracked shell files pass Bash syntax checking' 'make lint fails or is not configured' make lint
run_check a03 'all five pull-request workflows have the required common structure' 'one or more workflow files or required job names are missing or malformed' python3 -B "$PROBE" common
run_check a04 'the test/lint workflow binds both fail-closed Make targets' 'the test/lint workflow does not bind both Make targets fail-closed' python3 -B "$PROBE" test-lint
run_check a05 'the secret-scanning workflow is range-aware and fail-closed' 'the secret-scanning workflow lacks required fail-closed structure' python3 -B "$PROBE" gitleaks
run_check a06 'the size workflow enforces its limit and exemption path' 'the size workflow lacks limit or exemption enforcement' python3 -B "$PROBE" pr-size
run_check a07 'the history workflow fails closed on common-ancestor resolution' 'the history workflow lacks fail-closed common-ancestor checking' python3 -B "$PROBE" history
run_check a08 'the risk workflow separates gate authority from visibility labels' 'the risk workflow lacks roster, reapproval, or non-authoritative label structure' python3 -B "$PROBE" review

[ "$failures" -eq 0 ]
