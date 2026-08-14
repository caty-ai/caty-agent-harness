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

run_isolated() (
  local root canonical_root base requested_rc cleanup_rc
  root=""

  cleanup_isolated() {
    requested_rc=$1
    trap - EXIT HUP INT TERM
    cleanup_rc=0
    if [ -n "$root" ] && [ -d "$root" ]; then
      chmod -R u+rwx "$root" 2>/dev/null || true
      rm -rf -- "$root" || cleanup_rc=$?
    fi
    if [ "$requested_rc" -ne 0 ]; then
      exit "$requested_rc"
    fi
    exit "$cleanup_rc"
  }

  trap 'cleanup_isolated $?' EXIT
  trap 'cleanup_isolated 129' HUP
  trap 'cleanup_isolated 130' INT
  trap 'cleanup_isolated 143' TERM

  base=${TMPDIR:-/tmp}
  case "$base" in
    /) root=$(mktemp -d '/t22-probe.XXXXXX') || return 1 ;;
    *) root=$(mktemp -d "${base%/}/t22-probe.XXXXXX") || return 1 ;;
  esac
  canonical_root=$(cd "$root" && pwd -P) || return 1
  root=$canonical_root
  mkdir -p "$root/home" "$root/tmp" || return 1

  export HOME="$root/home"
  export TMPDIR="$root/tmp"
  "$@"
)

check_python_functions() {
  python3 -B - "$@" <<'PY'
import ast
import sys

path, *required = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    tree = ast.parse(handle.read(), filename=path)
present = {
    node.name
    for node in ast.walk(tree)
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
}
assert set(required).issubset(present)
PY
}

check_lg() {
  [ -x bin/lg ] || return 1
  [ -x tests/test_lg.sh ] || return 1
  run_isolated bash -n bin/lg || return 1
  run_isolated bash tests/test_lg.sh >/dev/null 2>&1
}

check_scratch_persistence() {
  [ -x hooks/scratch-persist.py ] || return 1
  [ -x tests/test_scratch_persist.sh ] || return 1
  run_isolated check_python_functions hooks/scratch-persist.py \
    extract_output resolve_scratch_dir main || return 1
  run_isolated bash tests/test_scratch_persist.sh >/dev/null 2>&1
}

check_brief_validator() {
  [ -x hooks/validate-subagent-brief.py ] || return 1
  [ -x tests/test_brief_validator.sh ] || return 1
  run_isolated check_python_functions hooks/validate-subagent-brief.py \
    required_sections_from_env render_skeleton main || return 1
  run_isolated bash tests/test_brief_validator.sh >/dev/null 2>&1
}

check_safety_hooks() {
  local path
  for path in \
    hooks/rm-enforcer.py \
    hooks/private-repo-enforcer.mjs \
    hooks/api-key-leak-detector.mjs \
    tests/test_safety_hooks.sh; do
    [ -x "$path" ] || return 1
  done
  run_isolated check_python_functions hooks/rm-enforcer.py \
    find_risk main || return 1
  run_isolated grep -Fq 'async function main()' \
    hooks/private-repo-enforcer.mjs || return 1
  run_isolated grep -Fq 'const API_KEY_PATTERNS' \
    hooks/api-key-leak-detector.mjs || return 1
  run_isolated grep -Fq 'async function main()' \
    hooks/api-key-leak-detector.mjs || return 1
  run_isolated bash tests/test_safety_hooks.sh >/dev/null 2>&1
}

check_recall() {
  [ -x bin/recall ] || return 1
  [ -x tests/test_recall.sh ] || return 1
  run_isolated run_recall_targeted >/dev/null 2>&1
}

run_recall_targeted() {
  local repo_root targeted
  repo_root=$(pwd -P) || return 1
  targeted="$TMPDIR/test_recall.targeted.sh"

  awk '
    index($0, "ROOT=$(cd ") == 1 {
      print "ROOT=${EV005_RECALL_ROOT:?}"
      root_replacements++
      next
    }
    $0 == "case_colon_path_survives_rg_and_grep_fallback" {
      excluded_invocations++
      next
    }
    { print }
    END {
      if (root_replacements != 1 || excluded_invocations != 1) {
        exit 1
      }
    }
  ' tests/test_recall.sh >"$targeted" || return 1

  EV005_RECALL_ROOT="$repo_root" bash "$targeted"
}

