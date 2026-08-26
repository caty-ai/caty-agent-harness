#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/lib-classify.sh"
FIXTURES="$ROOT/tests/fixtures/classify"

pass_count=0
fail_count=0

check() {
  local name=$1
  local exit_code=$2
  local fixture=$3
  local expected=$4
  local actual

  actual=$(classify_failure "$exit_code" "$FIXTURES/$fixture")
  if [[ "$actual" = "$expected" ]]; then
    pass_count=$(( pass_count + 1 ))
    printf 'PASS %s\n' "$name"
  else
    fail_count=$(( fail_count + 1 ))
    printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$actual"
  fi
}

check_with_stdout() {
  local name=$1
  local exit_code=$2
  local stderr_fixture=$3
  local stdout_fixture=$4
  local expected=$5
  local actual

  actual=$(classify_failure "$exit_code" "$FIXTURES/$stderr_fixture" "$FIXTURES/$stdout_fixture")
  if [[ "$actual" = "$expected" ]]; then
    pass_count=$(( pass_count + 1 ))
    printf 'PASS %s\n' "$name"
  else
    fail_count=$(( fail_count + 1 ))
    printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$actual"
  fi
}

check_files() {
  local name=$1
  local exit_code=$2
  local stderr_file=$3
  local stdout_file=$4
  local expected=$5
  local actual

  actual=$(classify_failure "$exit_code" "$stderr_file" "$stdout_file")
  if [[ "$actual" = "$expected" ]]; then
    pass_count=$(( pass_count + 1 ))
    printf 'PASS %s\n' "$name"
  else
    fail_count=$(( fail_count + 1 ))
    printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$actual"
  fi
}

fill_bytes() {
  local count=$1
  LC_ALL=C head -c "$count" /dev/zero | LC_ALL=C tr '\000' x
}

check auth-401 1 auth-401.json deterministic-auth
check auth-403 1 auth-403.json deterministic-auth
check auth-403-permission 1 auth-403-permission.json deterministic-auth
check auth-402-billing 1 auth-402-billing.json deterministic-auth
check oauth-invalid-grant 1 oauth-invalid-grant.json deterministic-auth
check invalid-request 1 invalid-request.json deterministic-input
check rate-limit 1 rate-limit.json transient
check timeout-408 1 timeout-408.json transient
check context-4xx 1 context-4xx.json context-overflow
check context-500 1 context-500.json context-overflow
check degenerate-empty 1 degenerate-empty.txt degenerate
check unknown-is-transient 1 unknown.json transient
check short-transient 1 short-transient.txt transient
check axios-401 1 axios-401.txt deterministic-auth
check curl-422 1 curl-422.txt deterministic-input
check gemini-code-400 1 gemini-code-400.json deterministic-input
check axios-429 1 axios-429.txt transient
check mixed-429-authkey 1 mixed-429-authkey.txt transient
check degenerate-whitespace 1 degenerate-whitespace.txt degenerate
check signal-137 137 unknown.json transient
check backward-compatible-two-arg-auth 1 auth-401.json deterministic-auth
check_with_stdout stdout-only-cli-login 1 degenerate-empty.txt cli-not-logged-in.txt deterministic-auth
check_with_stdout stdout-oauth-invalid-grant 1 degenerate-empty.txt oauth-invalid-grant.json deterministic-auth
check_with_stdout stdout-auth-permission 1 degenerate-empty.txt auth-403-permission.json deterministic-auth
check_with_stdout stdout-auth-billing 1 degenerate-empty.txt auth-402-billing.json deterministic-auth
check_with_stdout empty-stderr-and-stdout 1 degenerate-empty.txt degenerate-empty.txt degenerate
check_with_stdout combined-transient-wins-over-auth 1 rate-limit.json cli-not-logged-in.txt transient

missing_stdout=$(classify_failure 1 "$FIXTURES/auth-401.json" /path/that/does/not/exist)
if [[ "$missing_stdout" = deterministic-auth ]]; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS missing-stdout-does-not-mask-stderr-auth\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL missing-stdout-does-not-mask-stderr-auth: expected deterministic-auth, got %s\n' "$missing_stdout"
fi

