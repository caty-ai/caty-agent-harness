#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: sentinel-cron.sh --workspace <ws>\n' >&2
}

workspace=

while (($# > 0)); do
  case "$1" in
    --workspace)
      if (($# < 2)); then
        usage
        exit 2
      fi
      workspace=$2
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$workspace" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$workspace" ]]; then
  usage
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repo_root/scripts/lib-pause.sh"
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || {
  usage
  exit 2
}
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" openclaw-sentinel-cron
  exit 0
fi
install_script="$repo_root/install.sh"
notice_file=${SENTINEL_INBOX_FILE:-$workspace/loop/pending/sentinel-notice.md}
marker_line="# fable-loop sentinel notice v1"

if [[ ! -x "$install_script" ]]; then
  printf 'sentinel infra error: install.sh missing or not executable: %s\n' "$install_script" >&2
  exit 3
fi

tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$tmp_root/sentinel-cron.XXXXXX")
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

set +e
"$install_script" --check --workspace "$workspace" >"$work_dir/check.out" 2>&1
check_status=$?
set -e

{ grep -E '^(warning:|missing )' "$work_dir/check.out" || true; } >"$work_dir/findings"

if [[ "$check_status" -ne 0 || -s "$work_dir/findings" ]]; then
  if [[ ! -d "$(dirname "$notice_file")" ]]; then
    printf 'sentinel infra error: notice directory missing: %s\n' "$(dirname "$notice_file")" >&2
    exit 3
  fi
  if [[ ! -s "$work_dir/findings" ]]; then
    printf 'install.sh --check exited %s without warning/missing output\n' "$check_status" >"$work_dir/findings"
  fi

  existing_findings="$work_dir/existing-findings"
  marker_count=0
  if [[ -f "$notice_file" ]]; then
    marker_count=$(grep -Fxc "$marker_line" "$notice_file" 2>/dev/null || true)
  fi

  if [[ "$marker_count" -eq 1 ]]; then
    awk '
      index($0, "## Findings") == 1 {in_findings = 1; next}
      in_findings {print}
    ' "$notice_file" >"$existing_findings"
  else
    : >"$existing_findings"
  fi

  if [[ -f "$notice_file" ]] \
    && [[ "$marker_count" -eq 1 ]] \
    && cmp -s "$work_dir/findings" "$existing_findings"; then
    exit 0
  fi

  tmp_notice="$work_dir/sentinel-notice.md"
  {
    printf '%s\n' "$marker_line"
    printf 'UTC timestamp: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '\n'
    printf '## Findings\n'
    cat "$work_dir/findings"
  } >"$tmp_notice"
  mv "$tmp_notice" "$notice_file"
else
  if [[ -e "$notice_file" ]]; then
    rm -f "$notice_file"
  fi
fi

exit 0
