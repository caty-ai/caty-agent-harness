#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/adapters/openclaw/distill-audit.sh
TMP_ROOT=${TMPDIR:-/tmp}/distill-audit-test.$$
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
  mkdir -p "$ws/loop/pending" "$ws/skills/_staging"
  {
    printf '%s\n' '## Verified facts'
    printf '%s\n' '## General rules'
    printf '%s\n' '## Open failures'
    i=1
    while [ "$i" -le 100 ]; do
      printf -- '- 2026-07-05 old failure %03d (source: distill-audit)\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' '## Lessons learned'
    i=1
    while [ "$i" -le 60 ]; do
      printf -- '- 2026-07-05 old lesson %03d (source: distill-audit)\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' '## Last session'
  } >"$ws/STATE.md"
  mkdir -p "$ws/input"
  printf 'transcript\n' >"$ws/input/session.log"
  printf '%s\n' "$ws"
}

write_distiller() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
## LESSONS
- 2026-07-06 new lesson (source: distill-audit)
## OPEN_FAILURES
- 2026-07-06 new failure (source: distill-audit)
## SKILL_DRAFTS
OUT
SH
  chmod +x "$path"
}

write_auth_failure_distiller() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'AxiosError: Request failed with status code 401' >&2
exit 1
SH
  chmod +x "$path"
}

write_hanging_distiller() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
sleep 60
SH
  chmod +x "$path"
}

write_prompt_dump_distiller() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PROMPT_DUMP"
cat <<'OUT'
## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### prompt-skill
trigger: prompt-test
## Procedure
check the source
OUT
SH
  chmod +x "$path"
}

write_integrity_distiller() {
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

not_in_promoted_sections() {
  needle=$1
  state_file=$2
  awk -v needle="$needle" '
    {
      if (index($0, needle)) {
        found_anywhere = 1
      }
    }
    /^[[:space:]]*##[[:space:]]+/ {
      header = tolower($0)
      sub(/^[[:space:]]*/, "", header)
      sub(/[[:space:]]*$/, "", header)
      promoted = (header == "## verified facts" || header == "## general rules")
      if (promoted) {
        saw_promoted_header = 1
      }
      next
    }
    promoted && index($0, needle) {found_promoted = 1}
    END {
      exit(found_promoted || (!saw_promoted_header && found_anywhere))
    }
  ' "$state_file"
}

write_chars() {
  path=$1
  count=$2
  char=${3:-x}
  head -c "$count" /dev/zero | tr '\0' "$char" >"$path"
}

section_count() {
  section=$1
  file=$2
  awk -v section="$section" '
    index($0, section) == 1 {in_section = 1; next}
    in_section && /^## / {exit}
    in_section {count++}
    END {print count + 0}
  ' "$file"
}

helper_state=$TMP_ROOT/promoted-header-variants.md
{
  printf '%s\n' '## VERIFIED FACTS   '
  printf '%s\n' 'must-not-be-promoted'
  printf '%s\n' '## Open failures'
} >"$helper_state"
if ! not_in_promoted_sections 'must-not-be-promoted' "$helper_state"; then
  pass "promotion test helper recognizes case and trailing-space header variants"
else
  fail_case "promotion test helper recognizes case and trailing-space header variants" "needle was not detected"
fi

helper_state=$TMP_ROOT/promoted-header-missing.md
{
  printf '%s\n' '## Open failures'
  printf '%s\n' 'must-not-be-promoted'
} >"$helper_state"
if ! not_in_promoted_sections 'must-not-be-promoted' "$helper_state"; then
  pass "promotion test helper fails closed when promoted headers are absent"
else
  fail_case "promotion test helper fails closed when promoted headers are absent" "needle was not detected"
fi

distiller=$TMP_ROOT/input-filter-prompt-dump.sh
write_prompt_dump_distiller "$distiller"
attest_distiller_wrapper "$distiller" input-filter-prompt-dump

