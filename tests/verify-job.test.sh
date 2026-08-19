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

write_verify_json() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json
import sys

path, verdict, reason, timestamp = sys.argv[1:5]
with open(path, "w", encoding="utf-8") as record:
    json.dump(
        {
            "verdict": verdict,
            "reason": reason,
            "verifier_id": "history-fixture",
            "step": 1,
            "ts": timestamp,
        },
        record,
        indent=2,
        sort_keys=True,
    )
    record.write("\n")
PY
}

write_mutated_verify_json() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json
import sys

path, field, encoded_value, label = sys.argv[1:5]
record = {
    "verdict": "pass",
    "reason": f"INVALID-RECORD-{label}",
    "verifier_id": f"invalid-record-{label}",
    "step": 1,
    "ts": "2026-08-18T00:00:00Z",
}
if field == "__missing__":
    del record[encoded_value]
else:
    record[field] = json.loads(encoded_value)
with open(path, "w", encoding="utf-8") as destination:
    json.dump(record, destination, sort_keys=True)
    destination.write("\n")
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

write_configurable_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'VERDICT: %s\n' "${VERIFY_TEST_VERDICT:-pass}"
printf '%s\n' "${VERIFY_TEST_REASON:-configurable fixture}"
SH
  chmod +x "$path"
}

write_unicode_separator_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf 'line-sep\342\200\250injected reason\n'
SH
  chmod +x "$path"
}

write_corrupt_log_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
if [[ -n "${VERIFY_TEST_LOG_PATH:-}" ]]; then
  printf '\377' >"$VERIFY_TEST_LOG_PATH"
fi
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'record survives derived-log corruption'
SH
  chmod +x "$path"
}

write_warning_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'provider warning retained on stderr' >&2
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'warning fixture pass'
SH
  chmod +x "$path"
}

write_attempt_swap_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
mv "$VERIFY_TEST_SWAP_FROM" "$VERIFY_TEST_SWAP_MOVED"
ln -s "$VERIFY_TEST_SWAP_TARGET" "$VERIFY_TEST_SWAP_FROM"
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'attempt swap fixture pass'
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

write_unknown_verdict_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: mystery'
printf '%s\n' 'unknown verdict fixture'
SH
  chmod +x "$path"
}

write_timeout_tail_verifier() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'timeout-stdout-oldest-'
printf '%0400d\n' 0
printf '%s\n' 'timeout-stdout-01'
printf '%s\n' 'timeout-stdout-02'
printf 'timeout-stderr-oldest-' >&2
printf '%0400d\n' 0 >&2
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

bundle=$(make_bundle success-stderr)
verifier=$TMP_ROOT/warning-verifier.sh
write_warning_verifier "$verifier"
attest_verifier_wrapper "$verifier" warning
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=warning bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fq 'provider warning retained on stderr' \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: pass'; then
  pass "successful verifier stderr remains operator-visible"
else
  fail_case "successful verifier stderr remains operator-visible" "rc=$rc output=$output"
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
  && grep -Fq 'timeout-stdout-01 || timeout-stdout-02' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md" \
  && grep -Fq 'timeout-stderr-01 || timeout-stderr-02' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md" \
  && ! grep -Fq 'timeout-stdout-oldest-' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md" \
  && ! grep -Fq 'timeout-stderr-oldest-' "$TMP_ROOT/ws-timeout-tail/loop/VERIFY.log.md"; then
  pass "timeout reasons keep the newest capped stdout/stderr tail"
else
  fail_case "timeout reasons keep the newest capped stdout/stderr tail" "rc=$rc output=$output"
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

