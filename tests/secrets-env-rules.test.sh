#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WRAPPER_TEMPLATE=$ROOT/templates/cron-wrapper.tmpl.sh
TMP_ROOT=${TMPDIR:-/tmp}/secrets-env-rules-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

seed_workspace() {
  local name=$1
  local workspace=$TMP_ROOT/ws-$name

  "$ROOT/install.sh" --workspace "$workspace" >/dev/null 2>&1
  printf '%s\n' '- fixture; 2026-08-12T00:00' >>"$workspace/STATE.md"
  printf '%s\n' '- 2026-08-12 | task=fixture | verifier=test | verdict=pass | fixture' >>"$workspace/loop/VERIFY.log.md"
  printf '%s\n' "$workspace"
}

install_configured_wrapper() {
  local workspace=$1
  local secrets_file=$2
  local wrapper=$workspace/scripts/cron-wrapper.sh

  mkdir -p "$workspace/scripts"
  awk -v secrets_file="$secrets_file" '
    NR == 2 { printf "SECRETS_ENV=\"%s\"\n", secrets_file }
    { print }
  ' "$WRAPPER_TEMPLATE" >"$wrapper"
  chmod +x "$wrapper"
  printf '%s\n' "$wrapper"
}

assert_prediction() {
  local name=$1
  local secrets_file=$2
  local expected=$3
  local warning_fragment=$4
  local workspace wrapper check_rc wrapper_rc
  local check_warned=0 wrapper_rejected=0

  workspace=$(seed_workspace "$name")
  wrapper=$(install_configured_wrapper "$workspace" "$secrets_file")

  "$ROOT/install.sh" --check --workspace "$workspace" \
    >"$TMP_ROOT/$name.check.out" 2>"$TMP_ROOT/$name.check.err"
  check_rc=$?
  if grep -Fq 'warning: cron wrapper scripts/cron-wrapper.sh SECRETS_ENV ' "$TMP_ROOT/$name.check.err"; then
    check_warned=1
  fi

  TARGET="$TMP_ROOT/recorder" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$workspace" \
    "$wrapper" >"$TMP_ROOT/$name.wrapper.out" 2>"$TMP_ROOT/$name.wrapper.err"
  wrapper_rc=$?
  if [ "$wrapper_rc" -eq 3 ] \
    && grep -Fq 'cron-wrapper infra error:' "$TMP_ROOT/$name.wrapper.err"; then
    wrapper_rejected=1
  fi

  if [ "$expected" = reject ] \
    && [ "$check_rc" -eq 0 ] && [ "$check_warned" -eq 1 ] \
    && [ "$wrapper_rejected" -eq 1 ] \
    && grep -Fq "$warning_fragment" "$TMP_ROOT/$name.check.err"; then
    pass "$name check warning predicts real wrapper rejection"
  elif [ "$expected" = accept ] \
    && [ "$check_rc" -eq 0 ] && [ "$check_warned" -eq 0 ] \
    && [ "$wrapper_rc" -eq 0 ] && [ "$wrapper_rejected" -eq 0 ]; then
    pass "$name check silence predicts real wrapper acceptance"
  else
    fail_case "$name prediction equivalence" \
      "check_rc=$check_rc warned=$check_warned wrapper_rc=$wrapper_rc rejected=$wrapper_rejected check_stderr=$(cat "$TMP_ROOT/$name.check.err") wrapper_stderr=$(cat "$TMP_ROOT/$name.wrapper.err")"
  fi
}

assert_secrets_lib_failure() {
  local name=$1
  local harness_root=$2
  local expected_message=$3
  local workspace rc

  workspace=$(seed_workspace "lib-$name")
  TARGET="$TMP_ROOT/recorder" CATY_HARNESS_ROOT="$harness_root" CATY_WORKSPACE="$workspace" \
    SECRETS_ENV="$valid_file" "$WRAPPER_TEMPLATE" \
    >"$TMP_ROOT/lib-$name.out" 2>"$TMP_ROOT/lib-$name.err"
  rc=$?
  if [ "$rc" -eq 3 ] \
    && grep -Fq 'cron-wrapper infra error:' "$TMP_ROOT/lib-$name.err" \
    && grep -Fq "$expected_message" "$TMP_ROOT/lib-$name.err" \
    && ! grep -Fq 'status=paused' "$TMP_ROOT/lib-$name.err"; then
    pass "$name secrets library fails closed through the infra-error contract"
  else
    fail_case "$name secrets library fails closed" \
      "rc=$rc stderr=$(cat "$TMP_ROOT/lib-$name.err")"
  fi
}

