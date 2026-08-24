#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INTAKE=$ROOT/adapters/claude-code/flush-intake.sh
TMP_ROOT=${TMPDIR:-/tmp}/last-session-fold-test.$$
PASS_COUNT=0
FAIL_COUNT=0
TODAY=$(date -u '+%Y-%m-%d')
ISO_WEEK=$(date -u '+%G-W%V')

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
  shift
  env INTAKE_LOCK_SLEEP_S=0 "$@" "$INTAKE" "$ws" >"$TMP_ROOT/intake.out" 2>"$TMP_ROOT/intake.err"
}

receipt_value() {
  local ws=$1
  local key=$2
  tail -n 1 "$ws/loop/pending/intake-runs.log" | tr ' ' '\n' | sed -n "s/^$key=//p" | head -n 1
}

entry_count() {
  awk '
    index($0, "## Last session") == 1 {in_section = 1; next}
    in_section && /^## / {exit}
    in_section && (/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / || /^- task id:/) {count++}
    END {print count + 0}
  ' "$1"
}

file_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_state_prefix() {
  printf '%s\n' \
    '## Verified facts' \
    '## General rules' \
    '## Open failures' \
    '## Lessons learned' \
    '## Last session        (cap 20 entries — newest first; entry 1 carries the 4 fields inline)' \
    '<!-- Entry 1: - YYYY-MM-DD | task id | next: ... | blockers: ... | artifact: ... | handoff: loop/handoffs/<date>-<slug>.md -->' \
    '<!-- Entries 2..20: - YYYY-MM-DD | task id | handoff: loop/handoffs/<date>-<slug>.md -->'
}

ws=$(new_ws entry-one)
printf 'entry one narrative\n' >"$ws/loop/handoffs/2026-08-24-one.md"
{
  write_state_prefix
  printf '%s\n' '<!-- template preamble -->'
  printf '%s\n' '- 2026-08-24 | one | next: continue | blockers: none | artifact: loop/artifacts/one/result.md | handoff: loop/handoffs/2026-08-24-one.md'
  printf '%s\n' 'entry one remains multiline'
} >"$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/entry-one.before"
run_intake "$ws"
if cmp -s "$TMP_ROOT/entry-one.before" "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" last_session_entries)" -eq 1 ]; then
  pass '[1] entry 1 is untouched when no newer entry exists'
else
  fail_case '[1] entry 1 is untouched when no newer entry exists' "$(cat "$ws/STATE.md")"
fi

ws=$(new_ws missing-last-session)
awk 'index($0, "## Last session") != 1 {print}' "$ws/STATE.md" >"$TMP_ROOT/missing-last-session.state"
mv "$TMP_ROOT/missing-last-session.state" "$ws/STATE.md"
{
  printf '%s\n' '<!-- flush ts=2026-08-23T01:02:03Z outcome=ok -->'
  printf '%s\n' '- Intake survives a missing Last-session section.'
} >"$ws/loop/pending/flush-2026-08-23.md"
run_intake "$ws"
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq 'Intake survives a missing Last-session section.' "$ws/STATE.md" \
  && [ ! -e "$ws/loop/pending/flush-2026-08-23.md" ] \
  && [ -f "$ws/loop/archive/flush-2026-08-23.md" ] \
  && [ -e "$ws/loop/.deadman/distill.marker" ] \
  && grep -Fq 'last_session_fold=skipped reason=missing-section' "$ws/loop/pending/intake-runs.log"; then
  pass '[1-skip] a missing Last-session section skips only the fold and intake continues'
else
  fail_case '[1-skip] a missing Last-session section skips only the fold and intake continues' "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws collapse)
printf 'new handoff\n' >"$ws/loop/handoffs/2026-08-24-new.md"
printf 'old handoff\n' >"$ws/loop/handoffs/2026-08-23-old.md"
{
  write_state_prefix
  printf '%s\n' '<!-- template preamble -->'
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: loop/artifacts/new/result.md | handoff: loop/handoffs/2026-08-24-new.md'
  printf '%s\n' 'new inline continuation must remain'
  printf '%s\n' '- 2026-08-23 | old | next: old next | blockers: none | artifact: old.md | handoff: loop/handoffs/2026-08-23-old.md'
  printf '%s\n' 'old continuation must collapse'
} >"$ws/STATE.md"
run_intake "$ws"
if grep -Fqx -- '- 2026-08-24 | new | next: continue | blockers: none | artifact: loop/artifacts/new/result.md | handoff: loop/handoffs/2026-08-24-new.md' "$ws/STATE.md" \
  && grep -Fqx -- 'new inline continuation must remain' "$ws/STATE.md" \
  && grep -Fqx -- '- 2026-08-23 | old | handoff: loop/handoffs/2026-08-23-old.md' "$ws/STATE.md" \
  && ! grep -Fq 'old continuation must collapse' "$ws/STATE.md"; then
  pass '[2] a newer entry makes the host collapse only the previous entry'
