#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/atomic-write-file-test.$$
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

source "$ROOT/scripts/lib-state-fold.sh"

failure_dir=$TMP_ROOT/copy-failure
mkdir -p "$failure_dir"
failure_source=$failure_dir/source
failure_destination=$failure_dir/destination
failure_before=$failure_dir/destination.before
failure_tmp=$failure_dir/.destination.tmp.$$
dd if=/dev/zero of="$failure_source" bs=1024 count=8 2>/dev/null
printf 'original destination content\n' >"$failure_destination"
cp "$failure_destination" "$failure_before"
if (ulimit -f 1; atomic_write_file "$failure_source" "$failure_destination") \
  >"$failure_dir/output" 2>&1; then
  failure_rc=0
else
  failure_rc=$?
fi
if [ "$failure_rc" -ne 0 ] \
  && cmp -s "$failure_before" "$failure_destination" \
  && [ ! -e "$failure_tmp" ]; then
  pass "copy failure preserves destination and removes temporary file"
else
  fail_case "copy failure preserves destination and removes temporary file" \
    "rc=$failure_rc destination_preserved=$(cmp -s "$failure_before" "$failure_destination" && printf yes || printf no) temp_removed=$([ ! -e "$failure_tmp" ] && printf yes || printf no)"
fi

success_dir=$TMP_ROOT/success
mkdir -p "$success_dir"
success_source=$success_dir/source
success_destination=$success_dir/destination
success_tmp=$success_dir/.destination.tmp.$$
dd if=/dev/zero of="$success_source" bs=1024 count=8 2>/dev/null
printf 'old destination content\n' >"$success_destination"
if atomic_write_file "$success_source" "$success_destination"; then
  success_rc=0
else
  success_rc=$?
fi
if [ "$success_rc" -eq 0 ] \
  && cmp -s "$success_source" "$success_destination" \
  && [ ! -e "$success_tmp" ]; then
  pass "successful copy replaces destination byte-for-byte"
else
  fail_case "successful copy replaces destination byte-for-byte" \
    "rc=$success_rc destination_matches=$(cmp -s "$success_source" "$success_destination" && printf yes || printf no) temp_removed=$([ ! -e "$success_tmp" ] && printf yes || printf no)"
fi

directory_dir=$TMP_ROOT/directory-trap
mkdir -p "$directory_dir"
directory_source=$directory_dir/source
directory_destination=$directory_dir/destination
directory_tmp=$directory_dir/.destination.tmp.$$
directory_nested_tmp=$directory_destination/.destination.tmp.$$
printf 'replacement content\n' >"$directory_source"
mkdir -p "$directory_destination"
printf 'sentinel content\n' >"$directory_destination/sentinel"
if atomic_write_file "$directory_source" "$directory_destination"; then
  directory_rc=0
else
  directory_rc=$?
fi
if [ "$directory_rc" -ne 0 ] \
  && [ -d "$directory_destination" ] \
  && [ "$(cat "$directory_destination/sentinel" 2>/dev/null)" = "sentinel content" ] \
  && [ "$(ls -A "$directory_destination")" = "sentinel" ] \
  && [ ! -e "$directory_tmp" ] \
  && [ ! -e "$directory_nested_tmp" ]; then
  pass "existing directory destination is refused without changes"
else
  fail_case "existing directory destination is refused without changes" \
    "rc=$directory_rc entries=$(ls -A "$directory_destination" 2>/dev/null | tr '\n' ',') parent_temp_removed=$([ ! -e "$directory_tmp" ] && printf yes || printf no) nested_temp_removed=$([ ! -e "$directory_nested_tmp" ] && printf yes || printf no)"
fi

symlink_dir=$TMP_ROOT/symlink-dir-trap
mkdir -p "$symlink_dir"
symlink_source=$symlink_dir/source
symlink_real=$symlink_dir/realdir
symlink_destination=$symlink_dir/destination
symlink_tmp=$symlink_dir/.destination.tmp.$$
symlink_nested_tmp=$symlink_real/.destination.tmp.$$
printf 'replacement content\n' >"$symlink_source"
mkdir -p "$symlink_real"
printf 'sentinel content\n' >"$symlink_real/sentinel"
ln -s "$symlink_real" "$symlink_destination"
if atomic_write_file "$symlink_source" "$symlink_destination"; then
  symlink_rc=0
else
  symlink_rc=$?
fi
if [ "$symlink_rc" -ne 0 ] \
  && [ -L "$symlink_destination" ] \
  && [ "$(cat "$symlink_real/sentinel" 2>/dev/null)" = "sentinel content" ] \
  && [ "$(ls -A "$symlink_real")" = "sentinel" ] \
  && [ ! -e "$symlink_tmp" ] \
  && [ ! -e "$symlink_nested_tmp" ]; then
  pass "symlink-to-directory destination is refused with the symlink untouched"
else
  fail_case "symlink-to-directory destination is refused with the symlink untouched" \
    "rc=$symlink_rc still_symlink=$([ -L "$symlink_destination" ] && printf yes || printf no) entries=$(ls -A "$symlink_real" 2>/dev/null | tr '\n' ',') parent_temp_removed=$([ ! -e "$symlink_tmp" ] && printf yes || printf no) nested_temp_removed=$([ ! -e "$symlink_nested_tmp" ] && printf yes || printf no)"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
