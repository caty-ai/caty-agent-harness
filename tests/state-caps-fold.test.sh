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

run_intake_with_cat_failure() {
  local ws=$1
  local shim_dir=$2
  local mode=${3:-fail}
  env INTAKE_LOCK_SLEEP_S=0 STATE_CAPS_REAL_CAT="$REAL_CAT" \
    STATE_CAPS_CAT_MODE="$mode" \
    PATH="$shim_dir:$PATH" "$INTAKE" "$ws" \
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

ws=$(new_ws mutation-guard)
write_state "$ws/STATE.md" 121 80 1
run_intake "$ws"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
archive_bytes=0
if [ -f "$archive" ]; then
  archive_bytes=$(wc -c <"$archive" | tr -d '[:space:]')
fi
if [ "$archive_bytes" -gt 0 ] \
  && [ "$(body_count "$ws/STATE.md" '## Verified facts')" -eq 120 ]; then
  pass '[3] mutation guard requires both STATE shrinkage and archive growth'
else
  fail_case '[3] mutation guard requires both STATE shrinkage and archive growth' \
    'oversized STATE did not shrink with a recoverable archive append'
fi

ws=$(new_ws duplicate-heading)
write_state "$ws/STATE.md" 121 80 1
awk '
  index($0, "## General rules") == 1 && !inserted {
    print "## Verified facts      (cap 120 lines)"
    for (i = 1; i <= 121; i++) printf "- duplicate-verified-%03d\n", i
    inserted = 1
  }
  {print}
' "$ws/STATE.md" >"$TMP_ROOT/duplicate.state"
mv "$TMP_ROOT/duplicate.state" "$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/duplicate.before"
run_intake "$ws"
rc=$?
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
if [ "$rc" -eq 0 ] \
  && cmp -s "$TMP_ROOT/duplicate.before" "$ws/STATE.md" \
  && [ ! -e "$archive" ] \
  && [ "$(receipt_value "$ws" caps_fold)" = skipped ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = duplicate-heading ] \
  && [ "$(receipt_value "$ws" files_scanned)" -eq 0 ] \
  && [ -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[7] duplicate capped headings skip the fold without touching STATE or archive'
else
  fail_case '[7] duplicate capped headings skip the fold without touching STATE or archive' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

raw_ws=$(new_ws multi-flush)
write_state "$raw_ws/STATE.md" 121 80 0
awk '
  index($0, "## General rules") == 1 && !inserted {
    print "## Verified facts      (cap 120 lines)"
    for (i = 1; i <= 121; i++) printf "- duplicate-verified-%03d\n", i
    inserted = 1
  }
  {print}
' "$raw_ws/STATE.md" >"$TMP_ROOT/multi-flush.state"
mv "$TMP_ROOT/multi-flush.state" "$raw_ws/STATE.md"
raw_work="$TMP_ROOT/multi-flush-work"
raw_reason="$TMP_ROOT/multi-flush.reason"
mkdir -p "$raw_work"
if bash -c '
  source "$1"
  if fold_declared_state_caps "$2" "$3" "$4" test-adapter "$5"; then
    rc=0
  else
    rc=$?
  fi
  printf "%s\n" "$STATE_CAPS_FOLD_REASON" >"$6"
  exit "$rc"
' _ "$ROOT/scripts/lib-state-fold.sh" "$raw_ws" "$raw_ws/STATE.md" "$raw_work" \
  "$TODAY" "$raw_reason"; then
  raw_rc=0
else
  raw_rc=$?
fi
STATE_CAPS_FOLD_REASON=$(cat "$raw_reason")
if [ "$(wc -l <"$raw_work/state-caps.verified" | tr -d '[:space:]')" -eq 2 ] \
  && grep -Fqx -- '- verified-001' "$raw_work/state-caps.verified" \
  && grep -Fqx -- '- duplicate-verified-001' "$raw_work/state-caps.verified"; then
  pass '[8] sequential eviction flushes append without losing earlier lines'
else
  fail_case '[8] sequential eviction flushes append without losing earlier lines' \
    "rc=$raw_rc reason=$STATE_CAPS_FOLD_REASON payload=$(tr '\n' '|' <"$raw_work/state-caps.verified" 2>/dev/null)"
fi

ws=$(new_ws archive-target-directory)
write_state "$ws/STATE.md" 121 80 0
cp "$ws/STATE.md" "$TMP_ROOT/archive-target.before"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
mkdir "$archive"
run_intake "$ws"
rc=$?
if [ "$rc" -ne 0 ] \
  && cmp -s "$TMP_ROOT/archive-target.before" "$ws/STATE.md" \
  && [ -d "$archive" ] \
  && [ -z "$(find "$archive" -mindepth 1 -print -quit)" ] \
  && [ "$(receipt_value "$ws" caps_fold)" = failed ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = archive-target ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[9] a directory at the archive path fails before the STATE rename'
else
  fail_case '[9] a directory at the archive path fails before the STATE rename' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

REAL_CAT=$(command -v cat)
cat_shim="$TMP_ROOT/cat-shim"
mkdir -p "$cat_shim"
cat >"$cat_shim/cat" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  */state-caps.verified)
    [ "${STATE_CAPS_CAT_MODE:-fail}" = drop ] && exit 0
    exit 73
    ;;
esac
exec "$STATE_CAPS_REAL_CAT" "$@"
EOF
chmod 755 "$cat_shim/cat"

ws=$(new_ws archive-payload-failure)
write_state "$ws/STATE.md" 121 80 0
cp "$ws/STATE.md" "$TMP_ROOT/archive-payload.before"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
run_intake_with_cat_failure "$ws" "$cat_shim"
rc=$?
if [ "$rc" -ne 0 ] \
  && cmp -s "$TMP_ROOT/archive-payload.before" "$ws/STATE.md" \
  && grep -Fqx -- '- verified-001' "$ws/STATE.md" \
  && [ ! -e "$archive" ] \
  && [ "$(receipt_value "$ws" caps_fold)" = failed ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = archive-payload ] \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 0 ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[10] archive payload append failure aborts before the STATE rename'
else
  fail_case '[10] archive payload append failure aborts before the STATE rename' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws archive-integrity-failure)
write_state "$ws/STATE.md" 121 80 0
cp "$ws/STATE.md" "$TMP_ROOT/archive-integrity.before"
archive="$ws/loop/archive/intake-evictions-$TODAY.md"
run_intake_with_cat_failure "$ws" "$cat_shim" drop
rc=$?
if [ "$rc" -ne 0 ] \
  && cmp -s "$TMP_ROOT/archive-integrity.before" "$ws/STATE.md" \
  && grep -Fqx -- '- verified-001' "$ws/STATE.md" \
  && [ -f "$archive" ] \
  && [ "$(receipt_value "$ws" caps_fold)" = failed ] \
  && [ "$(receipt_value "$ws" caps_fold_reason)" = archive-integrity ] \
  && [ "$(receipt_value "$ws" caps_vf_evicted)" -eq 0 ] \
  && [ ! -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[11] archived line-count mismatch aborts before the STATE rename'
else
  fail_case '[11] archived line-count mismatch aborts before the STATE rename' \
    "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
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
