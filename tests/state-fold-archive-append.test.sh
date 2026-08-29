#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/state-fold-archive-append-test.$$
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

# shellcheck disable=SC1091
source "$ROOT/scripts/lib-state-fold.sh"

existing_dir=$TMP_ROOT/existing
mkdir -p "$existing_dir"
existing_archive=$existing_dir/archive.md
existing_source=$existing_dir/source.md
existing_expected=$existing_dir/expected.md
existing_tmp=$existing_dir/.archive.md.tmp.$$
printf 'existing archive\nwith a second line\n' >"$existing_archive"
printf 'appended payload\nwith a final line\n' >"$existing_source"
cp "$existing_archive" "$existing_expected"
cat "$existing_source" >>"$existing_expected"
if state_fold_atomic_archive_append "$existing_source" "$existing_archive"; then
  existing_rc=0
else
  existing_rc=$?
fi
if [ "$existing_rc" -eq 0 ] \
  && cmp -s "$existing_expected" "$existing_archive" \
  && [ ! -e "$existing_tmp" ]; then
  pass "existing archive append is byte-exact"
else
  fail_case "existing archive append is byte-exact" \
    "rc=$existing_rc matches=$(cmp -s "$existing_expected" "$existing_archive" && printf yes || printf no) temp_removed=$([ ! -e "$existing_tmp" ] && printf yes || printf no)"
fi

absent_dir=$TMP_ROOT/absent
mkdir -p "$absent_dir"
absent_archive=$absent_dir/archive.md
absent_source=$absent_dir/source.md
absent_tmp=$absent_dir/.archive.md.tmp.$$
printf 'new archive payload\n' >"$absent_source"
if state_fold_atomic_archive_append "$absent_source" "$absent_archive"; then
  absent_rc=0
else
  absent_rc=$?
fi
if [ "$absent_rc" -eq 0 ] \
  && cmp -s "$absent_source" "$absent_archive" \
  && [ ! -e "$absent_tmp" ]; then
  pass "absent archive is created byte-for-byte"
else
  fail_case "absent archive is created byte-for-byte" \
    "rc=$absent_rc matches=$(cmp -s "$absent_source" "$absent_archive" && printf yes || printf no) temp_removed=$([ ! -e "$absent_tmp" ] && printf yes || printf no)"
fi

directory_dir=$TMP_ROOT/directory
mkdir -p "$directory_dir"
directory_archive=$directory_dir/archive.md
directory_source=$directory_dir/source.md
directory_tmp=$directory_dir/.archive.md.tmp.$$
mkdir -p "$directory_archive"
printf 'sentinel\n' >"$directory_archive/sentinel"
printf 'refused payload\n' >"$directory_source"
if state_fold_atomic_archive_append "$directory_source" "$directory_archive"; then
  directory_rc=0
else
  directory_rc=$?
fi
if [ "$directory_rc" -ne 0 ] \
  && [ -d "$directory_archive" ] \
  && [ "$(cat "$directory_archive/sentinel" 2>/dev/null)" = sentinel ] \
  && [ "$(ls -A "$directory_archive")" = sentinel ] \
  && [ ! -e "$directory_tmp" ]; then
  pass "directory destination is refused without a temporary file"
else
  fail_case "directory destination is refused without a temporary file" \
    "rc=$directory_rc entries=$(find "$directory_archive" -mindepth 1 -maxdepth 1 -print 2>/dev/null | tr '\n' ',') temp_removed=$([ ! -e "$directory_tmp" ] && printf yes || printf no)"
fi

copy_dir=$TMP_ROOT/copy-failure
mkdir -p "$copy_dir"
copy_archive=$copy_dir/archive.md
copy_source=$copy_dir/source.md
copy_before=$copy_dir/archive.before
copy_tmp=$copy_dir/.archive.md.tmp.$$
printf 'original archive\n' >"$copy_archive"
printf 'new payload\n' >"$copy_source"
cp "$copy_archive" "$copy_before"
if (
  # shellcheck disable=SC2329
  cp() {
    printf 'partial copy\n' >"$2"
    return 1
  }
  state_fold_atomic_archive_append "$copy_source" "$copy_archive"
); then
  copy_rc=0
else
  copy_rc=$?
fi
if [ "$copy_rc" -ne 0 ] \
  && cmp -s "$copy_before" "$copy_archive" \
  && [ ! -e "$copy_tmp" ]; then
  pass "copy failure preserves the archive and removes its partial temporary file"
else
  fail_case "copy failure preserves the archive and removes its partial temporary file" \
    "rc=$copy_rc preserved=$(cmp -s "$copy_before" "$copy_archive" && printf yes || printf no) temp_removed=$([ ! -e "$copy_tmp" ] && printf yes || printf no)"
fi

