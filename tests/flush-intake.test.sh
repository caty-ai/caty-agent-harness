#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INTAKE=$ROOT/adapters/claude-code/flush-intake.sh
PROBE=$ROOT/scripts/deadman-probe.sh
TMP_ROOT=${TMPDIR:-/tmp}/flush-intake-test.$$
PASS_COUNT=0
FAIL_COUNT=0
TODAY=$(date -u +%F)

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
  ws=$(cd "$ws" && pwd -P)
  printf '%s\n' "$ws"
}

run_intake() {
  local ws=$1
  shift
  env INTAKE_LOCK_SLEEP_S=0 "$@" "$INTAKE" "$ws" >"$TMP_ROOT/intake.out" 2>"$TMP_ROOT/intake.err"
}

state_count() {
  local ws=$1
  local text=$2
  grep -Fxc -- "$text" "$ws/STATE.md" || true
}

receipt_value() {
  local ws=$1
  local key=$2
  tail -n 1 "$ws/loop/pending/intake-runs.log" | tr ' ' '\n' | sed -n "s/^$key=//p" | head -n 1
}

write_block() {
  local path=$1
  local date=$2
  local text=$3
  printf '%s\n' \
    "<!-- flush origin=stop-hook-demand session=test ts=${date}T01:02:03Z outcome=ok unverified=true -->" \
    "- $text" >"$path"
}

ws=$(new_ws case-01-fold)
cp "$ROOT/tests/fixtures/flush/basic.md" "$ws/loop/pending/flush-2026-07-01.md"
run_intake "$ws"
if grep -Fqx -- '- 2026-07-01 Keep the fold receipt beside the pending ledgers. (source: flush-intake)' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" folded)" -eq 2 ]; then
  pass '[1] ok blocks fold deterministically into Lessons learned'
else
  fail_case '[1] ok blocks fold deterministically into Lessons learned' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-02-skip)
printf '%s\n' \
  '<!-- flush origin=precompact-hook session=test ts=2026-07-01T01:02:03Z outcome=no_reply unverified=true -->' \
  '- This content must be skipped.' >"$ws/loop/pending/flush-2026-07-01.md"
run_intake "$ws"
if ! grep -Fq 'This content must be skipped' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" folded)" -eq 0 ]; then
  pass '[2] non-ok blocks are skipped whole'
else
  fail_case '[2] non-ok blocks are skipped whole' 'non-ok content was folded'
fi

ws=$(new_ws case-03-dedup)
write_block "$ws/loop/pending/flush-$TODAY.md" "$TODAY" 'A pending key rejects the same candidate.'
run_intake "$ws"
run_intake "$ws"
if [ "$(state_count "$ws" "- $TODAY A pending key rejects the same candidate. (source: flush-intake)")" -eq 1 ] \
  && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[3] pending-ledger dedup rejects a recurrence'
else
  fail_case '[3] pending-ledger dedup rejects a recurrence' 'recurrence was not rejected'
fi

if [ "$(receipt_value "$ws" folded)" -eq 0 ] && [ "$(receipt_value "$ws" deferred)" -eq 0 ]; then
  pass '[4] rerunning an unchanged current-day file is a true no-op'
else
  fail_case '[4] rerunning an unchanged current-day file is a true no-op' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-05-archive)
write_block "$ws/loop/pending/flush-2026-07-04.md" 2026-07-04 'An old complete file is archived.'
run_intake "$ws"
if [ -f "$ws/loop/archive/flush-2026-07-04.md" ] \
  && [ ! -e "$ws/loop/pending/flush-2026-07-04.md" ]; then
  pass '[5] a fully processed pre-today file moves to archive'
else
  fail_case '[5] a fully processed pre-today file moves to archive' 'archive transition missing'
fi

