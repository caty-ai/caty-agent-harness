#!/usr/bin/env bash
# fable-loop CHECKPOINT enforcement — Codex CLI Stop hook (DESIGN §4.1, Issue #93).
# Fires when the agent ends a turn in a workspace that has a fable-loop STATE.md
# and files changed after STATE.md was last written: asks once per session to
# CHECKPOINT. Exits 0 silently in every other case.
#
# Same core logic as the Claude Code reference (adapters/claude-code/checkpoint-stop-hook.sh);
# only the runtime contract differs:
#   - Input: Codex pipes the Stop payload as JSON on stdin with snake_case keys
#     (session_id / cwd / stop_hook_active / transcript_path / hook_event_name / ...),
#     the same keys the Claude Code hook reads. A legacy Codex delivered the JSON as
#     argv instead, so we fall back to $1 when stdin is empty.
#   - Block: Codex blocks a turn-end by printing {"decision":"block","reason":"..."}
#     on stdout and exiting 0 — the reason becomes an automatic continuation prompt.
#     (Claude Code instead uses exit 2 + stderr.) Plain-text stdout is invalid for a
#     Codex Stop hook, so we emit JSON or nothing.
#   - Loop guard: Codex sets stop_hook_active=true on the continuation it created, and
#     the once-per-session guard file backs it up, so we never re-block a continuation.
# Known accepted false positive (mirrors claude-code): git checkout/rebase rewrites
# tree mtimes and can trigger one spurious ask — bounded to once per session; the
# message tells the agent it may decline explicitly.
set -euo pipefail

# A guard hook must never crash the chain: bail silently without python3.
command -v python3 >/dev/null 2>&1 || exit 0

# Codex delivers the payload on stdin; a legacy build passed it as argv[1].
if [ -t 0 ]; then input=""; else input=$(cat || true); fi
[[ -n "$input" ]] || input=${1:-}
[[ -n "$input" ]] || exit 0

json_get() {
  printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get(sys.argv[1], "")
print(str(v))
' "$1" 2>/dev/null || true
}

# Never re-block a continuation that a Stop hook already forced (loop guard).
case "$(json_get stop_hook_active)" in
  True|true|1) exit 0 ;;
esac

session_id=$(json_get session_id)
session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')
cwd=$(json_get cwd)
[[ -n "$cwd" && -d "$cwd" ]] || exit 0
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
pause_lib="$repo_root/scripts/lib-pause.sh"
[[ -f "$pause_lib" && -r "$pause_lib" && ! -L "$pause_lib" ]] || exit 0
bash -n "$pause_lib" >/dev/null 2>&1 || exit 0
if ! source "$pause_lib" 2>/dev/null; then
  exit 0
fi
cwd=$(caty_pause_canonical_workspace "$cwd" 2>/dev/null) || exit 0
[[ "$(caty_pause_workspace_state "$cwd")" == enabled ]] || exit 0

state_file="$cwd/STATE.md"
[[ -f "$state_file" ]] || exit 0

# Ask at most once per session (state kept outside the workspace). If we cannot
# record the guard we must not block at all — an ask on every turn is worse than none.
guard_dir="${TMPDIR:-/tmp}/fable-loop-hook"
mkdir -p "$guard_dir" 2>/dev/null || exit 0
find "$guard_dir" -name 'nagged-*' -mtime +2 -delete 2>/dev/null || true
[[ -n "$session_id" ]] || session_id="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
guard="$guard_dir/nagged-codex-$session_id"
[[ -e "$guard" ]] && exit 0

# Task evidence: any workspace file changed after STATE.md was last written,
# excluding VCS/session noise and the loop's own machinery.
newer=$(find "$cwd" -type f -newer "$state_file" \
  ! -path "*/.git/*" ! -path "*/.omc/*" ! -path "*/.omx/*" ! -path "*/.claude/*" \
  ! -path "*/.codex/*" ! -path "*/loop/*" ! -path "*/node_modules/*" ! -name "STATE.md" \
  -print -quit 2>/dev/null || true)
[[ -n "$newer" ]] || exit 0

mkdir -p "$cwd/loop/pending" 2>/dev/null || true
flush_file="$cwd/loop/pending/flush-$(date -u +%F).md"
flush_stamp_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
stamp_sid=$session_id

reason_tmp=$(mktemp "$guard_dir/flh-codex-reason.XXXXXX") || exit 0
cat >"$reason_tmp" <<EOF || { rm -f "$reason_tmp"; exit 0; }
fable-loop CHECKPOINT: workspace files changed after STATE.md was last written (e.g. ${newer#"$cwd"/}).
Before ending the session, update '## Last session' in STATE.md (task id / next action / blockers / last verified artifact path) and fold any new observations into the right sections. If this turn genuinely produced nothing checkpoint-worthy, state that explicitly and continue — this reminder fires at most once per session.

Also append only genuinely NEW, delta-only observations to '$flush_file': first read '## Lessons learned' and '## Open failures' in STATE.md and today's flush file (if any) as already captured. If appending, prefix the block with '<!-- flush origin=stop-hook-demand session=$stamp_sid ts=$flush_stamp_ts outcome=ok unverified=true -->'. NO_REPLY is legal: if nothing new exists, say so explicitly instead of writing. Flush entries are unverified candidates; never fold them directly into '## Lessons learned' or '## Open failures' — normal distill gates apply later at intake. Do not capture transient environment failures or negative absolute tool claims; if a retry fixed it, capture the fix. Violation-shaped items go only to dated Open failures entries.
EOF

# Codex Stop contract: block by printing a decision JSON on stdout and exiting 0.
# If we cannot encode the JSON, fail open (exit 0, no block) rather than crash.
decision=$(python3 -c \
  'import json,sys; print(json.dumps({"decision":"block","reason":open(sys.argv[1], encoding="utf-8").read()}))' \
  "$reason_tmp" 2>/dev/null) || { rm -f "$reason_tmp"; exit 0; }
rm -f "$reason_tmp"
[[ -n "$decision" ]] || exit 0
touch "$guard" 2>/dev/null || exit 0
printf '%s\n' "$decision"
exit 0
