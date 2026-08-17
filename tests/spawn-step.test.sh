#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ADAPTER="$ROOT/adapters/hermes/spawn_step.sh"
RUNNER="$ROOT/scripts/task-runner.sh"

pass_count=0
fail_count=0
temps=()

log() {
  printf '%s\n' "$*"
}

pass() {
  pass_count=$(( pass_count + 1 ))
  log "PASS $1"
}

fail() {
  fail_count=$(( fail_count + 1 ))
  log "FAIL $1: $2"
}

cleanup() {
  local dir
  set +u
  for dir in "${temps[@]}"; do
    rm -rf "$dir"
  done
  set -u
}
trap cleanup EXIT

make_case_dir() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/spawn-step-test.XXXXXX")
  temps+=("$dir")
  mkdir -p "$dir/ws/loop" "$dir/attempt"
  printf '# State\n' >"$dir/ws/STATE.md"
  printf '# prompt\n' >"$dir/attempt/prompt.md"
  printf '# task\n' >"$dir/task.md"
  printf '%s\n' "$dir"
}

write_success_cli() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
prompt_file=$1
attempt_dir=$2
if [[ ! -f "$prompt_file" ]]; then
  exit 12
fi
printf '{"step_complete":true}\n' >"$attempt_dir/step-result.json"
SH
  chmod +x "$path"
}

write_exit_cli() {
  local path=$1
  local code=$2
  cat >"$path" <<SH
#!/usr/bin/env bash
exit $code
SH
  chmod +x "$path"
}

write_pwd_assert_cli() {
  local path=$1
  local expected_workspace=$2
  cat >"$path" <<SH
#!/usr/bin/env bash
set -euo pipefail
prompt_file=\$1
attempt_dir=\$2
if [[ "\$PWD" != "$expected_workspace" ]]; then
  printf 'bad pwd: %s\n' "\$PWD" >&2
  exit 13
fi
if [[ "\${WORKSPACE:-}" != "$expected_workspace" ]]; then
  printf 'bad WORKSPACE: %s\n' "\${WORKSPACE:-}" >&2
  exit 14
fi
test -f "\$prompt_file"
printf '{"step_complete":true}\n' >"\$attempt_dir/step-result.json"
SH
  chmod +x "$path"
}

run_adapter() {
  local dir=$1
  "$ADAPTER" "$dir/task.md" "$dir/ws" "$dir/attempt" 1
}

