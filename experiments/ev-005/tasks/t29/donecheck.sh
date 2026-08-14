#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

PROBE='.ev005-fixtures/growth_model_probe.py'
failures=0

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

[ -f "$PROBE" ] || {
  fail_check a01 'the bundled structural probe is missing'
  exit 1
}

run_check a01 'both canonical documents contain operational five-stage tables' 'canonical growth-model documents or five-stage tables are missing' python3 -B "$PROBE" canonical
run_check a02 'I, WE, and outside-model THEY mappings are present' 'the I/WE/THEY subject mapping is incomplete' python3 -B "$PROBE" subjects
run_check a03 'Relationship Readiness is documented as the second axis' 'the Relationship Readiness axis is incomplete' python3 -B "$PROBE" readiness
run_check a04 'all localized README growth sections have five stages' 'one or more localized README growth sections lack five-stage structure' python3 -B "$PROBE" readme-stages
run_check a05 'stage 3 and stage 4 claim strengths are separated in all READMEs' 'implemented/unverified and planned claim strengths are not separated' python3 -B "$PROBE" claim-strength
run_check a06 'the shared SVG has accessible minimal English stage labels' 'the shared SVG is missing, invalid, localized, or lacks stage labels' python3 -B "$PROBE" svg-labels
run_check a07 'the SVG legend and styles separate implemented, planned, and focus' 'the SVG style semantics or focus-not-state legend is incomplete' python3 -B "$PROBE" svg-styles
run_check a08 'the SVG marks the I-to-WE boundary between stages 4 and 5' 'the SVG I-to-WE boundary is missing or misplaced' python3 -B "$PROBE" svg-boundary
run_check a09 'each README places a relationship table immediately after the figure' 'a localized figure/table placement or relationship column is wrong' python3 -B "$PROBE" adjacency
run_check a10 'stage 1 evidence is an em dash in both canonical tables' 'stage 1 evidence is not an em dash in both canonical tables' python3 -B "$PROBE" stage-one-evidence
run_check a11 'generated repository content is current' 'the repository renderer check fails' python3 -B tools/render.py --check
run_check a12 'publication label, denylist, and SVG scans pass' 'the repository publication gate fails' python3 -B tools/check_publication_gate.py
run_check a13 'localized growth sections have structural parity' 'localized growth-section structure is inconsistent' python3 -B "$PROBE" parity

[ "$failures" -eq 0 ]
