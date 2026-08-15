#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t01-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

check_fixed() {
  local id="$1"
  local file="$2"
  local needle="$3"
  local reason="$4"
  if [ ! -f "$file" ]; then
    echo "CHECK $id FAIL missing $file"
    status=1
    return
  fi
  if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_cmd() {
  local id="$1"
  local reason="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_fixed "a01" "docs/engineering.md" 'producers only' "engineering doc says the hook outputs are producers only"
check_fixed "a02" "docs/engineering.md" 'must also schedule the consumer, `adapters/claude-code/flush-intake.sh`' "engineering doc says the consumer must be scheduled"
check_fixed "a03" "docs/engineering.md" 'two to four times per day' "engineering doc records the schedule window"
check_fixed "a04" "docs/engineering.md" 'LaunchAgent in the `gui/<uid>` domain' "engineering doc records the LaunchAgent scheduler surface"
check_fixed "a05" "docs/engineering.md" 'touches `loop/.deadman/distill.marker`' "engineering doc records the self-marking caveat"
check_fixed "a06" "docs/engineering.md" 'INSTALL.md](../adapters/claude-code/INSTALL.md) for the full setup steps' "engineering doc points to the normative setup procedure"

check_fixed "a07" "docs/reference.md" '`loop/pending/intake-runs.log`' "reference doc names the intake ledger"
check_fixed "a08" "docs/reference.md" 'append-only' "reference doc states the archive semantics"
check_fixed "a09" "docs/reference.md" 'INSTALL.md](../adapters/claude-code/INSTALL.md) for the full ledger format' "reference doc points to the normative setup procedure"

check_fixed "a10" "docs/engineering.ja.md" 'producer に過ぎません' "Japanese engineering doc says the hook outputs are producers only"
check_fixed "a11" "docs/engineering.ja.md" '`adapters/claude-code/flush-intake.sh` の定期実行' "Japanese engineering doc says the consumer must be scheduled"
check_fixed "a12" "docs/engineering.ja.md" '`21600`〜`43200`' "Japanese engineering doc records the schedule window"
check_fixed "a13" "docs/engineering.ja.md" '`gui/<uid>` domain の LaunchAgent' "Japanese engineering doc records the LaunchAgent scheduler surface"
check_fixed "a14" "docs/engineering.ja.md" '`loop/.deadman/distill.marker` を touch します' "Japanese engineering doc records the self-marking caveat"
check_fixed "a15" "docs/engineering.ja.md" '[adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md)' "Japanese engineering doc points to the normative setup procedure"

check_fixed "a16" "docs/reference.ja.md" '`loop/pending/intake-runs.log`' "Japanese reference doc names the intake ledger"
check_fixed "a17" "docs/reference.ja.md" '`loop/archive/` は append-only' "Japanese reference doc states the archive semantics"
check_fixed "a18" "docs/reference.ja.md" '[adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md)' "Japanese reference doc points to the normative setup procedure"

check_fixed "a19" "adapters/claude-code/INSTALL.md" 'must also schedule `adapters/claude-code/flush-intake.sh`' "source install doc states the consumer requirement"
check_fixed "a20" "adapters/claude-code/INSTALL.md" 'Run the consumer two to four times per day.' "source install doc states the schedule window"
check_fixed "a21" "adapters/claude-code/INSTALL.md" 'LaunchAgent remains the recommended macOS scheduler surface.' "source install doc states the LaunchAgent guidance"
check_fixed "a22" "adapters/claude-code/INSTALL.md" 'The consumer itself touches `loop/.deadman/distill.marker`' "source install doc states the self-marking caveat"
check_fixed "a23" "adapters/claude-code/INSTALL.md" '`loop/pending/intake-runs.log` for content-level silence, dedup, deferral, eviction, and' "source install doc states the ledger claim"
check_fixed "a24" "adapters/claude-code/INSTALL.md" '`loop/archive/` is append-only,' "source install doc states the archive semantics"

check_cmd "a25" "full repository test suite passes" run_isolated make test

exit "$status"
