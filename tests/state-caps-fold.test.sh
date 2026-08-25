#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INTAKE=$ROOT/adapters/claude-code/flush-intake.sh
TMP_ROOT=${TMPDIR:-/tmp}/state-caps-fold-test.$$
PASS_COUNT=0
FAIL_COUNT=0
TODAY=$(date -u '+%Y-%m-%d')

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
  printf '%s\n' "$ws"
}

run_intake() {
  local ws=$1
  env INTAKE_LOCK_SLEEP_S=0 "$INTAKE" "$ws" \
    >"$TMP_ROOT/intake.out" 2>"$TMP_ROOT/intake.err"
}

receipt_value() {
  local ws=$1
  local key=$2
  tail -n 1 "$ws/loop/pending/intake-runs.log" | tr ' ' '\n' \
    | sed -n "s/^$key=//p" | head -n 1
}

write_state() {
  local path=$1
  local verified_count=$2
  local rules_count=$3
  local with_preamble=${4:-0}
  local i

  {
    printf '%s\n' '## Verified facts      (cap 120 lines)'
    if [ "$with_preamble" -eq 1 ]; then
      printf '%s\n' '<!-- verified preamble must never count or move -->'
    fi
    i=1
    while [ "$i" -le "$verified_count" ]; do
      printf -- '- verified-%03d\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' '## General rules       (cap 80)'
    if [ "$with_preamble" -eq 1 ]; then
      printf '%s\n' '<!-- rules preamble must never count or move -->'
    fi
    i=1
    while [ "$i" -le "$rules_count" ]; do
      printf -- '- rule-%03d\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' \
      '## Open failures       (cap 100)' \
      '<!-- failures preamble -->' \
      '## Lessons learned     (cap 60)' \
      '<!-- lessons preamble -->' \
      '## Last session        (cap 20 entries — newest first)' \
      '<!-- last-session preamble -->'
  } >"$path"
}

body_count() {
  local path=$1
  local heading=$2
  awk -v heading="$heading" '
    index($0, heading) == 1 {in_section = 1; preamble = 1; next}
    in_section && /^## / {exit}
    in_section {
      if (preamble && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*<!--.*-->[[:space:]]*$/)) next
      preamble = 0
      count++
    }
    END {print count + 0}
  ' "$path"
}

ws=$(new_ws exact-boundary)
write_state "$ws/STATE.md" 120 80 1
cp "$ws/STATE.md" "$TMP_ROOT/exact.before"
run_intake "$ws"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
if cmp -s "$TMP_ROOT/exact.before" "$ws/STATE.md" \
  && [ ! -e "$archive" ] \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 0 ] \
  && [ "$(receipt_value "$ws" caps_gr_evicted)" -eq 0 ] \
  && [ "$(receipt_value "$ws" caps_fold)" = ok ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = none ]; then
  pass '[1] exact cap boundaries leave STATE byte-identical'
else
  fail_case '[1] exact cap boundaries leave STATE byte-identical' \
    "receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws verified-overflow)
write_state "$ws/STATE.md" 121 80 1
printf '%s\n' '- verified-001' >"$TMP_ROOT/verified.evicted.expected"
run_intake "$ws"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
tail -n +2 "$archive" >"$TMP_ROOT/verified.evicted.actual"
if [ "$(receipt_value "$ws" files_scanned)" -eq 0 ] \
  && [ "$(body_count "$ws/STATE.md" '## Verified facts')" -eq 120 ] \
  && [ "$(body_count "$ws/STATE.md" '## General rules')" -eq 80 ] \
  && ! grep -Fqx -- '- verified-001' "$ws/STATE.md" \
  && grep -Fqx -- '- verified-121' "$ws/STATE.md" \
  && grep -Fqx -- '<!-- verified preamble must never count or move -->' "$ws/STATE.md" \
  && ! grep -Fq 'preamble must never count or move' "$archive" \
  && cmp -s "$TMP_ROOT/verified.evicted.expected" "$TMP_ROOT/verified.evicted.actual" \
  && grep -Eq '^<!-- caps eviction section=verified-facts adapter=[^ ]+ ts=[^ ]+ -->$' "$archive" \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 1 ]; then
  pass '[2] cap+1 evicts the oldest body line verbatim and zero-candidate intake still folds'
else
  fail_case '[2] cap+1 evicts the oldest body line verbatim and zero-candidate intake still folds' \
    "receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log") archive=$(cat "$archive" 2>/dev/null)"
fi

if [ "$(wc -c <"$archive" | tr -d '[:space:]')" -gt 0 ] \
  && [ "$(body_count "$ws/STATE.md" '## Verified facts')" -eq 120 ]; then
  pass '[3] mutation guard requires both STATE shrinkage and archive growth'
else
  fail_case '[3] mutation guard requires both STATE shrinkage and archive growth' \
    'oversized STATE did not shrink with a recoverable archive append'
fi

ws=$(new_ws both-overflow)
write_state "$ws/STATE.md" 122 82 1
run_intake "$ws"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
if [ "$(body_count "$ws/STATE.md" '## Verified facts')" -eq 120 ] \
  && [ "$(body_count "$ws/STATE.md" '## General rules')" -eq 80 ] \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 2 ] \
  && [ "$(receipt_value "$ws" caps_gr_evicted)" -eq 2 ] \
  && [ "$(grep -c '^<!-- caps eviction section=verified-facts ' "$archive")" -eq 1 ] \
  && [ "$(grep -c '^<!-- caps eviction section=general-rules ' "$archive")" -eq 1 ] \
  && grep -Fqx -- '- verified-001' "$archive" \
  && grep -Fqx -- '- verified-002' "$archive" \
  && grep -Fqx -- '- rule-001' "$archive" \
  && grep -Fqx -- '- rule-002' "$archive"; then
  pass '[4] one fold archives both overflows under distinct section markers'
else
  fail_case '[4] one fold archives both overflows under distinct section markers' \
    "receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws missing-section)
write_state "$ws/STATE.md" 121 80 1
awk 'index($0, "## Verified facts") != 1 {print}' "$ws/STATE.md" \
  >"$TMP_ROOT/missing.state"
mv "$TMP_ROOT/missing.state" "$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/missing.before"
run_intake "$ws"
rc=$?
if [ "$rc" -eq 0 ] \
  && cmp -s "$TMP_ROOT/missing.before" "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" caps_fold)" = skipped ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = missing-verified-facts ] \
  && [ "$(receipt_value "$ws" files_scanned)" -eq 0 ] \
  && [ -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[5] a missing capped heading records SKIP and intake continues without touching STATE'
else
  fail_case '[5] a missing capped heading records SKIP and intake continues without touching STATE' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws archive-failure)
write_state "$ws/STATE.md" 121 80 0
cp "$ws/STATE.md" "$TMP_ROOT/archive-failure.before"
chmod 500 "$ws/loop/archive"
run_intake "$ws"
rc=$?
chmod 700 "$ws/loop/archive"
if [ "$rc" -ne 0 ] \
  && cmp -s "$TMP_ROOT/archive-failure.before" "$ws/STATE.md" \
  && [ ! -e "$ws/loop/archive/intake-evictions-$TODAY.md" ] \
  && [ "$(receipt_value "$ws" caps_fold)" = failed ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = archive-append ] \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 0 ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[6] real archive write failure aborts before the STATE rename'
else
  fail_case '[6] real archive write failure aborts before the STATE rename' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
