#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RECOMPUTE="$ROOT/docs/benchmark/recompute.py"
AGGREGATE="$ROOT/docs/benchmark/ev006-aggregate.json"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-evidence-test.XXXXXX")

log() {
  printf '%s\n' "$*"
}

pass() {
  PASS_COUNT=$(( PASS_COUNT + 1 ))
  log "PASS $1"
}

fail_case() {
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  log "FAIL $1: $2"
}

skip_case() {
  SKIP_COUNT=$(( SKIP_COUNT + 1 ))
  log "SKIP $1: $2"
}

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

print_summary() {
  log "Summary: $PASS_COUNT PASS, $FAIL_COUNT FAIL, $SKIP_COUNT SKIP"
}

if ! command -v python3 >/dev/null 2>&1; then
  reason='python3 is unavailable; benchmark evidence cannot be recomputed or verified'
  skip_case 'recompute script exits successfully' "$reason"
  skip_case 'English benchmark block matches recomputed stdout' "$reason"
  skip_case 'Japanese benchmark block matches recomputed stdout' "$reason"
  skip_case 'aggregate sha256 matches the digest pinned in recompute.py' "$reason"
  print_summary
  exit 0
fi

stdout_file="$TMP/recompute.stdout"
stderr_file="$TMP/recompute.stderr"
recompute_ok=0
if python3 "$RECOMPUTE" >"$stdout_file" 2>"$stderr_file"; then
  pass 'recompute script exits successfully'
  recompute_ok=1
else
  rc=$?
  fail_case 'recompute script exits successfully' \
    "exit=$rc stderr=$(cat "$stderr_file"); restore the sealed aggregate, then run python3 docs/benchmark/recompute.py and paste its stdout into both text blocks"
fi

assert_stdout_block() {
  local name=$1
  local document=$2
  local compare_stderr="$TMP/$(basename "$document").stderr"

  if [[ "$recompute_ok" -ne 1 ]]; then
    fail_case "$name" \
      'verified stdout is unavailable; restore the sealed aggregate, then run python3 docs/benchmark/recompute.py and paste its stdout into this text block'
    return
  fi

  if python3 - "$stdout_file" "$document" 2>"$compare_stderr" <<'PY'
import sys
from pathlib import Path

stdout = Path(sys.argv[1]).read_bytes()
document = Path(sys.argv[2]).read_bytes()
fenced_stdout = b"```text\n" + stdout + b"```"
sys.exit(0 if fenced_stdout in document else 1)
PY
  then
    pass "$name"
  else
    diagnostic=$(cat "$compare_stderr")
    fail_case "$name" \
      "stdout is not the exact fenced block${diagnostic:+; $diagnostic}; run python3 docs/benchmark/recompute.py and paste its stdout into this text block"
  fi
}

assert_stdout_block \
  'English benchmark block matches recomputed stdout' \
  "$ROOT/docs/benchmark.md"
assert_stdout_block \
  'Japanese benchmark block matches recomputed stdout' \
  "$ROOT/docs/benchmark.ja.md"

digest_stderr="$TMP/digest.stderr"
if digest_pair=$(python3 - "$RECOMPUTE" "$AGGREGATE" 2>"$digest_stderr" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_bytes()
matches = re.findall(
    rb'^EXPECTED_SHA256[ \t]*=[ \t]*"([0-9a-f]{64})"[ \t]*$',
    script,
    re.MULTILINE,
)
if len(matches) != 1:
    raise SystemExit("expected exactly one literal EXPECTED_SHA256 assignment")

actual = hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
print(matches[0].decode("ascii"), actual)
PY
); then
  read -r expected_digest actual_digest <<<"$digest_pair"
  if [[ "$actual_digest" == "$expected_digest" ]]; then
    pass 'aggregate sha256 matches the digest pinned in recompute.py'
  else
    fail_case 'aggregate sha256 matches the digest pinned in recompute.py' \
      "expected=$expected_digest actual=$actual_digest; restore the sealed aggregate, then run python3 docs/benchmark/recompute.py and paste its stdout into both text blocks"
  fi
else
  fail_case 'aggregate sha256 matches the digest pinned in recompute.py' \
    "$(cat "$digest_stderr"); keep one literal EXPECTED_SHA256 assignment in recompute.py, restore the sealed aggregate, then run the script and paste its stdout into both text blocks"
fi

print_summary
[[ "$FAIL_COUNT" -eq 0 ]]