case_success() {
  local name=success
  local dir
  dir=$(make_case_dir)
  write_success_cli "$dir/fake-hermes"
  if HERMES_STEP_CMD="$dir/fake-hermes" run_adapter "$dir" && [[ -f "$dir/attempt/step-result.json" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 0 and step-result.json"
  fi
}

case_step_cmd_unset() {
  local name=step-cmd-unset
  local dir code
  dir=$(make_case_dir)
  set +e
  unset HERMES_STEP_CMD
  run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 111 ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 111, got $code"
  fi
}

case_step_cmd_nonexistent() {
  local name=step-cmd-nonexistent
  local dir code
  dir=$(make_case_dir)
  set +e
  HERMES_STEP_CMD="$dir/missing-hermes" run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 111 ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 111, got $code"
  fi
}

case_step_runs_in_workspace() {
  local name=step-runs-in-workspace
  local dir
  local expected_workspace
  dir=$(make_case_dir)
  expected_workspace=$(cd "$dir/ws" && pwd -P)
  write_pwd_assert_cli "$dir/fake-hermes" "$expected_workspace"
  if HERMES_STEP_CMD="$dir/fake-hermes" run_adapter "$dir" >/dev/null 2>&1 && [[ -f "$dir/attempt/step-result.json" ]]; then
    pass "$name"
  else
    fail "$name" "expected fake CLI to observe PWD == workspace and WORKSPACE export"
  fi
}

case_probe_cmd_nonexistent() {
  local name=probe-cmd-nonexistent
  local dir code output marker
  dir=$(make_case_dir)
  write_success_cli "$dir/fake-hermes"
  marker='probe-path-sentinel-44'
  set +e
  output=$(HERMES_STEP_CMD="$dir/fake-hermes" \
    HERMES_PROBE_CMD="$dir/missing-probe-$marker" \
    run_adapter "$dir" 2>&1)
  code=$?
  set -e
  if [[ "$code" -eq 111 ]] \
    && grep -Fq 'HERMES_PROBE_CMD: not-found' <<<"$output" \
    && ! grep -Fq "$marker" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exit 111 with redacted not-found reason, got rc=$code output=$output"
  fi
}

case_probe_failure_skips_step() {
  local name=probe-failure-skips-step
  local dir code sentinel
  dir=$(make_case_dir)
  sentinel="$dir/invoked"
  cat >"$dir/fake-hermes" <<SH
#!/usr/bin/env bash
touch "$sentinel"
exit 0
SH
  chmod +x "$dir/fake-hermes"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" HERMES_PROBE_CMD=false run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 111 ]] && [[ ! -e "$sentinel" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 111 without invoking step command"
  fi
}

case_probe_does_not_expand_tilde() {
  local name=probe-does-not-expand-tilde
  local dir code shell_expanded_rc literal_argv_rc sentinel literal_tilde workspace
  dir=$(make_case_dir)
  sentinel="$dir/invoked"
  workspace=$(cd "$dir/ws" && pwd -P)
  literal_tilde="$workspace/~"
  cat >"$dir/fake-hermes" <<SH
#!/usr/bin/env bash
touch "$sentinel"
printf '{"step_complete":true}\n' >"\$2/step-result.json"
SH
  chmod +x "$dir/fake-hermes"
  if [[ -e "$literal_tilde" ]]; then
    fail "$name" "expected no literal tilde entry in workspace before probe"
    return
  fi
  set +e
  (
    cd "$workspace"
    sh -c '/bin/ls ~ >/dev/null 2>&1'
  )
  shell_expanded_rc=$?
  (
    cd "$workspace"
    /bin/ls '~' >/dev/null 2>&1
  )
  literal_argv_rc=$?
  set -e
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" HERMES_PROBE_CMD='/bin/ls ~' run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  # Portability: BSD ls exits 1 on a missing operand, GNU ls exits 2 — assert
  # nonzero rather than a specific code. The discriminating guard is the
  # sentinel/111 pair, not this premise arm.
  if [[ "$shell_expanded_rc" -eq 0 ]] \
    && [[ "$literal_argv_rc" -ne 0 ]] \
    && [[ "$code" -eq 111 ]] \
    && [[ ! -e "$sentinel" ]] \
    && [[ ! -e "$literal_tilde" ]]; then
    pass "$name"
  else
    fail "$name" "expected shell-tilde rc0, literal-argv nonzero rc, and adapter rc111 without step launch: shell=$shell_expanded_rc literal=$literal_argv_rc adapter=$code"
  fi
}

case_probe_refuses_standalone_operator() {
  local name=probe-refuses-standalone-operator
  local dir code output sentinel
  dir=$(make_case_dir)
  sentinel="$dir/invoked"
  cat >"$dir/fake-hermes" <<SH
#!/usr/bin/env bash
touch "$sentinel"
printf '{"step_complete":true}\n' >"\$2/step-result.json"
SH
  chmod +x "$dir/fake-hermes"
  write_exit_cli "$dir/probe-ok" 0
  set +e
  output=$(HERMES_STEP_CMD="$dir/fake-hermes" \
    HERMES_PROBE_CMD="$dir/probe-ok | $dir/probe-ok" \
    run_adapter "$dir" 2>&1)
  code=$?
  set -e
  if [[ "$code" -eq 111 ]] \
    && grep -Fq 'HERMES_PROBE_CMD: standalone-operator' <<<"$output" \
    && ! grep -Fq "$dir/probe-ok | $dir/probe-ok" <<<"$output" \
    && [[ ! -e "$sentinel" ]]; then
    pass "$name"
  else
    fail "$name" "expected standalone-operator refusal before step launch: rc=$code output=$output"
  fi
}

case_probe_resolution_failure_does_not_leak_value() {
  local name=probe-resolution-failure-does-not-leak-value
  local dir code output_file marker
  dir=$(make_case_dir)
  marker='probe-path-sentinel-81'
  write_success_cli "$dir/fake-hermes"
  output_file="$dir/captured.stderr"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" \
    HERMES_PROBE_CMD="$dir/missing-probe-$marker" \
    "$ADAPTER" "$dir/task.md" "$dir/ws" "$dir/attempt" 1 \
    2>"$output_file"
  code=$?
  set -e
  if [[ "$code" -eq 111 ]] \
    && grep -Fq 'HERMES_PROBE_CMD: not-found' "$output_file" \
    && ! grep -Fq "$marker" "$output_file"; then
    pass "$name"
  else
    fail "$name" "expected rc=111 without leaking probe value into captured stderr: rc=$code output=$(cat "$output_file" 2>/dev/null)"
  fi
}

case_step_exit_passthrough() {
  local name=step-exit-passthrough
  local dir code
  dir=$(make_case_dir)
  write_exit_cli "$dir/fake-hermes" 7
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 7 ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 7, got $code"
  fi
}

case_missing_prompt() {
  local name=missing-prompt
  local dir code
  dir=$(make_case_dir)
  rm -f "$dir/attempt/prompt.md"
  write_success_cli "$dir/fake-hermes"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 2 ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 2, got $code"
  fi
}

write_hanging_cli() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
attempt_dir=$2
printf '{"step_comp' >"$attempt_dir/step-result.json"
sleep 60 &
printf '%s\n' "$!" >"$attempt_dir/grandchild.pid"
wait
SH
  chmod +x "$path"
}

write_signal_hanging_cli() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
attempt_dir=$2
printf '%s\n' "$$" >"$attempt_dir/cli.pid"
printf '{"step_comp' >"$attempt_dir/step-result.json"
sleep 60 &
printf '%s\n' "$!" >"$attempt_dir/grandchild.pid"
wait
SH
  chmod +x "$path"
}

