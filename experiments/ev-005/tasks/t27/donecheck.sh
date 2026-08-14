#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

DOC='FOR-AGENTS.md'
failures=0

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
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

section() {
  number=$1
  [ -f "$DOC" ] || return 1
  awk -v number="$number" '
    $0 ~ "^## " number "[.]" { inside=1; next }
    inside && /^## [0-9]+[.]/ { exit }
    inside { print }
  ' "$DOC"
}

check_root_english_artifact() {
  [ -f "$DOC" ] || return 1
  for sibling in FOR-AGENTS.*.md; do
    [ -e "$sibling" ] && return 1
  done
  return 0
}

check_eight_sections() {
  actual=$(grep -E '^## [0-9]+[.]' "$DOC" 2>/dev/null | sed -E 's/^## ([0-9]+)[.].*$/\1/' | tr '\n' ' ')
  [ "$actual" = '1 2 3 4 5 6 7 8 ' ]
}

check_opening_tours() {
  body=$(section 1) || return 1
  printf '%s\n' "$body" | grep -Fqi '5-minute' \
    && printf '%s\n' "$body" | grep -Fqi '30-minute' \
    && printf '%s\n' "$body" | grep -Eqi 'visitor|visiting|reading'
}

check_authority_order() {
  section 2 | python3 -B -c '
import re, sys
expected = ["registry/modules.json", "docs/growth-model.md", "docs/evidence.md", "README"]
found = []
for line in sys.stdin:
    if not re.match(r"^[1-4][.] ", line):
        continue
    match = re.search(r"`([^`]+)`", line)
    if match:
        found.append(match.group(1))
    elif "README" in line:
        found.append("README")
raise SystemExit(0 if found == expected else 1)
'
}

check_state_vocabulary() {
  body=$(section 3) || return 1
  for needle in delivery visibility evidence license implemented planned unknown published preparing private observed unverified; do
    printf '%s\n' "$body" | grep -Fqi -- "$needle" || return 1
  done
}

check_evaluation_frame() {
  body=$(section 4) || return 1
  printf '%s\n' "$body" | grep -Eqi 'consisten|philosoph' \
    && printf '%s\n' "$body" | grep -Eqi 'plain|durab|long-lived' \
    && printf '%s\n' "$body" | grep -Eqi 'state|implemented.*/.*planned|planned.*/.*unknown' \
    && printf '%s\n' "$body" | grep -Eqi 'human.*gate|gate.*human'
}

check_tour_table_shape() {
  body=$(section 5) || return 1
  printf '%s\n' "$body" | grep -Eqi '^\|[[:space:]]*repository[[:space:]]*\|.*role.*\|.*verif' \
    && [ "$(printf '%s\n' "$body" | grep -Ec '^\|.*github\.com/[^/]+/[^/)]+.*\|')" -ge 1 ]
}

check_published_rows() {
  section 5 | python3 -B -c '
import json, pathlib, re, sys
try:
    registry = json.loads(pathlib.Path("registry/modules.json").read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
expected = {
    module.get("repo")
    for module in registry.get("modules", [])
    if module.get("status") == "published" and isinstance(module.get("repo"), str)
}
actual = set()
for line in sys.stdin:
    if not line.startswith("|"):
        continue
    for owner, repo in re.findall(r"https://github[.]com/([^/| )]+)/([^/| )]+)", line):
        actual.add(f"{owner}/{repo}")
raise SystemExit(0 if actual == expected and bool(expected) else 1)
'
}

check_counter_evidence() {
  body=$(section 6) || return 1
  printf '%s\n' "$body" | grep -Eqi 'public[[:space:]-]+issue|issue.*public' \
    && printf '%s\n' "$body" | grep -Eqi 'public.*evidence|evidence.*public'
}

check_output_schema() {
  body=$(section 7) || return 1
  for field in claim state evidence confidence unresolved; do
    printf '%s\n' "$body" | grep -Eqi "^[[:space:]]*$field[[:space:]]*:" || return 1
  done
  printf '%s\n' "$body" | grep -Eqi 'stop[[:space:]-]+rule' \
    && printf '%s\n' "$body" | grep -Eqi 'inferen' \
    && printf '%s\n' "$body" | grep -Fqi 'unresolved'
}

check_handoff() {
  body=$(section 8) || return 1
  printf '%s\n' "$body" | grep -Eq '^>[[:space:]]+' \
    && printf '%s\n' "$body" | grep -Fqi 'Fork the idea'
}

check_discovery_warning() {
  body=$(section 1) || return 1
  printf '%s\n' "$body" | grep -Fqi 'automatic discovery' \
    && printf '%s\n' "$body" | grep -Eqi 'not guaranteed|cannot guarantee|no guarantee'
}

run_check a01 'the root English entry artifact exists without localized siblings' 'the root English entry artifact is missing or has localized siblings' check_root_english_artifact
run_check a02 'the entry artifact has numbered sections 1 through 8' 'the entry artifact does not have exactly eight numbered sections' check_eight_sections
run_check a03 'the opening offers both time-budget tours' 'the opening is missing a required time-budget tour or visitor purpose' check_opening_tours
run_check a04 'the authority sources appear in the required order' 'the authority-source order is missing or changed' check_authority_order
run_check a05 'the four-axis state vocabulary is present' 'the state vocabulary is incomplete' check_state_vocabulary
run_check a06 'the four-part evaluation frame is present' 'the evaluation frame is incomplete' check_evaluation_frame
run_check a07 'the repository tour has role and verification columns' 'the repository tour table is missing or malformed' check_tour_table_shape
run_check a08 'tour rows exactly match published registry modules' 'tour rows do not exactly match published registry modules' check_published_rows
run_check a09 'the counter-evidence procedure is public-only' 'the public counter-evidence procedure is incomplete' check_counter_evidence
run_check a10 'the handoff schema and stop rule are present' 'the handoff schema or stop rule is incomplete' check_output_schema
run_check a11 'the human handoff template and invitation are present' 'the human handoff template or invitation is missing' check_handoff
run_check a12 'automatic discovery is explicitly not guaranteed' 'the automatic-discovery warning is missing' check_discovery_warning

[ "$failures" -eq 0 ]
