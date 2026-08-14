#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
NOTE='docs/cli-conventions.md'

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t26-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

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
  if "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_prefix_contract() {
  [ -f "$NOTE" ] || return 1
  grep -Fq '## Output prefixes and streams' "$NOTE" || return 1
  grep -Fq '`warning: `' "$NOTE" || return 1
  grep -Fq '`WARN:`' "$NOTE" || return 1
  grep -Fq '`WARNING:`' "$NOTE" || return 1
  grep -Eq 'FROZEN|frozen' "$NOTE" || return 1
  grep -Eiq 'outlier|defer|deviation' "$NOTE"
}

check_exit_contract() {
  [ -f "$NOTE" ] || return 1
  grep -Fq '## Exit codes' "$NOTE" || return 1
  grep -Eq '^\| `0` \|' "$NOTE" || return 1
  grep -Eq '^\| `1` \|' "$NOTE" || return 1
  grep -Eq '^\| `2` \|' "$NOTE" || return 1
  grep -Fq '`tr-enqueue` uses 1' "$NOTE" || return 1
  grep -Eiq 'known deviation|intentionally.*overload|contractual' "$NOTE" || return 1
  grep -Eq 'Optional .*`FAIL`.*exits? 0|Optional .*`FAIL`.*exit 0' "$NOTE"
}

check_stream_contract() {
  [ -f "$NOTE" ] || return 1
  run_isolated python3 - "$NOTE" <<'PY'
import pathlib
import sys

paragraphs = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split("\n\n")
for paragraph in paragraphs:
    lowered = paragraph.lower()
    if "stdout" in lowered and "stderr" in lowered and "machine" in lowered and "warning:" in lowered:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

check_inventory() {
  [ -f "$NOTE" ] || return 1
  for needle in \
    'missing path:' \
    'scripts/tr-enqueue' \
    'scripts/task-runner.sh' \
    'scripts/family-updater' \
    'tests/check-tickprobe.test.sh' \
    'tests/pause-contract.test.sh' \
    'tests/tr-enqueue.test.sh' \
    'tests/skill-lint.test.sh' \
    'tests/cli-conventions.test.sh'; do
    grep -Fq "$needle" "$NOTE" || return 1
  done
}

check_test_shape() {
  test_file='tests/cli-conventions.test.sh'
  [ -f "$test_file" ] || return 1
  grep -Eq 'task-runner-no-args[[:space:]]+2' "$test_file" || return 1
  grep -Eq 'tr-metrics-bad-usage[[:space:]]+2' "$test_file" || return 1
  grep -Eq 'deadman-probe-bad-usage[[:space:]]+2' "$test_file" || return 1
  grep -Eq 'install-unknown-flag[[:space:]]+2' "$test_file" || return 1
  grep -Eq 'tr-enqueue-usage-error[[:space:]]+1' "$test_file" || return 1
  grep -Fq 'invocations-are-side-effect-free' "$test_file"
}

run_check a01 'warning house style and frozen prefix deviations are documented' \
  'warning prefix convention or deviations are not documented' check_prefix_contract
run_check a02 'exit meanings and frozen exit deviations are documented' \
  'exit meanings or deviations are not documented' check_exit_contract
run_check a03 'machine and human output streams are documented' \
  'stdout/stderr routing contract is incomplete' check_stream_contract
run_check a04 'listed surfaces and regression pins are inventoried' \
  'listed surfaces or regression pins are missing from the note' check_inventory
run_check a05 'focused conventions test pins the usage exits and side-effect boundary' \
  'focused conventions test does not pin the required contracts' check_test_shape
run_check a06 'focused CLI conventions regression passes' \
  'focused CLI conventions regression fails' run_isolated bash tests/cli-conventions.test.sh

[ "$failures" -eq 0 ]