ws=$(make_ws input-filter-mixed)
rm "$ws/input/session.log"
printf '%s\n' 'CONVERSATION_JSONL_MARKER' >"$ws/input/00-conversation.jsonl"
write_chars "$ws/input/run.trajectory.jsonl" 30000 t
write_chars "$ws/input/heartbeat.json" 30000 h
write_chars "$ws/input/heartbeat-state.json" 30000 h
write_chars "$ws/input/catalog.json" 30000 c
write_chars "$ws/input/skills-catalog.json" 30000 c
write_chars "$ws/input/sessions.json" 30000 s
printf '%s\n' 'archived trajectory' >"$ws/input/run.trajectory.jsonl.archived"
printf '%s\n' 'heartbeat backup' >"$ws/input/heartbeat.json.bak"
printf '%s\n' 'heartbeat state temp' >"$ws/input/heartbeat-state.json.tmp"
printf '%s\n' 'catalog backup' >"$ws/input/catalog.json.bak"
printf '%s\n' 'skills catalog temp' >"$ws/input/skills-catalog.json.tmp"
printf '%s\n' 'session catalog backup' >"$ws/input/sessions.json.bak"
prompt_dump=$TMP_ROOT/input-filter-mixed-prompt.md
output=$(PROMPT_DUMP="$prompt_dump" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq 'CONVERSATION_JSONL_MARKER' "$prompt_dump" \
  && ! grep -Fq -- '.trajectory.jsonl ---' "$prompt_dump" \
  && ! grep -Fq -- '/heartbeat.json ---' "$prompt_dump" \
  && ! grep -Fq -- '/heartbeat-state.json ---' "$prompt_dump" \
  && ! grep -Fq -- '/catalog.json ---' "$prompt_dump" \
  && ! grep -Fq -- '/skills-catalog.json ---' "$prompt_dump" \
  && ! grep -Fq -- '/sessions.json ---' "$prompt_dump" \
  && ! grep -Fq -- '.trajectory.jsonl.archived ---' "$prompt_dump" \
  && ! grep -Fq -- '/heartbeat.json.bak ---' "$prompt_dump" \
  && ! grep -Fq -- '/heartbeat-state.json.tmp ---' "$prompt_dump" \
  && ! grep -Fq -- '/catalog.json.bak ---' "$prompt_dump" \
  && ! grep -Fq -- '/skills-catalog.json.tmp ---' "$prompt_dump" \
  && ! grep -Fq -- '/sessions.json.bak ---' "$prompt_dump"; then
  pass "mixed OpenClaw input selects conversation JSONL without snapshot budget dilution"
else
  fail_case "mixed OpenClaw input selects conversation JSONL without snapshot budget dilution" "rc=$rc output=$output prompt=$(grep '^--- ' "$prompt_dump" 2>/dev/null)"
fi

ws=$(make_ws input-filter-incremental)
rm "$ws/input/session.log"
touch -t 202001010000 "$ws/loop/.distill-last-run"
printf '%s\n' 'INCREMENTAL_CONVERSATION_MARKER' >"$ws/input/conversation.jsonl"
printf '%s\n' 'trajectory' >"$ws/input/run.trajectory.jsonl"
printf '%s\n' 'heartbeat' >"$ws/input/heartbeat.json"
printf '%s\n' 'catalog' >"$ws/input/catalog.json"
prompt_dump=$TMP_ROOT/input-filter-incremental-prompt.md
output=$(PROMPT_DUMP="$prompt_dump" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq 'INCREMENTAL_CONVERSATION_MARKER' "$prompt_dump" \
  && ! grep -Fq -- '.trajectory.jsonl ---' "$prompt_dump" \
  && ! grep -Fq -- '/heartbeat.json ---' "$prompt_dump" \
  && ! grep -Fq -- '/catalog.json ---' "$prompt_dump"; then
  pass "incremental marker path applies the same conversation input filter"
else
  fail_case "incremental marker path applies the same conversation input filter" "rc=$rc output=$output prompt=$(grep '^--- ' "$prompt_dump" 2>/dev/null)"
fi

ws=$(make_ws input-filter-only-snapshots)
rm "$ws/input/session.log"
printf '%s\n' 'trajectory' >"$ws/input/run.trajectory.jsonl"
printf '%s\n' 'heartbeat' >"$ws/input/heartbeat.json"
printf '%s\n' 'heartbeat state' >"$ws/input/heartbeat-state.json"
printf '%s\n' 'catalog' >"$ws/input/catalog.json"
printf '%s\n' 'skills catalog' >"$ws/input/skills-catalog.json"
printf '%s\n' 'session catalog' >"$ws/input/sessions.json"
output=$(DISTILLER_CMD="$TMP_ROOT/must-not-run-distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx 'nothing to distill' \
  && [ -e "$ws/loop/.distill-last-run" ] \
  && ! find "$ws/loop/pending" -name 'distill-*.md' -print | grep -q .; then
  pass "snapshot-only input exits cleanly without invoking the distiller"
else
  fail_case "snapshot-only input exits cleanly without invoking the distiller" "rc=$rc output=$output"
fi

ws=$(make_ws input-filter-claire)
prompt_dump=$TMP_ROOT/input-filter-claire-prompt.md
output=$(PROMPT_DUMP="$prompt_dump" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && grep -Fq "$ws/input/session.log" "$prompt_dump"; then
  pass "Claire-style non-JSONL transcript input remains eligible"
else
  fail_case "Claire-style non-JSONL transcript input remains eligible" "rc=$rc output=$output"
fi

ws=$(make_ws input-filter-similar-names)
rm "$ws/input/session.log"
printf '%s\n' 'TRAJECTORY_NOTES_CONVERSATION' >"$ws/input/trajectory-notes.jsonl"
printf '%s\n' 'HEARTBEAT_ANALYSIS_CONVERSATION' >"$ws/input/heartbeat-analysis.jsonl"
printf '%s\n' 'CATALOG_REVIEW_CONVERSATION' >"$ws/input/catalog-review.jsonl"
prompt_dump=$TMP_ROOT/input-filter-similar-names-prompt.md
output=$(PROMPT_DUMP="$prompt_dump" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq 'TRAJECTORY_NOTES_CONVERSATION' "$prompt_dump" \
  && grep -Fq 'HEARTBEAT_ANALYSIS_CONVERSATION' "$prompt_dump" \
  && grep -Fq 'CATALOG_REVIEW_CONVERSATION' "$prompt_dump"; then
  pass "snapshot terms inside ordinary conversation filenames are not over-filtered"
else
  fail_case "snapshot terms inside ordinary conversation filenames are not over-filtered" "rc=$rc output=$output"
fi

ws=$(make_ws cap)
distiller=$TMP_ROOT/fake-distiller.sh
write_distiller "$distiller"
attest_distiller_wrapper "$distiller" fake-distiller
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
lessons_lines=$(section_count "## Lessons learned" "$ws/STATE.md")
failures_lines=$(section_count "## Open failures" "$ws/STATE.md")
if [ "$rc" -eq 0 ] \
  && [ "$lessons_lines" -eq 60 ] \
  && [ "$failures_lines" -eq 100 ] \
  && grep -Fq -- '- 2026-07-06 new lesson (source: distill-audit)' "$ws/STATE.md" \
  && grep -Fq -- '- 2026-07-06 new failure (source: distill-audit)' "$ws/STATE.md" \
  && ! grep -Fq -- '- 2026-07-05 old lesson 001 (source: distill-audit)' "$ws/STATE.md" \
  && ! grep -Fq -- '- 2026-07-05 old failure 001 (source: distill-audit)' "$ws/STATE.md" \
  && [ ! -e "$ws/.STATE.md.tmp.$$" ] \
  && [ ! -d "$ws/loop/.distill-state.lock" ]; then
  pass "state rewrite is capped, atomic temp cleaned, and lock released"
else
  fail_case "state rewrite is capped, atomic temp cleaned, and lock released" "rc=$rc output=$output lessons=$lessons_lines failures=$failures_lines"
fi

ws=$(make_ws bad-cmd)
set +e
output=$(DISTILLER_CMD="$TMP_ROOT/missing-distiller.sh" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] && printf '%s\n' "$output" | grep -q 'DISTILLER_CMD not found'; then
  pass "invalid distiller command exits infra error"
else
  fail_case "invalid distiller command exits infra error" "rc=$rc output=$output"
fi

ws=$(make_ws auth-failure)
distiller=$TMP_ROOT/auth-failure-distiller.sh
write_auth_failure_distiller "$distiller"
attest_distiller_wrapper "$distiller" auth-failure-distiller
set +e
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$output" | grep -q 'AxiosError: Request failed with status code 401' \
  && printf '%s\n' "$output" | grep -q 'distill-audit.sh: call-site=distiller class=deterministic-auth' \
  && ! find "$ws/loop/pending" -name '.distill-*.md.tmp.*' -print | grep -q . \
  && ! find "$ws/loop/pending" -name 'distill-*.md' -print | grep -q .; then
  pass "401 distiller failure is classified deterministic-auth and cleans temp"
else
  fail_case "401 distiller failure is classified deterministic-auth and cleans temp" "rc=$rc output=$output"
fi

ws=$(make_ws timeout)
distiller=$TMP_ROOT/hanging-distiller.sh
write_hanging_distiller "$distiller"
attest_distiller_wrapper "$distiller" hanging-distiller
utc_date=$(date -u '+%Y-%m-%d')
set +e
output=$(DISTILLER_CMD="$distiller" DISTILL_TIMEOUT_S=2 DISTILL_GRACE_S=1 bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$output" | grep -q 'distill-audit.sh: call-site=distiller class=transient' \
  && [ ! -e "$ws/loop/.distill-last-run" ] \
  && [ ! -e "$ws/loop/pending/distill-$utc_date.md" ] \
  && ! find "$ws/loop/pending" -name '.distill-*.md.tmp.*' -print | grep -q . \
  && [ ! -d "$ws/loop/.distill-state.lock" ]; then
  pass "timed-out distiller leaves no marker, reply, temp, or lock"
else
  fail_case "timed-out distiller leaves no marker, reply, temp, or lock" "rc=$rc output=$output"
fi

ws=$(make_ws prompt-contract)
distiller=$TMP_ROOT/prompt-dump-distiller.sh
prompt_dump=$TMP_ROOT/distiller-prompt.md
write_prompt_dump_distiller "$distiller"
attest_distiller_wrapper "$distiller" prompt-dump-distiller
output=$(PROMPT_DUMP="$prompt_dump" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq "Current UTC date: $(date -u '+%Y-%m-%d')" "$prompt_dump" \
  && grep -Fq 'Do not save transient' "$prompt_dump" \
  && grep -Fq 'Open failures' "$prompt_dump" \
  && grep -q '^## Verification$' "$ws/skills/_staging/prompt-skill/SKILL.md"; then
  pass "distiller prompt has UTC and anti-capture contract; drafts have verification"
else
  fail_case "distiller prompt has UTC and anti-capture contract; drafts have verification" "rc=$rc output=$output"
fi

if grep -Fq 'returning all sections empty is the correct and desired outcome, not a failure' "$prompt_dump" \
  && grep -Fq 'never invent or pad observations to appear productive' "$prompt_dump" \
  && grep -Fq 'success, partial, fail, or uncertain' "$prompt_dump" \
  && grep -Fq 'Verified evidence takes priority over heuristic inference' "$prompt_dump" \
  && grep -Fq 'when evidence is absent, use uncertain' "$prompt_dump"; then
  pass "distiller prompt permits no-op and requires evidence-first outcome triage"
else
  fail_case "distiller prompt permits no-op and requires evidence-first outcome triage" "missing no-op or outcome-triage text"
fi

# Hermes has no distill script; its DISTILL guidance is the bootstrap block, a
# static data file — a text assertion IS the behavioral contract for it.
if grep -Fq 'do not save transient environment-dependent failures' "$ROOT/adapters/hermes/bootstrap-block.md"; then
  pass "Hermes bootstrap block carries the anti-capture contract"
else
  fail_case "Hermes bootstrap block carries the anti-capture contract" "missing anti-capture text"
fi

# Claude-code capture surface, behaviorally: run the PreCompact hook with a mock
# flush command that dumps the prompt it receives on stdin.
hook_ws=$TMP_ROOT/hook-ws
mkdir -p "$hook_ws/loop/pending"
{
  printf '%s\n' '## Verified facts'
  printf '%s\n' '## General rules'
  printf '%s\n' '## Open failures'
  printf '%s\n' '## Lessons learned'
  printf '%s\n' '## Last session'
} >"$hook_ws/STATE.md"
hook_mock=$TMP_ROOT/flush-mock.sh
cat >"$hook_mock" <<'SH'
#!/usr/bin/env bash
cat >"$FLUSH_PROMPT_DUMP"
printf 'NO_REPLY\n'
SH
chmod +x "$hook_mock"
hook_tmp=$TMP_ROOT/hook-tmpdir
mkdir -p "$hook_tmp"
flush_dump=$TMP_ROOT/flush-prompt.md
printf '{"session_id":"flh-test-%s","cwd":"%s"}' "$$" "$hook_ws" \
  | TMPDIR=$hook_tmp FLUSH_PROMPT_DUMP=$flush_dump FLH_FLUSH_CMD=$hook_mock FLH_FLUSH_TIMEOUT=30 \
    bash "$ROOT/adapters/claude-code/precompact-flush-hook.sh" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fq "Current UTC date: $(date -u '+%Y-%m-%d')" "$flush_dump" \
  && grep -Fq 'Do not save transient environment failures' "$flush_dump"; then
  pass "precompact flush prompt has UTC date and anti-capture contract"
else
  fail_case "precompact flush prompt has UTC date and anti-capture contract" "rc=$rc dump=$(cat "$flush_dump" 2>/dev/null | head -5)"
fi

ws=$(make_ws size-under)
write_chars "$ws/AGENTS.md" 3999
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
if [ "$rc" -eq 0 ] \
  && ! printf '%s\n' "$output" | grep -Fq 'WARNING: AGENTS.md ' \
  && ! printf '%s\n' "$output" | grep -Fq 'VIOLATION: AGENTS.md ' \
  && ! grep -Fq 'WARNING: AGENTS.md ' "$log" \
  && ! grep -Fq 'VIOLATION: AGENTS.md ' "$log"; then
  pass "injection size check stays quiet below warning threshold"
else
  fail_case "injection size check stays quiet below warning threshold" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-warning)
write_chars "$ws/AGENTS.md" 4000
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected='WARNING: AGENTS.md 4000 chars >= 80% of cap 5000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size check warns at eighty percent of cap"
else
  fail_case "injection size check warns at eighty percent of cap" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-violation)
write_chars "$ws/AGENTS.md" 5001
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected='VIOLATION: AGENTS.md 5001 chars > cap 5000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size check flags over-cap files"
else
  fail_case "injection size check flags over-cap files" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-override)
write_chars "$ws/AGENTS.md" 3000
write_chars "$ws/MEMORY.md" 8000
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='AGENTS.md=3000' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected='WARNING: AGENTS.md 3000 chars >= 80% of cap 3000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log" \
  && ! printf '%s\n' "$output" | grep -Fq 'MEMORY.md' \
  && ! grep -Fq 'MEMORY.md' "$log"; then
  pass "injection size cap override is scoped to named file"
else
  fail_case "injection size cap override is scoped to named file" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-octal-warning)
write_chars "$ws/AGENTS.md" 85
set +e
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='AGENTS.md=090' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
log=$ws/loop/pending/distill-runs.log
expected='WARNING: AGENTS.md 85 chars >= 80% of cap 90'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size octal-looking override warns as base ten"
else
  fail_case "injection size octal-looking override warns as base ten" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-octal-violation)
write_chars "$ws/AGENTS.md" 91
set +e
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='AGENTS.md=090' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
log=$ws/loop/pending/distill-runs.log
expected='VIOLATION: AGENTS.md 91 chars > cap 90'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size octal-looking override violates as base ten"
else
  fail_case "injection size octal-looking override violates as base ten" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-multi-override)
write_chars "$ws/AGENTS.md" 3001
write_chars "$ws/MEMORY.md" 9001
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='AGENTS.md=3000,MEMORY.md=9000' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected_agents='VIOLATION: AGENTS.md 3001 chars > cap 3000'
expected_memory='VIOLATION: MEMORY.md 9001 chars > cap 9000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected_agents" \
  && printf '%s\n' "$output" | grep -Fqx "$expected_memory" \
  && grep -Fq " $expected_agents" "$log" \
  && grep -Fq " $expected_memory" "$log"; then
  pass "injection size cap override applies multiple csv entries"
else
  fail_case "injection size cap override applies multiple csv entries" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-spaced-override)
