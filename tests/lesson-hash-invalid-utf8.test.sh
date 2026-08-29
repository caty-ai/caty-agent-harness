#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
STATE_FOLD_LIB=$ROOT/scripts/lib-state-fold.sh
INTAKE=$ROOT/adapters/claude-code/flush-intake.sh
TMP_ROOT=${TMPDIR:-/tmp}/lesson-hash-invalid-utf8-test.$$
EMPTY_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
ASCII_EXPECTED=b238af1ca82d4fcba0c46adc0ab0125c73f0b53e0065365158ea0d03de83a879
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

receipt_value() {
  local workspace=$1
  local key=$2
  tail -n 1 "$workspace/loop/pending/intake-runs.log" \
    | tr ' ' '\n' | sed -n "s/^$key=//p" | head -n 1
}

hash_candidate() {
  local candidate=$1
  local output=$2
  bash -c 'source "$1"; set +e; candidate_lesson_hash "$2"' _ \
    "$STATE_FOLD_LIB" "$candidate" >"$output" 2>/dev/null
}

hash_candidate_with_normalizer() {
  local candidate=$1
  local normalizer_mode=$2
  local output=$3
  bash -c '
    source "$1"
    set +e
    case "$2" in
      awk-failure)
        normalize_state_candidate() { return 1; }
        ;;
      partial-failure)
        normalize_state_candidate() { printf "partial\n"; return 1; }
        ;;
      python-failure)
        normalize_state_candidate() { printf "%s\n" "$1"; }
        ;;
    esac
    candidate_lesson_hash "$3"
  ' _ "$STATE_FOLD_LIB" "$normalizer_mode" "$candidate" >"$output" 2>/dev/null
}

invalid_one=$'- 2026-08-29 \xff\xfe broken one (source: distill-audit)'
invalid_two=$'- 2026-08-29 \xff\xfe totally different text (source: distill-audit)'
invalid_one_out=$TMP_ROOT/invalid-one.out
invalid_two_out=$TMP_ROOT/invalid-two.out
set +e
hash_candidate "$invalid_one" "$invalid_one_out"
invalid_one_rc=$?
hash_candidate "$invalid_two" "$invalid_two_out"
invalid_two_rc=$?
set -e
if [ "$invalid_one_rc" -ne 0 ] && [ "$invalid_two_rc" -ne 0 ] \
  && [ ! -s "$invalid_one_out" ] && [ ! -s "$invalid_two_out" ]; then
  pass 'different invalid-UTF-8 lessons are both refused without output'
else
  fail_case 'different invalid-UTF-8 lessons are both refused without output' \
    "rcs=$invalid_one_rc/$invalid_two_rc outputs=$(tr '\n' ';' <"$invalid_one_out")/$(tr '\n' ';' <"$invalid_two_out")"
fi

quiet_out=$TMP_ROOT/quiet-invalid.out
quiet_err=$TMP_ROOT/quiet-invalid.err
set +e
bash -c '
  source "$1"
  set +e
  normalize_state_candidate() { printf "%s\n" "$1"; }
  candidate_lesson_hash "$2"
' _ "$STATE_FOLD_LIB" "$invalid_one" >"$quiet_out" 2>"$quiet_err"
quiet_rc=$?
set -e
if [ "$quiet_rc" -ne 0 ] && [ ! -s "$quiet_out" ] && [ ! -s "$quiet_err" ]; then
  pass 'invalid-UTF-8 encode refusal is quiet'
else
  fail_case 'invalid-UTF-8 encode refusal is quiet' \
    "rc=$quiet_rc stdout=$(LC_ALL=C sed -n l "$quiet_out") stderr=$(LC_ALL=C sed -n l "$quiet_err")"
fi

awk_failure_out=$TMP_ROOT/awk-failure.out
python_failure_out=$TMP_ROOT/python-failure.out
set +e
hash_candidate_with_normalizer 'ordinary text' awk-failure "$awk_failure_out"
awk_failure_rc=$?
hash_candidate_with_normalizer "$invalid_one" python-failure "$python_failure_out"
python_failure_rc=$?
set -e
if [ "$awk_failure_rc" -ne 0 ] && [ "$python_failure_rc" -ne 0 ] \
  && [ ! -s "$awk_failure_out" ] && [ ! -s "$python_failure_out" ]; then
  pass 'awk-stage and Python-stage failures independently refuse hashing'
