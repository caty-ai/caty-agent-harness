#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/adapters/hermes/stale-claim-watchdog.sh
TMP_ROOT=${TMPDIR:-/tmp}/stale-claim-watchdog-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

FAKE_BIN=$TMP_ROOT/fake-bin
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'if [ "$#" -eq 1 ] && [ "$1" = "+%s" ]; then'
  printf '%s\n' '  printf "%s\n" "${FAKE_NOW_EPOCH:?}"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'exec /bin/date "$@"'
} >"$FAKE_BIN/date"
chmod +x "$FAKE_BIN/date"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

make_ws() {
  ws=$TMP_ROOT/ws-$1
  mkdir -p "$ws/loop/pending"
  printf '# State\n' >"$ws/STATE.md"
  printf '%s\n' "$ws"
}

write_cmd_stub() {
  path=$1
  out=$2
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$1" >>"%s"\n' "$out"
  } >"$path"
  chmod +x "$path"
}

write_list_cmd_stub() {
  path=$1
  args_log=$2
  heartbeat=$3
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$@" >"%s"\n' "$args_log"
    printf 'printf "job-from-command\\tclaimed\\t%s\\t1\\t3\\n"\n' "$heartbeat"
  } >"$path"
  chmod +x "$path"
}

now=$(date '+%s')
old=$((now - 7200))
fresh=$((now - 60))
ledger=$TMP_ROOT/ledger.tsv
{
  printf 'job-requeue\tclaimed\t%s\t1\t3\n' "$old"
  printf 'job-dlq\tclaimed\t%s\t3\t3\n' "$old"
  printf 'job-fresh\tclaimed\t%s\t0\t3\n' "$fresh"
  printf 'job-waiting\tqueued\t%s\t0\t3\n' "$old"
} >"$ledger"

