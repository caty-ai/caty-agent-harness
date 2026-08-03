#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PROBE=$ROOT/scripts/deadman-probe.sh
WRAPPER_TEMPLATE=$ROOT/templates/cron-wrapper.tmpl.sh
TMP_ROOT=${TMPDIR:-/tmp}/deadman-probe-test.$$
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
  local ws=$TMP_ROOT/$1
  mkdir -p "$ws/loop/.deadman"
  printf '# State\n## Open failures\n## Last session\n' >"$ws/STATE.md"
  printf '%s\n' "$ws"
}

run_probe() {
  local ws=$1
  local checks=${2:-'tick:300'}
  DEADMAN_CHECKS="$checks" DEADMAN_NOTIFY_CMD="$TMP_ROOT/notify" "$PROBE" "$ws" >"$TMP_ROOT/probe.out" 2>"$TMP_ROOT/probe.err"
}

entry_count() {
  grep -Fc -- 'deadman: tick' "$1/STATE.md"
}

file_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"
}

cat >"$TMP_ROOT/notify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$NOTIFY_LOG"
EOF
chmod +x "$TMP_ROOT/notify"
export NOTIFY_LOG=$TMP_ROOT/notify.log

ws=$(new_ws fresh)
touch "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(entry_count "$ws")" -eq 0 ]; then
  pass 'fresh marker is healthy'
else
  fail_case 'fresh marker is healthy' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws stale)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && grep -Fq 'deadman: tick last run evidence (tick.marker)' "$NOTIFY_LOG" \
  && grep -Fq 'exceeds 2x cadence (600s) — scheduler silence suspected' "$NOTIFY_LOG" \
  && awk '$0 == "## Open failures" { getline; good = ($0 ~ /^- .*deadman: tick /); exit } END { exit(good ? 0 : 1) }' "$ws/STATE.md"; then
  pass 'stale marker fires and notifies'
else
  fail_case 'stale marker fires and notifies' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws future)
# Deliberately distant fixture so this remains future-dated through year 2099.
touch -t 209901010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(entry_count "$ws")" -eq 0 ]; then
  pass 'future marker is healthy'
else
  fail_case 'future marker is healthy' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws idempotent)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; first_rc=$?
run_probe "$ws"; second_rc=$?
if [ "$first_rc" -eq 1 ] && [ "$second_rc" -eq 0 ] && [ "$(entry_count "$ws")" -eq 1 ]; then
  pass 'stale marker is reported once'
else
  fail_case 'stale marker is reported once' "rcs=$first_rc/$second_rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws recovery)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; first_rc=$?
touch "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; healthy_rc=$?
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; second_rc=$?
if [ "$first_rc" -eq 1 ] && [ "$healthy_rc" -eq 0 ] && [ "$second_rc" -eq 1 ] \
  && [ "$(entry_count "$ws")" -eq 2 ]; then
  pass 'recovery allows a new silence episode'
else
  fail_case 'recovery allows a new silence episode' "rcs=$first_rc/$healthy_rc/$second_rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws stale-sentinel)
touch -t 202001010005 "$ws/loop/.deadman/tick.marker"
: >"$ws/loop/.deadman/tick.fired"
touch -t 202001010000 "$ws/loop/.deadman/tick.fired"
: >"$NOTIFY_LOG"
run_probe "$ws" 'tick:60'; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && grep -Fq 'deadman: tick last run evidence (tick.marker)' "$NOTIFY_LOG"; then
  pass 'stale sentinel from prior episode fires again'
else
  fail_case 'stale sentinel from prior episode fires again' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws equal-mtime-sentinel)
touch -t 202001010005 "$ws/loop/.deadman/tick.marker"
: >"$ws/loop/.deadman/tick.fired"
touch -t 202001010005 "$ws/loop/.deadman/tick.fired"
: >"$NOTIFY_LOG"
run_probe "$ws" 'tick:60'; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && grep -Fq 'deadman: tick last run evidence (tick.marker)' "$NOTIFY_LOG"; then
  pass 'equal-mtime sentinel is retried'
else
  fail_case 'equal-mtime sentinel is retried' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws crash-after-claim)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