write_chars "$ws/AGENTS.md" 3000
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS=' AGENTS.md = 3000 ' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected='WARNING: AGENTS.md 3000 chars >= 80% of cap 3000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size cap override trims whitespace"
else
  fail_case "injection size cap override trims whitespace" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-malformed-warning)
write_chars "$ws/AGENTS.md" 5001
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='a=b=c' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
warning='injection_size_check: ignoring malformed DISTILL_SIZE_CAPS entries'
expected='VIOLATION: AGENTS.md 5001 chars > cap 5000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$warning" \
  && [ "$(printf '%s\n' "$output" | grep -Fc "$warning")" -eq 1 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log"; then
  pass "injection size malformed override warns once"
else
  fail_case "injection size malformed override warns once" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-unknown-warning)
write_chars "$ws/AGENTS.md" 3999
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='TYPO.md=1' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
warning='injection_size_check: ignoring malformed DISTILL_SIZE_CAPS entries'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$warning" \
  && [ "$(printf '%s\n' "$output" | grep -Fc "$warning")" -eq 1 ] \
  && ! printf '%s\n' "$output" | grep -Fq 'AGENTS.md ' \
  && ! grep -Fq 'AGENTS.md ' "$log"; then
  pass "injection size unknown override warns once and has no effect"
else
  fail_case "injection size unknown override warns once and has no effect" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-combined-rejections)
