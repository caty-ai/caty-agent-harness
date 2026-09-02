#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
RAW_REVIEW=$ROOT/scripts/raw-review.sh
TMP_ROOT=${TMPDIR:-/tmp}/raw-review-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_ROOT"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail_case() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

new_ws() {
  local name=$1
  local ws=$TMP_ROOT/$name
  "$ROOT/scripts/loop-init" --workspace "$ws" >/dev/null
  printf '%s\n' "$ws"
}

seed_two_weeks() {
  local ws=$1
  printf '%s\n' '<!-- flush origin=fixture session=session-a ts=2026-08-10T01:00:00Z -->' '- 2026-08-10 Durable retries need bounded backoff and receipts.' \
    >"$ws/loop/archive/flush-2026-08-10.md"
  printf '%s\n' '<!-- flush origin=fixture session=session-b ts=2026-08-17T01:00:00Z -->' '- 2026-08-17 Retry loops should cap backoff and leave an explicit receipt.' \
    >"$ws/loop/archive/flush-2026-08-17.md"
  printf '%s\n' '<!-- intake evictions -->' '- 2026-08-18 Evicted lessons remain reviewable in the raw layer.' \
    >"$ws/loop/archive/intake-evictions-2026-08-18.md"
}

seed_same_week_sessions() {
  local ws=$1 first_session=$2 second_session=$3
  printf '%s\n' \
    "<!-- flush origin=fixture session=$first_session ts=2026-08-10T01:00:00Z -->" \
    '- 2026-08-10 Session alpha records bounded retry guidance.' \
    "<!-- flush origin=fixture session=$second_session ts=2026-08-10T02:00:00Z -->" \
    '- 2026-08-10 Session beta independently records retry receipts.' \
    >"$ws/loop/archive/flush-2026-08-10.md"
}

seed_intake_eviction_sessions() {
  local ws=$1
  printf '%s\n' \
    '<!-- intake eviction adapter=claude-code ts=2026-08-10T01:00:00Z -->' \
    '- 2026-08-10 First evicted block records bounded retry guidance.' \
    '<!-- intake eviction adapter=codex ts=2026-08-10T02:00:00Z -->' \
    '- 2026-08-10 Second evicted block independently records retry receipts.' \
    >"$ws/loop/archive/intake-evictions-2026-08-10.md"
}

write_reviewer() {
  local path=$1 body=$2
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -u'
    printf '%s\n' "$body"
  } >"$path"
  chmod +x "$path"
}

GOOD=$TMP_ROOT/good-reviewer
write_reviewer "$GOOD" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: bounded retries
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:- 2026-08-10 Durable retries need bounded backoff
- flush-2026-08-17.md:- 2026-08-17 Retry loops should cap backoff
WEEKS: 1900-W01
EVIDENCE: The two weeks express the same operational rule in different words.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'

SAME_WEEK=$TMP_ROOT/same-week-reviewer
write_reviewer "$SAME_WEEK" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: same-week session recurrence
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Session alpha records bounded retry guidance
- flush-2026-08-10.md:Session beta independently records retry receipts
WEEKS: 2026-W33
EVIDENCE: The citations are independently attributable by their enclosing flush headers.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'

INTAKE_EVICTIONS=$TMP_ROOT/intake-evictions-reviewer
write_reviewer "$INTAKE_EVICTIONS" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: intake eviction recurrence
CLASS: capability-fact
MEMBERS:
- intake-evictions-2026-08-10.md:First evicted block records bounded retry guidance
- intake-evictions-2026-08-10.md:Second evicted block independently records retry receipts
WEEKS: 2026-W33
EVIDENCE: Production intake-eviction headers delimit independently attributable blocks.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'

NO_GROUPS=$TMP_ROOT/no-groups-reviewer
write_reviewer "$NO_GROUPS" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END'

VACUOUS=$TMP_ROOT/vacuous-reviewer
write_reviewer "$VACUOUS" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN RAW-REVIEW-OUTPUT-END'

CAPTURE=$TMP_ROOT/capture-reviewer
write_reviewer "$CAPTURE" 'capture=$1
cat >"$capture"
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: bounded retries
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:- 2026-08-10 Durable retries need bounded backoff
- flush-2026-08-17.md:- 2026-08-17 Retry loops should cap backoff
WEEKS: 2026-W33,2026-W34
EVIDENCE: Paraphrased recurrence.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'

