#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

ROOT=$(pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t28.XXXXXX") || exit 1
failures=0
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
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
  env_root=$(mktemp -d "$TMP_ROOT/isolation.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

check_design_boundary() {
  [ -f DESIGN-task-runner.md ] || return 1
  grep -Eiq 'trust|boundary|arbitrary.*shell' DESIGN-task-runner.md \
    && grep -Eiq 'mechanical|mechanically|enforce' DESIGN-task-runner.md \
    && grep -Eiq 'operator|configured provider' DESIGN-task-runner.md
}

check_quoted_hash_production() {
  workspace="$TMP_ROOT/workspace"
  task="$TMP_ROOT/quoted-hash.task.md"
  run_isolated "$ROOT/install.sh" --workspace "$workspace" >/dev/null 2>&1 || return 1
  cat >"$task" <<'EOF'
---
id: quoted-hash
title: quoted hash boundary probe
created: 2000-01-01T00:00:00Z
attempts_budget: 2
time_budget_min: 20
escalate_to: operator
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal

Exercise raw donecheck syntax validation.

## Done-when

```donecheck
printf '%s\n' '# retained' >/dev/null
test -s "$ARTIFACT_DIR/out/delivery-receipt.json"
```

## Step plan

1. Produce the artifact.
2. Deliver and capture the receipt.

## Resources

none

## Non-goals

none
EOF
  run_isolated "$ROOT/scripts/tr-enqueue" "$task" "$workspace" >/dev/null 2>&1 || return 1
  cmp -s "$task" "$workspace/loop/tasks/queue/quoted-hash.task.md"
}

check_quoted_hash_test() {
  found=0
  for test_path in tests/*.test.sh; do
    [ -f "$test_path" ] || continue
    if grep -Fq '# retained' "$test_path" \
      && grep -Fqi 'hash' "$test_path" \
      && grep -Fq 'tr-enqueue' "$test_path"; then
      found=$((found + 1))
      run_isolated bash "$test_path" >/dev/null 2>&1 || return 1
    fi
  done
  [ "$found" -ge 1 ]
}

check_raw_validation_contract() {
  [ -f DESIGN-task-runner.md ] && [ -f scripts/tr-enqueue ] || return 1
  grep -Fq 'invalid UTF-8' DESIGN-task-runner.md \
    && grep -Fq 'missing/multiple/unclosed donecheck' DESIGN-task-runner.md \
    && grep -Fq 'pinned-Bash' DESIGN-task-runner.md \
    && grep -Fq 'caty_extract_donecheck "$install_tmp"' scripts/tr-enqueue \
    && grep -Fq '"$TR_BASH" -n "$tmp_donecheck"' scripts/tr-enqueue
}

check_environment_contract() {
  [ -f DESIGN-task-runner.md ] && [ -f scripts/task-runner.sh ] || return 1
  grep -Fq 'env -i' DESIGN-task-runner.md \
    && grep -Fq 'TR_DC_CWD' DESIGN-task-runner.md \
    && grep -Fq '.tr-interpreters' DESIGN-task-runner.md \
    && grep -Fq 'env -i' scripts/task-runner.sh
}

check_resource_contract() {
  [ -f DESIGN-task-runner.md ] && [ -f scripts/task-runner.sh ] || return 1
  grep -Fqi 'process-group' DESIGN-task-runner.md \
    && grep -Fqi 'best-effort limits' DESIGN-task-runner.md \
    && grep -Fq 'TR_DONECHECK_TIMEOUT_S' scripts/task-runner.sh \
    && grep -Fq 'ulimit' scripts/task-runner.sh
}

check_receipt_contract() {
  [ -f DESIGN-task-runner.md ] && [ -f scripts/task-runner.sh ] || return 1
  grep -Fq 'non-symlink, non-empty regular file' DESIGN-task-runner.md \
    && grep -Fq 'beneath resolved `out/`' DESIGN-task-runner.md \
    && grep -Fq 'delivery receipt missing or invalid' scripts/task-runner.sh
}

check_spawn_contract() {
  [ -f DESIGN-task-runner.md ] && [ -f scripts/task-runner.sh ] || return 1
  grep -Fq 'non-absolute, non-regular, or non-executable' DESIGN-task-runner.md \
    && grep -Fq 'TR_SPAWN_STEP' scripts/task-runner.sh \
    && grep -Fq '[[ ! -f "$TR_SPAWN_STEP" ]]' scripts/task-runner.sh \
    && grep -Fq '[[ ! -x "$TR_SPAWN_STEP" ]]' scripts/task-runner.sh
}

check_residual_risks() {
  [ -f DESIGN-task-runner.md ] || return 1
  grep -Fqi 'arbitrary shell as the runner user' DESIGN-task-runner.md \
    && grep -Fqi 'privilege' DESIGN-task-runner.md \
    && grep -Fqi 'sandbox' DESIGN-task-runner.md \
    && grep -Fqi 'post-enqueue mutation' DESIGN-task-runner.md \
    && grep -Fqi 'setsid' DESIGN-task-runner.md \
    && grep -Fqi 'attest provider' DESIGN-task-runner.md
}

check_focused_suites() {
  for suite in tests/donecheck-extract.test.sh tests/tr-enqueue.test.sh tests/task-runner.test.sh tests/spawn-step.test.sh; do
    [ -f "$suite" ] || return 1
  done
  run_isolated bash tests/donecheck-extract.test.sh >/dev/null 2>&1 || return 1
  run_isolated bash tests/tr-enqueue.test.sh >/dev/null 2>&1 || return 1
  sed -e '/^case_env_integer_validation$/,$d' \
    -e "s|^ROOT=.*|ROOT='$ROOT'|" \
    tests/task-runner.test.sh >"$TMP_ROOT/task-runner-focused.test.sh" || return 1
  cat >>"$TMP_ROOT/task-runner-focused.test.sh" <<'EOF'
case_receipt_file_boundary
case_donecheck_environment_allowlist
case_donecheck_uses_pinned_interpreters
case_donecheck_timeout_is_tunable
(( fail_count == 0 ))
EOF
  run_isolated bash "$TMP_ROOT/task-runner-focused.test.sh" >/dev/null 2>&1 || return 1
  run_isolated bash tests/spawn-step.test.sh >/dev/null 2>&1
}

run_check a01 'the design note distinguishes mechanical and operator boundaries' 'the design trust boundary is not documented' check_design_boundary
run_check a02 'quoted hash syntax is accepted from the exact staged task' 'quoted hash syntax is altered, rejected, or staged differently' check_quoted_hash_production
run_check a03 'a focused quoted-hash regression passes' 'a focused quoted-hash regression is missing or fails' check_quoted_hash_test
run_check a04 'raw staged donecheck validation is fail-closed and pinned' 'raw staged donecheck validation contract is incomplete' check_raw_validation_contract
run_check a05 'donecheck environment and interpreter bounds are implemented' 'donecheck environment or interpreter bounds are incomplete' check_environment_contract
run_check a06 'timeout, process-group, and resource bounds are implemented' 'donecheck resource bounds are incomplete' check_resource_contract
run_check a07 'the resolved receipt boundary is enforced' 'the resolved receipt boundary is incomplete' check_receipt_contract
run_check a08 'the configured spawn provider is shape-checked' 'spawn-provider path/type/executable checks are incomplete' check_spawn_contract
run_check a09 'the committed residual risks are documented' 'one or more committed residual risks are undocumented' check_residual_risks
run_check a10 'focused execution-boundary suites pass' 'a focused execution-boundary suite is missing or fails' check_focused_suites

[ "$failures" -eq 0 ]
