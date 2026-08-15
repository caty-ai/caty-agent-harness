#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE=".ev005-fixtures/p05_probe.sh"

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-p05.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  shift 3
  if "$@" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_probe_case() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  local mode=$4
  if [ ! -f "$PROBE" ]; then
    fail_check "$check_id" "missing bundled probe $PROBE"
    return
  fi
  run_check "$check_id" "$pass_msg" "$fail_msg" \
    run_isolated bash "$PROBE" "$mode"
}

check_hook_surface() {
  run_isolated python3 - <<'PY'
import ast
from pathlib import Path

launcher = Path("hooks/validate-subagent-brief.sh")
body = Path("hooks/validate-subagent-brief.py")
suite = Path("tests/test_brief_validator.sh")

if not launcher.is_file() or not body.is_file() or not suite.is_file():
    raise SystemExit(1)

tree = ast.parse(body.read_text(encoding="utf-8"))
required = None
supported = None
env_names = set()
for node in tree.body:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "DEFAULT_REQUIRED_SECTIONS":
                required = ast.literal_eval(node.value)
            if isinstance(target, ast.Name) and target.id == "SUPPORTED_TOOLS":
                supported = ast.literal_eval(node.value)
    elif isinstance(node, ast.FunctionDef):
        for child in ast.walk(node):
            if isinstance(child, ast.Constant) and isinstance(child.value, str):
                if child.value.startswith("CK_BRIEF_") or child.value == "CK_SKIP_BRIEF_VALIDATION":
                    env_names.add(child.value)

if required != ["## 実装仕様", "## 実装チェック", "## レビュー基準"]:
    raise SystemExit(1)
if set(supported) != {"Agent", "Task"}:
    raise SystemExit(1)
expected_envs = {
    "CK_SKIP_BRIEF_VALIDATION",
    "CK_BRIEF_REQUIRED_SECTIONS",
    "CK_BRIEF_SKIP_SUBAGENT_TYPES",
    "CK_BRIEF_MIN_PROMPT_CHARS",
}
if not expected_envs.issubset(env_names):
    raise SystemExit(1)
PY
}

check_docs_and_examples() {
  run_isolated python3 - <<'PY'
import json
import re
from pathlib import Path

docs_path = Path("docs/brief-validator.md")
docs = docs_path.read_text(encoding="utf-8")
settings = json.loads(Path("examples/settings.json").read_text(encoding="utf-8"))

hooks = settings.get("hooks", {}).get("PreToolUse", [])
matched = False
for entry in hooks:
    if entry.get("matcher") != "Agent|Task":
        continue
    for hook in entry.get("hooks", []):
        command = hook.get("command", "")
        if "validate-subagent-brief.sh" in command and "if [ -f \"$f\" ]" in command:
            matched = True
            break
    if matched:
        break

if not matched:
    raise SystemExit(1)

needles = [
    "bash tests/test_brief_validator.sh",
    "CK_BRIEF_REQUIRED_SECTIONS",
    "CK_BRIEF_SKIP_SUBAGENT_TYPES",
    "CK_BRIEF_MIN_PROMPT_CHARS",
    "CK_SKIP_BRIEF_VALIDATION",
    "plain, case-sensitive substrings",
]
for needle in needles:
    if needle not in docs:
        raise SystemExit(1)

residue = re.compile(r"shojikumaru|/Users/|\balpha\b|openclaw|ALPHA_", re.IGNORECASE)
for path in [
    docs_path,
    Path("hooks/validate-subagent-brief.sh"),
    Path("hooks/validate-subagent-brief.py"),
    Path("tests/test_brief_validator.sh"),
]:
    text = path.read_text(encoding="utf-8")
    if residue.search(text):
        raise SystemExit(1)
PY
}

check_suite() {
  run_isolated bash -c '
    grep -Fq "case_missing_all_blocks" tests/test_brief_validator.sh &&
    grep -Fq "case_threshold_boundary" tests/test_brief_validator.sh &&
    grep -Fq "case_malformed_inputs_fail_open" tests/test_brief_validator.sh &&
    grep -Fq "case_interpreter_noise_before_blocked_sentinel" tests/test_brief_validator.sh &&
    bash tests/test_brief_validator.sh &&
    bash -n hooks/validate-subagent-brief.sh tests/test_brief_validator.sh &&
    python3 -B -c "import ast, pathlib; ast.parse(pathlib.Path(\"hooks/validate-subagent-brief.py\").read_text(encoding=\"utf-8\"))" &&
    python3 -m json.tool examples/settings.json >/dev/null
  '
}

run_check a01 'validator hook, body, and canonical tool/section contract ship' \
  'validator hook files or canonical contract are missing' check_hook_surface
run_probe_case a02 'incomplete substantial prompts block with the corrective contract' \
  'incomplete substantial prompts do not emit the expected block contract' block
run_probe_case a03 'canonical substantial prompts pass silently' \
  'canonical substantial prompts do not pass silently' compliant
run_probe_case a04 'default threshold, skip semantics, and tool routing hold' \
  'default threshold, skip semantics, or tool routing drifted' threshold_skip
run_probe_case a05 'environment overrides and fallback rules hold' \
  'environment override or fallback behavior drifted' env_overrides
run_probe_case a06 'launcher fail-open and shim-noise handling hold' \
  'launcher fail-open or shim-noise handling drifted' launcher_contract
run_check a07 'docs and example wiring describe guarded setup, verification, and residue-free public text' \
  'docs/example wiring or residue-free public text contract drifted' \
  check_docs_and_examples
run_check a08 'the regression suite, shell syntax, AST parse, and JSON parse all pass' \
  'the regression suite or parse/syntax checks do not pass' check_suite

[ "$failures" -eq 0 ]
