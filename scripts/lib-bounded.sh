#!/usr/bin/env bash
# Bounded subprocess helpers. run_bounded inherits its caller's stdout and stderr;
# callers that need capture should redirect the run_bounded invocation itself.

_BOUNDED_ACTIVE_PID=''

_bounded_pgid_live() {
  local pgid=$1
  [[ -n "$pgid" ]] && kill -0 -- "-$pgid" 2>/dev/null
}

_bounded_kill_group() {
  local pgid=$1
  local grace_s=$2
  local grace_start

  [[ -n "$pgid" ]] || return 0
  kill -TERM -- "-$pgid" 2>/dev/null || true
  grace_start=$SECONDS
  while _bounded_pgid_live "$pgid" && (( SECONDS - grace_start < grace_s )); do
    sleep 1
  done
  if _bounded_pgid_live "$pgid"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
  fi
}

_bounded_forward_term() {
  _bounded_kill_group "${_BOUNDED_ACTIVE_PID:-}" 2
  exit 143
}

resolve_timeout_env() {
  local env_name=$1
  local default_s=$2
  local floor_warn_s=${3:-10}
  local ceiling_warn_s=${4:-86400}
  local value=${!env_name-}

  if [[ -z "$value" ]]; then
    value=$default_s
  elif ! [[ "$value" =~ ^(0|[1-9][0-9]*)$ ]]; then
    printf 'WARNING: %s=%s is not numeric, using default %ss\n' \
      "$env_name" "$value" "$default_s" >&2
    value=$default_s
  elif (( value < floor_warn_s )); then
    printf 'WARNING: %s=%ss looks too low\n' "$env_name" "$value" >&2
  elif (( value > ceiling_warn_s )); then
    printf 'WARNING: %s=%ss looks too high\n' "$env_name" "$value" >&2
  fi

  printf '%s\n' "$value"
}

run_bounded() {
  local timeout_s=$1
  local grace_s=$2
  shift 2

  perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec {$ARGV[0]} @ARGV or die "exec: $!"' -- "$@" &
  local pid=$!
  _BOUNDED_ACTIVE_PID=$pid
  trap _bounded_forward_term TERM INT HUP
  local start_seconds=$SECONDS
  local timed_out=0
  local child_status=0

  # The direct-pid check covers the tiny interval before perl has called setsid().
  # Once setsid succeeds, the negative PID denotes the complete child process group.
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - start_seconds >= timeout_s )); then
      timed_out=1
      _bounded_kill_group "$pid" "$grace_s"
      break
    fi
    sleep 1
  done

  if wait "$pid"; then
    child_status=0
  else
    child_status=$?
  fi

  if (( timed_out == 1 )); then
    _BOUNDED_ACTIVE_PID=''
    trap - TERM INT HUP
    return 124
  fi

  # A successful or ordinary failing child may leave background descendants
  # holding locks. Reap its detached process group without changing its status.
  _bounded_kill_group "$pid" "$grace_s"
  _BOUNDED_ACTIVE_PID=''
  trap - TERM INT HUP
  return "$child_status"
}
