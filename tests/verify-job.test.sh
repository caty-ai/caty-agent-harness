#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/adapters/hermes/verify-job.sh
TMP_ROOT=${TMPDIR:-/tmp}/verify-job-test.$$
PASS_COUNT=0
FAIL_COUNT=0
VERIFY_HEADER='# VERIFY log — append-only verifier verdict history'

source "$ROOT/tests/lib-wrapper-conformance-fixture.sh"

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

verify_json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f).get(sys.argv[2])
print("" if value is None else value)
PY
}

make_bundle() {
  ws=$TMP_ROOT/ws-$1
  bundle=$ws/loop/artifacts/task-one
  mkdir -p "$bundle"
  printf '# State\n' >"$ws/STATE.md"
  printf 'request\n' >"$bundle/request.md"
  printf 'rubric\n' >"$bundle/rubric.md"
  printf 'result\n' >"$bundle/result.md"
  printf 'manifest\n' >"$bundle/manifest.md"
  printf 'evidence\n' >"$bundle/evidence.md"
  printf '{}\n' >"$bundle/metadata.json"
  printf '%s\n' "$bundle"
}

write_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'fixture pass'
SH
  chmod +x "$path"
}

write_reason_hygiene_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
case "${VERIFY_REASON_MODE:-japanese}" in
  unicode-empty)
    printf '\302\240\t \343\200\200\342\200\213\n'
    ;;
  nbsp-only)
    printf '\302\240\n'
    ;;
  ideographic-space-only)
    printf '\343\200\200\n'
    ;;
  zwsp-only)
    printf '\342\200\213\n'
    ;;
  japanese)
    printf '\346\227\245\346\234\254\350\252\236\343\201\256\347\220\206\347\224\261\n'
    ;;
  embedded-controls)
    printf '  visible\033[31m reason\007\177   \n'
    ;;
  control-only)
    printf '\033\007\177\n'
    ;;
  *)
    exit 98
    ;;
esac
SH
  chmod +x "$path"
}

write_auth_failure_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'AxiosError: Request failed with status code 401' >&2
exit 1
SH
  chmod +x "$path"
}

write_hanging_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
sleep 60
SH
  chmod +x "$path"
}

write_large_output_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'large output fixture pass'
i=0
while [ "$i" -lt 4000 ]; do
  printf '%080d\n' "$i"
  i=$((i + 1))
done
SH
  chmod +x "$path"
}

write_confusable_duplicate_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'confusable duplicate fixture'
printf '%s\n' 'VERDICT： fail'
printf '%s\n' 'smuggled duplicate'
SH
  chmod +x "$path"
}

write_nbsp_duplicate_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'nbsp duplicate fixture'
printf 'VERDICT:\302\240fail\n'
printf '%s\n' 'smuggled duplicate'
SH
  chmod +x "$path"
}

write_verdict_last_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'finding line before verdict'
printf '%s\n' 'VERDICT: fail'
printf '%s\n' 'old behavior reason'
SH
  chmod +x "$path"
}

write_timeout_tail_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'timeout-stdout-01'
printf '%s\n' 'timeout-stdout-02'
printf '%s\n' 'timeout-stderr-01' >&2
printf '%s\n' 'timeout-stderr-02' >&2
sleep 60
SH
  chmod +x "$path"
}

write_prompt_dump_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PROMPT_DUMP"
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'no-findings; residual risk: fixture evidence is synthetic'
SH
  chmod +x "$path"
}

attest_verifier_wrapper() {
  local wrapper_path=$1
  local name=$2
  local provider_path=$TMP_ROOT/$name-provider.sh
  local probe_path=$TMP_ROOT/$name-probe.sh

  conformance_write_provider "$provider_path"
  conformance_write_probe "$probe_path"
  conformance_attest_wrapper "$ROOT" verifier "$wrapper_path" "$provider_path" "$probe_path" "fixture-$name" "fixture-$name-v1"
}

bundle=$(make_bundle pass)
verifier=$TMP_ROOT/fake-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" fake
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=fake bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: pass' \
  && grep -q 'verifier=fake | verdict=pass | fixture pass' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md" \
  && [ "$(verify_json_field "$TMP_ROOT/ws-pass/loop/artifacts/task-one/verify.json" verdict)" = pass ] \
  && [ "$(verify_json_field "$TMP_ROOT/ws-pass/loop/artifacts/task-one/verify.json" reason)" = 'fixture pass' ]; then
  pass "valid verifier command runs and logs verdict"
