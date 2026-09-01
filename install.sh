#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-wrapper-conformance.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-pause.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-secrets-env.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-donecheck.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-state-fold.sh"
legacy_marker_line="# fable-loop bootstrap v1"
current_marker_line="# caty-agent-harness bootstrap v2"

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [--workspace <dir>]
  ./install.sh --hermes <profile> [--append-bootstrap <file>]
  ./install.sh --openclaw <workspace-dir> [--append-bootstrap <file>]
  ./install.sh [--workspace <dir>] --bootstrap-runtime <runtime> --append-bootstrap <file>
  ./install.sh --check [--workspace <dir>]
  ./install.sh --disable --workspace <dir> [--dry-run]
  ./install.sh --enable --workspace <dir> [--dry-run]
  ./install.sh --help

Modes:
  No args
      Initialize the current directory by running scripts/loop-init --workspace "$PWD".

  --workspace <dir>
      Initialize <dir> by running scripts/loop-init --workspace <dir>.

  --hermes <profile>
      Initialize $HOME/.hermes/profiles/<profile>/workspace, then print the Hermes
      bootstrap block and the remaining manual Hermes wiring steps.

  --openclaw <workspace-dir>
      Initialize <workspace-dir>, then print the OpenClaw bootstrap block, a cron
      template with the real workspace path, and the STAGING_DIR relocation note.

  --append-bootstrap <file>
      Append a bootstrap block idempotently. Hermes mode uses the Hermes block,
      OpenClaw mode uses the OpenClaw block, and generic mode keeps the OpenClaw
      block only as a legacy compatibility default.

      If <file> already contains:
        # caty-agent-harness bootstrap v2
      this prints exactly:
        skip: bootstrap already present
      and leaves the file unchanged.

  --bootstrap-runtime <claude-code|codex|kimi|hermes|openclaw>
      Select the marker-aware block used by --append-bootstrap. Generic mode keeps
      openclaw as its compatibility default; public install docs always select one.

  --check [--workspace <dir>]
      Read-only health check. Defaults to the current directory. Exits 1 when
      required layout, STATE.md headers, or pause-control path safety is invalid.
      Learning-path conformance rows read and hash configured wrappers, probes,
      providers, and evidence files without executing them.
      Adapter authors should set SKILL_DESC_MAX (bytes) to the measured CONSULT loader budget.

  --disable --workspace <dir> [--dry-run]
      Reversibly pause this initialized workspace. STATE.md, learning records,
      queued work, verification history, skills, and artifacts are preserved.

  --enable --workspace <dir> [--dry-run]
      Resume a workspace paused by --disable. This removes only the harness-owned
      regular DISABLED marker; hostile marker objects are never followed.
USAGE
}

die_usage() {
  local reason=${1-}
  if [[ -n "$reason" ]]; then
    printf 'install.sh: %s\n' "$reason" >&2
  fi
  usage >&2
  exit 2
}

block_file_for_mode() {
  local runtime=$1

  case "$runtime" in
    hermes)
      printf '%s\n' "$repo_root/adapters/hermes/bootstrap-block.md"
      ;;
    claude-code)
      printf '%s\n' "$repo_root/adapters/claude-code/bootstrap-block.md"
      ;;
    codex)
      printf '%s\n' "$repo_root/adapters/codex/bootstrap-block.md"
      ;;
    kimi)
      printf '%s\n' "$repo_root/adapters/kimi/bootstrap-block.md"
      ;;
    openclaw|generic)
      printf '%s\n' "$repo_root/adapters/openclaw/bootstrap-block.md"
      ;;
    *)
      printf 'unknown runtime: %s\n' "$runtime" >&2
      exit 2
      ;;
  esac
}

append_bootstrap() {
  local target=$1
  local block_file=$2

  if [[ -e "$target" ]] && grep -Fqx "$current_marker_line" "$target"; then
    printf 'skip: bootstrap already present\n'
    return 0
  fi

  if [[ -e "$target" ]]; then
    if [[ -s "$target" ]]; then
      local last_byte
      last_byte=$(tail -c 1 "$target" | od -An -t x1 | tr -d '[:space:]')
      if [[ "$last_byte" != "0a" ]]; then
        printf '\n' >>"$target"
      fi
    fi
    {
      printf '%s\n' "$current_marker_line"
      cat "$block_file"
    } >>"$target"
    printf 'append: %s\n' "$target"
  else
    {
      printf '%s\n' "$current_marker_line"
      cat "$block_file"
    } >"$target"
    printf 'create: %s\n' "$target"
  fi
}

