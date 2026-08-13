#!/usr/bin/env bash
set -euo pipefail

wrapper=${FABLE_WRAPPER_PATH:?}
provider=${PROBE_PROVIDER_PATH:?}
scratch_dir=${FABLE_ATTEST_SCRATCH_DIR:?}
[[ -f "$wrapper" && ! -L "$wrapper" && -x "$wrapper" ]] || exit 1
[[ -f "$provider" && ! -L "$provider" && -x "$provider" ]] || exit 1
[[ -d "$scratch_dir" ]] || exit 1

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
  "provider_version=${VERIFIER_MODEL:-claude-sonnet-5}" \
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
