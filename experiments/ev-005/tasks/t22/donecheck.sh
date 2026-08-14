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

check_five_tools() {
  for path in \
    bin/lg \
    hooks/scratch-persist.py \
    hooks/validate-subagent-brief.py \
    hooks/rm-enforcer.py \
    hooks/private-repo-enforcer.mjs \
    hooks/api-key-leak-detector.mjs \
    bin/recall; do
    [ -f "$path" ] || return 1
  done
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
  python3 -B - examples/settings.json <<'PY'
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

run_check a01 'all five generalized tool surfaces are present' 'one or more generalized tool surfaces are missing' check_five_tools
run_check a02 'recall documents its individual/shared-memory relationship and local-only use' 'recall does not document its individual/shared-memory relationship and local-only use' check_recall_relationship
run_check a03 'tracked text contains no literal personal-environment identifiers' 'tracked text contains a literal personal path, username, or private workspace identifier' check_no_personal_identifiers
run_check a04 'clean-environment setup and hook wiring are locally reproducible' 'setup documentation or settings wiring is incomplete' check_setup_wiring
run_check a05 'all four README files carry the required user-facing structure' 'four-language README structure is incomplete' check_readme_structure
run_check a06 'the local hero/thumbnail asset exists and is nonempty' 'the local hero/thumbnail asset is missing or empty' check_hero_asset
run_check a07 'the repository carries an MIT license' 'the MIT license is missing' check_mit_license

[ "$failures" -eq 0 ]
