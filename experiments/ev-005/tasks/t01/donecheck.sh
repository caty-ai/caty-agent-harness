#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

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

check_cmd_if_clean() {
  local id="$1"
  local reason="$2"
  shift 2
  if [ "$status" -ne 0 ]; then
    echo "CHECK $id FAIL earlier required assertions failed; command not run"
    return
  fi
  check_cmd "$id" "$reason" "$@"
}

check_fixed "a01" "docs/engineering.md" 'The Claude Code `Stop` and `PreCompact` hooks above are producers only' "engineering doc says the hook outputs are producers only"
check_fixed "a02" "docs/engineering.md" 'must also schedule the consumer, `adapters/claude-code/flush-intake.sh`' "engineering doc says the consumer must be scheduled"
check_fixed "a03" "docs/engineering.md" 'Run the consumer two to four times per day' "engineering doc records the schedule window"
check_fixed "a04" "docs/engineering.md" 'LaunchAgent in the `gui/<uid>` domain remains the recommended scheduler surface' "engineering doc records the LaunchAgent scheduler surface"
check_fixed "a05" "docs/engineering.md" 'The consumer touches `loop/.deadman/distill.marker` itself' "engineering doc records the self-marking caveat"
check_fixed "a06" "docs/engineering.md" 'See [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) for the full setup steps, ledger format, and scheduling detail.' "engineering doc points to the normative setup procedure"

check_fixed "a07" "docs/reference.md" "The flush intake consumer's accounting ledger is \`loop/pending/intake-runs.log\`." "reference doc names the intake ledger"
check_fixed "a08" "docs/reference.md" '`loop/archive/` is append-only and is never auto-pruned.' "reference doc states the archive semantics"
check_fixed "a09" "docs/reference.md" 'See [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) for the full ledger format and scheduling.' "reference doc points to the normative setup procedure"

check_fixed "a10" "docs/engineering.ja.md" '`Stop` / `PreCompact` hook は producer に過ぎません。' "Japanese engineering doc says the hook outputs are producers only"
check_fixed "a11" "docs/engineering.ja.md" 'consumer である `adapters/claude-code/flush-intake.sh` の定期実行も必ず設定してください。' "Japanese engineering doc says the consumer must be scheduled"
check_fixed "a12" "docs/engineering.ja.md" '`StartInterval` を `21600`〜`43200` 秒にします。' "Japanese engineering doc records the schedule window"
check_fixed "a13" "docs/engineering.ja.md" '`gui/<uid>` domain の LaunchAgent を推奨します。' "Japanese engineering doc records the LaunchAgent scheduler surface"
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

check_cmd_if_clean "a25" "full repository test suite passes" make test

exit "$status"
