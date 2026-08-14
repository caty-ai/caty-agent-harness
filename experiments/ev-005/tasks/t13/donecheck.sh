#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
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

family_section() {
  path=$1
  [ -f "$path" ] || return 1
  sed -n '/^<a id="family-os"><\/a>$/,/^<a id="acknowledgments"><\/a>$/p' "$path"
}

check_section_fragments() {
  path=$1
  shift
  section=$(family_section "$path") || return 1
  [ -n "$section" ] || return 1
  for needle in "$@"; do
    printf '%s\n' "$section" | grep -Fq -- "$needle" || return 1
  done
}

check_no_section_table() {
  path=$1
  section=$(family_section "$path") || return 1
  [ -n "$section" ] || return 1
  ! printf '%s\n' "$section" | grep -Eq '^[[:space:]]*\|'
}

check_footer_hash() {
  path=$1
  expected=$2
  [ -f "$path" ] || return 1
  python3 - "$path" "$expected" <<'PY'
import hashlib
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
try:
    data = path.read_bytes()
except OSError:
    raise SystemExit(1)
start = b"<!-- family:generated:family-footer:start -->"
end = b"<!-- family:generated:family-footer:end -->"
if data.count(start) != 1 or data.count(end) != 1:
    raise SystemExit(1)
begin = data.index(start)
finish = data.index(end, begin) + len(end)
actual = hashlib.sha256(data[begin:finish]).hexdigest()
raise SystemExit(0 if actual == expected else 1)
PY
}

check_single_module_table() {
  path=$1
  header=$2
  [ -f "$path" ] || return 1
  [ "$(grep -Fc -- "$header" "$path" 2>/dev/null)" = "1" ]
}

run_check "a01" "English family-section prose remains" "English family-section prose is missing" \
  check_section_fragments "README.md" \
  "github.com/caty-ai/family-os" "works on its own" \
  "github.com/caty-ai/family-dev-handbook" "our thanks to the foundations"
run_check "a02" "Japanese family-section prose remains" "Japanese family-section prose is missing" \
  check_section_fragments "README.ja.md" \
  "github.com/caty-ai/family-os" "単独でそのまま使えます" \
  "github.com/caty-ai/family-dev-handbook" "土台へのお礼"
run_check "a03" "Chinese family-section prose remains" "Chinese family-section prose is missing" \
  check_section_fragments "README.zh.md" \
  "github.com/caty-ai/family-os" "可以单独使用" \
  "github.com/caty-ai/family-dev-handbook" "基础致谢"
run_check "a04" "Thai family-section prose remains" "Thai family-section prose is missing" \
  check_section_fragments "README.th.md" \
  "github.com/caty-ai/family-os" "ใช้งานเดี่ยวๆ ได้เลย" \
  "github.com/caty-ai/family-dev-handbook" "ขอขอบคุณรากฐาน"

run_check "a05" "English authority note remains" "English authority note is missing" \
  check_section_fragments "README.md" \
  "connecting never moves authority" "FMA shares information" "does not drive other agents"
run_check "a06" "Japanese authority note remains" "Japanese authority note is missing" \
  check_section_fragments "README.ja.md" \
  "実行の権限は移りません" "FMA は情報を共有するだけ" "他のエージェントを動かしません"
run_check "a07" "Chinese authority note remains" "Chinese authority note is missing" \
  check_section_fragments "README.zh.md" \
  "连接不会转移执行权限" "FMA 只共享信息" "不驱动其他 Agent"
run_check "a08" "Thai authority note remains" "Thai authority note is missing" \
  check_section_fragments "README.th.md" \
  "ไม่ได้ย้ายอำนาจการทำงาน" "FMA แค่แชร์ข้อมูล" "ไม่ได้สั่งการ agent ตัวอื่น"

run_check "a09" "English hand-written module table is absent" "English hand-written family section still has a table" check_no_section_table "README.md"
run_check "a10" "Japanese hand-written module table is absent" "Japanese hand-written family section still has a table" check_no_section_table "README.ja.md"
run_check "a11" "Chinese hand-written module table is absent" "Chinese hand-written family section still has a table" check_no_section_table "README.zh.md"
run_check "a12" "Thai hand-written module table is absent" "Thai hand-written family section still has a table" check_no_section_table "README.th.md"

run_check "a13" "English generated footer is unchanged" "English generated footer changed" check_footer_hash "README.md" "a7a5330cf7e192070307bdebdcc2c4c4f1ce17423e7893b004f712ffac94d049"
run_check "a14" "Japanese generated footer is unchanged" "Japanese generated footer changed" check_footer_hash "README.ja.md" "9ac40ae515ca22547c97c2b39f18f1cfd13e3988ae1212cd881e0dd03236e2a7"
run_check "a15" "Chinese generated footer is unchanged" "Chinese generated footer changed" check_footer_hash "README.zh.md" "1c59fdb8049186ffd31b701faad6d90b4ac572dff5bca41cf08777e756fe05af"
run_check "a16" "Thai generated footer is unchanged" "Thai generated footer changed" check_footer_hash "README.th.md" "b295d844d220a4c0e97966b8861c09ca8365b8a6f30eac3ec8423d95ba150972"

run_check "a17" "English README has one family module table" "English README does not have exactly one family module table" check_single_module_table "README.md" "| Axis | Module |"
run_check "a18" "Japanese README has one family module table" "Japanese README does not have exactly one family module table" check_single_module_table "README.ja.md" "| 軸 | モジュール |"
run_check "a19" "Chinese README has one family module table" "Chinese README does not have exactly one family module table" check_single_module_table "README.zh.md" "| 轴 | 模块 |"
run_check "a20" "Thai README has one family module table" "Thai README does not have exactly one family module table" check_single_module_table "README.th.md" "| แกน | โมดูล |"

[ "$failures" -eq 0 ]