else
  fail_case '[2] a newer entry makes the host collapse only the previous entry' "$(cat "$ws/STATE.md")"
fi

ws=$(new_ws preserve-after)
printf 'new handoff\n' >"$ws/loop/handoffs/2026-08-24-new.md"
printf 'old handoff\n' >"$ws/loop/handoffs/2026-08-23-old.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: new.md | handoff: loop/handoffs/2026-08-24-new.md'
  printf '%s\n' '- 2026-08-23 | old | next: old next | blockers: none | artifact: old.md | handoff: loop/handoffs/2026-08-23-old.md'
  printf '%s\n' 'old continuation collapses before the following section'
  printf '%s\n' '## Open failures after fold'
  printf '%s\n' 'Prose after Last session must remain byte-identical.'
  printf '%s\n' '- after-section-verbatim-sentinel'
  printf '%s\n' 'final prose line'
} >"$ws/STATE.md"
sed -n '/^## Open failures after fold$/,$p' "$ws/STATE.md" >"$TMP_ROOT/preserve-after.expected"
run_intake "$ws"
sed -n '/^## Open failures after fold$/,$p' "$ws/STATE.md" >"$TMP_ROOT/preserve-after.actual"
if cmp -s "$TMP_ROOT/preserve-after.expected" "$TMP_ROOT/preserve-after.actual"; then
  pass '[2-after] sections and prose after Last session survive a fold byte-for-byte'
else
  fail_case '[2-after] sections and prose after Last session survive a fold byte-for-byte' "state=$(cat "$ws/STATE.md")"
fi

ws=$(new_ws missing-pointer)
printf 'new handoff\n' >"$ws/loop/handoffs/2026-08-24-new.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: new.md | handoff: loop/handoffs/2026-08-24-new.md'
  printf '%s\n' '- 2026-08-23 | missing | next: recover | blockers: none | artifact: missing.md | handoff: loop/handoffs/does-not-exist.md'
  printf '%s\n' 'body retained through missing-pointer synthesis'
} >"$ws/STATE.md"
run_intake "$ws"
synthesized=$(find "$ws/loop/handoffs" -maxdepth 1 -type f -name '2026-08-23-migrated*.md' -print | head -n 1)
if [ -n "$synthesized" ] \
  && grep -Fq 'body retained through missing-pointer synthesis' "$synthesized" \
  && grep -Fq "handoff: loop/handoffs/${synthesized##*/}" "$ws/STATE.md" \
  && [ "$(receipt_value "$ws" synthesized_handoffs)" -eq 1 ]; then
  pass '[3] a missing pointer target is synthesized before collapse'
else
  fail_case '[3] a missing pointer target is synthesized before collapse' "state=$(cat "$ws/STATE.md")"
fi

ws=$(new_ws suffix)
printf 'occupied\n' >"$ws/loop/handoffs/2026-08-23-migrated.md"
printf 'occupied\n' >"$ws/loop/handoffs/2026-08-23-migrated-2.md"
printf 'new\n' >"$ws/loop/handoffs/2026-08-24-new.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: new.md | handoff: loop/handoffs/2026-08-24-new.md'
  printf '%s\n' '- 2026-08-23 | pointerless | next: recover | blockers: none | artifact: old.md'
} >"$ws/STATE.md"
run_intake "$ws"
if [ -f "$ws/loop/handoffs/2026-08-23-migrated-3.md" ] \
  && grep -Fq 'handoff: loop/handoffs/2026-08-23-migrated-3.md' "$ws/STATE.md"; then
  pass '[4] synthesized handoffs use exclusive migrated-N suffixes'
else
  fail_case '[4] synthesized handoffs use exclusive migrated-N suffixes' "$(find "$ws/loop/handoffs" -maxdepth 1 -print)"
fi

