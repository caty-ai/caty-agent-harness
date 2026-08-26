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

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