: >"$ws/loop/.deadman/tick.fired"
touch -t 201901010000 "$ws/loop/.deadman/tick.fired"
: >"$NOTIFY_LOG"
DEADMAN_CHECKS='tick:60' DEADMAN_NOTIFY_CMD="$TMP_ROOT/notify" DEADMAN_TEST_CRASH_AFTER_CLAIM=1 "$PROBE" "$ws" >"$TMP_ROOT/probe.out" 2>"$TMP_ROOT/probe.err"; crash_rc=$?
crash_sentinel_absent=0
[ ! -e "$ws/loop/.deadman/tick.fired" ] && crash_sentinel_absent=1
run_probe "$ws" 'tick:60'; retry_rc=$?
if [ "$crash_rc" -eq 1 ] && [ "$crash_sentinel_absent" -eq 1 ] \
  && [ "$retry_rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && grep -Fq 'deadman: tick last run evidence (tick.marker)' "$NOTIFY_LOG"; then
  pass 'crash after claim retries without a sentinel'
else
  fail_case 'crash after claim retries without a sentinel' "rcs=$crash_rc/$retry_rc sentinel_absent=$crash_sentinel_absent"
fi

ws=$(new_ws awk-partial-failure)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
cp "$ws/STATE.md" "$TMP_ROOT/state-before"
mkdir -p "$TMP_ROOT/awk-shim-dir"
cat >"$TMP_ROOT/awk-shim-dir/awk" <<'EOF'
#!/usr/bin/env bash
printf 'partial output\n'
exit 1
EOF
chmod +x "$TMP_ROOT/awk-shim-dir/awk"
: >"$NOTIFY_LOG"
PATH="$TMP_ROOT/awk-shim-dir:$PATH" DEADMAN_CHECKS='tick:60' DEADMAN_NOTIFY_CMD="$TMP_ROOT/notify" "$PROBE" "$ws" >"$TMP_ROOT/probe.out" 2>"$TMP_ROOT/probe.err"; awk_rc=$?
awk_unchanged=0
cmp -s "$TMP_ROOT/state-before" "$ws/STATE.md" && awk_unchanged=1
awk_sentinel_absent=0
[ ! -e "$ws/loop/.deadman/tick.fired" ] && awk_sentinel_absent=1
awk_notify_count=0
[ -f "$NOTIFY_LOG" ] && awk_notify_count=$(wc -l <"$NOTIFY_LOG" | tr -d '[:space:]')
run_probe "$ws" 'tick:60'; awk_retry_rc=$?
if [ "$awk_rc" -eq 1 ] && [ "$awk_unchanged" -eq 1 ] \
  && [ "$awk_notify_count" -ge 1 ] \
  && [ "$awk_sentinel_absent" -eq 1 ] && [ "$awk_retry_rc" -eq 1 ] \
  && [ "$(entry_count "$ws")" -eq 1 ]; then
  pass 'awk failure preserves state and retries'
else
  fail_case 'awk failure preserves state and retries' "rcs=$awk_rc/$awk_retry_rc unchanged=$awk_unchanged"
fi

ws=$(new_ws abandoned-lock)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
mkdir "$ws/loop/.deadman/.state.lock"
touch -t 202001010000 "$ws/loop/.deadman/.state.lock"
run_probe "$ws" 'tick:60'; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ]; then
  pass 'abandoned state lock is reclaimed'
else
  fail_case 'abandoned state lock is reclaimed' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws bootstrap)
run_probe "$ws"; first_rc=$?
baseline=$ws/loop/.deadman/tick.baseline
touch -t 202001010000 "$baseline"
run_probe "$ws"; second_rc=$?
if [ "$first_rc" -eq 0 ] && [ -f "$baseline" ] && [ "$second_rc" -eq 1 ]; then
  pass 'missing marker bootstraps before firing'
else
  fail_case 'missing marker bootstraps before firing' "rcs=$first_rc/$second_rc baseline=$([ -f "$baseline" ] && printf yes || printf no)"
fi

target=$TMP_ROOT/target
cat >"$target" <<'EOF'
#!/usr/bin/env bash
if [[ -e "$PROBE_LOG" ]]; then
  printf 'yes\n' >"$TARGET_SAW_PROBE"
else
  printf 'no\n' >"$TARGET_SAW_PROBE"
