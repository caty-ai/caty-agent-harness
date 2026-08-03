#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
METRICS="$ROOT/scripts/tr-metrics.sh"

pass_count=0
fail_count=0
temps=()

log() {
  printf '%s\n' "$*"
}

pass() {
  pass_count=$(( pass_count + 1 ))
  log "PASS $1"
}

fail() {
  fail_count=$(( fail_count + 1 ))
  log "FAIL $1: $2"
}

cleanup() {
  local dir
  set +u
  for dir in "${temps[@]}"; do
    rm -rf "$dir"
  done
  set -u
}
trap cleanup EXIT

make_ws() {
  local ws
  ws=$(mktemp -d "${TMPDIR:-/tmp}/tr-metrics-test.XXXXXX")
  mkdir -p "$ws/loop/tasks"
  printf '%s\n' "$ws"
}

write_task() {
  local ws=$1
  local status=$2
  local id=$3
  local parent=$4
  local parent_line='parent_id: null'
  if [[ -n "$parent" ]]; then
    parent_line="parent_id: $parent"
  fi
  mkdir -p "$ws/loop/tasks/$status/$id"
  cat >"$ws/loop/tasks/$status/$id/$id.task.md" <<EOF
---
id: $id
$parent_line
---
EOF
}

case_three_generation_chain() {
  local ws
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" delivered a-001 ''
  write_task "$ws" delivered a-002 a-001
  write_task "$ws" delivered a-003 a-002
  if "$METRICS" "$ws" && grep -Fqx '| a-003 | delivered | a-001 -> a-002 -> a-003 |' "$ws/METRICS.md"; then
    pass three-generation-chain
  else
    fail three-generation-chain "expected full root-first chain for a-003"
  fi
}

case_two_generation_chain() {
  local ws
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" delivered b-001 ''
  write_task "$ws" dlq b-002 b-001
  if "$METRICS" "$ws" && grep -Fqx '| b-002 | dlq | b-001 -> b-002 |' "$ws/METRICS.md"; then
    pass two-generation-chain
  else
    fail two-generation-chain "expected parent-child chain for b-002"
  fi
}

case_cycle_terminates() {
  local ws code
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" delivered c-001 c-002
  write_task "$ws" delivered c-002 c-001
  set +e
  "$METRICS" "$ws" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 && -f "$ws/METRICS.md" ]] \
    && grep -Fqx '| c-001 | delivered | c-002 -> c-001 |' "$ws/METRICS.md" \
    && grep -Fqx '| c-002 | delivered | c-001 -> c-002 |' "$ws/METRICS.md"; then
    pass cycle-terminates
  else
    fail cycle-terminates "expected exit 0 and both cycle chains, got exit $code"
  fi
}

case_self_referential_parent() {
  local ws code
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" delivered self-001 self-001
  set +e
  "$METRICS" "$ws" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 && -f "$ws/METRICS.md" ]] \
    && grep -Fqx '| self-001 | delivered | self-001 |' "$ws/METRICS.md"; then
    pass self-referential-parent
  else
    fail self-referential-parent "expected exit 0 and a single-task chain, got exit $code"
  fi
}

case_missing_grandparent() {
  local ws
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" delivered mid-002 root-missing
  write_task "$ws" dlq leaf-003 mid-002
  if "$METRICS" "$ws" \
    && grep -Fqx '| leaf-003 | dlq | root-missing -> mid-002 -> leaf-003 |' "$ws/METRICS.md"; then
    pass missing-grandparent
  else
    fail missing-grandparent "expected root-first chain through absent grandparent for leaf-003"
  fi
}

case_unknown_parent_exits() {
  local ws code
  ws=$(make_ws)
  temps+=("$ws")
  write_task "$ws" dlq d-001 missing-parent
  set +e
  "$METRICS" "$ws" >/dev/null 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 && -f "$ws/METRICS.md" ]] && grep -Fqx '| d-001 | dlq | missing-parent -> d-001 |' "$ws/METRICS.md"; then
    pass unknown-parent-exits
  else
    fail unknown-parent-exits "expected exit 0 and named missing parent in chain, got exit $code"
  fi
}

case_three_generation_chain
case_two_generation_chain
case_cycle_terminates
case_self_referential_parent
case_missing_grandparent
case_unknown_parent_exits

log "TOTAL pass=$pass_count fail=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
