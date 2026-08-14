#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t15.XXXXXX") || {
  echo "CHECK a01 FAIL could not create isolated fixture-probe home"
  echo "CHECK a02 FAIL could not create isolated fixture-probe home"
  echo "CHECK a03 FAIL could not create isolated fixture-probe home"
  echo "CHECK a04 FAIL earlier fixture-probe setup failed"
  exit 1
}
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_fixture_check() {
  check_id=$1
  home_name=$2
  pass_msg=$3
  fail_msg=$4
  shift 4
  probe_home="$TEMP_ROOT/$home_name"
  if ! mkdir -p "$probe_home"; then
    fail_check "$check_id" "could not create isolated HOME"
    return
  fi
  if HOME="$probe_home" PYTHONDONTWRITEBYTECODE=1 "$@" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_fixture_pointer() {
  local path matching rc
  for path in README.md README.ja.md README.th.md README.zh.md docs/repository-map.md; do
    [ -f "$path" ] || continue
    matching=$(grep -Ei 'fixtures?' "$path" 2>/dev/null)
    rc=$?
    [ "$rc" -le 1 ] || return 1
    if [ -n "$matching" ] && printf '%s\n' "$matching" | grep -Eiq 'validator|smoke'; then
      return 0
    fi
  done
  return 1
}

run_fixture_check "a01" "budget" \
  "injection-budget-check accepts its bundled input" \
  "injection-budget-check bundled input is missing or does not exit 0" \
  python3 scripts/injection-budget-check --manifest manifests/fixtures/fixed-injection.yaml

run_fixture_check "a02" "lint" \
  "injection-lint accepts its bundled input" \
  "injection-lint bundled input is missing or does not exit 0" \
  python3 scripts/injection-lint --manifest-dir manifests/fixtures/injection --all

run_fixture_check "a03" "watchdog" \
  "watchdog accepts its bundled input" \
  "watchdog bundled input is missing or does not exit 0" \
  python3 scripts/watchdog --jobs-manifest manifests/fixtures/jobs.yaml

if check_fixture_pointer; then
  pass_check "a04" "a README or the repository map points to the fixture set"
else
  fail_check "a04" "no README or repository-map line points to the fixture set"
fi

[ "$failures" -eq 0 ]
