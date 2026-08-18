#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INTAKE=${INTAKE_UNDER_TEST:-$ROOT/adapters/claude-code/flush-intake.sh}
INTAKE_EXPECTED_LABEL=${INTAKE_EXPECTED_LABEL:-claude-code-flush-intake}
INTAKE_SELF_MARKING=${INTAKE_SELF_MARKING:-1}
INTAKE_CORE=$ROOT/scripts/flush-intake.sh
PROBE=$ROOT/scripts/deadman-probe.sh
TMP_ROOT=${TMPDIR:-/tmp}/flush-intake-test.$$
PASS_COUNT=0
FAIL_COUNT=0
TODAY=$(date -u +%F)
DEFAULT_INTAKE_MAX_FOLD=$(bash -c 'source "$1"; printf "%s\n" "$((STATE_FOLD_LESSONS_CAP_DEFAULT / 2))"' \
  _ "$ROOT/scripts/lib-state-fold.sh")

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

age_file_seconds() {
  local path=$1
  local seconds=$2

  if touch -d "$seconds seconds ago" "$path" 2>/dev/null; then
    return 0
  fi
  touch -t "$(date -v-"${seconds}"S '+%Y%m%d%H%M.%S')" "$path"
}

file_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"
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
first_ledger_fold=$(receipt_value "$ws" folded)
sed '/A pending key rejects the same candidate/d' "$ws/STATE.md" >"$TMP_ROOT/state-without-case-03"
mv "$TMP_ROOT/state-without-case-03" "$ws/STATE.md"
run_intake "$ws"
if [ "$first_ledger_fold" -eq 1 ] \
  && [ "$(state_count "$ws" "- $TODAY A pending key rejects the same candidate. (source: flush-intake)")" -eq 0 ] \
  && [ "$(receipt_value "$ws" deduped)" -eq 1 ]; then
  pass '[3] pending-ledger dedup rejects a recurrence without the STATE backstop'
else
  fail_case '[3] pending-ledger dedup rejects a recurrence without the STATE backstop' 'recurrence was not rejected'
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
  && [ "$output" = "status=paused workspace=$ws entrypoint=$INTAKE_EXPECTED_LABEL" ]; then
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
  && [ "$(receipt_value "$ws" eviction_archive)" = "loop/archive/intake-evictions-$TODAY.md" ] \
  && grep -Fq 'capped lesson 01' "$ws/loop/archive/intake-evictions-$TODAY.md" \
  && [ "$(awk '/^## Lessons learned/{s=1;next} s&&/^## /{exit} s{n++} END{print n+0}' "$ws/STATE.md")" -eq 60 ]; then
  pass '[10] STATE caps archive evicted lessons and surface the count and path'
else
  fail_case '[10] STATE caps archive evicted lessons and surface the count and path' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
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
  while [ "$i" -le "$((DEFAULT_INTAKE_MAX_FOLD + 1))" ]; do
    printf -- '- default budget candidate %02d\n' "$i"
    i=$((i + 1))
  done
} >"$default_ws/loop/pending/flush-2026-07-06.md"
run_intake "$default_ws"
if [ "$backlog_ordered" -eq 1 ] \
  && [ "$(receipt_value "$default_ws" folded)" -eq "$DEFAULT_INTAKE_MAX_FOLD" ] \
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
distill_marker="$ws/loop/.deadman/distill.marker"
distill_marker_arg="$ws/loop/../loop/.deadman/distill.marker"
mkdir -p "${distill_marker%/*}"
touch -t 202001010000 "$distill_marker"
marker_mtime_before=$(file_mtime "$distill_marker")
wrapper=$TMP_ROOT/cron-wrapper.sh
cp "$ROOT/templates/cron-wrapper.tmpl.sh" "$wrapper"
chmod +x "$wrapper"
TARGET="$INTAKE" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$ws" \
  DEADMAN_MARKER="$distill_marker_arg" \
  INTAKE_LOCK_ATTEMPTS=1 INTAKE_LOCK_SLEEP_S=0 "$wrapper" "$ws" >/dev/null 2>&1