missing_stderr=$(classify_failure 1 /path/that/does/not/exist)
if [[ "$missing_stderr" = degenerate ]]; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS missing-stderr-is-degenerate\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL missing-stderr-is-degenerate: expected degenerate, got %s\n' "$missing_stderr"
fi

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/lib-classify.XXXXXX")
trap 'chmod -R u+rwX "$test_tmp" 2>/dev/null || true; rm -rf "$test_tmp"' EXIT

empty_stderr="$test_tmp/empty.stderr"
unknown_stderr="$test_tmp/unknown.stderr"
structural_429="$test_tmp/structural-429.stdout"
split_stderr="$test_tmp/split.stderr"
split_stdout="$test_tmp/split.stdout"
login_prose="$test_tmp/login-prose.stdout"
unauthorized_prose="$test_tmp/unauthorized-prose.stdout"
unknown_stdout="$test_tmp/unknown.stdout"
whitespace_stdout="$test_tmp/whitespace.stdout"
binary_stdout="$test_tmp/binary.stdout"

: >"$empty_stderr"
printf '%s\n' 'unexpected upstream failure xyz123' >"$unknown_stderr"
printf '%s\n' '429 Too Many Requests' >"$structural_429"
printf '%s' 'invalid_api_' >"$split_stderr"
printf '%s' 'key' >"$split_stdout"
printf '%s\n' 'model says the docs claim login required, then crashed' >"$login_prose"
printf '%s\n' 'the user was unauthorized to enter' >"$unauthorized_prose"
printf '%s\n' 'unrecognized non-whitespace stdout evidence' >"$unknown_stdout"
printf ' \t\n' >"$whitespace_stdout"
printf '\xff' >"$binary_stdout"

check_files stdout-structural-429 1 "$empty_stderr" "$structural_429" transient
check_files unknown-stderr-stdout-login 1 "$unknown_stderr" "$FIXTURES/cli-not-logged-in.txt" deterministic-auth
check_files split-token-does-not-synthesize-auth 1 "$split_stderr" "$split_stdout" transient
check_files stdout-login-prose-excluded 1 "$unknown_stderr" "$login_prose" transient
check_files stdout-bare-unauthorized-excluded 1 "$empty_stderr" "$unauthorized_prose" transient
check_files stdout-unknown-non-whitespace 1 "$empty_stderr" "$unknown_stdout" transient
check_files stdout-whitespace-only 1 "$empty_stderr" "$whitespace_stdout" degenerate
check_files missing-stderr-stdout-login 1 "$test_tmp/missing.stderr" "$FIXTURES/cli-not-logged-in.txt" deterministic-auth
check_files stderr-auth-wins-over-stdout-429 1 "$FIXTURES/auth-401.json" "$structural_429" deterministic-auth
check_files invalid-utf8-stdout-is-nondegenerate 1 "$empty_stderr" "$binary_stdout" transient

