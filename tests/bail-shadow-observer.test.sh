#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK=${BAIL_HOOK_UNDER_TEST:-$ROOT/adapters/claude-code/precompact-flush-hook.sh}
TMP_ROOT=${TMPDIR:-/tmp}/bail-shadow-observer-test.$$
PASS_COUNT=0
FAIL_COUNT=0
FIXED_DAY=2026-08-21
FIXED_TIMESTAMP=2026-08-21T01:02:03Z

cleanup() {
  chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_ROOT/bin"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

cat >"$TMP_ROOT/bin/date" <<EOF
#!/usr/bin/env bash
case "\$*" in
  '-u +%F') printf '%s\n' '$FIXED_DAY' ;;
  '-u +%Y-%m-%dT%H:%M:%SZ') printf '%s\n' '$FIXED_TIMESTAMP' ;;
  *) exec /bin/date "\$@" ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/date"

cat >"$TMP_ROOT/fake-flush-model.sh" <<'EOF'
#!/usr/bin/env bash
if [ -n "${BAIL_PROMPT_CAPTURE:-}" ]; then
  cat >"$BAIL_PROMPT_CAPTURE"
else
  cat >/dev/null
fi
if [ "${BAIL_MAKE_GUARD_READONLY:-0}" = 1 ]; then
  chmod a-w "$PWD"
fi
printf '%s\n' "${BAIL_MODEL_OUTPUT:-NO_REPLY}"
exit "${BAIL_MODEL_STATUS:-0}"
EOF
chmod +x "$TMP_ROOT/fake-flush-model.sh"

new_ws() {
  local name=$1
  local ws=$TMP_ROOT/ws-$name
  "$ROOT/scripts/loop-init" --workspace "$ws" >/dev/null
  (cd "$ws" && pwd -P)
}

run_hook() {
  local ws=$1
  local run_name=$2
  local model_output=$3
  local model_status=${4:-0}
  local shadow_switch=${5:-1}
  local observer_outcome=${6:-}
  local make_readonly=${7:-0}
  local session_id=${8:-$run_name}
  local prompt_capture=${9:-}
  local run_dir=$TMP_ROOT/run-$run_name

  mkdir -p "$run_dir"
  set +e
  printf '{"cwd":"%s","session_id":"%s","trigger":"manual"}\n' "$ws" "$session_id" \
    | env PATH="$TMP_ROOT/bin:$PATH" \
      TMPDIR="$run_dir" \
      BAIL_MODEL_OUTPUT="$model_output" \
      BAIL_MODEL_STATUS="$model_status" \
      BAIL_MAKE_GUARD_READONLY="$make_readonly" \
      BAIL_PROMPT_CAPTURE="$prompt_capture" \
      FLH_FLUSH_CMD="$TMP_ROOT/fake-flush-model.sh" \
      FLH_BAIL_SHADOW="$shadow_switch" \
      FLH_BAIL_SHADOW_OUTCOME="$observer_outcome" \
      "$HOOK" >"$run_dir/stdout" 2>"$run_dir/stderr"
  RUN_RC=$?

  RUN_DIR=$run_dir
  RUN_GUARD=$run_dir/caty-agent-harness-hook
  RUN_SHADOW=$RUN_GUARD/bail-shadow.log
  RUN_PENDING=$ws/loop/pending/flush-$FIXED_DAY.md
}