ws=$(new_ws case-06-malformed)
cp "$ROOT/tests/fixtures/flush/malformed.md" "$ws/loop/pending/flush-2026-07-03.md"
run_intake "$ws"
quarantine_ws=$ws
if grep -Fq 'A valid sibling block survives malformed-file quarantine.' "$ws/STATE.md" \
  && grep -Fq 'flush intake quarantined malformed file loop/artifacts/flush-2026-07-03.malformed.md' "$ws/STATE.md" \
  && [ -f "$ws/loop/artifacts/flush-2026-07-03.malformed.md" ] \
  && grep -Fq 'quarantined_path=loop/artifacts/flush-2026-07-03.malformed.md' "$ws/loop/pending/intake-runs.log"; then
  pass '[6] malformed files preserve valid siblings and quarantine with a durable receipt path'
else
  fail_case '[6] malformed files preserve valid siblings and quarantine with a durable receipt path' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-07-busy)
mkdir "$ws/loop/.distill-state.lock"
run_intake "$ws" INTAKE_LOCK_ATTEMPTS=1
if [ "$(receipt_value "$ws" lock)" = busy ] \
  && [ "$(receipt_value "$ws" marker)" = untouched ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[7] lock-busy exits zero with a receipt and no marker touch'
else
  fail_case '[7] lock-busy exits zero with a receipt and no marker touch' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-08-pause)
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
before=$(find "$ws" -type f -exec shasum -a 256 {} \; | sort)
output=$("$INTAKE" "$ws" 2>&1)
rc=$?
after=$(find "$ws" -type f -exec shasum -a 256 {} \; | sort)
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && [ "$output" = "status=paused workspace=$ws entrypoint=claude-code-flush-intake" ]; then
  pass '[8] pause guard returns the stable status without mutation'
else
  fail_case '[8] pause guard returns the stable status without mutation' "rc=$rc output=$output"
fi

ws=$(new_ws case-09-empty)
printf 'debris\n' >"$ws/loop/pending/.intake-old.tmp.fixture"
touch -t 202001010000 "$ws/loop/pending/.intake-old.tmp.fixture"
run_intake "$ws"
if [ "$(receipt_value "$ws" files_scanned)" -eq 0 ] \
  && [ -f "$ws/loop/.deadman/distill.marker" ] \
  && [ ! -e "$ws/loop/pending/.intake-old.tmp.fixture" ]; then
  pass '[9] an empty successful scan writes a receipt and marker'
else
  fail_case '[9] an empty successful scan writes a receipt and marker' 'empty scan evidence missing'
fi

ws=$(new_ws case-10-cap)
{
  printf '%s\n' '## Verified facts' '## General rules' '## Open failures' '## Lessons learned'
  i=1
  while [ "$i" -le 60 ]; do
    printf -- '- 2026-06-01 capped lesson %02d (source: distill-audit)\n' "$i"
    i=$((i + 1))
  done
  printf '%s\n' '## Last session'
} >"$ws/STATE.md"
write_block "$ws/loop/pending/flush-2026-07-05.md" 2026-07-05 'A cap overflow is counted.'
run_intake "$ws"
if [ "$(receipt_value "$ws" evicted_by_cap)" -eq 1 ] \
  && [ "$(awk '/^## Lessons learned/{s=1;next} s&&/^## /{exit} s{n++} END{print n+0}' "$ws/STATE.md")" -eq 60 ]; then
  pass '[10] STATE caps evict oldest lines and report the count'
else
  fail_case '[10] STATE caps evict oldest lines and report the count' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-11-backlog)
{
  printf '%s\n' '<!-- flush ts=2026-07-06T01:00:00Z outcome=ok -->' '- oldest one' '- oldest two'
} >"$ws/loop/pending/flush-2026-07-06.md"
{
  printf '%s\n' '<!-- flush ts=2026-07-07T01:00:00Z outcome=ok -->' '- newer one' '- newer two'
} >"$ws/loop/pending/flush-2026-07-07.md"
run_intake "$ws" INTAKE_MAX_FOLD=2
first_old=0
[ -f "$ws/loop/archive/flush-2026-07-06.md" ] && [ -f "$ws/loop/pending/flush-2026-07-07.md" ] && first_old=1
run_intake "$ws" INTAKE_MAX_FOLD=2
if [ "$first_old" -eq 1 ] && grep -Fq 'newer two' "$ws/STATE.md" \
  && [ -f "$ws/loop/archive/flush-2026-07-07.md" ]; then
  backlog_ordered=1