fi
printf 'ran\n' >>"$TARGET_LOG"
EOF
chmod +x "$target"
wrapper=$TMP_ROOT/cron-wrapper.sh
cp "$WRAPPER_TEMPLATE" "$wrapper"
chmod +x "$wrapper"
export TARGET_LOG=$TMP_ROOT/target.log
marker=$TMP_ROOT/wrapper/.deadman/tick.marker
probe_fail=$TMP_ROOT/probe-fail
cat >"$probe_fail" <<'EOF'
#!/usr/bin/env bash
printf 'ran\n' >>"$PROBE_LOG"
if [[ -f "$MARKER_TO_CHECK" ]]; then
  printf 'yes\n' >"$PROBE_SAW_MARKER"
else
  printf 'no\n' >"$PROBE_SAW_MARKER"
fi
exit 1
EOF
chmod +x "$probe_fail"
export PROBE_LOG=$TMP_ROOT/probe.log
export PROBE_SAW_MARKER=$TMP_ROOT/probe-saw-marker
export TARGET_SAW_PROBE=$TMP_ROOT/target-saw-probe
export MARKER_TO_CHECK=$marker
wrapper_ws=$(new_ws wrapper-guard)
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  DEADMAN_MARKER="$marker" DEADMAN_PROBE="$probe_fail" "$wrapper"; wrapper_rc=$?
marker_age=$(( $(date +%s) - $(file_mtime "$marker") ))
if [ "$wrapper_rc" -eq 0 ] && [ -f "$marker" ] && [ "$marker_age" -le 60 ] \
  && [ -f "$PROBE_LOG" ] && [ "$(cat "$PROBE_SAW_MARKER")" = yes ] \
  && [ "$(cat "$TARGET_SAW_PROBE")" = yes ] \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 1 ]; then
  pass 'wrapper marks before probe and ignores probe failures'
else
  fail_case 'wrapper marks before probe and ignores probe failures' "rc=$wrapper_rc"
fi

secrets=$TMP_ROOT/secrets-env
printf 'DEADMAN_MARKER=relative/x\n' >"$secrets"
chmod 600 "$secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; secrets_rc=$?
if [ "$secrets_rc" -eq 3 ] && grep -Fq 'DEADMAN_MARKER must be an absolute path: relative/x' "$TMP_ROOT/wrapper.err"; then
  pass 'secrets overrides are revalidated'
else
  fail_case 'secrets overrides are revalidated' "rc=$secrets_rc"
fi

ws=$(new_ws malformed-checks)
run_probe "$ws" 'tick:abc'; rc=$?
if [ "$rc" -eq 2 ] && [ "$(entry_count "$ws")" -eq 0 ]; then
  pass 'malformed checks do not append failures'
else
  fail_case 'malformed checks do not append failures' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws overflow-cadence)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws" 'tick:9223372036854775807'; rc=$?
if [ "$rc" -eq 2 ] && [ "$(entry_count "$ws")" -eq 0 ]; then
  pass 'overflow cadence is malformed'
else
  fail_case 'overflow cadence is malformed' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws partial-violation)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
touch "$ws/loop/.deadman/distill.marker"
run_probe "$ws" 'tick:60 distill:60'; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && ! grep -Fq 'deadman: distill' "$ws/STATE.md" \
  && [ ! -e "$ws/loop/.deadman/distill.fired" ]; then
  pass 'partial violation fires only stale check'
else
  fail_case 'partial violation fires only stale check' "rc=$rc tick_entries=$(entry_count "$ws")"
fi

ws=$(new_ws missing-open-failures)
printf '# State\n## Last session\n' >"$ws/STATE.md"
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
run_probe "$ws"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(grep -Fc -- '## Open failures' "$ws/STATE.md")" -eq 1 ] \
  && grep -Fq 'deadman: tick last run evidence (tick.marker)' "$ws/STATE.md" \
  && awk '$0 == "## Open failures" { getline; good = ($0 ~ /^- .*deadman: tick /); exit } END { exit(good ? 0 : 1) }' "$ws/STATE.md"; then
  pass 'missing open failures heading is appended once'
else
  fail_case 'missing open failures heading is appended once' "rc=$rc headings=$(grep -Fc -- '## Open failures' "$ws/STATE.md")"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
