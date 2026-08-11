#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PROBE=$ROOT/scripts/deadman-probe.sh
WRAPPER_TEMPLATE=$ROOT/templates/cron-wrapper.tmpl.sh
LAUNCHD_TEMPLATE=$ROOT/templates/launchd.tmpl.plist
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

age_file_seconds() {
  local path=$1
  local seconds=$2

  if touch -d "$seconds seconds ago" "$path" 2>/dev/null; then
    return 0
  fi
  touch -t "$(date -v-"${seconds}"S '+%Y%m%d%H%M.%S')" "$path"
}

default_checks=$(awk -F"'" '/^checks=\$\{DEADMAN_CHECKS:-/ { print $2; exit }' "$PROBE")
template_markers=$(grep -Eho '\.deadman/[A-Za-z0-9._-]+' "$WRAPPER_TEMPLATE" "$LAUNCHD_TEMPLATE" | sort -u)
marker_contract_ok=1
marker_contract_detail=
if [ -z "$default_checks" ]; then
  marker_contract_ok=0
  marker_contract_detail='could not extract probe defaults'
fi
for check in $default_checks; do
  check_name=${check%%:*}
  expected_marker=".deadman/$check_name.marker"
  if ! grep -Fqx "$expected_marker" <<<"$template_markers"; then
    marker_contract_ok=0
    marker_contract_detail="missing $expected_marker"
    break
  fi
  while IFS= read -r template_marker; do
    case "$template_marker" in
      "$expected_marker") ;;
      ".deadman/$check_name"*)
        marker_contract_ok=0
        marker_contract_detail="unexpected $template_marker for $check_name"
        break 2
        ;;
    esac
  done <<<"$template_markers"
done
if [ "$marker_contract_ok" -eq 1 ]; then
  pass 'template marker guidance matches probe defaults'
else
  fail_case 'template marker guidance matches probe defaults' "$marker_contract_detail"
fi

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
awk_sentinel_present=0
[ -e "$ws/loop/.deadman/tick.fired" ] && awk_sentinel_present=1
awk_notify_count=0
[ -f "$NOTIFY_LOG" ] && awk_notify_count=$(wc -l <"$NOTIFY_LOG" | tr -d '[:space:]')
run_probe "$ws" 'tick:60'; awk_retry_rc=$?
if [ "$awk_rc" -eq 1 ] && [ "$awk_unchanged" -eq 1 ] \
  && [ "$awk_notify_count" -eq 1 ] \
  && [ "$awk_sentinel_present" -eq 1 ] && [ "$awk_retry_rc" -eq 0 ] \
  && [ "$(entry_count "$ws")" -eq 1 ] \
  && [ "$(wc -l <"$NOTIFY_LOG" | tr -d '[:space:]')" -eq 1 ] \
  && [ ! -e "$ws/loop/.deadman/tick.append-pending" ]; then
  pass 'append failure notifies once and retries without another notification'
else
  fail_case 'awk failure preserves state and retries' "rcs=$awk_rc/$awk_retry_rc unchanged=$awk_unchanged"
fi

ws=$(new_ws abandoned-lock)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
mkdir "$ws/loop/.distill-state.lock"
touch -t 202001010000 "$ws/loop/.distill-state.lock"
run_probe "$ws" 'tick:60'; rc=$?
if [ "$rc" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ]; then
  pass 'abandoned shared state lock is reclaimed'
else
  fail_case 'abandoned shared state lock is reclaimed' "rc=$rc entries=$(entry_count "$ws")"
fi

