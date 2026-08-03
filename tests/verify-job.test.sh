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
i=0
while [ "$i" -lt 4000 ]; do
  printf '%080d\n' "$i"
  i=$((i + 1))
done
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'large output fixture pass'
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
  && grep -q 'verifier=fake | verdict=pass | fixture pass' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md"; then
  pass "valid verifier command runs and logs verdict"
else
  fail_case "valid verifier command runs and logs verdict" "rc=$rc output=$output"
fi

if [ "$(sed -n '1p' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md")" = "$VERIFY_HEADER" ]; then
  pass "verify-job creates the append-only verifier history header"
else
  fail_case "verify-job creates the append-only verifier history header" \
    "header=$(sed -n '1p' "$TMP_ROOT/ws-pass/loop/VERIFY.log.md")"
fi

bundle=$(make_bundle existing-log)
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
output=$(VERIFIER_CMD="$verifier" VERIFIER_ID=fake bash "$SCRIPT" "$bundle" 2>&1)
rc=$?
head -n "$existing_lines" "$existing_log" >"$existing_prefix"
if [ "$rc" -eq 0 ] \
  && cmp -s "$existing_snapshot" "$existing_prefix" \
  && [ "$(wc -l <"$existing_log" | tr -d '[:space:]')" -eq "$((existing_lines + 1))" ] \
  && grep -q 'task=task-one | verifier=fake | verdict=pass | fixture pass' "$existing_log"; then
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
  && grep -q 'verifier=hanging | verdict=inconclusive | call-site=verifier class=transient; wall-clock timeout after 2s' "$TMP_ROOT/ws-timeout/loop/VERIFY.log.md"; then
  pass "timed out verifier is inconclusive and transient"
else
  fail_case "timed out verifier is inconclusive and transient" "rc=$rc output=$output"
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
  && grep -q 'verifier=large-output | verdict=pass | large output fixture pass' "$TMP_ROOT/ws-large-output/loop/VERIFY.log.md"; then
  pass "large verifier output is parsed from temp file"
else
  fail_case "large verifier output is parsed from temp file" "rc=$rc output=$output"
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
  && grep -qi 'findings first' "$prompt_dump" \
  && grep -qi 'residual risks' "$prompt_dump" \
  && grep -Fqi 'must NOT be pass' "$prompt_dump" \
  && grep -qi 'uncertain or indirect evidence as incomplete' "$prompt_dump"; then
  pass "verifier prompt has findings-first and completion-audit contract"
else
  fail_case "verifier prompt has findings-first and completion-audit contract" "rc=$rc output=$output"
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