large_size=225280
login_banner='Not logged in'
banner_size=${#login_banner}
large_tail_stdout="$test_tmp/large-tail.stdout"
large_middle_stdout="$test_tmp/large-middle.stdout"
fill_bytes $(( large_size - banner_size )) >"$large_tail_stdout"
printf '%s' "$login_banner" >>"$large_tail_stdout"
middle_prefix=$(( (large_size - banner_size) / 2 ))
middle_suffix=$(( large_size - banner_size - middle_prefix ))
{
  fill_bytes "$middle_prefix"
  printf '%s' "$login_banner"
  fill_bytes "$middle_suffix"
} >"$large_middle_stdout"

check_files bounded-tail-window-sees-login 1 "$empty_stderr" "$large_tail_stdout" deterministic-auth
check_files bounded-middle-window-omits-login 1 "$empty_stderr" "$large_middle_stdout" transient

wc_failure_bin="$test_tmp/wc-failure-bin"
mkdir -p "$wc_failure_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$wc_failure_bin/wc"
chmod +x "$wc_failure_bin/wc"
wc_failure_diag="$test_tmp/wc-failure.diag"
set +e
wc_failure_actual=$(PATH="$wc_failure_bin:$PATH" classify_failure 1 "$empty_stderr" "$large_tail_stdout" 2>"$wc_failure_diag")
wc_failure_rc=$?
set -e
if [[ "$wc_failure_rc" -eq 0 && "$wc_failure_actual" = deterministic-auth ]] \
  && grep -F -x -q "classify_failure: unreadable evidence: $large_tail_stdout" "$wc_failure_diag"; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS wc-failure-uses-conservative-bounded-read\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL wc-failure-uses-conservative-bounded-read: expected deterministic-auth plus unreadable diagnostic, got rc=%s result=%s\n' "$wc_failure_rc" "$wc_failure_actual"
fi

wc_failure_large_evidence="$test_tmp/wc-failure-large-evidence.stdout"
wc_failure_large_marker='Not logged in'
wc_failure_large_expected_bytes=$(( 2 * CLASSIFY_WINDOW_BYTES + 1 ))
wc_failure_large_size=$(( wc_failure_large_expected_bytes + 1 ))
fill_bytes $(( wc_failure_large_size - ${#wc_failure_large_marker} )) >"$wc_failure_large_evidence"
printf '%s' "$wc_failure_large_marker" >>"$wc_failure_large_evidence"
wc_failure_large_diag="$test_tmp/wc-failure-large.diag"
set +e
wc_failure_large_actual=$(PATH="$wc_failure_bin:$PATH" classify_failure 1 "$empty_stderr" "$wc_failure_large_evidence" 2>"$wc_failure_large_diag")
wc_failure_large_rc=$?
wc_failure_large_reader_output=$(PATH="$wc_failure_bin:$PATH" _classify_read_bounded "$wc_failure_large_evidence" 2>>"$wc_failure_large_diag")
wc_failure_large_reader_rc=$?
set -e
wc_failure_large_reader_bytes=$(printf '%s' "$wc_failure_large_reader_output" | wc -c)
wc_failure_large_file_bytes=$(wc -c <"$wc_failure_large_evidence")
if [[ "$wc_failure_large_rc" -eq 0 && "$wc_failure_large_reader_rc" -eq 0 ]] \
  && [[ "$wc_failure_large_actual" = deterministic-auth ]] \
  && [[ "$wc_failure_large_file_bytes" -gt "$CLASSIFY_INLINE_MAX_BYTES" ]] \
  && [[ "$wc_failure_large_file_bytes" -eq "$wc_failure_large_size" ]] \
  && [[ "$wc_failure_large_reader_bytes" -eq "$wc_failure_large_expected_bytes" ]] \
  && [[ "$wc_failure_large_reader_bytes" -lt "$wc_failure_large_file_bytes" ]]; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS wc-failure-with-large-evidence-still-windows\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL wc-failure-with-large-evidence-still-windows: expected deterministic-auth and %s-byte window output, got rc=%s reader_rc=%s result=%s reader_bytes=%s file_bytes=%s\n' "$wc_failure_large_expected_bytes" "$wc_failure_large_rc" "$wc_failure_large_reader_rc" "$wc_failure_large_actual" "$wc_failure_large_reader_bytes" "$wc_failure_large_file_bytes"
fi

wc_invalid_bin="$test_tmp/wc-invalid-bin"
mkdir -p "$wc_invalid_bin"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' not-a-number" >"$wc_invalid_bin/wc"
chmod +x "$wc_invalid_bin/wc"
wc_invalid_diag="$test_tmp/wc-invalid.diag"
set +e
wc_invalid_actual=$(PATH="$wc_invalid_bin:$PATH" classify_failure 1 "$empty_stderr" "$large_tail_stdout" 2>"$wc_invalid_diag")
wc_invalid_rc=$?
set -e
if [[ "$wc_invalid_rc" -eq 0 && "$wc_invalid_actual" = deterministic-auth ]] \
  && grep -F -x -q "classify_failure: invalid evidence size: value='not-a-number' file='$large_tail_stdout'" "$wc_invalid_diag"; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS nonnumeric-size-uses-conservative-bounded-read\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL nonnumeric-size-uses-conservative-bounded-read: expected deterministic-auth plus invalid-size diagnostic, got rc=%s result=%s\n' "$wc_invalid_rc" "$wc_invalid_actual"
fi

wc_leading_zero_bin="$test_tmp/wc-leading-zero-bin"
mkdir -p "$wc_leading_zero_bin"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' 0200000" >"$wc_leading_zero_bin/wc"
chmod +x "$wc_leading_zero_bin/wc"
wc_leading_zero_diag="$test_tmp/wc-leading-zero.diag"
set +e
wc_leading_zero_actual=$(PATH="$wc_leading_zero_bin:$PATH" classify_failure 1 "$empty_stderr" "$large_tail_stdout" 2>"$wc_leading_zero_diag")
wc_leading_zero_rc=$?
set -e
if [[ "$wc_leading_zero_rc" -eq 0 && "$wc_leading_zero_actual" = deterministic-auth ]] \
  && grep -F -x -q "classify_failure: invalid evidence size: value='0200000' file='$large_tail_stdout'" "$wc_leading_zero_diag"; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS leading-zero-size-is-rejected-conservatively\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL leading-zero-size-is-rejected-conservatively: expected deterministic-auth plus invalid-size diagnostic, got rc=%s result=%s\n' "$wc_leading_zero_rc" "$wc_leading_zero_actual"
fi

wc_spaced_bin="$test_tmp/wc-spaced-bin"
mkdir -p "$wc_spaced_bin"
printf '%s\n' '#!/usr/bin/env bash' "printf '  12 34  \\n'" >"$wc_spaced_bin/wc"
chmod +x "$wc_spaced_bin/wc"
wc_spaced_diag="$test_tmp/wc-spaced.diag"
set +e
wc_spaced_actual=$(PATH="$wc_spaced_bin:$PATH" classify_failure 1 "$empty_stderr" "$large_tail_stdout" 2>"$wc_spaced_diag")
wc_spaced_rc=$?
set -e
if [[ "$wc_spaced_rc" -eq 0 && "$wc_spaced_actual" = deterministic-auth ]] \
  && grep -F -x -q "classify_failure: invalid evidence size: value='12 34' file='$large_tail_stdout'" "$wc_spaced_diag"; then
  pass_count=$(( pass_count + 1 ))
  printf 'PASS internal-whitespace-size-is-rejected-conservatively\n'
else
  fail_count=$(( fail_count + 1 ))
  printf 'FAIL internal-whitespace-size-is-rejected-conservatively: expected deterministic-auth plus invalid-size diagnostic, got rc=%s result=%s\n' "$wc_spaced_rc" "$wc_spaced_actual"
fi

if [[ $(id -u) -eq 0 ]]; then
  printf 'SKIP unreadable-stdout-is-degenerate (running as root)\n'
else
  unreadable_stdout="$test_tmp/unreadable.stdout"
  unreadable_diag="$test_tmp/unreadable.diag"
  printf '%s\n' 'Not logged in' >"$unreadable_stdout"
  chmod 000 "$unreadable_stdout"
  unreadable_actual=$(classify_failure 1 "$empty_stderr" "$unreadable_stdout" 2>"$unreadable_diag")
  chmod 600 "$unreadable_stdout"
  if [[ "$unreadable_actual" = degenerate ]] \
    && grep -F -x -q "classify_failure: unreadable evidence: $unreadable_stdout" "$unreadable_diag"; then
    pass_count=$(( pass_count + 1 ))
    printf 'PASS unreadable-stdout-is-degenerate\n'
  else
    fail_count=$(( fail_count + 1 ))
    printf 'FAIL unreadable-stdout-is-degenerate: expected degenerate plus unreadable diagnostic, got %s\n' "$unreadable_actual"
  fi
fi

printf 'Summary: %s PASS, %s FAIL\n' "$pass_count" "$fail_count"
(( fail_count == 0 ))