verifier=$TMP_ROOT/linked-attempt-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" linked-attempt
linked_attempts_ok=1
for linked_attempt_mode in outside inside explicit-inside attempts-root; do
  bundle=$(make_bundle "linked-attempt-$linked_attempt_mode")
  outside_attempt=$TMP_ROOT/linked-attempt-$linked_attempt_mode-target
  attempt_dir_override=
  mkdir -p "$outside_attempt"
  case "$linked_attempt_mode" in
    outside)
      mkdir -p "$bundle/attempts/001"
      ln -s "$outside_attempt" "$bundle/attempts/002"
      ;;
    inside)
      mkdir -p "$bundle/attempts/001"
      ln -s 001 "$bundle/attempts/002"
      outside_attempt=$bundle/attempts/001
      ;;
    explicit-inside)
      mkdir -p "$bundle/attempts/001"
      ln -s 001 "$bundle/attempts/002"
      outside_attempt=$bundle/attempts/001
      attempt_dir_override=$bundle/attempts/./002
      ;;
    attempts-root)
      mkdir -p "$outside_attempt/001"
      ln -s "$outside_attempt" "$bundle/attempts"
      outside_attempt=$outside_attempt/001
      ;;
  esac
  set +e
  output=$(ATTEMPT_DIR="$attempt_dir_override" VERIFIER_CMD="$verifier" \
    VERIFIER_ID=linked-attempt bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 5 ] \
    || ! printf '%s\n' "$output" | grep -Fq 'unsafe verify record target' \
    || [ -e "$outside_attempt/verify.json" ]; then
    linked_attempts_ok=0
  fi
done
if [ "$linked_attempts_ok" -eq 1 ]; then
  pass "numeric attempt links stop verification regardless of where they point"
else
  fail_case "numeric attempt links stop verification regardless of where they point" \
    "one or more linked attempt layouts did not fail closed"
fi

bundle=$(make_bundle unreadable-attempts-root)
mkdir -p "$bundle/attempts/001"
chmod 000 "$bundle/attempts"
unreadable_attempts_ok=1
unreadable_run=1
while [ "$unreadable_run" -le 2 ]; do
  set +e
  output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=unreadable-attempts-root \
    bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 5 ] \
    || ! printf '%s\n' "$output" | grep -Fq \
      'verify-job record path error: bundle attempts directory cannot be opened' \
    || ! printf '%s\n' "$output" | grep -Fq \
      'verify-job infra error: unsafe verify record target' \
    || printf '%s\n' "$output" | grep -Fq 'Traceback' \
    || [ -e "$bundle/verify.json" ] \
    || [ -e "$bundle/attempts/001/verify.json" ]; then
    unreadable_attempts_ok=0
  fi
  unreadable_run=$((unreadable_run + 1))
done
chmod 700 "$bundle/attempts"
if [ "$unreadable_attempts_ok" -eq 1 ]; then
  pass "an unreadable attempts root fails cleanly and repeatably without selecting a record"
else
  fail_case "an unreadable attempts root fails cleanly and repeatably without selecting a record" \
    "one or both runs did not return the clean record-path infrastructure error"
fi

bundle=$(make_bundle attempt-swap-race)
mkdir -p "$bundle/attempts/001"
moved_attempt=$TMP_ROOT/attempt-swap-moved
swap_target=$TMP_ROOT/attempt-swap-target
mkdir -p "$swap_target"
verifier=$TMP_ROOT/attempt-swap-verifier.sh
write_attempt_swap_verifier "$verifier"
attest_verifier_wrapper "$verifier" attempt-swap
set +e
output=$(VERIFY_TEST_SWAP_FROM="$bundle/attempts/001" \
  VERIFY_TEST_SWAP_MOVED="$moved_attempt" VERIFY_TEST_SWAP_TARGET="$swap_target" \
  VERIFIER_CMD="$verifier" VERIFIER_ID=attempt-swap bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 5 ] \
  && printf '%s\n' "$output" | grep -Fq 'record target changed or is unsafe' \
  && [ ! -e "$moved_attempt/verify.json" ] \
  && [ ! -e "$swap_target/verify.json" ]; then
  pass "attempt replacement between selection and write cannot redirect verify.json"
else
  fail_case "attempt replacement between selection and write cannot redirect verify.json" \
    "rc=$rc output=$output moved=$(ls "$moved_attempt" 2>/dev/null) target=$(ls "$swap_target" 2>/dev/null)"
fi