observer_case() {
  local index=$1
  local family=$2
  local phrase=$3
  local logged_line=${4:-$phrase}
  local ws output expected name
  name=family-$index-$family
  ws=$(new_ws "$name")
  output=$(printf '%s\n%s' "$phrase" '- This durable observation is deliberately long enough for an ok canonical flush outcome.')
  run_hook "$ws" "$name" "$output"
  expected="timestamp=$FIXED_TIMESTAMP family=$family line=$logged_line"
  if [ "$RUN_RC" -eq 0 ] \
    && [ -f "$RUN_PENDING" ] \
    && [ -f "$RUN_SHADOW" ] \
    && [ "$(wc -l <"$RUN_SHADOW" | tr -d ' ')" -eq 1 ] \
    && grep -Fqx -- "$expected" "$RUN_SHADOW" \
    && [ "$(find "$RUN_DIR" -name bail-shadow.log -type f | wc -l | tr -d ' ')" -eq 1 ] \
    && [ "$(find "$ws" -name bail-shadow.log -type f | wc -l | tr -d ' ')" -eq 0 ]; then
    pass "[$index] $family is appended only to the guard-dir shadow log"
  else
    fail_case "[$index] $family is appended only to the guard-dir shadow log" \
      "rc=$RUN_RC pending=$(test -f "$RUN_PENDING" && tail -n 1 "$RUN_PENDING" || printf missing) shadow=$(test -f "$RUN_SHADOW" && tail -n 1 "$RUN_SHADOW" || printf missing)"
  fi
}

observer_case 1 unable_to_proceed "I can't proceed without losing the remaining work."
observer_case 2 giving_up 'Giving up on this implementation.'
observer_case 3 stopping_here 'Stopping here for now.'
observer_case 4 agents_in_flight '3 agents in flight.'
observer_case 5 check_back_later "I'll check back in five minutes."
observer_case 6 please_deflection 'Please run the remaining release steps for me.'
observer_case 6a unable_to_proceed 'Running out of context.'
observer_case 6b check_back_later "I'll continue later."
long_phrase='Stopping here for now. abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz'
observer_case 6c stopping_here "$long_phrase" "${long_phrase:0:120}"

ws=$(new_ws tail-only)
tail_output=$(printf '%s\n\n%s' 'Stopping here for a quoted earlier state.' '- This final paragraph is a normal durable observation that remains authoritative.')
run_hook "$ws" tail-only "$tail_output"
if [ "$RUN_RC" -eq 0 ] && [ -f "$RUN_PENDING" ] && [ ! -e "$RUN_SHADOW" ]; then
  pass '[7] only the last non-empty paragraph is scanned'
else
  fail_case '[7] only the last non-empty paragraph is scanned' \
    "rc=$RUN_RC shadow=$(test -e "$RUN_SHADOW" && tail -n 1 "$RUN_SHADOW" || printf absent)"
fi

ws=$(new_ws authority-parity)
parity_output=$(printf '%s\n%s' 'Stopping here for now.' '- This canonical observation is byte-stable across observer modes and long enough to pass.')
run_hook "$ws" parity-on "$parity_output" 0 1 '' 0 parity
on_rc=$RUN_RC
on_stdout=$TMP_ROOT/parity-on.stdout
on_stderr=$TMP_ROOT/parity-on.stderr
on_record=$TMP_ROOT/parity-on.record
cp "$RUN_DIR/stdout" "$on_stdout"
cp "$RUN_DIR/stderr" "$on_stderr"
cp "$RUN_PENDING" "$on_record"
on_shadow=$RUN_SHADOW
rm -f "$RUN_PENDING"
run_hook "$ws" parity-off "$parity_output" 0 0 '' 0 parity
off_rc=$RUN_RC
if [ "$on_rc" -eq "$off_rc" ] \
  && [ "$off_rc" -eq 0 ] \
  && cmp -s "$on_stdout" "$RUN_DIR/stdout" \
  && cmp -s "$on_stderr" "$RUN_DIR/stderr" \
  && cmp -s "$on_record" "$RUN_PENDING" \
  && grep -Fq 'outcome=ok' "$on_record" \
  && [ -f "$on_shadow" ] \
  && [ ! -e "$RUN_SHADOW" ]; then
  pass '[8] observer on/off preserves exit, streams, outcome, and canonical record byte-for-byte'
else
  fail_case '[8] observer on/off preserves exit, streams, outcome, and canonical record byte-for-byte' \
    "on_rc=$on_rc off_rc=$off_rc record_cmp=$(cmp -s "$on_record" "$RUN_PENDING"; printf '%s' $?)"
fi

