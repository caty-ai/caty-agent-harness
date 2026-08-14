#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE_ROOT=''

cleanup_probe_root() {
  [ -z "$PROBE_ROOT" ] || rm -rf "$PROBE_ROOT"
  PROBE_ROOT=''
}
trap cleanup_probe_root EXIT HUP INT TERM

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  shift 3
  if run_isolated "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_isolated() {
  local probe_home probe_tmp rc
  PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t18-probe.XXXXXX") || return 1
  probe_home="$PROBE_ROOT/home"
  probe_tmp="$PROBE_ROOT/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    cleanup_probe_root
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@" >/dev/null 2>&1
  rc=$?
  cleanup_probe_root
  return "$rc"
}

check_registry_field() {
  field=$1
  expected_json=$2
  python3 - "$field" "$expected_json" <<'PY'
import json
import pathlib
import sys

try:
    registry = json.loads(pathlib.Path("registry/modules.json").read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
entries = [item for item in registry.get("modules", []) if item.get("id") == "context-kit"]
if len(entries) != 1:
    raise SystemExit(1)
field = sys.argv[1].split(".")
value = entries[0]
for part in field:
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(1)
    value = value[part]
expected = json.loads(sys.argv[2])
raise SystemExit(0 if value == expected else 1)
PY
}

check_readme_table() {
  python3 - "$1" <<'PY'
import pathlib
import sys

try:
    lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)
vertical_anchor = "github.com/caty-ai/caty-agent-harness"
rows = [
    line
    for line in lines
    if line.lstrip().startswith("|")
    and vertical_anchor in line
    and "context-kit" in line
]
raise SystemExit(0 if len(rows) == 1 else 1)
PY
}

check_readme_equipment() {
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

try:
    lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

vertical_anchor = "github.com/caty-ai/caty-agent-harness"
headings = []
for index, line in enumerate(lines):
    match = re.match(r"^(#{1,6})[ ]+", line)
    if match:
        headings.append((index, len(match.group(1))))

for heading_index, level in headings:
    end = len(lines)
    for next_index, next_level in headings:
        if next_index > heading_index and next_level <= level:
            end = next_index
            break
    section = lines[heading_index + 1:end]
    if not any(vertical_anchor in line for line in section):
        continue
    for index, line in enumerate(section):
        stripped = line.strip()
        if not stripped.startswith("-") or "context-kit" not in stripped:
            continue
        prior = [candidate.strip() for candidate in section[max(0, index - 4):index] if candidate.strip()]
        if prior and prior[-1].startswith("**") and prior[-1].endswith("**"):
            raise SystemExit(0)
raise SystemExit(1)
PY
}

run_check a01 'the registry has one context-kit entry' \
  'the registry lacks a unique context-kit entry' check_registry_field id '"context-kit"'
run_check a02 'context-kit is on the vertical axis' \
  'context-kit is not on the vertical axis' check_registry_field axis.group '"vertical"'
run_check a03 'context-kit is not a foundation module' \
  'context-kit has the wrong foundation flag' check_registry_field axis.foundation 'false'
run_check a04 'context-kit remains preparing before the public flip' \
  'context-kit has the wrong pre-flip status' check_registry_field status '"preparing"'
run_check a05 'generated blocks are current' \
  'generated blocks are stale' python3 -B tools/render.py --check
run_check a06 'registry validation passes offline' \
  'offline registry validation fails' python3 -B tools/check_registry.py --offline

run_check a07 'English vertical table row mentions context-kit' \
  'English vertical table row omits context-kit' check_readme_table README.md
run_check a08 'Japanese vertical table row mentions context-kit' \
  'Japanese vertical table row omits context-kit' check_readme_table README.ja.md
run_check a09 'Chinese vertical table row mentions context-kit' \
  'Chinese vertical table row omits context-kit' check_readme_table README.zh.md
run_check a10 'Thai vertical table row mentions context-kit' \
  'Thai vertical table row omits context-kit' check_readme_table README.th.md

run_check a11 'English equipment category has a context-kit bullet' \
  'English equipment category lacks a context-kit bullet' check_readme_equipment README.md
run_check a12 'Japanese equipment category has a context-kit bullet' \
  'Japanese equipment category lacks a context-kit bullet' check_readme_equipment README.ja.md
run_check a13 'Chinese equipment category has a context-kit bullet' \
  'Chinese equipment category lacks a context-kit bullet' check_readme_equipment README.zh.md
run_check a14 'Thai equipment category has a context-kit bullet' \
  'Thai equipment category lacks a context-kit bullet' check_readme_equipment README.th.md

[ "$failures" -eq 0 ]