cat >"$TMP_ROOT/recorder" <<'EOF'
#!/usr/bin/env bash
printf 'ran\n'
EOF
chmod +x "$TMP_ROOT/recorder"

valid_file=$TMP_ROOT/valid.env
printf '# neutral fixture\n\n  GOOD="quoted"\r\n' >"$valid_file"
chmod 600 "$valid_file"

refused_file=$TMP_ROOT/refused.env
printf 'BASH_ENV=x\n' >"$refused_file"
chmod 600 "$refused_file"

readonly_name_file=$TMP_ROOT/readonly-name.env
printf 'UID=1\n' >"$readonly_name_file"
chmod 600 "$readonly_name_file"

non_assignment_file=$TMP_ROOT/non-assignment.env
printf 'export GOOD=plain\n' >"$non_assignment_file"
chmod 600 "$non_assignment_file"

nul_file=$TMP_ROOT/nul.env
printf 'GOOD=plain\nBROKEN=left\0right\n' >"$nul_file"
chmod 600 "$nul_file"

bad_mode_file=$TMP_ROOT/bad-mode.env
printf 'GOOD=plain\n' >"$bad_mode_file"
chmod 644 "$bad_mode_file"

symlink_source=$TMP_ROOT/symlink-source.env
symlink_file=$TMP_ROOT/symlink.env
printf 'GOOD=plain\n' >"$symlink_source"
chmod 600 "$symlink_source"
ln -s "$symlink_source" "$symlink_file"

assert_prediction valid "$valid_file" accept ''
assert_prediction refused-name "$refused_file" reject 'line 1 refuses interpreter-control name BASH_ENV'
assert_prediction readonly-name "$readonly_name_file" reject 'line 1 cannot export UID (reserved or read-only name)'
assert_prediction non-assignment "$non_assignment_file" reject 'line 1 is not a KEY=VALUE assignment'
assert_prediction embedded-nul "$nul_file" reject 'line 2 contains an embedded NUL byte'
assert_prediction bad-mode "$bad_mode_file" reject 'SECRETS_ENV permissions should be 0600 or 0400'
assert_prediction symlink "$symlink_file" reject 'SECRETS_ENV must not be a symlink'

dangling_file=$TMP_ROOT/dangling.env
ln -s "$TMP_ROOT/absent.env" "$dangling_file"
assert_prediction dangling-symlink "$dangling_file" reject 'SECRETS_ENV must not be a symlink'

fake_root=$TMP_ROOT/harness-without-secrets-lib
mkdir -p "$fake_root/scripts"
cp "$ROOT/scripts/lib-pause.sh" "$fake_root/scripts/lib-pause.sh"
missing_lib_ws=$(seed_workspace missing-lib)
TARGET="$TMP_ROOT/recorder" CATY_HARNESS_ROOT="$fake_root" CATY_WORKSPACE="$missing_lib_ws" \
  "$WRAPPER_TEMPLATE" >"$TMP_ROOT/no-secrets-lib.out" 2>"$TMP_ROOT/no-secrets-lib.err"
no_secrets_lib_rc=$?
TARGET="$TMP_ROOT/recorder" CATY_HARNESS_ROOT="$fake_root" CATY_WORKSPACE="$missing_lib_ws" \
  SECRETS_ENV="$valid_file" "$WRAPPER_TEMPLATE" \
  >"$TMP_ROOT/missing-lib.out" 2>"$TMP_ROOT/missing-lib.err"
