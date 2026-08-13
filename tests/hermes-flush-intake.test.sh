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

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