canonical_append_target() {
  local target=$1
  local parent
  local name

  caty_pause_value_is_record_safe "$target" || return 1
  [[ "$target" == /* ]] || return 1
  [[ ! -L "$target" ]] || return 1
  parent=$(dirname "$target")
  name=$(basename "$target")
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  parent=$(cd -P -- "$parent" && pwd) || return 1
  caty_pause_value_is_record_safe "$parent/$name" || return 1
  printf '%s/%s\n' "$parent" "$name"
}

register_instruction_file() {
  local workspace=$1
  local target=$2
  local control_dir="$workspace/.caty-agent-harness"
  local registry="$control_dir/instruction-files"
  local control_identity
  local registry_owner

  caty_pause_validate_initialized_workspace "$workspace" || return 0
  if [[ -L "$control_dir" || ( -e "$control_dir" && ! -d "$control_dir" ) ]]; then
    printf 'invalid harness control directory: %s\n' "$control_dir" >&2
    exit 2
  fi
  # Existing directories intentionally retain their mode.
  # shellcheck disable=SC2174
  mkdir -p -m 700 "$control_dir"
  if ! control_dir_is_user_owned "$control_dir"; then
    printf 'instruction registry control directory is not owned by the current user\n' >&2
    exit 2
  fi
  if [[ -L "$registry" || ( -e "$registry" && ! -f "$registry" ) ]]; then
    printf 'invalid instruction registry: %s\n' "$registry" >&2
    exit 2
  fi
  if [[ -f "$registry" ]]; then
    registry_owner=$(file_owner_uid "$registry" 2>/dev/null) || {
      printf 'cannot identify instruction registry owner\n' >&2
      exit 2
    }
    if [[ "$registry_owner" != "$(id -u)" || ! -r "$registry" ]]; then
      printf 'instruction registry is unreadable or not owned by the current user\n' >&2
      exit 2
    fi
  fi
  control_identity=$(path_identity "$control_dir") || {
    printf 'cannot identify instruction registry control directory\n' >&2
    exit 2
  }
  if ! (
    cd -P -- "$control_dir"
    control_dir_is_user_owned "$PWD"
    [[ "$(path_identity "$PWD" 2>/dev/null || true)" == "$control_identity" ]]
    [[ ! -L instruction-files && ( ! -e instruction-files || -f instruction-files ) ]]
    if [[ -f instruction-files ]]; then
      [[ "$(file_owner_uid instruction-files 2>/dev/null || true)" == "$(id -u)" && -r instruction-files ]]
      grep -Fqx "$target" instruction-files && exit 0
    fi
    umask 077
    printf '%s\n' "$target" >>instruction-files
  ); then
    printf 'instruction registry changed before append\n' >&2
    exit 2
  fi
  if ! control_dir_is_user_owned "$control_dir" \
    || [[ "$(path_identity "$control_dir" 2>/dev/null || true)" != "$control_identity" ]] \
    || [[ -L "$registry" || ! -f "$registry" || ! -r "$registry" ]] \
    || [[ "$(file_owner_uid "$registry" 2>/dev/null || true)" != "$(id -u)" ]] \
    || ! grep -Fqx "$target" "$registry"; then
    printf 'instruction registry or control directory changed during append\n' >&2
    exit 2
  fi
}

bootstrap_state_for_workspace() {
  local workspace=$1
  local registry="$workspace/.caty-agent-harness/instruction-files"
  local instruction_file
  local saw_file=0
  local saw_legacy=0
  local saw_unknown=0

  if [[ -L "$registry" || ! -f "$registry" || ! -r "$registry" ]]; then
    printf 'unknown\n'
    return 0
  fi

  while IFS= read -r instruction_file || [[ -n "$instruction_file" ]]; do
    [[ -n "$instruction_file" ]] || continue
    saw_file=1
    if ! caty_pause_value_is_record_safe "$instruction_file" \
      || [[ "$instruction_file" != /* || ! -f "$instruction_file" || ! -r "$instruction_file" || -L "$instruction_file" ]]; then
      saw_unknown=1
    elif instruction_has_legacy_bootstrap "$instruction_file"; then
      saw_legacy=1
      printf 'warning: legacy bootstrap is not pause-aware: %s\n' "$instruction_file" >&2
    elif grep -Fqx "$current_marker_line" "$instruction_file" \
      && instruction_has_current_pause_block "$instruction_file"; then
      :
    else
      saw_unknown=1
    fi
  done <"$registry"

  if (( saw_legacy )); then
    printf 'legacy\n'
  elif (( ! saw_file || saw_unknown )); then
    printf 'unknown\n'
  else
    printf 'current\n'
  fi
}

instruction_has_legacy_bootstrap() {
  local instruction_file=$1

  awk \
    -v legacy="$legacy_marker_line" \
    -v begin="$CATY_PAUSE_BEGIN_SENTINEL" \
    -v end="$CATY_PAUSE_END_SENTINEL" '
    $0 == legacy {found = 1}
    $0 == begin {in_v2 = 1; next}
    in_v2 && $0 == end {in_v2 = 0; next}
    !in_v2 {
      if (index($0, "The loop below applies to dispatched work with a deliverable.")) saw_loop = 1
      if (index($0, "CONSULT at task start:")) saw_consult = 1
      if (index($0, "CHECKPOINT at task end:")) saw_checkpoint = 1
    }
    END {exit (found || (saw_loop && saw_consult && saw_checkpoint)) ? 0 : 1}
  ' "$instruction_file"
}

instruction_has_current_pause_block() {
  local instruction_file=$1

  awk \
    -v begin="$CATY_PAUSE_BEGIN_SENTINEL" \
    -v pause="$CATY_PAUSE_SENTINEL" \
    -v end="$CATY_PAUSE_END_SENTINEL" '
    $0 == begin {
      in_block = 1
      saw_pause = 0
      saw_conditional = 0
      saw_skip = 0
      next
    }
    in_block && $0 == end {
      if (saw_pause && saw_conditional && saw_skip) found = 1
      in_block = 0
      next
    }
    in_block && $0 == pause {
      saw_pause = 1
      next
    }
    in_block && saw_pause {
      if (index($0, ".caty-agent-harness/DISABLED") \
          && index($0, "If it exists")) saw_conditional = 1
      if (saw_conditional && index($0, "skip all harness instructions")) saw_skip = 1
    }
    END {exit found ? 0 : 1}
  ' "$instruction_file"
}

control_dir_is_user_owned() {
  local control_dir=$1
  caty_pause_control_dir_is_safe "$control_dir"
}

path_identity() {
  stat -c '%d:%i' "$1" 2>/dev/null || stat -f '%d:%i' "$1" 2>/dev/null
}

pause_marker_is_user_owned_and_readable() {
  local marker=$1
  local owner_uid
  local mode
  local mode_decimal
  local owner_digit

  [[ -f "$marker" && ! -L "$marker" ]] || return 1
  owner_uid=$(file_owner_uid "$marker" 2>/dev/null) || return 1
  [[ "$owner_uid" == "$(id -u)" ]] || return 1
  mode=$(file_mode "$marker" 2>/dev/null) || return 1
  [[ "$mode" =~ ^[0-7]+$ ]] || return 1
  mode_decimal=$((10#$mode))
  owner_digit=$(((mode_decimal % 1000) / 100))
  (( (owner_digit & 4) != 0 )) || return 1
  [[ -r "$marker" ]]
}

pause_workspace() {
  local operation=$1
  local requested_workspace=$2
  local dry_run=$3
  local workspace
  local control_dir
  local marker
  local control_identity
  local marker_identity

  if ! workspace=$(caty_pause_canonical_workspace "$requested_workspace"); then
    printf 'invalid workspace path\n' >&2
    exit 2
  fi
  if ! caty_pause_validate_initialized_workspace "$workspace"; then
    printf 'workspace is not an initialized harness workspace: %s\n' "$workspace" >&2
    exit 2
  fi

  control_dir="$workspace/.caty-agent-harness"
  marker="$workspace/$CATY_PAUSE_RELATIVE_MARKER"
  printf 'workspace=%s\n' "$workspace"
  printf 'action=%s\n' "$operation"

  if [[ "$operation" == "disable" ]]; then
    if [[ -L "$control_dir" || ( -e "$control_dir" && ! -d "$control_dir" ) ]]; then
      printf 'invalid harness control directory: %s\n' "$control_dir" >&2
      exit 2
    fi
    if [[ -d "$control_dir" ]] && ! control_dir_is_user_owned "$control_dir"; then
      printf 'harness control directory is not owned by the current user: %s\n' "$control_dir" >&2
      exit 2
    fi
    if [[ -L "$marker" || -e "$marker" ]]; then
      printf 'result=already-paused\n'
      return 0
    fi
    if (( dry_run )); then
      printf 'result=would-pause\n'
      return 0
    fi
    mkdir -m 700 "$control_dir" 2>/dev/null || {
      [[ -d "$control_dir" && ! -L "$control_dir" ]] || {
        printf 'cannot create harness control directory: %s\n' "$control_dir" >&2
        exit 2
      }
    }
    if ! control_dir_is_user_owned "$control_dir"; then
      printf 'harness control directory is not owned by the current user: %s\n' "$control_dir" >&2
      exit 2
    fi
    control_identity=$(path_identity "$control_dir") || {
      printf 'cannot identify harness control directory\n' >&2
      exit 2
    }
    if ! control_dir_is_user_owned "$control_dir" \
      || [[ "$(path_identity "$control_dir" 2>/dev/null || true)" != "$control_identity" ]]; then
      printf 'harness control directory changed before marker creation\n' >&2
      exit 2
    fi
    if ! (
      cd -P -- "$control_dir"
      control_dir_is_user_owned "$PWD"
      [[ "$(path_identity "$PWD" 2>/dev/null || true)" == "$control_identity" ]]
      [[ ! -L DISABLED && ! -e DISABLED ]]
      set -C
      umask 077
      {
        printf 'schema=caty-agent-harness-pause/v1\n'
        printf 'disabled_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      } >DISABLED
    ) 2>/dev/null; then
      if [[ -L "$marker" || -e "$marker" ]]; then
        printf 'result=already-paused\n'
        return 0
      fi
      printf 'cannot create pause marker: %s\n' "$marker" >&2
      exit 2
    fi
    if ! control_dir_is_user_owned "$control_dir" \
      || [[ "$(path_identity "$control_dir" 2>/dev/null || true)" != "$control_identity" ]] \
      || ! pause_marker_is_user_owned_and_readable "$marker"; then
      printf 'pause marker or control directory changed during creation\n' >&2
      exit 2
    fi
    printf 'result=paused\n'
    return 0
  fi

  if [[ -L "$control_dir" || ( -e "$control_dir" && ! -d "$control_dir" ) ]]; then
    printf 'invalid harness control directory: %s\n' "$control_dir" >&2
    exit 2
  fi
  if [[ -d "$control_dir" ]] && ! control_dir_is_user_owned "$control_dir"; then
    printf 'harness control directory is not owned by the current user: %s\n' "$control_dir" >&2
    exit 2
  fi
  if [[ -L "$marker" || ( -e "$marker" && ! -f "$marker" ) ]]; then
    printf 'refusing to remove non-regular pause marker: %s\n' "$marker" >&2
    exit 2
  fi
  if [[ ! -e "$marker" ]]; then
    printf 'result=already-enabled\n'
    return 0
  fi
  if ! pause_marker_is_user_owned_and_readable "$marker"; then
    printf 'refusing to remove unreadable or foreign pause marker: %s\n' "$marker" >&2
    exit 2
  fi
  control_identity=$(path_identity "$control_dir") || {
    printf 'cannot identify harness control directory\n' >&2
    exit 2
  }
  marker_identity=$(path_identity "$marker") || {
    printf 'cannot identify pause marker\n' >&2
    exit 2
  }
  if (( dry_run )); then
    printf 'result=would-enable\n'
    return 0
  fi
  if ! control_dir_is_user_owned "$control_dir" \
    || [[ "$(path_identity "$control_dir" 2>/dev/null || true)" != "$control_identity" ]] \
    || ! pause_marker_is_user_owned_and_readable "$marker" \
    || [[ "$(path_identity "$marker" 2>/dev/null || true)" != "$marker_identity" ]]; then
    printf 'pause marker or control directory changed before enable\n' >&2
    exit 2
  fi
  if ! (
    cd -P -- "$control_dir"
    control_dir_is_user_owned "$PWD"
    [[ "$(path_identity "$PWD" 2>/dev/null || true)" == "$control_identity" ]]
    [[ ! -L DISABLED && -f DISABLED ]]
    pause_marker_is_user_owned_and_readable DISABLED
    [[ "$(path_identity DISABLED 2>/dev/null || true)" == "$marker_identity" ]]
    rm -- DISABLED
  ); then
    printf 'cannot remove pause marker: %s\n' "$marker" >&2
    exit 2
  fi
  if [[ -L "$marker" || -e "$marker" ]] \
    || ! control_dir_is_user_owned "$control_dir" \
    || [[ "$(path_identity "$control_dir" 2>/dev/null || true)" != "$control_identity" ]]; then
    printf 'pause marker removal could not be verified\n' >&2
    exit 2
  fi
  printf 'result=enabled\n'
}

run_loop_init() {
  local workspace=$1

  "$repo_root/scripts/loop-init" --workspace "$workspace"
  workspace=$(cd "$workspace" && pwd -P)
  migrate_last_session_on_install "$workspace"
  caty_load_interpreters "$workspace" || exit 2
}

migrate_last_session_on_install() {
  local workspace=$1
  local state_file="$workspace/STATE.md"
  local legacy_count
  local current_count
  local tmp_root
  local work_dir

  [[ -f "$state_file" ]] || return 0
  read -r legacy_count current_count <<EOF
$(awk '
  index($0, "## Last session") == 1 {in_section = 1; next}
  in_section && /^## / {exit}
  in_section && /^- task id:/ {legacy++}
  in_section && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / {current++}
  END {print legacy + 0, current + 0}
' "$state_file")
EOF
  if [[ "$legacy_count" -le 1 || "$current_count" -ne 0 ]]; then
    return 0
  fi
  if ! take_state_lock "$workspace" install-last-session-migration 30 1; then
    printf 'cannot acquire STATE lock for Last session migration\n' >&2
    return 1
  fi
  tmp_root=${TMPDIR:-/tmp}
  work_dir=$(mktemp -d "$tmp_root/last-session-install.XXXXXX") || {
    release_state_lock
    return 1
  }
  if ! fold_last_session_index "$workspace" "$state_file" "$work_dir" \
    "$(date -u '+%Y-%m-%d')" legacy-only; then
    printf 'Last session migration failed: %s\n' "$LAST_SESSION_FOLD_REASON" >&2
    rm -rf "$work_dir"
    release_state_lock
    return 1
  fi
  rm -rf "$work_dir"
  release_state_lock
}

print_hermes_next_steps() {
  cat "$repo_root/adapters/hermes/bootstrap-block.md"
  cat <<'EOF'

Remaining manual steps:
1. Append safely with --bootstrap-runtime hermes --append-bootstrap /absolute/instruction-file; the installer records that target for pause checks.
2. Wire an agjob job type named verify that calls adapters/hermes/verify-job.sh <bundle-dir>.
3. Create a single-file verifier wrapper and a separate verifier probe, then run scripts/attest-wrapper --route verifier --wrapper /abs/verifier-wrapper.sh --probe /abs/verifier-probe.sh.
4. Set VERIFIER_CMD=/abs/verifier-wrapper.sh; it must use a different vendor than the maker model per DESIGN R8.
5. Keep native auto_generate output staged in skills/_staging/ and do not promote during verifier outages or conformance failures.
EOF
}

print_openclaw_next_steps() {
  local workspace=$1

  workspace=$(cd "$workspace" && pwd)

  cat "$repo_root/adapters/openclaw/bootstrap-block.md"
  cat <<EOF

Nightly distillation cron template:
15 3 * * * CATY_HARNESS_ROOT="$repo_root" TARGET="$repo_root/adapters/openclaw/distill-audit.sh" DISTILLER_CMD="/abs/distiller-wrapper.sh" $repo_root/templates/cron-wrapper.tmpl.sh --workspace $workspace --input <session-log-dir> >>$workspace/loop/distill-cron.log 2>&1

Copy templates/cron-wrapper.tmpl.sh into the workspace scripts/ directory and use that copy for production cron. Set CATY_HARNESS_ROOT to this clone so the wrapper can apply the shared pause guard before secrets, deadman markers, probes, or TARGET. Leave --input <session-log-dir> as a placeholder until the real session-log directory is known. Before enabling cron, create a single-file distiller wrapper plus a separate probe and run scripts/attest-wrapper --route distiller --wrapper /abs/distiller-wrapper.sh --probe /abs/distiller-probe.sh.
If skills/ is symlinked or shared, set STAGING_DIR=$workspace/loop/skills-staging in the cron line to relocate draft skills outside the loaded skills tree.
EOF
}

extract_last_session_dates() {
  local state_file=$1

  awk '
    index($0, "## Last session") == 1 {in_section = 1; next}
    in_section && /^## / {exit}
    in_section && (/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / || /^- task id:/) {
      if (saw_entry) exit
      saw_entry = 1
    }
    in_section && saw_entry {print}
  ' "$state_file" | { grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true; } | sort -u
}

newest_verify_date() {
  local verify_file=$1

  { grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$verify_file" || true; } | sort | tail -n 1
}

print_relative() {
  local workspace=$1
  local path=$2

  case "$path" in
    "$workspace"/*)
      printf '%s\n' "${path#"$workspace"/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

file_owner_uid() {
  local path=$1
  stat -c "%u" "$path" 2>/dev/null || stat -f "%u" "$path"
}

file_mode() {
  local path=$1
  stat -c "%a" "$path" 2>/dev/null || stat -f "%Lp" "$path"
}

check_secrets_env_file() {
  local workspace=$1
  local secrets_file=$2
  local source_file=$3
  local home_resolution_note=${4:-}
  local wrapper_rel
  local shape_reasons shape_reason mode
  local nul_line
  local line_number=0 raw_line classify_rc

  [[ -n "$secrets_file" ]] || return 0
  wrapper_rel=$(print_relative "$workspace" "$source_file")
  if [[ -L "$secrets_file" ]]; then
    shape_reasons=$(secrets_env_file_shape_reasons "$secrets_file")
    while IFS= read -r shape_reason; do
      [[ -n "$shape_reason" ]] || continue
      printf 'FAIL: cron wrapper %s SECRETS_ENV %s: %s%s\n' "$wrapper_rel" "$shape_reason" "$secrets_file" "$home_resolution_note" >&2
    done <<EOF
$shape_reasons
EOF
    return 1
  fi
  if [[ ! -e "$secrets_file" ]]; then
    printf 'FAIL: cron wrapper %s SECRETS_ENV file not found: %s%s\n' "$wrapper_rel" "$secrets_file" "$home_resolution_note" >&2
    return 1
  fi
  if [[ ! -f "$secrets_file" ]]; then
    printf 'FAIL: cron wrapper %s SECRETS_ENV must be a regular file: %s%s\n' "$wrapper_rel" "$secrets_file" "$home_resolution_note" >&2
    return 1
  fi

  shape_reasons=$(secrets_env_file_shape_reasons "$secrets_file")
  while IFS= read -r shape_reason; do
    [[ -n "$shape_reason" ]] || continue
    case "$shape_reason" in
      'permissions must be 0600 or 0400; has '*)
        mode=${shape_reason##* }
        printf 'warning: cron wrapper %s SECRETS_ENV permissions should be 0600 or 0400: %s has %s\n' "$wrapper_rel" "$secrets_file" "$mode" >&2
        ;;
      *)
        printf 'warning: cron wrapper %s SECRETS_ENV %s: %s\n' "$wrapper_rel" "$shape_reason" "$secrets_file" >&2
        ;;
    esac
  done <<EOF
$shape_reasons
EOF

  if [[ ! -r "$secrets_file" ]]; then
    printf 'FAIL: cron wrapper %s SECRETS_ENV file is not readable: %s%s\n' "$wrapper_rel" "$secrets_file" "$home_resolution_note" >&2
    return 1
  fi

  if ! nul_line=$(secrets_env_first_nul_line "$secrets_file"); then
    printf 'warning: cron wrapper %s SECRETS_ENV could not be scanned for embedded NUL bytes: %s\n' "$wrapper_rel" "$secrets_file" >&2
    return 0
  fi
  if [[ -n "$nul_line" ]]; then
    printf 'warning: cron wrapper %s SECRETS_ENV line %s contains an embedded NUL byte: %s\n' "$wrapper_rel" "$nul_line" "$secrets_file" >&2
    return 0
  fi

  if ! exec 8<"$secrets_file"; then
    printf 'FAIL: cron wrapper %s SECRETS_ENV file is not readable: %s%s\n' "$wrapper_rel" "$secrets_file" "$home_resolution_note" >&2
    return 1
  fi
  while IFS= read -r -u 8 raw_line || [[ -n "$raw_line" ]]; do
    line_number=$((line_number + 1))
    if secrets_env_classify_line "$raw_line"; then
      classify_rc=0
    else
      classify_rc=$?
    fi
    case "$classify_rc" in
      0)
        if ! (command export "$SECRETS_ENV_KEY=$SECRETS_ENV_VALUE") 2>/dev/null; then
          printf 'warning: cron wrapper %s SECRETS_ENV line %s cannot export %s (reserved or read-only name): %s\n' \
            "$wrapper_rel" "$line_number" "$SECRETS_ENV_KEY" "$secrets_file" >&2
        fi
        ;;
      1)
        ;;
      2)
        printf 'warning: cron wrapper %s SECRETS_ENV line %s refuses interpreter-control name %s (rename it, e.g. APP_ENV): %s\n' \
          "$wrapper_rel" "$line_number" "$SECRETS_ENV_KEY" "$secrets_file" >&2
        ;;
      3)
        printf 'warning: cron wrapper %s SECRETS_ENV line %s is not a KEY=VALUE assignment: %s\n' \
          "$wrapper_rel" "$line_number" "$secrets_file" >&2
        ;;
      *)
        printf 'warning: cron wrapper %s SECRETS_ENV line %s could not be classified: %s\n' \
          "$wrapper_rel" "$line_number" "$secrets_file" >&2
        ;;
    esac
  done
  exec 8<&-
}

trim_wrapper_secrets_env_value() {
  local value=$1

  value=${value#"${value%%[![:space:]]*}"}
  case "$value" in
    *[![:space:]]*)
      value=${value%"${value##*[![:space:]]}"}
      ;;
    *)
      value=
      ;;
  esac

  printf '%s\n' "$value"
}

strip_wrapper_secrets_env_comment() {
  local value=$1
  local idx char quote='' prev_char=''

  for (( idx=0; idx<${#value}; idx++ )); do
    char=${value:idx:1}
    if [[ -z "$quote" ]]; then
      case "$char" in
        "'"|'"'|'`')
          quote=$char
          ;;
        '#')
          if [[ "$prev_char" =~ [[:space:]] ]]; then
            value=${value:0:idx}
            break
          fi
          ;;
      esac
    elif [[ "$char" == "$quote" ]]; then
      quote=
    fi
    prev_char=$char
  done

  trim_wrapper_secrets_env_value "$value"
}

wrapper_secrets_env_home_note() {
  local secrets_assignment=$1
  local home_brace_pattern="\${HOME}"

  if [[ "$secrets_assignment" == *"$home_brace_pattern"* ]] \
    || [[ "$secrets_assignment" =~ \$HOME([^A-Za-z0-9_]|$) ]]; then
    printf ' (resolution uses the checking process HOME and may differ under sudo/other users)'
  fi
}

substitute_wrapper_home_tokens() {
  local value=$1
  local home_value=${HOME:-}
  local resolved=
  local cursor=0
  local remaining token_suffix

  while (( cursor < ${#value} )); do
    remaining=${value:cursor}
    if [[ "$remaining" == "\${HOME}"* ]]; then
      resolved=$resolved$home_value
      cursor=$((cursor + 7))
      continue
    fi
    if [[ "$remaining" == "\$HOME"* ]]; then
      token_suffix=${remaining:5:1}
      if [[ -z "$token_suffix" || ! "$token_suffix" =~ [A-Za-z0-9_] ]]; then
        resolved=$resolved$home_value
        cursor=$((cursor + 5))
        continue
      fi
    fi
    resolved=$resolved${value:cursor:1}
    cursor=$((cursor + 1))
  done

  if [[ "$resolved" == *'$'* ]]; then
    return 1
  fi

  printf '%s\n' "$resolved"
}

resolve_wrapper_secrets_env_audit_path() {
  local secrets_assignment=$1
  local stripped_assignment first_char last_char inner_value

  stripped_assignment=$(strip_wrapper_secrets_env_comment "$secrets_assignment")
  WRAPPER_SECRETS_ENV_HOME_NOTE=$(wrapper_secrets_env_home_note "$stripped_assignment")
  WRAPPER_SECRETS_ENV_AUDIT_PATH=

  if [[ -z "$stripped_assignment" ]]; then
    return 1
  fi
  if [[ "$stripped_assignment" == *'`'* ]]; then
    return 1
  fi

  first_char=${stripped_assignment:0:1}
  last_char=${stripped_assignment: -1}

  if [[ "$stripped_assignment" != *"'"* && "$stripped_assignment" != *'"'* ]]; then
    if ! WRAPPER_SECRETS_ENV_AUDIT_PATH=$(substitute_wrapper_home_tokens "$stripped_assignment"); then
      return 1
    fi
    return 0
  fi

  if (( ${#stripped_assignment} >= 2 )) && [[ "$first_char" == '"' && "$last_char" == '"' ]]; then
    inner_value=${stripped_assignment:1:${#stripped_assignment}-2}
    if [[ "$inner_value" == *'"'* || "$inner_value" == *"'"* || "$inner_value" == *'`'* ]]; then
      return 1
    fi
    if ! WRAPPER_SECRETS_ENV_AUDIT_PATH=$(substitute_wrapper_home_tokens "$inner_value"); then
      return 1
    fi
    return 0
  fi

  if (( ${#stripped_assignment} >= 2 )) && [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
    inner_value=${stripped_assignment:1:${#stripped_assignment}-2}
    if [[ "$inner_value" == *'"'* || "$inner_value" == *"'"* || "$inner_value" == *'`'* ]]; then
      return 1
    fi
    WRAPPER_SECRETS_ENV_HOME_NOTE=
    WRAPPER_SECRETS_ENV_AUDIT_PATH=$inner_value
    return 0
  fi

  return 1
}

extract_wrapper_secrets_env() {
  local wrapper=$1
  local line assignment

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*SECRETS_ENV= ]]; then
      assignment=${line#*=}
      trim_wrapper_secrets_env_value "$assignment"
      return 0
    fi
  done <"$wrapper"
}

check_cron_wrappers() {
  local workspace=$1
  local scripts_dir="$workspace/scripts"
  local wrapper
  local secrets_assignment secrets_file
  local wrapper_rel
  local failures=0
  local unauditable_count=0
  local home_resolution_note

  [[ -d "$scripts_dir" ]] || return 0

  while IFS= read -r wrapper; do
    [[ -n "$wrapper" ]] || continue
    if grep -Fq '# fable-loop cron wrapper template v1' "$wrapper"; then
      secrets_assignment=$(extract_wrapper_secrets_env "$wrapper")
      if [[ -z "$secrets_assignment" ]]; then
        continue
      fi
      if resolve_wrapper_secrets_env_audit_path "$secrets_assignment"; then
        secrets_file=$WRAPPER_SECRETS_ENV_AUDIT_PATH
        home_resolution_note=${WRAPPER_SECRETS_ENV_HOME_NOTE:-}
        if ! check_secrets_env_file "$workspace" "$secrets_file" "$wrapper" "$home_resolution_note"; then
          failures=1
        fi
      else
        wrapper_rel=$(print_relative "$workspace" "$wrapper")
        home_resolution_note=${WRAPPER_SECRETS_ENV_HOME_NOTE:-}
        printf 'warning: cron wrapper %s SECRETS_ENV unauditable - manual check required: SECRETS_ENV=%s%s\n' \
          "$wrapper_rel" "$secrets_assignment" "$home_resolution_note" >&2
        unauditable_count=$((unauditable_count + 1))
      fi
    fi
  done < <(find "$scripts_dir" -type f -print)

  if (( unauditable_count > 0 )); then
    printf 'warning: cron wrapper SECRETS_ENV unauditable count: %s\n' "$unauditable_count" >&2
  fi

  return "$failures"
}

check_instruction_files() {
  local workspace=$1
  local max_lines=${INSTRUCTION_FILE_MAX_LINES:-200}
  local instruction_file
  local marker_count
  local marker_file_count=0
  local marker_total=0
  local line_count
  local is_instruction
  local instruction_name

  case "$max_lines" in
    ''|*[!0-9]*|0)
      max_lines=200
      ;;
  esac

  while IFS= read -r instruction_file; do
    [[ -n "$instruction_file" ]] || continue
    if [[ ! -r "$instruction_file" ]]; then
      printf 'warning: instruction lint: file is not readable: %s\n' \
        "$(print_relative "$workspace" "$instruction_file")" >&2
      continue
    fi

    marker_count=$(
      awk -v legacy="$legacy_marker_line" -v current="$current_marker_line" \
        '$0 == legacy || $0 == current {count++} END {print count + 0}' \
        "$instruction_file" 2>/dev/null || true
    )
    instruction_name=$(basename "$instruction_file")
    is_instruction=0
    case "$instruction_name" in
      AGENTS.md|CLAUDE.md|GEMINI.md|SYSTEM.md|SOUL.md|IDENTITY.md|USER.md|TOOLS.md|MEMORY.md|HEARTBEAT.md|*.instructions.md|.cursorrules)
        is_instruction=1
        ;;
    esac
    if (( is_instruction == 0 && marker_count == 0 )); then
      continue
    fi

    if (( marker_count > 0 )); then
      marker_file_count=$((marker_file_count + 1))
      marker_total=$((marker_total + marker_count))
    fi
    if (( marker_count > 1 )); then
      printf 'warning: instruction lint: duplicate bootstrap marker (%s copies): %s\n' \
        "$marker_count" "$(print_relative "$workspace" "$instruction_file")" >&2
    fi

    if ! line_count=$(awk 'END {print NR + 0}' "$instruction_file" 2>/dev/null); then
      printf 'warning: instruction lint: file could not be counted: %s\n' \
        "$(print_relative "$workspace" "$instruction_file")" >&2
      continue
    fi
    if (( line_count > max_lines )); then
      printf 'warning: instruction lint: file exceeds %s lines (%s): %s\n' \
        "$max_lines" "$line_count" "$(print_relative "$workspace" "$instruction_file")" >&2
    fi
  done < <(
    find "$workspace" \( -type f -o -type l \) \( -name '*.md' -o -name '.cursorrules' \) -print
  )

  if (( marker_total > 1 && marker_file_count > 1 )); then
    printf 'warning: instruction lint: duplicate bootstrap marker across %s instruction files (%s copies total)\n' \
      "$marker_file_count" "$marker_total" >&2
  fi
}

check_raw_review() {
  local workspace=$1
  local conf="$workspace/loop/review.conf"
  local promotions="$workspace/loop/promotions"
  local notify="$workspace/loop/notify"
  local wired=0
  local producer_set=0
  local reviewer_set=0
  local config_invalid=0
  local threshold=14
  local streak=0
  local newest_ts=
  local newest_epoch=
  local now_epoch
  local configured_threshold
  local config_line config_value carriage_return
  local -a config_argv

  if [[ -f "$conf" && ! -L "$conf" ]]; then
    carriage_return=$(printf '\r')
    while IFS= read -r config_line || [[ -n "$config_line" ]]; do
      config_line=${config_line%"$carriage_return"}
      config_line=${config_line#"${config_line%%[![:space:]]*}"}
      case "$config_line" in
        ''|'#'*) ;;
        producer=*)
          config_value=${config_line#producer=}
          [[ -n "$config_value" ]] && producer_set=1 || config_invalid=1
          ;;
        reviewer[[:space:]]*)
          read -r -a config_argv <<<"$config_line" || config_invalid=1
          if (( ${#config_argv[@]} >= 3 )); then
            reviewer_set=1
          else
            config_invalid=1
          fi
          ;;
        notify_cmd=*) ;;
        review_window_weeks=*|reviewer_timeout_s=*|fabricated_floor=*|prompt_max_bytes=*)
          config_value=${config_line#*=}
          case "$config_value" in ''|*[!0-9]*|0) config_invalid=1 ;; esac
          ;;
        zero_streak_threshold=*)
          configured_threshold=${config_line#zero_streak_threshold=}
          case "$configured_threshold" in
            ''|*[!0-9]*|0) config_invalid=1 ;;
            *) threshold=$configured_threshold ;;
          esac
          ;;
        *) config_invalid=1 ;;
      esac
    done <"$conf"
    if [[ "$producer_set" -eq 1 && "$reviewer_set" -eq 1 && "$config_invalid" -eq 0 ]]; then
      wired=1
    elif [[ "$config_invalid" -ne 0 || "$producer_set" -ne "$reviewer_set" ]]; then
      printf 'warning: review-config: loop/review.conf requires producer and reviewer wiring\n' >&2
    fi
  fi

  if [[ "$wired" -ne 1 && "$config_invalid" -eq 0 \
    && "$producer_set" -eq 0 && "$reviewer_set" -eq 0 ]]; then
    printf 'info: review not wired; loop/promotions/ is not required yet\n'
  fi

  if [[ -d "$notify" ]] && find "$notify" -maxdepth 1 -type f -name 'review-*.md' -print | grep -q .; then
    printf 'warning: review-notify-unread: review notification files require operator consumption\n' >&2
  fi

  if [[ "$wired" -eq 1 ]]; then
    if [[ -f "$promotions/runs.log" ]]; then
      newest_ts=$(sed -n 's/^ts=\([^[:space:]]*\).*/\1/p' "$promotions/runs.log" | LC_ALL=C sort | tail -n 1)
    fi
    if [[ -z "$newest_ts" ]]; then
      printf 'warning: review-silent: wired review has no run receipt\n' >&2
    else
      newest_epoch=$(python3 -B - "$newest_ts" <<'PY' 2>/dev/null
import datetime
import sys
try:
    value = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    raise SystemExit(1)
print(int(value.replace(tzinfo=datetime.timezone.utc).timestamp()))
PY
)
      now_epoch=$(date '+%s')
      if [[ -z "$newest_epoch" || $((now_epoch - newest_epoch)) -gt 172800 ]]; then
        printf 'warning: review-silent: newest review receipt is older than 48 hours\n' >&2
      fi
    fi
  fi

  if [[ -f "$promotions/.zero-streak" ]]; then
    streak=$(sed -n '1p' "$promotions/.zero-streak")
    case "$streak" in ''|*[!0-9]*) streak=0 ;; esac
    if (( streak >= threshold )); then
      printf 'warning: review-zero-streak: %s consecutive eligible zero-candidate runs (threshold %s)\n' "$streak" "$threshold" >&2
    fi
  fi
}

probe_readable_contains() {
  local path=$1
  local expected=$2

  [[ -f "$path" && -r "$path" ]] && grep -Fq -- "$expected" "$path"
}

probe_executable_contains() {
  local path=$1
  local expected=$2

  [[ -f "$path" && -x "$path" ]] && grep -Fq -- "$expected" "$path"
}

print_learning_path() {
  local adapter=$1
  local route=$2
  local status=$3

  printf 'learning path: adapter=%s | route=%s | %s\n' "$adapter" "$route" "$status"
}

print_learning_path_result() {
  local adapter=$1
  local route=$2
  shift 2

  if "$@"; then
    print_learning_path "$adapter" "$route" PASS
  else
    print_learning_path "$adapter" "$route" FAIL
  fi
}

probe_claude_consult() {
  probe_readable_contains "$repo_root/adapters/claude-code/TASK-PACKET-staff.md" \
    '--append-bootstrap' \
    && probe_readable_contains "$repo_root/adapters/claude-code/TASK-PACKET-staff.md" \
      'CLAUDE.md' \
    && probe_readable_contains "$repo_root/adapters/claude-code/bootstrap-block.md" \
      'CONSULT at task start:'
}

probe_adapter_consult() {
  local adapter=$1

  probe_readable_contains "$repo_root/adapters/$adapter/bootstrap-block.md" \
    'CONSULT at task start:'
}

probe_adapter_candidate_generation() {
  local adapter=$1

  case "$adapter" in
    claude-code)
      probe_executable_contains "$repo_root/adapters/claude-code/precompact-flush-hook.sh" \
        "pending_file=\"\$cwd/loop/pending/flush-" \
        && probe_executable_contains "$repo_root/adapters/claude-code/precompact-flush-hook.sh" \
          ">>\"\$pending_file\""
      ;;
    codex|kimi)
      probe_executable_contains "$repo_root/adapters/$adapter/checkpoint-stop-hook.sh" \
        "flush_file=\"\$cwd/loop/pending/flush-" \
        && probe_executable_contains "$repo_root/adapters/$adapter/checkpoint-stop-hook.sh" \
          'Also append only genuinely NEW'
      ;;
    hermes)
      probe_executable_contains "$repo_root/adapters/hermes/stale-claim-watchdog.sh" \
        "pending_file=\"\$pending_dir/watchdog-" \
        && probe_executable_contains "$repo_root/adapters/hermes/stale-claim-watchdog.sh" \
          ">>\"\$pending_file\""
      ;;
    openclaw)
      probe_executable_contains "$repo_root/adapters/openclaw/distill-audit.sh" \
        "reply_file=\"\$pending_dir/distill-" \
      && probe_executable_contains "$repo_root/adapters/openclaw/distill-audit.sh" \
          "atomic_write_file \"\$annotated_reply_file\" \"\$reply_file\""
      ;;
    *)
      return 1
      ;;
  esac
}