else
  fail_case 'awk-stage and Python-stage failures independently refuse hashing' \
    "rcs=$awk_failure_rc/$python_failure_rc outputs=$(tr '\n' ';' <"$awk_failure_out")/$(tr '\n' ';' <"$python_failure_out")"
fi

partial_failure_out=$TMP_ROOT/partial-failure.out
set +e
hash_candidate_with_normalizer 'ordinary text' partial-failure "$partial_failure_out"
partial_failure_rc=$?
set -e
if [ "$partial_failure_rc" -ne 0 ] && [ ! -s "$partial_failure_out" ]; then
  pass 'partial normalizer output with failure status is refused'
else
  fail_case 'partial normalizer output with failure status is refused' \
    "rc=$partial_failure_rc output=$(tr '\n' ';' <"$partial_failure_out")"
fi

key_text_empty_out=$TMP_ROOT/key-text-empty.out
set +e
bash -c '
  source "$1"
  set +e
  normalize_state_candidate() { return 0; }
  normalize_state_candidate_key_text "ordinary text"
' _ "$STATE_FOLD_LIB" >"$key_text_empty_out" 2>/dev/null
key_text_empty_rc=$?
set -e
if [ "$key_text_empty_rc" -ne 0 ] && [ ! -s "$key_text_empty_out" ]; then
  pass 'key-text normalization refuses empty output for non-empty input'
else
  fail_case 'key-text normalization refuses empty output for non-empty input' \
    "rc=$key_text_empty_rc output=$(tr '\n' ';' <"$key_text_empty_out")"
fi

empty_out=$TMP_ROOT/empty.out
normalized_empty_out=$TMP_ROOT/normalized-empty.out
set +e
hash_candidate '' "$empty_out"
empty_rc=$?
hash_candidate '   ' "$normalized_empty_out"
normalized_empty_rc=$?
set -e
if [ "$empty_rc" -ne 0 ] && [ "$normalized_empty_rc" -ne 0 ] \
  && [ ! -s "$empty_out" ] && [ ! -s "$normalized_empty_out" ]; then
  pass 'empty and empty-normalized lessons are refused without output'
else
  fail_case 'empty and empty-normalized lessons are refused without output' \
    "rcs=$empty_rc/$normalized_empty_rc outputs=$(tr '\n' ';' <"$empty_out")/$(tr '\n' ';' <"$normalized_empty_out")"
fi

if ! grep -Fqx -- "$EMPTY_SHA256" "$invalid_one_out" "$invalid_two_out" \
  "$awk_failure_out" "$python_failure_out" "$empty_out" "$normalized_empty_out"; then
  pass 'sha256 of empty text is never emitted as a lesson key'
else
  fail_case 'sha256 of empty text is never emitted as a lesson key' 'empty digest was emitted'
fi

reply=$TMP_ROOT/invalid.reply
annotated=$TMP_ROOT/invalid.annotated
{
  printf '%s\n' '## LESSONS'
  printf '%s\n' "$invalid_one"
} >"$reply"
: >"$annotated"
set +e
bash -c '
  source "$1"
  set +e
  annotate_reply_dedup_keys "$2" \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    "$3" "(source: distill-audit)" "LESSONS|OPEN_FAILURES"
' _ "$STATE_FOLD_LIB" "$reply" "$annotated" 2>/dev/null
annotate_rc=$?
set -e
if [ "$annotate_rc" -eq 0 ] \
  && [ "$(wc -l <"$annotated" | tr -d '[:space:]')" -eq 1 ] \
  && grep -Fqx -- '## LESSONS' "$annotated" \
  && ! LC_ALL=C grep -Fq '[dedup_key:' "$annotated"; then
  pass 'annotation drops a refused lesson instead of emitting an empty key'
else
  fail_case 'annotation drops a refused lesson instead of emitting an empty key' \
    "rc=$annotate_rc output=$(LC_ALL=C sed -n l "$annotated")"
fi

state=$TMP_ROOT/state.md
normalized_state=$TMP_ROOT/state.normalized
{
  printf '%s\n' '## Lessons learned'
  printf '%s\n' "$invalid_one"
  printf '%s\n' '- 2026-08-29 valid historical lesson (source: distill-audit)'
  printf '%s\n' '## Open failures'
} >"$state"
set +e
bash -c '
  source "$1"
  set +e
  snapshot_state_normalized_candidates "$2" "$3" "## Lessons learned"
