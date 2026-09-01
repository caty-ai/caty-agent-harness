#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CRON_WRAPPER=$ROOT/templates/cron-wrapper.tmpl.sh
UPDATER_WRAPPER=$ROOT/templates/updater-cron.tmpl.sh
BASELINE_PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cron-wrapper-path-test.XXXXXX")
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

seed_check_workspace() {
  local name=$1
  local workspace=$TMP_ROOT/check-$name

  "$ROOT/install.sh" --workspace "$workspace" >/dev/null 2>&1
  printf '%s\n' '- fixture; 2026-09-01T00:00' >>"$workspace/STATE.md"
  printf '%s\n' '- 2026-09-01 | task=fixture | verifier=test | verdict=pass | fixture' >>"$workspace/loop/VERIFY.log.md"
  printf '%s\n' "$workspace"
}

install_wrapper_with_secrets_assignment() {
  local workspace=$1
  local wrapper_name=$2
  local secrets_assignment=$3
  local wrapper=$workspace/scripts/$wrapper_name

  mkdir -p "$workspace/scripts"
  awk -v secrets_assignment="$secrets_assignment" '
    NR == 2 { printf "SECRETS_ENV=%s\n", secrets_assignment }
    { print }
  ' "$CRON_WRAPPER" >"$wrapper"
  chmod +x "$wrapper"
  printf '%s\n' "$wrapper"
}

capture_run() {
  local key=$1
  shift
  CAPTURE_STDOUT=$TMP_ROOT/$key.out
  CAPTURE_STDERR=$TMP_ROOT/$key.err
  "$@" >"$CAPTURE_STDOUT" 2>"$CAPTURE_STDERR"
  CAPTURE_RC=$?
}

WORKSPACE=$TMP_ROOT/workspace
mkdir -p "$WORKSPACE/loop"
printf '# State\n' >"$WORKSPACE/STATE.md"

TARGET_SCRIPT=$TMP_ROOT/observe-target
cat >"$TARGET_SCRIPT" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PATH" >"$OBSERVED_PATH_FILE"
if resolved_cli=$(command -v caty-wrapper-cli-stub 2>/dev/null); then
  printf '%s\n' "$resolved_cli" >"$RESOLVED_CLI_FILE"
else
  : >"$RESOLVED_CLI_FILE"
fi
EOF
chmod +x "$TARGET_SCRIPT"

observed_path=$TMP_ROOT/unset.path
resolved_cli=$TMP_ROOT/unset.cli
capture_run cron-unset env -u CATY_WRAPPER_EXTRA_PATH \
  TARGET="$TARGET_SCRIPT" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$WORKSPACE" \
  OBSERVED_PATH_FILE="$observed_path" RESOLVED_CLI_FILE="$resolved_cli" \
  "$CRON_WRAPPER"
if [[ "$CAPTURE_RC" -eq 0 && "$(cat "$observed_path" 2>/dev/null)" == "$BASELINE_PATH" ]]; then
  pass 'cron wrapper unset extra path preserves exact baseline PATH'
else
  fail_case 'cron wrapper unset extra path preserves exact baseline PATH' \
    "rc=$CAPTURE_RC path=$(cat "$observed_path" 2>/dev/null)"
fi

observed_path=$TMP_ROOT/empty.path
resolved_cli=$TMP_ROOT/empty.cli
capture_run cron-empty env CATY_WRAPPER_EXTRA_PATH= \
  TARGET="$TARGET_SCRIPT" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$WORKSPACE" \
  OBSERVED_PATH_FILE="$observed_path" RESOLVED_CLI_FILE="$resolved_cli" \
  "$CRON_WRAPPER"
if [[ "$CAPTURE_RC" -eq 0 && "$(cat "$observed_path" 2>/dev/null)" == "$BASELINE_PATH" ]]; then
  pass 'cron wrapper empty extra path is a no-op'
else
  fail_case 'cron wrapper empty extra path is a no-op' \
    "rc=$CAPTURE_RC path=$(cat "$observed_path" 2>/dev/null)"
fi

