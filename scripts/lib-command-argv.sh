#!/usr/bin/env bash

_validated_argv=()
_validated_reason=
_validated_status_code=0

validate_cmd_argv() {
  local env_name=$1
  local cmd=$2
  local empty_mode=${3:-required}
  local token

  : "$env_name"
  _validated_argv=()
  _validated_reason=
  _validated_status_code=0

  if [[ "$cmd" == *$'\n'* || "$cmd" == *$'\r'* ]]; then
    _validated_reason=raw-newline-or-carriage-return
    return 1
  fi

  local IFS=$' \t\n'
  read -r -a _validated_argv <<<"$cmd"
  if ((${#_validated_argv[@]} == 0)); then
    if [[ "$empty_mode" = allow-empty ]]; then
      return 0
    fi
    _validated_reason=empty-after-split
    return 1
  fi

  for token in "${_validated_argv[@]+"${_validated_argv[@]}"}"; do
    case "$token" in
      ';'|'&'|'|'|'<'|'>'|'>>'|'||'|'&&'|';;'|'`')
        _validated_reason=standalone-operator
        return 1
        ;;
    esac
  done

  return 0
}

resolve_cmd_argv0() {
  local env_name=$1
  local bin
  local resolved_bin=

  : "$env_name"
  _validated_reason=
  _validated_status_code=0
  if ((${#_validated_argv[@]} == 0)); then
    _validated_reason=empty-after-split
    return 1
  fi
  bin=${_validated_argv[0]}

  if [[ "$bin" == */* ]]; then
    if [[ ! -e "$bin" ]]; then
      _validated_reason=not-found
      _validated_status_code=127
      return 1
    fi
    resolved_bin=$bin
  else
    resolved_bin=$(type -P "$bin" 2>/dev/null || true)
    if [[ -z "$resolved_bin" ]]; then
      _validated_reason=not-found
      _validated_status_code=127
      return 1
    fi
  fi

  if [[ ! -f "$resolved_bin" || ! -x "$resolved_bin" ]]; then
    _validated_reason=not-executable
    _validated_status_code=126
    return 1
  fi

  _validated_argv[0]=$resolved_bin
  return 0
}

append_redacted_push_output() {
  local src=$1
  local dest=$2

  sed -E \
    -e 's/^_: .*/[bash-level error suppressed]/' \
    -e 's#^(.*/)?task-runner\.sh: line [0-9]+: .*$#[task-runner shell diagnostic redacted]#' \
    "$src" >>"$dest"
}
