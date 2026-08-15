#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
PROBE='.ev005-fixtures/p02_probe.sh'

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-p02-probe.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@"
  rc=$?
  return "$rc"
)

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

check_install_wiring() {
  [ -f adapters/claude-code/INSTALL.md ] || return 1
  python3 - <<'PY'
from pathlib import Path

text = Path("adapters/claude-code/INSTALL.md").read_text(encoding="utf-8")
needles = [
    "## Flush intake consumer",
    "adapters/claude-code/flush-intake.sh",
    "distill.marker",
    "intake-runs.log",
]
for needle in needles:
    if needle not in text:
        raise SystemExit(1)
PY
}

check_shared_fold_contract() {
  [ -f adapters/claude-code/flush-intake.sh ] || return 1
  [ -f adapters/openclaw/distill-audit.sh ] || return 1
  [ -f scripts/lib-state-fold.sh ] || return 1
  python3 - <<'PY'
from pathlib import Path

flush = Path("adapters/claude-code/flush-intake.sh").read_text(encoding="utf-8")
distill = Path("adapters/openclaw/distill-audit.sh").read_text(encoding="utf-8")
shared = Path("scripts/lib-state-fold.sh").read_text(encoding="utf-8")

for needle in (
    'source "$repo_root/scripts/lib-state-fold.sh"',
    'take_state_lock "$workspace" claude-code-flush-intake',
    'append_state_sections "$state_file"',
):
    if needle not in flush:
        raise SystemExit(1)

for needle in (
    'source "$repo_root/scripts/lib-state-fold.sh"',
    'take_state_lock "$workspace" openclaw-distill-audit',
    'snapshot_pending_dedup_keys "$pending_dir" "$prior_dedup_keys"',
    'annotate_reply_dedup_keys "$distiller_tmp_file" "$task_id" "$annotated_reply_file"',
    'split_annotated_reply_sections "$annotated_reply_file" "$lessons_file" "$failures_file"',
    'append_state_sections "$state_file"',
):
    if needle not in distill:
        raise SystemExit(1)

for helper in (
    "annotate_reply_dedup_keys",
    "split_annotated_reply_sections",
    "snapshot_pending_dedup_keys",
    "append_state_sections",
    "take_state_lock",
):
    if f"{helper}()" not in shared:
        raise SystemExit(1)
    if f"{helper}()" in distill:
        raise SystemExit(1)
PY
}

run_check a01 'flush intake folds lessons-only content and rejects duplicate refolds' \
  'flush intake does not fold lessons-only content or still refolds duplicates' \
  run_isolated bash "$PROBE" fold-and-dedup
run_check a02 'consumed flush files archive and the distill deadman marker is touched' \
  'flush intake does not archive consumed files or misses the distill marker' \
  run_isolated bash "$PROBE" archive-and-marker
run_check a03 'install docs describe the intake and deadman wiring' \
  'install docs do not describe the intake and deadman wiring' \
  check_install_wiring
run_check a04 'the intake and openclaw adapters share the state-fold implementation' \
  'the state-fold implementation is not shared through the common helper' \
  check_shared_fold_contract

[ "$failures" -eq 0 ]
