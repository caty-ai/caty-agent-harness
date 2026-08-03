#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/check-tickprobe-test.$$
PASS_COUNT=0
FAIL_COUNT=0
WARN_NONE='warning: task-runner queue non-empty but no tick evidence found'
WARN_OLD='warning: task-runner queue non-empty but last tick evidence is older than 30 minutes'
WARN_SAMEDAY='cannot prove fresh'
WARN_SECRETS='SECRETS_ENV permissions should be 0600 or 0400'
WARN_DUPLICATE_BOOTSTRAP='warning: instruction lint: duplicate bootstrap marker'
WARN_LARGE_INSTRUCTIONS='warning: instruction lint: file exceeds 200 lines'
PRECEDENCE_LINE='Instruction precedence: user request > runtime safety > loop gates > instruction files > bootstrap > STATE > skill.'
LEARNING_PATH_PREFIX='learning path:'
VERIFY_HEADER='# VERIFY log — append-only verifier verdict history'

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

FAKE_BIN=$TMP_ROOT/fake-bin
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'if [ "$#" -eq 1 ] && [ "$1" = "+%s" ]; then'
  printf '%s\n' '  printf "%s\n" "${FAKE_NOW_EPOCH:?}"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'exec /bin/date "$@"'
} >"$FAKE_BIN/date"
chmod +x "$FAKE_BIN/date"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

seed_dates() {
  ws=$1
  printf '%s\n' '- task id: fixture; next action: none; blockers: none; last verified artifact path: none; 2026-07-05' >>"$ws/STATE.md"
  printf '%s\n' '- 2026-07-05 | task=fixture | verifier=test | verdict=pass | fixture' >>"$ws/loop/VERIFY.log.md"
}

new_ws() {
  name=$1
  ws=$TMP_ROOT/ws-$name
  "$ROOT/install.sh" --workspace "$ws" >/dev/null 2>&1
  seed_dates "$ws"
  printf '%s\n' "$ws"
}

run_check() {
  ws=$1
  env -u VERIFIER_CMD -u DISTILLER_CMD \
    "$ROOT/install.sh" --check --workspace "$ws" 2>&1
}

run_check_at_epoch() {
  ws=$1
  now_epoch=$2
  FAKE_NOW_EPOCH=$now_epoch PATH="$FAKE_BIN:$PATH" \
    "$ROOT/install.sh" --check --workspace "$ws" 2>&1
}

file_mtime_epoch() {
  path=$1
  stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path"
}