protection_ok=1
protection_index=0
for protected_line in \
  'VERDICT: PASS' \
  'Pushed to origin/main.' \
  'Committed as abcdef0.' \
  'Opened PR #107.' \
  'Ready for review.'; do
  protection_index=$((protection_index + 1))
  ws=$(new_ws "protected-$protection_index")
  protected_output=$(printf '%s\n%s' "$protected_line" '- This protected completion record is long enough to keep the canonical outcome ok.')
  run_hook "$ws" "protected-$protection_index" "$protected_output"
  if [ "$RUN_RC" -ne 0 ] || [ ! -f "$RUN_PENDING" ] || [ -e "$RUN_SHADOW" ]; then
    protection_ok=0
  fi
done
ws=$(new_ws protected-line-scope)
protected_output=$(printf '%s\n%s\n%s' 'VERDICT: PASS' 'Stopping here for now.' '- This later line proves that protection excludes one line rather than its whole paragraph.')
run_hook "$ws" protected-line-scope "$protected_output"
if [ "$RUN_RC" -ne 0 ] \
  || ! grep -Fq 'family=stopping_here line=Stopping here for now.' "$RUN_SHADOW" 2>/dev/null; then
  protection_ok=0
fi
if [ "$protection_ok" -eq 1 ]; then
  pass '[9] verdict, ship-state, and ready-review lines are protected line-by-line'
else
  fail_case '[9] verdict, ship-state, and ready-review lines are protected line-by-line' \
    'a protected line logged, or a later unprotected line was suppressed'
fi

suppression_ok=1
for suppression in blocked timeout error; do
  ws=$(new_ws "suppressed-$suppression")
  suppressed_output=$(printf '%s\n%s' 'Stopping here for now.' '- This suppressed canonical candidate remains long enough for deterministic classification.')
  status=0
  override=$suppression
  expected_outcome=ok
  case "$suppression" in
    timeout) status=124; override=''; expected_outcome=timeout ;;
    error) status=7; override=''; expected_outcome=error ;;
  esac
  run_hook "$ws" "suppressed-$suppression" "$suppressed_output" "$status" 1 "$override"
  if [ "$RUN_RC" -ne 0 ] \
    || ! grep -Fq "outcome=$expected_outcome" "$RUN_PENDING" 2>/dev/null \
    || [ -e "$RUN_SHADOW" ]; then
    suppression_ok=0
  fi
done
if [ "$suppression_ok" -eq 1 ]; then
  pass '[10] blocked, timeout, and error outcomes suppress observation'
else
  fail_case '[10] blocked, timeout, and error outcomes suppress observation' \
    'one explicit stop outcome created a shadow record or changed canonical completion'
fi

ws=$(new_ws readonly-shadow)
readonly_output=$(printf '%s\n%s' 'Stopping here for now.' '- This canonical observation survives a read-only observer guard directory without mutation.')
run_hook "$ws" readonly-shadow "$readonly_output" 0 1 '' 1
if [ "$RUN_RC" -eq 0 ] \
  && grep -Fq 'outcome=ok' "$RUN_PENDING" 2>/dev/null \
  && grep -Fq 'This canonical observation survives' "$RUN_PENDING" \
  && [ ! -e "$RUN_SHADOW" ]; then
  pass '[11] read-only shadow-log failure cannot block canonical recording'
else
  fail_case '[11] read-only shadow-log failure cannot block canonical recording' \
    "rc=$RUN_RC pending=$(test -f "$RUN_PENDING" && tail -n 2 "$RUN_PENDING" || printf missing)"
fi
chmod u+w "$RUN_GUARD" 2>/dev/null || true

ws=$(new_ws c4-wording)
prompt_capture=$TMP_ROOT/c4-prompt
run_hook "$ws" c4-wording 'NO_REPLY' 0 0 '' 0 c4 "$prompt_capture"
if grep -Fqx 'Omitted content must not be reconstructed from memory.' "$prompt_capture" \
  && grep -Fqx 'Omitted content must not be reconstructed from memory.' \
    "$ROOT/adapters/claude-code/checkpoint-stop-hook.sh"; then
  pass '[12] C4 omission wording is present in both flush instruction paths'
else
  fail_case '[12] C4 omission wording is present in both flush instruction paths' \
    'the exact sentence is missing from the extractor prompt or checkpoint demand'
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
