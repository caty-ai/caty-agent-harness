#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0
ISOLATION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t09.XXXXXX" 2>/dev/null) || ISOLATION_ROOT=''

cleanup() {
  [ -z "$ISOLATION_ROOT" ] || rm -rf "$ISOLATION_ROOT"
}
trap cleanup EXIT HUP INT TERM

run_isolated() {
  local env_root rc
  [ -n "$ISOLATION_ROOT" ] || return 1
  env_root=$(mktemp -d "$ISOLATION_ROOT/probe.XXXXXX") || return 1
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    rm -rf "$env_root"
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  rm -rf "$env_root"
  return "$rc"
}

check_cmd() {
  id=$1
  reason=$2
  shift 2
  if run_isolated "$@" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_cmd "a01" "default permission policy accepts a gid mismatch at uid ownership and mode 0600" \
  python3 .ev005-fixtures/permission_probe.py default
check_cmd "a02" "pinned owner policy rejects a uid mismatch" \
  python3 .ev005-fixtures/permission_probe.py pinned-uid
check_cmd "a03" "pinned owner policy rejects a gid mismatch" \
  python3 .ev005-fixtures/permission_probe.py pinned-gid
check_cmd "a04" "repository tests exercise both permission-policy paths" \
  python3 .ev005-fixtures/test_coverage_probe.py

exit "$status"
