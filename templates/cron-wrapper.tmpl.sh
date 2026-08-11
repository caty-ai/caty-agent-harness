#!/usr/bin/env bash
set -euo pipefail

# fable-loop cron wrapper template v1
#
# Copy this file to the target workspace scripts/ directory, set TARGET and
# CATY_HARNESS_ROOT to absolute paths, and pass the target arguments to this wrapper.
# Optional SECRETS_ENV is parsed as data-only KEY=VALUE assignments, one per
# physical line, when the file exists, is not a symlink, is owned by the current
# uid, and has 0600 or 0400 permissions. No shell code is executed. One matching
# outer quote layer is stripped only when its inner value has no matching quote,
# and one trailing CR is removed per line. Interpreter- or loader-control names
# are refused; the refusal list is a hazard guard, not an exhaustive safety
# boundary. Portable Bash 3.2 cannot open with O_NOFOLLOW, so a residual path
# replacement race remains despite the pre/post-open identity checks.

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

TARGET=${TARGET:-/absolute/path/to/caty-agent-harness-target}
CATY_HARNESS_ROOT=${CATY_HARNESS_ROOT:-}
CATY_WORKSPACE=${CATY_WORKSPACE:-}
SECRETS_ENV=${SECRETS_ENV:-}
DEADMAN_MARKER=${DEADMAN_MARKER:-}
DEADMAN_PROBE=${DEADMAN_PROBE:-}
DEADMAN_PROBE_ARGS=${DEADMAN_PROBE_ARGS:-}

fail() {
  printf 'cron-wrapper infra error: %s\n' "$1" >&2
  exit 3
}

file_owner_uid() {
  stat -c "%u" "$1" 2>/dev/null || stat -f "%u" "$1"
}

file_mode() {
  stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1"
}

validate_secrets_env() {
  local secrets_path=$1 current_uid owner_uid mode

  current_uid=$(id -u)
  owner_uid=$(file_owner_uid "$secrets_path")
  mode=$(file_mode "$secrets_path")

  if [[ "$owner_uid" != "$current_uid" ]]; then
    fail "SECRETS_ENV owner uid $owner_uid does not match current uid $current_uid: $secrets_path"
  fi
  case "$mode" in
    400|0400|600|0600) ;;
    *)
      fail "SECRETS_ENV permissions must be 0600 or 0400: $secrets_path has $mode"
      ;;
  esac
}

same_open_file() {
  local path=$1 fd_path=$2 path_identity fd_identity

  if [[ "$path" -ef "$fd_path" ]]; then
    return 0
  fi

  # Bash 3.2 on macOS cannot establish -ef identity through /dev/fd. Its BSD
  # stat still exposes the underlying file metadata (except device and mode),
  # so compare the stable identity fields and fail closed if either read fails.
  path_identity=$(stat -f "%u:%g:%i:%z:%m:%c:%B" "$path" 2>/dev/null) || return 1
  fd_identity=$(stat -f "%u:%g:%i:%z:%m:%c:%B" "$fd_path" 2>/dev/null) || return 1
  [[ "$path_identity" == "$fd_identity" ]]
}

first_nul_line() {
  local secrets_path=$1

  LC_ALL=C od -An -v -t u1 "$secrets_path" 2>/dev/null | awk '
    BEGIN { line_number = 1 }
    {
      for (field = 1; field <= NF; field++) {
        if (!found && $field == 0) {
          first_match = line_number
          found = 1
        }
        if ($field == 10) {
          line_number++
        }
      }
    }
    END {
      if (found) {
        print first_match
      }
    }
  '
}