else
  fail_case "valid verifier command runs and logs verdict" "rc=$rc output=$output"
fi

source_grep_ok=1
grep -Fq 'write_record "$verify_record_path"' "$SCRIPT" || source_grep_ok=0
grep -Fq 'emit_record "$verify_record_path"' "$SCRIPT" || source_grep_ok=0
grep -Fq 'record_exit_code "$verify_record_path"' "$SCRIPT" || source_grep_ok=0
if [ "$source_grep_ok" -eq 1 ]; then
  pass "verify-job source routes log/stdout/exit through the canonical record helper"
else
  fail_case "verify-job source routes log/stdout/exit through the canonical record helper" \
    "source grep did not find the canonical record flow"
fi

if [ "$(sed -n '1p' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md")" = "$VERIFY_HEADER" ]; then
  pass "verify-job creates the append-only verifier history header"
else
  fail_case "verify-job creates the append-only verifier history header" \
    "header=$(sed -n '1p' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md")"
fi

reason_hygiene_verifier=$TMP_ROOT/reason-hygiene-verifier.sh
write_reason_hygiene_verifier "$reason_hygiene_verifier"
attest_verifier_wrapper "$reason_hygiene_verifier" reason-hygiene

bundle=$(make_bundle unicode-empty-reason)
unicode_empty_log=$TMP_ROOT/ws-unicode-empty-reason/loop/VERIFY.log.md
output=$(VERIFY_REASON_MODE=unicode-empty VERIFIER_CMD="$reason_hygiene_verifier" \
  VERIFIER_ID=reason-hygiene bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 6 ] \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: contract-violation' \
  && grep -Fq 'verdict=contract-violation | call-site=verifier class=contract-violation; provider output line 2 reason is empty' "$unicode_empty_log"; then
  pass "Unicode-space-only verifier reasons become contract violations"
else
  fail_case "Unicode-space-only verifier reasons become contract violations" \
    "rc=$rc output=$output log=$(cat "$unicode_empty_log" 2>/dev/null)"
fi

