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
  printf '%s\n' '<!-- flush origin=fixture -->' '- 2026-08-10 Durable retries need bounded backoff and receipts.' \
    >"$ws/loop/archive/flush-2026-08-10.md"
  printf '%s\n' '<!-- flush origin=fixture -->' '- 2026-08-17 Retry loops should cap backoff and leave an explicit receipt.' \
    >"$ws/loop/archive/flush-2026-08-17.md"
  printf '%s\n' '<!-- intake evictions -->' '- 2026-08-18 Evicted lessons remain reviewable in the raw layer.' \
    >"$ws/loop/archive/intake-evictions-2026-08-18.md"
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
    printf '%s\n' 'review_window_weeks=2' 'reviewer_timeout_s=1' \
      'fabricated_floor=2' 'zero_streak_threshold=2' 'prompt_max_bytes=2000000'
  } >"$ws/loop/review.conf"
}

latest_candidate() { find "$1/loop/promotions" -type f -name 'candidates-*.md' ! -name '*.rejects.md' | LC_ALL=C sort | tail -n 1; }

ws=$(new_ws promote)
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

receipt=$(tail -n 1 "$ws/loop/promotions/runs.log")
actual_bytes=$(wc -c <"$capture" | tr -d '[:space:]')
recorded_bytes=$(printf '%s\n' "$receipt" | sed -n 's/.* prompt_bytes=\([0-9][0-9]*\) .*/\1/p')
if [[ "$recorded_bytes" == "$actual_bytes" && "$receipt" == *' mode=retro '* && "$receipt" == *' error=none' ]]; then
  pass '[2] prompt_bytes accounts for the complete prompt and retro receipt fields are pinned'
else
  fail_case '[2] prompt_bytes accounts for the complete prompt and retro receipt fields are pinned' "actual=$actual_bytes receipt=$receipt"
fi

ws=$(new_ws dry)
seed_two_weeks "$ws"
called=$TMP_ROOT/dry-called
DRY_REVIEWER=$TMP_ROOT/dry-reviewer
write_reviewer "$DRY_REVIEWER" "touch '$called'; cat >/dev/null"
write_conf "$ws" producer-model "fixture $DRY_REVIEWER"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 --dry-run >"$TMP_ROOT/dry.out" 2>"$TMP_ROOT/dry.err"
rc=$?
if [[ "$rc" -eq 0 && ! -e "$called" ]] && grep -q '^prompt_bytes=[0-9][0-9]*$' "$TMP_ROOT/dry.out" \
  && grep -Fq 'loop/archive/flush-2026-08-10.md' "$TMP_ROOT/dry.out" \
  && [[ "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' mode=dry '* ]]; then
  pass '[3] dry-run validates and lists the complete window without model egress'
else
  fail_case '[3] dry-run validates and lists the complete window without model egress' "rc=$rc called=$([[ -e "$called" ]] && printf yes || printf no)"
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
sed -i.bak 's/reviewer_timeout_s=1/reviewer_timeout_s=5/' "$ws/loop/review.conf" && rm "$ws/loop/review.conf.bak"
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

NONZERO=$TMP_ROOT/nonzero
write_reviewer "$NONZERO" 'cat >/dev/null; exit 7'
EMPTY=$TMP_ROOT/empty
write_reviewer "$EMPTY" 'cat >/dev/null; exit 0'
SLOW=$TMP_ROOT/slow
write_reviewer "$SLOW" 'cat >/dev/null; sleep 3'
ws=$(new_ws chain)
seed_two_weeks "$ws"
write_conf "$ws" producer-model "missing $TMP_ROOT/not-there" "nonzero $NONZERO" "empty $EMPTY" "slow $SLOW" "good $GOOD"
"$RAW_REVIEW" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/chain.err"
rc=$?
if [[ "$rc" -eq 0 && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' model_used=good '* \
  && "$(tail -n 1 "$ws/loop/promotions/runs.log")" == *' chain_pos=5 '* ]]; then
  pass '[9] missing, non-zero, empty, and timed-out entries advance independently'
else
  fail_case '[9] missing, non-zero, empty, and timed-out entries advance independently' "rc=$rc log=$(tail -n 1 "$ws/loop/promotions/runs.log")"
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
sleep 2
printf '%s\n' '- arbitrarily late durable lesson' >"$ws/loop/archive/flush-2020-01-06.md"
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
  pass '[14c] late-arrival sweep is once-per-snapshot, nightly streak reaches threshold, and dry-run preserves watermark'
else
  fail_case '[14c] late-arrival sweep is once-per-snapshot, nightly streak reaches threshold, and dry-run preserves watermark' "rcs=$first_rc/$second_rc/$dry_rc watermarks=$first_watermark/$second_watermark/$after_dry_watermark streak=$(cat "$ws/loop/promotions/.zero-streak" 2>/dev/null) notify=$([[ -s "$ws/loop/notify/review-$(date -u +%Y-%m-%d).md" ]] && printf yes || printf no) late_count=$(grep -Fxc 'RAW-FILE: loop/archive/flush-2020-01-06.md' "$watermark_capture")"
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

if [[ -x "$RAW_REVIEW" && -x "$0" ]] && bash -n "$RAW_REVIEW" && bash -n "$0" \
  && ! grep -Eq 'TEST_|eval ' "$RAW_REVIEW"; then
  pass '[17] scripts are executable and Bash-valid with no production fault hooks or eval'
else
  fail_case '[17] scripts are executable and Bash-valid with no production fault hooks or eval' 'syntax, mode, or mutation-seam contract failed'
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
