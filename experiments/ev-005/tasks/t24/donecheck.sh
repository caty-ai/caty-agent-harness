#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/publication_gate_probe.py'
PROBE_ROOT=''

cleanup_probe_root() {
  [ -z "$PROBE_ROOT" ] || rm -rf "$PROBE_ROOT"
  PROBE_ROOT=''
}
trap cleanup_probe_root EXIT HUP INT TERM

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
  if run_isolated "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_isolated() {
  local probe_home probe_tmp rc
  PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t24-probe.XXXXXX") || return 1
  probe_home="$PROBE_ROOT/home"
  probe_tmp="$PROBE_ROOT/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    cleanup_probe_root
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 "$@"
  rc=$?
  cleanup_probe_root
  return "$rc"
}

run_probe() {
  mode=$1
  [ -f "$PROBE" ] || return 1
  python3 "$PROBE" "$mode"
}

check_workflow_absence() {
  needle=$1
  [ -f .github/workflows/family-links.yml ] || return 1
  ! grep -Fq -- "$needle" .github/workflows/family-links.yml
}

check_workflow_presence() {
  needle=$1
  [ -f .github/workflows/family-links.yml ] || return 1
  grep -Fq -- "$needle" .github/workflows/family-links.yml
}

run_check a01 'English README matches the published self-growth registry state' \
  'English README does not match the published self-growth registry state' run_probe readme-en
run_check a02 'Japanese README matches the published self-growth registry state' \
  'Japanese README does not match the published self-growth registry state' run_probe readme-ja
run_check a03 'Chinese README matches the published self-growth registry state' \
  'Chinese README does not match the published self-growth registry state' run_probe readme-zh
run_check a04 'Thai README matches the published self-growth registry state' \
  'Thai README does not match the published self-growth registry state' run_probe readme-th

run_check a05 'retired self-growth URL is not excluded from link checks' \
  'retired self-growth URL remains excluded from link checks' \
  check_workflow_absence 'github\.com/shojikumaru/self-growth-loop'
run_check a06 'retired memory URL is not excluded from link checks' \
  'retired memory URL remains excluded from link checks' \
  check_workflow_absence 'github\.com/shojikumaru/family-memory-architecture'
run_check a07 'preparing persona URL remains excluded from link checks' \
  'preparing persona URL is not excluded from link checks' \
  check_workflow_presence 'github\.com/shojikumaru/persona-growth-loop'
run_check a08 'retired self-growth repository is registered' \
  'retired self-growth repository is not registered exactly once' run_probe retired-repo

run_check a09 'English preparing module is plain text with its label' \
  'English preparing module is linked or unlabeled' run_probe preparing-en
run_check a10 'Japanese preparing module is plain text with its label' \
  'Japanese preparing module is linked or unlabeled' run_probe preparing-ja
run_check a11 'Chinese preparing module is plain text with its label' \
  'Chinese preparing module is linked or unlabeled' run_probe preparing-zh
run_check a12 'Thai preparing module is plain text with its label' \
  'Thai preparing module is linked or unlabeled' run_probe preparing-th

run_check a13 'personal-name patterns are rejected' \
  'personal-name patterns are not rejected' run_probe reject-name
run_check a14 'approval-record patterns are rejected' \
  'approval-record patterns are not rejected' run_probe reject-approval
run_check a15 'absolute personal paths are rejected' \
  'absolute personal paths are not rejected' run_probe reject-home-path
run_check a16 'internal host addresses are rejected' \
  'internal host addresses are not rejected' run_probe reject-host
run_check a17 'personal email addresses are rejected' \
  'personal email addresses are not rejected' run_probe reject-email
run_check a18 'unlisted personal repository links are rejected' \
  'unlisted personal repository links are not rejected' run_probe reject-personal-repo
run_check a19 'missing module labels are rejected' \
  'missing module labels are not rejected' run_probe reject-missing-label
run_check a20 'unsupported SVG state claims are rejected' \
  'unsupported SVG state claims are not rejected' run_probe reject-svg-state
run_check a21 'all required source suffixes are scanned' \
  'one or more required source suffixes escape the gate' run_probe scan-suffixes

run_check a22 'pull-request workflow enforces the publication gate' \
  'pull-request workflow does not enforce the publication gate completely' run_probe workflow-ci
run_check a23 'generated README blocks are current' \
  'generated README blocks are stale' python3 -B tools/render.py --check
run_check a24 'publication gate passes on repository sources' \
  'publication gate fails on repository sources' python3 -B tools/check_publication_gate.py
run_check a25 'clean bundled publication fixture passes' \
  'clean bundled publication fixture does not pass' run_probe clean

[ "$failures" -eq 0 ]
