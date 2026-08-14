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
  check_id=$1
  probe_mode=$2
  pass_msg=$3
  fail_msg=$4
  if [ ! -f "$PROBE" ]; then
    fail_check "$check_id" "missing bundled behavior probe"
    return
  fi
  if PYTHONDONTWRITEBYTECODE=1 python3 "$PROBE" "$probe_mode" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_recall_tests() {
  [ -f scripts/tests/test_recall.py ] || return 1
  PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/test_recall.py >/dev/null 2>&1
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