single_unicode_empty_ok=1
for unicode_empty_case in nbsp-only ideographic-space-only zwsp-only; do
  bundle=$(make_bundle "$unicode_empty_case-reason")
  single_unicode_empty_log=$TMP_ROOT/ws-$unicode_empty_case-reason/loop/VERIFY.log.md
  output=$(VERIFY_REASON_MODE="$unicode_empty_case" VERIFIER_CMD="$reason_hygiene_verifier" \
    VERIFIER_ID=reason-hygiene bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  if [ "$rc" -ne 6 ] \
    || ! grep -Fq 'verdict=contract-violation | call-site=verifier class=contract-violation; provider output line 2 reason is empty' \
      "$single_unicode_empty_log"; then
    single_unicode_empty_ok=0
  fi
done
if [ "$single_unicode_empty_ok" -eq 1 ]; then
  pass "NBSP-only, U+3000-only, and ZWSP-only reasons each contract-violate"
else
  fail_case "NBSP-only, U+3000-only, and ZWSP-only reasons each contract-violate" \
    "one or more single-sequence reasons escaped the empty-reason check"
fi

bundle=$(make_bundle japanese-reason)
japanese_log=$TMP_ROOT/ws-japanese-reason/loop/VERIFY.log.md
japanese_reason=$(printf '\346\227\245\346\234\254\350\252\236\343\201\256\347\220\206\347\224\261')
output=$(VERIFY_REASON_MODE=japanese VERIFIER_CMD="$reason_hygiene_verifier" \
  VERIFIER_ID=reason-hygiene bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && grep -Fq "verdict=pass | $japanese_reason" "$japanese_log"; then
  pass "fully Japanese verifier reasons reach the log unchanged"
else
  fail_case "fully Japanese verifier reasons reach the log unchanged" \
    "rc=$rc output=$output log=$(cat "$japanese_log" 2>/dev/null)"
fi

bundle=$(make_bundle embedded-control-reason)
embedded_control_log=$TMP_ROOT/ws-embedded-control-reason/loop/VERIFY.log.md
embedded_control_clean=$TMP_ROOT/embedded-control-clean.log
output=$(VERIFY_REASON_MODE=embedded-controls VERIFIER_CMD="$reason_hygiene_verifier" \
  VERIFIER_ID=reason-hygiene bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
LC_ALL=C tr -d '\000-\010\013-\037\177' \
  <"$embedded_control_log" >"$embedded_control_clean"
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | sed -n '2p' | grep -Fq '  visible[31m reason' \
  && grep -Fq 'verdict=pass |   visible[31m reason' "$embedded_control_log" \
  && cmp -s "$embedded_control_log" "$embedded_control_clean"; then
  pass "reason logging removes C0 and DEL bytes, preserves printable SGR suffixes, and keeps leading space"
else
  fail_case "reason logging removes C0 and DEL bytes, preserves printable SGR suffixes, and keeps leading space" \
    "rc=$rc output=$output log=$(cat "$embedded_control_log" 2>/dev/null)"
fi

bundle=$(make_bundle control-only-reason)
control_only_log=$TMP_ROOT/ws-control-only-reason/loop/VERIFY.log.md
output=$(VERIFY_REASON_MODE=control-only VERIFIER_CMD="$reason_hygiene_verifier" \
  VERIFIER_ID=reason-hygiene bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 6 ] \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: contract-violation' \
  && grep -Fq 'verdict=contract-violation | call-site=verifier class=contract-violation; provider output line 2 reason is empty' "$control_only_log"; then
  pass "control-only verifier reasons become contract violations"
else
  fail_case "control-only verifier reasons become contract violations" \
    "rc=$rc output=$output log=$(cat "$control_only_log" 2>/dev/null)"
fi

bundle=$(make_bundle existing-log)
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" fake-existing
existing_log=$TMP_ROOT/ws-existing-log/loop/VERIFY.log.md
existing_snapshot=$TMP_ROOT/existing-log.snapshot
existing_prefix=$TMP_ROOT/existing-log.prefix
printf '%s\n' \
  '# VERIFY log — legacy installed header' \
  '- 2026-01-01T00:00:00Z | task=old-one | verifier=legacy | verdict=pass | first retained verdict' \
  '- 2026-01-02T00:00:00Z | task=old-two | step=2 | verifier=legacy | verdict=fail | second retained verdict' \
  >"$existing_log"
cp "$existing_log" "$existing_snapshot"
existing_lines=$(wc -l <"$existing_snapshot" | tr -d '[:space:]')
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=fake-existing bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
head -n "$existing_lines" "$existing_log" >"$existing_prefix"
if [ "$rc" -eq 0 ] \
  && cmp -s "$existing_snapshot" "$existing_prefix" \
  && [ "$(wc -l <"$existing_log" | tr -d '[:space:]')" -eq "$((existing_lines + 1))" ] \
  && grep -q 'task=task-one | verifier=fake-existing | verdict=pass | fixture pass' "$existing_log"; then
  pass "verify-job appends without changing an existing log body"
else
  fail_case "verify-job appends without changing an existing log body" \
    "rc=$rc output=$output log=$(cat "$existing_log" 2>/dev/null)"
fi

bundle=$(make_bundle bad-cmd)
set +e
output=$(VERIFIER_CMD="$TMP_ROOT/missing-verifier.sh" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 5 ] && printf '%s\n' "$output" | grep -q 'VERIFIER_CMD not found'; then
  pass "invalid verifier command exits infra error"
else
  fail_case "invalid verifier command exits infra error" "rc=$rc output=$output"
fi

bundle=$(make_bundle auth-failure)
verifier=$TMP_ROOT/auth-failure-verifier.sh
write_auth_failure_verifier "$verifier"
attest_verifier_wrapper "$verifier" auth-failure
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=auth-failure bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 4 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: needs-human' \
  && grep -q 'verifier=auth-failure | verdict=needs-human | call-site=verifier class=deterministic-auth; verifier command exited 1' "$TMP_ROOT/ws-auth-failure/loop/VERIFY.log.md"; then
  pass "401 verifier failure is deterministic-auth and needs-human"
else
  fail_case "401 verifier failure is deterministic-auth and needs-human" "rc=$rc output=$output"
fi

bundle=$(make_bundle timeout)
verifier=$TMP_ROOT/hanging-verifier.sh
write_hanging_verifier "$verifier"
attest_verifier_wrapper "$verifier" hanging
set +e
output=$(VERIFY_TIMEOUT_S=2 VERIFY_GRACE_S=1 VERIFIER_CMD="$verifier" VERIFIER_ID=hanging bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 4 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: inconclusive' \
  && grep -q 'verifier=hanging | verdict=inconclusive | call-site=verifier class=transient; wall-clock timeout after 2s; stdout_tail=<empty>; stderr_tail=<empty>' "$TMP_ROOT/ws-timeout/loop/VERIFY.log.md"; then
  pass "timed out verifier is inconclusive and transient"
else
  fail_case "timed out verifier is inconclusive and transient" "rc=$rc output=$output"
fi

bundle=$(make_bundle timeout-tail)
verifier=$TMP_ROOT/timeout-tail-verifier.sh
write_timeout_tail_verifier "$verifier"
attest_verifier_wrapper "$verifier" timeout-tail
set +e
output=$(VERIFY_TIMEOUT_S=2 VERIFY_GRACE_S=1 VERIFIER_CMD="$verifier" VERIFIER_ID=timeout-tail bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 4 ] \
  && grep -Fq 'stdout_tail=timeout-stdout-01 || timeout-stdout-02' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md" \
  && grep -Fq 'stderr_tail=timeout-stderr-01 || timeout-stderr-02' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md"; then
  pass "timeout reasons include a capped stdout/stderr tail"
else
  fail_case "timeout reasons include a capped stdout/stderr tail" "rc=$rc output=$output"
fi

bundle=$(make_bundle signal-death)
verifier=$TMP_ROOT/signal-death-verifier.sh
cat >"$verifier" <<'SH'
#!/usr/bin/env bash
kill -TERM $$
SH
chmod +x "$verifier"
attest_verifier_wrapper "$verifier" signal-death
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=signal-death bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 4 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: inconclusive' \
  && grep -q 'verifier=signal-death | verdict=inconclusive | call-site=verifier class=transient; verifier command was killed (signal 15)' "$TMP_ROOT/ws-signal-death/loop/VERIFY.log.md"; then
  pass "signal-killed verifier is inconclusive and transient"
else
  fail_case "signal-killed verifier is inconclusive and transient" "rc=$rc output=$output"
fi

bundle=$(make_bundle large-output)
verifier=$TMP_ROOT/large-output-verifier.sh
write_large_output_verifier "$verifier"
attest_verifier_wrapper "$verifier" large-output
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=large-output bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: pass' \
  && grep -q 'verifier=large-output | verdict=pass | large output fixture pass' "$TMP_ROOT/ws-large-output/loop/VERIFY.log.md" \
  && [ "$(verify_json_field "$TMP_ROOT/ws-large-output/loop/artifacts/task-one/verify.json" reason)" = 'large output fixture pass' ]; then
  pass "large verifier output is parsed from temp file"
else
  fail_case "large verifier output is parsed from temp file" "rc=$rc output=$output"
fi

bundle=$(make_bundle attempts-record)
mkdir -p "$bundle/attempts/001"
verifier=$TMP_ROOT/attempts-record-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" attempts-record
output=$(VERIFY_STEP=2 VERIFIER_CMD="$verifier" VERIFIER_ID=attempts-record bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$bundle/attempts/001/verify.json" ] \
  && [ ! -f "$bundle/verify.json" ] \
  && [ "$(verify_json_field "$bundle/attempts/001/verify.json" step)" = 2 ]; then
  pass "verify-job persists verify.json to the current numeric attempt when present"
else
  fail_case "verify-job persists verify.json to the current numeric attempt when present" \
    "rc=$rc output=$output"
fi

bundle=$(make_bundle confusable-duplicate)
verifier=$TMP_ROOT/confusable-duplicate-verifier.sh
write_confusable_duplicate_verifier "$verifier"
attest_verifier_wrapper "$verifier" confusable-duplicate
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=confusable-duplicate bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 6 ] \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: contract-violation' \
  && grep -Fq 'multiple verdict markers after normalization' "$TMP_ROOT/ws-confusable-duplicate/loop/VERIFY.log.md"; then
  pass "ASCII plus confusable duplicate verdict markers contract-violate"
else
  fail_case "ASCII plus confusable duplicate verdict markers contract-violate" \
    "rc=$rc output=$output"
fi

bundle=$(make_bundle nbsp-duplicate)
verifier=$TMP_ROOT/nbsp-duplicate-verifier.sh
write_nbsp_duplicate_verifier "$verifier"
attest_verifier_wrapper "$verifier" nbsp-duplicate
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=nbsp-duplicate bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 6 ] \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: contract-violation' \
  && grep -Fq 'multiple verdict markers after normalization' "$TMP_ROOT/ws-nbsp-duplicate/loop/VERIFY.log.md"; then
  pass "ASCII plus NBSP duplicate verdict markers contract-violate"
else
  fail_case "ASCII plus NBSP duplicate verdict markers contract-violate" \
    "rc=$rc output=$output"
fi

bundle=$(make_bundle old-behavior-red)
verifier=$TMP_ROOT/verdict-last-verifier.sh
write_verdict_last_verifier "$verifier"
attest_verifier_wrapper "$verifier" verdict-last
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=verdict-last bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 6 ] \
  && grep -Fq 'provider output placed the verdict marker outside line 1' "$TMP_ROOT/ws-old-behavior-red/loop/VERIFY.log.md"; then
  pass "T-2 old verdict-last behavior is rejected as a contract violation"
else
  fail_case "T-2 old verdict-last behavior is rejected as a contract violation" \
    "rc=$rc output=$output"
fi

bundle=$(make_bundle step-field)
verifier=$TMP_ROOT/step-field-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" step-field
output=$(VERIFY_STEP=3 VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-step-field/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | step=3 | verifier=.* | verdict=pass | ' "$step_log"; then
  pass "VERIFY_STEP renders a step field into the log entry"
else
  fail_case "VERIFY_STEP renders a step field into the log entry" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle no-step-field)
output=$(VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-no-step-field/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=' "$step_log"; then
  pass "log entry without VERIFY_STEP keeps the old field layout"
else
  fail_case "log entry without VERIFY_STEP keeps the old field layout" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle derived-step-field)
printf '{"current_step": 4}\n' >"$bundle/state.json"
output=$(env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-derived-step-field/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | step=4 | verifier=.* | verdict=pass | ' "$step_log"; then
  pass "VERIFY_STEP derives the step field from state.json"
else
  fail_case "VERIFY_STEP derives the step field from state.json" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle explicit-step-overrides-derived)
printf '{"current_step": 4}\n' >"$bundle/state.json"
output=$(VERIFY_STEP=7 VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-explicit-step-overrides-derived/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | step=7 | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=4' "$step_log"; then
  pass "explicit VERIFY_STEP overrides state.json derivation"
else
  fail_case "explicit VERIFY_STEP overrides state.json derivation" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle malformed-state-no-step)
printf '{not valid json\n' >"$bundle/state.json"
output=$(env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-malformed-state-no-step/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=' "$step_log"; then
  pass "malformed state.json leaves VERIFY_STEP unset"
else
  fail_case "malformed state.json leaves VERIFY_STEP unset" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle missing-key-no-step)
printf '{"other": 1}\n' >"$bundle/state.json"
output=$(env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-missing-key-no-step/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=' "$step_log"; then
  pass "state.json without current_step leaves VERIFY_STEP unset"
else
  fail_case "state.json without current_step leaves VERIFY_STEP unset" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle noninteger-step-no-step)
printf '{"current_step": 4.5}\n' >"$bundle/state.json"
output=$(env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-noninteger-step-no-step/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=' "$step_log"; then
  pass "non-integer current_step leaves VERIFY_STEP unset"
else
  fail_case "non-integer current_step leaves VERIFY_STEP unset" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle negative-step-no-step)
printf '{"current_step": -1}\n' >"$bundle/state.json"
output=$(env -u VERIFY_STEP VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
step_log=$TMP_ROOT/ws-negative-step-no-step/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && grep -q -- '- .* | task=task-one | verifier=.* | verdict=pass | ' "$step_log" \
  && ! grep -q 'step=' "$step_log"; then
  pass "negative current_step leaves VERIFY_STEP unset"
else
  fail_case "negative current_step leaves VERIFY_STEP unset" "rc=$rc log=$(cat "$step_log" 2>/dev/null)"
fi

bundle=$(make_bundle prompt-contract)
verifier=$TMP_ROOT/prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/verifier-prompt.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" prompt-contract
output=$(PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -qi 'first two lines of your reply MUST be' "$prompt_dump" \
  && grep -qi 'residual risks' "$prompt_dump" \
  && grep -Fqi 'must NOT be pass' "$prompt_dump" \
  && grep -qi 'report findings after those first two lines' "$prompt_dump" \
  && grep -qi 'uncertain or indirect evidence as incomplete' "$prompt_dump"; then
  pass "verifier prompt has the first-two-lines contract and completion audit guidance"
else
  fail_case "verifier prompt has the first-two-lines contract and completion audit guidance" "rc=$rc output=$output"
fi

bundle=$(make_bundle verbatim-request-rubric)
verifier=$TMP_ROOT/verbatim-prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/verbatim-verifier-prompt.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" verbatim-request-rubric
{
  printf '%s\n' 'REQUEST-HEAD-SENTINEL'
  i=0
  while [ "$i" -lt 1000 ]; do
    printf 'request-line-%04d-keep-verbatim\n' "$i"
    i=$((i + 1))
  done
  printf '%s\n' 'REQUEST-TAIL-SENTINEL'
} >"$bundle/request.md"
{
  printf '%s\n' 'RUBRIC-HEAD-SENTINEL'
  i=0
  while [ "$i" -lt 1000 ]; do
    printf 'rubric-line-%04d-keep-verbatim\n' "$i"
    i=$((i + 1))
  done
  printf '%s\n' 'RUBRIC-TAIL-SENTINEL'
} >"$bundle/rubric.md"
output=$(PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -q 'REQUEST-HEAD-SENTINEL' "$prompt_dump" \
  && grep -q 'REQUEST-TAIL-SENTINEL' "$prompt_dump" \
  && grep -q 'RUBRIC-HEAD-SENTINEL' "$prompt_dump" \
  && grep -q 'RUBRIC-TAIL-SENTINEL' "$prompt_dump" \
  && ! sed -n '/--- request.md ---/,/--- rubric.md ---/p' "$prompt_dump" | grep -q '\[truncated:' \
  && ! sed -n '/--- rubric.md ---/,/--- result.md ---/p' "$prompt_dump" | grep -q '\[truncated:'; then
  pass "request and rubric are injected verbatim beyond the old per-file cap"
else
  fail_case "request and rubric are injected verbatim beyond the old per-file cap" "rc=$rc output=$output"
fi

bundle=$(make_bundle bounded-output)
bundle=$(cd "$bundle" && pwd -P)
verifier=$TMP_ROOT/bounded-prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/bounded-verifier-prompt.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" bounded-output
for file in result.md manifest.md evidence.md; do
  {
    printf '%s-HEAD-SENTINEL\n' "$file"
    i=0
    while [ "$i" -lt 400 ]; do
      printf '%s-line-%04d-bounded-output\n' "$file" "$i"
      i=$((i + 1))
    done
    printf '%s-TAIL-SENTINEL\n' "$file"
  } >"$bundle/$file"
done
output=$(HERMES_VERIFY_BUNDLE_MAX_BYTES=4096 PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
prompt_bytes=$(wc -c <"$prompt_dump" | tr -d '[:space:]')
if [ "$rc" -eq 0 ] \
  && [ "$prompt_bytes" -le 4096 ] \
  && grep -Fq "source: $bundle/result.md" "$prompt_dump" \
  && grep -Fq "source: $bundle/manifest.md" "$prompt_dump" \
  && grep -Fq "source: $bundle/evidence.md" "$prompt_dump" \
  && grep -q 'result.md-TAIL-SENTINEL' "$prompt_dump" \
  && grep -q 'manifest.md-TAIL-SENTINEL' "$prompt_dump" \
  && grep -q 'evidence.md-TAIL-SENTINEL' "$prompt_dump" \
  && ! grep -q 'result.md-HEAD-SENTINEL' "$prompt_dump" \
  && ! grep -q 'manifest.md-HEAD-SENTINEL' "$prompt_dump" \
  && ! grep -q 'evidence.md-HEAD-SENTINEL' "$prompt_dump"; then
  pass "large outputs use bounded excerpts with absolute pointers under the Hermes cap"
else
  fail_case "large outputs use bounded excerpts with absolute pointers under the Hermes cap" "rc=$rc bytes=$prompt_bytes output=$output"
fi

bundle=$(make_bundle verbatim-over-cap)
verifier=$TMP_ROOT/over-cap-prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/over-cap-verifier-prompt.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" verbatim-over-cap
{
  i=0
  while [ "$i" -lt 200 ]; do
    printf 'required-request-line-%04d\n' "$i"
    i=$((i + 1))
  done
} >"$bundle/request.md"
set +e
output=$(HERMES_VERIFY_BUNDLE_MAX_BYTES=1024 PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" VERIFIER_ID=over-cap bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 4 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: needs-human' \
  && grep -q 'verbatim request/rubric exceed Hermes verifier bundle cap' "$TMP_ROOT/ws-verbatim-over-cap/loop/VERIFY.log.md" \
  && [ ! -e "$prompt_dump" ]; then
  pass "verbatim request and rubric fail closed when they alone exceed the adapter cap"
else
  fail_case "verbatim request and rubric fail closed when they alone exceed the adapter cap" "rc=$rc output=$output"
fi

bundle=$(make_bundle symlink-artifact)
verifier=$TMP_ROOT/symlink-prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/symlink-verifier-prompt.md
outside_artifact=$TMP_ROOT/outside-secret.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" symlink-artifact
printf '%s\n' 'OUTSIDE-SECRET-MUST-NOT-BE-INLINED' >"$outside_artifact"
rm "$bundle/result.md"
ln -s "$outside_artifact" "$bundle/result.md"
set +e
output=$(PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" VERIFIER_ID=symlink-artifact bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: blocked-missing-artifact' \
  && grep -q 'missing required artifact(s): result.md' "$TMP_ROOT/ws-symlink-artifact/loop/VERIFY.log.md" \
  && ! grep -q 'OUTSIDE-SECRET-MUST-NOT-BE-INLINED' "$TMP_ROOT/ws-symlink-artifact/loop/VERIFY.log.md" \
  && [ ! -e "$prompt_dump" ]; then
  pass "symlinked bundle artifacts are rejected before verifier invocation"
else
  fail_case "symlinked bundle artifacts are rejected before verifier invocation" "rc=$rc output=$output"
fi

bundle=$(make_bundle hardlink-artifact)
verifier=$TMP_ROOT/hardlink-prompt-dump-verifier.sh
prompt_dump=$TMP_ROOT/hardlink-verifier-prompt.md
outside_artifact=$TMP_ROOT/outside-hardlink-secret.md
write_prompt_dump_verifier "$verifier"
attest_verifier_wrapper "$verifier" hardlink-artifact
printf '%s\n' 'OUTSIDE-HARDLINK-SECRET-MUST-NOT-BE-INLINED' >"$outside_artifact"
rm "$bundle/result.md"
ln "$outside_artifact" "$bundle/result.md"
set +e
output=$(PROMPT_DUMP="$prompt_dump" VERIFIER_CMD="$verifier" VERIFIER_ID=hardlink-artifact bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: blocked-missing-artifact' \
  && grep -q 'unsafe required artifact link or file type' "$TMP_ROOT/ws-hardlink-artifact/loop/VERIFY.log.md" \
  && ! grep -q 'OUTSIDE-HARDLINK-SECRET-MUST-NOT-BE-INLINED' "$TMP_ROOT/ws-hardlink-artifact/loop/VERIFY.log.md" \
  && [ ! -e "$prompt_dump" ]; then
  pass "hard-linked bundle artifacts are rejected before verifier invocation"
else
  fail_case "hard-linked bundle artifacts are rejected before verifier invocation" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
