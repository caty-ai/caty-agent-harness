#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
RAW_WEEK=$ROOT/scripts/raw-week.sh
TMP_ROOT=${TMPDIR:-/tmp}/raw-week-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_ROOT"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

new_ws() {
  local name=$1
  local ws=$TMP_ROOT/$name
  mkdir -p "$ws/loop/archive"
  printf '%s\n' "$ws"
}

boundary_failures=0
boundary_details=
while IFS=' ' read -r date expected_week; do
  [[ -n "$date" ]] || continue
  ws=$(new_ws "boundary-$date")
  : >"$ws/loop/archive/flush-$date.md"

  by_week=$("$RAW_WEEK" --workspace "$ws" --week "$expected_week" 2>"$TMP_ROOT/boundary.err")
  week_rc=$?
  by_date=$("$RAW_WEEK" --workspace "$ws" --date "$date" 2>"$TMP_ROOT/boundary-date.err")
  date_rc=$?
  expected_path="loop/archive/flush-$date.md"
  if [[ "$week_rc" -ne 0 || "$date_rc" -ne 0 \
    || "$by_week" != "$expected_path" || "$by_date" != "$expected_path" ]]; then
    boundary_failures=$((boundary_failures + 1))
    boundary_details="${boundary_details}${boundary_details:+; }date=$date expected=$expected_week week_rc=$week_rc date_rc=$date_rc by_week=$by_week by_date=$by_date"
  fi
done <<'BOUNDARIES'
2025-12-29 2026-W01
2026-01-01 2026-W01
2026-01-04 2026-W01
2026-01-05 2026-W02
2026-08-16 2026-W33
2026-08-17 2026-W34
2026-12-31 2026-W53
2027-01-03 2026-W53
2027-01-04 2027-W01
2024-12-30 2025-W01
2021-01-01 2020-W53
BOUNDARIES
if [[ "$boundary_failures" -eq 0 ]]; then
  pass '[1] ISO week arithmetic covers all calendar-year and week boundaries'
else
  fail_case '[1] ISO week arithmetic covers all calendar-year and week boundaries' \
    "$boundary_failures mismatch(es): $boundary_details"
fi

ws=$(new_ws members)
for name in \
  flush-2026-08-16.md \
  flush-2026-08-17.md \
  intake-evictions-2026-08-17.md \
  STATE-full-backup-2026-08-17.md \
  STATE-last-session-archive-2026-08-17.md \
  flush-backlog-backup-2026-08-17.tar.gz \
  retired-checkouts-2026-08-17.tar.gz \
  flush-2026-08-17.md.bak \
  flush-2026-08-17.markdown \
  flush-2026-13-01.md \
  flush-2026-02-30.md; do
  : >"$ws/loop/archive/$name"
done
ln -s retired-checkouts-2026-08-17.tar.gz \
  "$ws/loop/archive/flush-2026-08-18.md"

expected_w34=$(printf '%s\n' \
  'loop/archive/flush-2026-08-17.md' \
  'loop/archive/intake-evictions-2026-08-17.md')
actual_w34=$("$RAW_WEEK" --workspace "$ws" --week 2026-W34 2>"$TMP_ROOT/members.err")
members_rc=$?
if [[ "$members_rc" -eq 0 && "$actual_w34" == "$expected_w34" ]]; then
  pass '[2] only regular files with the two exact raw-layer basenames are members'
else
  fail_case '[2] only regular files with the two exact raw-layer basenames are members' \
    "rc=$members_rc output=$actual_w34"
fi

actual_w33=$("$RAW_WEEK" --workspace "$ws" --week 2026-W33 2>"$TMP_ROOT/split.err")
split_rc=$?
if [[ "$split_rc" -eq 0 && "$actual_w33" == 'loop/archive/flush-2026-08-16.md' \
  && "$actual_w34" != *'2026-08-16'* ]]; then
  pass '[3] Sunday and the following Monday are separated into different weeks'
else
  fail_case '[3] Sunday and the following Monday are separated into different weeks' \
    "w33=$actual_w33 w34=$actual_w34"
fi

assert_usage_error() {
  local label=$1
  shift
  "$RAW_WEEK" "$@" >"$TMP_ROOT/usage.out" 2>"$TMP_ROOT/usage.err"
  local rc=$?
  if [[ "$rc" -eq 2 ]]; then
    pass "$label"
  else
    fail_case "$label" "rc=$rc stderr=$(tr '\n' ' ' <"$TMP_ROOT/usage.err")"
  fi
}

assert_usage_error '[4] simultaneous --week and --date exits 2' \
  --workspace "$ws" --week 2026-W34 --date 2026-08-17
assert_usage_error '[5] omitting both --week and --date exits 2' --workspace "$ws"
assert_usage_error '[6] a non-zero-padded week exits 2' --workspace "$ws" --week 2026-W3
assert_usage_error '[7] omitting --workspace exits 2' --week 2026-W34
assert_usage_error '[8] an impossible date exits 2' --workspace "$ws" --date 2026-02-30
assert_usage_error '[9] a nonexistent ISO week exits 2' --workspace "$ws" --week 2025-W53

missing_ws=$TMP_ROOT/missing-archive
mkdir -p "$missing_ws/loop"
"$RAW_WEEK" --workspace "$missing_ws" --week 2026-W34 \
  >"$TMP_ROOT/missing.out" 2>"$TMP_ROOT/missing.err"
missing_rc=$?
if [[ "$missing_rc" -eq 1 \
  && ! -s "$TMP_ROOT/missing.out" \
  && "$(cat "$TMP_ROOT/missing.err")" == 'missing path: loop/archive/' ]]; then
  pass '[10] a missing archive reports the workspace contract error and exits 1'
else
  fail_case '[10] a missing archive reports the workspace contract error and exits 1' \
    "rc=$missing_rc stdout=$(cat "$TMP_ROOT/missing.out") stderr=$(cat "$TMP_ROOT/missing.err")"
fi

empty_ws=$(new_ws empty)
"$RAW_WEEK" --workspace "$empty_ws" --week 2026-W34 \
  >"$TMP_ROOT/empty.out" 2>"$TMP_ROOT/empty.err"
empty_rc=$?
if [[ "$empty_rc" -eq 0 && ! -s "$TMP_ROOT/empty.out" && ! -s "$TMP_ROOT/empty.err" ]]; then
  pass '[11] an empty raw week has empty output and exits 0'
else
  fail_case '[11] an empty raw week has empty output and exits 0' \
    "rc=$empty_rc stdout=$(cat "$TMP_ROOT/empty.out") stderr=$(cat "$TMP_ROOT/empty.err")"
fi

if [[ -x "$RAW_WEEK" && -x "$0" ]] && bash -n "$RAW_WEEK" && bash -n "$0"; then
  pass '[12] raw-week and its test are executable and syntax-valid'
else
  fail_case '[12] raw-week and its test are executable and syntax-valid' 'executable or syntax contract failed'
fi

if [[ -L "$ws/loop/archive/flush-2026-08-18.md" \
  && "$actual_w34" != *'loop/archive/flush-2026-08-18.md'* ]]; then
  pass '[13] a symlink with a raw-layer basename is not a member'
else
  fail_case '[13] a symlink with a raw-layer basename is not a member' \
    "fixture_is_symlink=$([[ -L "$ws/loop/archive/flush-2026-08-18.md" ]] && printf yes || printf no) output=$actual_w34"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
