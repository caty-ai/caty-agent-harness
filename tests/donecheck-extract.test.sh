#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/lib-donecheck.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/donecheck-extract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
pass_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

expect_status() {
  local name=$1 expected=$2 input=$3 output rc
  output="$tmp/$name.out"
  set +e
  caty_extract_donecheck "$input" "$output"
  rc=$?
  set -e
  if [[ "$rc" -eq "$expected" ]] && [[ ! -e "$output" ]]; then
    pass "$name"
  else
    fail "$name" "expected status=$expected/no output, got status=$rc output_exists=$([[ -e "$output" ]] && echo yes || echo no)"
  fi
}

cat >"$tmp/indented-heredoc.task.md" <<'EOF'
```donecheck
cat <<'TEXT' >/dev/null
  ```donecheck
TEXT
echo ok
```
EOF
if caty_extract_donecheck "$tmp/indented-heredoc.task.md" "$tmp/indented-heredoc.out" \
  && grep -Fqx '  ```donecheck' "$tmp/indented-heredoc.out" \
  && bash -n "$tmp/indented-heredoc.out"; then
  pass indented-fence-is-not-opener
else
  fail indented-fence-is-not-opener 'indented fence was not preserved inside the single block'
fi

printf '%s\r\n' '```donecheck' 'echo crlf' '```' >"$tmp/crlf.task.md"
if caty_extract_donecheck "$tmp/crlf.task.md" "$tmp/crlf.out" \
  && [[ "$(od -An -t x1 "$tmp/crlf.out" | tr -d '[:space:]')" = 6563686f2063726c660a ]]; then
  pass crlf-normalized-to-lf
else
  fail crlf-normalized-to-lf 'extracted bytes were not LF-normalized'
fi

printf '%s\n%s\n%s' '```donecheck' 'echo no-final-newline' '```' >"$tmp/no-final-newline.task.md"
if caty_extract_donecheck "$tmp/no-final-newline.task.md" "$tmp/no-final-newline.out" \
  && [[ "$(cat "$tmp/no-final-newline.out")" = 'echo no-final-newline' ]]; then
  pass missing-final-newline
else
  fail missing-final-newline 'closing fence without final LF was not accepted'
fi

cat >"$tmp/second-opener.task.md" <<'EOF'
```donecheck
true
```
ordinary text
```donecheck
false
```
EOF
expect_status second-opener-after-close 4 "$tmp/second-opener.task.md"

printf '%s\n' '```donecheck' 'true' >"$tmp/unclosed.task.md"
expect_status unclosed-fence 5 "$tmp/unclosed.task.md"

printf '%s\n' '```donecheck extra' 'true' '```' >"$tmp/info-string.task.md"
expect_status info-string-not-opener 2 "$tmp/info-string.task.md"

printf '\377```donecheck\ntrue\n```\n' >"$tmp/non-utf8.task.md"
expect_status non-utf8 3 "$tmp/non-utf8.task.md"

cat >"$tmp/column-zero-heredoc.task.md" <<'EOF'
```donecheck
cat <<'TEXT'
```
echo this-is-outside-the-extracted-block
TEXT
```
EOF
if caty_extract_donecheck "$tmp/column-zero-heredoc.task.md" "$tmp/column-zero-heredoc.out" \
  && [[ "$(cat "$tmp/column-zero-heredoc.out")" = "cat <<'TEXT'" ]] \
  && bash -n "$tmp/column-zero-heredoc.out" >/dev/null 2>&1; then
  pass column-zero-fence-textually-truncates-heredoc
else
  fail column-zero-fence-textually-truncates-heredoc 'documented textual truncation behavior changed'
fi

install_ws="$tmp/install-workspace"
if "$ROOT/install.sh" --workspace "$install_ws" >/dev/null \
  && [[ -f "$install_ws/loop/.tr-interpreters" ]] \
  && [[ "$(sed -n '1p' "$install_ws/loop/.tr-interpreters")" = TR_BASH=/* ]] \
  && [[ "$(sed -n '2p' "$install_ws/loop/.tr-interpreters")" = TR_PERL=/* ]]; then
  source "$install_ws/loop/.tr-interpreters"
  if [[ -x "$TR_BASH" && -x "$TR_PERL" ]]; then
    pass install-records-absolute-interpreters
  else
    fail install-records-absolute-interpreters 'recorded interpreter is not executable'
  fi
else
  fail install-records-absolute-interpreters 'install did not create the two-line interpreter record'
fi

invalid_record="$tmp/invalid-interpreters"
printf '%s\n' 'TR_BASH=relative/bash' 'TR_PERL=/usr/bin/perl' >"$invalid_record"
set +e
invalid_output=$(caty_read_interpreters "$invalid_record" 2>&1)
invalid_rc=$?
set -e
if [[ "$invalid_rc" -ne 0 ]] \
  && grep -Fq "file=$invalid_record" <<<"$invalid_output" \
  && grep -Fq 'value=relative/bash' <<<"$invalid_output"; then
  pass invalid-interpreter-record-fails-closed
else
  fail invalid-interpreter-record-fails-closed "rc=$invalid_rc output=$invalid_output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$pass_count" "$fail_count"
[[ "$fail_count" -eq 0 ]]
