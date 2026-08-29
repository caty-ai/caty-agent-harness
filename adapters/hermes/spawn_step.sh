#!/usr/bin/env bash
set -euo pipefail

# Hermes task-runner step adapter.
#
# The driver invokes this script as the process-group leader with:
#   spawn_step.sh <task-file> <workspace> <attempt-dir> <step-k>
#
# Required env:
#   HERMES_STEP_CMD
#     Command used as:
#       $HERMES_STEP_CMD <prompt-file> <attempt-dir>
#     The on-site installer pins the real CLI. That CLI must start a fresh
#     Hermes session for profile "luca", read the prompt file, write
#     <attempt-dir>/step-result.json, and exit.
#
# Optional env:
#   HERMES_PROBE_CMD
#     Cheap pre-flight reachability check. Failure exits 111 before launch.
#   HERMES_HTTP_TIMEOUT_S
#     Exported to the CLI environment. Defaults to 540.
#   HERMES_STEP_TIMEOUT_S
#     Wall-clock limit for the step command. It must stay below the driver's
#     TR_STEP_TIMEOUT_S (scripts/task-runner.sh), or the driver's hard group
#     kill wins first and this script cannot quarantine partial output.
#     run_bounded forwards TERM/INT/HUP to its detached CLI process group and
#     exits 143; this script's EXIT trap quarantines any canonical partial
#     result left by that forwarded-signal path.
#
# Command env vars are whitespace-split argv strings. Quotes are NOT honored, raw
# newline/CR is refused before splitting, standalone operator tokens are refused
# after splitting, and no command string is ever re-expanded through `sh -c`.
#
# Exit 111 is reserved for pre-flight infra failures only. Once the Hermes
# session command launches, its exit code is passed through unchanged.
# Adapters SHOULD duplicate fatal pre-flight CLI errors to stderr; the driver captures both streams as attempt evidence.
#
usage() {
  printf 'Usage: spawn_step.sh <task-file> <workspace> <attempt-dir> <step-k>\n' >&2
}

infra_fail() {
  printf 'spawn_step.sh: %s\n' "$1" >&2
  exit 111
}