marker_mtime_after=$(file_mtime "$distill_marker")
if { [ "$INTAKE_SELF_MARKING" -eq 1 ] && [ "$marker_mtime_before" = "$marker_mtime_after" ]; } \
  || { [ "$INTAKE_SELF_MARKING" -eq 0 ] && [ "$marker_mtime_before" != "$marker_mtime_after" ]; }; then
  marker_contract=1
else
  marker_contract=0
fi
if [ "$marker_contract" -eq 1 ] \
  && grep -Fq 'lock=busy marker=untouched' "$ws/loop/pending/intake-runs.log"; then
  pass '[19] cron wrapper applies the configured adapter deadman-marking contract'
else
  fail_case '[19] cron wrapper applies the configured adapter deadman-marking contract' \
    "self_marking=$INTAKE_SELF_MARKING before=$marker_mtime_before after=$marker_mtime_after"
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
age_file_seconds "$ws/loop/.distill-state.lock" 120
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
first_probe_entries=$(grep -Fc 'deadman: tick' "$ws/STATE.md" || true)
lock_retained=0
[ -d "$ws/loop/.distill-state.lock" ] && lock_retained=1
rm -rf "$ws/loop/.distill-state.lock"
set +e
NOTIFY_LOG="$notify_log" DEADMAN_CHECKS='tick:1' DEADMAN_NOTIFY_CMD="$notify" "$PROBE" "$ws" >/dev/null 2>&1
second_probe_rc=$?
set -e
if [ "$first_probe_rc" -eq 1 ] && [ "$second_probe_rc" -eq 0 ] \
  && [ "$first_probe_entries" -eq 0 ] && [ "$lock_retained" -eq 1 ] \
  && [ "$first_notify_count" -eq 1 ] && [ "$(wc -l <"$notify_log" | tr -d ' ')" -eq 1 ] \
  && grep -Fq 'deadman: tick' "$ws/STATE.md"; then
  pass '[22] short deadman wait retains a sub-stale lock, notifies once, and retries append'
else
  fail_case '[22] short deadman wait retains a sub-stale lock, notifies once, and retries append' "rcs=$first_probe_rc/$second_probe_rc retained=$lock_retained first_entries=$first_probe_entries notifications=$(wc -l <"$notify_log")"
fi
if grep -Fq -- '- concurrent fold remains present' "$ws/STATE.md" \
  && grep -Fq 'deadman: tick' "$ws/STATE.md"; then
  pass '[23] deadman retry preserves pre-existing STATE content'
else
  fail_case '[23] deadman retry preserves pre-existing STATE content' 'pre-existing STATE content was lost'
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
  '- Keep literal provenance (source: user) suffix' \
  '- Keep literal provenance suffix (source: flush-intake)' >"$ws/loop/pending/flush-2026-07-14.md"
run_intake "$ws"
anchor_ws=$ws
unicode_ws=$(new_ws case-26-unicode-key)
{
  printf '%s\n' '<!-- flush ts=2026-07-20T01:02:03Z outcome=ok -->'
  printf '%s\n' \
    '- Don’t retry Job A until “ready now”.' \
    "- Don't retry Job A until \"ready now\"." \
    $'- Don\'t retry Job\u00a0A until "ready now".' \
    '- Ｄｏｎ'\''ｔ ｒｅｔｒｙ Ｊｏｂ Ａ ｕｎｔｉｌ "ｒｅａｄｙ ｎｏｗ"．'
} >"$unicode_ws/loop/pending/flush-2026-07-20.md"
run_intake "$unicode_ws"
parenthetical_fixture="$ROOT/tests/fixtures/flush/normalization-parenthetical.md"
parenthetical_normalized="$TMP_ROOT/normalization-parenthetical.txt"
mech_normalized="$TMP_ROOT/normalization-mech.txt"
mech_normalized_input="$TMP_ROOT/normalization-mech.input"
bash -c '
  source "$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    normalize_state_candidate "$line"
  done <"$2"
