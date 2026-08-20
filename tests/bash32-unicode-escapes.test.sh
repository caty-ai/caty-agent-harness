#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/bash32-unicode-escapes-test.$$
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_ROOT"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail_case() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
skip_case() { SKIP_COUNT=$((SKIP_COUNT + 1)); printf 'SKIP %s: %s\n' "$1" "$2"; }

run_system_bash_case() {
  local name=$1 suite=$2 expected_pass=$3
  local log=$TMP_ROOT/$(basename "$suite").log
  local rc summary

  /bin/bash "$suite" >"$log" 2>&1
  rc=$?
  summary=$(grep '^Summary:' "$log" | tail -n 1)
  if [ "$rc" -eq 0 ] && grep -Fqx -- "$expected_pass" "$log"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc ${summary:-Summary: missing}"
  fi
}

if [ -x /bin/bash ]; then
  run_system_bash_case \
    'system bash folds four Unicode variants to one intake key' \
    "$ROOT/tests/flush-intake.test.sh" \
    'PASS [26] normalization is anchored, mech-check invariant, and key-only across Unicode variants'
  run_system_bash_case \
    'system bash presents an NBSP to the pending-dedup normalization' \
    "$ROOT/tests/pending-dedup.test.sh" \
    'PASS NBSP maps to an ordinary space in the candidate hash'
else
  skip_case 'system bash folds four Unicode variants to one intake key' '/bin/bash is unavailable'
  skip_case 'system bash presents an NBSP to the pending-dedup normalization' '/bin/bash is unavailable'
fi

if [ -x /bin/bash ]; then
  if [ "$SKIP_COUNT" -eq 0 ]; then
    pass 'an available system bash cannot be silently skipped'
  else
    fail_case 'an available system bash cannot be silently skipped' \
      "$SKIP_COUNT system-bash case(s) were skipped"
  fi
else
  skip_case 'an available system bash cannot be silently skipped' '/bin/bash is unavailable'
fi

good_fixture=$TMP_ROOT/good.sh
bad_fixture=$TMP_ROOT/bad.sh
cat >"$good_fixture" <<'GOOD'
#!/usr/bin/env bash
printf '%s\n' $'NBSP: \xc2\xa0' $'literal UTF-8: é' $'literal escape text: \\u00e9'
GOOD
printf '%s\n' '#!/usr/bin/env bash' >"$bad_fixture"
printf '%s' 'lower=$' >>"$bad_fixture"
printf '%s\n' "'bad: \\u00e9'" >>"$bad_fixture"
printf '%s' 'upper=$' >>"$bad_fixture"
printf '%s\n' "'bad: \\U0001f600'" >>"$bad_fixture"

lint_output=$(python3 -B "$ROOT/scripts/check-bash32-ansi-c-escapes" "$good_fixture" 2>&1)
lint_rc=$?
if [ "$lint_rc" -eq 0 ] && printf '%s\n' "$lint_output" | grep -Fq '1 shell files OK'; then
  pass 'bash32 ANSI-C lint accepts byte escapes, literal UTF-8, and escaped backslashes'
else
  fail_case 'bash32 ANSI-C lint accepts byte escapes, literal UTF-8, and escaped backslashes' \
    "rc=$lint_rc output=$lint_output"
fi

lint_output=$(python3 -B "$ROOT/scripts/check-bash32-ansi-c-escapes" "$bad_fixture" 2>&1)
lint_rc=$?
if [ "$lint_rc" -eq 1 ] \
  && [ "$(printf '%s\n' "$lint_output" | grep -Fc 'requires Bash 4.2+')" -eq 2 ] \
  && printf '%s\n' "$lint_output" | grep -Fq '2 violation(s) in 1 shell file(s)'; then
  pass 'bash32 ANSI-C lint rejects lowercase and uppercase Unicode escapes'
else
  fail_case 'bash32 ANSI-C lint rejects lowercase and uppercase Unicode escapes' \
    "rc=$lint_rc output=$lint_output"
fi

lint_output=$(python3 -B "$ROOT/scripts/check-bash32-ansi-c-escapes" 2>&1)
lint_rc=$?
if [ "$lint_rc" -eq 2 ] \
  && printf '%s\n' "$lint_output" | grep -Fq 'zero shell files checked' \
  && printf '%s\n' "$lint_output" | grep -Fq 'fail-closed'; then
  pass 'bash32 ANSI-C lint rejects an empty file set'
else
  fail_case 'bash32 ANSI-C lint rejects an empty file set' "rc=$lint_rc output=$lint_output"
fi

runner_fixture=$TMP_ROOT/runner
mkdir -p "$runner_fixture/tests"
cp "$ROOT/Makefile" "$runner_fixture/Makefile"
cat >"$runner_fixture/tests/a-pass.test.sh" <<'PASS_SUITE'
#!/usr/bin/env bash
printf 'a\n' >>run-order
exit 0
PASS_SUITE
cat >"$runner_fixture/tests/b-fail.test.sh" <<'FAIL_SUITE'
#!/usr/bin/env bash
printf 'b\n' >>run-order
exit 9
FAIL_SUITE
cat >"$runner_fixture/tests/c-pass.test.sh" <<'LATE_SUITE'
#!/usr/bin/env bash
printf 'c\n' >>run-order
exit 0
LATE_SUITE
runner_output=$(cd "$runner_fixture" && make test 2>&1)
runner_rc=$?
if [ "$runner_rc" -ne 0 ] \
  && [ "$(tr -d '\n' <"$runner_fixture/run-order")" = abc ] \
  && printf '%s\n' "$runner_output" | grep -Fqx 'Suite Summary: 2 PASS, 1 FAIL' \
  && printf '%s\n' "$runner_output" | grep -Fqx ' - b-fail.test.sh'; then
  pass 'make test runs later suites, reports failures, and exits nonzero'
else
  fail_case 'make test runs later suites, reports failures, and exits nonzero' \
    "rc=$runner_rc order=$(tr -d '\n' <"$runner_fixture/run-order" 2>/dev/null) output=$runner_output"
fi

printf 'Summary: %s PASS, %s FAIL, %s SKIP\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