write_chars "$ws/AGENTS.md" 3999
output=$(DISTILLER_CMD="$distiller" DISTILL_SIZE_CAPS='TYPO.md=1,a=b=c' bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
warning='injection_size_check: ignoring malformed DISTILL_SIZE_CAPS entries'
if [ "$rc" -eq 0 ] \
  && [ "$(printf '%s\n' "$output" | grep -Fc "$warning")" -eq 1 ] \
  && ! printf '%s\n' "$output" | grep -Fq 'AGENTS.md ' \
  && ! grep -Fq 'AGENTS.md ' "$log"; then
  pass "injection size combined rejected overrides warn once"
else
  fail_case "injection size combined rejected overrides warn once" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

ws=$(make_ws size-boundary)
write_chars "$ws/AGENTS.md" 5000
output=$(DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
log=$ws/loop/pending/distill-runs.log
expected='WARNING: AGENTS.md 5000 chars >= 80% of cap 5000'
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx "$expected" \
  && grep -Fq " $expected" "$log" \
  && ! printf '%s\n' "$output" | grep -Fq 'VIOLATION: AGENTS.md' \
  && ! grep -Fq 'VIOLATION: AGENTS.md' "$log"; then
  pass "injection size exact cap boundary warns without violation"
else
  fail_case "injection size exact cap boundary warns without violation" "rc=$rc output=$output log=$(cat "$log" 2>/dev/null)"
fi

distiller=$TMP_ROOT/integrity-distiller.sh
write_integrity_distiller "$distiller"
attest_distiller_wrapper "$distiller" integrity-distiller

ws=$(make_ws integrity-valid-files)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### valid-file-reference
trigger: test
files_created: input/session.log
Use the existing transcript.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ws/skills/_staging/valid-file-reference/SKILL.md" ]; then
  pass "integrity gate accepts existing files_created references"
else
  fail_case "integrity gate accepts existing files_created references" "rc=$rc output=$output"
fi

outside_file=$TMP_ROOT/outside-proof.txt
printf '%s\n' 'outside workspace' >"$outside_file"

ws=$(make_ws integrity-relative-traversal)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### relative-traversal
trigger: test
files_created: ../outside-proof.txt
Do not create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/relative-traversal/SKILL.md" ] \
  && grep -Fq 'distill integrity mismatch: skill relative-traversal' "$ws/STATE.md" \
  && not_in_promoted_sections '../outside-proof.txt' "$ws/STATE.md"; then
  pass "files_created rejects parent-directory traversal"
else
  fail_case "files_created rejects parent-directory traversal" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-absolute-path)
reply="## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### absolute-reference
trigger: test
files_created: $outside_file
Do not create this skill."
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/absolute-reference/SKILL.md" ] \
  && grep -Fq 'distill integrity mismatch: skill absolute-reference' "$ws/STATE.md" \
  && not_in_promoted_sections "$outside_file" "$ws/STATE.md"; then
  pass "files_created rejects absolute paths"
else
  fail_case "files_created rejects absolute paths" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-empty-elements)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### trailing-empty-element