else
  backlog_ordered=0
fi
default_ws=$(new_ws case-11-default-budget)
{
  printf '%s\n' '<!-- flush ts=2026-07-06T01:00:00Z outcome=ok -->'
  i=1
  while [ "$i" -le 31 ]; do
    printf -- '- default budget candidate %02d\n' "$i"
    i=$((i + 1))
  done
} >"$default_ws/loop/pending/flush-2026-07-06.md"
run_intake "$default_ws"
if [ "$backlog_ordered" -eq 1 ] && [ "$(receipt_value "$default_ws" folded)" -eq 30 ] \
  && [ "$(receipt_value "$default_ws" deferred)" -eq 1 ]; then
  pass '[11] backlog drains oldest-first and the default budget is half the Lessons cap'
else
  fail_case '[11] backlog drains oldest-first and the default budget is half the Lessons cap' 'ordering or default budget failed'
fi

ws=$(new_ws case-12-oscillation)
write_block "$ws/loop/pending/flush-2026-07-08.md" 2026-07-08 'Ledger identity survives STATE eviction.'
run_intake "$ws"
sed '/Ledger identity survives STATE eviction/d' "$ws/STATE.md" >"$TMP_ROOT/state-without-ledger-line"
mv "$TMP_ROOT/state-without-ledger-line" "$ws/STATE.md"
cp "$ws/loop/archive/flush-2026-07-08.md" "$ws/loop/pending/flush-2026-07-08.md"
run_intake "$ws"
if [ "$(receipt_value "$ws" folded)" -eq 0 ] && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[12] ledger tombstones prevent cap-eviction refold oscillation'
else
  fail_case '[12] ledger tombstones prevent cap-eviction refold oscillation' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-13-cross-source)
sed '/## Lessons learned/a\
- 2026-06-01 Cross route identity is shared. (source: distill-audit)' "$ws/STATE.md" >"$TMP_ROOT/cross-state"
mv "$TMP_ROOT/cross-state" "$ws/STATE.md"
write_block "$ws/loop/pending/flush-2026-07-09.md" 2026-07-09 'Cross route identity is shared.'
run_intake "$ws"
if [ "$(receipt_value "$ws" folded)" -eq 0 ] && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[13] normalized STATE comparison rejects distill-to-intake duplicates'
else
  fail_case '[13] normalized STATE comparison rejects distill-to-intake duplicates' 'cross-source duplicate folded'
fi

ws=$(new_ws case-14-cross-date)
write_block "$ws/loop/pending/flush-2026-07-10.md" 2026-07-10 'Cross-date identity is stable.'
write_block "$ws/loop/pending/flush-2026-07-11.md" 2026-07-11 'Cross-date identity is stable.'
run_intake "$ws"
if [ "$(grep -Fc 'Cross-date identity is stable.' "$ws/STATE.md")" -eq 1 ] \
  && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[14] same text re-emitted on a later date is rejected'
else
  fail_case '[14] same text re-emitted on a later date is rejected' 'cross-date duplicate folded'
fi

ws=$(new_ws case-15-producer)
sed '/## Lessons learned/a\
- 2026-07-01 Existing cap-annotated lesson.' "$ws/STATE.md" >"$TMP_ROOT/cap-state"
mv "$TMP_ROOT/cap-state" "$ws/STATE.md"
fake_flush=$TMP_ROOT/fake-flush-model.sh
cat >"$fake_flush" <<'SH'
#!/usr/bin/env bash
sed -n '1,220p' >"$PROMPT_CAPTURE"
printf '%s\n' '- This model output is deliberately long enough to pass the producer quality threshold.'
SH
chmod +x "$fake_flush"
prompt_capture=$TMP_ROOT/precompact-prompt.md
printf '{"cwd":"%s","session_id":"case-15","trigger":"manual"}\n' "$ws" \
  | TMPDIR="$TMP_ROOT/hook-temp" PROMPT_CAPTURE="$prompt_capture" FLH_FLUSH_CMD="$fake_flush" \
    "$ROOT/adapters/claude-code/precompact-flush-hook.sh"
