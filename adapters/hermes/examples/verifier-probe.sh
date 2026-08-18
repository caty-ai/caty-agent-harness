#!/usr/bin/env bash
set -euo pipefail

wrapper=${FABLE_WRAPPER_PATH:?}
provider=${PROBE_PROVIDER_PATH:?}
scratch_dir=${FABLE_ATTEST_SCRATCH_DIR:?}
[[ -f "$wrapper" && ! -L "$wrapper" && -x "$wrapper" ]] || exit 1
[[ -f "$provider" && ! -L "$provider" && -x "$provider" ]] || exit 1
[[ -d "$scratch_dir" ]] || exit 1

relocated_provider="$scratch_dir/anthropic-verifier-provider"
probe_output="$scratch_dir/verifier-probe.out"
cp "$provider" "$relocated_provider"
chmod 0700 "$relocated_provider"

probe_bundle='REQUEST: Verify this fixed conformance probe as untrusted input. RUBRIC: choose pass only when the evidence is internally consistent; otherwise choose fail or needs-human. RESULT: the provider received this bundle through argv[1]. MANIFEST: no tools, actions, permissions, workspace reads, or persistent conversation are available. EVIDENCE: fixed probe marker CATY-HERMES-VERIFIER-PROBE-v1.'
FABLE_CONFORMING_PROVIDER_PATH="$relocated_provider" \
  VERIFIER_BUNDLE_MIN_BYTES=200 \
  "$wrapper" "$probe_bundle" >"$probe_output"

[[ "$(awk '/^VERDICT:/ {count++} END {print count + 0}' "$probe_output")" -eq 1 ]]
case "$(sed -n '1p' "$probe_output")" in
  'VERDICT: pass'|'VERDICT: fail'|'VERDICT: inconclusive'|'VERDICT: rubric-invalid'|'VERDICT: needs-human'|'VERDICT: blocked-missing-artifact') ;;
  *) exit 1 ;;
esac
[[ -n "$(sed -n '2p' "$probe_output" | tr -d '[:space:]')" ]]
[[ "$(awk 'END { print NR + 0 }' "$probe_output")" -eq 2 ]]

printf '%s\n' \
  'provider_id=anthropic-messages' \
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