trigger: test
files_created: input/session.log,
Do not create this skill.
### middle-empty-element
trigger: test
files_created: input/session.log, , input/session.log
Do not create this skill.
### valid-element-sibling
trigger: test
files_created: input/session.log
Create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/trailing-empty-element/SKILL.md" ] \
  && [ ! -e "$ws/skills/_staging/middle-empty-element/SKILL.md" ] \
  && [ -f "$ws/skills/_staging/valid-element-sibling/SKILL.md" ] \
  && grep -Fq 'distill integrity mismatch: skill trailing-empty-element' "$ws/STATE.md" \
  && grep -Fq 'distill integrity mismatch: skill middle-empty-element' "$ws/STATE.md"; then
  pass "files_created rejects empty list elements without losing valid siblings"
else
  fail_case "files_created rejects empty list elements without losing valid siblings" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-non-files)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### workspace-root-reference
trigger: test
files_created: .
Do not create this skill.
### directory-reference
trigger: test
files_created: input
Do not create this skill.
### regular-file-sibling
trigger: test
files_created: input/session.log
Create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/workspace-root-reference/SKILL.md" ] \
  && [ ! -e "$ws/skills/_staging/directory-reference/SKILL.md" ] \
  && [ -f "$ws/skills/_staging/regular-file-sibling/SKILL.md" ] \
  && grep -Fq 'distill integrity mismatch: skill workspace-root-reference' "$ws/STATE.md" \
  && grep -Fq 'distill integrity mismatch: skill directory-reference' "$ws/STATE.md"; then
  pass "files_created accepts only regular files without losing valid siblings"