' _ "$ROOT/scripts/lib-state-fold.sh" "$parenthetical_fixture" >"$parenthetical_normalized"
cat >"$mech_normalized_input" <<'OUT'
- 2026-07-14 Keep a repeated route identity. (source: distill-audit)
- 2026-07-14 Keep a repeated route identity. (source: distill-audit) [mech_check: no]
OUT
bash -c '
  source "$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    normalize_state_candidate "$line"
  done <"$2"
' _ "$ROOT/scripts/lib-state-fold.sh" "$mech_normalized_input" >"$mech_normalized"
hash_plain=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$ROOT/scripts/lib-state-fold.sh" '- 2026-07-14 Keep a repeated route identity. (source: distill-audit)')
hash_mech=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$ROOT/scripts/lib-state-fold.sh" '- 2026-07-14 Keep a repeated route identity. (source: distill-audit) [mech_check: no]')
if [ "$(grep -Fc 'Keep literal provenance' "$anchor_ws/STATE.md")" -eq 2 ] \
  && grep -Fqx -- 'Keep a distinct local annotation. (some note)' "$parenthetical_normalized" \
  && [ "$(LC_ALL=C sort -u "$parenthetical_normalized" | wc -l | tr -d '[:space:]')" -eq 2 ] \
  && [ "$(LC_ALL=C sort -u "$mech_normalized" | wc -l | tr -d '[:space:]')" -eq 1 ] \
  && [ "$hash_plain" = "$hash_mech" ] \
  && grep -Fqx -- '- 2026-07-20 Don’t retry Job A until “ready now”. (source: flush-intake)' "$unicode_ws/STATE.md" \
  && [ "$(grep -Fc 'retry Job' "$unicode_ws/STATE.md")" -eq 1 ] \
  && [ "$(receipt_value "$unicode_ws" candidates)" -eq 4 ] \
  && [ "$(receipt_value "$unicode_ws" folded)" -eq 1 ] \
  && [ "$(receipt_value "$unicode_ws" deduped)" -eq 3 ]; then
  pass '[26] normalization is anchored, mech-check invariant, and key-only across Unicode variants'
else
  fail_case '[26] normalization is anchored, mech-check invariant, and key-only across Unicode variants' \
    "parenthetical=$(cat "$parenthetical_normalized" 2>/dev/null | tr '\n' ';') mech=$(cat "$mech_normalized" 2>/dev/null | tr '\n' ';') hashes=$hash_plain/$hash_mech receipt=$(tail -n1 "$unicode_ws/loop/pending/intake-runs.log")"
fi

if grep -Fq 'state_fold_candidate_is_duplicate' "$ROOT/adapters/openclaw/distill-audit.sh" \
  && grep -Fq 'state_fold_candidate_is_duplicate' "$INTAKE_CORE" \
  && grep -Fq 'annotate_reply_dedup_keys' "$INTAKE_CORE" \
  && grep -Fq 'annotate_reply_dedup_keys' "$ROOT/adapters/openclaw/distill-audit.sh" \
  && grep -Fq 'split_annotated_reply_sections' "$INTAKE_CORE" \
  && grep -Fq 'split_annotated_reply_sections' "$ROOT/adapters/openclaw/distill-audit.sh"; then
  pass '[27] both consumers call the shared annotation, splitting, and rejection machinery'
else
  fail_case '[27] both consumers call the shared annotation, splitting, and rejection machinery' 'one consumer forked fold logic'
fi

if [ -x "$0" ] && [ -x "$INTAKE" ] \
  && [ ! -x "$INTAKE_CORE" ] \
  && bash -n "$0" "$INTAKE" "$INTAKE_CORE" "$ROOT/scripts/lib-state-fold.sh" \
    "$ROOT/adapters/openclaw/distill-audit.sh" "$ROOT/scripts/deadman-probe.sh"; then
  pass '[28] suite and intake entry points are executable; touched shell files are syntax-valid'
