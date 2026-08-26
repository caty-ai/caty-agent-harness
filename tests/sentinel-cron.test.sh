#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/adapters/openclaw/sentinel-cron.sh
TMP_ROOT=${TMPDIR:-/tmp}/sentinel-cron-test.$$
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

seed_dates() {
  ws=$1
  printf '%s\n' 'fixture handoff' >"$ws/loop/handoffs/2026-07-05-fixture.md"
  printf '%s\n' '- 2026-07-05 | fixture | next: none | blockers: none | artifact: none | handoff: loop/handoffs/2026-07-05-fixture.md' >>"$ws/STATE.md"
  printf '%s\n' '- 2026-07-04 | task=fixture | verifier=test | verdict=pass | fixture' >>"$ws/loop/VERIFY.log.md"
}

ws=$TMP_ROOT/ws
"$ROOT/install.sh" --workspace "$ws" >/dev/null 2>&1
seed_dates "$ws"

notice=$ws/loop/pending/sentinel-notice.md

if bash "$SCRIPT" --workspace "$ws" >/dev/null 2>&1 && [ ! -e "$notice" ]; then
  pass "comment-only review config does not trip the sentinel"
else
  fail_case "comment-only review config does not trip the sentinel" "unexpected notice for opt-in review config"
fi

rm -f "$ws/loop/RUBRIC.tmpl.md"

if bash "$SCRIPT" --workspace "$ws" >/dev/null 2>&1 \
  && [ -f "$notice" ] \
  && grep -Fqx '# fable-loop sentinel notice v1' "$notice" \
  && grep -q 'missing path: loop/RUBRIC.tmpl.md' "$notice"; then
  pass "creates notice for missing path"
else
  fail_case "creates notice for missing path" "notice missing or content unexpected"
fi

cp "$notice" "$TMP_ROOT/notice.before"
line_count_before=$(wc -l <"$notice" | tr -d '[:space:]')
if bash "$SCRIPT" --workspace "$ws" >/dev/null 2>&1 \
  && cmp -s "$notice" "$TMP_ROOT/notice.before" \
  && [ "$(wc -l <"$notice" | tr -d '[:space:]')" = "$line_count_before" ] \
  && [ "$(grep -Fxc '# fable-loop sentinel notice v1' "$notice")" -eq 1 ]; then
  pass "rerun is stable and not duplicated"
else
  fail_case "rerun is stable and not duplicated" "notice changed or marker duplicated"
fi

cp "$ROOT/templates/RUBRIC.tmpl.md" "$ws/loop/RUBRIC.tmpl.md"
cp "$notice" "$TMP_ROOT/notice.indeterminate.before"
rm -f "$ws/STATE.md"
if output=$(bash "$SCRIPT" --workspace "$ws" 2>&1) \
  && printf '%s\n' "$output" | grep -Eq '^status=paused workspace=.* entrypoint=openclaw-sentinel-cron$' \
  && cmp -s "$notice" "$TMP_ROOT/notice.indeterminate.before"; then
  pass "uninitialized workspace fails closed without rewriting notice"
else
  fail_case "uninitialized workspace fails closed without rewriting notice" \
    "status or preserved notice was unexpected"
fi

cp "$ROOT/templates/STATE.md" "$ws/STATE.md"
seed_dates "$ws"
"$ROOT/install.sh" --workspace "$ws" >/dev/null 2>&1
printf '%s\n' 'producer=producer-model' 'reviewer other-model /bin/true' >"$ws/loop/review.conf"
printf 'ts=%s runid=fixture mode=nightly window=- files=0 prompt_bytes=0 model_used=other-model chain_pos=1 blocks=0 fabricated=0 rejected=0 candidates=0 self_review_refused=- zero_streak=0 error=none\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$ws/loop/promotions/runs.log"
if bash "$SCRIPT" --workspace "$ws" >/dev/null 2>&1 && [ ! -e "$notice" ]; then
  pass "clears notice after clean check"
else
  fail_case "clears notice after clean check" "notice still exists"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