if grep -Fq 'Existing cap-annotated lesson.' "$prompt_capture"; then
  pass '[15] precompact prefix matching includes cap-annotated STATE sections'
else
  fail_case '[15] precompact prefix matching includes cap-annotated STATE sections' 'captured context was empty'
fi

ws=$(new_ws case-16-model)
cp "$ROOT/tests/fixtures/flush/model-authored.md" "$ws/loop/pending/flush-2026-07-02.md"
run_intake "$ws"
if grep -Fq 'Prefer an atomic same-directory rename' "$ws/STATE.md" \
  && grep -Fq 'Keep a genuine parenthetical ending (macOS default).' "$ws/STATE.md" \
  && ! grep -Fq 'Numbered prose' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" headerless_bullets)" -eq 1 ]; then
  pass '[16] model-authored bullets are tolerated while prose and numbered lines are ignored'
else
  fail_case '[16] model-authored bullets are tolerated while prose and numbered lines are ignored' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-17-today-torn)
printf '%s\n' "<!-- flush ts=${TODAY}T01:02:03Z outcome=ok -->" >"$ws/loop/pending/flush-$TODAY.md"
printf '%s' '- A current torn block waits for completion.' >>"$ws/loop/pending/flush-$TODAY.md"
run_intake "$ws"
first_deferred=$(receipt_value "$ws" deferred)
printf '\n' >>"$ws/loop/pending/flush-$TODAY.md"
run_intake "$ws"
if [ "$first_deferred" -eq 1 ] \
  && grep -Fq 'A current torn block waits for completion.' "$ws/STATE.md"; then
  pass '[17] a torn current-day final block is deferred then consumed'
else
  fail_case '[17] a torn current-day final block is deferred then consumed' "deferred=$first_deferred"
fi

if [ -f "$quarantine_ws/loop/.deadman/distill.marker" ]; then
  pass '[18] quarantine and successful intake runs touch the liveness marker'
else
  fail_case '[18] quarantine and successful intake runs touch the liveness marker' 'marker missing'
fi

ws=$(new_ws case-19-wrapper)
mkdir "$ws/loop/.distill-state.lock"
wrapper=$TMP_ROOT/cron-wrapper.sh
cp "$ROOT/templates/cron-wrapper.tmpl.sh" "$wrapper"
chmod +x "$wrapper"
TARGET="$INTAKE" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$ws" \
  INTAKE_LOCK_ATTEMPTS=1 INTAKE_LOCK_SLEEP_S=0 "$wrapper" "$ws" >/dev/null 2>&1
if [ ! -e "$ws/loop/.deadman/distill.marker" ] \
  && grep -Fq 'lock=busy marker=untouched' "$ws/loop/pending/intake-runs.log"; then
  pass '[19] cron wrapper cannot pre-touch the intake distill marker'
else
  fail_case '[19] cron wrapper cannot pre-touch the intake distill marker' 'marker was masked by wrapper'
fi

ws=$(new_ws case-20-dual-route)
: >"$ws/loop/.distill-last-run"
: >"$ws/loop/pending/intake-runs.log"
set +e
dual_output=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
dual_rc=$?
set -e
if [ "$dual_rc" -eq 1 ] && printf '%s\n' "$dual_output" | grep -Fq 'conflicting fold route evidence'; then
  pass '[20] install check rejects evidence from both fold routes'
else
  fail_case '[20] install check rejects evidence from both fold routes' "rc=$dual_rc"
fi