parse_secrets_env() {
  local secrets_path=$1
  local line_number=0 raw_line line key value first_char last_char inner_value

  while IFS= read -r -u 9 raw_line || [[ -n "$raw_line" ]]; do
    line_number=$((line_number + 1))
    line=${raw_line%$'\r'}

    if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      case "$key" in
        BASH_ENV|ENV|SHELLOPTS|BASHOPTS|IFS|PS4|CDPATH|GLOBIGNORE|PATH|BASH_XTRACEFD|\
        PAGER|EDITOR|VISUAL|PERL5OPT|PERL5LIB|PERLLIB|PERL5DB|PERL5SHELL|\
        PYTHONSTARTUP|PYTHONPATH|PYTHONHOME|RUBYOPT|RUBYLIB|NODE_OPTIONS|NODE_PATH|\
        NODE_REPL_EXTERNAL_MODULE|GIT_SSH|GIT_SSH_COMMAND|GIT_EXTERNAL_DIFF|GIT_PAGER|\
        GIT_EDITOR|GIT_ASKPASS|SSH_ASKPASS|GIT_PROXY_COMMAND|GIT_CONFIG_GLOBAL|\
        GIT_CONFIG_SYSTEM|GIT_CONFIG_COUNT|GIT_CONFIG_PARAMETERS|GIT_EXEC_PATH|\
        GIT_ALTERNATE_OBJECT_DIRECTORIES|LESSOPEN|LESSCLOSE|BASH_FUNC_*|LD_*|DYLD_*)
          fail "SECRETS_ENV line $line_number refuses interpreter-control name $key (rename it, e.g. APP_ENV): $secrets_path"
          ;;
      esac
      if (( ${#value} >= 2 )); then
        first_char=${value:0:1}
        last_char=${value: -1}
        if [[ "$first_char" == "$last_char" && ( "$first_char" == "'" || "$first_char" == '"' ) ]]; then
          inner_value=${value:1:${#value}-2}
          if [[ "$inner_value" != *"$first_char"* ]]; then
            value=$inner_value
          fi
        fi
      fi
      # Bash 3.2 treats assignment errors from a directly invoked special
      # builtin as fatal even inside `if !`; `command` makes the status
      # catchable without changing export in the current shell.
      if ! command export "$key=$value" 2>/dev/null; then
        fail "SECRETS_ENV line $line_number cannot export $key (reserved or read-only name): $secrets_path"
      fi
      continue
    fi
    fail "SECRETS_ENV line $line_number is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $secrets_path"
  done
}

# Resolve the member workspace and shared pause helper before loading secrets,
# touching deadman markers, invoking probes, or executing TARGET. New installs
# should set CATY_HARNESS_ROOT explicitly; the TARGET-based lookup keeps the
# checked-in examples concise.
workspace_arg=$CATY_WORKSPACE
if [[ -z "$workspace_arg" ]]; then
  wrapper_args=("$@")
  for ((argument_index = 0; argument_index < ${#wrapper_args[@]}; argument_index++)); do
    argument=${wrapper_args[$argument_index]}
    case "$argument" in
      --workspace)
        if (( argument_index + 1 < ${#wrapper_args[@]} )); then
          workspace_arg=${wrapper_args[$((argument_index + 1))]}
        fi
        break
        ;;
      --input)
        argument_index=$((argument_index + 1))
        ;;
      --*)
        ;;
      *)
        if (( argument_index == 0 )); then
          workspace_arg=$argument
          break
        fi
        ;;
    esac
  done
fi

pause_helper=
if [[ -n "$CATY_HARNESS_ROOT" && -f "$CATY_HARNESS_ROOT/scripts/lib-pause.sh" ]]; then
  pause_helper="$CATY_HARNESS_ROOT/scripts/lib-pause.sh"
else
  target_dir=$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd -P) || target_dir=
  for candidate in "$target_dir/../scripts/lib-pause.sh" "$target_dir/../../scripts/lib-pause.sh"; do
    if [[ -f "$candidate" ]]; then
      pause_helper=$candidate
      break
    fi
  done
fi

if [[ -z "$pause_helper" || -z "$workspace_arg" || ! -f "$pause_helper" || ! -r "$pause_helper" || -L "$pause_helper" ]] \
  || ! bash -n "$pause_helper" >/dev/null 2>&1; then
  printf 'status=paused workspace=unknown entrypoint=cron-wrapper\n' >&2
  exit 0
fi
# shellcheck disable=SC1090
if ! source "$pause_helper" 2>/dev/null; then
  printf 'status=paused workspace=unknown entrypoint=cron-wrapper\n' >&2
  exit 0
fi
if ! workspace_arg=$(caty_pause_canonical_workspace "$workspace_arg" 2>/dev/null); then
  printf 'status=paused workspace=unknown entrypoint=cron-wrapper\n' >&2
  exit 0
fi
pause_state=$(caty_pause_workspace_state "$workspace_arg")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace_arg" cron-wrapper
  exit 0
fi

if [[ "$TARGET" != /* ]]; then
  fail "TARGET must be an absolute path: $TARGET"
fi
if [[ ! -x "$TARGET" ]]; then
  fail "TARGET is not executable: $TARGET"
fi

if [[ -n "$SECRETS_ENV" ]]; then
  if [[ -L "$SECRETS_ENV" ]]; then
    fail "SECRETS_ENV must not be a symlink: $SECRETS_ENV"
  fi
  if [[ -f "$SECRETS_ENV" ]]; then
    validate_secrets_env "$SECRETS_ENV"

    if ! nul_line=$(first_nul_line "$SECRETS_ENV"); then
      fail "SECRETS_ENV could not be scanned for embedded NUL bytes: $SECRETS_ENV"
    fi
    if [[ -n "$nul_line" ]]; then
      fail "SECRETS_ENV line $nul_line contains an embedded NUL byte: $SECRETS_ENV"
    fi

    if ! exec 9<"$SECRETS_ENV"; then
      fail "SECRETS_ENV is not readable: $SECRETS_ENV"
    fi
    if [[ -L "$SECRETS_ENV" ]] || ! same_open_file "$SECRETS_ENV" /dev/fd/9; then
      exec 9<&-
      fail "SECRETS_ENV changed while opening: $SECRETS_ENV"
    fi

    validate_secrets_env "$SECRETS_ENV"

    if [[ -L "$SECRETS_ENV" ]] || ! same_open_file "$SECRETS_ENV" /dev/fd/9; then
      exec 9<&-
      fail "SECRETS_ENV changed while validating: $SECRETS_ENV"
    fi

    parse_secrets_env "$SECRETS_ENV"
    exec 9<&-
  fi
fi

if [[ "$TARGET" != /* || ! -x "$TARGET" ]]; then
  fail "TARGET must remain an absolute executable after SECRETS_ENV: $TARGET"
fi
if [[ -n "$DEADMAN_MARKER" && "$DEADMAN_MARKER" != /* ]]; then
  fail "DEADMAN_MARKER must be an absolute path: $DEADMAN_MARKER"
fi
if [[ -n "$DEADMAN_PROBE" && "$DEADMAN_PROBE" != /* ]]; then
  fail "DEADMAN_PROBE must be an absolute path: $DEADMAN_PROBE"
fi

self_marking_flush_intake=0
flush_intake_target=$(cd "$(dirname "$pause_helper")/.." && pwd -P)/adapters/claude-code/flush-intake.sh
deadman_marker_compare=$DEADMAN_MARKER
deadman_marker_workspace=${DEADMAN_MARKER%/loop/.deadman/distill.marker}
if [[ "$deadman_marker_workspace" != "$DEADMAN_MARKER" ]] \
  && deadman_marker_workspace=$(caty_pause_canonical_workspace "$deadman_marker_workspace" 2>/dev/null); then
  deadman_marker_compare="$deadman_marker_workspace/loop/.deadman/distill.marker"
fi
if [[ -e "$flush_intake_target" && "$TARGET" -ef "$flush_intake_target" \
  && "$deadman_marker_compare" == "$workspace_arg/loop/.deadman/distill.marker" ]]; then
  self_marking_flush_intake=1
fi

if [[ -n "$DEADMAN_MARKER" && "$self_marking_flush_intake" -eq 0 ]]; then
  if ! mkdir -p "$(dirname "$DEADMAN_MARKER")"; then
    printf 'cron-wrapper warning: cannot create DEADMAN_MARKER parent: %s\n' "$DEADMAN_MARKER" >&2
  elif ! touch "$DEADMAN_MARKER"; then
    printf 'cron-wrapper warning: cannot touch DEADMAN_MARKER: %s\n' "$DEADMAN_MARKER" >&2
  fi
fi

if [[ -n "$DEADMAN_PROBE" ]]; then
  if [[ ! -x "$DEADMAN_PROBE" ]]; then
    printf 'cron-wrapper warning: DEADMAN_PROBE not executable: %s\n' "$DEADMAN_PROBE" >&2
  else
    deadman_probe_rc=0
    if [[ -n "$DEADMAN_PROBE_ARGS" ]]; then
      # DEADMAN_PROBE_ARGS is intentionally shell-style whitespace-separated extras.
      read -r -a deadman_probe_args <<<"$DEADMAN_PROBE_ARGS"
      "$DEADMAN_PROBE" "${deadman_probe_args[@]}" || deadman_probe_rc=$?
    else
      "$DEADMAN_PROBE" || deadman_probe_rc=$?
    fi
    if (( deadman_probe_rc != 0 )); then
      if (( deadman_probe_rc == 1 )); then
        printf 'cron-wrapper warning: DEADMAN_PROBE reported a deadman violation: %s\n' "$DEADMAN_PROBE" >&2
      else
        printf 'cron-wrapper warning: DEADMAN_PROBE failed: %s\n' "$DEADMAN_PROBE" >&2
      fi
    fi
  fi
fi

exec "$TARGET" "$@"
