#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

check_cmd() {
  id=$1
  reason=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_cmd "a01" "English README has the generated family table near the bottom" \
  python3 .ev005-fixtures/family_table_probe.py placement README.md
check_cmd "a02" "Japanese README has the generated family table near the bottom" \
  python3 .ev005-fixtures/family_table_probe.py placement README.ja.md
check_cmd "a03" "Chinese README has the generated family table near the bottom" \
  python3 .ev005-fixtures/family_table_probe.py placement README.zh.md
check_cmd "a04" "Thai README has the generated family table near the bottom" \
  python3 .ev005-fixtures/family_table_probe.py placement README.th.md
check_cmd "a05" "all localized blocks match registry-backed existing-builder output" \
  python3 .ev005-fixtures/family_table_probe.py content
check_cmd "a06" "all generated map rows are bold and unlinked" \
  python3 .ev005-fixtures/family_table_probe.py map-row
check_cmd "a07" "render check rejects a stale generated family table" \
  python3 .ev005-fixtures/family_table_probe.py stale
check_cmd "a08" "rendered blocks are current" python3 tools/render.py --check
check_cmd "a09" "offline registry validation passes" python3 -B tools/check_registry.py --offline
check_cmd "a10" "member footer lint passes" python3 tools/family_footer.py lint
check_cmd "a11" "family footer self-test passes" python3 tools/selftest_family_footer.py
check_cmd "a12" "default member footer keeps linked-map and unlinked-host behavior" \
  python3 .ev005-fixtures/family_table_probe.py member-footer

exit "$status"