check_recall_relationship() {
  [ -f docs/recall.md ] || return 1
  grep -Eiq 'individual|single[ -]agent' docs/recall.md \
    && grep -Eiq 'shared|multi-agent' docs/recall.md \
    && grep -Eiq 'local-only|local only' docs/recall.md
}

check_no_personal_identifiers() {
  local pattern tracked file
  tracked=$(git ls-files -- . 2>/dev/null) || return 1
  for pattern in '/Users/' '/home/shojikumaru' 'shojikumaru' 'SharedHub' 'alpha-wiki' 'claude-workspace' 'personal-alpha'; do
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      case "$file" in
        .ev005-*) continue ;;
      esac
      [ -f "$file" ] || continue
      if grep -I -Fq -- "$pattern" "$file" 2>/dev/null; then
        return 1
      fi
    done <<EOF
$tracked
EOF
  done
}

check_setup_wiring() {
  [ -f README.md ] || return 1
  [ -f examples/settings.json ] || return 1
  grep -Fq 'examples/settings.json' README.md || return 1
  grep -Fq '<CONTEXT_KIT_DIR>' README.md || return 1
  grep -Fq 'tests/*.sh' README.md || return 1
  run_isolated python3 -B - examples/settings.json <<'PY'
import json, sys

text = open(sys.argv[1], encoding="utf-8").read().replace("<CONTEXT_KIT_DIR>", "/tmp/workspace-toolkit")
settings = json.loads(text)
hooks = settings.get("hooks", {})
assert isinstance(hooks.get("PreToolUse"), list) and hooks["PreToolUse"]
assert isinstance(hooks.get("PostToolUse"), list) and hooks["PostToolUse"]
PY
}

check_readme_structure() {
  local readme anchor
  for readme in README.md README.ja.md README.zh.md README.th.md; do
    [ -f "$readme" ] || return 1
    for anchor in pain what requirements install safety docs license; do
      grep -Fq "<a id=\"$anchor\"></a>" "$readme" || return 1
    done
  done
}

check_hero_asset() {
  [ -s assets/readme/hero.png ]
}

check_mit_license() {
  [ -f LICENSE ] || return 1
  grep -Fq 'MIT License' LICENSE
}

run_check a01 'lg is executable, syntactically valid, and passes its full functional suite' 'lg is missing, invalid, or fails its functional suite' check_lg
run_check a02 'scratch persistence is executable, structurally valid, and passes its full functional suite' 'scratch persistence is missing, invalid, or fails its functional suite' check_scratch_persistence
run_check a03 'brief validation is executable, structurally valid, and passes its full functional suite' 'brief validation is missing, invalid, or fails its functional suite' check_brief_validator
run_check a04 'the safety hooks are executable, structurally present, and pass their full functional suite' 'one or more safety hooks are missing, invalid, or fail their functional suite' check_safety_hooks
run_check a05 'recall is executable and passes the 19-case targeted bundled functional suite' 'recall or its 19-case targeted bundled functional suite is missing or failing' check_recall
run_check a06 'recall documents its individual/shared-memory relationship and local-only use' 'recall does not document its individual/shared-memory relationship and local-only use' check_recall_relationship
run_check a07 'tracked text contains no literal personal-environment identifiers' 'tracked text contains a literal personal path, username, or private workspace identifier' check_no_personal_identifiers
run_check a08 'clean-environment setup and hook wiring are locally reproducible' 'setup documentation or settings wiring is incomplete' check_setup_wiring
run_check a09 'all four README files carry the required user-facing structure' 'four-language README structure is incomplete' check_readme_structure
run_check a10 'the local hero/thumbnail asset exists and is nonempty' 'the local hero/thumbnail asset is missing or empty' check_hero_asset
run_check a11 'the repository carries an MIT license' 'the MIT license is missing' check_mit_license

[ "$failures" -eq 0 ]