else
  fail_case "files_created accepts only regular files without losing valid siblings" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-missing-file)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### missing-file-reference
trigger: test
files_created: hallucinated/missing.txt
Do not create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/missing-file-reference/SKILL.md" ] \
  && grep -Fq 'declares files_created=hallucinated/missing.txt not found' "$ws/STATE.md" \
  && ! grep -Fq 'hallucinated/missing.txt' "$ws/skills/_staging"/*/SKILL.md 2>/dev/null \
  && not_in_promoted_sections 'hallucinated/missing.txt' "$ws/STATE.md"; then
  pass "missing files_created is rejected, recorded, and never silently promoted"
else
  fail_case "missing files_created is rejected, recorded, and never silently promoted" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-empty-file)
reply='## LESSONS
- 2026-07-06 lesson survives empty files_created (source: distill-audit)
## OPEN_FAILURES
- 2026-07-06 failure survives empty files_created (source: distill-audit)
## SKILL_DRAFTS
### empty-decl-skill
trigger: test
files_created:
Do not create this skill.
### valid-sibling-skill
trigger: test
Create this skill normally.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/empty-decl-skill/SKILL.md" ] \
  && [ -f "$ws/skills/_staging/valid-sibling-skill/SKILL.md" ] \
  && grep -Fq 'declares files_created= not found' "$ws/STATE.md" \
  && grep -Fq -- '- 2026-07-06 lesson survives empty files_created (source: distill-audit)' "$ws/STATE.md" \
  && grep -Fq -- '- 2026-07-06 failure survives empty files_created (source: distill-audit)' "$ws/STATE.md"; then
  pass "empty files_created is rejected without aborting sibling folds"
