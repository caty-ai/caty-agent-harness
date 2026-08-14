#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/t17_probe.sh'

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

check_marker_contract() {
  python3 - <<'PY'
import pathlib
import re

probe = pathlib.Path("scripts/deadman-probe.sh").read_text(encoding="utf-8")
match = re.search(r"^checks=\$\{DEADMAN_CHECKS:-'([^']+)'\}", probe, re.MULTILINE)
if not match:
    raise SystemExit(1)
names = [item.split(":", 1)[0] for item in match.group(1).split()]

templates = []
for path in ("templates/cron-wrapper.tmpl.sh", "templates/launchd.tmpl.plist"):
    templates.append(pathlib.Path(path).read_text(encoding="utf-8"))
markers = set(re.findall(r"\.deadman/[A-Za-z0-9._-]+", "\n".join(templates)))

for name in names:
    expected = f".deadman/{name}.marker"
    if expected not in markers:
        raise SystemExit(1)
    if any(marker.startswith(f".deadman/{name}") and marker != expected for marker in markers):
        raise SystemExit(1)
PY
}

check_marker_regression() {
  python3 - <<'PY'
import pathlib

tests = []
for path in pathlib.Path("tests").glob("*.test.sh"):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    if (
        "deadman-probe.sh" in text
        and "cron-wrapper.tmpl.sh" in text
        and "launchd.tmpl.plist" in text
        and ".marker" in text
        and "DEADMAN_CHECKS" in text
        and ("fail_case" in text or "exit 1" in text)
    ):
        tests.append(path)
if not tests:
    raise SystemExit(1)
PY
}

check_timeout_default() {
  [ -f scripts/task-runner.sh ] || return 1
  grep -Fq 'TR_DONECHECK_TIMEOUT_S=${TR_DONECHECK_TIMEOUT_S-60}' scripts/task-runner.sh \
    && grep -Eq 'for integer_var in .*TR_DONECHECK_TIMEOUT_S' scripts/task-runner.sh
}

check_metrics_baseline() {
  [ -f "$PROBE" ] || return 1
  bash "$PROBE" metrics
}

run_check a01 'failed pushes are recorded beside the report' \
  'failed push evidence is missing' bash "$PROBE" push-record
run_check a02 'failed pushes are surfaced without changing the runner result' \
  'failed push visibility or runner-result behavior is wrong' bash "$PROBE" push-visible
run_check a03 'scheduler marker guidance agrees with probe defaults' \
  'scheduler templates and probe defaults disagree' check_marker_contract
run_check a04 'a regression test covers marker agreement' \
  'no marker-agreement regression test was found' check_marker_regression
run_check a05 'the completion-gate timeout accepts an effective override' \
  'the completion-gate timeout override is ineffective' bash "$PROBE" timeout
run_check a06 'the timeout default is 60 seconds and is integer-validated' \
  'the timeout default or validation is missing' check_timeout_default
run_check a07 'generated metrics contain no fixed B0 estimate row' \
  'the fixed B0 estimate remains in generated metrics' check_metrics_baseline

[ "$failures" -eq 0 ]