ws=$(make_ws dry-run)
requeue_log=$TMP_ROOT/requeue.dry.log
dlq_log=$TMP_ROOT/dlq.dry.log
write_cmd_stub "$TMP_ROOT/requeue-dry.sh" "$requeue_log"
write_cmd_stub "$TMP_ROOT/dlq-dry.sh" "$dlq_log"
output=$(WATCHDOG_STALE_SECS=3600 WATCHDOG_REQUEUE_CMD="$TMP_ROOT/requeue-dry.sh" WATCHDOG_DLQ_CMD="$TMP_ROOT/dlq-dry.sh" bash "$SCRIPT" --workspace "$ws" --ledger-file "$ledger" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'would requeue: job-requeue' \
  && printf '%s\n' "$output" | grep -q 'would dlq: job-dlq' \
  && ! printf '%s\n' "$output" | grep -q 'job-fresh' \
  && [ ! -e "$requeue_log" ] \
  && [ ! -e "$dlq_log" ] \
  && ! find "$ws/loop/pending" -type f -name 'watchdog-*.md' -print | grep -q .; then
  pass "dry-run reports actions without side effects"
else
  fail_case "dry-run reports actions without side effects" "rc=$rc output=$output"
fi

ws=$(make_ws live)
requeue_log=$TMP_ROOT/requeue.live.log
dlq_log=$TMP_ROOT/dlq.live.log
write_cmd_stub "$TMP_ROOT/requeue-live.sh" "$requeue_log"
write_cmd_stub "$TMP_ROOT/dlq-live.sh" "$dlq_log"
output=$(WATCHDOG_STALE_SECS=3600 WATCHDOG_REQUEUE_CMD="$TMP_ROOT/requeue-live.sh" WATCHDOG_DLQ_CMD="$TMP_ROOT/dlq-live.sh" bash "$SCRIPT" --workspace "$ws" --ledger-file "$ledger" 2>&1)
rc=$?
pending_file=$(find "$ws/loop/pending" -type f -name 'watchdog-*.md' -print | head -n 1)
if [ "$rc" -eq 0 ] \
  && [ -f "$pending_file" ] \
  && grep -Fqx 'job-requeue' "$requeue_log" \
  && grep -Fqx 'job-dlq' "$dlq_log" \
  && ! grep -q 'job-fresh' "$requeue_log" "$dlq_log" "$pending_file" \
  && grep -q 'stale claim job-requeue heartbeat_age=' "$pending_file" \
  && grep -q 'action=requeue (source: stale-claim-watchdog)' "$pending_file" \
  && grep -q 'stale claim job-dlq heartbeat_age=' "$pending_file" \
  && grep -q 'action=dlq (source: stale-claim-watchdog)' "$pending_file"; then
  pass "live run calls actions and appends pending lines"
else
  fail_case "live run calls actions and appends pending lines" "rc=$rc output=$output pending=$pending_file"
fi

output=$(WATCHDOG_STALE_SECS=3600 WATCHDOG_REQUEUE_CMD="$TMP_ROOT/requeue-live.sh" WATCHDOG_DLQ_CMD="$TMP_ROOT/dlq-live.sh" bash "$SCRIPT" --workspace "$ws" --ledger-file "$ledger" 2>&1)
rc=$?
requeue_lines=$(grep -c 'stale claim job-requeue heartbeat_age=' "$pending_file")
if [ "$rc" -eq 0 ] && [ "$requeue_lines" -eq 1 ]; then
  pass "rerun does not duplicate pending lines for a still-stale job"
else
  fail_case "rerun does not duplicate pending lines for a still-stale job" "rc=$rc requeue_lines=$requeue_lines"
fi

ws=$(make_ws octal)
ledger_octal=$TMP_ROOT/ledger-octal.tsv
{
  printf 'job-octal\tclaimed\t0%s\t1\t3\n' "$old"
  printf 'job-after\tclaimed\t%s\t1\t3\n' "$old"
} >"$ledger_octal"
output=$(WATCHDOG_STALE_SECS=3600 bash "$SCRIPT" --workspace "$ws" --ledger-file "$ledger_octal" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'would requeue: job-octal' \
  && printf '%s\n' "$output" | grep -q 'would requeue: job-after'; then
  pass "leading-zero heartbeat does not abort the scan"
else
  fail_case "leading-zero heartbeat does not abort the scan" "rc=$rc output=$output"
fi

fixed_now=2000000000
ws=$(make_ws list-command-source)
list_args_log=$TMP_ROOT/list-command.args
list_args_expected=$TMP_ROOT/list-command.args.expected
list_cmd=$TMP_ROOT/list-command.sh
write_list_cmd_stub "$list_cmd" "$list_args_log" "$((fixed_now - 3601))"
printf '%s\n' alpha beta >"$list_args_expected"
output=$(FAKE_NOW_EPOCH=$fixed_now PATH="$FAKE_BIN:$PATH" WATCHDOG_STALE_SECS=3600 \
  AGJOB_LIST_CMD="$list_cmd alpha beta" bash "$SCRIPT" --workspace "$ws" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && cmp -s "$list_args_expected" "$list_args_log" \
  && printf '%s\n' "$output" | grep -Fqx 'would requeue: job-from-command'; then
  pass "AGJOB_LIST_CMD source splits argv and captures stdout ledger"
else
  fail_case "AGJOB_LIST_CMD source splits argv and captures stdout ledger" \
    "rc=$rc output=$output args=$(tr '\n' ' ' <"$list_args_log" 2>/dev/null)"
fi

ws=$(make_ws stale-boundary)
boundary_ledger=$TMP_ROOT/ledger-boundary.tsv
{
  printf 'job-threshold-minus-one\tclaimed\t%s\t1\t3\n' "$((fixed_now - 3599))"
  printf 'job-threshold-exact\tclaimed\t%s\t1\t3\n' "$((fixed_now - 3600))"
  printf 'job-threshold-plus-one\tclaimed\t%s\t1\t3\n' "$((fixed_now - 3601))"
} >"$boundary_ledger"
output=$(FAKE_NOW_EPOCH=$fixed_now PATH="$FAKE_BIN:$PATH" WATCHDOG_STALE_SECS=3600 \
  bash "$SCRIPT" --workspace "$ws" --ledger-file "$boundary_ledger" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && ! printf '%s\n' "$output" | grep -Fq 'job-threshold-minus-one' \
  && ! printf '%s\n' "$output" | grep -Fq 'job-threshold-exact' \
  && printf '%s\n' "$output" | grep -Fqx 'would requeue: job-threshold-plus-one'; then
  pass "stale threshold excludes ages stale_secs -1 and exact, includes +1"
else
  fail_case "stale threshold excludes ages stale_secs -1 and exact, includes +1" \
    "rc=$rc output=$output"
fi

ws=$(make_ws zero-threshold)
zero_ledger=$TMP_ROOT/ledger-zero-threshold.tsv
{
  printf 'job-zero-age\tclaimed\t%s\t1\t3\n' "$fixed_now"
  printf 'job-one-second-old\tclaimed\t%s\t1\t3\n' "$((fixed_now - 1))"
} >"$zero_ledger"
output=$(FAKE_NOW_EPOCH=$fixed_now PATH="$FAKE_BIN:$PATH" WATCHDOG_STALE_SECS=0 \
  bash "$SCRIPT" --workspace "$ws" --ledger-file "$zero_ledger" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && ! printf '%s\n' "$output" | grep -Fq 'job-zero-age' \
  && printf '%s\n' "$output" | grep -Fqx 'would requeue: job-one-second-old'; then
  pass "WATCHDOG_STALE_SECS=0 keeps age zero and flags age one"
else
  fail_case "WATCHDOG_STALE_SECS=0 keeps age zero and flags age one" "rc=$rc output=$output"
fi

ws=$(make_ws bad-list-cmd)
set +e
output=$(WATCHDOG_STALE_SECS=3600 AGJOB_LIST_CMD="$TMP_ROOT/missing-list.sh" bash "$SCRIPT" --workspace "$ws" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] && printf '%s\n' "$output" | grep -q 'AGJOB_LIST_CMD not found'; then
  pass "invalid list command exits infra error"
else
  fail_case "invalid list command exits infra error" "rc=$rc output=$output"
fi

ws=$(make_ws bad-action-cmd)
set +e
output=$(WATCHDOG_STALE_SECS=3600 WATCHDOG_REQUEUE_CMD="$TMP_ROOT/missing-requeue.sh" bash "$SCRIPT" --workspace "$ws" --ledger-file "$ledger" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] && printf '%s\n' "$output" | grep -q 'WATCHDOG_REQUEUE_CMD not found'; then
  pass "invalid action command exits infra error"
else
  fail_case "invalid action command exits infra error" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
