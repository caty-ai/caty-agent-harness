#!/usr/bin/env bash

fixture_new_workspace() {
  local name=$1
  local ws=$APPLY_FIXTURE_TMP/$name
  "$ROOT/scripts/loop-init" --workspace "$ws" >/dev/null
  printf '%s\n' 'recurrence_unit=weeks' >>"$ws/loop/review.conf"
  printf '%s\n' "$ws" >>"$SECOND_RUN_WORKSPACES_FILE"
  printf '%s\n' "$ws"
}

fixture_candidate_begin() {
  local ws=$1 runid=$2 reviewer=${3:-fixture-reviewer}
  FIXTURE_CANDIDATE=$ws/loop/promotions/candidates-$runid.md
  printf '# Raw review candidates\n\nrunid: %s\nreviewer: %s\n\n' "$runid" "$reviewer" >"$FIXTURE_CANDIDATE"
}

fixture_candidate_block() {
  local runid=$1 number=$2 class=$3 theme=$4 weeks=$5 reviewer=${6:-fixture-reviewer} supersedes=${7-} run_k=${8:-1}
  local id
  id=$(printf 'theme-%s-%03d' "$runid" "$number")
  {
    printf '## %s\n' "$id"
    printf 'theme: %s\n' "$theme"
    printf 'class: %s\n' "$class"
    printf 'reviewer: %s\n' "$reviewer"
    printf 'run-weeks: %s\n' "$weeks"
    printf 'run-k: %s\n' "$run_k"
    printf 'promote: yes\n'
    [[ -n "$supersedes" ]] && printf 'supersedes: %s\n' "$supersedes"
    printf 'weeks: %s\n' "$weeks"
    printf 'union-k: 99\n'
    printf 'members:\n- flush-2026-08-10.md:fixture evidence\n'
    printf 'member-hash: 0123456789abcdef\n'
    printf 'evidence: |\n  Synthetic fixture evidence.\n\n'
  } >>"$FIXTURE_CANDIDATE"
}

fixture_session_candidate_block() {
  local runid=$1 number=$2 class=$3 theme=$4 weeks=$5 run_k=$6 reviewer=${7:-fixture-reviewer}
  local id
  id=$(printf 'theme-%s-%03d' "$runid" "$number")
  {
    printf '## %s\n' "$id"
    printf 'theme: %s\n' "$theme"
    printf 'class: %s\n' "$class"
    printf 'reviewer: %s\n' "$reviewer"
    printf 'run-weeks: %s\n' "$weeks"
    printf 'run-k: %s\n' "$run_k"
    printf 'promote: yes\n'
    printf 'weeks: %s\n' "$weeks"
    printf 'union-k: 1\n'
    printf 'members:\n'
    printf '%s\n' '- flush-2026-08-10.md:first fixture evidence' '- flush-2026-08-10.md:second fixture evidence'
    printf '%s\n' 'member-hash: 0123456789abcdef' 'member-hash: fedcba9876543210'
    printf 'evidence: |\n  Synthetic same-week session evidence.\n\n'
  } >>"$FIXTURE_CANDIDATE"
}

fixture_run_apply() {
  local ws=$1
  shift
  APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 "$APPLY_SCRIPT" --workspace "$ws" "$@"
}

fixture_section_count() {
  local ws=$1 heading=$2
  awk -v heading="$heading" '
    /^## / {inside=(index($0, heading)==1); next}
    inside && !/^[[:space:]]*$/ && !/^[[:space:]]*<!--.*-->[[:space:]]*$/ {n++}
    END {print n+0}
  ' "$ws/STATE.md"
}

fixture_add_lines() {
  local ws=$1 heading=$2 count=$3 prefix=${4:-seed}
  local tmp=$ws/STATE.fixture
  awk -v heading="$heading" -v count="$count" -v prefix="$prefix" '
    /^## / {
      if (inside) for (i=1; i<=count; i++) print "- 2026-01-01 " prefix " " i
      inside=(index($0, heading)==1)
      print; next
    }
    {print}
    END {if (inside) for (i=1; i<=count; i++) print "- 2026-01-01 " prefix " " i}
  ' "$ws/STATE.md" >"$tmp"
  mv "$tmp" "$ws/STATE.md"
}
