#!/usr/bin/env bash
set -euo pipefail

MODE=${1:?mode required}
ROOT=$(pwd)
HOOK="${ROOT}/hooks/validate-subagent-brief.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-p05-probe.XXXXXX")
RUN_STDOUT=""
RUN_STDERR=""
RUN_STATUS=0
REAL_PYTHON=$(command -v python3)

cleanup() {
  chmod -R u+rwx "${TMP_ROOT}" 2>/dev/null || true
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT HUP INT TERM

long_text() {
  python3 -c 'print("x" * 600, end="")'
}

repeated_text() {
  python3 -c 'import sys; print("x" * int(sys.argv[1]), end="")' "$1"
}

canonical_prompt() {
  printf '## 実装仕様\n## 実装チェック\n## レビュー基準\n%s' "$(long_text)"
}

payload_for() {
  local tool_name=$1
  local subagent_type=$2
  local prompt=$3
  python3 - "${tool_name}" "${subagent_type}" "${prompt}" <<'PY'
import json
import sys

print(json.dumps({
    "tool_name": sys.argv[1],
    "tool_input": {
        "subagent_type": sys.argv[2],
        "prompt": sys.argv[3],
    },
}))
PY
}

run_hook() {
  local payload=$1
  shift
  RUN_STDOUT="${TMP_ROOT}/stdout"
  RUN_STDERR="${TMP_ROOT}/stderr"
  if printf '%s' "${payload}" | env "$@" bash "${HOOK}" >"${RUN_STDOUT}" 2>"${RUN_STDERR}"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
}

case_block() {
  run_hook "$(payload_for Agent executor "$(long_text)")"
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'Missing sections: ## 実装仕様, ## 実装チェック, ## レビュー基準' "${RUN_STDERR}" || return 1
  grep -Fq 'https://github.com/caty-ai/family-dev-handbook/blob/main/docs/07-delegation-brief.md' "${RUN_STDERR}" || return 1
  grep -Fq 'https://github.com/caty-ai/family-dev-handbook/blob/main/templates/brief-template.md' "${RUN_STDERR}" || return 1
  grep -Fq 'CK_SKIP_BRIEF_VALIDATION=1 in the environment that launches Claude Code' "${RUN_STDERR}" || return 1
}

case_compliant() {
  run_hook "$(payload_for Agent executor "$(canonical_prompt)")"
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDOUT}" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1
}

case_threshold_skip() {
  run_hook "$(payload_for Agent executor "$(repeated_text 499)")"
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook "$(payload_for Agent executor "$(repeated_text 500)")"
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'Missing sections: ## 実装仕様, ## 実装チェック, ## レビュー基準' "${RUN_STDERR}" || return 1

  run_hook "$(payload_for Agent writer "$(long_text)")"
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook "$(payload_for Agent writer2 "$(long_text)")"
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq "subagent type 'writer2'" "${RUN_STDERR}" || return 1

  run_hook "$(payload_for Task executor "$(long_text)")"
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq '[validate-subagent-brief] Blocked Task delegation' "${RUN_STDERR}" || return 1

  run_hook "$(payload_for Bash executor "$(long_text)")"
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1
}

