#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/probe_recall_env.py'

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_probe() {
  local check_id=$1
  local probe_mode=$2
  local pass_msg=$3
  local fail_msg=$4
  local env_root rc
  if [ ! -f "$PROBE" ]; then
    fail_check "$check_id" "missing bundled behavior probe"
    return
  fi
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t16-probe.XXXXXX") || {
    fail_check "$check_id" "could not create isolated behavior-probe root"
    return
  }
  mkdir -p "$env_root/home" "$env_root/tmp" || {
    rm -rf "$env_root"
    fail_check "$check_id" "could not create isolated HOME and TMPDIR"
    return
  }
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    python3 "$PROBE" "$probe_mode" >/dev/null 2>&1
  rc=$?
  rm -rf "$env_root"
  if [ "$rc" -eq 0 ]; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_recall_tests() {
  local env_root python_path rc
  [ -f scripts/tests/test_recall.py ] || return 1
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t16-tests.XXXXXX") || return 1
  python_path="$env_root/pythonpath"
  mkdir -p "$env_root/home" "$env_root/tmp" "$python_path" || {
    rm -rf "$env_root"
    return 1
  }
  if ! cat >"$python_path/sitecustomize.py" <<'PY'
import os
import pwd


_ISOLATED_HOME = os.environ["HOME"]
_ORIGINAL_GETPWUID = pwd.getpwuid


def _isolated_getpwuid(uid):
    entry = _ORIGINAL_GETPWUID(uid)
    if uid != os.getuid():
        return entry
    fields = list(entry)
    fields[5] = _ISOLATED_HOME
    return pwd.struct_passwd(fields)


pwd.getpwuid = _isolated_getpwuid
PY
  then
    rm -rf "$env_root"
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONPATH="$python_path" \
    PYTHONDONTWRITEBYTECODE=1 \
    python3 scripts/tests/test_recall.py >/dev/null 2>&1
  rc=$?
  rm -rf "$env_root"
  return "$rc"
}

check_docs_enforcement() {
  local matching rc
  [ -f docs/recall-usage.md ] || return 1
  matching=$(grep -Ei '0600' docs/recall-usage.md 2>/dev/null)
  rc=$?
  [ "$rc" -le 1 ] || return 1
  [ -n "$matching" ] || return 1
  printf '%s\n' "$matching" | grep -Eiq 'recall' || return 1
  printf '%s\n' "$matching" | grep -Eiq 'requir|reject|enforc'
}

run_probe "a01" "accept" \
  "recall accepts a mode-0600 credentials env file" \
  "recall does not accept a valid mode-0600 credentials env file"

run_probe "a02" "reject" \
  "recall clearly rejects a non-0600 credentials env file" \
  "recall accepts a non-0600 file or its error does not identify the mode requirement"

run_probe "a03" "test-accept" \
  "the recall regression tests cover mode-0600 acceptance" \
  "no recall regression test mechanically covers mode-0600 acceptance"

run_probe "a04" "test-reject" \
  "the recall regression tests cover non-0600 rejection" \
  "no recall regression test mechanically covers non-0600 rejection"

if check_recall_tests; then
  pass_check "a05" "the targeted recall regression test module passes"
else
  fail_check "a05" "the targeted recall regression test module fails"
fi

if check_docs_enforcement; then
  pass_check "a06" "recall usage documents runtime mode-0600 enforcement"
else
  fail_check "a06" "recall usage does not document runtime mode-0600 enforcement"
fi

[ "$failures" -eq 0 ]