probe_adapter_verifier() {
  local adapter=$1

  probe_executable_contains "$repo_root/adapters/$adapter/verify-job.sh" \
    "verifier_cmd=\${VERIFIER_CMD:-"
}

probe_adapter_distiller_cron() {
  local adapter=$1

  case "$adapter" in
    claude-code|codex|kimi)
      # shellcheck disable=SC2016
      probe_executable_contains "$repo_root/adapters/claude-code/flush-intake.sh" \
        'source "$repo_root/scripts/flush-intake.sh"' \
        && grep -Fq -- "snapshot_pending_dedup_keys \"\$pending_dir\"" \
          "$repo_root/scripts/flush-intake.sh" \
        && grep -Fq -- "atomic_write_file \"\$ledger_source\" \"\$ledger_file\"" \
          "$repo_root/scripts/flush-intake.sh" \
        && probe_executable_contains "$repo_root/templates/cron-wrapper.tmpl.sh" \
          '# fable-loop cron wrapper template v1'
      ;;
    *)
      probe_executable_contains "$repo_root/adapters/$adapter/distill-audit.sh" \
        "distiller_cmd=\${DISTILLER_CMD:-" \
        && probe_executable_contains "$repo_root/templates/cron-wrapper.tmpl.sh" \
          '# fable-loop cron wrapper template v1'
      ;;
  esac
}