else
  fail_case "empty files_created is rejected without aborting sibling folds" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-source-task)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### bad-source-reference
trigger: test
source_task_id: fabricated-session.log
Do not create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/bad-source-reference/SKILL.md" ] \
  && grep -Fq 'declares source_task_id=fabricated-session.log not found' "$ws/STATE.md"; then
  pass "hallucinated source_task_id is rejected and recorded"
else
  fail_case "hallucinated source_task_id is rejected and recorded" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-target-skill)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### expected-skill-name
trigger: test
target_skill: different-skill-name
Do not create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$ws/skills/_staging/expected-skill-name/SKILL.md" ] \
  && grep -Fq 'declares target_skill=different-skill-name not found' "$ws/STATE.md"; then
  pass "mismatched target_skill is rejected and recorded"
else
  fail_case "mismatched target_skill is rejected and recorded" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-valid-target-skill)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### valid-target-skill
trigger: test
target_skill: valid-target-skill
Create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ws/skills/_staging/valid-target-skill/SKILL.md" ]; then
  pass "matching target_skill is accepted and creates a draft"
else
  fail_case "matching target_skill is accepted and creates a draft" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-valid-source-task)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### valid-source-task
trigger: test
source_task_id: session.log
Create this skill.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ws/skills/_staging/valid-source-task/SKILL.md" ]; then
  pass "selected source_task_id basename is accepted and creates a draft"
