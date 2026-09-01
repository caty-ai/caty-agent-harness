#!/usr/bin/env bash
set -euo pipefail

# fable-loop cron wrapper template v2
# Legacy health-check signature (remove only with the install.sh v2 migration):
# fable-loop cron wrapper template v1
#
# Copy this file to the target workspace scripts/ directory, set TARGET and
# CATY_HARNESS_ROOT to absolute paths, and pass the target arguments to this wrapper.
# Optional CATY_WRAPPER_EXTRA_PATH appends absolute directories to the pinned
# system PATH for user-local CLI installs on Linux/WSL2. Appending prevents those
# directories from shadowing system tools.
# Optional SECRETS_ENV is parsed as data-only KEY=VALUE assignments, one per
# physical line, when the file exists, is not a symlink, is owned by the current
# uid, and has 0600 or 0400 permissions. No shell code is executed. One matching
# outer quote layer is stripped only when its inner value has no matching quote,
# and one trailing CR is removed per line. Interpreter- or loader-control names
# are refused by scripts/lib-secrets-env.sh, which must be installed beside the
# pause helper. The refusal list is a hazard guard, not an exhaustive safety
# boundary. Portable Bash 3.2 cannot open with O_NOFOLLOW, so a residual path
# replacement race remains despite the pre/post-open identity checks; accepted
# risk record: docs/engineering.md#accepted-risk-cron-wrapper-secrets-env-race.

fail() {
  printf 'cron-wrapper infra error: %s\n' "$1" >&2
  exit 3
}

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
if [[ -n "${CATY_WRAPPER_EXTRA_PATH:-}" ]]; then
  extra_path_remainder=$CATY_WRAPPER_EXTRA_PATH
  while :; do
    case "$extra_path_remainder" in
      *:*)
        extra_path_entry=${extra_path_remainder%%:*}
        extra_path_remainder=${extra_path_remainder#*:}
        extra_path_has_more=1
        ;;
      *)
        extra_path_entry=$extra_path_remainder
        extra_path_remainder=
        extra_path_has_more=0
        ;;
    esac
    if [[ -z "$extra_path_entry" || "$extra_path_entry" != /* ]]; then
      fail "CATY_WRAPPER_EXTRA_PATH entry must be non-empty and absolute: '$extra_path_entry'"
    fi
    if (( extra_path_has_more == 0 )); then
      break
    fi
  done
  PATH="$PATH:$CATY_WRAPPER_EXTRA_PATH"
fi
export PATH

TARGET=${TARGET:-/absolute/path/to/caty-agent-harness-target}
CATY_HARNESS_ROOT=${CATY_HARNESS_ROOT:-}
CATY_WORKSPACE=${CATY_WORKSPACE:-}
SECRETS_ENV=${SECRETS_ENV:-}
DEADMAN_MARKER=${DEADMAN_MARKER:-}
DEADMAN_PROBE=${DEADMAN_PROBE:-}
DEADMAN_PROBE_ARGS=${DEADMAN_PROBE_ARGS:-}

validate_secrets_env() {
  local secrets_path=$1 shape_reasons shape_reason mode

  shape_reasons=$(secrets_env_file_shape_reasons "$secrets_path")
  while IFS= read -r shape_reason; do
    [[ -n "$shape_reason" ]] || continue
    case "$shape_reason" in
      'permissions must be 0600 or 0400; has '*)
        mode=${shape_reason##* }
        fail "SECRETS_ENV permissions must be 0600 or 0400: $secrets_path has $mode"
        ;;
      *)
        fail "SECRETS_ENV $shape_reason: $secrets_path"
        ;;
    esac
  done <<EOF
$shape_reasons
EOF
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

parse_secrets_env() {
  local secrets_path=$1
  local line_number=0 raw_line classify_rc

  while IFS= read -r -u 9 raw_line || [[ -n "$raw_line" ]]; do
    line_number=$((line_number + 1))
    if secrets_env_classify_line "$raw_line"; then
      classify_rc=0
    else
      classify_rc=$?
    fi
    case "$classify_rc" in
      0)
        # `command` keeps assignment failures catchable across shells and modes
        # without changing where the variable is set.
        if ! command export "$SECRETS_ENV_KEY=$SECRETS_ENV_VALUE" 2>/dev/null; then
          fail "SECRETS_ENV line $line_number cannot export $SECRETS_ENV_KEY (reserved or read-only name): $secrets_path"
        fi
        ;;
      1)
        ;;
      2)
        fail "SECRETS_ENV line $line_number refuses interpreter-control name $SECRETS_ENV_KEY (rename it, e.g. APP_ENV): $secrets_path"
        ;;
      3)
        fail "SECRETS_ENV line $line_number is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $secrets_path"
        ;;
      *)
        fail "SECRETS_ENV line $line_number could not be classified: $secrets_path"
        ;;
    esac
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
  secrets_lib="$(dirname "$pause_helper")/lib-secrets-env.sh"
  if [[ ! -f "$secrets_lib" || ! -r "$secrets_lib" || -L "$secrets_lib" ]] \
    || ! bash -n "$secrets_lib" >/dev/null 2>&1; then
    fail "SECRETS_ENV acceptance library is unavailable or invalid: $secrets_lib"
  fi
  # shellcheck disable=SC1090
  if ! source "$secrets_lib" 2>/dev/null; then
    fail "SECRETS_ENV acceptance library could not be loaded: $secrets_lib"
  fi

  if [[ -L "$SECRETS_ENV" ]]; then
    validate_secrets_env "$SECRETS_ENV"
  fi
  if [[ ! -e "$SECRETS_ENV" ]]; then
    fail "SECRETS_ENV file not found: $SECRETS_ENV"
  fi
  if [[ ! -f "$SECRETS_ENV" ]]; then
    fail "SECRETS_ENV must be a regular file: $SECRETS_ENV"
  fi

  validate_secrets_env "$SECRETS_ENV"

  if [[ ! -r "$SECRETS_ENV" ]]; then
    fail "SECRETS_ENV is not readable: $SECRETS_ENV"
  fi
  if ! exec 9<"$SECRETS_ENV"; then
    fail "SECRETS_ENV is not readable: $SECRETS_ENV"
  fi
  if [[ -L "$SECRETS_ENV" ]] || ! same_open_file "$SECRETS_ENV" /dev/fd/9; then
    exec 9<&-
    fail "SECRETS_ENV changed while opening: $SECRETS_ENV"
  fi

  validate_secrets_env "$SECRETS_ENV"

  if ! nul_line=$(secrets_env_first_nul_line "$SECRETS_ENV"); then
    exec 9<&-
    fail "SECRETS_ENV could not be scanned for embedded NUL bytes: $SECRETS_ENV"
  fi
  if [[ -n "$nul_line" ]]; then
    exec 9<&-
    fail "SECRETS_ENV line $nul_line contains an embedded NUL byte: $SECRETS_ENV"
  fi

  if [[ -L "$SECRETS_ENV" ]] || ! same_open_file "$SECRETS_ENV" /dev/fd/9; then
    exec 9<&-
    fail "SECRETS_ENV changed while validating: $SECRETS_ENV"
  fi

  parse_secrets_env "$SECRETS_ENV"
  exec 9<&-
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
