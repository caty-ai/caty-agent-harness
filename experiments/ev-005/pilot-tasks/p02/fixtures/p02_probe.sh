#!/bin/bash
set -euo pipefail

usage() {
  printf 'Usage: p02_probe.sh <fold-and-dedup|archive-and-marker>\n' >&2
}

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

mode=$1
repo_root=$(pwd -P)
intake=$repo_root/adapters/claude-code/flush-intake.sh
loop_init=$repo_root/scripts/loop-init

[[ -x "$intake" && -x "$loop_init" ]] || exit 1

tmp_root=${TMPDIR:-/tmp}
probe_root=$(mktemp -d "$tmp_root/ev005-p02-fixture.XXXXXX")
cleanup() {
  rm -rf "$probe_root"
}
trap cleanup EXIT HUP INT TERM

receipt_value() {
  local ws=$1
  local key=$2
  tail -n 1 "$ws/loop/pending/intake-runs.log" | tr ' ' '\n' | sed -n "s/^$key=//p" | head -n 1
}

new_ws() {
  local ws=$1
  "$loop_init" --workspace "$ws" >/dev/null
  (cd "$ws" && pwd -P)
}

write_fold_fixture() {
  local path=$1
  cat >"$path" <<'EOF'
<!-- flush origin=stop-hook-demand session=fixture-fold ts=2026-07-01T01:02:03Z outcome=ok unverified=true -->
- Fold the pending flush corpus through the governed lessons path.
<!-- flush origin=stop-hook-demand session=fixture-skip ts=2026-07-01T01:02:03Z outcome=no_reply unverified=true -->
- This no-reply block must not reach STATE.md.
EOF
}

write_dedup_fixture() {
  local path=$1
  cat >"$path" <<'EOF'
<!-- flush origin=stop-hook-demand session=fixture-dedup ts=2026-07-08T01:02:03Z outcome=ok unverified=true -->
- Ledger identity survives STATE eviction.
EOF
}

run_intake() {
  local ws=$1
  "$intake" "$ws"
}

case "$mode" in
  fold-and-dedup)
    ws=$(new_ws "$probe_root/fold")
    write_fold_fixture "$ws/loop/pending/flush-2026-07-01.md"
    run_intake "$ws"

    folded_line='- 2026-07-01 Fold the pending flush corpus through the governed lessons path. (source: flush-intake)'
    skipped_line='This no-reply block must not reach STATE.md.'
    if ! grep -Fqx -- "$folded_line" "$ws/STATE.md"; then
      exit 1
    fi
    if grep -Fq -- "$skipped_line" "$ws/STATE.md"; then
      exit 1
    fi
    if [[ "$(receipt_value "$ws" folded)" != 1 ]]; then
      exit 1
    fi

    write_dedup_fixture "$ws/loop/pending/flush-2026-07-08.md"
    run_intake "$ws"
    sed '/Ledger identity survives STATE eviction\./d' "$ws/STATE.md" >"$probe_root/state.without-dedup"
    mv "$probe_root/state.without-dedup" "$ws/STATE.md"
    cp "$ws/loop/archive/flush-2026-07-08.md" "$ws/loop/pending/flush-2026-07-08.md"
    run_intake "$ws"

    dedup_line='- 2026-07-08 Ledger identity survives STATE eviction. (source: flush-intake)'
    [[ "$(grep -Fxc -- "$dedup_line" "$ws/STATE.md" || true)" -eq 0 ]] || exit 1
    [[ "$(receipt_value "$ws" deduped)" == 1 ]] || exit 1
    [[ "$(receipt_value "$ws" folded)" == 0 ]] || exit 1
    ;;
  archive-and-marker)
    ws=$(new_ws "$probe_root/archive")
    write_fold_fixture "$ws/loop/pending/flush-2026-07-01.md"
    run_intake "$ws"

    [[ ! -e "$ws/loop/pending/flush-2026-07-01.md" ]] || exit 1
    [[ -f "$ws/loop/archive/flush-2026-07-01.md" ]] || exit 1
    [[ -f "$ws/loop/.deadman/distill.marker" ]] || exit 1
    [[ "$(receipt_value "$ws" marker)" == touched ]] || exit 1
    ;;
  *)
    usage
    exit 2
    ;;
esac