ws=$(new_ws sub-stale-lock)
touch -t 202001010000 "$ws/loop/.deadman/tick.marker"
mkdir "$ws/loop/.distill-state.lock"
age_file_seconds "$ws/loop/.distill-state.lock" 120
: >"$NOTIFY_LOG"
run_probe "$ws" 'tick:1'; first_rc=$?
lock_retained=0
[ -d "$ws/loop/.distill-state.lock" ] && lock_retained=1
first_entries=$(entry_count "$ws")
first_notifications=$(wc -l <"$NOTIFY_LOG" | tr -d '[:space:]')
rm -rf "$ws/loop/.distill-state.lock"
run_probe "$ws" 'tick:1'; retry_rc=$?
if [ "$first_rc" -eq 1 ] && [ "$retry_rc" -eq 0 ] \
  && [ "$lock_retained" -eq 1 ] && [ "$first_entries" -eq 0 ] \
  && [ "$first_notifications" -eq 1 ] && [ "$(entry_count "$ws")" -eq 1 ] \
  && [ "$(wc -l <"$NOTIFY_LOG" | tr -d '[:space:]')" -eq 1 ]; then
  pass 'probe wait never reclaims a lock younger than the shared stale threshold'
else
  fail_case 'probe wait never reclaims a lock younger than the shared stale threshold' \
    "rcs=$first_rc/$retry_rc retained=$lock_retained entries=$first_entries/$(entry_count "$ws") notifications=$first_notifications/$(wc -l <"$NOTIFY_LOG")"
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
  DEADMAN_MARKER="$marker" DEADMAN_PROBE="$probe_fail" "$wrapper" \
  >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; wrapper_rc=$?
marker_age=$(( $(date +%s) - $(file_mtime "$marker") ))
if [ "$wrapper_rc" -eq 0 ] && [ -f "$marker" ] && [ "$marker_age" -le 60 ] \
  && [ -f "$PROBE_LOG" ] && [ "$(cat "$PROBE_SAW_MARKER")" = yes ] \
  && [ "$(cat "$TARGET_SAW_PROBE")" = yes ] \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 1 ] \
  && grep -Fq 'cron-wrapper warning: DEADMAN_PROBE reported a deadman violation:' "$TMP_ROOT/wrapper.err" \
  && ! grep -Fq 'cron-wrapper warning: DEADMAN_PROBE failed:' "$TMP_ROOT/wrapper.err"; then
  pass 'wrapper marks before probe and ignores probe failures'
else
  fail_case 'wrapper marks before probe and ignores probe failures' "rc=$wrapper_rc"
fi

probe_broken=$TMP_ROOT/probe-broken
cat >"$probe_broken" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$probe_broken"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  DEADMAN_MARKER="$marker" DEADMAN_PROBE="$probe_broken" "$wrapper" \
  >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; broken_wrapper_rc=$?
if [ "$broken_wrapper_rc" -eq 0 ] \
  && grep -Fq "cron-wrapper warning: DEADMAN_PROBE failed: $probe_broken" "$TMP_ROOT/wrapper.err" \
  && ! grep -Fq 'reported a deadman violation' "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 2 ]; then
  pass 'wrapper distinguishes probe breakage from violations'
else
  fail_case 'wrapper distinguishes probe breakage from violations' "rc=$broken_wrapper_rc stderr=$(cat "$TMP_ROOT/wrapper.err")"
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

quoted_marker="$TMP_ROOT/quoted marker/.deadman/tick.marker"
quoted_secrets=$TMP_ROOT/secrets-env-quoted
printf 'DEADMAN_MARKER="%s"\r\n' "$quoted_marker" >"$quoted_secrets"
chmod 600 "$quoted_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$quoted_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; quoted_secrets_rc=$?
if [ "$quoted_secrets_rc" -eq 0 ] && [ -f "$quoted_marker" ] \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'quoted CRLF secrets overrides export without quotes'
else
  fail_case 'quoted CRLF secrets overrides export without quotes' "rc=$quoted_secrets_rc marker=$([ -f "$quoted_marker" ] && printf yes || printf no)"
fi

secrets_capture_target=$TMP_ROOT/secrets-capture-target
cat >"$secrets_capture_target" <<'EOF'
#!/usr/bin/env bash
printf 'FOO=%s\n' "${FOO-}"
printf 'STRIPPED=%s\n' "${STRIPPED-}"
printf 'VERBATIM=%s\n' "${VERBATIM-}"
printf 'LEADING=%s\n' "${LEADING-}"
printf 'TRAILING=%s\n' "${TRAILING-}"
printf 'MIDDLE=%s\n' "${MIDDLE-}"
printf 'SINGLE=%s\n' "${SINGLE-}"
printf 'EMPTY=%s\n' "${EMPTY-}"
EOF
chmod +x "$secrets_capture_target"

