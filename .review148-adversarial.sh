#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TMP_ROOT=$(mktemp -d /tmp/review148-adversarial.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

new_ws() {
  local name=$1
  local ws=$TMP_ROOT/$name
  "$ROOT/scripts/loop-init" --workspace "$ws" >/dev/null
  printf '%s\n' "$ws"
}

seed_retro() {
  local ws=$1
  printf '%s\n' '<!-- fixture -->' '- 2026-08-10 Real first-week lesson.' >"$ws/loop/archive/flush-2026-08-10.md"
  printf '%s\n' '<!-- fixture -->' '- 2026-08-17 Unrelated second-week lesson.' >"$ws/loop/archive/flush-2026-08-17.md"
}

write_base_conf() {
  local ws=$1 reviewer=$2 timeout=${3:-3}
  printf '%s\n' \
    'producer=producer-model' \
    "reviewer other-model $reviewer" \
    'review_window_weeks=2' \
    "reviewer_timeout_s=$timeout" \
    'fabricated_floor=2' \
    'zero_streak_threshold=14' \
    'prompt_max_bytes=2000000' >"$ws/loop/review.conf"
}

printf '%s\n' '=== whitespace-only citation ==='
ws=$(new_ws whitespace-citation)
seed_retro "$ws"
reviewer=$TMP_ROOT/whitespace-reviewer
{
  printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null'
  printf '%s\n' \
    'printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN "THEME: fabricated recurrence" "CLASS: rule" MEMBERS:' \
    'printf "%s \n" "- flush-2026-08-10.md:" "- flush-2026-08-17.md:"' \
    'printf "%s\n" "WEEKS: 1900-W01" "EVIDENCE: no verbatim lesson text was cited" "PROMOTE: yes" RAW-REVIEW-OUTPUT-END'
} >"$reviewer"
chmod +x "$reviewer"
write_base_conf "$ws" "$reviewer"
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W34 >"$TMP_ROOT/whitespace.out" 2>"$TMP_ROOT/whitespace.err"
rc=$?
candidate=$(find "$ws/loop/promotions" -type f -name 'candidates-*.md' ! -name '*.rejects.md' | head -n 1)
printf 'rc=%s receipt=%s\n' "$rc" "$(tail -n 1 "$ws/loop/promotions/runs.log")"
printf 'candidate_promote=%s candidate_run_k=%s member_hashes=%s\n' \
  "$(sed -n 's/^promote: //p' "$candidate" | head -n 1)" \
  "$(sed -n 's/^run-k: //p' "$candidate" | head -n 1)" \
  "$(grep -c '^member-hash:' "$candidate")"

printf '%s\n' '=== equal-second late arrival ==='
ws=$(new_ws equal-second-late)
dates=$(python3 -B - <<'PY'
import datetime
today = datetime.datetime.now(datetime.timezone.utc).date()
monday = today - datetime.timedelta(days=today.isoweekday() - 1)
print((monday - datetime.timedelta(weeks=1)).isoformat(), monday.isoformat())
PY
)
read -r previous_date current_date <<EOF
$dates
EOF
printf '%s\n' '- previous current-window lesson' >"$ws/loop/archive/flush-$previous_date.md"
printf '%s\n' '- current current-window lesson' >"$ws/loop/archive/flush-$current_date.md"
capture=$TMP_ROOT/equal-second-prompt
reviewer=$TMP_ROOT/capture-no-groups
{
  printf '%s\n' '#!/usr/bin/env bash' 'capture=$1' 'cat >"$capture"' \
    'printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END'
} >"$reviewer"
chmod +x "$reviewer"
write_base_conf "$ws" "$reviewer $capture"
"$ROOT/scripts/raw-review.sh" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/equal1.err"
first_rc=$?
watermark=$(sed -n '1p' "$ws/loop/promotions/.last-success-epoch")
late=$ws/loop/archive/flush-2020-01-06.md
printf '%s\n' '- arbitrarily late lesson at the receipt-second boundary' >"$late"
python3 -B - "$late" "$watermark" <<'PY'
import os
import sys
os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))
PY
mtime=$(stat -f '%m' "$late")
"$ROOT/scripts/raw-review.sh" --workspace "$ws" >/dev/null 2>"$TMP_ROOT/equal2.err"
second_rc=$?
included=$(grep -Fc 'RAW-FILE: loop/archive/flush-2020-01-06.md' "$capture")
printf 'first_rc=%s second_rc=%s stored_watermark=%s late_mtime=%s second_prompt_occurrences=%s\n' \
  "$first_rc" "$second_rc" "$watermark" "$mtime" "$included"