write_fast_lingering_cli() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
attempt_dir=$2
sleep 60 &
printf '%s\n' "$!" >"$attempt_dir/grandchild.pid"
printf '{"step_complete":true}\n' >"$attempt_dir/step-result.json"
SH
  chmod +x "$path"
}

write_failure_result_cli() {
  local path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
attempt_dir=$2
printf '{"step_complete":false}\n' >"$attempt_dir/step-result.json"
exit 1
SH
  chmod +x "$path"
}

case_timeout_quarantines_partial_output_and_kills_group() {
  local name=timeout-quarantines-partial-output-and-kills-group
  local dir code grandchild_pid tries
  dir=$(make_case_dir)
  write_hanging_cli "$dir/fake-hermes"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" HERMES_STEP_TIMEOUT_S=2 HERMES_STEP_GRACE_S=1 run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  grandchild_pid=$(cat "$dir/attempt/grandchild.pid" 2>/dev/null || true)
  tries=0
  while [[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" 2>/dev/null && (( tries < 10 )); do
    sleep 1
    tries=$(( tries + 1 ))
  done
  if [[ "$code" -eq 124 ]] && [[ ! -e "$dir/attempt/step-result.json" ]] && \
     [[ -f "$dir/attempt/step-result.json.partial" ]] && [[ -n "$grandchild_pid" ]] && \
     ! kill -0 "$grandchild_pid" 2>/dev/null && grep -q 'class=transient' "$dir/attempt/classify.log"; then
    pass "$name"
  else
    fail "$name" "expected 124, quarantined output, dead grandchild, and transient classification"
  fi
}

case_fast_exit_preserves_complete_output_and_reaps_group() {
  local name=fast-exit-preserves-complete-output-and-reaps-group
  local dir code grandchild_pid tries
  dir=$(make_case_dir)
  write_fast_lingering_cli "$dir/fake-hermes"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" HERMES_STEP_TIMEOUT_S=10 HERMES_STEP_GRACE_S=1 run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  grandchild_pid=$(cat "$dir/attempt/grandchild.pid" 2>/dev/null || true)
  tries=0
  while [[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" 2>/dev/null && (( tries < 3 )); do
    sleep 1
    tries=$(( tries + 1 ))
  done
  if [[ "$code" -eq 0 ]] && [[ -f "$dir/attempt/step-result.json" ]] && \
     [[ ! -e "$dir/attempt/step-result.json.partial" ]] && [[ -n "$grandchild_pid" ]] && \
     ! kill -0 "$grandchild_pid" 2>/dev/null; then
    pass "$name"
  else
    fail "$name" "expected exit 0, unquarantined complete result, and dead grandchild"
  fi
}

case_ordinary_failure_preserves_complete_output() {
  local name=ordinary-failure-preserves-complete-output
  local dir code
  dir=$(make_case_dir)
  write_failure_result_cli "$dir/fake-hermes"
  set +e
  HERMES_STEP_CMD="$dir/fake-hermes" run_adapter "$dir" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 1 ]] && [[ -f "$dir/attempt/step-result.json" ]] && \
     [[ ! -e "$dir/attempt/step-result.json.partial" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit 1 with unquarantined complete result"
  fi
}

case_forwarded_term_quarantines_partial_output_and_kills_group() {
  local name=forwarded-term-quarantines-partial-output-and-kills-group
  local dir adapter_pid code grandchild_pid tries
  dir=$(make_case_dir)
  write_signal_hanging_cli "$dir/fake-hermes"
  HERMES_STEP_CMD="$dir/fake-hermes" HERMES_STEP_TIMEOUT_S=30 HERMES_STEP_GRACE_S=1 \
    "$ADAPTER" "$dir/task.md" "$dir/ws" "$dir/attempt" 1 >/dev/null 2>&1 &
  adapter_pid=$!
  tries=0
  while { [[ ! -s "$dir/attempt/cli.pid" ]] || [[ ! -s "$dir/attempt/grandchild.pid" ]]; } && (( tries < 40 )); do
    sleep 0.1
    tries=$(( tries + 1 ))
  done
  kill -TERM "$adapter_pid" 2>/dev/null || true
  set +e
  wait "$adapter_pid"
  code=$?
  set -e
  grandchild_pid=$(cat "$dir/attempt/grandchild.pid" 2>/dev/null || true)
  tries=0
  while [[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" 2>/dev/null && (( tries < 60 )); do
    sleep 0.1
    tries=$(( tries + 1 ))
  done
  if [[ "$code" -eq 143 ]] && [[ ! -e "$dir/attempt/step-result.json" ]] && \
     [[ -f "$dir/attempt/step-result.json.partial" ]] && [[ -n "$grandchild_pid" ]] && \
     ! kill -0 "$grandchild_pid" 2>/dev/null; then
    pass "$name"
  else
    fail "$name" "expected 143, quarantined output, and dead forwarded grandchild"
  fi
}

case_runner_rejects_relative_spawn_step() {
  local name=runner-rejects-relative-spawn-step
  local dir code output
  dir=$(make_case_dir)
  set +e
  output=$(TR_SPAWN_STEP=relative-spawn bash "$RUNNER" "$dir/ws" 2>&1)
  code=$?
  set -e
  if [[ "$code" -eq 2 ]] \
    && grep -Fq 'TR_SPAWN_STEP must be an absolute executable file' <<<"$output" \
    && ! grep -Fq 'relative-spawn' <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exit 2 with redacted TR_SPAWN_STEP validation, got rc=$code output=$output"
  fi
}

case_runner_rejects_nonexecutable_spawn_step() {
  local name=runner-rejects-nonexecutable-spawn-step
  local dir path code output
  dir=$(make_case_dir)
  path="$dir/not-executable"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$path"
  chmod 644 "$path"
  set +e
  output=$(TR_SPAWN_STEP="$path" bash "$RUNNER" "$dir/ws" 2>&1)
  code=$?
  set -e
  if [[ "$code" -eq 2 ]] \
    && grep -Fq 'TR_SPAWN_STEP must be an absolute executable file' <<<"$output" \
    && ! grep -Fq "$path" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exit 2 with redacted non-executable TR_SPAWN_STEP validation, got rc=$code output=$output"
  fi
}

case_success
case_step_cmd_unset
case_step_cmd_nonexistent
case_step_runs_in_workspace
case_probe_cmd_nonexistent
case_probe_failure_skips_step
case_probe_does_not_expand_tilde
case_probe_refuses_standalone_operator
case_probe_resolution_failure_does_not_leak_value
case_step_exit_passthrough
case_missing_prompt
case_timeout_quarantines_partial_output_and_kills_group
case_fast_exit_preserves_complete_output_and_reaps_group
case_ordinary_failure_preserves_complete_output
case_forwarded_term_quarantines_partial_output_and_kills_group
case_runner_rejects_relative_spawn_step
case_runner_rejects_nonexecutable_spawn_step

log "TOTAL pass=$pass_count fail=$fail_count"
if (( fail_count > 0 )); then
  exit 1
fi
