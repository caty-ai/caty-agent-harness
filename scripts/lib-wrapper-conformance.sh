#!/usr/bin/env bash

# This file is a sourced library. Public result globals are consumed by callers, and
# WCF_* fields are populated dynamically by wrapper_conformance_set_field.
# shellcheck disable=SC2034,SC2154

WRAPPER_CONFORMANCE_MAX_TTL_S=604800
WRAPPER_CONFORMANCE_MAX_RECORDS=32
WRAPPER_CONFORMANCE_MAX_BYTES=4096
WRAPPER_CONFORMANCE_REASON=
WRAPPER_CONFORMANCE_WRAPPER_PATH=
WRAPPER_CONFORMANCE_EVIDENCE_PATH=
WRAPPER_CONFORMANCE_STAGE_DIR=
WRAPPER_CONFORMANCE_STAGED_PATH=
WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH=
WRAPPER_CONFORMANCE_PROVIDER_PATH=
WRAPPER_CONFORMANCE_PROVIDER_ID=
WRAPPER_CONFORMANCE_PROVIDER_VERSION=
WRAPPER_CONFORMANCE_PROBE_PATH=
WRAPPER_CONFORMANCE_CHECKED_AT=
WRAPPER_CONFORMANCE_EXPIRES_AT=

wrapper_conformance_reset() {
  WRAPPER_CONFORMANCE_REASON=
  WRAPPER_CONFORMANCE_WRAPPER_PATH=
  WRAPPER_CONFORMANCE_EVIDENCE_PATH=
  WRAPPER_CONFORMANCE_STAGE_DIR=
  WRAPPER_CONFORMANCE_STAGED_PATH=
  WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH=
  WRAPPER_CONFORMANCE_PROVIDER_PATH=
  WRAPPER_CONFORMANCE_PROVIDER_ID=
  WRAPPER_CONFORMANCE_PROVIDER_VERSION=
  WRAPPER_CONFORMANCE_PROBE_PATH=
  WRAPPER_CONFORMANCE_CHECKED_AT=
  WRAPPER_CONFORMANCE_EXPIRES_AT=
}

wrapper_conformance_fail() {
  WRAPPER_CONFORMANCE_REASON=$1
  return 1
}