indented_secrets=$TMP_ROOT/secrets-env-indented
printf '  FOO=bar\n' >"$indented_secrets"
chmod 600 "$indented_secrets"
TARGET="$secrets_capture_target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$indented_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; indented_rc=$?
if [ "$indented_rc" -eq 0 ] && grep -Fxq 'FOO=bar' "$TMP_ROOT/wrapper.out"; then
  pass 'indented secrets assignments are accepted'
else
  fail_case 'indented secrets assignments are accepted' "rc=$indented_rc stdout=$(cat "$TMP_ROOT/wrapper.out")"
fi

spaced_key_secrets=$TMP_ROOT/secrets-env-spaced-key
printf '  FOO =bar\n' >"$spaced_key_secrets"
chmod 600 "$spaced_key_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$spaced_key_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; spaced_key_rc=$?
if [ "$spaced_key_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $spaced_key_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'whitespace between a secrets key and equals remains malformed'
else
  fail_case 'whitespace between a secrets key and equals remains malformed' \
    "rc=$spaced_key_rc stderr=$(cat "$TMP_ROOT/wrapper.err")"
fi

quoted_shape_secrets=$TMP_ROOT/secrets-env-quoted-shapes
cat >"$quoted_shape_secrets" <<'EOF'
STRIPPED="a+b"
VERBATIM="a"+"b"
LEADING="a
TRAILING=a"
MIDDLE=a"b
SINGLE="
EMPTY=""
EOF
chmod 600 "$quoted_shape_secrets"
TARGET="$secrets_capture_target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$quoted_shape_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; quoted_shape_rc=$?
if [ "$quoted_shape_rc" -eq 0 ] \
  && grep -Fxq 'STRIPPED=a+b' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'VERBATIM="a"+"b"' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'LEADING="a' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'TRAILING=a"' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'MIDDLE=a"b' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'SINGLE="' "$TMP_ROOT/wrapper.out" \
  && grep -Fxq 'EMPTY=' "$TMP_ROOT/wrapper.out"; then
  pass 'outer quotes are stripped only when the inner value has no matching quote'
else
  fail_case 'outer quotes are stripped only when the inner value has no matching quote' \
    "rc=$quoted_shape_rc stdout=$(cat "$TMP_ROOT/wrapper.out")"
fi

readonly_secrets=$TMP_ROOT/secrets-env-readonly
printf 'UID=1000\n' >"$readonly_secrets"
chmod 600 "$readonly_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$readonly_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; readonly_rc=$?
if [ "$readonly_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 cannot export UID (reserved or read-only name): $readonly_secrets" "$TMP_ROOT/wrapper.err" \
  && ! grep -Fq 'readonly variable' "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'read-only shell names fail through the infra-error contract'
else
  fail_case 'read-only shell names fail through the infra-error contract' \
    "rc=$readonly_rc stderr=$(cat "$TMP_ROOT/wrapper.err")"
fi

pager_secrets=$TMP_ROOT/secrets-env-pager
printf 'PAGER=/tmp/x\n' >"$pager_secrets"
chmod 600 "$pager_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$pager_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; pager_rc=$?
if [ "$pager_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 refuses interpreter-control name PAGER (rename it, e.g. APP_ENV): $pager_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'added exact interpreter-control names are refused'
else
  fail_case 'added exact interpreter-control names are refused' "rc=$pager_rc"
fi

env_secrets=$TMP_ROOT/secrets-env-env
printf '# comment\n\nENV=production\n' >"$env_secrets"
chmod 600 "$env_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$env_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; env_rc=$?
if [ "$env_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 3 refuses interpreter-control name ENV (rename it, e.g. APP_ENV): $env_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'interpreter-control refusals include an actionable rename hint'
else
  fail_case 'interpreter-control refusals include an actionable rename hint' "rc=$env_rc"
fi

nul_secrets=$TMP_ROOT/secrets-env-nul
printf 'FIRST=ok\nNUL_VALUE=before\0after\n' >"$nul_secrets"
chmod 600 "$nul_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$nul_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; nul_rc=$?
if [ "$nul_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 2 contains an embedded NUL byte: $nul_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'embedded NUL bytes fail closed with the first offending line number'
else
  fail_case 'embedded NUL bytes fail closed with the first offending line number' \
    "rc=$nul_rc stderr=$(cat "$TMP_ROOT/wrapper.err")"
fi

bash_env_marker=$TMP_ROOT/bash-env-marker
bash_env_script=$TMP_ROOT/bash-env-script
printf ': >"%s"\n' "$bash_env_marker" >"$bash_env_script"
chmod 600 "$bash_env_script"
bash_env_secrets=$TMP_ROOT/secrets-env-bash-env
printf 'BASH_ENV=%s\n' "$bash_env_script" >"$bash_env_secrets"
chmod 600 "$bash_env_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$bash_env_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; bash_env_rc=$?
if [ "$bash_env_rc" -eq 3 ] && [ ! -e "$bash_env_marker" ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 refuses interpreter-control name BASH_ENV (rename it, e.g. APP_ENV): $bash_env_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'BASH_ENV is refused before its startup script can run'
else
  fail_case 'BASH_ENV is refused before its startup script can run' \
    "rc=$bash_env_rc marker=$([ -e "$bash_env_marker" ] && printf present || printf absent)"
fi

prefix_secrets=$TMP_ROOT/secrets-env-prefix
printf 'LD_PRELOAD=/tmp/x\n' >"$prefix_secrets"
chmod 600 "$prefix_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$prefix_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; prefix_rc=$?
if [ "$prefix_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 refuses interpreter-control name LD_PRELOAD (rename it, e.g. APP_ENV): $prefix_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'dynamic-loader prefix names are refused'
else
  fail_case 'dynamic-loader prefix names are refused' "rc=$prefix_rc"
fi

prefix_boundary_log=$TMP_ROOT/prefix-boundary.log
prefix_boundary_target=$TMP_ROOT/prefix-boundary-target
cat >"$prefix_boundary_target" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${LDAP_TOKEN-}" >"$PREFIX_BOUNDARY_LOG"
EOF
chmod +x "$prefix_boundary_target"
prefix_boundary_allowed=$TMP_ROOT/secrets-env-prefix-boundary-allowed
printf 'LDAP_TOKEN=abc\n' >"$prefix_boundary_allowed"
chmod 600 "$prefix_boundary_allowed"
TARGET="$prefix_boundary_target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  PREFIX_BOUNDARY_LOG="$prefix_boundary_log" SECRETS_ENV="$prefix_boundary_allowed" "$wrapper" \
  >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; prefix_boundary_allowed_rc=$?
prefix_boundary_refused=$TMP_ROOT/secrets-env-prefix-boundary-refused
printf 'LD_AUDIT=/tmp/x\n' >"$prefix_boundary_refused"
chmod 600 "$prefix_boundary_refused"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$prefix_boundary_refused" "$wrapper" \
  >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; prefix_boundary_refused_rc=$?
if [ "$prefix_boundary_allowed_rc" -eq 0 ] \
  && [ -f "$prefix_boundary_log" ] && [ "$(cat "$prefix_boundary_log")" = abc ] \
  && [ "$prefix_boundary_refused_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 1 refuses interpreter-control name LD_AUDIT (rename it, e.g. APP_ENV): $prefix_boundary_refused" "$TMP_ROOT/wrapper.err"; then
  pass 'dynamic-loader prefix families match only at the start of a name'
else
  fail_case 'dynamic-loader prefix families match only at the start of a name' \
    "rcs=$prefix_boundary_allowed_rc/$prefix_boundary_refused_rc value=$([ -f "$prefix_boundary_log" ] && cat "$prefix_boundary_log" || printf missing)"
fi

near_miss_log=$TMP_ROOT/near-miss.log
near_miss_target=$TMP_ROOT/near-miss-target
cat >"$near_miss_target" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MY_PATH_TOKEN-}" >"$NEAR_MISS_LOG"
EOF
chmod +x "$near_miss_target"
near_miss_secrets=$TMP_ROOT/secrets-env-near-miss
printf 'MY_PATH_TOKEN=abc\n' >"$near_miss_secrets"
chmod 600 "$near_miss_secrets"
TARGET="$near_miss_target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  NEAR_MISS_LOG="$near_miss_log" SECRETS_ENV="$near_miss_secrets" "$wrapper" \
  >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; near_miss_rc=$?
if [ "$near_miss_rc" -eq 0 ] && [ -f "$near_miss_log" ] \
  && [ "$(cat "$near_miss_log")" = abc ]; then
  pass 'hazardous substrings in legitimate names remain accepted'
else
  fail_case 'hazardous substrings in legitimate names remain accepted' \
    "rc=$near_miss_rc value=$([ -f "$near_miss_log" ] && cat "$near_miss_log" || printf missing)"
fi

would_be_command_side_effect=$TMP_ROOT/would-be-command-side-effect
secrets_command=$TMP_ROOT/secrets-env-command
cat >"$secrets_command" <<EOF
# comment

DEADMAN_MARKER=$marker
touch "$would_be_command_side_effect"
EOF
chmod 600 "$secrets_command"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$secrets_command" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; secrets_command_rc=$?
if [ "$secrets_command_rc" -eq 3 ] && [ ! -e "$would_be_command_side_effect" ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 4 is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $secrets_command" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'would-be command lines are rejected without side effects'
else
  fail_case 'would-be command lines are rejected without side effects' "rc=$secrets_command_rc side_effect=$([ -e "$would_be_command_side_effect" ] && printf yes || printf no)"
fi

malformed_secrets=$TMP_ROOT/secrets-env-malformed
cat >"$malformed_secrets" <<EOF
DEADMAN_MARKER=$marker
BAD-KEY=value
EOF
chmod 600 "$malformed_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$malformed_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; malformed_secrets_rc=$?
if [ "$malformed_secrets_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 2 is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $malformed_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'malformed secrets lines fail with line numbers'
else
  fail_case 'malformed secrets lines fail with line numbers' "rc=$malformed_secrets_rc"
fi

pem_secrets=$TMP_ROOT/secrets-env-pem
# PEM-shaped fixture: the same multi-line quoted structure a real key file has, with a
# neutral block label so local and CI secret scanners do not flag the test data.
cat >"$pem_secrets" <<'EOF'
BLOCK_VALUE="-----BEGIN EXAMPLE BLOCK-----
YWJj
-----END EXAMPLE BLOCK-----"
EOF
chmod 600 "$pem_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$pem_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; pem_rc=$?
if [ "$pem_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV line 2 is not a KEY=VALUE assignment; SECRETS_ENV requires one assignment per line (store multi-line secrets in their own file and put the path in SECRETS_ENV): $pem_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'PEM-shaped multi-line values fail with the documented path workaround'
else
  fail_case 'PEM-shaped multi-line values fail with the documented path workaround' \
    "rc=$pem_rc stderr=$(cat "$TMP_ROOT/wrapper.err")"
fi

symlink_source=$TMP_ROOT/secrets-env-symlink-source
symlink_secrets=$TMP_ROOT/secrets-env-symlink
printf 'DEADMAN_MARKER=%s\n' "$marker" >"$symlink_source"
chmod 600 "$symlink_source"
ln -s "$symlink_source" "$symlink_secrets"
TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$wrapper_ws" \
  SECRETS_ENV="$symlink_secrets" "$wrapper" >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"; symlink_secrets_rc=$?
if [ "$symlink_secrets_rc" -eq 3 ] \
  && grep -Fq "cron-wrapper infra error: SECRETS_ENV must not be a symlink: $symlink_secrets" "$TMP_ROOT/wrapper.err" \
  && [ "$(wc -l <"$TARGET_LOG" | tr -d '[:space:]')" -eq 3 ]; then
  pass 'symlink secrets env is refused'
else
  fail_case 'symlink secrets env is refused' "rc=$symlink_secrets_rc"
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