write_over_cap_state() {
  local ws=$1
  local long_tail=${2:-0}
  local i=1
  write_state_prefix
  printf '%s\n' '<!-- preamble stays out of the archive -->'
  while [ "$i" -le 21 ]; do
    printf 'handoff %02d\n' "$i" >"$ws/loop/handoffs/2026-08-24-entry-$i.md"
    if [ "$i" -eq 1 ]; then
      printf -- '- 2026-08-24 | entry-%02d | next: continue | blockers: none | artifact: artifact-%02d | handoff: loop/handoffs/2026-08-24-entry-%d.md\n' "$i" "$i" "$i"
    else
      printf -- '- 2026-08-24 | entry-%02d | handoff: loop/handoffs/2026-08-24-entry-%d.md\n' "$i" "$i"
    fi
    if [ "$i" -eq 21 ]; then
      printf '%s\n' 'tail-entry-verbatim-sentinel'
      if [ "$long_tail" -eq 1 ]; then
        python3 -B - <<'PY'
print("- oversize-sentinel-" + "x" * 6200)
PY
      fi
    fi
    i=$((i + 1))
  done
}

ws=$(new_ws over-cap)
write_over_cap_state "$ws" 1 >"$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/over-cap.before"
run_intake "$ws"
archive="$ws/loop/archive/last-session-$ISO_WEEK.md"
if [ "$(receipt_value "$ws" files_scanned)" -eq 0 ] \
  && [ "$(receipt_value "$ws" evicted)" -eq 1 ] \
  && [ "$(entry_count "$ws/STATE.md")" -eq 20 ] \
  && grep -Fq 'entry-01 | next: continue' "$ws/STATE.md" \
  && ! grep -Fq 'entry-21' "$ws/STATE.md" \
  && ! grep -Fq 'entry-01' "$archive" \
  && grep -Fq 'tail-entry-verbatim-sentinel' "$archive" \
  && grep -Fq 'oversize-sentinel-' "$archive" \
  && ! grep -Fq 'preamble stays out' "$archive"; then
  pass '[5] zero-file intake keeps the head and archives the oversize tail verbatim'
else
  fail_case '[5] zero-file intake keeps the head and archives the oversize tail verbatim' "receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws archive-failure)
write_over_cap_state "$ws" 0 >"$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/archive-failure.before"
chmod 500 "$ws/loop/archive"
run_intake "$ws"
rc=$?
chmod 700 "$ws/loop/archive"
if [ "$rc" -ne 0 ] \
  && cmp -s "$TMP_ROOT/archive-failure.before" "$ws/STATE.md" \
  && [ ! -e "$ws/loop/archive/last-session-$ISO_WEEK.md" ] \
  && grep -Fq 'last_session_fold=failed reason=archive-append' "$ws/loop/pending/intake-runs.log"; then
  pass '[6] archive failure aborts before STATE rename'
else
  fail_case '[6] archive failure aborts before STATE rename' "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws concurrent-writer)
printf 'new\n' >"$ws/loop/handoffs/2026-08-24-new.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: new.md | handoff: loop/handoffs/2026-08-24-new.md'
  printf '%s\n' '- 2026-08-23 | pointerless | next: recover | blockers: none | artifact: old.md'
  awk 'BEGIN {for (i = 1; i <= 100000; i++) printf "race-padding-%06d\n", i}'
} >"$ws/STATE.md"
(
  : >"$TMP_ROOT/race-writer.started"
  while [ ! -e "$TMP_ROOT/race-writer.stop" ]; do
    printf '%s\n' '<!-- real concurrent writer -->' >>"$ws/STATE.md"
    sleep 0.001
  done
) &
race_pid=$!
while [ ! -e "$TMP_ROOT/race-writer.started" ]; do :; done
run_intake "$ws"
rc=$?
: >"$TMP_ROOT/race-writer.stop"
wait "$race_pid" 2>/dev/null || true
if [ "$rc" -ne 0 ] \
  && grep -Fq '<!-- real concurrent writer -->' "$ws/STATE.md" \
  && [ "$(find "$ws/loop/handoffs" -maxdepth 1 -type f -name '*migrated*.md' | wc -l | tr -d '[:space:]')" -eq 0 ] \
  && grep -Fq 'last_session_fold=failed reason=concurrent-writer' "$ws/loop/pending/intake-runs.log"; then
  pass '[7] concurrent-writer mismatch aborts before creating handoffs'