else
  fail_case '[28] suite and intake entry points are executable; touched shell files are syntax-valid' 'suite contract is not runnable'
fi

ws=$(new_ws case-29-budget-trace)
{
  printf '%s\n' '<!-- flush ts=2026-07-15T01:02:03Z outcome=ok -->'
  i=1
  while [ "$i" -le 5 ]; do
    printf -- '- Budget candidate %s bypasses work only after the cap.\n' "$i"
    i=$((i + 1))
  done
} >"$ws/loop/pending/flush-2026-07-15.md"
dedup_trace=$TMP_ROOT/dedup-pipeline.trace
rm -f "$dedup_trace"
run_intake "$ws" INTAKE_MAX_FOLD=2 STATE_FOLD_TEST_TRACE_FILE="$dedup_trace"
if [ "$(receipt_value "$ws" candidates)" -eq 5 ] \
  && [ "$(receipt_value "$ws" deferred)" -eq 3 ] \
  && [ "$(receipt_value "$ws" folded)" -eq 2 ] \
  && [ "$(receipt_value "$ws" deduped)" -eq 0 ] \
  && [ "$(grep -Fxc annotate "$dedup_trace")" -eq 2 ] \
  && [ "$(grep -Fxc split "$dedup_trace")" -eq 2 ] \
  && [ "$(grep -Fxc dedup "$dedup_trace")" -eq 2 ] \
  && [ "$(grep -Fxc sha256 "$dedup_trace")" -eq 4 ]; then
  pass '[29] candidates after the accepted budget bypass annotate, split, hash, and dedup'
else
  fail_case '[29] candidates after the accepted budget bypass annotate, split, hash, and dedup' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log") trace=$(tr '\n' ',' <"$dedup_trace" 2>/dev/null)"
fi

ws=$(new_ws case-30-malformed-filename)
write_block "$ws/loop/pending/flush-not-a-date.md" 2026-07-15 'A malformed filename is quarantined.'
run_intake "$ws"
if [ ! -e "$ws/loop/pending/flush-not-a-date.md" ] \
  && [ -f "$ws/loop/artifacts/flush-not-a-date.malformed.md" ] \
  && grep -Fq 'flush intake quarantined malformed file loop/artifacts/flush-not-a-date.malformed.md' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" quarantined)" -eq 1 ]; then
  pass '[30] malformed flush filenames are quarantined with durable evidence'
else
  fail_case '[30] malformed flush filenames are quarantined with durable evidence' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-31-missing-section)
sed 's/^## Lessons learned.*/## Missing lessons/' "$ws/STATE.md" >"$TMP_ROOT/state-missing-lessons"
mv "$TMP_ROOT/state-missing-lessons" "$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/state-before-missing-section"
write_block "$ws/loop/pending/flush-2026-07-16.md" 2026-07-16 'Missing sections fail closed.'
set +e
run_intake "$ws"
missing_section_rc=$?
set -e
if [ "$missing_section_rc" -eq 1 ] \
  && cmp -s "$TMP_ROOT/state-before-missing-section" "$ws/STATE.md" \
  && [ -f "$ws/loop/pending/flush-2026-07-16.md" ] \
  && ! find "$ws/loop/pending" -maxdepth 1 -name 'intake-*.md' -print | grep -q . \
  && [ ! -e "$ws/loop/archive/flush-2026-07-16.md" ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ] \
  && [ "$(receipt_value "$ws" candidates)" -eq 1 ] \
  && [ "$(receipt_value "$ws" folded)" -eq 0 ] \
  && [ "$(receipt_value "$ws" error)" = missing-section ] \
  && [ "$(receipt_value "$ws" marker)" = untouched ]; then
  missing_section_failed_closed=1
else
  missing_section_failed_closed=0
