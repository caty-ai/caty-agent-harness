#!/usr/bin/env bash
# Caty Agent Harness CHECKPOINT enforcement — Claude Code Stop hook (DESIGN §4.1, Issue #7).
# Fires when the assistant ends a turn in a Caty Agent Harness workspace that has STATE.md
# and files changed after STATE.md was last written: blocks once per session with a
# reminder to CHECKPOINT. Exits 0 (silent) in every other case.
# Known accepted false positive (GLM review 2026-07-04): git checkout/rebase rewrites
# tree mtimes and can trigger one spurious nag — bounded to once per session by the
# guard; the message tells the assistant it may decline explicitly.
set -euo pipefail

# A guard hook must never crash the chain: bail silently without python3.
command -v python3 >/dev/null 2>&1 || exit 0

input=$(cat || true)
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

# Nudge at most once per session (state kept outside the workspace). If we cannot
# record the guard we must not block at all — a nag on every turn is worse than none.
guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"
mkdir -p "$guard_dir" 2>/dev/null || exit 0
find "$guard_dir" -name 'nagged-*' -mtime +2 -delete 2>/dev/null || true
[[ -n "$session_id" ]] || session_id="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
guard="$guard_dir/nagged-$session_id"
[[ -e "$guard" ]] && exit 0

# Task evidence: any workspace file changed after STATE.md was last written,
# excluding VCS/session noise and the loop's own machinery.
newer=$(find "$cwd" -type f -newer "$state_file" \
  ! -path "*/.git/*" ! -path "*/.omc/*" ! -path "*/.omx/*" ! -path "*/.claude/*" \
  ! -path "*/loop/*" ! -path "*/node_modules/*" ! -name "STATE.md" \
  -print -quit 2>/dev/null || true)
[[ -n "$newer" ]] || exit 0

touch "$guard" 2>/dev/null || exit 0
mkdir -p "$cwd/loop/pending" 2>/dev/null || true
flush_file="$cwd/loop/pending/flush-$(date -u +%F).md"
flush_stamp_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
stamp_sid=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')
[[ -n "$stamp_sid" ]] || stamp_sid="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
cat >&2 <<EOF
caty-agent-harness CHECKPOINT: workspace files changed after STATE.md was last written (e.g. ${newer#"$cwd"/}).
Before ending the session, update '## Last session' in STATE.md (task id / next action / blockers / last verified artifact path) and fold any new observations into the right sections. If this turn genuinely produced nothing checkpoint-worthy, state that explicitly and continue — this reminder fires at most once per session.

Also append only genuinely NEW, delta-only observations to '$flush_file': first read '## Lessons learned' and '## Open failures' in STATE.md and today's flush file (if any) as already captured. If appending, prefix the block with '<!-- flush origin=stop-hook-demand session=$stamp_sid ts=$flush_stamp_ts outcome=ok unverified=true -->'. NO_REPLY is legal: if nothing new exists, say so explicitly instead of writing. Flush is Lessons-only: violations and open failures go directly to dated entries in STATE.md '## Open failures', never into the flush file. Never flush bullets asserting preferences, judgments, or facts about the owner, family members, or the agent's own identity or values; route those to '## Open failures' or a human. Never fold flush entries into '## Lessons learned' or '## Open failures' yourself — only the intake job folds them, later, through its gates. Do not capture transient environment failures or negative absolute tool claims; if a retry fixed it, capture the fix.
State explicitly when content was omitted.
Omitted content must not be reconstructed from memory.
EOF
exit 2