else
  fail_case '[7] concurrent-writer mismatch aborts before creating handoffs' "rc=$rc state_bytes=$(wc -c <"$ws/STATE.md" | tr -d '[:space:]')"
fi

ws=$(new_ws exported-hooks-ignored)
write_over_cap_state "$ws" 0 >"$ws/STATE.md"
{
  printf '%s\n' '<!-- flush ts=2026-08-23T01:02:03Z outcome=ok -->'
  printf '%s\n' '- Exported former fault hooks cannot alter production intake.'
} >"$ws/loop/pending/flush-2026-08-23.md"
run_intake "$ws" STATE_FOLD_TEST_CONCURRENT_WRITE=1 STATE_FOLD_TEST_FAIL_ARCHIVE_APPEND=1
rc=$?
if [ "$rc" -eq 0 ] \
  && ! grep -Fq '<!-- concurrent writer test -->' "$ws/STATE.md" \
  && grep -Fq 'Exported former fault hooks cannot alter production intake.' "$ws/STATE.md" \
  && [ -f "$ws/loop/archive/last-session-$ISO_WEEK.md" ] \
  && [ ! -e "$ws/loop/pending/flush-2026-08-23.md" ] \
  && [ -e "$ws/loop/.deadman/distill.marker" ]; then
  pass '[7-env] exported former fault hooks have no effect on STATE or intake'
else
  fail_case '[7-env] exported former fault hooks have no effect on STATE or intake' "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

ws=$(new_ws legacy-migration)
python3 -B - >"$ws/STATE.md" <<'PY'
from datetime import date, timedelta

print("## Verified facts")
print("## General rules")
print("## Open failures")
print("## Lessons learned")
print("## Last session        (cap 20 entries — newest first)")
print("<!-- synthetic legacy diet preamble -->")
print("<!-- template-owned comment before the first boundary -->")
start = date(2026, 8, 24)
for i in range(1, 188):
    day = start - timedelta(days=i - 1)
    stamp = day.isoformat()
    print(f"- task id: synthetic-{i:03d}")
    print(f"- next action: continue synthetic {i:03d} on {stamp}")
    print("- blockers: none")
    print(f"- last verified artifact path: loop/artifacts/synthetic-{i:03d}/result.md")
    if i <= 13:
        print(f"- stray non-boundary bullet {i:02d}")
    if i % 17 == 0:
        print(f"mid-block prose for synthetic session {i:03d}")
    if i <= 5:
        print(f"- comparison window {stamp}（前回 2025-12-0{i}、日本語注記）")
    if i == 42:
        print("- oversize legacy bullet " + "y" * 6200)
PY
awk '
  index($0, "## Last session") == 1 {in_section = 1; next}
  in_section && /^## / {exit}
  in_section && /^- task id:/ {saw_entry = 1}
  in_section && saw_entry {print}
' "$ws/STATE.md" >"$TMP_ROOT/legacy-block.expected"
"$ROOT/install.sh" --workspace "$ws" >"$TMP_ROOT/install.out" 2>"$TMP_ROOT/install.err"
rc=$?
archive="$ws/loop/archive/last-session-$ISO_WEEK.md"
migrated="$ws/loop/handoffs/2026-08-24-migrated.md"
if [ "$rc" -eq 0 ] \
  && cmp -s "$TMP_ROOT/legacy-block.expected" "$archive" \
  && cmp -s "$TMP_ROOT/legacy-block.expected" "$migrated" \
  && [ "$(find "$ws/loop/handoffs" -maxdepth 1 -type f -name '*-migrated*.md' | wc -l | tr -d '[:space:]')" -eq 1 ] \
  && [ "$(entry_count "$ws/STATE.md")" -eq 20 ] \
  && grep -Fqx -- '- 2026-08-24 | synthetic-001 | next: continue synthetic 001 on 2026-08-24 | blockers: none | artifact: loop/artifacts/synthetic-001/result.md | handoff: loop/handoffs/2026-08-24-migrated.md' "$ws/STATE.md" \
  && [ "$(grep -Fc 'handoff: loop/handoffs/2026-08-24-migrated.md' "$ws/STATE.md")" -eq 20 ] \
  && grep -Fq '<!-- synthetic legacy diet preamble -->' "$ws/STATE.md" \
  && ! grep -Fq '<!-- synthetic legacy diet preamble -->' "$archive"; then
  pass '[8] eager install migration is lossless and rebuilds one shared-pointer index'