ws=$(new_ws case-21-lock)
holder=$TMP_ROOT/lock-holder.sh
cat >"$holder" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
take_state_lock "$2" fixture-holder
trap release_state_lock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
: >"$3"
while :; do sleep 1; done
SH
chmod +x "$holder"
ready=$TMP_ROOT/holder-ready
"$holder" "$ROOT/scripts/lib-state-fold.sh" "$ws" "$ready" &
holder_pid=$!
while [ ! -e "$ready" ]; do sleep 0.05; done
owner_line=$(cat "$ws/loop/.distill-state.lock/pid")
kill -TERM "$holder_pid"
wait "$holder_pid" 2>/dev/null || true
trap_released=0
[ ! -d "$ws/loop/.distill-state.lock" ] && trap_released=1
mkdir "$ws/loop/.distill-state.lock"
touch -t 202001010000 "$ws/loop/.distill-state.lock"
stale_result=$(DISTILL_STATE_LOCK_STALE_S=1 bash -c 'set -euo pipefail; source "$1"; take_state_lock "$2" stale-test 2 0; printf "%s:%s\n" "$STATE_FOLD_LOCK_OWNED" "$STATE_FOLD_LOCK_DIR"; release_state_lock' _ "$ROOT/scripts/lib-state-fold.sh" "$ws")
shim=$TMP_ROOT/rm-shim
mkdir "$shim"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$shim/rm"
chmod +x "$shim/rm"
mkdir "$ws/loop/.distill-state.lock"
touch -t 202001010000 "$ws/loop/.distill-state.lock"
bounded_result=$(PATH="$shim:$PATH" DISTILL_STATE_LOCK_STALE_S=1 bash -c 'set -euo pipefail; source "$1"; if take_state_lock "$2" bounded-test 2 0; then rc=0; else rc=$?; fi; printf "%s:%s\n" "$rc" "$STATE_FOLD_LOCK_OWNED"' _ "$ROOT/scripts/lib-state-fold.sh" "$ws")
if [[ "$owner_line" == *'fixture-holder' ]] && [ "$trap_released" -eq 1 ] \
  && [[ "$stale_result" == 1:*'.distill-state.lock' ]] && [ "$bounded_result" = '1:0' ]; then
  pass '[21] shared lock records callers, releases on signal, takes stale locks, and bounds failed takeover'
else
  fail_case '[21] shared lock records callers, releases on signal, takes stale locks, and bounds failed takeover' "owner=$owner_line released=$trap_released stale=$stale_result bounded=$bounded_result"
fi
rm -rf "$ws/loop/.distill-state.lock"

ws=$(new_ws case-22-probe)
mkdir -p "$ws/loop/.deadman"
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
printf '%s\n' '- concurrent fold remains present' >>"$ws/STATE.md"
mkdir "$ws/loop/.distill-state.lock"
notify=$TMP_ROOT/notify.sh
cat >"$notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$NOTIFY_LOG"
SH
chmod +x "$notify"
notify_log=$TMP_ROOT/notify.log
set +e
NOTIFY_LOG="$notify_log" DEADMAN_CHECKS='tick:1' DEADMAN_NOTIFY_CMD="$notify" "$PROBE" "$ws" >/dev/null 2>&1
first_probe_rc=$?
set -e
first_notify_count=$(wc -l <"$notify_log" | tr -d ' ')
rm -rf "$ws/loop/.distill-state.lock"
set +e
NOTIFY_LOG="$notify_log" DEADMAN_CHECKS='tick:1' DEADMAN_NOTIFY_CMD="$notify" "$PROBE" "$ws" >/dev/null 2>&1
second_probe_rc=$?
set -e
if [ "$first_probe_rc" -eq 1 ] && [ "$second_probe_rc" -eq 0 ] \
  && [ "$first_notify_count" -eq 1 ] && [ "$(wc -l <"$notify_log" | tr -d ' ')" -eq 1 ] \
  && grep -Fq 'deadman: tick' "$ws/STATE.md"; then
  pass '[22] lock-blocked deadman notification fires once and append retries next cycle'
else
  fail_case '[22] lock-blocked deadman notification fires once and append retries next cycle' "rcs=$first_probe_rc/$second_probe_rc notifications=$(wc -l <"$notify_log")"
