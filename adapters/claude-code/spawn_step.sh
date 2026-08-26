#!/usr/bin/env bash
set -euo pipefail

# Claude Code task-runner step adapter with an opt-in passive overflow sentinel.
# argv: spawn_step.sh <task-file> <workspace> <attempt-dir> <step-k>

usage() {
  printf 'Usage: spawn_step.sh <task-file> <workspace> <attempt-dir> <step-k>\n' >&2
}

config_fail() {
  printf 'spawn_step.sh: %s\n' "$1" >&2
  exit 2
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
source "$repo_root/scripts/lib-bounded.sh"
source "$repo_root/scripts/lib-command-argv.sh"
source "$repo_root/scripts/lib-pause.sh"
prompt_file="$attempt_dir/prompt.md"

: "$task_file" "$step_k"

[[ -d "$workspace" ]] || config_fail "workspace dir not found: $workspace"
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) \
  || config_fail 'invalid or symlinked workspace'
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" overflow-spawn-step
  exit 0
fi
[[ -d "$attempt_dir" ]] || config_fail "attempt dir not found: $attempt_dir"
attempt_dir=$(cd "$attempt_dir" && pwd -P)
prompt_file="$attempt_dir/prompt.md"
[[ -f "$prompt_file" ]] || config_fail "missing prompt file: $prompt_file"

ovf_mode=${OVF_SENTINEL:-}
case "$ovf_mode" in
  ''|shadow|active) ;;
  *) config_fail 'OVF_SENTINEL must be unset, shadow, or active' ;;
esac

ovf_step_cmd=${OVF_STEP_CMD:-claude -p --output-format stream-json --verbose}
if ! validate_cmd_argv OVF_STEP_CMD "$ovf_step_cmd"; then
  config_fail "OVF_STEP_CMD: $_validated_reason"
fi
if ! resolve_cmd_argv0 OVF_STEP_CMD; then
  config_fail "OVF_STEP_CMD: $_validated_reason"
fi
step_argv=("${_validated_argv[@]+"${_validated_argv[@]}"}")

export TASK_FILE="$task_file" ATTEMPT_DIR="$attempt_dir" WORKSPACE="$workspace"
artifact_dir=$(cd "$attempt_dir/../.." && pwd)
export ARTIFACT_DIR="$artifact_dir"
cd "$workspace"

step_call_finished=1
_overflow_quarantine_partial() {
  if [[ "${step_call_finished:-0}" -eq 0 ]] && [[ -f "${attempt_dir:-}/step-result.json" ]]; then
    mv -f "$attempt_dir/step-result.json" "$attempt_dir/step-result.json.partial"
  fi
}
trap _overflow_quarantine_partial EXIT

# Fully-off means no Python, no tee, and no overflow-sentinel artifacts.
if [[ -z "$ovf_mode" ]]; then
  ovf_step_timeout_s=540
  if [[ -n "${TR_STEP_TIMEOUT_S:-}" && "$TR_STEP_TIMEOUT_S" =~ ^[1-9][0-9]*$ ]]; then
    ovf_step_timeout_s=$TR_STEP_TIMEOUT_S
  fi
  step_call_finished=0
  set +e
  run_bounded "$ovf_step_timeout_s" 10 /bin/bash -c \
    'prompt=$1; shift; exec "$@" <"$prompt"' _ "$prompt_file" \
    "${step_argv[@]+"${step_argv[@]}"}"
  step_status=$?
  set -e
  step_call_finished=1
  if [[ "$step_status" -eq 124 || "$step_status" -gt 128 ]] && [[ -f "$attempt_dir/step-result.json" ]]; then
    mv -f "$attempt_dir/step-result.json" "$attempt_dir/step-result.json.partial"
  fi
  exit "$step_status"
fi

ovf_t_abs=${OVF_T_ABS:-80000}
case "$ovf_t_abs" in
  ''|*[!0-9]*|0|0[0-9]*) config_fail 'OVF_T_ABS must be an integer >= 1' ;;
esac
ovf_w_pct=${OVF_W_PCT:-50}
case "$ovf_w_pct" in
  ''|*[!0-9]*|0|0[0-9]*) config_fail 'OVF_W_PCT must be an integer from 1 through 99' ;;
