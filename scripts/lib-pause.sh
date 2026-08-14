#!/usr/bin/env bash
# Shared Caty Agent Harness workspace-pause primitives.
#
# Callers must pass an explicit workspace.  This library never falls back to
# cwd or an environment variable, because an implicit workspace could pause or
# resume the wrong agent.

CATY_PAUSE_RELATIVE_MARKER=".caty-agent-harness/DISABLED"
CATY_PAUSE_SENTINEL="CATY PAUSE AWARE v1"
CATY_PAUSE_BEGIN_SENTINEL="BEGIN CATY AGENT HARNESS BOOTSTRAP v2"
CATY_PAUSE_END_SENTINEL="END CATY AGENT HARNESS BOOTSTRAP v2"

caty_pause_value_is_record_safe() {
  local value=${1-}

  [[ -n "$value" ]] || return 1
  # Bracket ranges are collation-dependent (fail-open on bash 3.2 under any non-C collation);
  # [[:cntrl:]] classifies C0+DEL stably across locales.
  case "$value" in
    *[[:cntrl:]]*) return 1 ;;
    *) return 0 ;;
  esac
}

caty_pause_path_owner_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1" 2>/dev/null
}

caty_pause_canonical_workspace() {
  local workspace=${1-}

  caty_pause_value_is_record_safe "$workspace" || return 1
  [[ -n "$workspace" && "$workspace" != "/" ]] || return 1
  [[ -d "$workspace" && ! -L "$workspace" ]] || return 1
  (
    cd -P -- "$workspace" 2>/dev/null || exit 1
    [[ "$PWD" != "/" ]] || exit 1
    caty_pause_value_is_record_safe "$PWD" || exit 1
    printf '%s\n' "$PWD"
  )
}

caty_pause_validate_initialized_workspace() {
  local workspace=${1-}

  [[ -n "$workspace" && "$workspace" != "/" ]] || return 1
  [[ -d "$workspace" && ! -L "$workspace" ]] || return 1
  [[ -f "$workspace/STATE.md" && ! -L "$workspace/STATE.md" ]] || return 1
  [[ -d "$workspace/loop" && ! -L "$workspace/loop" ]] || return 1
}

caty_pause_control_dir_is_safe() {
  local control_dir=$1
  local owner_uid

  [[ -d "$control_dir" && ! -L "$control_dir" && -r "$control_dir" && -x "$control_dir" ]] || return 1
  owner_uid=$(caty_pause_path_owner_uid "$control_dir") || return 1
  [[ "$owner_uid" == "$(id -u)" ]]
}

# Print exactly one state value: enabled, paused, or indeterminate.
caty_pause_workspace_state() {
  local workspace=${1-}
  local control_dir
  local marker
  if ! caty_pause_value_is_record_safe "$workspace" \
    || [[ "$workspace" == "/" || ! -d "$workspace" || -L "$workspace" ]] \
    || ! caty_pause_validate_initialized_workspace "$workspace"; then
    printf 'indeterminate\n'
    return 0
  fi

  control_dir="$workspace/.caty-agent-harness"
  marker="$workspace/$CATY_PAUSE_RELATIVE_MARKER"

  if [[ -L "$control_dir" || ( -e "$control_dir" && ! -d "$control_dir" ) ]]; then
    printf 'indeterminate\n'
  elif [[ -L "$marker" || -e "$marker" ]]; then
    printf 'paused\n'
  elif [[ ! -e "$control_dir" ]]; then
    printf 'enabled\n'
  elif ! caty_pause_control_dir_is_safe "$control_dir"; then
    printf 'indeterminate\n'
  elif ! ls -A "$control_dir" >/dev/null 2>&1; then
    printf 'indeterminate\n'
  else
    printf 'enabled\n'
  fi
}

caty_pause_status_record() {
  local workspace=$1
  local entrypoint=$2

  printf 'status=paused workspace=%s entrypoint=%s\n' "$workspace" "$entrypoint" >&2
}
