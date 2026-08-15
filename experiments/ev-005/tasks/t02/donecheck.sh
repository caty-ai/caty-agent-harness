#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

status=0

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t02-probe.XXXXXX") || return 1
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
  if visible_content "$file" | grep -F -- "$needle" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_pair() {
  local id="$1"
  local file="$2"
  local needle_a="$3"
  local needle_b="$4"
  local reason="$5"
  if [ ! -f "$file" ]; then
    echo "CHECK $id FAIL missing $file"
    status=1
    return
  fi
  if visible_content "$file" | grep -F -- "$needle_a" >/dev/null 2>&1 \
    && visible_content "$file" | grep -F -- "$needle_b" >/dev/null 2>&1; then
    echo "CHECK $id PASS $reason"
  else
    echo "CHECK $id FAIL $reason"
    status=1
  fi
}

check_pair "a01" "README.md" 'macOS: ✅ tested' 'Linux: ⚠️ expected to work' "English support matrix records tested macOS and expected Linux text"
check_pair "a02" "README.md" '| Windows | ❌ not supported' 'WSL' "English support matrix records Windows status"
check_pair "a03" "README.ja.md" 'macOS: ✅ テスト済み' 'Linux: ⚠️ 動作見込み' "Japanese support matrix records tested macOS and expected Linux text"
check_pair "a04" "README.ja.md" '| Windows | ❌ 非対応' 'WSL' "Japanese support matrix records Windows status"
check_pair "a05" "README.zh.md" 'macOS：✅ 已测试' 'Linux：⚠️ 预计可用' "Chinese support matrix records tested macOS and expected Linux text"
check_pair "a06" "README.zh.md" '| Windows | ❌ 不支持' 'WSL' "Chinese support matrix records Windows status"
check_pair "a07" "README.th.md" 'macOS: ✅ ทดสอบแล้ว' 'Linux: ⚠️ คาดว่าจะใช้งานได้' "Thai support matrix records tested macOS and expected Linux text"
check_pair "a08" "README.th.md" '| Windows | ❌ ไม่รองรับ' 'WSL' "Thai support matrix records Windows status"

check_fixed "a09" "README.md" '![runtime: bash 3.2+]' "English runtime badge alt carries payload"
check_fixed "a10" "README.md" '![platform: macOS | Linux]' "English platform badge alt carries payload"
check_fixed "a11" "README.md" '![status: public preview]' "English status badge alt carries payload"
check_fixed "a12" "README.ja.md" '![runtime: bash 3.2+]' "Japanese runtime badge alt carries payload"
check_fixed "a13" "README.ja.md" '![platform: macOS | Linux]' "Japanese platform badge alt carries payload"
check_fixed "a14" "README.ja.md" '![status: public preview]' "Japanese status badge alt carries payload"
check_fixed "a15" "README.zh.md" '![runtime: bash 3.2+]' "Chinese runtime badge alt carries payload"
check_fixed "a16" "README.zh.md" '![platform: macOS | Linux]' "Chinese platform badge alt carries payload"
check_fixed "a17" "README.zh.md" '![status: public preview]' "Chinese status badge alt carries payload"
check_fixed "a18" "README.th.md" '![runtime: bash 3.2+]' "Thai runtime badge alt carries payload"
check_fixed "a19" "README.th.md" '![platform: macOS | Linux]' "Thai platform badge alt carries payload"
check_fixed "a20" "README.th.md" '![status: public preview]' "Thai status badge alt carries payload"

check_fixed "a21" "docs/agent-guide.md" "run the bundled example" "agent guide names the bundled example"
check_fixed "a22" "docs/agent-guide.md" 'templates/examples/img-pilot.task.md.' "agent guide points to the concrete bundled demo task"
check_fixed "a23" "docs/agent-guide.md" 'scripts/loop-init --workspace "$WORKSPACE"' "agent guide starts the demo walkthrough at workspace initialization"
check_fixed "a24" "docs/agent-guide.md" 'scripts/tr-enqueue templates/examples/img-pilot.task.md "$WORKSPACE"' "agent guide enqueues the bundled demo task"
check_fixed "a25" "docs/agent-guide.md" 'TR_SPAWN_STEP="$STEP_PROVIDER" scripts/task-runner.sh "$WORKSPACE"' "agent guide runs the bundled demo end to end"

exit "$status"
