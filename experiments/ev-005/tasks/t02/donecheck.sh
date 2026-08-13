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

check_fixed "a01" "README.md" '| OS | macOS: ✅ tested (test suite runs on Apple-silicon macOS) ／ Linux: ⚠️ expected to work (POSIX, bash 3.2+, Python 3 stdlib) — not yet verified |' "English support matrix records tested macOS and expected Linux text"
check_fixed "a02" "README.md" '| Windows | ❌ not supported (not tested; WSL not tested) |' "English support matrix records Windows status"
check_fixed "a03" "README.ja.md" '| OS | macOS: ✅ テスト済み（Apple シリコン搭載 macOS でテストスイートを実行） ／ Linux: ⚠️ 動作見込み（POSIX、bash 3.2+、Python 3 標準ライブラリ）— 未検証 |' "Japanese support matrix records tested macOS and expected Linux text"
check_fixed "a04" "README.ja.md" '| Windows | ❌ 非対応（未テスト、WSL も未テスト） |' "Japanese support matrix records Windows status"
check_fixed "a05" "README.zh.md" '| 操作系统 | macOS：✅ 已测试（测试套件在 Apple 芯片 macOS 上运行） ／ Linux：⚠️ 预计可用（POSIX、bash 3.2+、Python 3 标准库）——尚未验证 |' "Chinese support matrix records tested macOS and expected Linux text"
check_fixed "a06" "README.zh.md" '| Windows | ❌ 不支持（未测试；WSL 未测试） |' "Chinese support matrix records Windows status"
check_fixed "a07" "README.th.md" '| ระบบปฏิบัติการ | macOS: ✅ ทดสอบแล้ว (รันชุดทดสอบบน macOS ที่ใช้ Apple silicon) ／ Linux: ⚠️ คาดว่าจะใช้งานได้ (POSIX, bash 3.2+, ไลบรารีมาตรฐานของ Python 3) — ยังไม่ได้ตรวจสอบ |' "Thai support matrix records tested macOS and expected Linux text"
check_fixed "a08" "README.th.md" '| Windows | ❌ ไม่รองรับ (ยังไม่ได้ทดสอบ และยังไม่ได้ทดสอบ WSL) |' "Thai support matrix records Windows status"

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

check_fixed "a21" "docs/agent-guide.md" "I'll remember where we were. Or ask me to run the bundled example at" "agent guide names the bundled example"
check_fixed "a22" "docs/agent-guide.md" 'templates/examples/img-pilot.task.md.' "agent guide points to the concrete bundled demo task"
check_fixed "a23" "docs/agent-guide.md" 'scripts/loop-init --workspace "$WORKSPACE"' "agent guide starts the demo walkthrough at workspace initialization"
check_fixed "a24" "docs/agent-guide.md" 'scripts/tr-enqueue templates/examples/img-pilot.task.md "$WORKSPACE"' "agent guide enqueues the bundled demo task"
check_fixed "a25" "docs/agent-guide.md" 'TR_SPAWN_STEP="$STEP_PROVIDER" scripts/task-runner.sh "$WORKSPACE"' "agent guide runs the bundled demo end to end"

exit "$status"