write_conf() {
  local ws=$1 producer=$2
  shift 2
  {
    printf 'producer=%s\n' "$producer"
    while [[ $# -gt 0 ]]; do printf 'reviewer %s\n' "$1"; shift; done
    printf '%s\n' 'review_window_weeks=2' 'reviewer_timeout_s=10' \
      'fabricated_floor=2' 'zero_streak_threshold=2' 'prompt_max_bytes=2000000'
  } >"$ws/loop/review.conf"
}

latest_candidate() { find "$1/loop/promotions" -type f -name 'candidates-*.md' ! -name '*.rejects.md' | LC_ALL=C sort | tail -n 1; }

ws=$(new_ws promote)
promote_ws=$ws
seed_two_weeks "$ws"
capture=$TMP_ROOT/captured-prompt
write_conf "$ws" producer-model "fixture $CAPTURE $capture"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >"$TMP_ROOT/promote.out" 2>"$TMP_ROOT/promote.err"
rc=$?
candidate=$(latest_candidate "$ws")
if [[ "$rc" -eq 0 && -f "$candidate" ]] \
  && grep -Fq 'run-k: 2' "$candidate" && grep -Fq 'promote: yes' "$candidate" \
  && grep -Fq 'RAW-FILE: loop/archive/intake-evictions-2026-08-18.md' "$capture" \
  && grep -Fq 'Evicted lessons remain reviewable' "$capture"; then
  pass '[1] paraphrased cross-week citations promote with host K=2 and evictions stay whole'
else
  fail_case '[1] paraphrased cross-week citations promote with host K=2 and evictions stay whole' "rc=$rc candidate=$candidate stderr=$(cat "$TMP_ROOT/promote.err")"
fi

ws=$(new_ws intake-eviction-sessions)
seed_intake_eviction_sessions "$ws"
write_conf "$ws" producer-model "fixture $INTAKE_EVICTIONS"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/intake-eviction-sessions.err"
rc=$?
candidate=$(latest_candidate "$ws")
if [[ "$rc" -eq 0 && -f "$candidate" ]] \
  && grep -Fq 'run-k: 2' "$candidate" \
  && grep -Fq 'promote: yes' "$candidate" \
  && grep -Fq 'run-sessions: 2' "$ws/loop/promotions/ledger.md"; then
  pass '[263-6] production intake-eviction headers without session ids use per-block pseudo-sessions'
else
  fail_case '[263-6] production intake-eviction headers without session ids use per-block pseudo-sessions' "rc=$rc candidate=$(cat "$candidate" 2>/dev/null)"
fi

ws=$(new_ws sessions-same-week)
seed_same_week_sessions "$ws" session-alpha session-beta
write_conf "$ws" producer-model "fixture $SAME_WEEK"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/sessions-same-week.err"
rc=$?
candidate=$(latest_candidate "$ws")
if [[ "$rc" -eq 0 && -f "$candidate" ]] \
  && grep -Fq 'run-k: 2' "$candidate" \
  && grep -Fq 'promote: yes' "$candidate" \
  && ! grep -Fq 'run-sessions:' "$candidate" \
  && grep -Fq 'run-sessions: 2' "$ws/loop/promotions/ledger.md"; then
  pass '[263-1] default sessions mode promotes two distinct sessions in one ISO week'
else
  fail_case '[263-1] default sessions mode promotes two distinct sessions in one ISO week' "rc=$rc candidate=$(cat "$candidate" 2>/dev/null)"
fi

ws=$(new_ws sessions-same-id)
seed_same_week_sessions "$ws" session-shared session-shared
write_conf "$ws" producer-model "fixture $SAME_WEEK"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/sessions-same-id.err"
rc=$?
candidate=$(latest_candidate "$ws")
if [[ "$rc" -eq 0 && -f "$candidate" ]] \
  && grep -Fq 'run-k: 1' "$candidate" \
  && grep -Fq 'promote: not-yet' "$candidate" \
  && grep -Fq 'run-sessions: 1' "$ws/loop/promotions/ledger.md"; then
  pass '[263-2] default sessions mode does not count two members from one session twice'
else
  fail_case '[263-2] default sessions mode does not count two members from one session twice' "rc=$rc candidate=$(cat "$candidate" 2>/dev/null)"
fi

ws=$(new_ws weeks-same-week)
seed_same_week_sessions "$ws" session-alpha session-beta
write_conf "$ws" producer-model "fixture $SAME_WEEK"
printf '%s\n' 'recurrence_unit=weeks' >>"$ws/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/weeks-same-week.err"
same_week_rc=$?
same_week_candidate=$(latest_candidate "$ws")
ws_cross_week=$(new_ws weeks-cross-week)
seed_two_weeks "$ws_cross_week"
write_conf "$ws_cross_week" producer-model "fixture $GOOD"
printf '%s\n' 'recurrence_unit=weeks' >>"$ws_cross_week/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_cross_week" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/weeks-cross-week.err"
cross_week_rc=$?
cross_week_candidate=$(latest_candidate "$ws_cross_week")
if [[ "$same_week_rc" -eq 0 && "$cross_week_rc" -eq 0 ]] \
  && grep -Fq 'run-weeks: 2026-W33' "$same_week_candidate" \
  && grep -Fq 'run-k: 1' "$same_week_candidate" \
  && grep -Fq 'promote: not-yet' "$same_week_candidate" \
  && grep -Fq 'run-weeks: 2026-W33,2026-W34' "$cross_week_candidate" \
  && grep -Fq 'run-k: 2' "$cross_week_candidate" \
  && grep -Fq 'promote: yes' "$cross_week_candidate" \
  && ! grep -Fq 'run-sessions:' "$same_week_candidate" \
  && ! grep -Fq 'run-sessions:' "$cross_week_candidate"; then
  pass '[263-3] weeks mode preserves same-week downgrade and cross-week promotion semantics'
else
  fail_case '[263-3] weeks mode preserves same-week downgrade and cross-week promotion semantics' "rcs=$same_week_rc/$cross_week_rc"
fi

ws=$(new_ws sessions-min-weeks)
seed_same_week_sessions "$ws" session-alpha session-beta
write_conf "$ws" producer-model "fixture $SAME_WEEK"
printf '%s\n' 'promote_min_weeks=2' >>"$ws/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/sessions-min-weeks.err"
rc=$?
candidate=$(latest_candidate "$ws")
if [[ "$rc" -eq 0 && -f "$candidate" ]] \
  && grep -Fq 'run-k: 2' "$candidate" \
  && grep -Fq 'promote: not-yet' "$candidate"; then
  pass '[263-4] sessions mode also enforces a configured minimum ISO-week spread'
else
  fail_case '[263-4] sessions mode also enforces a configured minimum ISO-week spread' "rc=$rc candidate=$(cat "$candidate" 2>/dev/null)"
fi

invalid_config_rcs=
invalid_config_receipts=1
for invalid_config in 'recurrence_unit=days' 'promote_min_k=0' 'promote_min_weeks=-1'; do
  invalid_name=${invalid_config%%=*}
  ws=$(new_ws "invalid-$invalid_name")
  seed_two_weeks "$ws"
  write_conf "$ws" producer-model "fixture $GOOD"
  printf '%s\n' "$invalid_config" >>"$ws/loop/review.conf"
  "$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/invalid-$invalid_name.err"
  invalid_rc=$?
  invalid_config_rcs="$invalid_config_rcs/$invalid_rc"
  [[ "$invalid_rc" -eq 2 \
    && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=config' ]] \
    || invalid_config_receipts=0
done
if [[ "$invalid_config_receipts" -eq 1 ]]; then
  pass '[263-5] invalid recurrence unit and promotion thresholds fail closed as config errors'
else
  fail_case '[263-5] invalid recurrence unit and promotion thresholds fail closed as config errors' "rcs=$invalid_config_rcs"
fi

receipt=$(tail -n 1 "$promote_ws/loop/promotions/runs.log")
actual_bytes=$(wc -c <"$capture" | tr -d '[:space:]')
recorded_bytes=$(printf '%s\n' "$receipt" | sed -n 's/.* prompt_bytes=\([0-9][0-9]*\) .*/\1/p')
if [[ "$recorded_bytes" == "$actual_bytes" && "$receipt" == *' mode=retro unit=sessions '* && "$receipt" == *' error=none' ]] \
  && grep -Fq 'Emit no more than 30 THEME blocks' "$capture" \
  && grep -Fq 'at most five MEMBERS citations per theme' "$capture" \
  && grep -Fq 'conservative machine tags' "$capture" \
  && grep -Fq 'paired emphasis markers' "$capture" \
  && grep -Fq 'meaningful lone `*` token' "$capture" \
  && grep -Fq 'configured unit (distinct sessions or ISO weeks)' "$capture" \
  && grep -Fq 'trying to infer which recurrence unit is active' "$capture" \
  && ! grep -Fq 'default unit' "$capture"; then
  pass '[2] prompt bytes, output budget, and retro receipt fields are pinned'
else
  fail_case '[2] prompt bytes, output budget, and retro receipt fields are pinned' "actual=$actual_bytes receipt=$receipt"
fi

ws=$(new_ws dry)
seed_two_weeks "$ws"
printf '7\n' >"$ws/loop/promotions/.zero-streak"
called=$TMP_ROOT/dry-called
DRY_REVIEWER=$TMP_ROOT/dry-reviewer
write_reviewer "$DRY_REVIEWER" "touch '$called'; cat >/dev/null"
write_conf "$ws" producer-model "fixture $DRY_REVIEWER"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 --dry-run >"$TMP_ROOT/dry.out" 2>"$TMP_ROOT/dry.err"
rc=$?
if [[ "$rc" -eq 0 && ! -e "$called" ]] && grep -q '^prompt_bytes=[0-9][0-9]*$' "$TMP_ROOT/dry.out" \
  && grep -Fq 'loop/archive/flush-2026-08-10.md' "$TMP_ROOT/dry.out" \
  && [[ "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' mode=dry '* ]] \
  && [[ "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' zero_streak=7 '* ]] \
  && [[ ! -e "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]]; then
  pass '[3] dry-run validates and lists the complete window without model egress or notification'
else
  fail_case '[3] dry-run validates and lists the complete window without model egress or notification' "rc=$rc called=$([[ -e "$called" ]] && printf yes || printf no) receipt=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

ws=$(new_ws no-groups)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $NO_GROUPS"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/no-groups.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' blocks=0 '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' candidates=0 '* ]]; then
  pass '[4] explicit NO_GROUPS is a non-vacuous zero-candidate success'
else
  fail_case '[4] explicit NO_GROUPS is a non-vacuous zero-candidate success' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

ws=$(new_ws vacuous)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $VACUOUS"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/vacuous.err"
rc=$?
if [[ "$rc" -eq 1 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=chain-exhausted' \
  && -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]]; then
  pass '[5] zero blocks without NO_GROUPS fails closed and notifies'
else
  fail_case '[5] zero blocks without NO_GROUPS fails closed and notifies' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

BAD_MARKERS=$TMP_ROOT/bad-markers
write_reviewer "$BAD_MARKERS" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END RAW-REVIEW-OUTPUT-END'
ws=$(new_ws markers)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "bad $BAD_MARKERS" "good $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/markers.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=good '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' chain_pos=2 '* ]]; then
  pass '[6] duplicate output markers fail one entry and advance the chain'
else
  fail_case '[6] duplicate output markers fail one entry and advance the chain' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

LOCK_CHECK=$TMP_ROOT/lock-check-reviewer
lock_seen=$TMP_ROOT/lock-seen-during-model-call
write_reviewer "$LOCK_CHECK" 'lock_path=$1
sentinel=$2
cat >/dev/null
[[ -e "$lock_path" ]] && : >"$sentinel"
sleep 1
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: bounded retries
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:- 2026-08-10 Durable retries need bounded backoff
- flush-2026-08-17.md:- 2026-08-17 Retry loops should cap backoff
WEEKS: 2026-W33,2026-W34
EVIDENCE: Concurrent fixture.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'
ws=$(new_ws overlap)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $LOCK_CHECK $ws/loop/promotions/.lock $lock_seen"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/overlap1.err" &
pid1=$!
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/overlap2.err" &
pid2=$!
wait "$pid1"; rc1=$?
wait "$pid2"; rc2=$?
if [[ "$rc1" -eq 0 && "$rc2" -eq 0 && ! -e "$lock_seen" \
  && "$(awk 'END {print NR + 0}' "$ws/loop/promotions/runs.log")" -eq 2 \
  && "$(find "$ws/loop/promotions" -name 'candidates-*.md' ! -name '*.rejects.md' | wc -l | tr -d ' ')" -eq 2 ]]; then
  pass '[9b] overlapping model calls hold no review lock and both append complete outputs'
else
  fail_case '[9b] overlapping model calls hold no review lock and both append complete outputs' "rc1=$rc1 rc2=$rc2 lock_seen=$([[ -e "$lock_seen" ]] && printf yes || printf no)"
fi

OVER100=$TMP_ROOT/over100
write_reviewer "$OVER100" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN
i=1
while [ "$i" -le 101 ]; do
  printf "%s\n" "THEME: t$i" "CLASS: rule" MEMBERS: "- flush-2026-08-10.md:- 2026-08-10 Durable retries" "WEEKS: 2026-W33" "EVIDENCE: e" "PROMOTE: not-yet"
  i=$((i + 1))
done
printf "%s\n" RAW-REVIEW-OUTPUT-END'
ws=$(new_ws over100-ws)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "too-many $OVER100" "good $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/over100.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=good '* ]]; then
  pass '[7] more than 100 blocks fails the call and advances the chain'
else
  fail_case '[7] more than 100 blocks fails the call and advances the chain' "rc=$rc"
fi

MIXED=$TMP_ROOT/mixed-reviewer
write_reviewer "$MIXED" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: fabricated full block retained
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:This line was never present
WEEKS: 2026-W33
EVIDENCE: must survive in rejects
PROMOTE: yes
THEME: valid first
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:- 2026-08-10 Durable retries
WEEKS: 2026-W33
EVIDENCE: valid
PROMOTE: yes
THEME: valid second
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:- 2026-08-17 Retry loops
WEEKS: 2026-W34
EVIDENCE: valid
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws=$(new_ws rejects)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "mixed $MIXED"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/rejects.err"
rc=$?
reject_file=$(find "$ws/loop/promotions" -name '*.rejects.md' | head -n 1)
if [[ "$rc" -eq 0 && -f "$reject_file" ]] \
  && grep -Fq 'THEME: fabricated full block retained' "$reject_file" \
  && grep -Fq 'EVIDENCE: must survive in rejects' "$reject_file" \
  && grep -Fq 'run-k: 1' "$(latest_candidate "$ws")" \
  && grep -Fq 'promote: not-yet' "$(latest_candidate "$ws")" \
  && [[ "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' fabricated=1 '* ]]; then
  pass '[8] fabricated citation drops the full block and the small-N floor permits valid blocks'
else
  fail_case '[8] fabricated citation drops the full block and the small-N floor permits valid blocks' "rc=$rc reject=$reject_file"
fi

EMPTY_QUOTE=$TMP_ROOT/empty-quote-reviewer
write_reviewer "$EMPTY_QUOTE" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN "THEME: empty quote" "CLASS: rule" MEMBERS:
printf "%s" "- flush-2026-08-10.md:"
printf "   \n"
printf "%s\n" "WEEKS: 2026-W33" "EVIDENCE: invalid normalized quote" "PROMOTE: yes" RAW-REVIEW-OUTPUT-END'
SHORT_QUOTE=$TMP_ROOT/short-quote-reviewer
write_reviewer "$SHORT_QUOTE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: short quote
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Dur
WEEKS: 2026-W33
EVIDENCE: invalid short quote
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'
EIGHT_QUOTE=$TMP_ROOT/eight-quote-reviewer
write_reviewer "$EIGHT_QUOTE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: exact minimum quote
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:Retry lo
WEEKS: 2026-W34
EVIDENCE: exactly eight normalized characters
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_empty=$(new_ws quote-empty)
seed_two_weeks "$ws_empty"
write_conf "$ws_empty" producer-model "empty $EMPTY_QUOTE"
"$RAW_REVIEW" --workspace "$ws_empty" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/quote-empty.err"
empty_rc=$?
ws_short=$(new_ws quote-short)
seed_two_weeks "$ws_short"
write_conf "$ws_short" producer-model "short $SHORT_QUOTE"
"$RAW_REVIEW" --workspace "$ws_short" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/quote-short.err"
short_rc=$?
ws_eight=$(new_ws quote-eight)
seed_two_weeks "$ws_eight"
write_conf "$ws_eight" producer-model "eight $EIGHT_QUOTE"
"$RAW_REVIEW" --workspace "$ws_eight" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/quote-eight.err"
eight_rc=$?
if [[ "$empty_rc" -eq 1 && "$short_rc" -eq 1 && "$eight_rc" -eq 0 \
  && "$(tail -n 1 "$ws_empty/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_empty/loop/promotions/runs.log")" == *' error=chain-exhausted' \
  && "$(tail -n 1 "$ws_short/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_short/loop/promotions/runs.log")" == *' error=chain-exhausted' \
  && "$(tail -n 1 "$ws_eight/loop/promotions/runs.log")" == *' fabricated=0 '* \
  && "$(tail -n 1 "$ws_eight/loop/promotions/runs.log")" == *' candidates=1 '* ]]; then
  pass '[R1-1] normalized quotes below eight characters reject while an eight-character prefix passes'
else
  fail_case '[R1-1] normalized quotes below eight characters reject while an eight-character prefix passes' "rcs=$empty_rc/$short_rc/$eight_rc receipts=$(tail -n 1 "$ws_empty/loop/promotions/runs.log") | $(tail -n 1 "$ws_short/loop/promotions/runs.log") | $(tail -n 1 "$ws_eight/loop/promotions/runs.log")"
fi

REAL_SHAPE=$TMP_ROOT/real-shape-reviewer
write_reviewer "$REAL_SHAPE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: linked worktree commits
CLASS: capability-fact
MEMBERS:
- flush-2026-08-01.md:codex exec `-s workspace-write` は linked git worktree 内で `git commit` できない
WEEKS: 2026-W31
EVIDENCE: Honest lesson-content prefix without storage decoration.
PROMOTE: not-yet
THEME: star bullet and date without colon
CLASS: rule
MEMBERS:
- flush-2026-08-01.md:2026-08-01 **star bullet date without colon remains citable**
WEEKS: 2026-W31
EVIDENCE: Both source and quote require the same comparison canonicalization.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_real_shape=$(new_ws real-shape)
printf '%s\n' \
  '- 2026-08-01: **codex exec `-s workspace-write` は linked git worktree 内で `git commit` できない** — tail' \
  '* 2026-08-01 **star bullet date without colon remains citable** — tail' \
  >"$ws_real_shape/loop/archive/flush-2026-08-01.md"
write_conf "$ws_real_shape" producer-model "real-shape $REAL_SHAPE"
"$RAW_REVIEW" --workspace "$ws_real_shape" --week 2026-W31 >/dev/null 2>"$TMP_ROOT/real-shape.err"
real_shape_rc=$?
variant_hash=$(python3 -B -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' \
  '2026-08-01 **star bullet date without colon remains citable**')
if [[ "$real_shape_rc" -eq 0 \
  && "$(tail -n 1 "$ws_real_shape/loop/promotions/runs.log")" == *' blocks=2 '* \
  && "$(tail -n 1 "$ws_real_shape/loop/promotions/runs.log")" == *' fabricated=0 '* \
  && "$(tail -n 1 "$ws_real_shape/loop/promotions/runs.log")" == *' candidates=2 '* ]] \
  && grep -Fq "member-hash: $variant_hash" "$(latest_candidate "$ws_real_shape")"; then
  pass '[R2-1] real lesson shape and bullet/date/emphasis variants authenticate content prefixes'
else
  fail_case '[R2-1] real lesson shape and bullet/date/emphasis variants authenticate content prefixes' "rc=$real_shape_rc receipt=$(tail -n 1 "$ws_real_shape/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/real-shape.err")"
fi

CANONICAL_REJECTS=$TMP_ROOT/canonical-rejects-reviewer
write_reviewer "$CANONICAL_REJECTS" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: canonicalized mid-line fragment
CLASS: rule
MEMBERS:
- flush-2026-08-01.md:workspace-write` は linked
WEEKS: 2026-W31
EVIDENCE: Canonicalization must preserve prefix anchoring.
PROMOTE: not-yet
THEME: canonicalized whitespace
CLASS: rule
MEMBERS:
- flush-2026-08-01.md:- 2026-08-01: **   **
WEEKS: 2026-W31
EVIDENCE: Minimum length applies after comparison canonicalization.
PROMOTE: not-yet
THEME: cross-line splice
CLASS: rule
MEMBERS:
- flush-2026-08-01.md:codex exec `-s workspace-write` は linked git worktree 内で `git commit` できないmeaningful content
WEEKS: 2026-W31
EVIDENCE: A quote may not join canonicalized source lines.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_canonical_rejects=$(new_ws canonical-rejects)
printf '%s\n' \
  '- 2026-08-01: **codex exec `-s workspace-write` は linked git worktree 内で `git commit` できない** — tail' \
  '- 2026-08-01: **meaningful content**' \
  >"$ws_canonical_rejects/loop/archive/flush-2026-08-01.md"
write_conf "$ws_canonical_rejects" producer-model "canonical-rejects $CANONICAL_REJECTS"
"$RAW_REVIEW" --workspace "$ws_canonical_rejects" --week 2026-W31 >/dev/null 2>"$TMP_ROOT/canonical-rejects.err"
canonical_rejects_rc=$?
if [[ "$canonical_rejects_rc" -eq 1 \
  && "$(tail -n 1 "$ws_canonical_rejects/loop/promotions/runs.log")" == *' fabricated=3 '* \
  && "$(tail -n 1 "$ws_canonical_rejects/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R2-2] canonicalized mid-line, whitespace-only, and cross-line quotes remain rejected'
else
  fail_case '[R2-2] canonicalized mid-line, whitespace-only, and cross-line quotes remain rejected' "rc=$canonical_rejects_rc receipt=$(tail -n 1 "$ws_canonical_rejects/loop/promotions/runs.log")"
fi

BRACKET_TAGS_VALID=$TMP_ROOT/bracket-tags-valid-reviewer
write_reviewer "$BRACKET_TAGS_VALID" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: bracket tag content prefix
CLASS: rule
MEMBERS:
- flush-2026-07-19.md:stdin 二重リダイレクトの罠: `codex exec - < brief.md
WEEKS: 2026-W29
EVIDENCE: Content-anchored quotes should validate after leading date and tag markers.
PROMOTE: not-yet
THEME: quote may include matching tag
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:[session-806] content with a shared leading tag still validates
WEEKS: 2026-W30
EVIDENCE: Shared comparison canonicalization must allow tags on both sides too.
PROMOTE: not-yet
THEME: two leading tags before content
CLASS: rule
MEMBERS:
- flush-2026-07-21.md:content survives two machine tags
WEEKS: 2026-W30
EVIDENCE: Up to two machine-shaped leading tags are comparison-only decoration.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_bracket_tags_valid=$(new_ws bracket-tags-valid)
cat <<'EOF_RAW' >"$ws_bracket_tags_valid/loop/archive/flush-2026-07-19.md"
- 2026-07-19 [session-839] stdin 二重リダイレクトの罠: `codex exec - < brief.md ...` は最後のリダイレクトが勝ち brief が空になる（source tail）
EOF_RAW
cat <<'EOF_RAW' >"$ws_bracket_tags_valid/loop/archive/flush-2026-07-20.md"
- [session-806] content with a shared leading tag still validates
EOF_RAW
cat <<'EOF_RAW' >"$ws_bracket_tags_valid/loop/archive/flush-2026-07-21.md"
- 2026-07-21 [2026-07-21] [session-42] content survives two machine tags
EOF_RAW
write_conf "$ws_bracket_tags_valid" producer-model "bracket-tags-valid $BRACKET_TAGS_VALID"
"$RAW_REVIEW" --workspace "$ws_bracket_tags_valid" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/bracket-tags-valid.err"
bracket_tags_valid_rc=$?
if [[ "$bracket_tags_valid_rc" -eq 0 \
  && "$(tail -n 1 "$ws_bracket_tags_valid/loop/promotions/runs.log")" == *' blocks=3 '* \
  && "$(tail -n 1 "$ws_bracket_tags_valid/loop/promotions/runs.log")" == *' fabricated=0 '* \
  && "$(tail -n 1 "$ws_bracket_tags_valid/loop/promotions/runs.log")" == *' candidates=3 '* ]]; then
  pass '[R3-1] leading bracket tags canonicalize on both sides for content-anchored and tag-inclusive quotes'
else
  fail_case '[R3-1] leading bracket tags canonicalize on both sides for content-anchored and tag-inclusive quotes' "rc=$bracket_tags_valid_rc receipt=$(tail -n 1 "$ws_bracket_tags_valid/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/bracket-tags-valid.err")"
fi

BRACKET_TAGS_MIDLINE=$TMP_ROOT/bracket-tags-midline-reviewer
write_reviewer "$BRACKET_TAGS_MIDLINE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: tagged mid-line fragment
CLASS: rule
MEMBERS:
- flush-2026-07-19.md:最後のリダイレクトが勝ち brief
WEEKS: 2026-W29
EVIDENCE: Prefix anchoring still applies after tag stripping.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_bracket_tags_midline=$(new_ws bracket-tags-midline)
cat <<'EOF_RAW' >"$ws_bracket_tags_midline/loop/archive/flush-2026-07-19.md"
- 2026-07-19 [session-839] stdin 二重リダイレクトの罠: `codex exec - < brief.md ...` は最後のリダイレクトが勝ち brief が空になる（source tail）
EOF_RAW
write_conf "$ws_bracket_tags_midline" producer-model "bracket-tags-midline $BRACKET_TAGS_MIDLINE"
"$RAW_REVIEW" --workspace "$ws_bracket_tags_midline" --week 2026-W29 >/dev/null 2>"$TMP_ROOT/bracket-tags-midline.err"
bracket_tags_midline_rc=$?
if [[ "$bracket_tags_midline_rc" -eq 1 \
  && "$(tail -n 1 "$ws_bracket_tags_midline/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_bracket_tags_midline/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R3-2] bracket stripping does not relax prefix anchoring for mid-line fragments'
else
  fail_case '[R3-2] bracket stripping does not relax prefix anchoring for mid-line fragments' "rc=$bracket_tags_midline_rc receipt=$(tail -n 1 "$ws_bracket_tags_midline/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/bracket-tags-midline.err")"
fi

BRACKET_TAGS_EMPTY=$TMP_ROOT/bracket-tags-empty-reviewer
write_reviewer "$BRACKET_TAGS_EMPTY" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: tag-only quote
CLASS: rule
MEMBERS:
- flush-2026-07-19.md:[session-839]
WEEKS: 2026-W29
EVIDENCE: Empty-after-tag quotes must still fail the minimum-length guard.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_bracket_tags_empty=$(new_ws bracket-tags-empty)
cat <<'EOF_RAW' >"$ws_bracket_tags_empty/loop/archive/flush-2026-07-19.md"
- 2026-07-19 [session-839] stdin 二重リダイレクトの罠: `codex exec - < brief.md ...` は最後のリダイレクトが勝ち brief が空になる（source tail）
EOF_RAW
write_conf "$ws_bracket_tags_empty" producer-model "bracket-tags-empty $BRACKET_TAGS_EMPTY"
"$RAW_REVIEW" --workspace "$ws_bracket_tags_empty" --week 2026-W29 >/dev/null 2>"$TMP_ROOT/bracket-tags-empty.err"
bracket_tags_empty_rc=$?
if [[ "$bracket_tags_empty_rc" -eq 1 \
  && "$(tail -n 1 "$ws_bracket_tags_empty/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_bracket_tags_empty/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R3-3] tag-only quotes still die after bracket stripping empties the canonicalized citation'
else
  fail_case '[R3-3] tag-only quotes still die after bracket stripping empties the canonicalized citation' "rc=$bracket_tags_empty_rc receipt=$(tail -n 1 "$ws_bracket_tags_empty/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/bracket-tags-empty.err")"
fi

CANONICAL_RESIDUE=$TMP_ROOT/canonical-residue-reviewer
write_reviewer "$CANONICAL_RESIDUE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: indented sub-bullet content
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:Parallel supervisor briefs MUST include "write only your file"
WEEKS: 2026-W30
EVIDENCE: Leading indentation before a bullet is comparison-only decoration.
PROMOTE: not-yet
THEME: indented marker on both sides
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:  - Parallel supervisor briefs MUST include "write only your file"
WEEKS: 2026-W30
EVIDENCE: Source and quote use the same indented-bullet canonicalization.
PROMOTE: not-yet
THEME: literal shell ellipsis
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:bash trap: command `$( ... )` retains stdout
WEEKS: 2026-W30
EVIDENCE: A source-authenticated literal ellipsis is not model truncation.
PROMOTE: not-yet
THEME: literal lens ellipsis
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:glm-panel lens "custom: ..." remains a verbatim prefix
WEEKS: 2026-W30
EVIDENCE: Exact source matching authenticates the punctuation.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_canonical_residue=$(new_ws canonical-residue)
cat <<'EOF_RAW' >"$ws_canonical_residue/loop/archive/flush-2026-07-20.md"
  - Parallel supervisor briefs MUST include "write only your file" before delegation.
- 2026-07-21 bash trap: command `$( ... )` retains stdout until descendants close it.
- glm-panel lens "custom: ..." remains a verbatim prefix in the source.
EOF_RAW
write_conf "$ws_canonical_residue" producer-model "canonical-residue $CANONICAL_RESIDUE"
"$RAW_REVIEW" --workspace "$ws_canonical_residue" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/canonical-residue.err"
canonical_residue_rc=$?
if [[ "$canonical_residue_rc" -eq 0 \
  && "$(tail -n 1 "$ws_canonical_residue/loop/promotions/runs.log")" == *' blocks=4 '* \
  && "$(tail -n 1 "$ws_canonical_residue/loop/promotions/runs.log")" == *' fabricated=0 '* \
  && "$(tail -n 1 "$ws_canonical_residue/loop/promotions/runs.log")" == *' candidates=4 '* ]]; then
  pass '[R4-1] indented bullets and source-literal ellipses authenticate as exact prefixes'
else
  fail_case '[R4-1] indented bullets and source-literal ellipses authenticate as exact prefixes' "rc=$canonical_residue_rc receipt=$(tail -n 1 "$ws_canonical_residue/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/canonical-residue.err")"
fi

INDENTED_DECOY=$TMP_ROOT/indented-decoy-reviewer
write_reviewer "$INDENTED_DECOY" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: too-short indented decoy
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:  - Authent
WEEKS: 2026-W30
EVIDENCE: Bullet stripping must not bypass the eight-character floor.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_indented_decoy=$(new_ws indented-decoy)
printf '%s\n' '  - Authentic source content remains longer than the decoy.' \
  >"$ws_indented_decoy/loop/archive/flush-2026-07-20.md"
write_conf "$ws_indented_decoy" producer-model "indented-decoy $INDENTED_DECOY"
"$RAW_REVIEW" --workspace "$ws_indented_decoy" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/indented-decoy.err"
indented_decoy_rc=$?
if [[ "$indented_decoy_rc" -eq 1 \
  && "$(tail -n 1 "$ws_indented_decoy/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_indented_decoy/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R4-2] indented bullet stripping preserves the eight-character citation floor'
else
  fail_case '[R4-2] indented bullet stripping preserves the eight-character citation floor' "rc=$indented_decoy_rc receipt=$(tail -n 1 "$ws_indented_decoy/loop/promotions/runs.log")"
fi

CLASSIFIED_REJECTIONS=$TMP_ROOT/classified-rejections-reviewer
write_reviewer "$CLASSIFIED_REJECTIONS" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: trailing truncation ellipsis
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:model-added truncation needs full text...
WEEKS: 2026-W29
EVIDENCE: A trailing ellipsis that only authenticates after stripping is model-added truncation.
PROMOTE: not-yet
THEME: free-form label skip
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:review diff misses untracked files
WEEKS: 2026-W30
EVIDENCE: Arbitrary labels are not safely strippable.
PROMOTE: not-yet
THEME: mid-line quote
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:side effect starts here
WEEKS: 2026-W30
EVIDENCE: Prefix anchoring remains mandatory.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_classified_rejections=$(new_ws classified-rejections)
cat <<'EOF_RAW' >"$ws_classified_rejections/loop/archive/flush-2026-07-18.md"
- 2026-07-19 stdin trap: `codex exec - < brief.md ... < /dev/null` loses input.
EOF_RAW
cat <<'EOF_RAW' >"$ws_classified_rejections/loop/archive/flush-2026-07-20.md"
- model-added truncation needs full text after this point.
- caty-cloud #7: review diff misses untracked files.
- root cause first; side effect starts here.
EOF_RAW
write_conf "$ws_classified_rejections" producer-model "classified-rejections $CLASSIFIED_REJECTIONS"
"$RAW_REVIEW" --workspace "$ws_classified_rejections" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/classified-rejections.err"
classified_rejections_rc=$?
if [[ "$classified_rejections_rc" -eq 1 \
  && "$(tail -n 1 "$ws_classified_rejections/loop/promotions/runs.log")" == *' blocks=3 '* \
  && "$(tail -n 1 "$ws_classified_rejections/loop/promotions/runs.log")" == *' fabricated=3 '* \
  && "$(tail -n 1 "$ws_classified_rejections/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R4-3] classified truncation, label-skip, and mid-line quotes remain rejected'
else
  fail_case '[R4-3] classified truncation, label-skip, and mid-line quotes remain rejected' "rc=$classified_rejections_rc receipt=$(tail -n 1 "$ws_classified_rejections/loop/promotions/runs.log")"
fi

FABRICATION_BOUNDARY=$TMP_ROOT/fabrication-boundary-reviewer
write_reviewer "$FABRICATION_BOUNDARY" 'fabricated_count=$1
cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN
i=1
while [ "$i" -le 25 ]; do
  printf "THEME: boundary block %s\n" "$i"
  printf "%s\n" "CLASS: rule" MEMBERS:
  if [ "$i" -le "$fabricated_count" ]; then
    printf -- "- flush-2026-08-10.md:fabricated quote %s\n" "$i"
  else
    printf "%s\n" "- flush-2026-08-10.md:Durable r"
  fi
  printf "%s\n" "WEEKS: 2026-W33" "EVIDENCE: boundary" "PROMOTE: not-yet"
  i=$((i + 1))
done
printf "%s\n" RAW-REVIEW-OUTPUT-END'
ws_boundary_ten=$(new_ws boundary-ten)
seed_two_weeks "$ws_boundary_ten"
write_conf "$ws_boundary_ten" producer-model "boundary-ten $FABRICATION_BOUNDARY 10"
"$RAW_REVIEW" --workspace "$ws_boundary_ten" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/boundary-ten.err"
boundary_ten_rc=$?
ws_boundary_thirteen=$(new_ws boundary-thirteen)
seed_two_weeks "$ws_boundary_thirteen"
write_conf "$ws_boundary_thirteen" producer-model "boundary-thirteen $FABRICATION_BOUNDARY 13"
"$RAW_REVIEW" --workspace "$ws_boundary_thirteen" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/boundary-thirteen.err"
boundary_thirteen_rc=$?
boundary_ten_candidate=$(latest_candidate "$ws_boundary_ten")
if [[ "$boundary_ten_rc" -eq 0 && -f "$boundary_ten_candidate" \
  && "$(grep -c '^## theme-' "$boundary_ten_candidate")" -eq 15 \
  && "$(tail -n 1 "$ws_boundary_ten/loop/promotions/runs.log")" == *' blocks=25 '* \
  && "$(tail -n 1 "$ws_boundary_ten/loop/promotions/runs.log")" == *' fabricated=10 '* \
  && "$(tail -n 1 "$ws_boundary_ten/loop/promotions/runs.log")" == *' candidates=15 '* \
  && "$boundary_thirteen_rc" -eq 1 \
  && "$(tail -n 1 "$ws_boundary_thirteen/loop/promotions/runs.log")" == *' blocks=25 '* \
  && "$(tail -n 1 "$ws_boundary_thirteen/loop/promotions/runs.log")" == *' fabricated=13 '* \
  && "$(tail -n 1 "$ws_boundary_thirteen/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R4-4] default whole-call guard accepts 25/10 and fails at the 25/13 half boundary'
else
  fail_case '[R4-4] default whole-call guard accepts 25/10 and fails at the 25/13 half boundary' "rcs=$boundary_ten_rc/$boundary_thirteen_rc ten=$(tail -n 1 "$ws_boundary_ten/loop/promotions/runs.log") thirteen=$(tail -n 1 "$ws_boundary_thirteen/loop/promotions/runs.log")"
fi

ws_pct_zero=$(new_ws pct-zero)
seed_two_weeks "$ws_pct_zero"
write_conf "$ws_pct_zero" producer-model "fixture $GOOD"
printf '%s\n' 'fabricated_pct=0' >>"$ws_pct_zero/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_pct_zero" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/pct-zero.err"
pct_zero_rc=$?
ws_pct_over=$(new_ws pct-over)
seed_two_weeks "$ws_pct_over"
write_conf "$ws_pct_over" producer-model "fixture $GOOD"
printf '%s\n' 'fabricated_pct=101' >>"$ws_pct_over/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_pct_over" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/pct-over.err"
pct_over_rc=$?
ws_pct_valid=$(new_ws pct-valid)
seed_two_weeks "$ws_pct_valid"
write_conf "$ws_pct_valid" producer-model "pct-valid $FABRICATION_BOUNDARY 13"
printf '%s\n' 'fabricated_pct=60' >>"$ws_pct_valid/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_pct_valid" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/pct-valid.err"
pct_valid_rc=$?
if [[ "$pct_zero_rc" -eq 2 && "$pct_over_rc" -eq 2 && "$pct_valid_rc" -eq 0 \
  && "$(tail -n 1 "$ws_pct_zero/loop/promotions/runs.log")" == *' error=config' \
  && "$(tail -n 1 "$ws_pct_over/loop/promotions/runs.log")" == *' error=config' \
  && "$(tail -n 1 "$ws_pct_valid/loop/promotions/runs.log")" == *' fabricated=13 '* \
  && "$(tail -n 1 "$ws_pct_valid/loop/promotions/runs.log")" == *' candidates=12 '* \
  && "$(tail -n 1 "$ws_pct_valid/loop/promotions/runs.log")" == *' error=none' ]]; then
  pass '[R4-5] fabricated_pct accepts 1-100 and controls the whole-call boundary'
else
  fail_case '[R4-5] fabricated_pct accepts 1-100 and controls the whole-call boundary' "rcs=$pct_zero_rc/$pct_over_rc/$pct_valid_rc"
fi

PUNCTUATION_MINUS_FINAL=$TMP_ROOT/punctuation-minus-final-reviewer
write_reviewer "$PUNCTUATION_MINUS_FINAL" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: punctuation-minus-final still authenticates
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:retry later can succeed
WEEKS: 2026-W30
EVIDENCE: Dropping only terminal punctuation must not reject an otherwise exact content prefix.
PROMOTE: not-yet
THEME: different tail still fabricates
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:retry later can recover
WEEKS: 2026-W30
EVIDENCE: A changed tail remains unauthenticated even after punctuation tolerance.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_punctuation_minus_final=$(new_ws punctuation-minus-final)
printf '%s\n' '- retry later can succeed.' >"$ws_punctuation_minus_final/loop/archive/flush-2026-07-20.md"
write_conf "$ws_punctuation_minus_final" producer-model "punctuation-minus-final $PUNCTUATION_MINUS_FINAL"
"$RAW_REVIEW" --workspace "$ws_punctuation_minus_final" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/punctuation-minus-final.err"
punctuation_minus_final_rc=$?
if [[ "$punctuation_minus_final_rc" -eq 0 \
  && "$(tail -n 1 "$ws_punctuation_minus_final/loop/promotions/runs.log")" == *' blocks=2 '* \
  && "$(tail -n 1 "$ws_punctuation_minus_final/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_punctuation_minus_final/loop/promotions/runs.log")" == *' candidates=1 '* ]]; then
  pass '[R5-1] punctuation-minus-final authenticates while an actual tail change still rejects'
else
  fail_case '[R5-1] punctuation-minus-final authenticates while an actual tail change still rejects' "rc=$punctuation_minus_final_rc receipt=$(tail -n 1 "$ws_punctuation_minus_final/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/punctuation-minus-final.err")"
fi

ELLIPSIS_TRIAGE=$TMP_ROOT/ellipsis-triage-reviewer
write_reviewer "$ELLIPSIS_TRIAGE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: literal shell ellipsis stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:bash trap: command `$( ... )` retains stdout
WEEKS: 2026-W30
EVIDENCE: Exact source ellipses must validate before any truncation heuristic runs.
PROMOTE: not-yet
THEME: ascii source-ending ellipsis stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:source-ending ellipsis remains literal ...
WEEKS: 2026-W30
EVIDENCE: A source-authenticated trailing ... must pass.
PROMOTE: not-yet
THEME: unicode source-ending ellipsis stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:unicode source-ending ellipsis remains literal …
WEEKS: 2026-W30
EVIDENCE: A source-authenticated trailing … must pass.
PROMOTE: not-yet
THEME: model-added truncation is still rejected
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:model-added truncation needs full text...
WEEKS: 2026-W30
EVIDENCE: Only a stripped-form match may classify trailing ellipsis as model truncation.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_ellipsis_triage=$(new_ws ellipsis-triage)
cat <<'EOF_RAW' >"$ws_ellipsis_triage/loop/archive/flush-2026-07-20.md"
- 2026-07-20 bash trap: command `$( ... )` retains stdout until descendants close it.
- source-ending ellipsis remains literal ...
- unicode source-ending ellipsis remains literal …
- model-added truncation needs full text after this point.
EOF_RAW
write_conf "$ws_ellipsis_triage" producer-model "ellipsis-triage $ELLIPSIS_TRIAGE"
"$RAW_REVIEW" --workspace "$ws_ellipsis_triage" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/ellipsis-triage.err"
ellipsis_triage_rc=$?
if [[ "$ellipsis_triage_rc" -eq 0 \
  && "$(tail -n 1 "$ws_ellipsis_triage/loop/promotions/runs.log")" == *' blocks=4 '* \
  && "$(tail -n 1 "$ws_ellipsis_triage/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_ellipsis_triage/loop/promotions/runs.log")" == *' candidates=3 '* ]]; then
  pass '[R5-2] exact ellipses validate first and only stripped trailing ellipses classify as truncation'
else
  fail_case '[R5-2] exact ellipses validate first and only stripped trailing ellipses classify as truncation' "rc=$ellipsis_triage_rc receipt=$(tail -n 1 "$ws_ellipsis_triage/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/ellipsis-triage.err")"
fi

CONSERVATIVE_CANONICALIZATION=$TMP_ROOT/conservative-canonicalization-reviewer
write_reviewer "$CONSERVATIVE_CANONICALIZATION" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: machine tag strips conservatively
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:content with a shared leading tag still validates
WEEKS: 2026-W30
EVIDENCE: Conservative machine tags may strip on both sides.
PROMOTE: not-yet
THEME: date-like machine tag also strips
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:date-stamped machine tag still strips
WEEKS: 2026-W30
EVIDENCE: Numeric machine tags remain comparison-only decoration.
PROMOTE: not-yet
THEME: paired emphasis still authenticates
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:paired emphasis survives for citations
WEEKS: 2026-W30
EVIDENCE: Paired emphasis markers may strip while the enclosed text remains.
PROMOTE: not-yet
THEME: machine tag with hash still strips
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:hash-tagged machine label still strips
WEEKS: 2026-W30
EVIDENCE: A machine tag may include punctuation as long as it has no spaces and contains an ASCII digit.
PROMOTE: not-yet
THEME: word-adjacent single-star emphasis still authenticates
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:single-star emphasis survives for citations
WEEKS: 2026-W30
EVIDENCE: Single-star stripping stays allowed for word-adjacent emphasis.
PROMOTE: not-yet
THEME: preserved warning tag still matters
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:delete files
WEEKS: 2026-W30
EVIDENCE: Human warning tags like NEVER must not be stripped away.
PROMOTE: not-yet
THEME: lone glob star still matters
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:rm -rf
WEEKS: 2026-W30
EVIDENCE: A prefix may not silently omit a remaining lone/glob * token.
PROMOTE: not-yet
THEME: machine tag without delimiter stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:content fused to machine tag stays literal
WEEKS: 2026-W30
EVIDENCE: A machine tag strips only when a delimiter space or tab follows the closing bracket.
PROMOTE: not-yet
THEME: single-star glob stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:rm .
WEEKS: 2026-W30
EVIDENCE: Single-star stripping must not erase semantic glob content such as *.*.
PROMOTE: not-yet
THEME: direct-star suffix stays literal
CLASS: rule
MEMBERS:
- flush-2026-07-20.md:dangerous
WEEKS: 2026-W30
EVIDENCE: Prefix matching must not ignore a directly adjacent trailing * token.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_conservative_canonicalization=$(new_ws conservative-canonicalization)
cat <<'EOF_RAW' >"$ws_conservative_canonicalization/loop/archive/flush-2026-07-20.md"
- [session-806] content with a shared leading tag still validates
- [2026-07-20] date-stamped machine tag still strips
- **paired emphasis survives** for citations
- [caty-cloud#7] hash-tagged machine label still strips
- *single-star emphasis survives* for citations
- [NEVER] **delete * files**
- rm -rf *
- [session-806]content fused to machine tag stays literal
- rm *.*
- dangerous*glob
EOF_RAW
write_conf "$ws_conservative_canonicalization" producer-model "conservative-canonicalization $CONSERVATIVE_CANONICALIZATION"
printf '%s\n' 'fabricated_pct=100' >>"$ws_conservative_canonicalization/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_conservative_canonicalization" --week 2026-W30 >/dev/null 2>"$TMP_ROOT/conservative-canonicalization.err"
conservative_canonicalization_rc=$?
if [[ "$conservative_canonicalization_rc" -eq 0 \
  && "$(tail -n 1 "$ws_conservative_canonicalization/loop/promotions/runs.log")" == *' blocks=10 '* \
  && "$(tail -n 1 "$ws_conservative_canonicalization/loop/promotions/runs.log")" == *' fabricated=5 '* \
  && "$(tail -n 1 "$ws_conservative_canonicalization/loop/promotions/runs.log")" == *' candidates=5 '* ]]; then
  pass '[R5-3] machine tags need a delimiter, paired emphasis stays narrow, and warning/glob content remains meaningful'
else
  fail_case '[R5-3] machine tags need a delimiter, paired emphasis stays narrow, and warning/glob content remains meaningful' "rc=$conservative_canonicalization_rc receipt=$(tail -n 1 "$ws_conservative_canonicalization/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/conservative-canonicalization.err")"
fi

BAD_SINGLETON=$TMP_ROOT/bad-singleton-reviewer
write_reviewer "$BAD_SINGLETON" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: lone fabricated singleton
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:retries need
WEEKS: 2026-W33
EVIDENCE: A single bad block must not count as a successful review.
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_bad_singleton=$(new_ws bad-singleton)
seed_two_weeks "$ws_bad_singleton"
write_conf "$ws_bad_singleton" producer-model "bad-singleton $BAD_SINGLETON" "good $GOOD"
"$RAW_REVIEW" --workspace "$ws_bad_singleton" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/bad-singleton.err"
bad_singleton_rc=$?
if [[ "$bad_singleton_rc" -eq 0 \
  && "$(tail -n 1 "$ws_bad_singleton/loop/promotions/runs.log")" == *' model_used=good '* \
  && "$(tail -n 1 "$ws_bad_singleton/loop/promotions/runs.log")" == *' chain_pos=2 '* ]] \
  && grep -Fqx 'reviewer_failed=bad-singleton reason=fabrication-threshold' "$TMP_ROOT/bad-singleton.err"; then
  pass '[R5-4] a parsed review with zero accepted candidates fails closed and advances to the next reviewer'
else
  fail_case '[R5-4] a parsed review with zero accepted candidates fails closed and advances to the next reviewer' "rc=$bad_singleton_rc receipt=$(tail -n 1 "$ws_bad_singleton/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/bad-singleton.err")"
fi

ws_decimal_config=$(new_ws decimal-config)
seed_two_weeks "$ws_decimal_config"
write_conf "$ws_decimal_config" producer-model "decimal-config $FABRICATION_BOUNDARY 17"
printf '%s\n' 'review_window_weeks=02' 'reviewer_timeout_s=08' 'fabricated_pct=0100' 'zero_streak_threshold=0100' >>"$ws_decimal_config/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws_decimal_config" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/decimal-config.err"
decimal_config_rc=$?
if [[ "$decimal_config_rc" -eq 0 \
  && "$(tail -n 1 "$ws_decimal_config/loop/promotions/runs.log")" == *' blocks=25 '* \
  && "$(tail -n 1 "$ws_decimal_config/loop/promotions/runs.log")" == *' fabricated=17 '* \
  && "$(tail -n 1 "$ws_decimal_config/loop/promotions/runs.log")" == *' candidates=8 '* \
  && "$(tail -n 1 "$ws_decimal_config/loop/promotions/runs.log")" == *' error=none' ]]; then
  pass '[R5-5] decimal config parsing treats 08 and 0100 as 8 and 100 instead of octal semantics'
else
  fail_case '[R5-5] decimal config parsing treats 08 and 0100 as 8 and 100 instead of octal semantics' "rc=$decimal_config_rc receipt=$(tail -n 1 "$ws_decimal_config/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/decimal-config.err")"
fi

ws_boundary_twelve=$(new_ws boundary-twelve)
seed_two_weeks "$ws_boundary_twelve"
write_conf "$ws_boundary_twelve" producer-model "boundary-twelve $FABRICATION_BOUNDARY 12"
"$RAW_REVIEW" --workspace "$ws_boundary_twelve" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/boundary-twelve.err"
boundary_twelve_rc=$?
boundary_twelve_candidate=$(latest_candidate "$ws_boundary_twelve")
if [[ "$boundary_twelve_rc" -eq 0 && -f "$boundary_twelve_candidate" \
  && "$(grep -c '^## theme-' "$boundary_twelve_candidate")" -eq 13 \
  && "$(tail -n 1 "$ws_boundary_twelve/loop/promotions/runs.log")" == *' blocks=25 '* \
  && "$(tail -n 1 "$ws_boundary_twelve/loop/promotions/runs.log")" == *' fabricated=12 '* \
  && "$(tail -n 1 "$ws_boundary_twelve/loop/promotions/runs.log")" == *' candidates=13 '* \
  && "$(tail -n 1 "$ws_boundary_twelve/loop/promotions/runs.log")" == *' error=none' ]]; then
  pass '[R5-6] the default whole-call guard keeps the 25/12 pass seam intact'
else
  fail_case '[R5-6] the default whole-call guard keeps the 25/12 pass seam intact' "rc=$boundary_twelve_rc receipt=$(tail -n 1 "$ws_boundary_twelve/loop/promotions/runs.log") stderr=$(cat "$TMP_ROOT/boundary-twelve.err")"
fi

OUTPUT_CAP_ERROR=$TMP_ROOT/output-cap-error-reviewer
write_reviewer "$OUTPUT_CAP_ERROR" 'cat >/dev/null
printf "%s\n" "API Error: Claude'"'"'s response exceeded the 32000 output token maximum."'
ws_output_cap=$(new_ws output-cap)
seed_two_weeks "$ws_output_cap"
write_conf "$ws_output_cap" producer-model "output-cap $OUTPUT_CAP_ERROR"
"$RAW_REVIEW" --workspace "$ws_output_cap" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/output-cap.err"
output_cap_rc=$?
if [[ "$output_cap_rc" -eq 1 \
  && "$(tail -n 1 "$ws_output_cap/loop/promotions/runs.log")" == *' error=chain-exhausted' ]] \
  && grep -Fqx 'reviewer_failed=output-cap reason=grammar' "$TMP_ROOT/output-cap.err"; then
  pass '[R2-3] an unfenced output-cap API error fails the reviewer call as grammar'
else
  fail_case '[R2-3] an unfenced output-cap API error fails the reviewer call as grammar' "rc=$output_cap_rc stderr=$(cat "$TMP_ROOT/output-cap.err")"
fi

BLANK_ONE=$TMP_ROOT/blank-one-reviewer
write_reviewer "$BLANK_ONE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: first separated block
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Durable r
WEEKS: 2026-W33
EVIDENCE: first
PROMOTE: not-yet

THEME: second separated block
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:Retry lo
WEEKS: 2026-W34
EVIDENCE: second
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
BLANK_THREE=$TMP_ROOT/blank-three-reviewer
write_reviewer "$BLANK_THREE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: first separated block
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Durable r
WEEKS: 2026-W33
EVIDENCE: first
PROMOTE: not-yet



THEME: second separated block
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:Retry lo
WEEKS: 2026-W34
EVIDENCE: second
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
BLANK_INSIDE=$TMP_ROOT/blank-inside-reviewer
write_reviewer "$BLANK_INSIDE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: invalid interior blank
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Durable r

- flush-2026-08-17.md:Retry lo
WEEKS: 2026-W33,2026-W34
EVIDENCE: interior blanks are not separators
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
ws_one=$(new_ws blank-one)
seed_two_weeks "$ws_one"
write_conf "$ws_one" producer-model "one $BLANK_ONE"
"$RAW_REVIEW" --workspace "$ws_one" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/blank-one.err"
one_rc=$?
ws_three=$(new_ws blank-three)
seed_two_weeks "$ws_three"
write_conf "$ws_three" producer-model "three $BLANK_THREE"
"$RAW_REVIEW" --workspace "$ws_three" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/blank-three.err"
three_rc=$?
ws_inside=$(new_ws blank-inside)
seed_two_weeks "$ws_inside"
write_conf "$ws_inside" producer-model "inside $BLANK_INSIDE"
"$RAW_REVIEW" --workspace "$ws_inside" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/blank-inside.err"
inside_rc=$?
if [[ "$one_rc" -eq 0 && "$three_rc" -eq 0 && "$inside_rc" -eq 1 \
  && "$(tail -n 1 "$ws_one/loop/promotions/runs.log")" == *' blocks=2 '* \
  && "$(tail -n 1 "$ws_three/loop/promotions/runs.log")" == *' blocks=2 '* \
  && "$(tail -n 1 "$ws_inside/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R1-2] blank-separated blocks parse while a blank inside MEMBERS remains invalid'
else
  fail_case '[R1-2] blank-separated blocks parse while a blank inside MEMBERS remains invalid' "rcs=$one_rc/$three_rc/$inside_rc"
fi

MIDLINE=$TMP_ROOT/midline-reviewer
write_reviewer "$MIDLINE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: mid-line fabrication
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:retries need
WEEKS: 2026-W33
EVIDENCE: substring is not a prefix
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
FLOOR_ONE=$TMP_ROOT/floor-one-reviewer
write_reviewer "$FLOOR_ONE" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: fabricated one
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:not present anywhere
WEEKS: 2026-W33
EVIDENCE: fabricated
PROMOTE: not-yet
THEME: valid one
CLASS: rule
MEMBERS:
- flush-2026-08-10.md:Durable r
WEEKS: 2026-W33
EVIDENCE: valid
PROMOTE: not-yet
THEME: valid two
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:Retry lo
WEEKS: 2026-W34
EVIDENCE: valid
PROMOTE: not-yet
THEME: valid three
CLASS: rule
MEMBERS:
- intake-evictions-2026-08-18.md:Evicted l
WEEKS: 2026-W34
EVIDENCE: valid
PROMOTE: not-yet
RAW-REVIEW-OUTPUT-END
OUT'
FLOOR_TWO=$TMP_ROOT/floor-two-reviewer
sed 's/flush-2026-08-10.md:Durable r/flush-2026-08-10.md:also fabricated/' "$FLOOR_ONE" >"$FLOOR_TWO"
chmod +x "$FLOOR_TWO"
ws_midline=$(new_ws midline)
seed_two_weeks "$ws_midline"
write_conf "$ws_midline" producer-model "midline $MIDLINE"
"$RAW_REVIEW" --workspace "$ws_midline" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/midline.err"
midline_rc=$?
ws_floor_one=$(new_ws floor-one)
seed_two_weeks "$ws_floor_one"
write_conf "$ws_floor_one" producer-model "floor-one $FLOOR_ONE"
"$RAW_REVIEW" --workspace "$ws_floor_one" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/floor-one.err"
floor_one_rc=$?
ws_floor_two=$(new_ws floor-two)
seed_two_weeks "$ws_floor_two"
write_conf "$ws_floor_two" producer-model "floor-two $FLOOR_TWO"
"$RAW_REVIEW" --workspace "$ws_floor_two" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/floor-two.err"
floor_two_rc=$?
if [[ "$midline_rc" -eq 1 && "$floor_one_rc" -eq 0 && "$floor_two_rc" -eq 1 \
  && "$(tail -n 1 "$ws_midline/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_midline/loop/promotions/runs.log")" == *' error=chain-exhausted' \
  && "$(tail -n 1 "$ws_floor_one/loop/promotions/runs.log")" == *' blocks=4 '* \
  && "$(tail -n 1 "$ws_floor_one/loop/promotions/runs.log")" == *' fabricated=1 '* \
  && "$(tail -n 1 "$ws_floor_two/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R1-8] citations are prefix-anchored and the four-block fabrication floor seam is pinned'
else
  fail_case '[R1-8] citations are prefix-anchored and the four-block fabrication floor seam is pinned' "rcs=$midline_rc/$floor_one_rc/$floor_two_rc"
fi

NONZERO=$TMP_ROOT/nonzero
write_reviewer "$NONZERO" 'cat >/dev/null; exit 7'
EMPTY=$TMP_ROOT/empty
write_reviewer "$EMPTY" 'cat >/dev/null; exit 0'
SLOW=$TMP_ROOT/slow
write_reviewer "$SLOW" 'cat >/dev/null; sleep 3'
ws=$(new_ws chain)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "missing $TMP_ROOT/not-there" "nonzero $NONZERO" "empty $EMPTY" "slow $SLOW" "good $GOOD"
sed -i.bak 's/reviewer_timeout_s=10/reviewer_timeout_s=1/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/chain.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=good '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' chain_pos=5 '* ]]; then
  pass '[9] missing, non-zero, empty, and timed-out entries advance independently'
else
  fail_case '[9] missing, non-zero, empty, and timed-out entries advance independently' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

TIMEOUT_CHILD=$TMP_ROOT/timeout-child-reviewer
timeout_child_pid_file=$TMP_ROOT/timeout-child.pid
timeout_child_marker=raw-review-timeout-child-$$
timeout_child_started=$TMP_ROOT/timeout-child.started
timeout_child_survived=$TMP_ROOT/timeout-child.survived
write_reviewer "$TIMEOUT_CHILD" 'pid_file=$1
marker=$2
started=$3
survived=$4
python3 -B -c '\''import pathlib, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
signal.signal(signal.SIGHUP, signal.SIG_IGN)
pathlib.Path(sys.argv[2]).write_text("started\n")
time.sleep(5)
pathlib.Path(sys.argv[3]).write_text("survived\n")
time.sleep(300)'\'' "$marker" "$started" "$survived" &
printf "%s\n" "$!" >"$pid_file"
attempt=0
while [[ ! -e "$started" && "$attempt" -lt 100 ]]; do
  sleep 0.02
  attempt=$((attempt + 1))
done
[[ -e "$started" ]] || exit 9
cat >/dev/null
sleep 300'
NO_TIMEOUT_BIN=$TMP_ROOT/no-timeout-bin
mkdir -p "$NO_TIMEOUT_BIN"
for tool in awk bash cat cp date dirname env find grep id ls mkdir mktemp mv paste python3 rm sed sleep sort stat tr wc; do
  tool_path=$(command -v "$tool")
  ln -s "$tool_path" "$NO_TIMEOUT_BIN/$tool"
done
ws=$(new_ws timeout-descendant)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $TIMEOUT_CHILD $timeout_child_pid_file $timeout_child_marker $timeout_child_started $timeout_child_survived"
sed -i.bak 's/reviewer_timeout_s=10/reviewer_timeout_s=3/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
PATH="$NO_TIMEOUT_BIN" "$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/timeout-child.err"
timeout_child_rc=$?
timeout_child_pid=$(sed -n '1p' "$timeout_child_pid_file" 2>/dev/null || true)
timeout_child_alive=1
poll=0
while [[ "$poll" -lt 30 ]]; do
  timeout_child_command=$(ps -ww -p "$timeout_child_pid" -o command= 2>/dev/null || true)
  case "$timeout_child_command" in
    *"$timeout_child_marker"*) sleep 0.1 ;;
    *) timeout_child_alive=0; break ;;
  esac
  poll=$((poll + 1))
done
sleep 3
if [[ "$timeout_child_rc" -eq 1 && -n "$timeout_child_pid" && -e "$timeout_child_started" \
  && ! -e "$timeout_child_survived" \
  && "$timeout_child_alive" -eq 0 \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[R1-6] fallback timeout kills the reviewer process group and its marked descendant'
else
  [[ -n "$timeout_child_pid" ]] && kill -9 "$timeout_child_pid" 2>/dev/null || true
  fail_case '[R1-6] fallback timeout kills the reviewer process group and its marked descendant' "rc=$timeout_child_rc pid=$timeout_child_pid command=$timeout_child_command survived=$([[ -e "$timeout_child_survived" ]] && printf yes || printf no)"
fi

ws=$(new_ws producer-unset)
seed_two_weeks "$ws"
printf 'reviewer fixture %s\n' "$GOOD" >"$ws/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/unset.err"
rc=$?
if [[ "$rc" -eq 2 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=config' \
  && -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]]; then
  pass '[10] unset producer is a notified configuration-class exit 2'
else
  fail_case '[10] unset producer is a notified configuration-class exit 2' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

REAL_PYTHON=$(command -v python3)
PYTHON_ERROR_BIN=$TMP_ROOT/python-error-bin
mkdir -p "$PYTHON_ERROR_BIN"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'real_python=%q\n' "$REAL_PYTHON"
  cat <<'SH'
if [[ "${3-}" == producer-model && "${4-}" == other-model ]]; then
  exit 3
fi
exec "$real_python" "$@"
SH
} >"$PYTHON_ERROR_BIN/python3"
chmod +x "$PYTHON_ERROR_BIN/python3"
ws=$(new_ws self-review-error)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "other-model $GOOD"
PATH="$PYTHON_ERROR_BIN:$PATH" "$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/self-review-error.err"
self_review_error_rc=$?
if [[ "$self_review_error_rc" -eq 1 \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=chain-exhausted' ]] \
  && grep -Fqx 'self_review_check_error=other-model' "$TMP_ROOT/self-review-error.err"; then
  pass '[R1-3] self-review matcher infrastructure errors refuse the entry and log the error'
else
  fail_case '[R1-3] self-review matcher infrastructure errors refuse the entry and log the error' "rc=$self_review_error_rc stderr=$(cat "$TMP_ROOT/self-review-error.err")"
fi

ws=$(new_ws indented-crlf)
seed_two_weeks "$ws"
printf '  producer=producer-model\r\n  reviewer fixture %s\r\n  review_window_weeks=2\r\n  recurrence_unit=sessions\r\n  promote_min_k=2\r\n  promote_min_weeks=0\r\n  reviewer_timeout_s=10\r\n  fabricated_floor=2\r\n  zero_streak_threshold=2\r\n  prompt_max_bytes=2000000\r\n' \
  "$GOOD" >"$ws/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/indented-crlf.err"
indented_crlf_rc=$?
indented_check=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
indented_check_rc=$?
if [[ "$indented_crlf_rc" -eq 0 && "$indented_check_rc" -eq 0 \
  && "$indented_check" != *'warning: review-config:'* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=fixture '* ]]; then
  pass '[R1-7] indented CRLF review configuration is wired in production and health check grammars'
else
  fail_case '[R1-7] indented CRLF review configuration is wired in production and health check grammars' "rcs=$indented_crlf_rc/$indented_check_rc check=$indented_check"
fi

ws=$(new_ws identity)
seed_two_weeks "$ws"
write_conf "$ws" 'openai/gpt-5.6-sol' "gpt-5.6-sol $GOOD" "openai/gpt-5.6-sol $GOOD" "anthropic/gpt-5.6-sol $GOOD" "xai/gpt-5.6-sol $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/identity.err"
rc=$?
if [[ "$rc" -eq 1 && "$(grep -c '^self_review_refused=' "$TMP_ROOT/identity.err")" -eq 4 \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=chain-exhausted' ]]; then
  pass '[11] four normalized aliases refuse self-review and exhaust the chain'
else
  fail_case '[11] four normalized aliases refuse self-review and exhaust the chain' "rc=$rc stderr=$(cat "$TMP_ROOT/identity.err")"
fi

ws=$(new_ws version)
seed_two_weeks "$ws"
write_conf "$ws" glm-5.3 "glm-5.2 $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/version.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=glm-5.2 '* ]]; then
  pass '[12] model version suffix is preserved so glm-5.3 does not refuse glm-5.2'
else
  fail_case '[12] model version suffix is preserved so glm-5.3 does not refuse glm-5.2' "rc=$rc stderr=$(cat "$TMP_ROOT/version.err")"
fi

ws=$(new_ws version-prefix)
seed_two_weeks "$ws"
write_conf "$ws" glm-5 "glm-5.3 $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/version-prefix.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=glm-5.3 '* ]]; then
  pass '[12b] numeric version extension is not mistaken for token-boundary containment'
else
  fail_case '[12b] numeric version extension is not mistaken for token-boundary containment' "rc=$rc stderr=$(cat "$TMP_ROOT/version-prefix.err")"
fi

ws=$(new_ws paused)
seed_two_weeks "$ws"
called=$TMP_ROOT/paused-called
PAUSED_REVIEWER=$TMP_ROOT/paused-reviewer
write_reviewer "$PAUSED_REVIEWER" "touch '$called'; cat >/dev/null"
write_conf "$ws" producer-model "fixture $PAUSED_REVIEWER"
mkdir -p "$ws/.caty-agent-harness"
: >"$ws/.caty-agent-harness/DISABLED"
printf '9\n' >"$ws/loop/promotions/.zero-streak"
"$RAW_REVIEW" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/paused.err"
rc=$?
if [[ "$rc" -eq 0 && ! -e "$called" && "$(cat "$ws/loop/promotions/.zero-streak")" == 9 \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' zero_streak=9 '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=skipped-paused' ]]; then
  pass '[13] pause guard prevents egress and leaves zero_streak unchanged'
else
  fail_case '[13] pause guard prevents egress and leaves zero_streak unchanged' "rc=$rc called=$([[ -e "$called" ]] && printf yes || printf no)"
fi

ws=$(new_ws budget)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $GOOD"
sed -i.bak 's/prompt_max_bytes=2000000/prompt_max_bytes=10/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/budget.err"
rc=$?
if [[ "$rc" -eq 1 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=prompt-too-large' \
  && -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]]; then
  pass '[14] over-budget prompt is never truncated and takes the notified exit-1 path'
else
  fail_case '[14] over-budget prompt is never truncated and takes the notified exit-1 path' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
fi

ws=$(new_ws dry-budget)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $GOOD"
printf '6\n' >"$ws/loop/promotions/.zero-streak"
sed -i.bak 's/prompt_max_bytes=2000000/prompt_max_bytes=10/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 --dry-run >/dev/null 2>"$TMP_ROOT/dry-budget.err"
dry_budget_rc=$?
if [[ "$dry_budget_rc" -eq 1 \
  && ! -e "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' mode=dry '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' zero_streak=6 '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=prompt-too-large' ]]; then
  pass '[R1-adjacent] failing dry-run writes an accurate receipt but never a notification'
else
  fail_case '[R1-adjacent] failing dry-run writes an accurate receipt but never a notification' "rc=$dry_budget_rc receipt=$(tail -n 1 "$ws/loop/promotions/runs.log") notify=$([[ -e "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]] && printf yes || printf no)"
fi

ws=$(new_ws notify-failure)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "vacuous $VACUOUS"
notify_capture=$TMP_ROOT/notify-capture
NOTIFIER=$TMP_ROOT/failing-notifier
write_reviewer "$NOTIFIER" 'notification=$1
capture=$2
fixed=$3
printf "%s|%s\n" "$notification" "$fixed" >"$capture"
exit 9'
printf 'notify_cmd=%s %s fixed-arg\n' "$NOTIFIER" "$notify_capture" >>"$ws/loop/review.conf"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/notify-failure.err"
rc=$?
canonical_notify_ws=$(cd "$ws" && pwd -P)
if [[ "$rc" -eq 1 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=chain-exhausted' \
  && "$(cat "$notify_capture")" == "$canonical_notify_ws/loop/notify/review-$(date -u +%Y-%m-%d).md|fixed-arg" ]]; then
  pass '[14b] notify_cmd receives the file as $1; notifier failure never suppresses exit 1'
else
  fail_case '[14b] notify_cmd receives the file as $1; notifier failure never suppresses exit 1' "rc=$rc capture=$(cat "$notify_capture" 2>/dev/null)"
fi

current_dates=$(python3 -B - <<'PY'
import datetime
today = datetime.datetime.now(datetime.timezone.utc).date()
monday = today - datetime.timedelta(days=today.isoweekday() - 1)
print((monday - datetime.timedelta(weeks=1)).isoformat(), monday.isoformat())
PY
)
read -r previous_date current_date <<EOF
$current_dates
EOF
CAPTURE_NO_GROUPS=$TMP_ROOT/capture-no-groups
write_reviewer "$CAPTURE_NO_GROUPS" 'capture=$1
cat >"$capture"
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END'
ws=$(new_ws watermark-streak)
printf '%s\n' '- prior-week eligible input' >"$ws/loop/archive/flush-$previous_date.md"
printf '%s\n' '- current-week eligible input' >"$ws/loop/archive/flush-$current_date.md"
watermark_capture=$TMP_ROOT/watermark-capture
write_conf "$ws" producer-model "fixture $CAPTURE_NO_GROUPS $watermark_capture"
"$RAW_REVIEW" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/watermark1.err"
first_rc=$?
first_watermark=$(cat "$ws/loop/promotions/.last-success-epoch")
printf '%s\n' '- arbitrarily late durable lesson' >"$ws/loop/archive/flush-2020-01-06.md"
python3 -B - "$ws/loop/archive/flush-2020-01-06.md" "$first_watermark" <<'PY'
import os
import sys
os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))
PY
"$RAW_REVIEW" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/watermark2.err"
second_rc=$?
second_watermark=$(cat "$ws/loop/promotions/.last-success-epoch")
"$RAW_REVIEW" --workspace "$ws" --dry-run >/dev/null 2>"$TMP_ROOT/watermark-dry.err"
dry_rc=$?
after_dry_watermark=$(cat "$ws/loop/promotions/.last-success-epoch")
if [[ "$first_rc" -eq 0 && "$second_rc" -eq 0 && "$dry_rc" -eq 0 \
  && "$second_watermark" -ge "$first_watermark" && "$after_dry_watermark" == "$second_watermark" \
  && "$(cat "$ws/loop/promotions/.zero-streak")" -eq 2 \
  && -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" \
  && $(grep -Fxc 'RAW-FILE: loop/archive/flush-2020-01-06.md' "$watermark_capture") -eq 1 ]]; then
  pass '[R1-5] same-second late arrival is reviewed, nightly streak reaches threshold, and dry-run preserves watermark'
else
  fail_case '[R1-5] same-second late arrival is reviewed, nightly streak reaches threshold, and dry-run preserves watermark' "rcs=$first_rc/$second_rc/$dry_rc watermarks=$first_watermark/$second_watermark/$after_dry_watermark streak=$(cat "$ws/loop/promotions/.zero-streak" 2>/dev/null) notify=$([[ -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]] && printf yes || printf no) late_count=$(grep -Fxc 'RAW-FILE: loop/archive/flush-2020-01-06.md' "$watermark_capture")"
fi

ws=$(new_ws supersedes)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/super1.err"
ledger_prefix=$TMP_ROOT/ledger-prefix
runs_prefix=$TMP_ROOT/runs-prefix
cp "$ws/loop/promotions/ledger.md" "$ledger_prefix"
cp "$ws/loop/promotions/runs.log" "$runs_prefix"
sleep 1
ONE_WEEK=$TMP_ROOT/one-week-reviewer
write_reviewer "$ONE_WEEK" 'cat >/dev/null
cat <<"OUT"
RAW-REVIEW-OUTPUT-BEGIN
THEME: bounded retries regrouped
CLASS: rule
MEMBERS:
- flush-2026-08-17.md:- 2026-08-17 Retry loops should cap backoff
WEEKS: 2026-W33,2026-W34
EVIDENCE: The model asks to promote from one current-run week.
PROMOTE: yes
RAW-REVIEW-OUTPUT-END
OUT'
write_conf "$ws" producer-model "fixture $ONE_WEEK"
sed -i.bak 's/review_window_weeks=2/review_window_weeks=1/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/super2.err"
rc=$?
if [[ "$rc" -eq 0 ]] && cmp -s "$ledger_prefix" <(head -c "$(wc -c <"$ledger_prefix")" "$ws/loop/promotions/ledger.md") \
  && cmp -s "$runs_prefix" <(head -c "$(wc -c <"$runs_prefix")" "$ws/loop/promotions/runs.log") \
  && grep -Fq 'supersedes: theme-' "$ws/loop/promotions/ledger.md" \
  && grep -Fq 'union-k: 2' "$ws/loop/promotions/ledger.md" \
  && [[ "$(tail -n 13 "$ws/loop/promotions/ledger.md")" == *'run-k: 1'* ]] \
  && [[ "$(tail -n 13 "$ws/loop/promotions/ledger.md")" == *'promote: not-yet'* ]] \
  && [[ "$(find "$ws/loop/promotions" -name 'candidates-*.md' ! -name '*.rejects.md' | wc -l | tr -d ' ')" -eq 2 ]]; then
  pass '[15] reruns are unique, ledger/runs remain byte-prefix append-only, and overlap supersedes'
else
  fail_case '[15] reruns are unique, ledger/runs remain byte-prefix append-only, and overlap supersedes' "rc=$rc ledger=$(cat "$ws/loop/promotions/ledger.md")"
fi

ws=$(new_ws lock-busy)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "fixture $GOOD"
mkdir "$ws/loop/promotions/.lock"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/lock.err"
rc=$?
if [[ "$rc" -eq 1 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' error=lock-busy' ]]; then
  pass '[16] lock-busy still emits its mandatory receipt and exits 1'
else
  fail_case '[16] lock-busy still emits its mandatory receipt and exits 1' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log" 2>/dev/null)"
fi

PERF_REVIEWER=$TMP_ROOT/perf-reviewer
write_reviewer "$PERF_REVIEWER" 'cat >/dev/null
printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN
i=981
while [ "$i" -le 1000 ]; do
  printf "THEME: performance citation %s\n" "$i"
  printf "%s\n" "CLASS: rule" MEMBERS:
  printf -- "- flush-2026-08-10.md:Performance citation %04d\n" "$i"
  printf "%s\n" "WEEKS: 2026-W33" "EVIDENCE: cached source validation" "PROMOTE: not-yet"
  i=$((i + 1))
done
printf "%s\n" RAW-REVIEW-OUTPUT-END'
ws=$(new_ws performance)
i=1
while [[ "$i" -le 1000 ]]; do
  printf 'Performance citation %04d has a stable source prefix.\n' "$i"
  i=$((i + 1))
done >"$ws/loop/archive/flush-2026-08-10.md"
write_conf "$ws" producer-model "fixture $PERF_REVIEWER"
perf_started=$(date '+%s')
"$RAW_REVIEW" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/performance.err" &
perf_pid=$!
perf_deadline=$((perf_started + 10))
while kill -0 "$perf_pid" 2>/dev/null && [[ "$(date '+%s')" -lt "$perf_deadline" ]]; do
  sleep 1
done
if kill -0 "$perf_pid" 2>/dev/null; then
  kill "$perf_pid" 2>/dev/null || true
  wait "$perf_pid" 2>/dev/null || true
  perf_rc=124
else
  wait "$perf_pid"
  perf_rc=$?
fi
perf_elapsed=$(($(date '+%s') - perf_started))
if [[ "$perf_rc" -eq 0 && "$perf_elapsed" -lt 10 \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' blocks=20 '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' candidates=20 '* ]]; then
  pass '[R1-9] twenty citations against a thousand-line fixture validate in under ten seconds'
else
  fail_case '[R1-9] twenty citations against a thousand-line fixture validate in under ten seconds' "rc=$perf_rc elapsed=$perf_elapsed receipt=$(tail -n 1 "$ws/loop/promotions/runs.log" 2>/dev/null)"
fi

if [[ -x "$RAW_REVIEW" && -x "$0" ]] && bash -n "$RAW_REVIEW" && bash -n "$0" \
  && ! grep -Eq 'TEST_|eval ' "$RAW_REVIEW"; then
  pass '[17] scripts are executable and Bash-valid with no production fault hooks or eval'
else
  fail_case '[17] scripts are executable and Bash-valid with no production fault hooks or eval' 'syntax, mode, or mutation-seam contract failed'
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