else
  fail_case '[8] eager install migration is lossless and rebuilds one shared-pointer index' "rc=$rc stderr=$(cat "$TMP_ROOT/install.err")"
fi
state_hash_before=$(file_hash "$ws/STATE.md")
archive_hash_before=$(file_hash "$archive")
handoff_hash_before=$(file_hash "$migrated")
"$ROOT/install.sh" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/install-second.err"
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$state_hash_before" = "$(file_hash "$ws/STATE.md")" ] \
  && [ "$archive_hash_before" = "$(file_hash "$archive")" ] \
  && [ "$handoff_hash_before" = "$(file_hash "$migrated")" ] \
  && [ "$(find "$ws/loop/handoffs" -maxdepth 1 -type f -name '*-migrated*.md' | wc -l | tr -d '[:space:]')" -eq 1 ]; then
  pass '[9] eager legacy migration is idempotent on a second install'
else
  fail_case '[9] eager legacy migration is idempotent on a second install' "rc=$rc stderr=$(cat "$TMP_ROOT/install-second.err")"
fi

ws=$(new_ws mixed-migration)
printf 'new-format handoff\n' >"$ws/loop/handoffs/2026-08-24-new.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: continue | blockers: none | artifact: new.md | handoff: loop/handoffs/2026-08-24-new.md'
  i=1
  while [ "$i" -le 22 ]; do
    printf -- '- task id: mixed-%02d\n' "$i"
    printf -- '- next action: continue mixed %02d\n' "$i"
    printf '%s\n' '- blockers: none'
    printf -- '- last verified artifact path: loop/artifacts/mixed-%02d/result.md\n' "$i"
    printf -- 'mixed-lossless-sentinel-%02d\n' "$i"
    i=$((i + 1))
  done
} >"$ws/STATE.md"
run_intake "$ws"
rc=$?
archive="$ws/loop/archive/last-session-$ISO_WEEK.md"
{
  cat "$ws/STATE.md"
  find "$ws/loop/handoffs" -maxdepth 1 -type f -name '*-migrated*.md' -print | LC_ALL=C sort | while IFS= read -r handoff; do
    cat "$handoff"
  done
  cat "$archive"
} >"$TMP_ROOT/mixed-migration.corpus"
mixed_lossless=1
i=1
while [ "$i" -le 22 ]; do
  sentinel=$(printf 'mixed-lossless-sentinel-%02d' "$i")
  if [ "$(grep -Fxc "$sentinel" "$TMP_ROOT/mixed-migration.corpus")" -ne 1 ]; then
    mixed_lossless=0
  fi
  i=$((i + 1))
done
if [ "$rc" -eq 0 ] \
  && [ "$mixed_lossless" -eq 1 ] \
  && [ "$(entry_count "$ws/STATE.md")" -eq 20 ] \
  && [ "$(find "$ws/loop/handoffs" -maxdepth 1 -type f -name '*-migrated*.md' | wc -l | tr -d '[:space:]')" -eq 19 ] \
  && [ "$(receipt_value "$ws" evicted)" -eq 3 ] \
  && [ "$(receipt_value "$ws" synthesized_handoffs)" -eq 19 ]; then
  pass '[9-mixed] mixed blocks synthesize retained legacy entries separately without loss'
else
  fail_case '[9-mixed] mixed blocks synthesize retained legacy entries separately without loss' "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi
cp "$ws/STATE.md" "$TMP_ROOT/mixed-state.before"
cp -R "$ws/loop/handoffs" "$TMP_ROOT/mixed-handoffs.before"
cp "$archive" "$TMP_ROOT/mixed-archive.before"
run_intake "$ws"
rc=$?
if [ "$rc" -eq 0 ] \
  && cmp -s "$TMP_ROOT/mixed-state.before" "$ws/STATE.md" \
  && diff -r "$TMP_ROOT/mixed-handoffs.before" "$ws/loop/handoffs" >/dev/null \
  && cmp -s "$TMP_ROOT/mixed-archive.before" "$archive"; then
  pass '[9-mixed-idempotent] mixed-block synthesis is idempotent on a second intake'
else
  fail_case '[9-mixed-idempotent] mixed-block synthesis is idempotent on a second intake' "rc=$rc receipt=$(tail -n 1 "$ws/loop/pending/intake-runs.log")"
fi

run_check() {
  env -u VERIFIER_CMD -u DISTILLER_CMD "$ROOT/install.sh" --check --workspace "$1" 2>&1
}