printf '%s\n' '=== install --check versus production config parser ==='
ws=$(new_ws leading-space-config)
seed_retro "$ws"
reviewer=$TMP_ROOT/no-groups
{
  printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
    'printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END'
} >"$reviewer"
chmod +x "$reviewer"
printf '  producer=producer-model\n  reviewer other-model %s\n' "$reviewer" >"$ws/loop/review.conf"
"$ROOT/install.sh" --check --workspace "$ws" >"$TMP_ROOT/check.out" 2>"$TMP_ROOT/check.err"
check_rc=$?
review_config_warnings=$(grep -c 'warning: review-config:' "$TMP_ROOT/check.err")
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/leading.err"
raw_rc=$?
printf 'check_rc=%s review_config_warnings=%s raw_review_rc=%s raw_receipt=%s\n' \
  "$check_rc" "$review_config_warnings" "$raw_rc" "$(tail -n 1 "$ws/loop/promotions/runs.log")"

printf '%s\n' '=== timeout descendant ==='
ws=$(new_ws timeout-descendant)
seed_retro "$ws"
sentinel=$TMP_ROOT/timeout-descendant-survived
reviewer=$TMP_ROOT/timeout-parent
{
  printf '%s\n' '#!/usr/bin/env bash' 'sentinel=$1' 'cat >/dev/null' \
    '/bin/sh -c '\''trap "" HUP TERM; sleep 3; : >"$1"'\'' sh "$sentinel" &' \
    'sleep 20'
} >"$reviewer"
chmod +x "$reviewer"
write_base_conf "$ws" "$reviewer $sentinel" 1
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/timeout.err"
timeout_rc=$?
sleep 4
printf 'timeout_rc=%s receipt_error=%s descendant_survived=%s\n' \
  "$timeout_rc" "$(sed -n 's/.* error=//p' "$ws/loop/promotions/runs.log" | tail -n 1)" \
  "$([[ -e "$sentinel" ]] && printf yes || printf no)"

printf '%s\n' '=== argv injection remains literal ==='
ws=$(new_ws argv-injection)
seed_retro "$ws"
pwn=$TMP_ROOT/config-eval-pwned
reviewer=$TMP_ROOT/args-no-groups
{
  printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
    'printf "%s\n" RAW-REVIEW-OUTPUT-BEGIN NO_GROUPS: RAW-REVIEW-OUTPUT-END'
} >"$reviewer"
chmod +x "$reviewer"
printf 'producer=producer-model\nreviewer other-model %s $(touch %s) ; touch %s\n' "$reviewer" "$pwn" "$pwn" >"$ws/loop/review.conf"
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W34 >/dev/null 2>"$TMP_ROOT/argv.err"
argv_rc=$?
printf 'argv_rc=%s injection_side_effect=%s\n' "$argv_rc" "$([[ -e "$pwn" ]] && printf yes || printf no)"

printf '%s\n' '=== notification append and redaction ==='
ws=$(new_ws notification)
printf '%s\n' 'SECRET_LESSON_BODY must never enter notifications' >"$ws/loop/archive/flush-2026-08-10.md"
printf '%s\n' 'producer=producer-model' 'reviewer missing-model /definitely/missing/reviewer' >"$ws/loop/review.conf"
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/notify1.err"
notify_rc1=$?
"$ROOT/scripts/raw-review.sh" --workspace "$ws" --week 2026-W33 >/dev/null 2>"$TMP_ROOT/notify2.err"
notify_rc2=$?
notify=$ws/loop/notify/review-$(date -u +%Y-%m-%d).md
printf 'notify_rcs=%s/%s blocks=%s secret_occurrences=%s\n' "$notify_rc1" "$notify_rc2" \
  "$(grep -c '^## .* runid=' "$notify")" "$(grep -c 'SECRET_LESSON_BODY' "$notify")"
