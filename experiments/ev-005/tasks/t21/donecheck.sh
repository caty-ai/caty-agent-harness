#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
TMP_ROOT=''
BASELINE_OUTPUT=''
MISSING_OUTPUT=''
BASELINE_RC=0
MISSING_RC=0

cleanup() {
  [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] && rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t21-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

check_design_contract() {
  [ -f DESIGN.md ] || return 1
  section=$(grep -A4 -F 'Skill frontmatter:' DESIGN.md 2>/dev/null) || return 1
  for key in name description trigger status verified_at verifier_id; do
    printf '%s\n' "$section" | grep -Fq "$key" || return 1
  done
  printf '%s\n' "$section" | grep -Fq 'verified skills'
}

check_staging_template() {
  path='skills/_staging/SKILL.tmpl.md'
  [ -f "$path" ] || return 1
  for needle in 'status: draft' 'source:' 'verified_at:' 'verifier_id:' 'promot'; do
    grep -Fq "$needle" "$path" || return 1
  done
}

prepare_probe() {
  local ws
  [ -x scripts/loop-init ] || return 1
  [ -x install.sh ] || return 1
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t21-skill-lint.XXXXXX") || return 1
  ws=$TMP_ROOT/ws
  run_isolated scripts/loop-init --workspace "$ws" >/dev/null 2>&1 || return 1
  mkdir -p "$ws/skills/verified-complete" "$ws/skills/draft-without-verification" || return 1

  cat >"$ws/skills/verified-complete/SKILL.md" <<'EOF'
---
name: verified-complete
description: complete verified skill
trigger: verified-complete
status: verified
verified_at: 2030-01-01T00:00:00Z
verifier_id: local-verifier
---

# verified-complete

## Verification

Checked.
EOF
  cat >"$ws/skills/draft-without-verification/SKILL.md" <<'EOF'
---
name: draft-without-verification
description: draft skill
trigger: draft-without-verification
status: draft
---

# draft-without-verification

## Verification

Pending.
EOF

  BASELINE_OUTPUT=$(run_isolated ./install.sh --check --workspace "$ws" 2>&1)
  BASELINE_RC=$?

  mkdir -p "$ws/skills/verified-missing" || return 1
  cat >"$ws/skills/verified-missing/SKILL.md" <<'EOF'
---
name: verified-missing
description: verified skill missing verification metadata
trigger: verified-missing
status: verified
---

# verified-missing

## Verification

Checked.
EOF
  MISSING_OUTPUT=$(run_isolated ./install.sh --check --workspace "$ws" 2>&1)
  MISSING_RC=$?
}

check_missing_warnings() {
  printf '%s\n' "$MISSING_OUTPUT" | grep -Fq 'warning: skill lint: missing verified_at for status verified: skills/verified-missing/SKILL.md' \
    && printf '%s\n' "$MISSING_OUTPUT" | grep -Fq 'warning: skill lint: missing verifier_id for status verified: skills/verified-missing/SKILL.md'
}

check_conditional_clean_cases() {
  ! printf '%s\n' "$BASELINE_OUTPUT" | grep -Eq 'skill lint: missing (verified_at|verifier_id).*skills/(verified-complete|draft-without-verification)/SKILL.md'
}

check_advisory_exit() {
  [ "$MISSING_RC" -eq "$BASELINE_RC" ]
}

check_targeted_regression() {
  local test_file found
  found=0
  while IFS= read -r test_file; do
    [ -f "$test_file" ] || continue
    grep -Fq 'status: verified' "$test_file" || continue
    grep -Fq 'missing verified_at' "$test_file" || continue
    grep -Fq 'missing verifier_id' "$test_file" || continue
    grep -Fq 'exit status' "$test_file" || continue
    found=1
    run_isolated bash "$test_file" >/dev/null 2>&1 || return 1
  done <<EOF
$(git ls-files -- 'tests/*.test.sh' 2>/dev/null)
EOF
  [ "$found" -eq 1 ]
}

run_check a01 'design records the conditional six-field verified-skill contract' 'design does not record the conditional six-field verified-skill contract' check_design_contract
run_check a02 'staging template records promotion-time verification fields' 'staging template does not record promotion-time verification fields' check_staging_template

if prepare_probe; then
  run_check a03 'a verified skill missing verification metadata emits both warnings' 'missing verification metadata does not emit both verified-skill warnings' check_missing_warnings
  run_check a04 'draft and complete verified skills avoid missing-field warnings' 'draft or complete verified skill receives an incorrect missing-field warning' check_conditional_clean_cases
  run_check a05 'verified-skill warnings leave the check exit status unchanged' 'verified-skill warnings change the check exit status' check_advisory_exit
else
  fail_check a03 'temporary skill-lint probe could not be prepared'
  fail_check a04 'temporary skill-lint probe could not be prepared'
  fail_check a05 'temporary skill-lint probe could not be prepared'
fi

run_check a06 'targeted conditional-field regression test passes' 'targeted conditional-field regression test is missing or fails' check_targeted_regression

[ "$failures" -eq 0 ]