move_dir=$TMP_ROOT/move-failure
mkdir -p "$move_dir"
move_archive=$move_dir/archive.md
move_source=$move_dir/source.md
move_before=$move_dir/archive.before
move_tmp=$move_dir/.archive.md.tmp.$$
printf 'original archive\n' >"$move_archive"
printf 'new payload\n' >"$move_source"
cp "$move_archive" "$move_before"
if (
  # shellcheck disable=SC2329
  mv() {
    return 1
  }
  state_fold_atomic_archive_append "$move_source" "$move_archive"
); then
  move_rc=0
else
  move_rc=$?
fi
if [ "$move_rc" -ne 0 ] \
  && cmp -s "$move_before" "$move_archive" \
  && [ ! -e "$move_tmp" ]; then
  pass "move failure preserves the archive and removes the verified temporary file"
else
  fail_case "move failure preserves the archive and removes the verified temporary file" \
    "rc=$move_rc preserved=$(cmp -s "$move_before" "$move_archive" && printf yes || printf no) temp_removed=$([ ! -e "$move_tmp" ] && printf yes || printf no)"
fi

tail_dir=$TMP_ROOT/tail-corruption
mkdir -p "$tail_dir"
tail_archive=$tail_dir/archive.md
tail_source=$tail_dir/source.md
tail_before=$tail_dir/archive.before
tail_tmp=$tail_dir/.archive.md.tmp.$$
printf 'original archive\n' >"$tail_archive"
printf 'expected appended payload\n' >"$tail_source"
cp "$tail_archive" "$tail_before"
tail_source_bytes=$(wc -c <"$tail_source" | tr -d '[:space:]')
if (
  # shellcheck disable=SC2329
  cat() {
    head -c "$tail_source_bytes" /dev/zero | tr '\0' x
  }
  state_fold_atomic_archive_append "$tail_source" "$tail_archive"
); then
  tail_rc=0
else
  tail_rc=$?
fi
if [ "$tail_rc" -ne 0 ] \
  && cmp -s "$tail_before" "$tail_archive" \
  && [ ! -e "$tail_tmp" ]; then
  pass "same-length appended-tail corruption is refused"
else
  fail_case "same-length appended-tail corruption is refused" \
    "rc=$tail_rc preserved=$(cmp -s "$tail_before" "$tail_archive" && printf yes || printf no) temp_removed=$([ ! -e "$tail_tmp" ] && printf yes || printf no)"
fi

prefix_dir=$TMP_ROOT/prefix-corruption
mkdir -p "$prefix_dir"
prefix_archive=$prefix_dir/archive.md
prefix_source=$prefix_dir/source.md
prefix_before=$prefix_dir/archive.before
prefix_tmp=$prefix_dir/.archive.md.tmp.$$
printf 'original archive prefix\n' >"$prefix_archive"
printf 'valid appended payload\n' >"$prefix_source"
cp "$prefix_archive" "$prefix_before"
prefix_bytes=$(wc -c <"$prefix_archive" | tr -d '[:space:]')
if (
  # shellcheck disable=SC2329
  cp() {
    head -c "$prefix_bytes" /dev/zero | tr '\0' x >"$2"
  }
  state_fold_atomic_archive_append "$prefix_source" "$prefix_archive"
); then
  prefix_rc=0
else
  prefix_rc=$?
fi
if [ "$prefix_rc" -ne 0 ] \
  && cmp -s "$prefix_before" "$prefix_archive" \
  && [ ! -e "$prefix_tmp" ]; then
  pass "same-length archive-prefix corruption is refused"
else
  fail_case "same-length archive-prefix corruption is refused" \
    "rc=$prefix_rc preserved=$(cmp -s "$prefix_before" "$prefix_archive" && printf yes || printf no) temp_removed=$([ ! -e "$prefix_tmp" ] && printf yes || printf no)"
fi

empty_dir=$TMP_ROOT/empty-source
mkdir -p "$empty_dir"
empty_archive=$empty_dir/archive.md
empty_source=$empty_dir/source.md
empty_before=$empty_dir/archive.before
empty_probe=$empty_dir/tail-zero.out
empty_tmp=$empty_dir/.archive.md.tmp.$$
printf 'archive unchanged by empty append\n' >"$empty_archive"
: >"$empty_source"
cp "$empty_archive" "$empty_before"
tail -c 0 "$empty_archive" >"$empty_probe"
if state_fold_atomic_archive_append "$empty_source" "$empty_archive"; then
  empty_rc=0
else
  empty_rc=$?
fi
if [ "$empty_rc" -eq 0 ] \
  && cmp -s "$empty_before" "$empty_archive" \
  && cmp -s "$empty_source" "$empty_probe" \
  && [ ! -e "$empty_tmp" ]; then
  pass "zero-byte append succeeds unchanged and tail -c 0 is empty"
else
  fail_case "zero-byte append succeeds unchanged and tail -c 0 is empty" \
    "rc=$empty_rc unchanged=$(cmp -s "$empty_before" "$empty_archive" && printf yes || printf no) tail_zero_empty=$(cmp -s "$empty_source" "$empty_probe" && printf yes || printf no) temp_removed=$([ ! -e "$empty_tmp" ] && printf yes || printf no)"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