bundle=$(make_bundle attempts-record)
mkdir -p "$bundle/attempts/001"
verifier=$TMP_ROOT/attempts-record-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" attempts-record
output=$(ATTEMPT_DIR="$bundle/attempts/001/../001" VERIFY_STEP=2 \
  VERIFIER_CMD="$verifier" VERIFIER_ID=attempts-record bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$bundle/attempts/001/verify.json" ] \
  && [ ! -f "$bundle/verify.json" ] \
  && [ "$(verify_json_field "$bundle/attempts/001/verify.json" step)" = 2 ]; then
  pass "verify-job accepts a contained explicit attempt path with relative components"
else
  fail_case "verify-job accepts a contained explicit attempt path with relative components" \
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
preamble_ok=0
if [ "$rc" -eq 6 ] \
  && grep -Fq 'provider output placed the verdict marker outside line 1' "$TMP_ROOT/ws-old-behavior-red/loop/VERIFY.log.md"; then
  preamble_ok=1
fi
bundle=$(make_bundle unknown-verdict)
verifier=$TMP_ROOT/unknown-verdict-verifier.sh
write_unknown_verdict_verifier "$verifier"
attest_verifier_wrapper "$verifier" unknown-verdict
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=unknown-verdict bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$preamble_ok" -eq 1 ] \
  && [ "$rc" -eq 6 ] \
  && grep -Fq 'provider output used an unknown verdict: mystery' \
    "$TMP_ROOT/ws-unknown-verdict/loop/VERIFY.log.md"; then
  pass "T-2 preamble and unknown verdicts are contract violations"
else
  fail_case "T-2 preamble and unknown verdicts are contract violations" \
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

verifier=$TMP_ROOT/malformed-step-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" malformed-step
malformed_step_ok=1
for malformed_step in abc 2.5; do
  bundle=$(make_bundle "malformed-explicit-step-${malformed_step//./-}")
  set +e
  output=$(VERIFY_STEP="$malformed_step" VERIFIER_CMD="$verifier" VERIFIER_ID=malformed-step \
    bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  malformed_record=$bundle/verify.json
  malformed_log=${bundle%/loop/artifacts/task-one}/loop/VERIFY.log.md
  if [ "$rc" -ne 0 ] \
    || ! printf '%s\n' "$output" | grep -Fq 'VERDICT: pass' \
    || [ ! -f "$malformed_record" ] \
    || [ -n "$(verify_json_field "$malformed_record" step 2>/dev/null)" ] \
    || grep -Fq 'step=' "$malformed_log"; then
    malformed_step_ok=0
  fi
done
if [ "$malformed_step_ok" -eq 1 ]; then
  pass "malformed explicit VERIFY_STEP values are treated as unset"
else
  fail_case "malformed explicit VERIFY_STEP values are treated as unset" \
    "abc or 2.5 produced a non-verdict exit or a step-bound artifact"
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

bundle=$(make_bundle interrupted-record-log)
mkdir -p "$bundle/attempts/000" "$bundle/attempts/001"
printf '%s\n' '{"verdict":"fail","reason":"PARTIAL-MUST-NOT-BACKFILL"' \
  >"$bundle/attempts/000/verify.json"
verifier=$TMP_ROOT/configurable-verifier.sh
write_configurable_verifier "$verifier"
attest_verifier_wrapper "$verifier" configurable
interrupted_log=$TMP_ROOT/ws-interrupted-record-log/loop/VERIFY.log.md
set +e
first_output=$(HERMES_VERIFY_TEST_INTERRUPT_AFTER_RECORD=1 VERIFY_TEST_VERDICT=fail \
  VERIFY_TEST_REASON='interrupted fail record' VERIFIER_CMD="$verifier" VERIFIER_ID=configurable \
  bash "$SCRIPT" "$bundle" 2>&1)
first_rc=$?
set -e
first_record_verdict=$(verify_json_field "$bundle/attempts/001/verify.json" verdict 2>/dev/null)
first_log_count=$(grep -Fc 'interrupted fail record' "$interrupted_log" 2>/dev/null || true)
second_output=$(VERIFY_TEST_VERDICT=pass VERIFY_TEST_REASON='replacement pass record' \
  VERIFIER_CMD="$verifier" VERIFIER_ID=configurable bash "$SCRIPT" "$bundle" 2>&1)
second_rc=$?
fail_line=$(grep -nF 'interrupted fail record' "$interrupted_log" | cut -d: -f1)
pass_line=$(grep -nF 'replacement pass record' "$interrupted_log" | cut -d: -f1)
if [ "$first_rc" -eq 97 ] \
  && [ "$first_record_verdict" = fail ] \
  && [ "$first_log_count" -eq 0 ] \
  && [ "$second_rc" -eq 0 ] \
  && [ "$(grep -Fc 'interrupted fail record' "$interrupted_log")" -eq 1 ] \
  && [ "$(grep -Fc 'replacement pass record' "$interrupted_log")" -eq 1 ] \
  && [ "$fail_line" -lt "$pass_line" ] \
  && ! grep -Fq 'PARTIAL-MUST-NOT-BACKFILL' "$interrupted_log"; then
  pass "startup reconciles an interrupted record write without trusting partial records"
else
  fail_case "startup reconciles an interrupted record write without trusting partial records" \
    "first_rc=$first_rc first_output=$first_output second_rc=$second_rc second_output=$second_output log=$(cat "$interrupted_log" 2>/dev/null)"
fi

bundle=$(make_bundle reconciliation-order)
mkdir -p "$bundle/attempts/001" "$bundle/attempts/002"
write_verify_json "$bundle/attempts/001/verify.json" fail \
  'older missing projection' '2026-08-18T00:00:00Z'
write_verify_json "$bundle/attempts/002/verify.json" pass \
  'newer authoritative projection' '2026-08-18T00:00:01Z'
write_verify_json "$bundle/verify.json" fail \
  'STALE-ROOT-MUST-NOT-BACKFILL' '2026-08-18T00:00:02Z'
reconciliation_order_log=$TMP_ROOT/ws-reconciliation-order/loop/VERIFY.log.md
printf '%s\n' \
  "$VERIFY_HEADER" \
  '- 2026-08-18T00:00:01Z | task=task-one | step=1 | verifier=history-fixture | verdict=pass | newer authoritative projection' \
  >"$reconciliation_order_log"
verifier=$TMP_ROOT/reconciliation-order-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" reconciliation-order
set +e
output=$(HERMES_VERIFY_TEST_STOP_AFTER_RECONCILE=1 VERIFIER_CMD="$verifier" \
  bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
last_task_line=$(grep -F 'task=task-one' "$reconciliation_order_log" | tail -n 1)
if [ "$rc" -eq 98 ] \
  && [ "$(grep -Fc 'older missing projection' "$reconciliation_order_log")" -eq 1 ] \
  && [ "$(grep -Fc 'newer authoritative projection' "$reconciliation_order_log")" -eq 2 ] \
  && ! grep -Fq 'STALE-ROOT-MUST-NOT-BACKFILL' "$reconciliation_order_log" \
  && printf '%s\n' "$last_task_line" | grep -Fq 'verdict=pass | newer authoritative projection'; then
  pass "reconciliation never leaves an older backfill after a newer record"
else
  fail_case "reconciliation never leaves an older backfill after a newer record" \
    "rc=$rc output=$output log=$(cat "$reconciliation_order_log" 2>/dev/null)"
fi

verifier=$TMP_ROOT/schema-record-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" schema-record
for verdict_shape in list dict; do
  bundle=$(make_bundle "reconcile-verdict-$verdict_shape")
  mkdir -p "$bundle/attempts/001" "$bundle/attempts/002"
  if [ "$verdict_shape" = list ]; then
    encoded_verdict='["pass"]'
  else
    encoded_verdict='{"a": 1}'
  fi
  write_mutated_verify_json "$bundle/attempts/001/verify.json" verdict \
    "$encoded_verdict" "verdict-$verdict_shape"
  set +e
  output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=schema-record bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  schema_log=${bundle%/loop/artifacts/task-one}/loop/VERIFY.log.md
  if [ "$rc" -eq 0 ] \
    && printf '%s\n' "$output" | grep -Fq 'VERDICT: pass' \
    && [ "$(verify_json_field "$bundle/attempts/002/verify.json" verdict 2>/dev/null)" = pass ] \
    && [ "$(grep -Fc 'task=task-one' "$schema_log" 2>/dev/null || true)" -eq 1 ] \
    && ! grep -Fq "INVALID-RECORD-verdict-$verdict_shape" "$schema_log"; then
    pass "parseable record with $verdict_shape verdict is ignored and verification recovers"
  else
    fail_case "parseable record with $verdict_shape verdict is ignored and verification recovers" \
      "rc=$rc output=$output log=$(cat "$schema_log" 2>/dev/null)"
  fi
done

bundle=$(make_bundle reconcile-schema-matrix)
schema_index=1
while IFS='|' read -r field encoded_value label; do
  attempt_name=$(printf '%03d' "$schema_index")
  mkdir -p "$bundle/attempts/$attempt_name"
  write_mutated_verify_json "$bundle/attempts/$attempt_name/verify.json" \
    "$field" "$encoded_value" "$label"
  schema_index=$((schema_index + 1))
done <<'EOF'
__missing__|verdict|missing-verdict
__missing__|reason|missing-reason
__missing__|verifier_id|missing-verifier-id
__missing__|step|missing-step
__missing__|ts|missing-ts
verdict|null|verdict-null
verdict|true|verdict-bool
verdict|0|verdict-int
verdict|1.5|verdict-float
verdict|""|verdict-empty
verdict|"mystery"|verdict-unknown
reason|null|reason-null
reason|true|reason-bool
reason|0|reason-int
reason|1.5|reason-float
reason|[]|reason-list
reason|{}|reason-dict
reason|""|reason-empty
reason|"   "|reason-blank
reason|"bad\u0007"|reason-cc
reason|"bad\u200b"|reason-cf
verifier_id|null|verifier-null
verifier_id|true|verifier-bool
verifier_id|0|verifier-int
verifier_id|1.5|verifier-float
verifier_id|[]|verifier-list
verifier_id|{}|verifier-dict
verifier_id|""|verifier-empty
verifier_id|"bad\u0007"|verifier-cc
verifier_id|"bad\u200b"|verifier-cf
ts|null|ts-null
ts|true|ts-bool
ts|0|ts-int
ts|1.5|ts-float
ts|[]|ts-list
ts|{}|ts-dict
ts|""|ts-empty
ts|"2026-08-18 00:00:00"|ts-shape
step|true|step-true
step|false|step-false
step|0|step-zero
step|-1|step-negative
step|1.5|step-float
step|"1"|step-string
step|[]|step-list
step|{}|step-dict
EOF
mkdir -p "$bundle/attempts/999"
set +e
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=schema-record bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
schema_log=$TMP_ROOT/ws-reconcile-schema-matrix/loop/VERIFY.log.md
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fq 'VERDICT: pass' \
  && [ "$(verify_json_field "$bundle/attempts/999/verify.json" verdict 2>/dev/null)" = pass ] \
  && [ "$(grep -Fc 'task=task-one' "$schema_log" 2>/dev/null || true)" -eq 1 ] \
  && ! grep -Fq 'INVALID-RECORD-' "$schema_log"; then
  pass "parseable records with incomplete schemas, wrong JSON types, unknown verdicts, or malformed timestamps are ignored"
else
  fail_case "parseable records with incomplete schemas, wrong JSON types, unknown verdicts, or malformed timestamps are ignored" \
    "rc=$rc output=$output task_lines=$(grep -Fc 'task=task-one' "$schema_log" 2>/dev/null || true) log=$(cat "$schema_log" 2>/dev/null)"
fi

bundle=$(make_bundle unicode-separator-dedup)
verifier=$TMP_ROOT/unicode-separator-verifier.sh
write_unicode_separator_verifier "$verifier"
attest_verifier_wrapper "$verifier" unicode-separator
unicode_runs_ok=1
unicode_run=1
while [ "$unicode_run" -le 3 ]; do
  attempt_name=$(printf '%03d' "$unicode_run")
  mkdir -p "$bundle/attempts/$attempt_name"
  set +e
  output=$(ATTEMPT_DIR="$bundle/attempts/$attempt_name" VERIFY_STEP="$unicode_run" \
    VERIFIER_CMD="$verifier" VERIFIER_ID=unicode-separator bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$output" | grep -Fq 'VERDICT: pass'; then
    unicode_runs_ok=0
  fi
  unicode_run=$((unicode_run + 1))
done
unicode_log=$TMP_ROOT/ws-unicode-separator-dedup/loop/VERIFY.log.md
unicode_counts=$(python3 - "$unicode_log" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
physical_entries = sum(
    "line-sep\u2028injected reason" in line for line in text.split("\n")
)
print(f"{physical_entries} {text.count(chr(0x2028))}")
PY
)
if [ "$unicode_runs_ok" -eq 1 ] && [ "$unicode_counts" = '3 3' ]; then
  pass "U+2028 remains record text and N verifier runs produce exactly N physical log entries"
else
  fail_case "U+2028 remains record text and N verifier runs produce exactly N physical log entries" \
    "runs_ok=$unicode_runs_ok counts=$unicode_counts log=$(cat "$unicode_log" 2>/dev/null)"
fi

verifier=$TMP_ROOT/corrupt-log-verifier.sh
write_corrupt_log_verifier "$verifier"
attest_verifier_wrapper "$verifier" corrupt-log
bundle=$(make_bundle linked-derived-log)
outside_log=$TMP_ROOT/linked-derived-log-target
printf '%s\n' 'OUTSIDE-LOG-MUST-STAY-UNCHANGED' >"$outside_log"
ln -s "$outside_log" "$TMP_ROOT/ws-linked-derived-log/loop/VERIFY.log.md"
set +e
linked_log_output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=linked-derived-log \
  bash "$SCRIPT" "$bundle" 2>&1)
linked_log_rc=$?
set -e
linked_log_record=$(verify_json_field "$bundle/verify.json" verdict 2>/dev/null || true)

bundle=$(make_bundle corrupt-derived-log-after-provider)
corrupt_log=$TMP_ROOT/ws-corrupt-derived-log-after-provider/loop/VERIFY.log.md
set +e
corrupt_log_output=$(VERIFY_TEST_LOG_PATH="$corrupt_log" VERIFIER_CMD="$verifier" \
  VERIFIER_ID=corrupt-derived-log bash "$SCRIPT" "$bundle" 2>&1)
corrupt_log_rc=$?
set -e
corrupt_log_record=$(verify_json_field "$bundle/verify.json" verdict 2>/dev/null || true)
if [ "$linked_log_rc" -eq 0 ] \
  && [ "$linked_log_record" = pass ] \
  && printf '%s\n' "$linked_log_output" | grep -Fq 'VERDICT: pass' \
  && [ "$(cat "$outside_log")" = 'OUTSIDE-LOG-MUST-STAY-UNCHANGED' ] \
  && [ "$corrupt_log_rc" -eq 0 ] \
  && [ "$corrupt_log_record" = pass ] \
  && printf '%s\n' "$corrupt_log_output" | grep -Fq 'VERDICT: pass' \
  && printf '%s\n' "$corrupt_log_output" | grep -Fq 'log reconciliation error'; then
  pass "unsafe or corrupted derived logs never suppress the authoritative record, stdout verdict, or exit mapping"
else
  fail_case "unsafe or corrupted derived logs never suppress the authoritative record, stdout verdict, or exit mapping" \
    "linked_rc=$linked_log_rc linked_record=$linked_log_record linked_output=$linked_log_output corrupt_rc=$corrupt_log_rc corrupt_record=$corrupt_log_record corrupt_output=$corrupt_log_output"
fi

verifier=$TMP_ROOT/attempt-litter-verifier.sh
write_verifier "$verifier"
attest_verifier_wrapper "$verifier" attempt-litter
litter_paths_ok=1
for litter_mode in fallback explicit; do
  bundle=$(make_bundle "attempt-litter-$litter_mode")
  mkdir -p "$bundle/attempts/001" "$bundle/attempts/009"
  printf '%s\n' 'numeric regular-file litter' >"$bundle/attempts/007"
  mkfifo "$bundle/attempts/008"
  chmod 000 "$bundle/attempts/009"
  if [ "$litter_mode" = explicit ]; then
    attempt_dir_override=$bundle/attempts/001
  else
    attempt_dir_override=
  fi
  set +e
  output=$(ATTEMPT_DIR="$attempt_dir_override" VERIFIER_CMD="$verifier" \
    VERIFIER_ID=attempt-litter bash "$SCRIPT" "$bundle" 2>&1)
  rc=$?
  set -e
  chmod 700 "$bundle/attempts/009"
  litter_log=${bundle%/loop/artifacts/task-one}/loop/VERIFY.log.md
  litter_task_count=$(grep -Fc 'task=task-one' "$litter_log" 2>/dev/null || true)
  litter_task_count=${litter_task_count:-0}
  if [ "$rc" -ne 0 ] \
    || ! printf '%s\n' "$output" | grep -Fq 'VERDICT: pass' \
    || [ "$(verify_json_field "$bundle/attempts/001/verify.json" verdict 2>/dev/null)" != pass ] \
    || [ -e "$bundle/attempts/009/verify.json" ] \
    || [ "$litter_task_count" -ne 1 ]; then
    litter_paths_ok=0
  fi
done
if [ "$litter_paths_ok" -eq 1 ]; then
  pass "numeric regular-file, FIFO, and unreadable-directory litter is skipped for fallback and explicit attempts"
else
  fail_case "numeric regular-file, FIFO, and unreadable-directory litter is skipped for fallback and explicit attempts" \
    "one or more litter shapes blocked verification or redirected verify.json"
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
