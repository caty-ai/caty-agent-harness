#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/caty-claude-checkpoint-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail_case() {
  printf 'not ok - %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail_case "$name" "expected=$expected actual=$actual"
  fi
}

run_hook() {
  local sid=$1
  set +e
  printf '{"cwd":"%s","session_id":"%s"}\n' "$ws" "$sid" |
    TMPDIR="$TMP/guards" bash "$ROOT/adapters/claude-code/checkpoint-stop-hook.sh" \
      >"$TMP/hook.stdout" 2>"$TMP/hook.stderr"
  hook_rc=$?
  set -e
}

ws="$TMP/ws"
mkdir -p "$ws" "$TMP/guards"
"$ROOT/install.sh" --workspace "$ws" >/dev/null
ws=$(cd "$ws" && pwd -P)
"$ROOT/install.sh" --enable --workspace "$ws" >/dev/null
sleep 1
printf 'x\n' >"$ws/change.txt"
guard_dir="$TMP/guards/caty-agent-harness-hook"

run_hook 'abc/def'
assert_eq "slash session blocks" "2" "$hook_rc"
grep -Fq 'caty-agent-harness CHECKPOINT' "$TMP/hook.stderr" \
  && pass "slash session emits checkpoint reminder" \
  || fail_case "slash session emits checkpoint reminder" "reminder missing"
[[ -f "$guard_dir/nagged-abcdef" ]] \
  && pass "slash session creates sanitized guard" \
  || fail_case "slash session creates sanitized guard" "nagged-abcdef missing"
[[ ! -e "$guard_dir/abc" ]] \
  && pass "slash session creates no abc path" \
  || fail_case "slash session creates no abc path" "abc path exists"
grep -Fq 'session=abcdef ' "$TMP/hook.stderr" \
  && pass "flush stamp uses sanitized session" \
  || fail_case "flush stamp uses sanitized session" "session=abcdef missing"

run_hook '../../escape'
assert_eq "traversal session blocks" "2" "$hook_rc"
[[ -f "$guard_dir/nagged-....escape" ]] \
  && pass "traversal session keeps dots inside guard directory" \
  || fail_case "traversal session keeps dots inside guard directory" "nagged-....escape missing"
[[ ! -e "$TMP/guards/escape" && ! -e "$TMP/escape" ]] \
  && pass "traversal session creates no escaped paths" \
  || fail_case "traversal session creates no escaped paths" "escaped path exists"

run_hook 'abc/def'
assert_eq "repeated slash session allows stop" "0" "$hook_rc"
assert_eq "repeated slash session has empty stderr" "0" "$(wc -c <"$TMP/hook.stderr" | tr -d ' ')"

run_hook '///'
assert_eq "empty sanitized session blocks" "2" "$hook_rc"
fallback_guard=$(find "$guard_dir" -type f -name 'nagged-cwd-*' -print -quit)
[[ -n "$fallback_guard" ]] \
  && pass "empty sanitized session uses cwd guard fallback" \
  || fail_case "empty sanitized session uses cwd guard fallback" "nagged-cwd-* missing"

printf 'Claude Code checkpoint hook tests: %s failure(s)\n' "$failures"
if (( failures )); then
  exit 1
fi
