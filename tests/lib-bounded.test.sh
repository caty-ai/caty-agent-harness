#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/scripts/lib-bounded.sh"
TMP_ROOT=${TMPDIR:-/tmp}/lib-bounded-test.$$
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

output=$TMP_ROOT/output.txt
set +e
run_bounded 3 1 bash -c 'printf "bounded output\\n"; exit 7' >"$output"
rc=$?
set -e
if [ "$rc" -eq 7 ] && [ "$(cat "$output")" = 'bounded output' ]; then
  pass "command in time preserves exit code and stdout"
else
  fail_case "command in time preserves exit code and stdout" "rc=$rc output=$(cat "$output" 2>/dev/null)"
fi

start=$SECONDS
set +e
run_bounded 2 1 bash -c 'sleep 60'
rc=$?
set -e
elapsed=$((SECONDS - start))
if [ "$rc" -eq 124 ] && [ "$elapsed" -le 5 ]; then
  pass "timeout returns 124 within wall-clock bound"
else
  fail_case "timeout returns 124 within wall-clock bound" "rc=$rc elapsed=${elapsed}s"
fi

pidfile=$TMP_ROOT/grandchild.pid
set +e
run_bounded 2 1 bash -c 'sleep 60 & printf "%s\\n" "$!" >"$1"; wait' _ "$pidfile"
rc=$?
set -e
grandchild_pid=$(cat "$pidfile" 2>/dev/null || true)
tries=0
while [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null && [ "$tries" -lt 3 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ "$rc" -eq 124 ] && [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass "timeout kills background grandchild in process group"
else
  fail_case "timeout kills background grandchild in process group" "rc=$rc grandchild_pid=$grandchild_pid still_live=$([[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" 2>/dev/null && printf yes || printf no)"
fi

unset BOUNDED_TEST_TIMEOUT || true
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10)
if [ "$resolved" = 42 ]; then
  pass "unset timeout uses default"
else
  fail_case "unset timeout uses default" "resolved=$resolved"
fi

BOUNDED_TEST_TIMEOUT=oops
warning=$TMP_ROOT/non-numeric.stderr
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10 2>"$warning")
if [ "$resolved" = 42 ] && grep -q 'WARNING: BOUNDED_TEST_TIMEOUT=oops is not numeric, using default 42s' "$warning"; then
  pass "non-numeric timeout warns and uses default"
else
  fail_case "non-numeric timeout warns and uses default" "resolved=$resolved warning=$(cat "$warning")"
fi

BOUNDED_TEST_TIMEOUT=1
warning=$TMP_ROOT/low.stderr
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10 2>"$warning")
if [ "$resolved" = 1 ] && grep -q 'WARNING: BOUNDED_TEST_TIMEOUT=1s looks too low' "$warning"; then
  pass "low timeout warns without clamping"
else
  fail_case "low timeout warns without clamping" "resolved=$resolved warning=$(cat "$warning")"
fi

BOUNDED_TEST_TIMEOUT=08
warning=$TMP_ROOT/leading-zero.stderr
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10 2>"$warning")
if [ "$resolved" = 42 ] && grep -q 'WARNING: BOUNDED_TEST_TIMEOUT=08 is not numeric, using default 42s' "$warning"; then
  pass "leading-zero timeout warns and uses default"
else
  fail_case "leading-zero timeout warns and uses default" "resolved=$resolved warning=$(cat "$warning")"
fi

BOUNDED_TEST_TIMEOUT=86401
warning=$TMP_ROOT/high.stderr
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10 2>"$warning")
if [ "$resolved" = 86401 ] && grep -q 'WARNING: BOUNDED_TEST_TIMEOUT=86401s looks too high' "$warning"; then
  pass "high timeout warns without clamping"
else
  fail_case "high timeout warns without clamping" "resolved=$resolved warning=$(cat "$warning")"
fi

BOUNDED_TEST_TIMEOUT=0
warning=$TMP_ROOT/zero.stderr
resolved=$(resolve_timeout_env BOUNDED_TEST_TIMEOUT 42 10 2>"$warning")
if [ "$resolved" = 0 ] && grep -q 'WARNING: BOUNDED_TEST_TIMEOUT=0s looks too low' "$warning"; then
  pass "zero timeout warns without clamping"
else
  fail_case "zero timeout warns without clamping" "resolved=$resolved warning=$(cat "$warning")"
fi

