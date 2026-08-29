#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HERMES_INTAKE=$ROOT/adapters/hermes/flush-intake.sh
CLAUDE_INTAKE=$ROOT/adapters/claude-code/flush-intake.sh
CORE=$ROOT/scripts/flush-intake.sh
TMP_ROOT=${TMPDIR:-/tmp}/hermes-flush-intake-test.$$
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

new_ws() {
  local name=$1
  local ws=$TMP_ROOT/$name
  "$ROOT/scripts/loop-init" --workspace "$ws" >/dev/null
  (cd "$ws" && pwd -P)
}

workspace_snapshot() {
  local ws=$1
  find "$ws" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
}

assert_core_refusal() {
  local name=$1
  local ws=$2
  local mode=$3
  local before
  local after
  local output
  local rc

  before=$(workspace_snapshot "$ws")
  set +e
  if [ "$mode" = direct ]; then
    output=$(CATY_INTAKE_ADAPTER=rogue bash "$CORE" "$ws" 2>&1)
    rc=$?
  else
    output=$(CATY_INTAKE_ADAPTER=rogue workspace="$ws" \
      bash -c 'source "$1"' _ "$CORE" 2>&1)
    rc=$?
  fi
  set -e
  after=$(workspace_snapshot "$ws")
  if [ "$rc" -eq 2 ] && [ "$before" = "$after" ] \
    && [ ! -e "$ws/loop/pending/intake-runs.log" ] \
    && [ ! -e "$ws/loop/.deadman/distill.marker" ] \
    && printf '%s\n' "$output" | grep -Fq 'core must be sourced from a guarded adapter entry'; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc output=$output"
  fi
}

ws=$(new_ws pause)
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
before=$(find "$ws" -type f -exec shasum -a 256 {} \; | sort)
output=$("$HERMES_INTAKE" "$ws" 2>&1)
rc=$?
after=$(find "$ws" -type f -exec shasum -a 256 {} \; | sort)
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && [ "$output" = "status=paused workspace=$ws entrypoint=hermes-flush-intake" ]; then
  pass '[1] Hermes intake pause guard reports its adapter label without mutation'
else
  fail_case '[1] Hermes intake pause guard reports its adapter label without mutation' \
    "rc=$rc output=$output"
fi

ws=$(new_ws fold)
printf '%s\n' \
  '<!-- flush origin=checkpoint session=hermes-test ts=2026-07-20T01:02:03Z outcome=ok unverified=true -->' \
  '- Hermes folds through the shared intake core.' \
  >"$ws/loop/pending/flush-2026-07-20.md"
INTAKE_LOCK_SLEEP_S=0 "$HERMES_INTAKE" "$ws"
receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")
if grep -Fq 'Hermes folds through the shared intake core.' "$ws/STATE.md" \
  && printf '%s\n' "$receipt" | grep -Fq 'folded=1' \
  && [ -f "$ws/loop/archive/flush-2026-07-20.md" ]; then
  pass '[2] Hermes entry completes a successful shared-core fold'
else
  fail_case '[2] Hermes entry completes a successful shared-core fold' "receipt=$receipt"
fi

if grep -Fq 'CATY_INTAKE_ADAPTER=claude-code' "$CLAUDE_INTAKE" \
  && grep -Fq 'CATY_INTAKE_ADAPTER=hermes' "$HERMES_INTAKE" \
  && grep -Fq 'adapter_identity="${CATY_INTAKE_ADAPTER}-flush-intake"' "$CLAUDE_INTAKE" \
  && grep -Fq 'adapter_identity="${CATY_INTAKE_ADAPTER}-flush-intake"' "$HERMES_INTAKE" \
  && grep -Fq 'caty_pause_status_record "$workspace" "$adapter_identity"' "$CLAUDE_INTAKE" \
  && grep -Fq 'caty_pause_status_record "$workspace" "$adapter_identity"' "$HERMES_INTAKE" \
  && grep -Fq 'take_state_lock "$workspace" "$adapter_identity"' "$CORE"; then
  pass '[3] pause status and lock caller share the adapter-derived identity contract'
else
  fail_case '[3] pause status and lock caller share the adapter-derived identity contract' \
    'identity composition or a label consumer diverged'
fi

if [ -x "$HERMES_INTAKE" ] && [ -x "$CLAUDE_INTAKE" ] && [ ! -x "$CORE" ] \
  && bash -n "$HERMES_INTAKE" "$CLAUDE_INTAKE" "$CORE"; then
  pass '[4] both guarded entries are executable and the sourced core is syntax-valid'
