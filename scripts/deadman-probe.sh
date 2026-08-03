#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: deadman-probe.sh <workspace-dir>\n' >&2
  exit 2
}

mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || echo 0
}

append_failure() {
  local state_file=$1
  local entry=$2
  local tmp_file

  if grep -Eq '^## Open failures[[:space:]]*(\([^)]*\))?[[:space:]]*$' "$state_file" 2>/dev/null; then
    tmp_file="$state_file.deadman.$$"
    trap 'rm -f "$tmp_file"' RETURN
    if awk -v entry="$entry" '
      !inserted && /^## Open failures[[:space:]]*(\([^)]*\))?[[:space:]]*$/ {
        print
        print entry
        inserted = 1
        next
      }
      { print }
    ' "$state_file" >"$tmp_file"; then
      if ! mv "$tmp_file" "$state_file"; then
        rm -f "$tmp_file"
        printf 'deadman-probe: mv failed while appending to %s, STATE.md left unchanged\n' "$state_file" >&2
        return 1
      fi
    else
      rm -f "$tmp_file"
      printf 'deadman-probe: awk failed while appending to %s, STATE.md left unchanged\n' "$state_file" >&2
      return 1
    fi
  else
    {
      printf '\n## Open failures\n'
      printf '%s\n' "$entry"
    } >>"$state_file"
  fi
}

create_baseline() {
  local baseline=$1

  [[ -e "$baseline" ]] && return 0
  (set -C; : >"$baseline") 2>/dev/null || [[ -e "$baseline" ]]
}

fire_once() {
  local sentinel=$1

  (set -C; : >"$sentinel") 2>/dev/null
}

append_failure_with_lock() {
  local name=$1
  local entry=$2
  local lock=$deadman_dir/.state.lock
  local attempts=0

  while (( attempts < 10 )); do
    if mkdir "$lock" 2>/dev/null; then
      (
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT
        append_failure "$state_file" "$entry"
      )
      return $?
    fi

    (( attempts += 1 ))
    if (( attempts < 10 )); then
      sleep 0.5
    fi
  done

  lock_age=$(( $(date +%s) - $(mtime "$lock") ))
  if [[ -d "$lock" ]] && (( lock_age > 60 )); then
    rmdir "$lock" 2>/dev/null || rm -rf "$lock" 2>/dev/null || true
    if mkdir "$lock" 2>/dev/null; then
      (
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT
        append_failure "$state_file" "$entry"
      )
      return $?
    fi
  fi

  printf 'deadman-probe: STATE.md lock timeout, skipping append for %s (notify still sent)\n' "$name" >&2
  return 1
}

[[ $# -eq 1 ]] || usage

workspace=$1
[[ -d "$workspace" ]] || usage
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/scripts/lib-pause.sh"
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || usage
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" deadman-probe
  exit 0
fi

checks=${DEADMAN_CHECKS:-'tick:300 distill:86400'}
[[ -n "$checks" ]] || usage

state_file=$workspace/STATE.md
deadman_dir=$workspace/loop/.deadman
mkdir -p "$deadman_dir"
(set -C; : >"$state_file") 2>/dev/null || true

new_violation=0
for check in $checks; do
  # Max 9 digits is about 31 years and keeps cadence * 2 within signed 64-bit range.
  if [[ ! $check =~ ^([A-Za-z0-9][A-Za-z0-9._-]*):([1-9][0-9]{0,8})$ ]]; then
    printf 'deadman-probe: malformed DEADMAN_CHECKS entry: %s\n' "$check" >&2
    exit 2
  fi

  name=${BASH_REMATCH[1]}
  cadence=${BASH_REMATCH[2]}
  threshold=$((cadence * 2))
  marker=$deadman_dir/$name.marker
  baseline=$deadman_dir/$name.baseline
  sentinel=$deadman_dir/$name.fired

  if [[ ! -e "$marker" ]]; then
    create_baseline "$baseline" || {
      printf 'deadman-probe: cannot create baseline: %s\n' "$baseline" >&2
      exit 2
    }
  fi

  reference=
  if [[ -e "$marker" ]]; then
    reference=$marker
  fi
  if [[ -e "$baseline" ]] && { [[ -z "$reference" ]] || [[ $(mtime "$baseline") -gt $(mtime "$reference") ]]; }; then
    reference=$baseline
  fi

  now=$(date +%s)
  age=$((now - $(mtime "$reference")))
  if (( age < 0 || age <= threshold )); then
    rm -f "$sentinel"
    printf '%s healthy age=%ss\n' "$name" "$age"
    continue
  fi

  if [[ -e "$sentinel" ]] && (( $(mtime "$sentinel") > $(mtime "$reference") )); then
    printf '%s stale-reported age=%ss\n' "$name" "$age"
    continue
  fi

  if [[ -e "$sentinel" ]] && ! rm "$sentinel" 2>/dev/null; then
    printf '%s stale-reported age=%ss\n' "$name" "$age"
    continue
  fi

  if [[ ${DEADMAN_TEST_CRASH_AFTER_CLAIM:-} == 1 ]]; then
    exit 1
  fi

  utc_date=$(date -u +%F)
  message="$utc_date | deadman: $name last run evidence ($(basename "$reference")) ${age}s old exceeds 2x cadence (${threshold}s) — scheduler silence suspected"
  append_ok=1
  if ! append_failure_with_lock "$name" "- $message"; then
    append_ok=0
  fi
  notify_cmd=${DEADMAN_NOTIFY_CMD:-tg-send}
  if command -v "$notify_cmd" >/dev/null 2>&1; then
    "$notify_cmd" "$message" || true
  fi

  if (( append_ok )) && fire_once "$sentinel"; then
    printf '%s stale-fired age=%ss\n' "$name" "$age"
  elif (( append_ok )); then
    printf '%s stale-reported age=%ss\n' "$name" "$age"
  else
    printf '%s stale-retry age=%ss\n' "$name" "$age"
  fi
  new_violation=1
done

exit "$new_violation"
