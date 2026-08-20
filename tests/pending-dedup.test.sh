#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/adapters/openclaw/distill-audit.sh
STATE_FOLD_LIB=${STATE_FOLD_LIB_UNDER_TEST:-$ROOT/scripts/lib-state-fold.sh}
TMP_ROOT=${TMPDIR:-/tmp}/pending-dedup-test.$$
PASS_COUNT=0
FAIL_COUNT=0

source "$ROOT/tests/lib-wrapper-conformance-fixture.sh"

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

make_ws() {
  ws=$TMP_ROOT/ws-$1
  mkdir -p "$ws/loop/pending" "$ws/skills/_staging" "$ws/input"
  {
    printf '%s\n' '## Verified facts'
    printf '%s\n' '## General rules'
    printf '%s\n' '## Open failures'
    printf '%s\n' '## Lessons learned'
    printf '%s\n' '## Last session'
  } >"$ws/STATE.md"
  printf 'transcript\n' >"$ws/input/session.log"
  printf '%s\n' "$ws"
}

write_distiller() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$DISTILL_REPLY"
SH
  chmod +x "$path"
}

attest_distiller_wrapper() {
  local wrapper_path=$1
  local name=$2
  local provider_path=$TMP_ROOT/$name-provider.sh
  local probe_path=$TMP_ROOT/$name-probe.sh

  conformance_write_provider "$provider_path"
  conformance_write_probe "$probe_path"
  conformance_attest_wrapper "$ROOT" distiller "$wrapper_path" "$provider_path" "$probe_path" "fixture-$name" "fixture-$name-v1"
}

section_count_text() {
  text=$1
  file=$2
  grep -Fxc -- "$text" "$file" || true
}

distiller=$TMP_ROOT/fake-distiller.sh
write_distiller "$distiller"
attest_distiller_wrapper "$distiller" pending-dedup
utc_date=$(date -u '+%Y-%m-%d')
reply_one=$'## LESSONS\n- 2026-07-06 same lesson (source: distill-audit)\n## OPEN_FAILURES\n- 2026-07-06 same failure (source: distill-audit)\n## SKILL_DRAFTS'