fi
sed 's/^## Missing lessons/## Lessons learned - house annotation/' "$ws/STATE.md" >"$TMP_ROOT/state-restored-lessons"
mv "$TMP_ROOT/state-restored-lessons" "$ws/STATE.md"
set +e
run_intake "$ws"
annotated_section_rc=$?
set -e
if [ "$missing_section_failed_closed" -eq 1 ] \
  && [ "$annotated_section_rc" -eq 0 ] \
  && grep -Fqx '## Lessons learned - house annotation' "$ws/STATE.md" \
  && grep -Fq 'Missing sections fail closed.' "$ws/STATE.md" \
  && [ -f "$ws/loop/archive/flush-2026-07-16.md" ] \
  && [ -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[31] missing requested STATE section fails atomically and a prefix-matched annotated header folds after repair'
else
  fail_case '[31] missing requested STATE section fails atomically and a prefix-matched annotated header folds after repair' "failed_closed=$missing_section_failed_closed repair_rc=$annotated_section_rc receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

set +e
/bin/bash -uc '
  source "$1"
  if state_fold_section_allowed CANDIDATE ""; then
    exit 1
  fi
' _ "$ROOT/scripts/lib-state-fold.sh" >"$TMP_ROOT/bash32-array.out" 2>"$TMP_ROOT/bash32-array.err"
bash32_array_rc=$?
set -e
if [ "$bash32_array_rc" -eq 0 ]; then
  pass '[32] empty section-heading arrays are safe under nounset on system bash'
else
  fail_case '[32] empty section-heading arrays are safe under nounset on system bash' "rc=$bash32_array_rc error=$(tr '\n' ' ' <"$TMP_ROOT/bash32-array.err")"
fi

ws=$(new_ws case-33-byte-cap)
{
  printf '%s\n' '<!-- flush ts=2026-07-17T01:02:03Z outcome=ok -->'
  printf '%s\n' '- This short bullet remains.'
  printf '%s\n' '- This deliberately oversized bullet is much longer than the configured thirty-two-byte intake boundary.'
} >"$ws/loop/pending/flush-2026-07-17.md"
run_intake "$ws" INTAKE_MAX_BULLET_BYTES=32
if grep -Fq 'This short bullet remains.' "$ws/STATE.md" \
  && ! grep -Fq 'deliberately oversized bullet' "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" candidates)" -eq 2 ] \
  && [ "$(receipt_value "$ws" folded)" -eq 1 ] \
  && [ "$(receipt_value "$ws" dropped_oversize)" -eq 1 ]; then
  pass '[33] oversized bullets are dropped whole and counted in the receipt'
else
  fail_case '[33] oversized bullets are dropped whole and counted in the receipt' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws case-34-control-strip)
{
  printf '%s\n' '<!-- flush ts=2026-07-18T01:02:03Z outcome=ok -->'
  printf -- '- Control-byte dedup joins\000 field\007separator\034 text.\n'
} >"$ws/loop/pending/flush-2026-07-18.md"
write_block "$ws/loop/pending/flush-2026-07-19.md" 2026-07-19 \
  'Control-byte dedup joins fieldseparator text.'
run_intake "$ws"
LC_ALL=C tr -d '\000-\010\013-\037' <"$ws/STATE.md" >"$TMP_ROOT/control-free-state"
if grep -Fq 'Control-byte dedup joins fieldseparator text.' "$ws/STATE.md" \
  && [ "$(grep -Fc 'Control-byte dedup joins' "$ws/STATE.md")" -eq 1 ] \
  && [ "$(receipt_value "$ws" folded)" -eq 1 ] \
  && [ "$(receipt_value "$ws" deduped)" -eq 1 ] \
  && cmp -s "$ws/STATE.md" "$TMP_ROOT/control-free-state"; then
  pass '[34] C0 controls are stripped before FS-delimited parsing and dedup'
else
  fail_case '[34] C0 controls are stripped before FS-delimited parsing and dedup' "receipt=$(tail -n1 "$ws/loop/pending/intake-runs.log")"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
