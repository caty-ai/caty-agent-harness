#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

DOC_PATH='docs/trial-isolation.md'
ADOPTION_PATH='docs/adoption-wiring.md'
ENQUEUE_PATH='scripts/trial-enqueue.sh'
EXPECT_CONDITION2_LINE='589298a1955265fbf163aeebb602722d2741d5e7'
EXPECT_ENQUEUE_T2_LINE='626dd187bc9aa985cc034b8762a7a4307cfdca46'
EXPECT_ADOPTION_T2_ROW='613a8d4dd851868aafafb5709d777ac30d07aebf'
failures=0

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t04-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

visible_content() {
  local file="$1"
  run_isolated python3 -B - "$file" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    text = handle.read()
sys.stdout.write(re.sub(r'<!--.*?-->', '', text, flags=re.S))
PY
}

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

line_hash_matches() {
  path=$1
  pattern=$2
  expected=$3
  [ -f "$path" ] || return 1
  line=$(visible_content "$path" | grep -F "$pattern" 2>/dev/null | sed -n '1p') || return 1
  [ -n "$line" ] || return 1
  [ "$(printf '%s\n' "$line" | git hash-object --stdin 2>/dev/null)" = "$expected" ]
}

check_public_intro() {
  [ -f "$DOC_PATH" ] || return 1
  visible_content "$DOC_PATH" | grep -F "caty-ai/x-collector" >/dev/null 2>&1
}

check_link_line() {
  [ -f "$DOC_PATH" ] || return 1
  visible_content "$DOC_PATH" | grep -F "https://github.com/caty-ai/x-collector" >/dev/null 2>&1
}

check_go_through_pipeline() {
  [ -f "$DOC_PATH" ] || return 1
  visible_content "$DOC_PATH" | grep -Ei "(through|via) (that|the|this) (collection )?pipeline" >/dev/null 2>&1
}

check_inherit_controls() {
  [ -f "$DOC_PATH" ] || return 1
  visible_content "$DOC_PATH" | grep -F "inherit" >/dev/null 2>&1 &&
  visible_content "$DOC_PATH" | grep -F "collection controls" >/dev/null 2>&1
}

check_condition1_still_closed() {
  [ -f "$DOC_PATH" ] || return 1
  visible_content "$DOC_PATH" | grep -F "The collection-controls prerequisite (tracked on the operator's private tracker) is closed, providing the required collection controls." >/dev/null 2>&1
}

check_condition2_line() {
  line_hash_matches "$DOC_PATH" "pre-approved the concrete trial plan." "$EXPECT_CONDITION2_LINE"
}

check_enqueue_t2_line() {
  line_hash_matches "$ENQUEUE_PATH" "T2) isolation_level='" "$EXPECT_ENQUEUE_T2_LINE"
}

check_adoption_t2_row() {
  line_hash_matches "$ADOPTION_PATH" "| T2 |" "$EXPECT_ADOPTION_T2_ROW"
}

check_private_count() {
  [ -f "$DOC_PATH" ] || return 1
  [ "$(visible_content "$DOC_PATH" | grep -o 'private' | wc -l | tr -d ' ')" = "2" ]
}

run_check "a01" "public pipeline introduction is present" "public pipeline introduction is missing" check_public_intro
run_check "a02" "linked public repository line matches the required target" "linked public repository line is missing or changed" check_link_line
run_check "a03" "qualifying trials are routed through that pipeline" "pipeline-routing statement is missing" check_go_through_pipeline
run_check "a04" "pipeline control inheritance is stated" "pipeline control-inheritance statement is missing" check_inherit_controls
run_check "a05" "condition 1 still requires the closed prerequisite" "condition 1 changed" check_condition1_still_closed
run_check "a06" "condition 2 line remains unchanged" "condition 2 line changed" check_condition2_line
run_check "a07" "trial-enqueue T2 isolation string remains unchanged" "trial-enqueue T2 isolation string changed" check_enqueue_t2_line
run_check "a08" "adoption-wiring T2 row remains unchanged" "adoption-wiring T2 row changed" check_adoption_t2_row
run_check "a09" "no additional private-reference wording was introduced" "additional private-reference wording was introduced" check_private_count

[ "$failures" -eq 0 ]