ws=$(make_ws repeated)
output=$(DISTILL_REPLY="$reply_one" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
pending=$ws/loop/pending/distill-$utc_date.md
lesson_key_one=$(sed -n 's/.*\[dedup_key: \([^]]*\)\]$/\1/p' "$pending" | sed -n '1p')
if [ "$rc" -eq 0 ] \
  && [ "$(grep -Ec '^- 2026-07-06 (same lesson|same failure) \(source: distill-audit\) \[dedup_key: [0-9a-f]{64}:[0-9a-f]{64}\]$' "$pending")" -eq 2 ]; then
  pass "pending lesson and failure bullets carry task_id:lesson_hash keys"
else
  fail_case "pending lesson and failure bullets carry task_id:lesson_hash keys" "rc=$rc output=$output"
fi

# Delete the marker to model a cron re-fire of the same unchanged batch.
rm -f "$ws/loop/.distill-last-run"
output=$(DISTILL_REPLY="$reply_one" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
lesson_key_two=$(sed -n 's/.*\[dedup_key: \([^]]*\)\]$/\1/p' "$pending" | sed -n '1p')
if [ "$rc" -eq 0 ] \
  && [ "$(section_count_text '- 2026-07-06 same lesson (source: distill-audit)' "$ws/STATE.md")" -eq 1 ] \
  && [ "$(section_count_text '- 2026-07-06 same failure (source: distill-audit)' "$ws/STATE.md")" -eq 1 ] \
  && [ "$lesson_key_one" = "$lesson_key_two" ]; then
  pass "same batch re-fire folds lesson and open failure once and produces the same normalized hash"
else
  fail_case "same batch re-fire folds lesson and open failure once and produces the same normalized hash" "rc=$rc output=$output lesson_count=$(section_count_text '- 2026-07-06 same lesson (source: distill-audit)' "$ws/STATE.md") failure_count=$(section_count_text '- 2026-07-06 same failure (source: distill-audit)' "$ws/STATE.md") keys=$lesson_key_one/$lesson_key_two"
fi

reply_two=$'## LESSONS\n- 2026-07-06   different    lesson (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
rm -f "$ws/loop/.distill-last-run"
output=$(DISTILL_REPLY="$reply_two" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fqx -- '- 2026-07-06 same lesson (source: distill-audit)' "$ws/STATE.md" \
  && grep -Fqx -- '- 2026-07-06   different    lesson (source: distill-audit)' "$ws/STATE.md"; then
  pass "different lesson text with a different hash folds independently"
else
  fail_case "different lesson text with a different hash folds independently" "rc=$rc output=$output"
fi

ws=$(make_ws normalized)
reply_normal=$'## LESSONS\n- 2026-07-06 normalized lesson (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
DISTILL_REPLY="$reply_normal" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" >/dev/null 2>&1
key_normal=$(sed -n 's/.*\[dedup_key: \([^]]*\)\]$/\1/p' "$ws/loop/pending/distill-$utc_date.md" | sed -n '1p')
rm -f "$ws/loop/.distill-last-run"
reply_spaced=$'## LESSONS\n- 2026-07-06   normalized    lesson (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
DISTILL_REPLY="$reply_spaced" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" >/dev/null 2>&1
key_spaced=$(sed -n 's/.*\[dedup_key: \([^]]*\)\]$/\1/p' "$ws/loop/pending/distill-$utc_date.md" | sed -n '1p')
if [ "$key_normal" = "$key_spaced" ] \
  && [ "$(section_count_text '- 2026-07-06 normalized lesson (source: distill-audit)' "$ws/STATE.md")" -eq 1 ]; then
  pass "whitespace-normalized lesson text has a deterministic hash across invocations"
else
  fail_case "whitespace-normalized lesson text has a deterministic hash across invocations" "keys=$key_normal/$key_spaced"
fi

hash_ascii_quote=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" "- 2026-07-06 Use 'retry' after failure. (source: distill-audit)")
hash_smart_quote=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Use ‘retry’ after failure. (source: distill-audit)')
if [ "$hash_ascii_quote" = "$hash_smart_quote" ]; then
  pass "smart apostrophes map to ASCII only in the candidate hash"
else
  fail_case "smart apostrophes map to ASCII only in the candidate hash" \
    "hashes=$hash_ascii_quote/$hash_smart_quote"
fi

hash_ascii_space=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Keep retry budget bounded. (source: distill-audit)')
hash_nbsp=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" $'- 2026-07-06 Keep\xc2\xa0retry budget bounded. (source: distill-audit)')
if [ "$hash_ascii_space" = "$hash_nbsp" ]; then
  pass "NBSP maps to an ordinary space in the candidate hash"
else
  fail_case "NBSP maps to an ordinary space in the candidate hash" \
    "hashes=$hash_ascii_space/$hash_nbsp"
fi

hash_ascii_width=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Retry ID ABC-123. (source: distill-audit)')
hash_fullwidth=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Ｒｅｔｒｙ ＩＤ ＡＢＣ－１２３． (source: distill-audit)')
if [ "$hash_ascii_width" = "$hash_fullwidth" ]; then
  pass "NFKC folds fullwidth ASCII in the candidate hash"
else
  fail_case "NFKC folds fullwidth ASCII in the candidate hash" \
    "hashes=$hash_ascii_width/$hash_fullwidth"
fi

hash_latin_a=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Keep route A distinct. (source: distill-audit)')
hash_greek_alpha=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 Keep route Α distinct. (source: distill-audit)')
if [ "$hash_latin_a" != "$hash_greek_alpha" ]; then
  pass "NFKC does not collapse a Greek alpha into Latin A"
else
  fail_case "NFKC does not collapse a Greek alpha into Latin A" \
    "hashes=$hash_latin_a/$hash_greek_alpha"
fi

hash_plain=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 normalized lesson (source: distill-audit)')
hash_mech=$(bash -c 'source "$1"; candidate_lesson_hash "$2"' _ "$STATE_FOLD_LIB" '- 2026-07-06 normalized lesson (source: distill-audit) [mech_check: yes]')
rm -f "$ws/loop/.distill-last-run"
reply_mech=$'## LESSONS\n- 2026-07-06 normalized lesson (source: distill-audit) [mech_check: yes]\n## OPEN_FAILURES\n## SKILL_DRAFTS'
DISTILL_REPLY="$reply_mech" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" >/dev/null 2>&1
key_mech=$(sed -n 's/.*\[dedup_key: \([^]]*\)\]$/\1/p' "$ws/loop/pending/distill-$utc_date.md" | sed -n '1p')
state_lines=$(grep -F 'normalized lesson' "$ws/STATE.md" 2>/dev/null | tr '\n' ';')
if [ "$hash_plain" = "$hash_mech" ] \
  && [ "$key_normal" = "$key_mech" ] \
  && [ "$(grep -Fc 'normalized lesson' "$ws/STATE.md")" -eq 1 ] \
  && grep -Fq -- '- 2026-07-06 normalized lesson (source: distill-audit) [mech_check: yes] [dedup_key: ' "$ws/loop/pending/distill-$utc_date.md"; then
  pass "mech-check lessons keep the same candidate hash and dedup key as plain lessons"
else
  fail_case "mech-check lessons keep the same candidate hash and dedup key as plain lessons" "hashes=$hash_plain/$hash_mech keys=$key_normal/$key_mech state=$state_lines"
fi

split_reply=$TMP_ROOT/split-mech-check.reply.md
split_lessons=$TMP_ROOT/split-mech-check.lessons.txt
split_failures=$TMP_ROOT/split-mech-check.failures.txt
split_key=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
split_line='- 2026-07-06 independently observed lesson (source: distill-audit) [mech_check: yes]'
printf '## LESSONS\n%s [dedup_key: %s]\n## OPEN_FAILURES\n## SKILL_DRAFTS\n' \
  "$split_line" "$split_key" >"$split_reply"
: >"$split_lessons"
: >"$split_failures"
bash -c '
  source "$1"
  split_annotated_reply_sections "$2" "$3" "$4" \
    "(source: distill-audit)" "LESSONS|OPEN_FAILURES"
' _ "$STATE_FOLD_LIB" "$split_reply" "$split_lessons" "$split_failures"
split_rc=$?
if [ "$split_rc" -eq 0 ] \
  && grep -Fqx -- "$split_key"$'\t'"$split_line" "$split_lessons" \
  && [ "$(wc -l <"$split_lessons" | tr -d '[:space:]')" -eq 1 ] \
  && [ ! -s "$split_failures" ]; then
  pass "split keeps a mech-check lesson and its dedup key in LESSONS"
else
  fail_case "split keeps a mech-check lesson and its dedup key in LESSONS" \
    "rc=$split_rc lessons=$(tr '\n' ';' <"$split_lessons")"
fi

# A malformed legacy annotation must not suppress a new valid key for the same text.
ws=$(make_ws malformed)
cat >"$ws/loop/pending/distill-legacy.md" <<'OUT'
## LESSONS
- 2026-07-06 legacy distinct lesson (source: distill-audit) [dedup_key: malformed]
OUT
reply_legacy=$'## LESSONS\n- 2026-07-06 legacy distinct lesson (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
output=$(DISTILL_REPLY="$reply_legacy" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(section_count_text '- 2026-07-06 legacy distinct lesson (source: distill-audit)' "$ws/STATE.md")" -eq 1 ]; then
  pass "malformed or missing legacy keys remain distinct"
else
  fail_case "malformed or missing legacy keys remain distinct" "rc=$rc output=$output"
fi

# New normalization is append-only. A legacy annotation remains byte-for-byte
# intact; because its old hash is not migrated, one duplicate may cross the
# old-key/new-key boundary before the normalized key is recorded.
ws=$(make_ws append-only-key-boundary)
legacy_task_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
legacy_lesson_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
legacy_line="- 2026-07-06 Don’t retry route Ａ. (source: distill-audit) [dedup_key: $legacy_task_hash:$legacy_lesson_hash]"
sed "/^## Last session/i\\
$legacy_line" "$ws/STATE.md" >"$TMP_ROOT/state-with-legacy-key"
mv "$TMP_ROOT/state-with-legacy-key" "$ws/STATE.md"
cp "$ws/STATE.md" "$TMP_ROOT/state-before-append"
reply_append=$'## LESSONS\n- 2026-07-06 Don\'t retry route A. (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
output=$(DISTILL_REPLY="$reply_append" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
appended_line="- 2026-07-06 Don't retry route A. (source: distill-audit)"
grep -Fvx -- "$appended_line" "$ws/STATE.md" >"$TMP_ROOT/state-without-append"
if [ "$rc" -eq 0 ] \
  && grep -Fqx -- "$legacy_line" "$ws/STATE.md" \
  && grep -Fqx -- "$appended_line" "$ws/STATE.md" \
  && cmp -s "$TMP_ROOT/state-before-append" "$TMP_ROOT/state-without-append"; then
  pass "legacy STATE dedup annotations remain byte-identical across the append-only key boundary"
else
  fail_case "legacy STATE dedup annotations remain byte-identical across the append-only key boundary" \
    "rc=$rc output=$output legacy_count=$(grep -Fxc -- "$legacy_line" "$ws/STATE.md")"
fi

# Same-day replacements must retain prior keys so A -> B -> whitespace-variant A
# cannot fold A a second time after B replaces the day's pending record.
ws=$(make_ws same-day-replace)
reply_a=$'## LESSONS\n- 2026-07-06 replacement lesson A (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
reply_b=$'## LESSONS\n- 2026-07-06 replacement lesson B (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
reply_a_variant=$'## LESSONS\n- 2026-07-06   replacement    lesson A (source: distill-audit)\n## OPEN_FAILURES\n## SKILL_DRAFTS'
DISTILL_REPLY="$reply_a" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" >/dev/null 2>&1
rm -f "$ws/loop/.distill-last-run"
DISTILL_REPLY="$reply_b" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" >/dev/null 2>&1
rm -f "$ws/loop/.distill-last-run"
output=$(DISTILL_REPLY="$reply_a_variant" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(section_count_text '- 2026-07-06 replacement lesson A (source: distill-audit)' "$ws/STATE.md")" -eq 1 ] \
  && [ "$(section_count_text '- 2026-07-06 replacement lesson B (source: distill-audit)' "$ws/STATE.md")" -eq 1 ]; then
  pass "same-day pending replacement preserves A to B to A dedup history"
else
  fail_case "same-day pending replacement preserves A to B to A dedup history" "rc=$rc output=$output a_count=$(section_count_text '- 2026-07-06 replacement lesson A (source: distill-audit)' "$ws/STATE.md") b_count=$(section_count_text '- 2026-07-06 replacement lesson B (source: distill-audit)' "$ws/STATE.md")"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