pidfile=$TMP_ROOT/fast-success-grandchild.pid
start=$SECONDS
set +e
run_bounded 10 1 bash -c 'sleep 60 & printf "%s\\n" "$!" >"$1"; exit 0' _ "$pidfile"
rc=$?
set -e
elapsed=$((SECONDS - start))
grandchild_pid=$(cat "$pidfile" 2>/dev/null || true)
tries=0
while [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null && [ "$tries" -lt 3 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ "$rc" -eq 0 ] && [ "$elapsed" -le 3 ] && [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass "fast successful child reaps lingering grandchild without timeout"
else
  fail_case "fast successful child reaps lingering grandchild without timeout" "rc=$rc elapsed=${elapsed}s grandchild_pid=$grandchild_pid"
fi

pidfile=$TMP_ROOT/fast-failure-grandchild.pid
set +e
run_bounded 10 1 bash -c 'sleep 60 & printf "%s\\n" "$!" >"$1"; exit 5' _ "$pidfile"
rc=$?
set -e
grandchild_pid=$(cat "$pidfile" 2>/dev/null || true)
tries=0
while [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null && [ "$tries" -lt 3 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ "$rc" -eq 5 ] && [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass "fast failing child preserves status and reaps lingering grandchild"
else
  fail_case "fast failing child preserves status and reaps lingering grandchild" "rc=$rc grandchild_pid=$grandchild_pid"
fi

pidfile=$TMP_ROOT/quick-grandchild.pid
set +e
run_bounded 10 1 bash -c 'sleep 0.1 & printf "%s\\n" "$!" >"$1"; wait; exit 0' _ "$pidfile"
rc=$?
set -e
grandchild_pid=$(cat "$pidfile" 2>/dev/null || true)
if [ "$rc" -eq 0 ] && [ -n "$grandchild_pid" ] && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass "already-exited grandchild leaves behavior unchanged"
else
  fail_case "already-exited grandchild leaves behavior unchanged" "rc=$rc grandchild_pid=$grandchild_pid"
fi

pidfile=$TMP_ROOT/term-resistant.pid
start=$SECONDS
set +e
run_bounded 2 2 bash -c 'trap "" TERM; printf "%s\\n" "$$" >"$1"; while :; do sleep 60 & wait "$!"; done' _ "$pidfile"
rc=$?
set -e
elapsed=$((SECONDS - start))
child_pid=$(cat "$pidfile" 2>/dev/null || true)
tries=0
while [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null && [ "$tries" -lt 3 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ "$rc" -eq 124 ] && [ "$elapsed" -ge 3 ] && [ "$elapsed" -le 7 ] && [ -n "$child_pid" ] && ! kill -0 "$child_pid" 2>/dev/null; then
  pass "TERM-resistant group escalates to KILL after grace"
else
  fail_case "TERM-resistant group escalates to KILL after grace" "rc=$rc elapsed=${elapsed}s child_pid=$child_pid"
fi

term_child=$TMP_ROOT/term-forward-child.sh
term_wrapper=$TMP_ROOT/term-forward-wrapper.sh
direct_pidfile=$TMP_ROOT/term-forward-direct.pid
grandchild_pidfile=$TMP_ROOT/term-forward-grandchild.pid
cat >"$term_child" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$1"
sleep 60 &
printf '%s\n' "$!" >"$2"
wait
SH
cat >"$term_wrapper" <<'SH'
#!/usr/bin/env bash
source "$1/scripts/lib-bounded.sh"
run_bounded 30 5 "$2" "$3" "$4"
SH
chmod +x "$term_child" "$term_wrapper"
"$term_wrapper" "$ROOT" "$term_child" "$direct_pidfile" "$grandchild_pidfile" &
wrapper_pid=$!
tries=0
while { [ ! -s "$direct_pidfile" ] || [ ! -s "$grandchild_pidfile" ]; } && [ "$tries" -lt 40 ]; do
  sleep 0.1
  tries=$((tries + 1))
done
direct_pid=$(cat "$direct_pidfile" 2>/dev/null || true)
grandchild_pid=$(cat "$grandchild_pidfile" 2>/dev/null || true)
kill -TERM "$wrapper_pid" 2>/dev/null || true
set +e
wait "$wrapper_pid"
rc=$?
set -e
tries=0
while { { [ -n "$direct_pid" ] && kill -0 "$direct_pid" 2>/dev/null; } || { [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null; }; } && [ "$tries" -lt 60 ]; do
  sleep 0.1
  tries=$((tries + 1))
done
if [ "$rc" -eq 143 ] && [ -n "$direct_pid" ] && [ -n "$grandchild_pid" ] && \
   ! kill -0 "$direct_pid" 2>/dev/null && ! kill -0 "$grandchild_pid" 2>/dev/null; then
  pass "TERM forwards to detached child process group"
else
  fail_case "TERM forwards to detached child process group" "rc=$rc direct_pid=$direct_pid grandchild_pid=$grandchild_pid"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