wrapper_conformance_sha256_file() {
  local path=$1
  local output
  local digest

  if command -v sha256sum >/dev/null 2>&1; then
    output=$(sha256sum "$path") || return 1
  elif command -v shasum >/dev/null 2>&1; then
    output=$(shasum -a 256 "$path") || return 1
  else
    return 1
  fi
  digest=${output%%[[:space:]]*}
  [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s\n' "$digest" | tr 'A-F' 'a-f'
}

wrapper_conformance_now_epoch() {
  date '+%s'
}

wrapper_conformance_validate_path_value() {
  local field_name=$1
  local path=$2

  if [[ ! "$path" =~ ^/[-+./0-9:@A-Z_a-z]+$ ]]; then
    wrapper_conformance_fail "$field_name must be an absolute path using the v1 path alphabet"
    return 1
  fi
}

wrapper_conformance_validate_hex64() {
  local field_name=$1
  local value=$2

  if [[ ! "$value" =~ ^[0-9a-f]{64}$ ]]; then
    wrapper_conformance_fail "$field_name must be 64 lowercase hex characters"
    return 1
  fi
}

wrapper_conformance_validate_provider_id() {
  local value=$1

  if [[ ! "$value" =~ ^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$ ]]; then
    wrapper_conformance_fail "provider_id must use the bounded token alphabet"
    return 1
  fi
}

wrapper_conformance_validate_provider_version() {
  local value=$1

  if [[ ! "$value" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]]; then
    wrapper_conformance_fail "provider_version must use the bounded label alphabet"
    return 1
  fi
}

wrapper_conformance_validate_trusted_file_mode() {
  local field_name=$1
  local path=$2
  local stat_output
  local owner_id
  local mode
  local current_uid

  stat_output=$(stat -c '%u %a' "$path" 2>/dev/null || stat -f '%u %Lp' "$path" 2>/dev/null) || {
    wrapper_conformance_fail "$field_name ownership and mode could not be inspected: $path"
    return 1
  }
  owner_id=${stat_output%% *}
  mode=${stat_output#* }
  current_uid=$(id -u)
  if [[ ! "$owner_id" =~ ^[0-9]+$ || ( "$owner_id" != "$current_uid" && "$owner_id" != 0 ) ]]; then
    wrapper_conformance_fail "$field_name must be owned by the invoking uid or root: $path"
    return 1
  fi
  if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
    wrapper_conformance_fail "$field_name mode is invalid: $path"
    return 1
  fi
  if (( (8#$mode & 8#022) != 0 )); then
    wrapper_conformance_fail "$field_name must not be group- or world-writable: $path"
    return 1
  fi
}

wrapper_conformance_validate_executable() {
  local field_name=$1
  local path=$2

  wrapper_conformance_validate_path_value "$field_name" "$path" || return 1
  if [[ ! -e "$path" ]]; then
    wrapper_conformance_fail "$field_name not found: $path"
    return 1
  fi
  if [[ ! -f "$path" || -L "$path" ]]; then
    wrapper_conformance_fail "$field_name must be a regular file: $path"
    return 1
  fi
  if [[ ! -x "$path" ]]; then
    wrapper_conformance_fail "$field_name not executable: $path"
    return 1
  fi
  wrapper_conformance_validate_trusted_file_mode "$field_name" "$path" || return 1
}

wrapper_conformance_require_distinct_file_identity() {
  local first_name=$1
  local first_path=$2
  local second_name=$3
  local second_path=$4

  if [[ "$first_path" == "$second_path" || "$first_path" -ef "$second_path" ]]; then
    wrapper_conformance_fail "$first_name and $second_name must identify distinct files"
    return 1
  fi
}

wrapper_conformance_require_distinct_content() {
  local first_name=$1
  local first_sha=$2
  local second_name=$3
  local second_sha=$4

  if [[ "$first_sha" == "$second_sha" ]]; then
    wrapper_conformance_fail "$first_name and $second_name must have distinct content"
    return 1
  fi
}

wrapper_conformance_parse_cmd() {
  local env_name=$1
  local cmd=$2
  local evidence_path=${3:-}
  local argv

  wrapper_conformance_reset
  if [[ "$cmd" == *$'\n'* || "$cmd" == *$'\r'* ]]; then
    wrapper_conformance_fail "$env_name must be exactly one absolute wrapper path"
    return 1
  fi
  read -r -a argv <<<"$cmd"
  if ((${#argv[@]} == 0)); then
    wrapper_conformance_fail "$env_name is required"
    return 1
  fi
  if ((${#argv[@]} != 1)); then
    wrapper_conformance_fail "$env_name must be exactly one absolute wrapper path"
    return 1
  fi

  WRAPPER_CONFORMANCE_WRAPPER_PATH=${argv[0]}
  wrapper_conformance_validate_executable "$env_name" "$WRAPPER_CONFORMANCE_WRAPPER_PATH" || return 1

  if [[ -n "$evidence_path" ]]; then
    WRAPPER_CONFORMANCE_EVIDENCE_PATH=$evidence_path
  else
    WRAPPER_CONFORMANCE_EVIDENCE_PATH=${WRAPPER_CONFORMANCE_WRAPPER_PATH}.conformance
  fi
  wrapper_conformance_validate_path_value "evidence_path" "$WRAPPER_CONFORMANCE_EVIDENCE_PATH" || return 1
}

wrapper_conformance_set_field() {
  local key=$1
  local value=$2
  local variable_name=

  case "$key" in
    schema) variable_name=WCF_schema ;;
    route) variable_name=WCF_route ;;
    wrapper_path) variable_name=WCF_wrapper_path ;;
    wrapper_sha256) variable_name=WCF_wrapper_sha256 ;;
    provider_id) variable_name=WCF_provider_id ;;
    provider_version) variable_name=WCF_provider_version ;;
    provider_path) variable_name=WCF_provider_path ;;
    provider_sha256) variable_name=WCF_provider_sha256 ;;
    provider_launch) variable_name=WCF_provider_launch ;;
    provider_relocatable) variable_name=WCF_provider_relocatable ;;
    probe_path) variable_name=WCF_probe_path ;;
    probe_sha256) variable_name=WCF_probe_sha256 ;;
    checked_at_epoch) variable_name=WCF_checked_at_epoch ;;
    expires_at_epoch) variable_name=WCF_expires_at_epoch ;;
    fresh_session) variable_name=WCF_fresh_session ;;
    persistence_off) variable_name=WCF_persistence_off ;;
    input_mode) variable_name=WCF_input_mode ;;
    tool_requests) variable_name=WCF_tool_requests ;;
    action_requests) variable_name=WCF_action_requests ;;
    permission_requests) variable_name=WCF_permission_requests ;;
    workspace_access) variable_name=WCF_workspace_access ;;
    *)
      wrapper_conformance_fail "unknown evidence key: $key"
      return 1
      ;;
  esac

  if [[ -n "${!variable_name:-}" ]]; then
    wrapper_conformance_fail "duplicate evidence key: $key"
    return 1
  fi
  printf -v "$variable_name" '%s' "$value"
}

