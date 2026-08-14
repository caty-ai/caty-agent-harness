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
  PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t20-probe.XXXXXX") || return 1
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

evidence_probe() {
  mode=$1
  python3 - "$mode" <<'PY'
import datetime as dt
import pathlib
import re
import sys

mode = sys.argv[1]
try:
    text = pathlib.Path("docs/evidence.md").read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)

row = re.compile(r"^\|(?P<field>[^|]+)\|(?P<value>[^|]+)\|$")
entries = []
current = None
for raw in text.splitlines():
    match = row.match(raw.strip())
    if not match:
        continue
    field = match.group("field").strip()
    value = match.group("value").strip()
    if field in {"field", "---"}:
        continue
    if field == "claim-id":
        if current is not None:
            entries.append(current)
        current = {field: value}
    elif current is not None:
        current[field] = value
if current is not None:
    entries.append(current)

required = {
    "claim-id",
    "believe",
    "built",
    "actually happened",
    "still don't know",
    "state (delivery · visibility · evidence)",
    "evidence",
    "observed-at",
    "last-reviewed",
    "owner",
    "counter-evidence",
}

if mode == "schema":
    if len(entries) < 4:
        raise SystemExit(1)
    ids = []
    for entry in entries:
        if required.difference(entry):
            raise SystemExit(1)
        if any(not entry[field].strip() for field in required):
            raise SystemExit(1)
        claim_id = entry["claim-id"]
        if not re.fullmatch(r"[A-Z][A-Z0-9_-]*-[0-9]{3,}", claim_id):
            raise SystemExit(1)
        ids.append(claim_id)
        if len([part for part in entry["state (delivery · visibility · evidence)"].split("·") if part.strip()]) != 3:
            raise SystemExit(1)
        for field in ("observed-at", "last-reviewed"):
            try:
                dt.date.fromisoformat(entry[field])
            except ValueError:
                raise SystemExit(1)
        if "http://" not in entry["evidence"] and "https://" not in entry["evidence"]:
            raise SystemExit(1)
    if len(ids) != len(set(ids)):
        raise SystemExit(1)
    raise SystemExit(0)

blobs = [" ".join(entry.values()).lower() for entry in entries]
if mode == "silent":
    ok = any("silent" in blob and ("fix" in blob or "recover" in blob or "closed" in blob) for blob in blobs)
elif mode == "gate":
    ok = any("gate" in blob and ("deliberate" in blob or "mutation" in blob) and ("fail" in blob or " red" in blob) for blob in blobs)
elif mode == "weekly":
    ok = any(("weekly" in blob or "scheduled" in blob) and "run" in blob and "pass" in blob for blob in blobs)
elif mode == "growth":
    sections = re.split(r"(?m)^##[ ]+", text.lower())
    ok = any(
        all(token in section for token in ("propose", "trial", "council", "owner", "adopt"))
        and ("unverified" in section or "primary:" in section)
        for section in sections
    )
else:
    raise SystemExit(2)
raise SystemExit(0 if ok else 1)
PY
}

check_expiry_statement() {
  [ -f docs/evidence.md ] || return 1
  matching=$(grep -Ei 'last-reviewed' docs/evidence.md 2>/dev/null) || return 1
  printf '%s\n' "$matching" | grep -Fq '90 days' \
    && printf '%s\n' "$matching" | grep -Eiq 'unknown|reverif'
}

check_freshness_workflow() {
  python3 - <<'PY'
import pathlib
import re

try:
    text = pathlib.Path(".github/workflows/family-links.yml").read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)

if not re.search(r"(?m)^\s*schedule:\s*$", text):
    raise SystemExit(1)
if "docs/evidence.md" not in text or "last-reviewed" not in text:
    raise SystemExit(1)
if not re.search(r"age[^\n]*>\s*90|>\s*90[^\n]*age", text, re.IGNORECASE):
    raise SystemExit(1)
if not re.search(r"SystemExit\(1\)|exit\s+1", text):
    raise SystemExit(1)
if not re.search(r"required_fields|required[^\n]*claim-id", text):
    raise SystemExit(1)
PY
}

check_fail_closed_contract() {
  python3 - <<'PY'
import pathlib
import re

try:
    evidence = pathlib.Path("docs/evidence.md").read_text(encoding="utf-8")
    workflow = pathlib.Path(".github/workflows/family-links.yml").read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)

statement = next((line for line in evidence.splitlines() if "last-reviewed" in line and "90 days" in line), "")
if not re.search(r"unknown|reverif", statement, re.IGNORECASE):
    raise SystemExit(1)
if not re.search(r"stale\s*=|stale\.append|age[^\n]*>\s*90", workflow, re.IGNORECASE):
    raise SystemExit(1)
if not re.search(r"SystemExit\(1\)|exit\s+1", workflow):
    raise SystemExit(1)
if re.search(r"write_text\([^\n]*evidence\.md|open\([^\n]*evidence\.md[^\n]*['\"]w", workflow):
    raise SystemExit(1)
PY
}

run_check a01 'the evidence register exists' \
  'docs/evidence.md is missing' test -f docs/evidence.md
run_check a02 'every claim has the required complete schema' \
  'claim schema, stable ids, dates, states, or links are incomplete' evidence_probe schema
run_check a03 'the initial register covers silent-failure discovery and repair' \
  'the silent-failure evidence entry is missing' evidence_probe silent
run_check a04 'the initial register covers a deliberately broken gate' \
  'the red/green gate evidence entry is missing' evidence_probe gate
run_check a05 'the initial register covers an observed weekly run' \
  'the weekly reality-check evidence entry is missing' evidence_probe weekly
run_check a06 'the governed growth sequence is recorded without overstating evidence' \
  'the growth-cycle entry or its honest evidence state is missing' evidence_probe growth
run_check a07 'the register states the 90-day unknown rule' \
  'the 90-day expiry rule is missing' check_expiry_statement
run_check a08 'the weekly workflow enforces evidence freshness' \
  'the scheduled freshness job lacks schema or age enforcement' check_freshness_workflow
run_check a09 'stale evidence fails closed without workflow edits to the register' \
  'stale evidence does not fail closed or automation rewrites the register' check_fail_closed_contract

[ "$failures" -eq 0 ]