if (($# != 4)); then
  usage
  exit 2
fi

task_file=$1
workspace=$2
attempt_dir=$3
step_k=$4
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repo_root/scripts/lib-classify.sh"
source "$repo_root/scripts/lib-bounded.sh"
source "$repo_root/scripts/lib-command-argv.sh"
source "$repo_root/scripts/lib-pause.sh"
prompt_file="$attempt_dir/prompt.md"

HERMES_HTTP_TIMEOUT_S=$(resolve_timeout_env HERMES_HTTP_TIMEOUT_S 540)
export HERMES_HTTP_TIMEOUT_S
HERMES_STEP_TIMEOUT_S=$(resolve_timeout_env HERMES_STEP_TIMEOUT_S 540)
HERMES_STEP_GRACE_S=$(resolve_timeout_env HERMES_STEP_GRACE_S 10 1)
TR_STEP_TIMEOUT_S=$(resolve_timeout_env TR_STEP_TIMEOUT_S 600 1)

# An HTTP timeout above the step timeout silently lets the wrapper kill hide the client timeout.
if (( HERMES_HTTP_TIMEOUT_S > HERMES_STEP_TIMEOUT_S )); then
  printf 'spawn_step.sh: ordering invariant failed: HERMES_HTTP_TIMEOUT_S(value=%s) <= HERMES_STEP_TIMEOUT_S(value=%s)\n' \
    "$HERMES_HTTP_TIMEOUT_S" "$HERMES_STEP_TIMEOUT_S" >&2
  exit 2
fi
# A cleanup grace at or above its step timeout silently makes cleanup outlive the operation it cleans up.
if (( HERMES_STEP_GRACE_S >= HERMES_STEP_TIMEOUT_S )); then
  printf 'spawn_step.sh: ordering invariant failed: HERMES_STEP_GRACE_S(value=%s) < HERMES_STEP_TIMEOUT_S(value=%s)\n' \
    "$HERMES_STEP_GRACE_S" "$HERMES_STEP_TIMEOUT_S" >&2
  exit 2
fi
# An adapter timeout plus grace at or above the driver timeout silently lets the driver preempt result quarantine.
if (( HERMES_STEP_TIMEOUT_S + HERMES_STEP_GRACE_S >= TR_STEP_TIMEOUT_S )); then
  printf 'spawn_step.sh: ordering invariant failed: HERMES_STEP_TIMEOUT_S(value=%s) + HERMES_STEP_GRACE_S(value=%s) < TR_STEP_TIMEOUT_S(value=%s)\n' \
    "$HERMES_STEP_TIMEOUT_S" "$HERMES_STEP_GRACE_S" "$TR_STEP_TIMEOUT_S" >&2
  exit 2
fi

# Keep the driver-facing arguments visible to strict mode and future audits.
: "$task_file" "$workspace" "$step_k"

if [[ ! -d "$workspace" ]]; then
  printf 'spawn_step.sh: workspace dir not found: %s\n' "$workspace" >&2
  exit 2
fi
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || {
  printf 'spawn_step.sh: invalid or symlinked workspace\n' >&2
  exit 2
}
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" hermes-spawn-step
  exit 0
fi

if [[ ! -f "$prompt_file" ]]; then
  printf 'spawn_step.sh: missing prompt file: %s\n' "$prompt_file" >&2
  exit 2
fi

if [[ -z "${HERMES_STEP_CMD:-}" ]]; then
  infra_fail 'HERMES_STEP_CMD is required'
fi

if ! validate_cmd_argv HERMES_STEP_CMD "$HERMES_STEP_CMD"; then
  infra_fail "HERMES_STEP_CMD: $_validated_reason"
fi
if ! resolve_cmd_argv0 HERMES_STEP_CMD; then
  infra_fail "HERMES_STEP_CMD: $_validated_reason"
fi
step_argv=("${_validated_argv[@]+"${_validated_argv[@]}"}")

probe_argv=()
if [[ -n "${HERMES_PROBE_CMD:-}" ]]; then
  if ! validate_cmd_argv HERMES_PROBE_CMD "$HERMES_PROBE_CMD"; then
    infra_fail "HERMES_PROBE_CMD: $_validated_reason"
  fi
  if ! resolve_cmd_argv0 HERMES_PROBE_CMD; then
    infra_fail "HERMES_PROBE_CMD: $_validated_reason"
  fi
  probe_argv=("${_validated_argv[@]+"${_validated_argv[@]}"}")
  cd "$workspace"
  if ! "${probe_argv[@]+"${probe_argv[@]}"}"; then
    infra_fail 'HERMES_PROBE_CMD failed'
  fi
fi

# Weak-model sessions lean on env vars they can echo — export the location
# contract alongside the prompt's concrete paths (field lesson: pilot 003
# improvised /tmp when ARTIFACT_DIR arrived empty).
artifact_dir=$(cd "$attempt_dir/.." && cd .. && pwd)
export TASK_FILE="$task_file" ARTIFACT_DIR="$artifact_dir" ATTEMPT_DIR="$attempt_dir" WORKSPACE="$workspace"

cd "$workspace"
step_stderr="$attempt_dir/step.stderr"
step_call_finished=0
_spawn_step_exit_quarantine() {
  if [[ "${step_call_finished:-0}" -eq 0 ]] && [[ -f "${attempt_dir:-}/step-result.json" ]]; then
    mv -f "$attempt_dir/step-result.json" "$attempt_dir/step-result.json.partial"
  fi
}
trap _spawn_step_exit_quarantine EXIT
set +e
run_bounded "$HERMES_STEP_TIMEOUT_S" "$HERMES_STEP_GRACE_S" "${step_argv[@]+"${step_argv[@]}"}" "$prompt_file" "$attempt_dir" 2>"$step_stderr"
step_status=$?
set -e
step_call_finished=1

if [[ "$step_status" -eq 124 || "$step_status" -gt 128 ]] && [[ -f "$attempt_dir/step-result.json" ]]; then
  mv -f "$attempt_dir/step-result.json" "$attempt_dir/step-result.json.partial"
fi

if (( step_status != 0 )); then
  failure_class=$(classify_failure "$step_status" "$step_stderr")
  cat "$step_stderr" >&2
  # classify.log is adapter-local and advisory; the driver's driver.json (which sees both streams) is the canonical classification.
  printf 'spawn_step.sh: call-site=step class=%s\n' "$failure_class" >>"$attempt_dir/classify.log"
fi

exit "$step_status"