fi
if grep -Fq -- '- concurrent fold remains present' "$ws/STATE.md" \
  && grep -Fq 'deadman: tick' "$ws/STATE.md"; then
  pass '[23] deadman retry preserves concurrent STATE content without a lost update'
else
  fail_case '[23] deadman retry preserves concurrent STATE content without a lost update' 'one STATE update was lost'
fi

ws=$(new_ws case-24-old-torn)
printf '%s\n' '<!-- flush ts=2026-07-12T01:02:03Z outcome=ok -->' '- A complete old line folds.' >"$ws/loop/pending/flush-2026-07-12.md"
printf '%s' '- This truncated old line is dropped.' >>"$ws/loop/pending/flush-2026-07-12.md"
run_intake "$ws"
if grep -Fq 'A complete old line folds.' "$ws/STATE.md" \
  && ! grep -Fq 'This truncated old line is dropped.' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" torn_lines)" -eq 1 ] \
  && [ -f "$ws/loop/archive/flush-2026-07-12.md" ] \
  && grep -Fq 'This truncated old line is dropped.' "$ws/loop/archive/flush-2026-07-12.md"; then
  pass '[24] a pre-today unterminated line is dropped, counted, and archived intact'
else
  fail_case '[24] a pre-today unterminated line is dropped, counted, and archived intact' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-25-order)
write_block "$ws/loop/pending/flush-2026-07-13.md" 2026-07-13 'STATE moves before the ledger.'
set +e
INTAKE_LOCK_SLEEP_S=0 INTAKE_TEST_CRASH_AFTER_STATE=1 "$INTAKE" "$ws" >/dev/null 2>&1
crash_rc=$?
set -e
ledger_after_crash=$(find "$ws/loop/pending" -maxdepth 1 -name 'intake-*.md' -print)
marker_after_crash=0
[ -e "$ws/loop/.deadman/distill.marker" ] && marker_after_crash=1
run_intake "$ws"
if [ "$crash_rc" -eq 75 ] && [ -z "$ledger_after_crash" ] && [ "$marker_after_crash" -eq 0 ] \
  && [ "$(state_count "$ws" '- 2026-07-13 STATE moves before the ledger. (source: flush-intake)')" -eq 1 ] \
  && [ "$(receipt_value "$ws" folded)" -eq 0 ] && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[25] crash after STATE move is stopped by normalized STATE backstop on retry'
else
  fail_case '[25] crash after STATE move is stopped by normalized STATE backstop on retry' "rc=$crash_rc ledger=$ledger_after_crash"
fi

ws=$(new_ws case-26-anchor)
printf '%s\n' \
  '<!-- flush ts=2026-07-14T01:02:03Z outcome=ok -->' \
  '- Keep the parenthetical ending (macOS default).' \
  '- Keep the parenthetical ending.' >"$ws/loop/pending/flush-2026-07-14.md"
run_intake "$ws"
if [ "$(grep -Fc 'Keep the parenthetical ending' "$ws/STATE.md")" -eq 2 ]; then
  pass '[26] normalization strips only the anchored consumer source marker'
else
  fail_case '[26] normalization strips only the anchored consumer source marker' 'legitimate parenthetical was stripped'
fi

if grep -Fq 'state_fold_candidate_is_duplicate' "$ROOT/adapters/openclaw/distill-audit.sh" \
  && grep -Fq 'state_fold_candidate_is_duplicate' "$INTAKE" \
  && grep -Fq 'annotate_reply_dedup_keys' "$INTAKE" \
  && grep -Fq 'split_annotated_reply_sections' "$INTAKE"; then
  pass '[27] both consumers call the shared annotation, splitting, and rejection machinery'
else
  fail_case '[27] both consumers call the shared annotation, splitting, and rejection machinery' 'one consumer forked fold logic'
fi

if [ -x "$INTAKE" ] && bash -n "$0" "$INTAKE" "$ROOT/scripts/lib-state-fold.sh"; then
  pass '[28] full-suite entry points are executable and syntax-valid'
else
  fail_case '[28] full-suite entry points are executable and syntax-valid' 'suite contract is not runnable'
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