case_env_overrides() {
  local custom_prompt short_prompt payload

  custom_prompt=$(printf '## Goal\n## Self-check\n## Review criteria\n%s' "$(long_text)")
  run_hook "$(payload_for Agent executor "${custom_prompt}")" CK_BRIEF_REQUIRED_SECTIONS='## Goal|## Self-check|## Review criteria'
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook "$(payload_for Agent executor "$(canonical_prompt)")" CK_BRIEF_REQUIRED_SECTIONS='## Goal|## Self-check|## Review criteria'
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'Missing sections: ## Goal, ## Self-check, ## Review criteria' "${RUN_STDERR}" || return 1

  run_hook "$(payload_for Agent executor "$(long_text)")" CK_BRIEF_REQUIRED_SECTIONS='a||b'
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'Missing sections: ## 実装仕様, ## 実装チェック, ## レビュー基準' "${RUN_STDERR}" || return 1

  short_prompt=$(python3 -c 'print("x" * 120, end="")')
  run_hook "$(payload_for Agent executor "${short_prompt}")" CK_BRIEF_MIN_PROMPT_CHARS=100
  [ "${RUN_STATUS}" = "2" ] || return 1

  run_hook "$(payload_for Agent executor "${short_prompt}")" CK_BRIEF_MIN_PROMPT_CHARS=not-a-number
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook "$(payload_for Agent research-lite "$(long_text)")" CK_BRIEF_SKIP_SUBAGENT_TYPES=research-lite
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook "$(payload_for Agent writer "$(long_text)")" CK_BRIEF_SKIP_SUBAGENT_TYPES=research-lite
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'CK_BRIEF_SKIP_SUBAGENT_TYPES (effective: research-lite).' "${RUN_STDERR}" || return 1
  ! grep -Fq 'Explore' "${RUN_STDERR}" || return 1

  payload=$(payload_for Agent executor "$(long_text)")
  run_hook '' CK_BRIEF_MIN_PROMPT_CHARS=1
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook 'garbage' CK_BRIEF_MIN_PROMPT_CHARS=1
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook '[]' CK_BRIEF_MIN_PROMPT_CHARS=1
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook '{"tool_name":"Agent"}' CK_BRIEF_MIN_PROMPT_CHARS=1
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  run_hook '{"tool_name":"Agent","tool_input":{"subagent_type":"executor","prompt":42}}' CK_BRIEF_MIN_PROMPT_CHARS=1
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1
}

case_launcher_contract() {
  local isolated_dir isolated_hook payload fake_bin fake_python shim_bin shim_python

  isolated_dir="${TMP_ROOT}/missing-body"
  isolated_hook="${isolated_dir}/validate-subagent-brief.sh"
  mkdir -p "${isolated_dir}"
  cp "${HOOK}" "${isolated_hook}"
  payload=$(payload_for Agent executor "$(long_text)")
  RUN_STDOUT="${TMP_ROOT}/missing-body.stdout"
  RUN_STDERR="${TMP_ROOT}/missing-body.stderr"
  if bash "${isolated_hook}" >"${RUN_STDOUT}" 2>"${RUN_STDERR}" <<<"${payload}"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDOUT}" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  fake_bin="${TMP_ROOT}/fake-bin"
  fake_python="${fake_bin}/python3"
  mkdir -p "${fake_bin}"
  printf '#!/bin/sh\nprintf "simulated interpreter failure\\n" >&2\nexit 2\n' > "${fake_python}"
  chmod 755 "${fake_python}"
  run_hook "${payload}" PATH="${fake_bin}:${PATH}"
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDOUT}" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  RUN_STDOUT="${TMP_ROOT}/placeholder.stdout"
  RUN_STDERR="${TMP_ROOT}/placeholder.stderr"
  if printf '%s' "${payload}" | sh -c 'f="<CONTEXT_KIT_DIR>/hooks/validate-subagent-brief.sh"; if [ -f "$f" ]; then bash "$f"; fi' >"${RUN_STDOUT}" 2>"${RUN_STDERR}"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
  [ "${RUN_STATUS}" = "0" ] || return 1
  [ ! -s "${RUN_STDOUT}" ] || return 1
  [ ! -s "${RUN_STDERR}" ] || return 1

  shim_bin="${TMP_ROOT}/shim-bin"
  shim_python="${shim_bin}/python3"
  mkdir -p "${shim_bin}"
  cat > "${shim_python}" <<EOF
#!/bin/sh
printf 'python shim noise\n' >&2
exec "${REAL_PYTHON}" "\$@"
EOF
  chmod 755 "${shim_python}"
  run_hook "${payload}" PATH="${shim_bin}:${PATH}"
  [ "${RUN_STATUS}" = "2" ] || return 1
  grep -Fq 'python shim noise' "${RUN_STDERR}" || return 1
  grep -Fq '[validate-subagent-brief] Blocked Agent delegation' "${RUN_STDERR}" || return 1
}

case "${MODE}" in
  block)
    case_block
    ;;
  compliant)
    case_compliant
    ;;
  threshold_skip)
    case_threshold_skip
    ;;
  env_overrides)
    case_env_overrides
    ;;
  launcher_contract)
    case_launcher_contract
    ;;
  *)
    printf 'unknown mode: %s\n' "${MODE}" >&2
    exit 2
    ;;
esac
