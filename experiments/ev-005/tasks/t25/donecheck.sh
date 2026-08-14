#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t25.XXXXXX") || exit 1
TEST_OUTPUT="$TMP_ROOT/family-updater.out"
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

check_documented_trust_mechanism() {
  [ -f docs/updater-rollout.md ] || return 1
  grep -Eiq 'SSH.*sign|sign.*SSH' docs/updater-rollout.md || return 1
  grep -Fq 'allowed_signers' docs/updater-rollout.md || return 1
  grep -Eiq 'outside|out-of-repo' docs/updater-rollout.md
}

check_verification_order() {
  [ -f scripts/family-updater ] || return 1
  [ -f scripts/lib-updater-verify.sh ] || return 1
  run_isolated python3 - <<'PY'
import pathlib

text = pathlib.Path("scripts/family-updater").read_text(encoding="utf-8")
verify = text.find("updater_capture_verify_and_bind")
checkout = text.find("updater_checkout_captured_commit")
install = text.find("run_install_check", checkout)
if min(verify, checkout, install) < 0 or not verify < checkout < install:
    raise SystemExit(1)
PY
}

check_output_row() {
  pattern=$1
  [ -f "$TEST_OUTPUT" ] || return 1
  grep -Eiq -- "$pattern" "$TEST_OUTPUT"
}

run_check a01 'signed-tag trust mechanism and signer pin are documented' \
  'signed-tag trust mechanism or signer pin is not documented' check_documented_trust_mechanism
run_check a02 'verification precedes captured-OID checkout and installer execution' \
  'candidate code can be checked out or run before verification' check_verification_order

test_rc=0
run_isolated bash tests/family-updater.test.sh >"$TEST_OUTPUT" 2>&1 || test_rc=$?
if [ "$test_rc" -eq 0 ]; then
  pass_check a03 'focused family-updater regression module passes'
else
  fail_check a03 "focused family-updater regression module exits $test_rc"
fi

run_check a04 'unsigned substituted release is refused' \
  'regressions do not prove unsigned substituted release refusal' \
  check_output_row '^PASS .*unsigned.*refused'
run_check a05 'moved or lightweight tags cannot trigger candidate install' \
  'regressions do not prove tampered tag refusal before install' \
  check_output_row '^PASS .*moved tag.*install|^PASS .*lightweight.*no install'
run_check a06 'verification failures expose a clear reason' \
  'regressions do not prove clear fail-closed verification messages' \
  check_output_row '^PASS .*missing allowed_signers.*names the file|^PASS .*signature.*message'

[ "$failures" -eq 0 ]