first_extra=$TMP_ROOT/first-extra
second_extra=$TMP_ROOT/second-extra
mkdir -p "$first_extra" "$second_extra"
stub_cli=$second_extra/caty-wrapper-cli-stub
cat >"$stub_cli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stub_cli"
observed_path=$TMP_ROOT/valid.path
resolved_cli=$TMP_ROOT/valid.cli
capture_run cron-valid env CATY_WRAPPER_EXTRA_PATH="$first_extra:$second_extra" \
  TARGET="$TARGET_SCRIPT" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$WORKSPACE" \
  OBSERVED_PATH_FILE="$observed_path" RESOLVED_CLI_FILE="$resolved_cli" \
  "$CRON_WRAPPER"
expected_path=$BASELINE_PATH:$first_extra:$second_extra
if [[ "$CAPTURE_RC" -eq 0 \
  && "$(cat "$observed_path" 2>/dev/null)" == "$expected_path" \
  && "$(cat "$resolved_cli" 2>/dev/null)" == "$stub_cli" ]]; then
  pass 'cron wrapper appends valid entries and target resolves CLI from second entry'
else
  fail_case 'cron wrapper appends valid entries and target resolves CLI from second entry' \
    "rc=$CAPTURE_RC path=$(cat "$observed_path" 2>/dev/null) cli=$(cat "$resolved_cli" 2>/dev/null)"
fi

capture_run cron-relative env CATY_WRAPPER_EXTRA_PATH=relative-entry \
  TARGET=relative-target CATY_HARNESS_ROOT= CATY_WORKSPACE= "$CRON_WRAPPER"
if [[ "$CAPTURE_RC" -eq 3 \
  && "$(cat "$CAPTURE_STDERR")" == *'cron-wrapper infra error:'* \
  && "$(cat "$CAPTURE_STDERR")" == *'CATY_WRAPPER_EXTRA_PATH'* \
  && "$(cat "$CAPTURE_STDERR")" == *'relative-entry'* ]]; then
  pass 'cron wrapper rejects a relative extra path entry'
else
  fail_case 'cron wrapper rejects a relative extra path entry' \
    "rc=$CAPTURE_RC stderr=$(cat "$CAPTURE_STDERR")"
fi

capture_run cron-empty-entry env CATY_WRAPPER_EXTRA_PATH=/a::/b \
  TARGET=relative-target CATY_HARNESS_ROOT= CATY_WORKSPACE= "$CRON_WRAPPER"
if [[ "$CAPTURE_RC" -eq 3 \
  && "$(cat "$CAPTURE_STDERR")" == *'cron-wrapper infra error:'* \
  && "$(cat "$CAPTURE_STDERR")" == *'CATY_WRAPPER_EXTRA_PATH'* \
  && "$(cat "$CAPTURE_STDERR")" == *"entry must be non-empty and absolute: ''"* ]]; then
  pass 'cron wrapper rejects an empty extra path entry'
else
  fail_case 'cron wrapper rejects an empty extra path entry' \
    "rc=$CAPTURE_RC stderr=$(cat "$CAPTURE_STDERR")"
fi

capture_run updater-relative env CATY_WRAPPER_EXTRA_PATH=relative-updater \
  FMA_SCRIPTS_DIR= REPO_DIR=relative-repo "$UPDATER_WRAPPER"
if [[ "$CAPTURE_RC" -eq 3 \
  && "$(cat "$CAPTURE_STDERR")" == *'updater-cron infra error:'* \
  && "$(cat "$CAPTURE_STDERR")" == *'CATY_WRAPPER_EXTRA_PATH'* \
  && "$(cat "$CAPTURE_STDERR")" == *'relative-updater'* \
  && "$(cat "$CAPTURE_STDERR")" != *'FMA_SCRIPTS_DIR is not set'* ]]; then
  pass 'updater wrapper rejects invalid extra path before other preconditions'
else
  fail_case 'updater wrapper rejects invalid extra path before other preconditions' \
    "rc=$CAPTURE_RC stderr=$(cat "$CAPTURE_STDERR")"
fi

missing_extra=$TMP_ROOT/missing-updater-extra
capture_run updater-valid env CATY_WRAPPER_EXTRA_PATH="$missing_extra" \
  FMA_SCRIPTS_DIR= REPO_DIR=relative-repo "$UPDATER_WRAPPER"