assert_no_tick_warning() {
  name=$1
  ws=$2
  output=$(run_check "$ws")
  rc=$?
  if [ "$rc" -eq 0 ] \
    && ! printf '%s\n' "$output" | grep -Fq "$WARN_NONE" \
    && ! printf '%s\n' "$output" | grep -Fq "$WARN_OLD"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

assert_has_warning() {
  name=$1
  ws=$2
  expected=$3
  output=$(run_check "$ws")
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$output" | grep -Fq "$expected"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

assert_no_instruction_warning() {
  name=$1
  ws=$2
  output=$(run_check "$ws")
  rc=$?
  if [ "$rc" -eq 0 ] \
    && ! printf '%s\n' "$output" | grep -Fq "$WARN_DUPLICATE_BOOTSTRAP" \
    && ! printf '%s\n' "$output" | grep -Fq "$WARN_LARGE_INSTRUCTIONS"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

assert_route_status() {
  name=$1
  output=$2
  adapter=$3
  route=$4
  status=$5
  expected="$LEARNING_PATH_PREFIX adapter=$adapter | route=$route | $status"
  if printf '%s\n' "$output" | grep -Fqx "$expected"; then
    pass "$name"
  else
    fail_case "$name" "missing: $expected"
  fi
}

copy_harness() {
  destination=$1
  mkdir -p "$destination"
  cp "$ROOT/install.sh" "$destination/install.sh"
  cp -R "$ROOT/adapters" "$ROOT/scripts" "$ROOT/templates" "$destination/"
}

queue_task() {
  ws=$1
  id=$2
  mkdir -p "$ws/loop/tasks/queue"
  printf '# task\n' >"$ws/loop/tasks/queue/$id.task.md"
}

assert_tick_age_boundary() {
  name=$1
  age=$2
  expect_warning=$3
  ws=$(new_ws "tick-age-$age")
  queue_task "$ws" task-one
  evidence=$ws/loop/artifacts/task-one/state.json
  mkdir -p "$(dirname "$evidence")"
  printf '{}\n' >"$evidence"
  touch -t 202001010000 "$evidence"
  evidence_epoch=$(file_mtime_epoch "$evidence")
  output=$(run_check_at_epoch "$ws" "$((evidence_epoch + age))")
  rc=$?
  case "$output" in
    *"$WARN_OLD"*) warning_seen=yes ;;
    *) warning_seen=no ;;
  esac
  if [ "$rc" -eq 0 ] \
    && ! printf '%s\n' "$output" | grep -Fq "$WARN_NONE" \
    && [ "$warning_seen" = "$expect_warning" ]; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc evidence_epoch=$evidence_epoch age=$age output=$output"
  fi
}

for adapter_block in "$ROOT"/adapters/*/bootstrap-block.md; do
  adapter_name=$(basename "$(dirname "$adapter_block")")
  precedence_count=$(grep -Fxc "$PRECEDENCE_LINE" "$adapter_block" || true)
  if [ "$precedence_count" -eq 1 ]; then
    pass "$adapter_name bootstrap has exactly one precedence contract"
  else
    fail_case "$adapter_name bootstrap has exactly one precedence contract" "count=$precedence_count"
  fi
done

ws=$(new_ws no-queue)
if [ "$(sed -n '1p' "$ws/loop/VERIFY.log.md")" = "$VERIFY_HEADER" ]; then
  pass "loop-init generates the append-only verifier history header"
else
  fail_case "loop-init generates the append-only verifier history header" \
    "header=$(sed -n '1p' "$ws/loop/VERIFY.log.md")"
fi
assert_no_tick_warning "no queue dir is silent" "$ws"
assert_has_warning "same-day date-only Last session warns" "$ws" "$WARN_SAMEDAY"
assert_no_instruction_warning "normal initialized workspace passes instruction lint" "$ws"

probe_ws=$(new_ws learning-paths)
probe_output=$(run_check "$probe_ws")
probe_rc=$?
if [ "$probe_rc" -eq 0 ] && [ "$probe_ws" != "$ROOT" ]; then
  pass "learning-path probes run through an initialized temporary workspace"
else
  fail_case "learning-path probes run through an initialized temporary workspace" "rc=$probe_rc workspace=$probe_ws"
fi

route_lines=$(printf '%s\n' "$probe_output" | grep -F "$LEARNING_PATH_PREFIX" || true)
route_count=$(printf '%s\n' "$route_lines" | grep -c '^learning path:' || true)
if [ "$route_count" -eq 22 ]; then
  pass "learning-path probes report 20 availability rows plus 2 conformance rows"
else
  fail_case "learning-path probes report 20 availability rows plus 2 conformance rows" "count=$route_count output=$route_lines"
fi

assert_route_status "claude-code CONSULT injection passes" "$probe_output" claude-code "CONSULT injection" PASS
assert_route_status "claude-code candidate generation passes" "$probe_output" claude-code "candidate generation" PASS
assert_route_status "claude-code verifier availability fails explicitly" "$probe_output" claude-code "verifier available" FAIL
assert_route_status "claude-code distiller cron fails explicitly" "$probe_output" claude-code "distiller cron" FAIL

assert_route_status "codex CONSULT injection passes" "$probe_output" codex "CONSULT injection" PASS
assert_route_status "codex candidate generation passes" "$probe_output" codex "candidate generation" PASS
assert_route_status "codex verifier availability fails explicitly" "$probe_output" codex "verifier available" FAIL
assert_route_status "codex distiller cron fails explicitly" "$probe_output" codex "distiller cron" FAIL

assert_route_status "hermes CONSULT injection passes" "$probe_output" hermes "CONSULT injection" PASS
assert_route_status "hermes candidate generation passes" "$probe_output" hermes "candidate generation" PASS
assert_route_status "hermes verifier availability passes" "$probe_output" hermes "verifier available" PASS
assert_route_status "hermes distiller cron fails explicitly" "$probe_output" hermes "distiller cron" FAIL
assert_route_status "hermes verifier conformance fails explicitly when unset" "$probe_output" hermes "verifier conformance" FAIL

assert_route_status "kimi CONSULT injection passes" "$probe_output" kimi "CONSULT injection" PASS
assert_route_status "kimi candidate generation passes" "$probe_output" kimi "candidate generation" PASS
assert_route_status "kimi verifier availability fails explicitly" "$probe_output" kimi "verifier available" FAIL
assert_route_status "kimi distiller cron fails explicitly" "$probe_output" kimi "distiller cron" FAIL

assert_route_status "openclaw CONSULT injection passes" "$probe_output" openclaw "CONSULT injection" PASS
assert_route_status "openclaw candidate generation passes" "$probe_output" openclaw "candidate generation" PASS
assert_route_status "openclaw verifier availability fails explicitly" "$probe_output" openclaw "verifier available" FAIL
assert_route_status "openclaw distiller cron passes" "$probe_output" openclaw "distiller cron" PASS
assert_route_status "openclaw distiller conformance fails explicitly when unset" "$probe_output" openclaw "distiller conformance" FAIL

broken_harness=$TMP_ROOT/broken-harness
copy_harness "$broken_harness"
chmod -x "$broken_harness/adapters/hermes/verify-job.sh"
broken_ws=$TMP_ROOT/ws-broken-learning-path
"$broken_harness/install.sh" --workspace "$broken_ws" >/dev/null 2>&1
seed_dates "$broken_ws"
broken_output=$("$broken_harness/install.sh" --check --workspace "$broken_ws" 2>&1)
broken_rc=$?
broken_routes=$(printf '%s\n' "$broken_output" | grep -F "$LEARNING_PATH_PREFIX" || true)
broken_route_count=$(printf '%s\n' "$broken_routes" | grep -c '^learning path:' || true)
expected_broken_routes=$(printf '%s\n' "$route_lines" | sed \
  's/learning path: adapter=hermes | route=verifier available | PASS/learning path: adapter=hermes | route=verifier available | FAIL/')
if [ "$broken_rc" -eq 0 ] \
  && [ "$broken_route_count" -eq 22 ] \
  && printf '%s\n' "$broken_routes" | grep -Fqx 'learning path: adapter=hermes | route=verifier available | FAIL' \
  && [ "$broken_routes" = "$expected_broken_routes" ]; then
  pass "breaking only Hermes verifier flips exactly one route to FAIL"
else
  fail_case "breaking only Hermes verifier flips exactly one route to FAIL" "rc=$broken_rc output=$broken_routes"
fi

broken_candidate_harness=$TMP_ROOT/broken-candidate-harness
copy_harness "$broken_candidate_harness"
codex_hook=$broken_candidate_harness/adapters/codex/checkpoint-stop-hook.sh
# shellcheck disable=SC2016
sed 's#flush_file="$cwd/loop/pending/#flush_file="$cwd/loop/disabled/#' \
  "$codex_hook" >"$codex_hook.tmp"
chmod +x "$codex_hook.tmp"
mv "$codex_hook.tmp" "$codex_hook"
broken_candidate_ws=$TMP_ROOT/ws-broken-candidate-path
"$broken_candidate_harness/install.sh" --workspace "$broken_candidate_ws" >/dev/null 2>&1
seed_dates "$broken_candidate_ws"
broken_candidate_output=$("$broken_candidate_harness/install.sh" --check --workspace "$broken_candidate_ws" 2>&1)
broken_candidate_rc=$?
broken_candidate_routes=$(printf '%s\n' "$broken_candidate_output" | grep -F "$LEARNING_PATH_PREFIX" || true)
broken_candidate_route_count=$(printf '%s\n' "$broken_candidate_routes" | grep -c '^learning path:' || true)
expected_broken_candidate_routes=$(printf '%s\n' "$route_lines" | sed \
  's/learning path: adapter=codex | route=candidate generation | PASS/learning path: adapter=codex | route=candidate generation | FAIL/')
if [ "$broken_candidate_rc" -eq 0 ] \
  && [ "$broken_candidate_route_count" -eq 22 ] \
  && printf '%s\n' "$broken_candidate_routes" | grep -Fqx 'learning path: adapter=codex | route=candidate generation | FAIL' \
  && [ "$broken_candidate_routes" = "$expected_broken_candidate_routes" ]; then
  pass "breaking only Codex pending-write seam flips exactly one route to FAIL"
else
  fail_case "breaking only Codex pending-write seam flips exactly one route to FAIL" \
    "rc=$broken_candidate_rc output=$broken_candidate_routes"
fi

ws=$(new_ws duplicate-bootstrap)
{
  printf '%s\n' '# fable-loop bootstrap v1'
  printf '%s\n' 'first block'
  printf '%s\n' '# fable-loop bootstrap v1'
  printf '%s\n' 'second block'
} >"$ws/AGENTS.md"
assert_has_warning "duplicate bootstrap marker warns without failing check" "$ws" "$WARN_DUPLICATE_BOOTSTRAP"

ws=$(new_ws duplicate-bootstrap-across-files)
printf '%s\n' '# fable-loop bootstrap v1' >"$ws/AGENTS.md"
printf '%s\n' '# fable-loop bootstrap v1' >"$ws/CLAUDE.md"
assert_has_warning "bootstrap marker in multiple instruction files warns" "$ws" "$WARN_DUPLICATE_BOOTSTRAP"

ws=$(new_ws duplicate-bootstrap-custom-file)
printf '%s\n%s\n' '# fable-loop bootstrap v1' '# fable-loop bootstrap v1' >"$ws/custom-agent-prompt.md"
assert_has_warning "duplicate bootstrap marker in custom append target warns" "$ws" "$WARN_DUPLICATE_BOOTSTRAP"

ws=$(new_ws single-bootstrap-custom-file)
mkdir -p "$ws/prompts"
printf '%s\n' '# fable-loop bootstrap v1' >"$ws/prompts/agent.md"
assert_no_instruction_warning "single bootstrap marker in nested custom target is healthy" "$ws"

ws=$(new_ws duplicate-bootstrap-nested-file)
mkdir -p "$ws/prompts"
printf '%s\n%s\n' '# fable-loop bootstrap v1' '# fable-loop bootstrap v1' >"$ws/prompts/agent.md"
assert_has_warning "duplicate bootstrap marker in nested custom target warns" "$ws" "$WARN_DUPLICATE_BOOTSTRAP"

ws=$(new_ws exact-limit-instructions)
i=0
while [ "$i" -lt 200 ]; do
  printf 'instruction line %03d\n' "$i"
  i=$((i + 1))
done >"$ws/AGENTS.md"
assert_no_instruction_warning "instruction file at exact line limit is healthy" "$ws"

ws=$(new_ws large-instructions)
i=0
while [ "$i" -lt 201 ]; do
  printf 'instruction line %03d\n' "$i"
  i=$((i + 1))
done >"$ws/AGENTS.md"
assert_has_warning "oversized instruction file warns without failing check" "$ws" "$WARN_LARGE_INSTRUCTIONS"

ws=$(new_ws empty-queue)
mkdir -p "$ws/loop/tasks/queue"
assert_no_tick_warning "empty queue is silent" "$ws"

ws=$(new_ws no-evidence)
queue_task "$ws" task-one
assert_has_warning "nonempty queue with no evidence warns" "$ws" "$WARN_NONE"
"$ROOT/install.sh" --check --workspace "$ws" >"$TMP_ROOT/check.stdout" 2>"$TMP_ROOT/check.stderr"
stream_rc=$?
if [ "$stream_rc" -eq 0 ] \
  && ! grep -Fq 'warning:' "$TMP_ROOT/check.stdout" \
  && grep -Fq "$WARN_NONE" "$TMP_ROOT/check.stderr" \
  && grep -Fqx 'state=enabled' "$TMP_ROOT/check.stdout" \
  && grep -Fqx 'bootstrap_state=unknown' "$TMP_ROOT/check.stdout"; then
  pass "check keeps machine tokens on stdout and human warnings on stderr"
else
  fail_case "check keeps machine tokens on stdout and human warnings on stderr" \
    "rc=$stream_rc stdout=$(cat "$TMP_ROOT/check.stdout") stderr=$(cat "$TMP_ROOT/check.stderr")"
fi

ws=$(new_ws old-evidence)
queue_task "$ws" task-one
mkdir -p "$ws/loop/artifacts/task-one"
printf '{}\n' >"$ws/loop/artifacts/task-one/state.json"
touch -t 202001010000 "$ws/loop/artifacts/task-one/state.json"
assert_has_warning "old tick evidence warns" "$ws" "$WARN_OLD"

ws=$(new_ws fresh-evidence)
queue_task "$ws" task-one
mkdir -p "$ws/loop/artifacts/task-one"
printf '{}\n' >"$ws/loop/artifacts/task-one/state.json"
assert_no_tick_warning "fresh tick evidence is silent" "$ws"

ws=$(new_ws progress-evidence)
queue_task "$ws" task-one
mkdir -p "$ws/loop/artifacts/task-one"
printf '# progress\n' >"$ws/loop/artifacts/task-one/PROGRESS.md"
assert_no_tick_warning "fresh PROGRESS.md evidence is silent" "$ws"

assert_tick_age_boundary "tick evidence age 1799 seconds is fresh" 1799 no
assert_tick_age_boundary "tick evidence age 1800 seconds is boundary-fresh" 1800 no
assert_tick_age_boundary "tick evidence age 1801 seconds warns" 1801 yes

ws=$(new_ws newest-wins)
queue_task "$ws" task-one
mkdir -p "$ws/loop/artifacts/task-old" "$ws/loop/artifacts/task-new"
printf '{}\n' >"$ws/loop/artifacts/task-old/state.json"
touch -t 202001010000 "$ws/loop/artifacts/task-old/state.json"
printf '{}\n' >"$ws/loop/artifacts/task-new/state.json"
assert_no_tick_warning "newest evidence wins over stale sibling" "$ws"

ws=$(new_ws unsafe-secrets)
mkdir -p "$ws/scripts"
secret="$ws/scripts/cron.env"
wrapper="$ws/scripts/cron-wrapper.sh"
printf 'DISTILLER_CMD=/bin/echo\n' >"$secret"
chmod 0644 "$secret"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# fable-loop cron wrapper template v1'
  printf 'SECRETS_ENV="%s"\n' "$secret"
} >"$wrapper"
assert_has_warning "cron wrapper unsafe secrets perms warn" "$ws" "$WARN_SECRETS"

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
