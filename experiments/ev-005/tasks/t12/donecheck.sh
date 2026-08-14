#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t12.XXXXXX") || exit 1
failures=0
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

check_no_yaml_import() {
  local script env_root rc
  script=$1
  [ -f "$script" ] || return 1
  env_root=$(mktemp -d "$TMP_ROOT/ast-probe.XXXXXX") || return 1
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    rm -rf "$env_root"
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    python3 - "$script" <<'PY'
import ast
import sys

try:
    tree = ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])
except (OSError, SyntaxError, UnicodeError):
    raise SystemExit(1)

for node in ast.walk(tree):
    if isinstance(node, ast.Import) and any(alias.name == "yaml" or alias.name.startswith("yaml.") for alias in node.names):
        raise SystemExit(1)
    if isinstance(node, ast.ImportFrom) and node.module and (node.module == "yaml" or node.module.startswith("yaml.")):
        raise SystemExit(1)
PY
  rc=$?
  rm -rf "$env_root"
  return "$rc"
}

check_no_pyyaml_note() {
  path=$1
  [ -f "$path" ] || return 1
  ! grep -Eiq 'PyYAML' "$path"
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

run_check a01 'content-lint has no yaml import' 'content-lint imports yaml or cannot be parsed' check_no_yaml_import scripts/content-lint
run_check a02 'injection-lint has no yaml import' 'injection-lint imports yaml or cannot be parsed' check_no_yaml_import scripts/injection-lint
run_check a03 'README.md has no PyYAML guidance' 'README.md retains PyYAML guidance or is missing' check_no_pyyaml_note README.md
run_check a04 'README.ja.md has no PyYAML guidance' 'README.ja.md retains PyYAML guidance or is missing' check_no_pyyaml_note README.ja.md
run_check a05 'README.th.md has no PyYAML guidance' 'README.th.md retains PyYAML guidance or is missing' check_no_pyyaml_note README.th.md
run_check a06 'README.zh.md has no PyYAML guidance' 'README.zh.md retains PyYAML guidance or is missing' check_no_pyyaml_note README.zh.md
run_check a07 'repository map has no PyYAML guidance' 'repository map retains PyYAML guidance or is missing' check_no_pyyaml_note docs/repository-map.md
run_check a08 'getting started has no PyYAML guidance' 'getting started retains PyYAML guidance or is missing' check_no_pyyaml_note docs/getting-started.md
run_check a09 'agent guide has no PyYAML guidance' 'agent guide retains PyYAML guidance or is missing' check_no_pyyaml_note docs/agent-guide.md
run_check a10 'contributing guide has no PyYAML guidance' 'contributing guide retains PyYAML guidance or is missing' check_no_pyyaml_note CONTRIBUTING.md
run_check a11 'security guide has no PyYAML guidance' 'security guide retains PyYAML guidance or is missing' check_no_pyyaml_note SECURITY.md

suite_root=$(mktemp -d "$TMP_ROOT/suite.XXXXXX")
if [ $? -ne 0 ] || ! mkdir -p "$suite_root/home" "$suite_root/tmp"; then
  [ -n "${suite_root:-}" ] && rm -rf "$suite_root"
  fail_check a12 'could not create isolated full-suite environment'
  fail_check a13 'could not create isolated full-suite environment'
else
  HOME="$suite_root/home" TMPDIR="$suite_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    python3 -S scripts/tests/run_tests.py >"$suite_root/suite.log" 2>&1
  suite_rc=$?
  if [ "$suite_rc" -eq 0 ]; then
    pass_check a12 'full repository suite passes'
  else
    fail_check a12 'full repository suite fails'
  fi
  if grep -Eq 'Final summary: .*skipped=0([[:space:]]|$)' "$suite_root/suite.log"; then
    pass_check a13 'full repository suite reports no skips'
  else
    fail_check a13 'full repository suite does not report zero skips'
  fi
  rm -rf "$suite_root"
fi

[ "$failures" -eq 0 ]