probe_adapter_conformance() {
  local route=$1
  local env_name=$2
  local cmd=${!env_name-}

  [[ -n "$cmd" ]] || return 1
  wrapper_conformance_readonly "$route" "$env_name" "$cmd"
}

check_learning_paths() {
  local adapter

  # Capability probes are read-only and diagnostic: they inspect configured
  # adapter paths. Conformance probes read and hash configured wrapper, provider,
  # and probe paths, including env-supplied external ones. They never execute a
  # model or mutate the checked workspace. FAIL does not change --check semantics.
  for adapter in claude-code codex hermes kimi openclaw; do
    if [[ "$adapter" == "claude-code" ]]; then
      print_learning_path_result "$adapter" "CONSULT injection" probe_claude_consult
    else
      print_learning_path_result "$adapter" "CONSULT injection" \
        probe_adapter_consult "$adapter"
    fi
    print_learning_path_result "$adapter" "candidate generation" \
      probe_adapter_candidate_generation "$adapter"
    print_learning_path_result "$adapter" "verifier available" \
      probe_adapter_verifier "$adapter"
    print_learning_path_result "$adapter" "distiller cron" \
      probe_adapter_distiller_cron "$adapter"
  done
  print_learning_path_result hermes "verifier conformance" \
    probe_adapter_conformance verifier VERIFIER_CMD
  print_learning_path_result openclaw "distiller conformance" \
    probe_adapter_conformance distiller DISTILLER_CMD
}

