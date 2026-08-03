#!/usr/bin/env bash
set -euo pipefail

# Stale agjob claim watchdog.
#
# Ledger input is a tab-separated stream with exactly five columns:
#   job_id<TAB>status<TAB>last_heartbeat_epoch<TAB>attempts_used<TAB>attempts_budget
#
# Sources:
#   AGJOB_LIST_CMD
#       Optional command string that prints the ledger format above, one job per line.
#   --ledger-file <path>
#       Optional deterministic test/input seam. Reads the same ledger format directly.
#
# Actions:
#   WATCHDOG_REQUEUE_CMD
#       Optional command string. Called as argv + "$job_id" for stale claimed jobs with
#       attempts remaining. If unset, the script prints "would requeue: <job_id>".
#   WATCHDOG_DLQ_CMD
#       Optional command string. Called as argv + "$job_id" for stale claimed jobs with
#       exhausted attempts. If unset, the script prints "would dlq: <job_id>".
#   WATCHDOG_STALE_SECS
#       Age threshold in seconds. Defaults to 3600.
#
# Command env vars should prefer a single wrapper-script path. Multi-token
# strings are whitespace-split; quotes are NOT honored.
#
# --dry-run scans and prints planned actions, but never calls action commands and never
# writes loop/pending/.

usage() {
  printf 'Usage: stale-claim-watchdog.sh --workspace <ws> [--ledger-file <path>] [--dry-run]\n' >&2
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

infra_fail() {
  printf 'stale-claim-watchdog infra error: %s\n' "$1" >&2
  exit 3
}

validate_cmd_argv0() {
  local env_name=$1
  local cmd=$2
  local bin
  local resolved_bin

  read -r -a _validated_argv <<<"$cmd"
  if ((${#_validated_argv[@]} == 0)); then
    infra_fail "$env_name is empty"
  fi

  bin=${_validated_argv[0]}
  if [[ "$bin" == */* ]]; then
    if [[ ! -e "$bin" ]]; then
      infra_fail "$env_name not found: $bin"
    fi
    if [[ ! -x "$bin" ]]; then
      infra_fail "$env_name not executable: $bin"
    fi
  else
    resolved_bin=$(command -v "$bin" 2>/dev/null || true)
    if [[ -z "$resolved_bin" ]]; then
      infra_fail "$env_name not found: $bin"
    fi
    if [[ ! -x "$resolved_bin" ]]; then
      infra_fail "$env_name not executable: $bin"
    fi
  fi
}

ensure_pending_file() {
  if [[ ! -e "$pending_file" ]]; then
    printf '%s\n' '# Stale claim watchdog notices — append-only distill candidates' >"$pending_file"
  fi
}

append_pending() {
  local job_id=$1
  local age=$2
  local action=$3
  local utc_date

  # Dedup within the daily file: a job that stays stale across cron ticks (action
  # command wired but ineffective, or unset) must not flood pending/.
  if [[ -f "$pending_file" ]] \
    && grep -Fq -- " stale claim $job_id heartbeat_age=" "$pending_file"; then
    return 0
  fi

  utc_date=$(date -u '+%Y-%m-%d')
  ensure_pending_file
  printf -- '- %s stale claim %s heartbeat_age=%ss action=%s (source: stale-claim-watchdog)\n' \
    "$utc_date" "$job_id" "$age" "$action" >>"$pending_file"
}

run_action_cmd() {
  local env_name=$1
  local cmd=$2
  local job_id=$3
  local argv

  validate_cmd_argv0 "$env_name" "$cmd"
  argv=("${_validated_argv[@]}")
  "${argv[@]}" "$job_id"
}

workspace=
ledger_file=
dry_run=0

while (($# > 0)); do
  case "$1" in
    --workspace)
      if (($# < 2)); then
        usage
        exit 2
      fi
      workspace=$2
      shift 2
      ;;
    --ledger-file)
      if (($# < 2)); then
        usage
        exit 2
      fi
      ledger_file=$2
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$workspace" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$workspace" ]]; then
  usage
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repo_root/scripts/lib-pause.sh"
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || {
  printf 'stale-claim-watchdog: invalid or symlinked workspace\n' >&2
  exit 2
}
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" hermes-stale-claim-watchdog
  exit 0
fi
pending_dir="$workspace/loop/pending"
pending_file="$pending_dir/watchdog-$(date -u '+%Y-%m-%d').md"
stale_secs=${WATCHDOG_STALE_SECS:-3600}

if ! is_uint "$stale_secs"; then
  printf 'WATCHDOG_STALE_SECS must be an unsigned integer\n' >&2
  exit 2
fi

tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$tmp_root/stale-claim-watchdog.XXXXXX")
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

input_file="$work_dir/ledger.tsv"
if [[ -n "$ledger_file" ]]; then
  if [[ ! -f "$ledger_file" ]]; then
    usage
    exit 2
  fi
  cp "$ledger_file" "$input_file"
elif [[ -n "${AGJOB_LIST_CMD:-}" ]]; then
  validate_cmd_argv0 AGJOB_LIST_CMD "$AGJOB_LIST_CMD"
  agjob_argv=("${_validated_argv[@]}")
  "${agjob_argv[@]}" >"$input_file"
else
  printf 'stale-claim-watchdog: AGJOB_LIST_CMD unset and --ledger-file not provided; no-op\n'
  exit 0
fi

if [[ "$dry_run" -eq 0 && ! -d "$pending_dir" ]]; then
  printf 'stale-claim-watchdog infra error: pending directory missing: %s\n' "$pending_dir" >&2
  exit 3
fi

now_epoch=$(date '+%s')

while IFS=$'\t' read -r job_id status last_heartbeat attempts_used attempts_budget extra; do
  [[ -n "$job_id" ]] || continue
  case "$job_id" in
    \#*) continue ;;
  esac
  [[ -z "${extra:-}" ]] || continue
  [[ "$status" = "claimed" ]] || continue
  is_uint "$last_heartbeat" || continue
  is_uint "$attempts_used" || continue
  is_uint "$attempts_budget" || continue

  # Force base-10: a leading zero (e.g. 08) would otherwise abort the whole scan
  # as an invalid octal under set -e.
  age=$(( now_epoch - 10#$last_heartbeat ))
  if (( age <= stale_secs )); then
    continue
  fi

  if (( attempts_used < attempts_budget )); then
    action=requeue
    planned='would requeue'
    action_cmd=${WATCHDOG_REQUEUE_CMD:-}
  else
    action=dlq
    planned='would dlq'
    action_cmd=${WATCHDOG_DLQ_CMD:-}
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%s: %s\n' "$planned" "$job_id"
    continue
  fi

  if [[ -n "$action_cmd" ]]; then
    if [[ "$action" = "requeue" ]]; then
      run_action_cmd WATCHDOG_REQUEUE_CMD "$action_cmd" "$job_id"
    else
      run_action_cmd WATCHDOG_DLQ_CMD "$action_cmd" "$job_id"
    fi
  else
    printf '%s: %s\n' "$planned" "$job_id"
  fi
  append_pending "$job_id" "$age" "$action"
done <"$input_file"

exit 0
