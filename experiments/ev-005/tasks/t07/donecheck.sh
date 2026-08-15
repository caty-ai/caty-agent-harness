#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t07-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

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

check_cmd() {
  local id="$1"
  local reason="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_no_unallowed_occurrences() {
  local id="$1"
  local reason="$2"
  local raw residual rc line content
  raw=$(mktemp "${TMPDIR:-/tmp}/ev005-t07-raw.XXXXXX") || {
    echo "CHECK $id FAIL could not create temp file"
    status=1
    return
  }
  residual=$(mktemp "${TMPDIR:-/tmp}/ev005-t07-residual.XXXXXX") || {
    rm -f "$raw"
    echo "CHECK $id FAIL could not create temp file"
    status=1
    return
  }
  git grep -ni -i 'fable' -- . ':(exclude).ev005-donecheck.sh' >"$raw" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "CHECK $id FAIL git grep failed"
    status=1
    rm -f "$raw" "$residual"
    return
  fi
  while IFS= read -r line; do
    content=${line#*:}
    content=${content#*:}
    if printf '%s\n' "$content" | grep -Eq -- '# fable-loop (bootstrap|cron wrapper template|sentinel notice) v1|fable-wrapper-conformance/v[01]|FABLE_[A-Z0-9_]+|Fable 5|Fable-class|Fable/Mythos|self-labeled "Fable"'; then
      continue
    fi
    printf '%s\n' "$line" >>"$residual"
  done <"$raw"
  if [ ! -s "$residual" ]; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
  rm -f "$raw" "$residual"
}

check_fixed "a01" "DESIGN.md" '# Caty Agent Harness v0.2 — Minimal Self-Improving Loop Harness for OpenClaw & Hermes Agent' "design title uses the public product name"
check_absent "a02" "DESIGN.md" '# fable-loop v0.2 — Minimal Self-Improving Loop Harness for OpenClaw & Hermes Agent' "design title drops the retired working name"

check_fixed "a03" "DESIGN-task-runner.md" 'Parent: Issue #8 (EPIC). Companion to DESIGN.md (harness v0.2); does not restate it.' "task-runner companion note uses the public product name"
check_absent "a04" "DESIGN-task-runner.md" 'Parent: Issue #8 (EPIC). Companion to DESIGN.md (fable-loop v0.2); does not restate it.' "task-runner companion note drops the retired working name"
check_fixed "a05" "DESIGN-task-runner.md" 'The harness loop guards the QUALITY of finished work; task-runner DRIVES work to' "task-runner loop description uses the public product name"
check_absent "a06" "DESIGN-task-runner.md" 'The fable-loop guards the QUALITY of finished work; task-runner DRIVES work to' "task-runner loop description drops the retired working name"
check_fixed "a07" "DESIGN-task-runner.md" 'verify: mechanical` and are excluded from k≥2 promotion until a real harness' "task-runner verification sentence uses the public product name"
check_absent "a08" "DESIGN-task-runner.md" 'verify: mechanical` and are excluded from k≥2 promotion until a real fable-loop' "task-runner verification sentence drops the retired working name"

check_fixed "a09" "SYNTHESIS.md" '# Cross-Review Synthesis & Adjudication — harness design v0.1 → v0.2' "synthesis title uses the public product name"
check_absent "a10" "SYNTHESIS.md" '# Cross-Review Synthesis & Adjudication — fable-loop v0.1 → v0.2' "synthesis title drops the retired working name"
check_fixed "a11" "SYNTHESIS.md" 'the R1–R15 in this file are harness v0.2 design-review resolutions' "synthesis namespace note uses the public product name"
check_absent "a12" "SYNTHESIS.md" 'the R1–R15 in this file are fable-loop v0.2 design-review resolutions' "synthesis namespace note drops the retired working name"
check_fixed "a13" "SYNTHESIS-task-runner.md" 'until a real harness VERIFY' "task-runner synthesis verification sentence uses the public product name"
check_absent "a14" "SYNTHESIS-task-runner.md" 'until a real fable-loop VERIFY' "task-runner synthesis verification sentence drops the retired working name"
check_fixed "a15" "SYNTHESIS-task-runner.md" "attempts_budget\` vs the harness's N=3 verify retries named distinctly" "task-runner synthesis retry wording uses the public product name"
check_absent "a16" "SYNTHESIS-task-runner.md" "attempts_budget\` vs fable-loop's N=3 verify retries named distinctly" "task-runner synthesis retry wording drops the retired working name"

check_fixed "a17" "docs/governance-rules.md" '> pre-publication private tracker #26' "governance historical-source prose uses the neutral tracker wording"
check_absent "a18" "docs/governance-rules.md" '> fable-loop-harness#26 (private tracker)' "governance historical-source prose drops the retired tracker name"
check_fixed "a19" "docs/governance-rules.md" '| Synthesis R1–R15 | `SYNTHESIS.md` | harness v0.1→v0.2 design review resolutions (verifier, STATE.md, rubric discipline) |' "governance synthesis-scope row uses the public product name"
check_absent "a20" "docs/governance-rules.md" '| Synthesis R1–R15 | `SYNTHESIS.md` | fable-loop v0.1→v0.2 design review resolutions (verifier, STATE.md, rubric discipline) |' "governance synthesis-scope row drops the retired working name"
check_fixed "a21" "docs/governance-rules.md" '| v1.0 source | pre-publication private tracker #26 (issue body) |' "governance v1.0 source row uses the neutral tracker wording"
check_absent "a22" "docs/governance-rules.md" '| v1.0 source | fable-loop-harness#26 (issue body) |' "governance v1.0 source row drops the retired tracker name"
check_fixed "a23" "docs/governance-rules.md" '| Amendment issue | pre-publication private tracker #123 |' "governance amendment row uses the neutral tracker wording"
check_absent "a24" "docs/governance-rules.md" '| Amendment issue | fable-loop-harness#123 |' "governance amendment row drops the retired tracker name"

check_fixed "a25" "docs/updater-rollout.md" 'From: Alpha · SoT: pre-publication private tracker Issue #36' "updater rollout source-of-truth line uses the neutral tracker wording"
check_absent "a26" "docs/updater-rollout.md" 'From: Alpha · SoT: fable-loop-harness Issue #36' "updater rollout source-of-truth line drops the retired tracker name"
check_fixed "a27" "docs/updater-rollout.md" '> Path correction (install learning, pre-publication private tracker #40): the cron line below shows' "updater rollout path-correction note uses the neutral tracker wording"
check_absent "a28" "docs/updater-rollout.md" '> Path correction (install learning, fable-loop #40): the cron line below shows' "updater rollout path-correction note drops the retired tracker name"

check_fixed "a29" "scripts/lib-wrapper-conformance.sh" 'stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/caty-wrapper-stage.XXXXXX") || {' "wrapper conformance uses the public stage prefix"
check_absent "a30" "scripts/lib-wrapper-conformance.sh" 'stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/fable-wrapper-stage.XXXXXX") || {' "wrapper conformance drops the retired stage prefix"
check_fixed "a31" "scripts/attest-wrapper" 'scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/caty-attest-wrapper.XXXXXX")' "attest wrapper uses the public scratch prefix"
check_absent "a32" "scripts/attest-wrapper" 'scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/fable-attest-wrapper.XXXXXX")' "attest wrapper drops the retired scratch prefix"
check_fixed "a33" "scripts/attest-wrapper" 'probe_stdout=$(mktemp "${TMPDIR:-/tmp}/caty-attest-wrapper.stdout.XXXXXX")' "attest wrapper uses the public stdout prefix"
check_absent "a34" "scripts/attest-wrapper" 'probe_stdout=$(mktemp "${TMPDIR:-/tmp}/fable-attest-wrapper.stdout.XXXXXX")' "attest wrapper drops the retired stdout prefix"
check_fixed "a35" "scripts/attest-wrapper" 'probe_stderr=$(mktemp "${TMPDIR:-/tmp}/caty-attest-wrapper.stderr.XXXXXX")' "attest wrapper uses the public stderr prefix"
check_absent "a36" "scripts/attest-wrapper" 'probe_stderr=$(mktemp "${TMPDIR:-/tmp}/fable-attest-wrapper.stderr.XXXXXX")' "attest wrapper drops the retired stderr prefix"

check_no_unallowed_occurrences "a37" "no case-insensitive fable occurrence exists outside the explicit allowlist"
check_cmd "a38" "full repository test suite passes on the branch-equivalent tree" run_isolated make test
check_cmd "a39" "repository lint passes on the branch-equivalent tree" run_isolated make lint

exit "$status"