else
  fail_case "selected source_task_id basename is accepted and creates a draft" "rc=$rc output=$output"
fi

ws=$(make_ws integrity-backward-compatible)
reply='## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
### no-declarations
trigger: test
This remains the legacy draft format.'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$ws/skills/_staging/no-declarations/SKILL.md" ] \
  && grep -Fq 'This remains the legacy draft format.' "$ws/skills/_staging/no-declarations/SKILL.md" \
  && ! grep -Fq 'distill integrity mismatch: skill no-declarations' "$ws/STATE.md"; then
  pass "drafts without declarations retain legacy skill creation behavior"
else
  fail_case "drafts without declarations retain legacy skill creation behavior" "rc=$rc output=$output"
fi

ws=$(make_ws normalized-cross-source-rejection)
awk '
  {print}
  index($0, "## Lessons learned") == 1 {
    print "- 2026-07-01 shared route observation (source: flush-intake)"
  }
' "$ws/STATE.md" >"$TMP_ROOT/cross-source-state"
mv "$TMP_ROOT/cross-source-state" "$ws/STATE.md"
reply='## LESSONS
- 2026-07-06 shared route observation (source: distill-audit)
## OPEN_FAILURES
## SKILL_DRAFTS'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(grep -Fc 'shared route observation' "$ws/STATE.md")" -eq 1 ] \
  && ! grep -Fq -- '- 2026-07-06 shared route observation (source: distill-audit)' "$ws/STATE.md"; then
  pass "normalized rejection blocks flush-intake text from distill"
else
  fail_case "normalized rejection blocks flush-intake text from distill" "rc=$rc output=$output"
fi

ws=$(make_ws normalized-cross-date-rejection)
awk '
  {print}
  index($0, "## Lessons learned") == 1 {
    print "- 2026-07-01 repeated on a later date (source: distill-audit)"
  }
' "$ws/STATE.md" >"$TMP_ROOT/cross-date-state"
mv "$TMP_ROOT/cross-date-state" "$ws/STATE.md"
reply='## LESSONS
- 2026-07-06 repeated on a later date (source: distill-audit)
## OPEN_FAILURES
## SKILL_DRAFTS'
output=$(DISTILL_REPLY="$reply" DISTILLER_CMD="$distiller" bash "$SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(grep -Fc 'repeated on a later date' "$ws/STATE.md")" -eq 1 ] \
  && ! grep -Fq -- '- 2026-07-06 repeated on a later date (source: distill-audit)' "$ws/STATE.md"; then
  pass "normalized rejection blocks same distill text on a later date"
else
  fail_case "normalized rejection blocks same distill text on a later date" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
