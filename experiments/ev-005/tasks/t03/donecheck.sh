#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

EXPECT_WORKFLOW_BLOB='f8957a9ab7d2b2b69bf30505f329350d14b725c2'
WORKFLOW_PATH='.github/workflows/review-labels.yml'
failures=0

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_workflow_blob() {
  [ -f "$WORKFLOW_PATH" ] || return 1
  [ "$(git hash-object -- "$WORKFLOW_PATH" 2>/dev/null)" = "$EXPECT_WORKFLOW_BLOB" ]
}

check_auth_none_decl() {
  [ -f "$WORKFLOW_PATH" ] || return 1
  grep -Fq "RISK_PATHS_AUTH='none'" "$WORKFLOW_PATH"
}

check_no_auth_dir_paths() {
  auth_paths=$(git ls-files -- ':(glob,icase)**/auth/**' 2>/dev/null) || return 1
  [ -z "$auth_paths" ]
}

check_no_non_test_auth_like_filenames() {
  local all_paths paths rc
  all_paths=$(git ls-files 2>/dev/null) || return 1
  paths=$(printf '%s\n' "$all_paths" \
    | grep -Evi '^tests/' \
    | grep -Ei '(^|/)[^/]*(auth|signin|token)[^/]*$|(^|/)auth/')
  rc=$?
  [ "$rc" -le 1 ] || return 1
  [ -z "$paths" ]
}

check_billing_none_decl() {
  [ -f "$WORKFLOW_PATH" ] || return 1
  grep -Fq "RISK_PATHS_BILLING='none'" "$WORKFLOW_PATH"
}

check_outbound_none_decl() {
  [ -f "$WORKFLOW_PATH" ] || return 1
  grep -Fq "RISK_PATHS_OUTBOUND='none'" "$WORKFLOW_PATH"
}

check_gates_none_decl() {
  [ -f "$WORKFLOW_PATH" ] || return 1
  grep -Fq "RISK_PATHS_GATES='none'" "$WORKFLOW_PATH"
}

run_check "a01" "workflow matches the required regenerated snapshot" "workflow does not match the required regenerated snapshot" check_workflow_blob
run_check "a02" "AUTH none declaration is present" "AUTH none declaration is missing" check_auth_none_decl
run_check "a03" "no tracked auth directory paths exist" "tracked auth directory paths exist" check_no_auth_dir_paths
run_check "a04" "no non-test auth/signin/token filenames exist" "non-test auth/signin/token filenames exist" check_no_non_test_auth_like_filenames
run_check "a05" "billing none declaration is present" "billing none declaration is missing or changed" check_billing_none_decl
run_check "a06" "outbound none declaration is present" "outbound none declaration is missing or changed" check_outbound_none_decl
run_check "a07" "gates none declaration is present" "gates none declaration is missing or changed" check_gates_none_decl

[ "$failures" -eq 0 ]