else
  fail_case '[4] both guarded entries are executable and the sourced core is syntax-valid' \
    'mode or syntax contract failed'
fi

ws=$(new_ws direct-enabled)
assert_core_refusal '[5] directly executing the core refuses an enabled workspace without side effects' \
  "$ws" direct

ws=$(new_ws direct-paused)
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
assert_core_refusal '[6] directly executing the core refuses a paused workspace without side effects' \
  "$ws" direct

ws=$(new_ws unsentineled-source)
assert_core_refusal '[7] sourcing the core without the guarded-entry sentinel has no side effects' \
  "$ws" source

ws=$(new_ws 'canonical argv with space')
canonical_ws=$(cd "$ws" && pwd -P)
noncanonical_ws="$ws/./"
mkdir_shim="$TMP_ROOT/mkdir-shim"
lock_path_log="$TMP_ROOT/lock-paths.log"
real_mkdir=$(command -v mkdir)
mkdir -p "$mkdir_shim"
cat >"$mkdir_shim/mkdir" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$CATY_LOCK_PATH_LOG"
exec "$CATY_REAL_MKDIR" "$@"
SH
chmod 0755 "$mkdir_shim/mkdir"
printf '%s\n' \
  '<!-- flush origin=checkpoint session=canonical-test ts=2026-07-22T01:02:03Z outcome=ok unverified=true -->' \
  '- Canonical workspace paths survive adapter handoff.' \
  >"$ws/loop/pending/flush-2026-07-22.md"
PATH="$mkdir_shim:$PATH" CATY_LOCK_PATH_LOG="$lock_path_log" CATY_REAL_MKDIR="$real_mkdir" \
  INTAKE_LOCK_SLEEP_S=0 "$CLAUDE_INTAKE" "$noncanonical_ws"
receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")
receipt_tokens_clean=1
for receipt_token in $receipt; do
  case "$receipt_token" in
    [A-Za-z_][A-Za-z0-9_]*=*) ;;
    *) receipt_tokens_clean=0 ;;
  esac
done
parsed_folded=$(printf '%s\n' "$receipt" | tr ' ' '\n' | sed -n 's/^folded=//p')
if grep -Fq 'Canonical workspace paths survive adapter handoff.' "$ws/STATE.md" \
  && grep -Fqx "$canonical_ws/loop/.distill-state.lock" "$lock_path_log" \
  && ! grep -Fqx "$noncanonical_ws/loop/.distill-state.lock" "$lock_path_log" \
  && [ "$receipt_tokens_clean" -eq 1 ] && [ "$parsed_folded" -eq 1 ] \
  && ! printf '%s\n' "$receipt" | grep -Fq 'workspace='; then
  pass '[8] spaced non-canonical argv folds through the canonical lock path with a parser-clean receipt'
else
  fail_case '[8] spaced non-canonical argv folds through the canonical lock path with a parser-clean receipt' \
    "receipt=$receipt canonical=$canonical_ws raw=$noncanonical_ws locks=$(tr '\n' ';' <"$lock_path_log")"
fi

ws=$(new_ws canonical-paused-status)
canonical_ws=$(cd "$ws" && pwd -P)
noncanonical_ws="$ws/./"
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
before=$(workspace_snapshot "$ws")
output=$("$CLAUDE_INTAKE" "$noncanonical_ws" 2>&1)
rc=$?
after=$(workspace_snapshot "$ws")
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && [ "$output" = "status=paused workspace=$canonical_ws entrypoint=claude-code-flush-intake" ]; then
  pass '[9] non-canonical paused argv reports the canonical workspace without mutation'
else
  fail_case '[9] non-canonical paused argv reports the canonical workspace without mutation' \
    "rc=$rc output=$output"
fi

full_suite_log="$TMP_ROOT/hermes-full-suite.log"
set +e
INTAKE_UNDER_TEST="$HERMES_INTAKE" \
  INTAKE_EXPECTED_LABEL=hermes-flush-intake \
  INTAKE_SELF_MARKING=0 \
  bash "$ROOT/tests/flush-intake.test.sh" >"$full_suite_log" 2>&1
full_suite_rc=$?
set -e
if [ "$full_suite_rc" -eq 0 ] \
  && grep -Fqx 'Summary: 40 PASS, 0 FAIL' "$full_suite_log"; then
  pass '[10] the full flush-intake behavioural suite passes through the Hermes entry'
else
  fail_case '[10] the full flush-intake behavioural suite passes through the Hermes entry' \
    "rc=$full_suite_rc output=$(tail -n 10 "$full_suite_log" | tr '\n' ';')"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
