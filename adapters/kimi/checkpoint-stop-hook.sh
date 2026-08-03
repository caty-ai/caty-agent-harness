#!/usr/bin/env bash
# fable-loop CHECKPOINT enforcement — Kimi Code CLI Stop hook (DESIGN §4.1, Issue #93).
# Fires when the model is about to end a turn in a workspace that has a fable-loop
# STATE.md and files changed after STATE.md was last written: asks once per session
# to CHECKPOINT. Exits 0 silently in every other case.
#
# Same core logic as the Claude Code reference (adapters/claude-code/checkpoint-stop-hook.sh);
# runtime contract notes:
#   - Input: Kimi pipes the Stop payload as JSON on stdin with snake_case keys
#     (hook_event_name / session_id / cwd), the same keys the Claude Code hook reads.
#     We fall back to $1 when stdin is empty for defensiveness.
#   - Block: Kimi's Stop event is blockable via exit code 2; the reason on stderr is
#     appended so the model continues (identical to Claude Code's contract).
#   - Loop guard: Kimi's Stop payload has NO stop_hook_active field, so the once-per-
#     session guard file is the loop protection — after the first ask, the second Stop
#     in the same session finds the guard and exits 0. (We still honor stop_hook_active
#     if a future Kimi adds it; reading a missing key is a harmless no-op.)
#   - fail-open: exit 0 (or any code other than 2) means allow, so any environment
#     problem degrades to silence, never a crash or a block.
# Known accepted false positive (mirrors claude-code): git checkout/rebase rewrites
# tree mtimes and can trigger one spurious ask — bounded to once per session; the
# message tells the model it may decline explicitly.
set -euo pipefail

# A guard hook must never crash the chain: bail silently without python3.
command -v python3 >/dev/null 2>&1 || exit 0

# Kimi delivers the payload on stdin; fall back to argv[1] defensively.
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

# Never re-block a continuation already forced by a Stop hook. Kimi does not send this
# field today (the guard file below is the real loop protection), but honor it if present.
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
guard="$guard_dir/nagged-kimi-$session_id"
[[ -e "$guard" ]] && exit 0

# Task evidence: any workspace file changed after STATE.md was last written,
# excluding VCS/session noise and the loop's own machinery.
newer=$(find "$cwd" -type f -newer "$state_file" \
  ! -path "*/.git/*" ! -path "*/.omc/*" ! -path "*/.omx/*" ! -path "*/.claude/*" \
  ! -path "*/.kimi-code/*" ! -path "*/loop/*" ! -path "*/node_modules/*" ! -name "STATE.md" \
  -print -quit 2>/dev/null || true)
[[ -n "$newer" ]] || exit 0

mkdir -p "$cwd/loop/pending" 2>/dev/null || true
flush_file="$cwd/loop/pending/flush-$(date -u +%F).md"
flush_stamp_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
stamp_sid=$session_id
touch "$guard" 2>/dev/null || exit 0
cat >&2 <<EOF
fable-loop CHECKPOINT: workspace files changed after STATE.md was last written (e.g. ${newer#"$cwd"/}).
Before ending the session, update '## Last session' in STATE.md (task id / next action / blockers / last verified artifact path) and fold any new observations into the right sections. If this turn genuinely produced nothing checkpoint-worthy, state that explicitly and continue — this reminder fires at most once per session.

Also append only genuinely NEW, delta-only observations to '$flush_file': first read '## Lessons learned' and '## Open failures' in STATE.md and today's flush file (if any) as already captured. If appending, prefix the block with '<!-- flush origin=stop-hook-demand session=$stamp_sid ts=$flush_stamp_ts outcome=ok unverified=true -->'. NO_REPLY is legal: if nothing new exists, say so explicitly instead of writing. Flush entries are unverified candidates; never fold them directly into '## Lessons learned' or '## Open failures' — normal distill gates apply later at intake. Do not capture transient environment failures or negative absolute tool claims; if a retry fixed it, capture the fix. Violation-shaped items go only to dated Open failures entries.
EOF
exit 2