wrapper_conformance_require_field() {
  local key=$1
  local variable_name=$2

  if [[ -z "${!variable_name:-}" ]]; then
    wrapper_conformance_fail "missing evidence key: $key"
    return 1
  fi
}

wrapper_conformance_parse_record() {
  local evidence_path=$1
  local line
  local key
  local value
  local records=0
  local byte_count

  unset \
    WCF_schema WCF_route WCF_wrapper_path WCF_wrapper_sha256 \
    WCF_provider_id WCF_provider_version WCF_provider_path WCF_provider_sha256 \
    WCF_provider_launch WCF_provider_relocatable \
    WCF_probe_path WCF_probe_sha256 WCF_checked_at_epoch WCF_expires_at_epoch \
    WCF_fresh_session WCF_persistence_off WCF_input_mode WCF_tool_requests \
    WCF_action_requests WCF_permission_requests WCF_workspace_access

  if [[ ! -e "$evidence_path" ]]; then
    wrapper_conformance_fail "missing evidence: $evidence_path"
    return 1
  fi
  if [[ ! -f "$evidence_path" || -L "$evidence_path" ]]; then
    wrapper_conformance_fail "evidence must be a regular file: $evidence_path"
    return 1
  fi
  wrapper_conformance_validate_trusted_file_mode evidence "$evidence_path" || return 1
  byte_count=$(wc -c <"$evidence_path" 2>/dev/null || printf '0')
  byte_count=${byte_count//[[:space:]]/}
  if [[ ! "$byte_count" =~ ^[0-9]+$ ]]; then
    wrapper_conformance_fail "evidence size could not be measured: $evidence_path"
    return 1
  fi
  if (( byte_count > WRAPPER_CONFORMANCE_MAX_BYTES )); then
    wrapper_conformance_fail "evidence exceeds ${WRAPPER_CONFORMANCE_MAX_BYTES} bytes: $evidence_path"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    records=$((records + 1))
    if (( records > WRAPPER_CONFORMANCE_MAX_RECORDS )); then
      wrapper_conformance_fail "evidence exceeds ${WRAPPER_CONFORMANCE_MAX_RECORDS} records: $evidence_path"
      return 1
    fi
    if [[ "$line" != *=* ]]; then
      wrapper_conformance_fail "malformed evidence record: $line"
      return 1
    fi
    key=${line%%=*}
    value=${line#*=}
    if [[ -z "$key" || -z "$value" ]]; then
      wrapper_conformance_fail "malformed evidence record: $line"
      return 1
    fi
    wrapper_conformance_set_field "$key" "$value" || return 1
  done <"$evidence_path"

  wrapper_conformance_require_field schema WCF_schema || return 1
  wrapper_conformance_require_field route WCF_route || return 1
  wrapper_conformance_require_field wrapper_path WCF_wrapper_path || return 1
  wrapper_conformance_require_field wrapper_sha256 WCF_wrapper_sha256 || return 1
  wrapper_conformance_require_field provider_id WCF_provider_id || return 1
  wrapper_conformance_require_field provider_version WCF_provider_version || return 1
  wrapper_conformance_require_field provider_path WCF_provider_path || return 1
  wrapper_conformance_require_field provider_sha256 WCF_provider_sha256 || return 1
  wrapper_conformance_require_field provider_launch WCF_provider_launch || return 1
  wrapper_conformance_require_field provider_relocatable WCF_provider_relocatable || return 1
  wrapper_conformance_require_field probe_path WCF_probe_path || return 1
  wrapper_conformance_require_field probe_sha256 WCF_probe_sha256 || return 1
  wrapper_conformance_require_field checked_at_epoch WCF_checked_at_epoch || return 1
  wrapper_conformance_require_field expires_at_epoch WCF_expires_at_epoch || return 1
  wrapper_conformance_require_field fresh_session WCF_fresh_session || return 1
  wrapper_conformance_require_field persistence_off WCF_persistence_off || return 1
  wrapper_conformance_require_field input_mode WCF_input_mode || return 1
  wrapper_conformance_require_field tool_requests WCF_tool_requests || return 1
  wrapper_conformance_require_field action_requests WCF_action_requests || return 1
  wrapper_conformance_require_field permission_requests WCF_permission_requests || return 1
  wrapper_conformance_require_field workspace_access WCF_workspace_access || return 1
}

wrapper_conformance_validate_record() {
  local route=$1
  local wrapper_path=$2
  local wrapper_sha
  local provider_sha
  local probe_sha
  local now_epoch
  local checked_at
  local expires_at

  if [[ "$WCF_schema" != 'fable-wrapper-conformance/v1' ]]; then
    wrapper_conformance_fail "unsupported evidence schema: $WCF_schema"
    return 1
  fi
  if [[ "$WCF_route" != 'verifier' && "$WCF_route" != 'distiller' ]]; then
    wrapper_conformance_fail "route must be verifier or distiller"
    return 1
  fi
  if [[ "$WCF_route" != "$route" ]]; then
    wrapper_conformance_fail "route mismatch: expected $route, found $WCF_route"
    return 1
  fi
  if [[ "$WCF_wrapper_path" != "$wrapper_path" ]]; then
    wrapper_conformance_fail "wrapper path mismatch: expected $wrapper_path, found $WCF_wrapper_path"
    return 1
  fi

  wrapper_conformance_validate_path_value "wrapper_path" "$WCF_wrapper_path" || return 1
  wrapper_conformance_validate_hex64 wrapper_sha256 "$WCF_wrapper_sha256" || return 1
  wrapper_conformance_validate_provider_id "$WCF_provider_id" || return 1
  wrapper_conformance_validate_provider_version "$WCF_provider_version" || return 1
  wrapper_conformance_validate_executable provider_path "$WCF_provider_path" || return 1
  wrapper_conformance_validate_hex64 provider_sha256 "$WCF_provider_sha256" || return 1
  wrapper_conformance_validate_executable probe_path "$WCF_probe_path" || return 1
  wrapper_conformance_validate_hex64 probe_sha256 "$WCF_probe_sha256" || return 1
  wrapper_conformance_require_distinct_file_identity \
    wrapper_path "$WCF_wrapper_path" probe_path "$WCF_probe_path" || return 1
  wrapper_conformance_require_distinct_file_identity \
    wrapper_path "$WCF_wrapper_path" provider_path "$WCF_provider_path" || return 1
  wrapper_conformance_require_distinct_file_identity \
    probe_path "$WCF_probe_path" provider_path "$WCF_provider_path" || return 1

  if [[ ! "$WCF_checked_at_epoch" =~ ^(0|[1-9][0-9]{0,11})$ ]]; then
    wrapper_conformance_fail "checked_at_epoch must be a bounded unsigned integer"
    return 1
  fi
  if [[ ! "$WCF_expires_at_epoch" =~ ^(0|[1-9][0-9]{0,11})$ ]]; then
    wrapper_conformance_fail "expires_at_epoch must be a bounded unsigned integer"
    return 1
  fi
  checked_at=$((10#$WCF_checked_at_epoch))
  expires_at=$((10#$WCF_expires_at_epoch))
  if (( checked_at >= expires_at )); then
    wrapper_conformance_fail "expires_at_epoch must be later than checked_at_epoch"
    return 1
  fi
  if (( expires_at - checked_at > WRAPPER_CONFORMANCE_MAX_TTL_S )); then
    wrapper_conformance_fail "attestation TTL exceeds ${WRAPPER_CONFORMANCE_MAX_TTL_S} seconds"
    return 1
  fi
  now_epoch=$(wrapper_conformance_now_epoch) || return 1
  if [[ ! "$now_epoch" =~ ^[0-9]+$ ]]; then
    wrapper_conformance_fail "current epoch is invalid"
    return 1
  fi
  now_epoch=$((10#$now_epoch))
  if (( checked_at > now_epoch )); then
    wrapper_conformance_fail "future evidence is not accepted"
    return 1
  fi
  if (( expires_at <= now_epoch )); then
    wrapper_conformance_fail "stale evidence is not accepted"
    return 1
  fi

  if [[ "$WCF_fresh_session" != 'pass' ]]; then
    wrapper_conformance_fail "fresh_session must equal pass"
    return 1
  fi
  if [[ "$WCF_persistence_off" != 'pass' ]]; then
    wrapper_conformance_fail "persistence_off must equal pass"
    return 1
  fi
  if [[ "$WCF_input_mode" != 'host-inline' ]]; then
    wrapper_conformance_fail "input_mode must equal host-inline"
    return 1
  fi
  if [[ "$WCF_tool_requests" != 'auto-deny' ]]; then
    wrapper_conformance_fail "tool_requests must equal auto-deny"
    return 1
  fi
  if [[ "$WCF_action_requests" != 'auto-deny' ]]; then
    wrapper_conformance_fail "action_requests must equal auto-deny"
    return 1
  fi
  if [[ "$WCF_permission_requests" != 'auto-deny' ]]; then
    wrapper_conformance_fail "permission_requests must equal auto-deny"
    return 1
  fi
  if [[ "$WCF_workspace_access" != 'none' ]]; then
    wrapper_conformance_fail "workspace_access must equal none"
    return 1
  fi
  if [[ "$WCF_provider_launch" != 'host-staged-env' ]]; then
    wrapper_conformance_fail "provider_launch must equal host-staged-env"
    return 1
  fi
  if [[ "$WCF_provider_relocatable" != 'pass' ]]; then
    wrapper_conformance_fail "provider_relocatable must equal pass"
    return 1
  fi

  wrapper_sha=$(wrapper_conformance_sha256_file "$wrapper_path") || {
    wrapper_conformance_fail "sha256 tooling is required"
    return 1
  }
  if [[ "$wrapper_sha" != "$WCF_wrapper_sha256" ]]; then
    wrapper_conformance_fail "wrapper content hash mismatch"
    return 1
  fi

  provider_sha=$(wrapper_conformance_sha256_file "$WCF_provider_path") || {
    wrapper_conformance_fail "sha256 tooling is required"
    return 1
  }
  if [[ "$provider_sha" != "$WCF_provider_sha256" ]]; then
    wrapper_conformance_fail "provider content hash mismatch"
    return 1
  fi

  probe_sha=$(wrapper_conformance_sha256_file "$WCF_probe_path") || {
    wrapper_conformance_fail "sha256 tooling is required"
    return 1
  }
  if [[ "$probe_sha" != "$WCF_probe_sha256" ]]; then
    wrapper_conformance_fail "probe content hash mismatch"
    return 1
  fi
  wrapper_conformance_require_distinct_content \
    wrapper_path "$wrapper_sha" probe_path "$probe_sha" || return 1
  wrapper_conformance_require_distinct_content \
    wrapper_path "$wrapper_sha" provider_path "$provider_sha" || return 1
  wrapper_conformance_require_distinct_content \
    probe_path "$probe_sha" provider_path "$provider_sha" || return 1

  WRAPPER_CONFORMANCE_PROVIDER_PATH=$WCF_provider_path
  WRAPPER_CONFORMANCE_PROVIDER_ID=$WCF_provider_id
  WRAPPER_CONFORMANCE_PROVIDER_VERSION=$WCF_provider_version
  WRAPPER_CONFORMANCE_PROBE_PATH=$WCF_probe_path
  WRAPPER_CONFORMANCE_CHECKED_AT=$WCF_checked_at_epoch
  WRAPPER_CONFORMANCE_EXPIRES_AT=$WCF_expires_at_epoch
}

wrapper_conformance_check_record() {
  local route=$1
  local wrapper_path=$2
  local evidence_path=$3

  wrapper_conformance_parse_record "$evidence_path" || return 1
  wrapper_conformance_validate_record "$route" "$wrapper_path" || return 1
}

wrapper_conformance_stage_runtime() {
  local wrapper_path=$1
  local expected_wrapper_sha=$2
  local provider_path=$3
  local expected_provider_sha=$4
  local stage_dir
  local staged_path
  local staged_provider_path
  local staged_sha
  local staged_provider_sha

  stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/caty-wrapper-stage.XXXXXX") || {
    wrapper_conformance_fail "failed to create wrapper stage directory"
    return 1
  }
  chmod 700 "$stage_dir" || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "failed to secure wrapper stage directory"
    return 1
  }

  staged_path="$stage_dir/wrapper"
  staged_provider_path="$stage_dir/provider"
  cp "$wrapper_path" "$staged_path" || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "failed to stage wrapper copy"
    return 1
  }
  cp "$provider_path" "$staged_provider_path" || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "failed to stage provider copy"
    return 1
  }
  chmod 700 "$staged_path" || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "failed to secure staged wrapper copy"
    return 1
  }
  chmod 700 "$staged_provider_path" || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "failed to secure staged provider copy"
    return 1
  }
  staged_sha=$(wrapper_conformance_sha256_file "$staged_path") || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "sha256 tooling is required"
    return 1
  }
  if [[ "$staged_sha" != "$expected_wrapper_sha" ]]; then
    rm -rf "$stage_dir"
    wrapper_conformance_fail "staged wrapper content hash mismatch"
    return 1
  fi
  staged_provider_sha=$(wrapper_conformance_sha256_file "$staged_provider_path") || {
    rm -rf "$stage_dir"
    wrapper_conformance_fail "sha256 tooling is required"
    return 1
  }
  if [[ "$staged_provider_sha" != "$expected_provider_sha" ]]; then
    rm -rf "$stage_dir"
    wrapper_conformance_fail "staged provider content hash mismatch"
    return 1
  fi

  WRAPPER_CONFORMANCE_STAGE_DIR=$stage_dir
  WRAPPER_CONFORMANCE_STAGED_PATH=$staged_path
  WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH=$staged_provider_path
}

wrapper_conformance_readonly() {
  local route=$1
  local env_name=$2
  local cmd=$3
  local evidence_path=${4:-}

  wrapper_conformance_parse_cmd "$env_name" "$cmd" "$evidence_path" || return 1
  wrapper_conformance_check_record "$route" "$WRAPPER_CONFORMANCE_WRAPPER_PATH" "$WRAPPER_CONFORMANCE_EVIDENCE_PATH" || return 1
}

wrapper_conformance_gate() {
  local route=$1
  local env_name=$2
  local cmd=$3
  local evidence_path=${4:-}

  wrapper_conformance_readonly "$route" "$env_name" "$cmd" "$evidence_path" || return 1
  wrapper_conformance_stage_runtime \
    "$WRAPPER_CONFORMANCE_WRAPPER_PATH" "$WCF_wrapper_sha256" \
    "$WRAPPER_CONFORMANCE_PROVIDER_PATH" "$WCF_provider_sha256" || return 1
}

wrapper_conformance_cleanup_stage() {
  local stage_dir=${1:-}

  if [[ -n "$stage_dir" ]]; then
    rm -rf "$stage_dir"
  fi
  return 0
}
