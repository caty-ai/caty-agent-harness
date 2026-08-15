#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

PROBE='.ev005-fixtures/growth_model_probe.py'
failures=0
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

run_probe_check() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  shift 3
  if [ ! -f "$PROBE" ]; then
    fail_check "$check_id" "missing bundled structural probe $PROBE"
    return
  fi
  run_check "$check_id" "$pass_msg" "$fail_msg" python3 -B "$PROBE" "$@"
}

run_isolated() {
  local probe_home probe_tmp rc
  PROBE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t29-probe.XXXXXX") || return 1
  probe_home="$PROBE_ROOT/home"
  probe_tmp="$PROBE_ROOT/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    cleanup_probe_root
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@" >/dev/null 2>&1
  rc=$?
  cleanup_probe_root
  return "$rc"
}

run_probe_check a01 'both canonical documents contain operational five-stage tables' 'canonical growth-model documents or five-stage tables are missing' canonical
run_probe_check a02 'I, WE, and outside-model THEY mappings are present' 'the I/WE/THEY subject mapping is incomplete' subjects
run_probe_check a03 'Relationship Readiness is documented as the second axis' 'the Relationship Readiness axis is incomplete' readiness
run_probe_check a04 'all localized README growth sections have five stages' 'one or more localized README growth sections lack five-stage structure' readme-stages
run_probe_check a05 'stage 3 and stage 4 claim strengths are separated in all READMEs' 'implemented/unverified and planned claim strengths are not separated' claim-strength
run_probe_check a06 'the shared SVG has accessible minimal English stage labels' 'the shared SVG is missing, invalid, localized, or lacks stage labels' svg-labels
run_probe_check a07 'the SVG legend and styles separate implemented, planned, and focus' 'the SVG style semantics or focus-not-state legend is incomplete' svg-styles
run_probe_check a08 'the SVG marks the I-to-WE boundary between stages 4 and 5' 'the SVG I-to-WE boundary is missing or misplaced' svg-boundary
run_probe_check a09 'each README places a relationship table immediately after the figure' 'a localized figure/table placement or relationship column is wrong' adjacency
run_probe_check a10 'stage 1 evidence is an em dash in both canonical tables' 'stage 1 evidence is not an em dash in both canonical tables' stage-one-evidence
run_check a11 'generated repository content is current' 'the repository renderer check fails' python3 -B tools/render.py --check
run_check a12 'publication label, denylist, and SVG scans pass' 'the repository publication gate fails' python3 -B tools/check_publication_gate.py
run_probe_check a13 'localized growth sections have structural parity' 'localized growth-section structure is inconsistent' parity

[ "$failures" -eq 0 ]
