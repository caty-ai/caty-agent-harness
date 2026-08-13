#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

check_fixed() {
  local id="$1"
  local file="$2"
  local needle="$3"
  local reason="$4"
  if [ ! -f "$file" ]; then
    echo "CHECK $id FAIL missing $file"
    status=1
    return
  fi
  if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_absent() {
  local id="$1"
  local file="$2"
  local needle="$3"
  local reason="$4"
  if [ ! -f "$file" ]; then
    echo "CHECK $id FAIL missing $file"
    status=1
    return
  fi
  if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    echo "CHECK $id FAIL $reason"
    status=1
  else
    echo "CHECK $id PASS $reason"
  fi
}

check_fixed "a01" "adapters/claude-code/INSTALL.md" 'cwd for a Caty Agent Harness' "Claude install stop-hook description uses the public product name"
check_absent "a02" "adapters/claude-code/INSTALL.md" 'What it does: when the assistant ends a turn in a cwd that contains a fable-loop' "Claude install stop-hook description drops the retired product name"
check_fixed "a03" "adapters/claude-code/INSTALL.md" 'governed, headless capture attempt per session.' "Claude install precompact section matches the renamed prose block"
check_absent "a04" "adapters/claude-code/INSTALL.md" 'governed, headless capture attempt per session. It supplies the current `## Lessons' "Claude install drops the pre-rename precompact block wording"

check_fixed "a05" "adapters/claude-code/checkpoint-stop-hook.sh" '# Caty Agent Harness CHECKPOINT enforcement' "Claude stop hook banner uses the public product name"
check_absent "a06" "adapters/claude-code/checkpoint-stop-hook.sh" '# fable-loop CHECKPOINT enforcement — Claude Code Stop hook (DESIGN §4.1, Issue #7).' "Claude stop hook banner drops the retired product name"
check_fixed "a07" "adapters/claude-code/checkpoint-stop-hook.sh" 'turn in a Caty Agent Harness workspace' "Claude stop hook workspace comment uses the public product name"
check_absent "a08" "adapters/claude-code/checkpoint-stop-hook.sh" '# Fires when the assistant ends a turn in a workspace that has a fable-loop STATE.md' "Claude stop hook workspace comment drops the retired product name"
check_fixed "a09" "adapters/claude-code/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"' "Claude stop hook uses the public guard-directory prefix"
check_absent "a10" "adapters/claude-code/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/fable-loop-hook"' "Claude stop hook drops the retired guard-directory prefix"
check_fixed "a11" "adapters/claude-code/checkpoint-stop-hook.sh" 'caty-agent-harness CHECKPOINT' "Claude stop hook reminder uses the public CHECKPOINT prefix"
check_absent "a12" "adapters/claude-code/checkpoint-stop-hook.sh" 'fable-loop CHECKPOINT: workspace files changed after STATE.md was last written' "Claude stop hook reminder drops the retired CHECKPOINT prefix"

check_fixed "a13" "adapters/claude-code/precompact-flush-hook.sh" '# Caty Agent Harness pre-destruction memory flush' "Claude precompact banner uses the public product name"
check_absent "a14" "adapters/claude-code/precompact-flush-hook.sh" '# fable-loop pre-destruction memory flush — Claude Code PreCompact hook (Issue #47).' "Claude precompact banner drops the retired product name"
check_fixed "a15" "adapters/claude-code/precompact-flush-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"' "Claude precompact hook uses the public guard-directory prefix"
check_absent "a16" "adapters/claude-code/precompact-flush-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/fable-loop-hook"' "Claude precompact hook drops the retired guard-directory prefix"
check_fixed "a17" "adapters/claude-code/precompact-flush-hook.sh" 'memory-flush extractor for a Caty Agent Harness workspace' "Claude precompact prompt uses the public product name"
check_absent "a18" "adapters/claude-code/precompact-flush-hook.sh" 'You are a memory-flush extractor for a fable-loop workspace about to lose its context window.' "Claude precompact prompt drops the retired product name"

check_fixed "a19" "adapters/codex/INSTALL.md" 'Caty Agent' "Codex install intro uses the public product name"
check_absent "a20" "adapters/codex/INSTALL.md" 'Codex CLI supports the same lifecycle hooks as Claude Code, so fable-loop CHECKPOINT' "Codex install intro drops the retired product name"
check_fixed "a21" "adapters/codex/INSTALL.md" 'cwd for a Caty Agent Harness' "Codex install stop-hook description uses the public product name"
check_absent "a22" "adapters/codex/INSTALL.md" 'What it does: when the agent ends a turn in a cwd that contains a fable-loop' "Codex install stop-hook description drops the retired product name"

check_fixed "a23" "adapters/codex/checkpoint-stop-hook.sh" '# Caty Agent Harness CHECKPOINT enforcement' "Codex stop hook banner uses the public product name"
check_absent "a24" "adapters/codex/checkpoint-stop-hook.sh" '# fable-loop CHECKPOINT enforcement — Codex CLI Stop hook (DESIGN §4.1, Issue #93).' "Codex stop hook banner drops the retired product name"
check_fixed "a25" "adapters/codex/checkpoint-stop-hook.sh" 'turn in a Caty Agent Harness workspace' "Codex stop hook workspace comment uses the public product name"
check_absent "a26" "adapters/codex/checkpoint-stop-hook.sh" '# Fires when the agent ends a turn in a workspace that has a fable-loop STATE.md' "Codex stop hook workspace comment drops the retired product name"
check_fixed "a27" "adapters/codex/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"' "Codex stop hook uses the public guard-directory prefix"
check_absent "a28" "adapters/codex/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/fable-loop-hook"' "Codex stop hook drops the retired guard-directory prefix"
check_fixed "a29" "adapters/codex/checkpoint-stop-hook.sh" 'caty-agent-harness CHECKPOINT' "Codex stop hook reminder uses the public CHECKPOINT prefix"
check_absent "a30" "adapters/codex/checkpoint-stop-hook.sh" 'fable-loop CHECKPOINT: workspace files changed after STATE.md was last written' "Codex stop hook reminder drops the retired CHECKPOINT prefix"

check_fixed "a31" "adapters/kimi/INSTALL.md" 'Caty Agent Harness CHECKPOINT enforcement' "Kimi install intro uses the public product name"
check_absent "a32" "adapters/kimi/INSTALL.md" 'fable-loop CHECKPOINT enforcement reuses the reference Stop-hook logic' "Kimi install intro drops the retired product name"
check_fixed "a33" "adapters/kimi/INSTALL.md" 'cwd for a Caty Agent Harness workspace' "Kimi install stop-hook description uses the public product name"
check_absent "a34" "adapters/kimi/INSTALL.md" 'end a turn in a cwd with a fable-loop `STATE.md` and workspace files changed after' "Kimi install stop-hook description drops the retired product name"

check_fixed "a35" "adapters/kimi/checkpoint-stop-hook.sh" '# Caty Agent Harness CHECKPOINT enforcement' "Kimi stop hook banner uses the public product name"
check_absent "a36" "adapters/kimi/checkpoint-stop-hook.sh" '# fable-loop CHECKPOINT enforcement — Kimi Code CLI Stop hook (DESIGN §4.1, Issue #93).' "Kimi stop hook banner drops the retired product name"
check_fixed "a37" "adapters/kimi/checkpoint-stop-hook.sh" 'turn in a Caty Agent Harness workspace' "Kimi stop hook workspace comment uses the public product name"
check_absent "a38" "adapters/kimi/checkpoint-stop-hook.sh" '# Fires when the model is about to end a turn in a workspace that has a fable-loop' "Kimi stop hook workspace comment drops the retired product name"
check_fixed "a39" "adapters/kimi/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"' "Kimi stop hook uses the public guard-directory prefix"
check_absent "a40" "adapters/kimi/checkpoint-stop-hook.sh" 'guard_dir="${TMPDIR:-/tmp}/fable-loop-hook"' "Kimi stop hook drops the retired guard-directory prefix"
check_fixed "a41" "adapters/kimi/checkpoint-stop-hook.sh" 'caty-agent-harness CHECKPOINT' "Kimi stop hook reminder uses the public CHECKPOINT prefix"
check_absent "a42" "adapters/kimi/checkpoint-stop-hook.sh" 'fable-loop CHECKPOINT: workspace files changed after STATE.md was last written' "Kimi stop hook reminder drops the retired CHECKPOINT prefix"

check_fixed "a43" "docs/plugin-convention.md" 'Caty Agent Harness is a **generic completion engine**' "plugin convention uses the public product name"
check_absent "a44" "docs/plugin-convention.md" 'fable-loop-harness is a **generic completion engine**' "plugin convention drops the retired product name"

check_fixed "a45" "templates/cron-wrapper.tmpl.sh" 'TARGET=${TARGET:-/absolute/path/to/caty-agent-harness-target}' "cron-wrapper template uses the public target-path example"
check_absent "a46" "templates/cron-wrapper.tmpl.sh" 'TARGET=${TARGET:-/absolute/path/to/fable-loop-target}' "cron-wrapper template drops the retired target-path example"

check_fixed "a47" "templates/launchd.tmpl.plist" 'Caty Agent Harness LaunchAgent template v1' "launchd template banner uses the public product name"
check_absent "a48" "templates/launchd.tmpl.plist" 'fable-loop LaunchAgent template v1' "launchd template banner drops the retired product name"
check_fixed "a49" "templates/launchd.tmpl.plist" '<string>com.example.caty-agent-harness-tick</string>' "launchd template uses the public label example"
check_absent "a50" "templates/launchd.tmpl.plist" '<string>com.example.fable-loop-tick</string>' "launchd template drops the retired label example"
check_fixed "a51" "templates/launchd.tmpl.plist" '<string>/absolute/path/to/caty-agent-harness-target</string>' "launchd template uses the public target-path example"
check_absent "a52" "templates/launchd.tmpl.plist" '<string>/absolute/path/to/fable-loop-target</string>' "launchd template drops the retired target-path example"

check_fixed "a53" "templates/updater-cron.tmpl.sh" 'Caty Agent Harness updater cron wrapper' "updater-cron template banner uses the public product name"
check_absent "a54" "templates/updater-cron.tmpl.sh" '# fable-loop updater cron wrapper template v1' "updater-cron template banner drops the retired product name"
check_fixed "a55" "templates/updater-cron.tmpl.sh" 'REPO_DIR=${REPO_DIR:-/absolute/path/to/caty-agent-harness}' "updater-cron template uses the public repository-path example"
check_absent "a56" "templates/updater-cron.tmpl.sh" 'REPO_DIR=${REPO_DIR:-/absolute/path/to/fable-loop-harness}' "updater-cron template drops the retired repository-path example"

check_fixed "a57" "tests/pause-contract.test.sh" "grep -Fq 'caty-agent-harness CHECKPOINT' \"\$TMP/enabled-hook.stderr\" \\" "pause-contract enabled-hook assertion uses the public CHECKPOINT prefix"
check_absent "a58" "tests/pause-contract.test.sh" "grep -Fq 'fable-loop CHECKPOINT' \"\$TMP/enabled-hook.stderr\" \\" "pause-contract enabled-hook assertion drops the retired CHECKPOINT prefix"
check_fixed "a59" "tests/pause-contract.test.sh" 'assert "caty-agent-harness CHECKPOINT" in value["reason"]' "pause-contract Codex JSON assertion uses the public CHECKPOINT prefix"
check_absent "a60" "tests/pause-contract.test.sh" 'assert "fable-loop CHECKPOINT" in value["reason"]' "pause-contract Codex JSON assertion drops the retired CHECKPOINT prefix"
check_fixed "a61" "tests/pause-contract.test.sh" "grep -Fq 'caty-agent-harness CHECKPOINT' \"\$TMP/multiworkspace-hook.stderr\" \\" "pause-contract multiworkspace assertion uses the public CHECKPOINT prefix"
check_absent "a62" "tests/pause-contract.test.sh" "grep -Fq 'fable-loop CHECKPOINT' \"\$TMP/multiworkspace-hook.stderr\" \\" "pause-contract multiworkspace assertion drops the retired CHECKPOINT prefix"

check_fixed "a63" "templates/cron-wrapper.tmpl.sh" '# fable-loop cron wrapper template v1' "frozen cron-wrapper marker remains unchanged"
check_fixed "a64" "install.sh" 'legacy_marker_line="# fable-loop bootstrap v1"' "frozen bootstrap marker remains unchanged"
check_fixed "a65" "adapters/openclaw/sentinel-cron.sh" 'marker_line="# fable-loop sentinel notice v1"' "frozen sentinel-notice marker remains unchanged"
check_fixed "a66" "adapters/CONTRACT.md" 'schema=fable-wrapper-conformance/v1' "frozen wrapper schema remains in the adapter contract"
check_fixed "a67" "scripts/attest-wrapper" 'schema=fable-wrapper-conformance/v1' "frozen wrapper schema remains in the attestation command"
check_fixed "a68" "scripts/lib-wrapper-conformance.sh" "'fable-wrapper-conformance/v1'" "frozen wrapper schema remains in the conformance library"
check_fixed "a69" "adapters/CONTRACT.md" '`FABLE_CONFORMING_PROVIDER_PATH`' "frozen provider-path variable remains in the adapter contract"
check_fixed "a70" "adapters/hermes/INSTALL.md" '`FABLE_CONFORMING_PROVIDER_PATH`' "frozen provider-path variable remains in the Hermes adapter documentation"
check_fixed "a71" "adapters/hermes/verify-job.sh" 'FABLE_CONFORMING_PROVIDER_PATH="$WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH"' "frozen provider-path variable remains in the Hermes implementation"
check_fixed "a72" "adapters/openclaw/INSTALL.md" '`FABLE_CONFORMING_PROVIDER_PATH`' "frozen provider-path variable remains in the OpenClaw adapter documentation"
check_fixed "a73" "adapters/openclaw/distill-audit.sh" 'FABLE_CONFORMING_PROVIDER_PATH="$WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH"' "frozen provider-path variable remains in the OpenClaw implementation"
check_fixed "a74" "tests/wrapper-conformance.test.sh" 'FABLE_CONFORMING_PROVIDER_PATH' "frozen provider-path variable remains in the contract test"
check_fixed "a75" "scripts/attest-wrapper" 'FABLE_WRAPPER_ROUTE="$route"' "frozen wrapper-route variable remains unchanged"
check_fixed "a76" "scripts/attest-wrapper" 'FABLE_WRAPPER_PATH="$wrapper_path"' "frozen wrapper-path variable remains unchanged"
check_fixed "a77" "scripts/attest-wrapper" 'FABLE_ATTEST_SCRATCH_DIR="$scratch_dir"' "frozen attestation-scratch variable remains unchanged"

exit "$status"
