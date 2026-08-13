#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: flush-intake.sh <workspace-dir>\n' >&2
}

[[ $# -eq 1 && -d "$1" ]] || {
  usage
  exit 2
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-pause.sh"
workspace=$(caty_pause_canonical_workspace "$1" 2>/dev/null) || {
  usage
  exit 2
}
CATY_INTAKE_ADAPTER=hermes
adapter_identity="${CATY_INTAKE_ADAPTER}-flush-intake"
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" "$adapter_identity"
  exit 0
fi

# shellcheck disable=SC1091
CATY_INTAKE_GUARDED_ENTRY=1
source "$repo_root/scripts/flush-intake.sh"
