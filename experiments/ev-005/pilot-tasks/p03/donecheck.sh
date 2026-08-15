#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  local check_id pass_msg fail_msg
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

check_all_strings() {
  local path needle
  path=$1
  shift
  [ -f "$path" ] || return 1
  for needle in "$@"; do
    grep -Fq "$needle" "$path" || return 1
  done
}

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-p03-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  mkdir -p "$env_root/home" "$env_root/tmp" || return 1
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 "$@"
  rc=$?
  return "$rc"
)

check_cli_provider_contract() {
  check_all_strings \
    adapters/hermes/examples/verifier-provider-cli.sh \
    'penultimate line' \
    'exactly once' \
    'count_exact' \
    'marker_count += count_exact($0, "VERDICT:")' \
    'verdict_number = NR' \
    'cat "$normalized_reply_file" || fail '\''CLI output could not be emitted'\'''
}

check_python_provider_contract() {
  check_all_strings \
    adapters/hermes/examples/verifier-provider.py \
    'penultimate line' \
    'exactly once' \
    'VERDICT_PATTERN = re.compile(' \
    'verdict_indexes = [' \
    'verdict_index = verdict_indexes[0]' \
    '(line for line in normalized_lines[verdict_index + 1 :] if line)'
}

check_wrapper_contract() {
  check_all_strings \
    adapters/hermes/examples/verifier-wrapper.sh \
    'marker_count += count_exact($0, "VERDICT:")' \
    'if ($0 ~ /^VERDICT: (pass|fail|inconclusive|rubric-invalid|needs-human|blocked-missing-artifact)$/)' \
    'for (line = verdict_number + 1; line <= NR; line++)' \
    'if (lines[line] != "") {' \
    'cat "$validated_output" || exit 65' \
    '[[ $# -eq 1 && -n "$bundle" ]] || exit 64' \
    ']] || exit 69' \
    'exit 70'
}

check_docs_contract() {
  check_all_strings \
    adapters/hermes/INSTALL.md \
    'anchored allowed verdict' \
    '`VERDICT:` occurrence' \
    'NUL byte'
  check_all_strings \
    templates/VERIFY-BUNDLE.tmpl.md \
    'last two lines' \
    'exactly once'
}

check_wrapper_nul_rejection() {
  check_all_strings \
    adapters/hermes/examples/verifier-wrapper.sh \
    "tr -d '\\0'" \
    'cmp -s "$provider_output" "$nul_stripped_output"'
}

check_cli_nul_rejection() {
  check_all_strings \
    adapters/hermes/examples/verifier-provider-cli.sh \
    "tr -d '\\0'" \
    'cmp -s "$reply_file" "$normalized_reply_file"'
}

check_python_nul_rejection() {
  check_all_strings \
    adapters/hermes/examples/verifier-provider.py \
    'if "\x00" in reply:' \
    'fail("provider returned malformed output")'
}

check_cli_behavior() {
  check_all_strings tests/hermes-verifier-cli.test.sh \
    'CLI_MODE=verdict-last' \
    'extra-before-anchor' \
    'nul-before-anchor' || return 1
  run_isolated bash tests/hermes-verifier-cli.test.sh >/dev/null 2>&1
}

check_examples_behavior() {
  check_all_strings tests/hermes-verifier-examples.test.sh \
    'invalid_wrapper_matrix_ok' \
    'api_acceptance_ok' \
    'api_nul_matrix_ok' || return 1
  run_isolated bash tests/hermes-verifier-examples.test.sh >/dev/null 2>&1
}

check_verify_job_behavior() {
  run_isolated bash tests/verify-job.test.sh >/dev/null 2>&1
}

check_wrapper_conformance_behavior() {
  run_isolated bash tests/wrapper-conformance.test.sh >/dev/null 2>&1
}

check_no_stale_first_line() {
  ! grep -RniE 'FIRST line|first line' \
    adapters/hermes/examples \
    adapters/hermes/INSTALL.md >/dev/null 2>&1
}

run_check a01 \
  'CLI provider uses the verdict-last unique-marker contract and two-line emit path' \
  'CLI provider prompt contract is missing or incomplete' \
  check_cli_provider_contract
run_check a02 \
  'Python provider prompt and parser use the position-free unique-marker contract' \
  'Python provider contract is missing or incomplete' \
  check_python_provider_contract
run_check a03 \
  'wrapper uses the position-free anchored verdict parser and keeps exit-code semantics' \
  'wrapper contract or exit-code table is missing or incomplete' \
  check_wrapper_contract
run_check a04 \
  'template and install notes describe the position-free unique-marker contract' \
  'template or install notes do not describe the updated contract' \
  check_docs_contract
run_check a05 \
  'CLI verifier path accepts verdict-last and rejects malformed replies' \
  'CLI verifier regression behavior is wrong' \
  check_cli_behavior
run_check a06 \
  'example wrapper/provider path accepts verdict-last and rejects malformed replies' \
  'example wrapper/provider regression behavior is wrong' \
  check_examples_behavior
run_check a07 \
  'verify-job integration still passes with the unchanged wrapper contract' \
  'verify-job integration regressed' \
  check_verify_job_behavior
run_check a08 \
  'wrapper-conformance integration still passes with the unchanged wrapper contract' \
  'wrapper-conformance integration regressed' \
  check_wrapper_conformance_behavior
run_check a09 \
  'no touched example or install surface still describes the first-line contract' \
  'stale first-line wording remains' \
  check_no_stale_first_line
run_check a10 \
  'wrapper rejects NUL bytes before parsing' \
  'wrapper NUL-byte rejection is missing' \
  check_wrapper_nul_rejection
run_check a11 \
  'CLI provider rejects NUL bytes before normalization' \
  'CLI provider NUL-byte rejection is missing' \
  check_cli_nul_rejection
run_check a12 \
  'Python provider rejects NUL bytes before normalization' \
  'Python provider NUL-byte rejection is missing' \
  check_python_nul_rejection

[ "$failures" -eq 0 ]