write_check_state() {
  local ws=$1
  local mode=$2
  local i
  printf 'handoff\n' >"$ws/loop/handoffs/healthy.md"
  {
    write_state_prefix
    case "$mode" in
      healthy)
        printf '%s\n' '- 2026-08-24 | healthy | next: none | blockers: none | artifact: none | handoff: loop/handoffs/healthy.md'
        ;;
      entries)
        i=1
        while [ "$i" -le 21 ]; do
          printf -- '- 2026-08-24 | entry-%02d | handoff: loop/handoffs/healthy.md\n' "$i"
          i=$((i + 1))
        done
        ;;
      lines)
        printf '%s\n' '- 2026-08-24 | lines | next: none | blockers: none | artifact: none | handoff: loop/handoffs/healthy.md'
        i=1
        while [ "$i" -le 60 ]; do
          printf 'prose physical line %02d\n' "$i"
          i=$((i + 1))
        done
        ;;
      grammar)
        printf '%s\n' '- task id: legacy-check; next action: none; blockers: none; last verified artifact path: none; 2026-08-24'
        ;;
      pointer)
        printf '%s\n' '- 2026-08-24 | missing | next: none | blockers: none | artifact: none | handoff: loop/handoffs/missing.md'
        ;;
    esac
  } >"$ws/STATE.md"
  printf '%s\n' '- 2026-08-23 | task=fixture | verifier=test | verdict=pass | fixture' >>"$ws/loop/VERIFY.log.md"
}

ws=$(new_ws check-healthy)
write_check_state "$ws" healthy
output=$(run_check "$ws")
if ! printf '%s\n' "$output" | grep -q 'warning: last-session-'; then
  pass '[10] healthy new-format workspace emits zero Last-session warnings'
else
  fail_case '[10] healthy new-format workspace emits zero Last-session warnings' "$output"
fi

for warning in entries lines grammar pointer; do
  ws=$(new_ws "check-$warning")
  write_check_state "$ws" "$warning"
  output=$(run_check "$ws")
  warning_count=$(printf '%s\n' "$output" | grep -c 'warning: last-session-' || true)
  if [ "$warning_count" -eq 1 ] \
    && printf '%s\n' "$output" | grep -Fq "warning: last-session-$warning:"; then
    pass "[11-$warning] each Last-session warning condition reports only itself"
  else
    fail_case "[11-$warning] each Last-session warning condition reports only itself" "$output"
  fi
done

ws=$(new_ws freshness-entry-one)
printf 'new\n' >"$ws/loop/handoffs/new.md"
printf 'old\n' >"$ws/loop/handoffs/old.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: none | blockers: none | artifact: none | handoff: loop/handoffs/new.md'
  printf '%s\n' '- 2020-01-01 | old | handoff: loop/handoffs/old.md'
} >"$ws/STATE.md"
printf '%s\n' '- 2026-08-23 | task=fixture | verifier=test | verdict=pass | fixture' >>"$ws/loop/VERIFY.log.md"
output=$(run_check "$ws")
if ! printf '%s\n' "$output" | grep -Fq 'Last session date 2020-01-01 is older'; then
  pass '[12] freshness comparison is scoped to entry 1'
else
  fail_case '[12] freshness comparison is scoped to entry 1' "$output"
fi

ws=$(new_ws sibling-scope-entry-one)
mkdir -p "$ws/../sibling-artifacts"
printf 'sibling artifact\n' >"$ws/../sibling-artifacts/result.md"
printf 'new\n' >"$ws/loop/handoffs/new.md"
printf 'old\n' >"$ws/loop/handoffs/old.md"
{
  write_state_prefix
  printf '%s\n' '- 2026-08-24 | new | next: none | blockers: none | artifact: none | handoff: loop/handoffs/new.md'
  printf '%s\n' '- 2026-08-23 | old | handoff: loop/handoffs/old.md'
  printf '%s\n' 'historical sibling-artifacts/result.md reference'
} >"$ws/STATE.md"
printf '%s\n' '- 2026-08-23 | task=fixture | verifier=test | verdict=pass | fixture' >>"$ws/loop/VERIFY.log.md"
output=$(run_check "$ws")
if ! printf '%s\n' "$output" | grep -Fq 'warning: Last session references sibling-project path:'; then
  pass '[13] sibling-path mismatch detection is scoped to entry 1'
else
  fail_case '[13] sibling-path mismatch detection is scoped to entry 1' "$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
