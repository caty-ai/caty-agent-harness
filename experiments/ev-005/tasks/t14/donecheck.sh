#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE_ROOT=''

cleanup_probe_root() {
  [ -z "$PROBE_ROOT" ] || rm -rf "$PROBE_ROOT"
  PROBE_ROOT=''
}
trap cleanup_probe_root EXIT HUP INT TERM

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_check() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  shift 3
  if run_isolated "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_isolated() {
  local probe_home probe_tmp rc
  PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t14-probe.XXXXXX") || return 1
  probe_home="$PROBE_ROOT/home"
  probe_tmp="$PROBE_ROOT/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    cleanup_probe_root
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 "$@"
  rc=$?
  cleanup_probe_root
  return "$rc"
}

check_module_field() {
  field=$1
  expected_json=$2
  python3 - "$field" "$expected_json" <<'PY'
import json
import pathlib
import sys

try:
    registry = json.loads(pathlib.Path("registry/modules.json").read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
modules = [module for module in registry.get("modules", []) if module.get("id") == "self-growth-loop"]
if len(modules) != 1:
    raise SystemExit(1)
field = sys.argv[1]
expected = json.loads(sys.argv[2])
if field not in modules[0] or modules[0][field] != expected:
    raise SystemExit(1)
PY
}

run_check "a01" "self-growth repository target is current" "self-growth repository target is not current" check_module_field "repo" '"caty-ai/self-growth-loop"'
run_check "a02" "self-growth status is published" "self-growth status is not published" check_module_field "status" '"published"'
run_check "a03" "self-growth license is MIT" "self-growth license is not MIT" check_module_field "license" '"MIT"'
run_check "a04" "self-growth family footer is enabled" "self-growth family footer is not enabled" check_module_field "footer" 'true'
run_check "a05" "registry checker passes offline" "registry checker fails offline" python3 -B tools/check_registry.py --offline
run_check "a06" "family-footer self-test passes" "family-footer self-test fails" python3 -B tools/selftest_family_footer.py

[ "$failures" -eq 0 ]