if [[ "$CAPTURE_RC" -eq 3 \
  && "$(cat "$CAPTURE_STDERR")" == *'updater-cron infra error: FMA_SCRIPTS_DIR is not set'* \
  && "$(cat "$CAPTURE_STDERR")" != *'CATY_WRAPPER_EXTRA_PATH'* ]]; then
  pass 'updater wrapper accepts valid missing directory and reaches next precondition'
else
  fail_case 'updater wrapper accepts valid missing directory and reaches next precondition' \
    "rc=$CAPTURE_RC stderr=$(cat "$CAPTURE_STDERR")"
fi

check_workspace=$(seed_check_workspace home-resolution)
fake_home=$TMP_ROOT/fake-home
mkdir -p "$fake_home"
home_secret=$fake_home/home-resolution.env
printf 'GOOD=plain\n' >"$home_secret"
chmod 644 "$home_secret"
install_wrapper_with_secrets_assignment "$check_workspace" cron-home-resolution.sh '"$HOME/home-resolution.env"' >/dev/null
set +e
home_output=$(HOME="$fake_home" "$ROOT/install.sh" --check --workspace "$check_workspace" 2>&1)
home_rc=$?
set -e
if [[ "$home_rc" -eq 0 \
  && "$home_output" == *"warning: cron wrapper scripts/cron-home-resolution.sh SECRETS_ENV permissions should be 0600 or 0400: $home_secret has 644"* \
  && "$home_output" != *'unauditable - manual check required'* ]]; then
  pass 'install check resolves $HOME SECRETS_ENV paths and audits the resolved file'
else
  fail_case 'install check resolves $HOME SECRETS_ENV paths and audits the resolved file' \
    "rc=$home_rc output=$home_output"
fi

check_workspace=$(seed_check_workspace home-brace-resolution)
brace_secret=$fake_home/home-brace-resolution.env
printf 'GOOD=plain\n' >"$brace_secret"
chmod 644 "$brace_secret"
install_wrapper_with_secrets_assignment "$check_workspace" cron-home-brace-resolution.sh '"${HOME}/home-brace-resolution.env"' >/dev/null
set +e
brace_output=$(HOME="$fake_home" "$ROOT/install.sh" --check --workspace "$check_workspace" 2>&1)
brace_rc=$?
set -e
if [[ "$brace_rc" -eq 0 \
  && "$brace_output" == *"warning: cron wrapper scripts/cron-home-brace-resolution.sh SECRETS_ENV permissions should be 0600 or 0400: $brace_secret has 644"* \
  && "$brace_output" != *'unauditable - manual check required'* ]]; then
  pass 'install check resolves ${HOME} SECRETS_ENV paths and audits the resolved file'
else
  fail_case 'install check resolves ${HOME} SECRETS_ENV paths and audits the resolved file' \
    "rc=$brace_rc output=$brace_output"
fi

check_workspace=$(seed_check_workspace unresolved-dollar)
install_wrapper_with_secrets_assignment "$check_workspace" cron-unresolved.sh '"$SECRETS_DIR/unresolved.env"' >/dev/null
install_wrapper_with_secrets_assignment "$check_workspace" cron-home-boundary.sh '"$HOMELESS/not-home.env"' >/dev/null
set +e
unresolved_output=$("$ROOT/install.sh" --check --workspace "$check_workspace" 2>&1)
unresolved_rc=$?
set -e
if [[ "$unresolved_rc" -eq 0 \
  && "$unresolved_output" == *'warning: cron wrapper scripts/cron-unresolved.sh SECRETS_ENV unauditable - manual check required: SECRETS_ENV=$SECRETS_DIR/unresolved.env'* \
  && "$unresolved_output" == *'warning: cron wrapper scripts/cron-home-boundary.sh SECRETS_ENV unauditable - manual check required: SECRETS_ENV=$HOMELESS/not-home.env'* \
  && "$unresolved_output" == *'warning: cron wrapper SECRETS_ENV unauditable count: 2'* ]]; then
  pass 'install check reports unresolved dollar paths and $HOME boundary misses as unauditable with a summary count'
else
  fail_case 'install check reports unresolved dollar paths and $HOME boundary misses as unauditable with a summary count' \
    "rc=$unresolved_rc output=$unresolved_output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