missing_lib_rc=$?
if [ "$no_secrets_lib_rc" -eq 0 ] && grep -Fxq 'ran' "$TMP_ROOT/no-secrets-lib.out" \
  && [ "$missing_lib_rc" -eq 3 ] \
  && grep -Fq 'cron-wrapper infra error: SECRETS_ENV acceptance library is unavailable or invalid:' "$TMP_ROOT/missing-lib.err" \
  && ! grep -Fq 'status=paused' "$TMP_ROOT/missing-lib.err"; then
  pass 'secrets library is optional without secrets and fails closed when configured'
else
  fail_case 'missing secrets library fails closed' \
    "no_secrets_rc=$no_secrets_lib_rc secrets_rc=$missing_lib_rc stderr=$(cat "$TMP_ROOT/missing-lib.err")"
fi

symlink_lib_root=$TMP_ROOT/harness-symlink-secrets-lib
mkdir -p "$symlink_lib_root/scripts"
cp "$ROOT/scripts/lib-pause.sh" "$symlink_lib_root/scripts/lib-pause.sh"
ln -s "$ROOT/scripts/lib-secrets-env.sh" "$symlink_lib_root/scripts/lib-secrets-env.sh"
assert_secrets_lib_failure symlink "$symlink_lib_root" \
  'SECRETS_ENV acceptance library is unavailable or invalid:'

unreadable_lib_root=$TMP_ROOT/harness-unreadable-secrets-lib
mkdir -p "$unreadable_lib_root/scripts"
cp "$ROOT/scripts/lib-pause.sh" "$unreadable_lib_root/scripts/lib-pause.sh"
cp "$ROOT/scripts/lib-secrets-env.sh" "$unreadable_lib_root/scripts/lib-secrets-env.sh"
chmod 000 "$unreadable_lib_root/scripts/lib-secrets-env.sh"
if [ -r "$unreadable_lib_root/scripts/lib-secrets-env.sh" ]; then
  pass 'unreadable secrets library check skipped because this user can read mode 000 files'
else
  assert_secrets_lib_failure unreadable "$unreadable_lib_root" \
    'SECRETS_ENV acceptance library is unavailable or invalid:'
fi

invalid_lib_root=$TMP_ROOT/harness-invalid-secrets-lib
mkdir -p "$invalid_lib_root/scripts"
cp "$ROOT/scripts/lib-pause.sh" "$invalid_lib_root/scripts/lib-pause.sh"
printf 'this is not valid shell syntax (\n' >"$invalid_lib_root/scripts/lib-secrets-env.sh"
assert_secrets_lib_failure syntax-invalid "$invalid_lib_root" \
  'SECRETS_ENV acceptance library is unavailable or invalid:'

source_failure_lib_root=$TMP_ROOT/harness-source-failure-secrets-lib
mkdir -p "$source_failure_lib_root/scripts"
cp "$ROOT/scripts/lib-pause.sh" "$source_failure_lib_root/scripts/lib-pause.sh"
printf 'return 1\n' >"$source_failure_lib_root/scripts/lib-secrets-env.sh"
assert_secrets_lib_failure source-failure "$source_failure_lib_root" \
  'SECRETS_ENV acceptance library could not be loaded:'

refusal_locations=$(grep -Fl 'BASH_ENV|ENV|SHELLOPTS' \
  "$ROOT/scripts/lib-secrets-env.sh" "$ROOT/templates/cron-wrapper.tmpl.sh" "$ROOT/install.sh" || true)
assignment_locations=$(grep -Fl '([A-Za-z_][A-Za-z0-9_]*)=(.*)' \
  "$ROOT/scripts/lib-secrets-env.sh" "$ROOT/templates/cron-wrapper.tmpl.sh" "$ROOT/install.sh" || true)
if [ "$refusal_locations" = "$ROOT/scripts/lib-secrets-env.sh" ] \
  && [ "$assignment_locations" = "$ROOT/scripts/lib-secrets-env.sh" ]; then
  pass 'refusal list and assignment grammar have one production source'
else
  fail_case 'single-source anti-drift guard' \
    "refusal_locations=$refusal_locations assignment_locations=$assignment_locations"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
