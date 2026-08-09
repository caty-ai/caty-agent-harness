#!/usr/bin/env bash
set -euo pipefail

# fable-loop cron wrapper template v1
#
# Copy this file to the target workspace scripts/ directory, set TARGET and
# CATY_HARNESS_ROOT to absolute paths, and pass the target arguments to this wrapper.
# Optional SECRETS_ENV is sourced only when the file exists, is owned by the
# current uid, and has 0600 or 0400 permissions.

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

# Resolve the member workspace and shared pause helper before sourcing secrets,
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

if [[ -n "$SECRETS_ENV" && -f "$SECRETS_ENV" ]]; then
  current_uid=$(id -u)
  owner_uid=$(file_owner_uid "$SECRETS_ENV")
  mode=$(file_mode "$SECRETS_ENV")

  if [[ "$owner_uid" != "$current_uid" ]]; then
    fail "SECRETS_ENV owner uid $owner_uid does not match current uid $current_uid: $SECRETS_ENV"
  fi
  case "$mode" in
    400|0400|600|0600) ;;
    *)
      fail "SECRETS_ENV permissions must be 0600 or 0400: $SECRETS_ENV has $mode"
      ;;
  esac

  # shellcheck disable=SC1090
  . "$SECRETS_ENV"
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

if [[ -n "$DEADMAN_MARKER" ]]; then
  if ! mkdir -p "$(dirname "$DEADMAN_MARKER")"; then
    printf 'cron-wrapper warning: cannot create DEADMAN_MARKER parent: %s\n' "$DEADMAN_MARKER" >&2
  elif ! touch "$DEADMAN_MARKER"; then
    printf 'cron-wrapper warning: cannot touch DEADMAN_MARKER: %s\n' "$DEADMAN_MARKER" >&2
  fi
fi

if [[ -n "$DEADMAN_PROBE" ]]; then
  if [[ ! -x "$DEADMAN_PROBE" ]]; then
    printf 'cron-wrapper warning: DEADMAN_PROBE not executable: %s\n' "$DEADMAN_PROBE" >&2
  elif [[ -n "$DEADMAN_PROBE_ARGS" ]]; then
    # DEADMAN_PROBE_ARGS is intentionally shell-style whitespace-separated extras.
    read -r -a deadman_probe_args <<<"$DEADMAN_PROBE_ARGS"
    if ! "$DEADMAN_PROBE" "${deadman_probe_args[@]}"; then
      printf 'cron-wrapper warning: DEADMAN_PROBE failed: %s\n' "$DEADMAN_PROBE" >&2
    fi
  elif ! "$DEADMAN_PROBE"; then
    printf 'cron-wrapper warning: DEADMAN_PROBE failed: %s\n' "$DEADMAN_PROBE" >&2
  fi
fi

exec "$TARGET" "$@"
