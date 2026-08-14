#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/t19_probe.sh'

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

check_test_coverage() {
  mode=$1
  python3 - "$mode" <<'PY'
import pathlib
import sys

mode = sys.argv[1]
for path in pathlib.Path("tests").glob("*.test.sh"):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    common = "cron-wrapper.tmpl.sh" in text and "SECRETS_ENV" in text
    if mode == "data":
        covered = common and "touch " in text and "KEY=VALUE" in text and "chmod 600" in text
    else:
        covered = common and "ln -s" in text and "symlink" in text and "chmod 600" in text
    if covered:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

run_check a01 'valid assignments reach the scheduler target' \
  'valid KEY=VALUE input is not exported' bash "$PROBE" assignment
run_check a02 'shell syntax remains inert data' \
  'SECRETS_ENV shell syntax executed or was not preserved as data' bash "$PROBE" inert
run_check a03 'SECRETS_ENV symlinks are refused before target execution' \
  'a SECRETS_ENV symlink was accepted or reached the target' bash "$PROBE" symlink
run_check a04 'a local regression test covers data-only loading' \
  'no data-only loading regression test was found' check_test_coverage data
run_check a05 'a local regression test covers symlink refusal' \
  'no symlink-refusal regression test was found' check_test_coverage symlink

[ "$failures" -eq 0 ]
