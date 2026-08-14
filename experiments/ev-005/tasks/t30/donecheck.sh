#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

PROBE='.ev005-fixtures/workflow_probe.py'
failures=0

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@" >/dev/null 2>&1; then
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