esac
(( ovf_w_pct <= 99 )) || config_fail 'OVF_W_PCT must be an integer from 1 through 99'
printf -v ovf_w '0.%02d' "$ovf_w_pct"

ovf_ctx_window=${OVF_CTX_WINDOW:-}
if [[ -n "$ovf_ctx_window" ]]; then
  case "$ovf_ctx_window" in
    *[!0-9]*|0|0[0-9]*) config_fail 'OVF_CTX_WINDOW must be an integer >= 1' ;;
  esac
fi

ovf_finalize_timeout_s=${OVF_FINALIZE_TIMEOUT_S:-10}
case "$ovf_finalize_timeout_s" in
  ''|*[!0-9]*|0|0[0-9]*) config_fail 'OVF_FINALIZE_TIMEOUT_S must be an integer >= 1' ;;
esac

ovf_owner=${OVF_COMPACTION_OWNER:-}
case "$ovf_owner" in
  ''|sentinel|host) ;;
  *) config_fail 'OVF_COMPACTION_OWNER must be sentinel or host' ;;
esac

ovf_hf_config=${OVF_HF_CONFIG:-}
if [[ -n "$ovf_hf_config" ]]; then
  python3 -B "$repo_root/scripts/lib_overflow_sentinel.py" validate-hf "$ovf_hf_config" >/dev/null \
    || config_fail 'OVF_HF_CONFIG must name a validated local HF config.json'
fi

ovf_hf_network=${OVF_HF_NETWORK:-}
case "$ovf_hf_network" in
  ''|0|1) ;;
  *) config_fail 'OVF_HF_NETWORK must be unset, 0, or 1' ;;
esac
ovf_hf_cache_dir=${OVF_HF_CACHE_DIR:-}
if [[ "$ovf_hf_network" == 1 ]]; then
  [[ -n "$ovf_hf_cache_dir" ]] || config_fail 'OVF_HF_CACHE_DIR must be set when OVF_HF_NETWORK=1'
  python3 -B "$repo_root/scripts/lib_overflow_sentinel.py" prepare-hf-cache "$ovf_hf_cache_dir" >/dev/null \
    || config_fail 'OVF_HF_CACHE_DIR must name a writable non-symlink cache directory'
fi

ovf_step_timeout_s=540
if [[ -n "${TR_STEP_TIMEOUT_S:-}" && "$TR_STEP_TIMEOUT_S" =~ ^[1-9][0-9]*$ ]]; then
  if (( TR_STEP_TIMEOUT_S > ovf_finalize_timeout_s + 2 )); then
    ovf_step_timeout_s=$((TR_STEP_TIMEOUT_S - ovf_finalize_timeout_s - 1))
  else
    ovf_step_timeout_s=1
  fi
  if (( ovf_step_timeout_s <= 30 )); then
    printf 'warning: overflow sentinel derived CLI budget is only %ss after finalize reservation\n' \
      "$ovf_step_timeout_s" >&2
  fi
fi

if [[ -z "$ovf_owner" ]]; then
  printf 'warning: OVF_COMPACTION_OWNER is unset; overflow sentinel owns compaction detection\n' >&2
  ovf_owner=sentinel
fi

attempt_name=$(basename "$attempt_dir")
case "$attempt_name" in
  ''|*[!0-9]*) config_fail 'attempt directory basename must be numeric' ;;
esac
task_id=$(basename "$artifact_dir")
stream_path="$attempt_dir/stream.jsonl"
eof_path="$attempt_dir/overflow-stream.eof"
eof_tmp="$eof_path.tmp.$$"
monitor_stderr="$attempt_dir/.overflow-monitor.stderr.$$"
augmented_prompt=
monitor_pid=

