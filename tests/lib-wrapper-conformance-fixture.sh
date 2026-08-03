#!/usr/bin/env bash

conformance_write_provider() {
  local path=$1

  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'fixture provider'
SH
  chmod +x "$path"
}

conformance_write_probe() {
  local path=$1

  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'provider_id=%s\n' "${PROBE_PROVIDER_ID:-fixture-provider}"
printf 'provider_version=%s\n' "${PROBE_PROVIDER_VERSION:-fixture-v1}"
printf 'provider_path=%s\n' "${PROBE_PROVIDER_PATH:?}"
printf '%s\n' 'provider_launch=host-staged-env'
printf '%s\n' 'provider_relocatable=pass'
printf '%s\n' 'fresh_session=pass'
printf '%s\n' 'persistence_off=pass'
printf '%s\n' 'input_mode=host-inline'
printf '%s\n' 'tool_requests=auto-deny'
printf '%s\n' 'action_requests=auto-deny'
printf '%s\n' 'permission_requests=auto-deny'
printf '%s\n' 'workspace_access=none'
SH
  chmod +x "$path"
}

conformance_attest_wrapper() {
  local root=$1
  local route=$2
  local wrapper_path=$3
  local provider_path=$4
  local probe_path=$5
  local provider_id=${6:-fixture-provider}
  local provider_version=${7:-fixture-v1}
  local evidence_path=${8:-}

  if [[ -n "$evidence_path" ]]; then
    PROBE_PROVIDER_ID="$provider_id" \
      PROBE_PROVIDER_VERSION="$provider_version" \
      PROBE_PROVIDER_PATH="$provider_path" \
      "$root/scripts/attest-wrapper" --route "$route" --wrapper "$wrapper_path" \
      --probe "$probe_path" --evidence "$evidence_path" >/dev/null
  else
    PROBE_PROVIDER_ID="$provider_id" \
      PROBE_PROVIDER_VERSION="$provider_version" \
      PROBE_PROVIDER_PATH="$provider_path" \
      "$root/scripts/attest-wrapper" --route "$route" --wrapper "$wrapper_path" \
      --probe "$probe_path" >/dev/null
  fi
}