' _ "$STATE_FOLD_LIB" "$state" "$normalized_state" 2>/dev/null
snapshot_rc=$?
set -e
if [ "$snapshot_rc" -eq 0 ] \
  && [ "$(wc -l <"$normalized_state" | tr -d '[:space:]')" -eq 1 ] \
  && grep -Fqx -- 'valid historical lesson' "$normalized_state"; then
  pass 'STATE snapshot skips a refused historical line without adding an empty entry'
else
  fail_case 'STATE snapshot skips a refused historical line without adding an empty entry' \
    "rc=$snapshot_rc output=$(LC_ALL=C sed -n l "$normalized_state")"
fi

prior_hashes=$TMP_ROOT/prior.hashes
batch_hashes=$TMP_ROOT/batch.hashes
empty_normalized_state=$TMP_ROOT/empty-normalized-state
: >"$prior_hashes"
: >"$batch_hashes"
printf '\n' >"$empty_normalized_state"
set +e
bash -c '
  source "$1"
  set +e
  state_fold_candidate_is_duplicate \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    "$2" "$3" "$4" "$5" "$6"
' _ "$STATE_FOLD_LIB" "$invalid_one" "$prior_hashes" "$batch_hashes" \
  "$state" "$empty_normalized_state" 2>/dev/null
duplicate_rc=$?
set -e
if [ "$duplicate_rc" -ne 0 ]; then
  pass 'normalization failure cannot match an empty normalized-state entry'
else
  fail_case 'normalization failure cannot match an empty normalized-state entry' \
    'invalid candidate was treated as a duplicate'
fi

workspace=$TMP_ROOT/intake-workspace
"$ROOT/scripts/loop-init" --workspace "$workspace" >/dev/null
invalid_flush=$workspace/loop/pending/flush-2026-07-22.md
{
  printf '%s\n' '<!-- flush ts=2026-07-22T01:02:03Z outcome=ok -->'
  printf -- '- Invalid UTF-8 \377\376 candidate is refused.\n'
} >"$invalid_flush"
cp "$invalid_flush" "$TMP_ROOT/invalid-utf8-original.md"
intake_trace=$TMP_ROOT/intake.trace
: >"$intake_trace"
set +e
STATE_FOLD_TEST_TRACE_FILE="$intake_trace" INTAKE_LOCK_SLEEP_S=0 "$INTAKE" "$workspace" \
  >"$TMP_ROOT/intake.out" 2>"$TMP_ROOT/intake.err"
intake_rc=$?
set -e
if [ "$intake_rc" -eq 0 ] \
  && [ "$(receipt_value "$workspace" candidates)" -eq 1 ] \
  && [ "$(receipt_value "$workspace" rejected)" -eq 1 ] \
  && [ "$(receipt_value "$workspace" folded)" -eq 0 ] \
  && [ "$(receipt_value "$workspace" deduped)" -eq 0 ] \
  && ! LC_ALL=C grep -Fq 'Invalid UTF-8' "$workspace/STATE.md" \
  && cmp -s "$TMP_ROOT/invalid-utf8-original.md" \
    "$workspace/loop/archive/flush-2026-07-22.md"; then
  pass 'intake rejects invalid UTF-8 visibly and archives the raw file byte-identically'
else
  fail_case 'intake rejects invalid UTF-8 visibly and archives the raw file byte-identically' \
    "rc=$intake_rc receipt=$(tail -n 1 "$workspace/loop/pending/intake-runs.log" 2>/dev/null)"
fi

if ! grep -Eq '^(annotate|dedup)$' "$intake_trace"; then
  pass 'intake invalid-UTF-8 validation stops before annotation and dedup'
else
  fail_case 'intake invalid-UTF-8 validation stops before annotation and dedup' \
    "trace=$(tr '\n' ',' <"$intake_trace")"
fi

ascii_out=$TMP_ROOT/ascii.out
if hash_candidate '- 2026-08-29 plain ASCII control (source: distill-audit)' "$ascii_out" \
  && [ "$(cat "$ascii_out")" = "$ASCII_EXPECTED" ]; then
  pass 'plain-ASCII lesson keeps its pre-fix hash'
else
  fail_case 'plain-ASCII lesson keeps its pre-fix hash' \
    "actual=$(cat "$ascii_out" 2>/dev/null) expected=$ASCII_EXPECTED"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