_overflow_spawn_exit_quarantine() {
  if [[ -n "${monitor_pid:-}" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
    kill -KILL "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  [[ -z "${augmented_prompt:-}" ]] || rm -f "$augmented_prompt"
  rm -f "$eof_tmp" "$monitor_stderr"
  _overflow_quarantine_partial
}
trap _overflow_spawn_exit_quarantine EXIT

nudge_shown=0
prior_pending=
prior_pending_number=-1
if [[ -d "$artifact_dir/attempts" ]]; then
  for pending_candidate in "$artifact_dir"/attempts/*/overflow-nudge.pending; do
    [[ -f "$pending_candidate" && ! -L "$pending_candidate" ]] || continue
    [[ "$(dirname "$pending_candidate")" != "$attempt_dir" ]] || continue
    pending_attempt=$(basename "$(dirname "$pending_candidate")")
    case "$pending_attempt" in
      ''|*[!0-9]*) continue ;;
    esac
    pending_number=$((10#$pending_attempt))
    if (( pending_number > prior_pending_number )); then
      prior_pending=$pending_candidate
      prior_pending_number=$pending_number
    fi
  done
fi
if [[ -n "$prior_pending" ]]; then
  augmented_prompt=$(mktemp "$attempt_dir/.overflow-prompt.XXXXXX")
  {
    cat "$prior_pending"
    printf '\n--- original step prompt ---\n\n'
    cat "$prompt_file"
  } >"$augmented_prompt"
  rm -f "$prior_pending"
  prompt_file=$augmented_prompt
  nudge_shown=1
fi

monitor_args=(
  "$repo_root/adapters/claude-code/overflow_sentinel_monitor.py"
  --stream "$stream_path"
  --eof "$eof_path"
  --attempt-dir "$attempt_dir"
  --artifact-dir "$artifact_dir"
  --task-id "$task_id"
  --attempt "$attempt_name"
  --mode "$ovf_mode"
  --model "${CLAUDE_MODEL:-claude-unknown}"
  --t-abs "$ovf_t_abs"
  --w "$ovf_w"
)
[[ -z "$ovf_ctx_window" ]] || monitor_args+=(--ctx-window "$ovf_ctx_window")
[[ -z "$ovf_hf_config" ]] || monitor_args+=(--hf-config "$ovf_hf_config")
if [[ "$ovf_hf_network" == 1 ]]; then
  monitor_args+=(--hf-network --hf-cache-dir "$ovf_hf_cache_dir")
fi
[[ "$ovf_owner" != host ]] || monitor_args+=(--tap-status disabled-host)
(( nudge_shown == 0 )) || monitor_args+=(--nudge-shown)

python3 -B "${monitor_args[@]}" 2>"$monitor_stderr" &
monitor_pid=$!

step_call_finished=0
set +e
run_bounded "$ovf_step_timeout_s" 10 /bin/bash -c \
  'prompt=$1; shift; exec "$@" <"$prompt"' _ "$prompt_file" \
  "${step_argv[@]+"${step_argv[@]}"}" \
  | tee "$stream_path"
step_status=${PIPESTATUS[0]}
set -e
step_call_finished=1

if [[ "$step_status" -eq 124 || "$step_status" -gt 128 ]] && [[ -f "$attempt_dir/step-result.json" ]]; then
  mv -f "$attempt_dir/step-result.json" "$attempt_dir/step-result.json.partial"
fi

printf '%s\n' "$step_status" >"$eof_tmp"
mv -f "$eof_tmp" "$eof_path"

join_started=$SECONDS
monitor_timed_out=0
while kill -0 "$monitor_pid" 2>/dev/null; do
  if (( SECONDS - join_started >= ovf_finalize_timeout_s )); then
    monitor_timed_out=1
    kill -KILL "$monitor_pid" 2>/dev/null || true
    break
  fi
  sleep 0.05
done
set +e
wait "$monitor_pid"
monitor_status=$?
set -e
monitor_pid=

if (( monitor_timed_out == 1 )); then
  printf 'warning: overflow sentinel finalize timeout; records may be incomplete\n' >&2
elif (( monitor_status != 0 )); then
  printf 'warning: overflow sentinel monitor failed; continuing without complete sentinel records\n' >&2
  [[ ! -s "$monitor_stderr" ]] || cat "$monitor_stderr" >&2
elif [[ -s "$monitor_stderr" ]]; then
  cat "$monitor_stderr" >&2
fi

exit "$step_status"
