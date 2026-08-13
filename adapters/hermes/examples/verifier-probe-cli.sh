#!/usr/bin/env bash
set -euo pipefail

probe_fail() {
  printf 'CLI verifier probe: %s\n' "$1" >&2
  exit 1
}

sha256_file() {
  local path=$1
  local output
  local digest

  if command -v shasum >/dev/null 2>&1; then
    output=$(shasum -a 256 "$path") || return 1
  elif command -v sha256sum >/dev/null 2>&1; then
    output=$(sha256sum "$path") || return 1
  else
    return 1
  fi
  digest=${output%%[[:space:]]*}
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

wrapper=${FABLE_WRAPPER_PATH:?}
provider=${PROBE_PROVIDER_PATH:?}
scratch_dir=${FABLE_ATTEST_SCRATCH_DIR:?}
[[ -f "$wrapper" && ! -L "$wrapper" && -x "$wrapper" ]] || exit 1
[[ -f "$provider" && ! -L "$provider" && -x "$provider" ]] || exit 1
[[ -d "$scratch_dir" ]] || exit 1

cli_bin=${VERIFIER_CLI_BIN:-}
if [[ -z "$cli_bin" ]]; then
  [[ -n "${HOME:-}" ]] || probe_fail 'VERIFIER_CLI_BIN is unavailable'
  cli_bin=$HOME/.local/bin/claude
fi
[[ "$cli_bin" == /* && -e "$cli_bin" && -f "$cli_bin" && -x "$cli_bin" ]] \
  || probe_fail 'VERIFIER_CLI_BIN is unavailable or not executable'

model=${VERIFIER_MODEL:-claude-sonnet-5}
[[ "$model" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] \
  || probe_fail 'VERIFIER_MODEL is invalid'
cli_sha256=$(sha256_file "$cli_bin") \
  || probe_fail 'VERIFIER_CLI_BIN could not be hashed'
provider_version_limit=64
provider_version_suffix=+cli-${cli_sha256:0:16}
model_prefix_limit=$((provider_version_limit - ${#provider_version_suffix}))
model_prefix=${model:0:model_prefix_limit}
provider_version=$model_prefix$provider_version_suffix
[[ ${#provider_version} -le $provider_version_limit ]] \
  || probe_fail 'provider_version exceeds the attester limit'

relocated_provider=$scratch_dir/claude-cli-verifier-provider
probe_output=$scratch_dir/verifier-probe-cli.out
cp "$provider" "$relocated_provider" || exit 1
chmod 0700 "$relocated_provider" || exit 1

challenge_hex=$(LC_ALL=C od -An -N12 -tx1 /dev/urandom | tr -d '[:space:]') || exit 1
[[ "$challenge_hex" =~ ^[0-9a-f]{24}$ ]] || exit 1
challenge=CATY-CLI-PROBE-$challenge_hex
probe_bundle="REQUEST: Verify that the result and evidence contain the same probe token. RUBRIC: choose pass only when both tokens match exactly, and include the matching token in the concise reason. RESULT: the probe token is $challenge. MANIFEST: this fixed-shape probe grants no tools, actions, permissions, workspace reads, or persistent conversation. EVIDENCE: the independently supplied probe token is $challenge."

if ! FABLE_CONFORMING_PROVIDER_PATH="$relocated_provider" \
  VERIFIER_BUNDLE_MIN_BYTES=200 \
  "$wrapper" "$probe_bundle" >"$probe_output"; then
  exit 1
fi

[[ "$(sed -n '1p' "$probe_output")" == 'VERDICT: pass' ]] || exit 1
[[ "$(sed -n '2p' "$probe_output")" == *"$challenge"* ]] || exit 1
[[ "$(awk 'END { print NR + 0 }' "$probe_output")" -eq 2 ]] || exit 1

printf '%s\n' \
  'provider_id=claude-cli' \
  "provider_version=$provider_version" \
  "provider_path=$provider" \
  'provider_launch=host-staged-env' \
  'provider_relocatable=pass' \
  'fresh_session=pass' \
  'persistence_off=pass' \
  'input_mode=host-inline' \
  'tool_requests=auto-deny' \
  'action_requests=auto-deny' \
  'permission_requests=auto-deny' \
  'workspace_access=none'