check_workspace() {
  local workspace=$1
  local failures=0
  local pause_state
  local bootstrap_state
  local public_state
  local state_file="$workspace/STATE.md"
  local verify_file="$workspace/loop/VERIFY.log.md"
  local pending_dir="$workspace/loop/pending"
  local staging_dir="$workspace/skills/_staging"
  local expected_headers
  local missing_headers
  local header

  if workspace=$(caty_pause_canonical_workspace "$workspace"); then
    pause_state=$(caty_pause_workspace_state "$workspace")
  else
    pause_state=indeterminate
    failures=1
  fi
  bootstrap_state=$(bootstrap_state_for_workspace "$workspace")
  public_state=enabled
  if [[ "$pause_state" == paused ]]; then
    case "$bootstrap_state" in
      current) public_state=paused ;;
      legacy) public_state=paused-partial-legacy-bootstrap ;;
      unknown) public_state=paused-soft-unknown ;;
    esac
  elif [[ "$pause_state" == indeterminate ]]; then
    public_state=paused-soft-unknown
    printf 'warning: pause state is indeterminate; automated paths will perform no work\n' >&2
    failures=1
  fi
  if [[ "$pause_state" == paused && "$bootstrap_state" == unknown ]]; then
    printf 'warning: pause-aware bootstrap coverage is unknown; interactive model instructions may still run\n' >&2
  fi

  printf 'state=%s\n' "$public_state"
  printf 'bootstrap_state=%s\n' "$bootstrap_state"
  printf 'check: workspace %s\n' "$workspace"

  if [[ ! -f "$workspace/STATE.md" ]]; then
    printf 'missing path: STATE.md\n'
    failures=1
  fi
  if [[ ! -d "$workspace/skills" ]]; then
    printf 'missing path: skills/\n'
    failures=1
  fi
  if [[ ! -d "$workspace/skills/_staging" ]]; then
    printf 'missing path: skills/_staging/\n'
    failures=1
  fi
  if [[ ! -d "$workspace/loop" ]]; then
    printf 'missing path: loop/\n'
    failures=1
  fi
  if [[ ! -f "$workspace/loop/RUBRIC.tmpl.md" ]]; then
    printf 'missing path: loop/RUBRIC.tmpl.md\n'
    failures=1
  fi
  if [[ ! -d "$workspace/loop/pending" ]]; then
    printf 'missing path: loop/pending/\n'
    failures=1
  fi
  if [[ ! -d "$workspace/loop/artifacts" ]]; then
    printf 'missing path: loop/artifacts/\n'
    failures=1
  fi
  if [[ ! -d "$workspace/loop/archive" ]]; then
    printf 'missing path: loop/archive/\n'
    failures=1
  fi
  if [[ ! -d "$workspace/loop/handoffs" ]]; then
    printf 'missing path: loop/handoffs/\n'
    failures=1
  fi
  if [[ ! -f "$workspace/loop/VERIFY.log.md" ]]; then
    printf 'missing path: loop/VERIFY.log.md\n'
    failures=1
  fi

  expected_headers='## Verified facts
## General rules
## Open failures
## Lessons learned
## Last session'

  if [[ -f "$state_file" ]]; then
    missing_headers=$(
      awk '
        BEGIN {
          expected[1] = "## Verified facts"
          expected[2] = "## General rules"
          expected[3] = "## Open failures"
          expected[4] = "## Lessons learned"
          expected[5] = "## Last session"
          next_expected = 1
        }
        {
          if (next_expected <= 5 && index($0, expected[next_expected]) == 1) {
            next_expected++
          }
        }
        END {
          for (i = next_expected; i <= 5; i++) {
            print expected[i]
          }
        }
      ' "$state_file"
    )
  else
    missing_headers=$expected_headers
  fi

  if [[ -n "$missing_headers" ]]; then
    while IFS= read -r header; do
      [[ -n "$header" ]] || continue
      printf 'missing header: %s\n' "$header"
    done <<EOF
$missing_headers
EOF
    failures=1
  fi

  if [[ -f "$state_file" ]]; then
    local last_session_entries
    local last_session_lines
    local last_session_pointer
    last_session_entries=$(awk '
      index($0, "## Last session") == 1 {in_section = 1; next}
      in_section && /^## / {exit}
      in_section && (/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / || /^- task id:/) {entries++}
      END {print entries + 0}
    ' "$state_file")
    last_session_lines=$(awk '
      index($0, "## Last session") == 1 {in_section = 1; next}
      in_section && /^## / {exit}
      in_section {lines++}
      END {print lines + 0}
    ' "$state_file")
    if [[ "$last_session_entries" -gt 20 ]]; then
      printf 'warning: last-session-entries: %s entries exceeds cap 20\n' "$last_session_entries" >&2
    fi
    if [[ "$last_session_lines" -gt 60 ]]; then
      printf 'warning: last-session-lines: %s physical lines exceeds cap 60\n' "$last_session_lines" >&2
    fi
    if awk '
      index($0, "## Last session") == 1 {in_section = 1; next}
      in_section && /^## / {exit}
      in_section && /^- task id:/ {found = 1}
      END {exit found ? 0 : 1}
    ' "$state_file"; then
      printf 'warning: last-session-grammar: legacy task-id boundary remains after migration\n' >&2
    fi
    while IFS= read -r last_session_pointer; do
      [[ -n "$last_session_pointer" ]] || continue
      if ! last_session_pointer_is_usable "$workspace" "$last_session_pointer"; then
        printf 'warning: last-session-pointer: handoff target is missing: %s\n' "$last_session_pointer" >&2
      fi
    done < <(
      awk '
        index($0, "## Last session") == 1 {in_section = 1; next}
        in_section && /^## / {exit}
        in_section && (/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / || /^- task id:/) {print}
      ' "$state_file" | sed -n 's/.*handoff:[[:space:]]*\([^ |]*\).*/\1/p'
    )
  fi

  if [[ -f "$state_file" && -f "$verify_file" ]]; then
    local last_dates
    local newest_date
    local stale_found=0

    last_dates=$(extract_last_session_dates "$state_file")
    newest_date=$(newest_verify_date "$verify_file")

    if [[ -z "$last_dates" || -z "$newest_date" ]]; then
      printf 'warning: dates could not be found/compared for Last session and loop/VERIFY.log.md\n' >&2
    else
      local date_value
      for date_value in $last_dates; do
        if [[ "$date_value" < "$newest_date" ]]; then
          printf 'warning: Last session date %s is older than newest VERIFY.log.md date %s\n' "$date_value" "$newest_date" >&2
          stale_found=1
        elif [[ "$date_value" = "$newest_date" ]]; then
          if ! awk '
            index($0, "## Last session") == 1 {in_section = 1; next}
            in_section && /^## / {exit}
            in_section && (/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / || /^- task id:/) {
              if (saw_entry) exit
              saw_entry = 1
            }
            in_section && saw_entry && /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/ {found = 1}
            END {exit found ? 0 : 1}
          ' "$state_file"; then
            printf 'warning: Last session date %s has date-only granularity and loop/VERIFY.log.md has same-day entries; cannot prove fresh\n' "$date_value" >&2
          fi
        fi
      done
      if [[ "$stale_found" -eq 0 ]]; then
        printf 'ok: Last session dates are not older than newest VERIFY.log.md date %s\n' "$newest_date"
      fi
    fi
  else
    printf 'warning: dates could not be found/compared for Last session and loop/VERIFY.log.md\n' >&2
  fi

  if [[ -d "$pending_dir" ]]; then
    while IFS= read -r old_pending; do
      [[ -n "$old_pending" ]] || continue
      printf 'warning: pending file older than 7 days: %s\n' "$(print_relative "$workspace" "$old_pending")" >&2
    done < <(find "$pending_dir" -type f -mtime +7 -print)
  fi

  if [[ -e "$workspace/loop/.distill-last-run" \
    && -e "$workspace/loop/pending/intake-runs.log" ]]; then
    printf 'conflicting fold route evidence: openclaw distill and flush intake have both run\n'
    failures=1
  fi

  if [[ -d "$staging_dir" ]]; then
    while IFS= read -r draft_file; do
      [[ -n "$draft_file" ]] || continue
      if grep -q '^[[:space:]]*status:[[:space:]]*draft[[:space:]]*$' "$draft_file"; then
        printf 'warning: draft older than 14 days: %s\n' "$(print_relative "$workspace" "$draft_file")" >&2
      fi
    done < <(find "$staging_dir" -type f -mtime +14 -print)
  fi

  # Skill lint warnings do not affect --check exit semantics. The loader budget is
  # adapter-specific, so callers may tune it with SKILL_DESC_MAX (default: 200).
  local skill_desc_max=${SKILL_DESC_MAX:-200}
  local skill_file rel_path description description_bytes key key_value status_value
  while IFS= read -r skill_file; do
    [[ -n "$skill_file" ]] || continue
    rel_path=$(print_relative "$workspace" "$skill_file")
    description=$(awk '
      $0 == "---" {markers++; next}
      markers == 1 && /^description:[[:space:]]*/ {
        sub(/^description:[[:space:]]*/, "")
        print
        exit
      }
      markers >= 2 {exit}
    ' "$skill_file")
    if [[ -z "$description" ]]; then
      printf 'warning: skill lint: missing description: %s\n' "$rel_path" >&2
    else
      description_bytes=$(printf '%s' "$description" | wc -c | tr -d '[:space:]')
      if (( description_bytes > skill_desc_max )); then
        printf 'warning: skill lint: description exceeds %s bytes: %s\n' "$skill_desc_max" "$rel_path" >&2
      fi
    fi
    if ! grep -q '^## Verification[[:space:]]*$' "$skill_file"; then
      printf 'warning: skill lint: missing ## Verification section: %s\n' "$rel_path" >&2
    fi
    status_value=
    for key in name trigger status verified_at verifier_id; do
      key_value=$(awk -v key="$key" '
        $0 == "---" {markers++; next}
        markers == 1 && $0 ~ ("^" key ":[[:space:]]*") {
          sub("^" key ":[[:space:]]*", "")
          print
          exit
        }
        markers >= 2 {exit}
      ' "$skill_file")
      if [[ "$key" == status ]]; then
        status_value=$key_value
        status_value=$(printf '%s' "$status_value" | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
      fi
      if [[ "$key" == verified_at || "$key" == verifier_id ]]; then
        if [[ "$status_value" == verified && -z "$key_value" ]]; then
          printf 'warning: skill lint: missing %s for status verified: %s\n' "$key" "$rel_path" >&2
        fi
      elif [[ -z "$key_value" ]]; then
        printf 'warning: skill lint: missing %s: %s\n' "$key" "$rel_path" >&2
      fi
    done
  done < <(find "$workspace/skills" -type f -name 'SKILL.md' -print 2>/dev/null)

  if ! check_cron_wrappers "$workspace"; then
    failures=1
  fi
  check_instruction_files "$workspace"
  check_raw_review "$workspace"
  check_learning_paths

  if [[ -d "$workspace/loop/tasks/queue" ]]; then
    local queued_task
    queued_task=$(find "$workspace/loop/tasks/queue" -maxdepth 1 -type f -name '*.task.md' -print | head -n 1)
    if [[ -n "$queued_task" ]]; then
      local newest_tick_mtime
      newest_tick_mtime=''
      if [[ -d "$workspace/loop/artifacts" ]]; then
        newest_tick_mtime=$(
          find "$workspace/loop/artifacts" -type f \( -name 'state.json' -o -name 'PROGRESS.md' \) -exec sh -c '
            for path do
              mtime=$(stat -c "%Y" "$path" 2>/dev/null || stat -f "%m" "$path")
              printf "%s\n" "$mtime"
            done
          ' sh {} + | sort -n | tail -n 1
        )
      fi
      if [[ -z "$newest_tick_mtime" ]]; then
        printf 'warning: task-runner queue non-empty but no tick evidence found\n' >&2
      else
        local now_epoch
        now_epoch=$(date '+%s')
        if (( newest_tick_mtime < now_epoch - 1800 )); then
          printf 'warning: task-runner queue non-empty but last tick evidence is older than 30 minutes\n' >&2
        fi
      fi
    fi
  fi

  # Scope-mismatch checkpoint detection (Issue #7): a Last session referencing a
  # RELATIVE path that does not exist in this workspace but does exist in a sibling
  # directory usually means the checkpoint was written into the wrong STATE.md.
  # Absolute paths, ~ paths, and URLs are legitimate host references and are skipped
  # (Some agents' STATE.md legitimately points at that agent's own remote home directory).
  if [[ -f "$state_file" ]]; then
    local token
    local ws_base
    ws_base=$(basename "$workspace")
    while IFS= read -r token; do
      [[ -n "$token" ]] || continue
      case "$token" in
        *://*|/*|"~"*) continue ;;
        "$ws_base"/*) continue ;;
      esac
      if [[ ! -e "$workspace/$token" && -e "$workspace/../$token" ]]; then
        printf 'warning: Last session references sibling-project path: %s — this checkpoint may belong to another workspace STATE.md\n' "$token" >&2
      fi
    done < <(
      awk '
        function is_boundary(value) {
          return value ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / \
            || value ~ /^- task id:/
        }
        index($0, "## Last session") == 1 {in_section = 1; next}
        in_section && /^## / {exit}
        in_section && is_boundary($0) {
          entries++
          if (entries > 1) exit
        }
        in_section && entries == 1 {print}
      ' "$state_file" | grep -Eo '[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+' | sort -u | head -20
    )
  fi

  if [[ "$failures" -ne 0 ]]; then
    return 1
  fi

  printf 'ok: required layout and STATE.md headers present\n'
  return 0
}

workspace=$PWD
runtime=generic
hermes_profile=
append_file=
bootstrap_runtime=
check_mode=0
workspace_explicit=0
pause_mode=
dry_run=0

while (($# > 0)); do
  case "$1" in
    --workspace)
      (($# >= 2)) || die_usage 'missing argument for --workspace'
      workspace=$2
      workspace_explicit=1
      shift 2
      ;;
    --hermes)
      (($# >= 2)) || die_usage 'missing argument for --hermes'
      [[ "$runtime" == "generic" ]] || die_usage '--hermes cannot be combined with another runtime flag'
      hermes_profile=$2
      runtime=hermes
      shift 2
      ;;
    --openclaw)
      (($# >= 2)) || die_usage 'missing argument for --openclaw'
      [[ "$runtime" == "generic" ]] || die_usage '--openclaw cannot be combined with another runtime flag'
      workspace=$2
      runtime=openclaw
      shift 2
      ;;
    --append-bootstrap)
      (($# >= 2)) || die_usage 'missing argument for --append-bootstrap'
      append_file=$2
      shift 2
      ;;
    --bootstrap-runtime)
      (($# >= 2)) || die_usage 'missing argument for --bootstrap-runtime'
      bootstrap_runtime=$2
      case "$bootstrap_runtime" in
        claude-code|codex|kimi|hermes|openclaw) ;;
        *) die_usage "invalid --bootstrap-runtime value: $bootstrap_runtime" ;;
      esac
      shift 2
      ;;
    --check)
      check_mode=1
      shift
      ;;
    --disable)
      [[ -z "$pause_mode" ]] || die_usage '--disable conflicts with an existing pause-mode flag'
      pause_mode=disable
      shift
      ;;
    --enable)
      [[ -z "$pause_mode" ]] || die_usage '--enable conflicts with an existing pause-mode flag'
      pause_mode=enable
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

if ! caty_pause_value_is_record_safe "$workspace"; then
  printf 'invalid workspace path\n' >&2
  exit 2
fi

if [[ -n "$pause_mode" ]]; then
  [[ "$check_mode" -eq 0 && "$runtime" == "generic" && -z "$append_file" && -z "$bootstrap_runtime" && "$workspace_explicit" -eq 1 ]] || die_usage '--enable/--disable requires --workspace and forbids --check/runtime/bootstrap flags'
  pause_workspace "$pause_mode" "$workspace" "$dry_run"
  exit $?
fi

[[ "$dry_run" -eq 0 ]] || die_usage '--dry-run requires --enable or --disable'
[[ -z "$bootstrap_runtime" || -n "$append_file" ]] || die_usage '--bootstrap-runtime requires --append-bootstrap'

if [[ "$check_mode" -eq 1 ]]; then
  [[ "$runtime" == "generic" && -z "$append_file" && -z "$bootstrap_runtime" ]] || die_usage '--check cannot be combined with runtime or bootstrap flags'
  check_workspace "$workspace"
  exit $?
fi

if [[ "$runtime" == "hermes" ]]; then
  [[ "$workspace_explicit" -eq 0 ]] || die_usage '--hermes does not accept --workspace'
  workspace="$HOME/.hermes/profiles/$hermes_profile/workspace"
fi

if [[ "$runtime" != "generic" || "$workspace_explicit" -eq 1 || -z "$append_file" ]]; then
  run_loop_init "$workspace"
fi

if [[ -n "$append_file" ]]; then
  if ! append_file=$(canonical_append_target "$append_file"); then
    printf 'append target must be an absolute path with an existing real parent: %s\n' "$append_file" >&2
    exit 2
  fi
  selected_bootstrap_runtime=${bootstrap_runtime:-$runtime}
  append_bootstrap "$append_file" "$(block_file_for_mode "$selected_bootstrap_runtime")"
  if workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null); then
    register_instruction_file "$workspace" "$append_file"
  fi
fi

case "$runtime" in
  hermes)
    print_hermes_next_steps
    ;;
  openclaw)
    print_openclaw_next_steps "$workspace"
    ;;
  generic)
    ;;
esac
