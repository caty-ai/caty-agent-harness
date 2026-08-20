#!/usr/bin/env bash
# Caty Agent Harness pre-destruction memory flush — Claude Code PreCompact hook (Issue #47).
# Captures only new, unverified candidates before compaction; it never blocks compaction.
set -euo pipefail
trap 'exit 0' ERR

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

extract_section() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import sys

try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except Exception:
    sys.exit(0)

heading = sys.argv[2]
capturing = False
body = []
for line in lines:
    if line.startswith("## "):
        if capturing:
            break
        capturing = line.startswith(heading)
        continue
    if capturing:
        body.append(line)
print("\n".join(body))
PY
}

extract_transcript_text() {
  tail -n 400 "$1" 2>/dev/null | python3 -c '
import json, sys

def text_from(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "") for block in content
            if isinstance(block, dict) and isinstance(block.get("text"), str)
        )
    return ""

for line in sys.stdin:
    try:
        item = json.loads(line)
    except Exception:
        continue
    message = item.get("message") if isinstance(item, dict) else None
    candidate = message if isinstance(message, dict) else item
    if not isinstance(candidate, dict):
        continue
    role = candidate.get("role") or candidate.get("type")
    if role not in ("user", "assistant"):
        continue
    text = text_from(candidate.get("content"))
    if text:
        print(text)
' 2>/dev/null || true
}

last_nonempty_paragraph() {
  python3 -c '
import sys

text = sys.stdin.read()
paragraphs = []
current = []
for raw_line in text.splitlines():
    if raw_line.strip():
        current.append(raw_line)
        continue
    if current:
        paragraphs.append("\n".join(current))
        current = []
if current:
    paragraphs.append("\n".join(current))
if paragraphs:
    sys.stdout.write(paragraphs[-1])
' 2>/dev/null || true
}

shadow_line_prefix() {
  python3 -c '
import sys

line = sys.stdin.read()
if len(line) > 120:
    line = line[:120]
sys.stdout.write(line)
' 2>/dev/null || true
}

bail_shadow_append() {
  local family=$1
  local matched_line=$2
  local shadow_log=$3
  local shadow_timestamp
  # Observer log format for Issue #107 measurements:
  # ${TMPDIR:-/tmp}/caty-agent-harness-hook/bail-shadow.log contains append-only
  # records: timestamp=<UTC ISO8601> family=<canonical_family> line=<first 120 chars>.
  # Reviewers label each record true-bail or false-positive; the measured FP rate is:
  #   false-positive records / total reviewed records (N/A when no records exist)
  # Outcomes degenerate and no_reply are observed and included in labeling; only blocked/timeout/error are suppressed.
  # There is no log rotation; manually archive the log at measurement end, with TMPDIR OS cleanup bounding growth.
  # and any promotion beyond observation-only must happen in a separate issue
  # after that measured FP rate is recorded for #107.
  shadow_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 0
  matched_line=$(printf '%s' "$matched_line" | shadow_line_prefix)
  [[ -n "$matched_line" ]] || return 0
  {
    printf 'timestamp=%s family=%s line=%s\n' \
      "$shadow_timestamp" "$family" "$matched_line"
  } 2>/dev/null >>"$shadow_log" || true
}

bail_shadow_observe() {
  local observer_outcome=$1
  local observer_text=$2
  local guard_dir=$3
  local paragraph line family
  local protected_verdict protected_ship protected_review
  local unable_to_proceed giving_up stopping_here agents_in_flight
  local check_back_later check_back_user please_deflection

  [[ "${FLH_BAIL_SHADOW:-1}" != 0 ]] || return 0
  case "$observer_outcome" in
    blocked|timeout|error) return 0 ;;
  esac

  # Tail-only scan: earlier paragraphs often quote tentative or historical phrases,
  # but the last non-empty paragraph is the strongest proxy for the final exit intent.
  paragraph=$(printf '%s' "$observer_text" | last_nonempty_paragraph)
  [[ -n "$paragraph" ]] || return 0

  # verdict_line: verifier results are protected evidence, not stop intent.
  protected_verdict='^VERDICT:[[:space:]]'
  # commit_push_pr: completed commit, push, or PR hand-offs are protected ship state.
  protected_ship='^([Pp]ushed to |[Cc]ommitted as |[Cc]ommit: |([Oo]pened|[Cc]reated|[Mm]erged|[Ss]ubmitted) (PR|P/R|pull request)( #[0-9]+|[[:space:]]|$)|([Pp]ull request|PR|P/R) #[0-9]+ (is )?(open|opened|merged|submitted|ready))'
  # ready_for_review: explicit review/merge/ship readiness is a protected hand-off.
  protected_review='^[Rr]eady (for (review|re-review)|to (review|re-review|upload|merge|ship|land))([^[:alnum:]_]|$)'

  # unable_to_proceed: the assistant explicitly says it cannot continue or finish.
  unable_to_proceed="(^I (can('?t|not)|am unable to) (proceed|continue|make (any )?progress|complete|fix this)|^(I('?m| am) )?[Rr]unning out of context)([^[:alnum:]_]|$)"
  # giving_up: the assistant directly abandons the task or calls it unactionable.
  giving_up="^(Giving up|I('?m| am) giving up|The task is not actionable)([^[:alnum:]_]|$)"
  # stopping_here: the assistant parks or pauses the current branch of work.
  stopping_here="^(Stopping here|I've stopped here|Parked (the|this) branch|Paused here)([.,;]|$| for | -| until| pending| since| because)"
  # agents_in_flight: the assistant hands off to still-running agents, jobs, or loops.
  agents_in_flight='^(([1-9][0-9]* )?(agent|cron|task|fork|job|worker|PR|check)s? (in flight|remaining|active|still (running|working)|pending|running|launched)([^[:alnum:]_]|$)|(Continuous )?([Ll]oop|[Cc]rons?|[Bb]abysit) (active|healthy|continuing|running|will keep|continues)([^[:alnum:]_]|$)|Waiting for (the )?(agent|cron|task|fork|worker|job|remaining|them)s?([^[:alnum:]_]|$)|Agents? will report back([^[:alnum:]_]|$)|Waiting\.?$)'
  # check_back_later: the assistant defers its own poll/retry to a later condition.
  check_back_later="^((I will|I'll|Will) (check back|re-?check|poll|look again|retry|re-?run|try again) (in([^[:alnum:]_]|$)|again([^[:alnum:]_]|$)|(when|once|after|until)[[:space:]]+[^[:space:]]+)|[Cc]heck back later([^[:alnum:]_]|$)|(I will|I'll|Let's) continue later([^[:alnum:]_]|$))"
  # A deferral to you/your is a legitimate input wait, not an assistant self-bail.
  check_back_user=' (when|once|after|until)[[:space:]]+(you|your)([^[:alnum:]_]|$)'
  # please_deflection: the assistant redirects execution back to the owner.
  please_deflection='^Please (start|run|provide|grant|export|add|install|configure|give me|paste|point me|set (the |up |[A-Z][A-Z0-9_]+))'

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || continue
    [[ -n "$line" ]] || continue

    if printf '%s\n' "$line" | grep -E -q -- "$unable_to_proceed" 2>/dev/null; then
      family=unable_to_proceed
    elif printf '%s\n' "$line" | grep -E -q -- "$giving_up" 2>/dev/null; then
      family=giving_up
    elif printf '%s\n' "$line" | grep -E -q -- "$stopping_here" 2>/dev/null; then
      family=stopping_here
    elif printf '%s\n' "$line" | grep -E -q -- "$agents_in_flight" 2>/dev/null; then
      family=agents_in_flight
    elif printf '%s\n' "$line" | grep -E -q -- "$check_back_later" 2>/dev/null; then
      if printf '%s\n' "$line" | grep -E -q -- "$check_back_user" 2>/dev/null; then
        continue
      fi
      family=check_back_later
    elif printf '%s\n' "$line" | grep -E -q -- "$protected_verdict" 2>/dev/null; then
      family=verdict_line
    elif printf '%s\n' "$line" | grep -E -q -- "$protected_ship" 2>/dev/null; then
      family=commit_push_pr
    elif printf '%s\n' "$line" | grep -E -q -- "$protected_review" 2>/dev/null; then
      family=ready_for_review
    elif printf '%s\n' "$line" | grep -E -q -- "$please_deflection" 2>/dev/null; then
      family=please_deflection
    else
      continue
    fi

    # These three source-panel families are deliberately observation-protected.
    # Excluding the matching line, rather than its paragraph, preserves a later
    # genuine bail signal in the same final paragraph.
    case "$family" in
      verdict_line|commit_push_pr|ready_for_review) continue ;;
    esac
    bail_shadow_append "$family" "$line" "$guard_dir/bail-shadow.log"
    return 0
  done <<<"$paragraph"
}

session_id=$(json_get session_id)
cwd=$(json_get cwd)
[[ -n "$cwd" && -d "$cwd" ]] || exit 0
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
pause_lib="$repo_root/scripts/lib-pause.sh"
[[ -f "$pause_lib" && -r "$pause_lib" && ! -L "$pause_lib" ]] || exit 0
bash -n "$pause_lib" >/dev/null 2>&1 || exit 0
# shellcheck disable=SC1090
if ! source "$pause_lib" 2>/dev/null; then
  exit 0
fi
cwd=$(caty_pause_canonical_workspace "$cwd" 2>/dev/null) || exit 0
[[ "$(caty_pause_workspace_state "$cwd")" == enabled ]] || exit 0

state_file="$cwd/STATE.md"
[[ -f "$state_file" ]] || exit 0

guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"
mkdir -p "$guard_dir" 2>/dev/null || exit 0
find "$guard_dir" -name 'flushed-*' -mtime +2 -delete 2>/dev/null || true
[[ -n "$session_id" ]] || session_id="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')
[[ -n "$session_id" ]] || session_id="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
guard="$guard_dir/flushed-$session_id"
[[ -e "$guard" ]] && exit 0
touch "$guard" 2>/dev/null || exit 0

today=$(date -u +%F) || exit 0
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ) || exit 0
trigger=$(json_get trigger)
[[ -n "$trigger" ]] || trigger=$(json_get matcher)
case "$trigger" in
  auto|manual) ;;
  *) trigger=unknown ;;
esac

lessons=$(extract_section "$state_file" '## Lessons learned')
open_failures=$(extract_section "$state_file" '## Open failures')
pending_file="$cwd/loop/pending/flush-$today.md"
previous_flush=$(cat "$pending_file" 2>/dev/null || true)
transcript_path=$(json_get transcript_path)
transcript_delta=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  transcript_delta=$(extract_transcript_text "$transcript_path")
fi
if (( ${#transcript_delta} > 30000 )); then
  transcript_delta=${transcript_delta: -30000}
fi

prompt_tmp=$(mktemp "$guard_dir/flh-flush-prompt.XXXXXX" 2>/dev/null) || exit 0
output_tmp=$(mktemp "$guard_dir/flh-flush-output.XXXXXX" 2>/dev/null) || {
  rm -f "$prompt_tmp" 2>/dev/null || true
  exit 0
}
block_tmp=$(mktemp "$guard_dir/flh-flush-block.XXXXXX" 2>/dev/null) || {
  rm -f "$prompt_tmp" "$output_tmp" 2>/dev/null || true
  exit 0
}
# shellcheck disable=SC2329
cleanup() {
  rm -f "$prompt_tmp" "$output_tmp" "$block_tmp" 2>/dev/null || true
}
trap cleanup EXIT

cat >"$prompt_tmp" <<EOF
You are a memory-flush extractor for a Caty Agent Harness workspace about to lose its context window. Below is (1) what is ALREADY captured — do not restate any of it — and (2) the recent session transcript. Extract only NEW durable observations (lessons, open failures, decisions with reasons, verified facts). Output either exactly NO_REPLY (if nothing new) or markdown bullets (- ...), one observation per bullet, each self-contained with concrete referents (paths/ids), no headers, no prose around them.
State explicitly when content was omitted.
Omitted content must not be reconstructed from memory.
Current UTC date: $today
Do not save transient environment failures or negative absolute tool claims; if a retry fixed it, save the fix. Such items go only to dated Open failures entries.

ALREADY CAPTURED: ## Lessons learned
$lessons

ALREADY CAPTURED: ## Open failures
$open_failures

ALREADY CAPTURED: today's flush file
$previous_flush

RECENT SESSION TRANSCRIPT:
$transcript_delta
EOF

flush_cmd=${FLH_FLUSH_CMD:-claude -p --bare}
read -r -a model_cmd <<<"$flush_cmd" || exit 0
(( ${#model_cmd[@]} > 0 )) || exit 0
flush_timeout=${FLH_FLUSH_TIMEOUT:-120}
set +e
timeout_bin=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)
if [[ -n "$timeout_bin" ]]; then
  if (
    cd "$guard_dir" || exit 1
    "$timeout_bin" -k 5 "$flush_timeout" "${model_cmd[@]}" <"$prompt_tmp" >"$output_tmp"
  ); then
    model_status=0
  else
    model_status=$?
  fi
else
  if timeout_marker=$(mktemp "$guard_dir/flh-flush-timeout.XXXXXX" 2>/dev/null); then
    rm -f "$timeout_marker" 2>/dev/null || true
    (
      cd "$guard_dir" || exit 1
      exec "${model_cmd[@]}" <"$prompt_tmp" >"$output_tmp"
    ) &
    model_pid=$!
    (
      sleep "$flush_timeout"
      if kill -0 "$model_pid" 2>/dev/null; then
        : >"$timeout_marker"
        kill "$model_pid" 2>/dev/null || true
        for _ in {1..10}; do
          kill -0 "$model_pid" 2>/dev/null || break
          sleep 0.5
        done
        if kill -0 "$model_pid" 2>/dev/null; then
          kill -9 "$model_pid" 2>/dev/null || true
        fi
      fi
    ) &
    watchdog_pid=$!
    if wait "$model_pid" 2>/dev/null; then
      model_status=0
    else
      model_status=$?
    fi
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    if [[ -e "$timeout_marker" && "$model_status" -ne 0 ]]; then
      model_status=124
    fi
    rm -f "$timeout_marker" 2>/dev/null || true
  else
    model_status=1
  fi
fi
set -e

outcome=ok
model_output=$(cat "$output_tmp" 2>/dev/null || true)
cleaned_output=$(printf '%s' "$model_output" | tr -d '\r' || true)
trimmed_output=$(printf '%s' "$cleaned_output" | python3 -c 'import sys; print(sys.stdin.read().strip())' 2>/dev/null || true)
if [[ "$model_status" -eq 124 ]]; then
  outcome=timeout
elif [[ "$model_status" -ne 0 ]]; then
  outcome=error
elif [[ "$trimmed_output" =~ ^[[:space:]]*[Nn][Oo]_[Rr][Ee][Pp][Ll][Yy][[:space:]]*$ ]]; then
  outcome=no_reply
else
  bullet_payload=$(grep -- '^- ' <<<"$trimmed_output" || true)
  if [[ -z "$bullet_payload" ]] || (( ${#bullet_payload} < 40 )); then
    outcome=degenerate
  fi
fi
# The outcome override is an observer-only test seam. The subshell and fail-open
# boundary prevent every observer variable or failure from reaching canonical state.
( bail_shadow_observe "${FLH_BAIL_SHADOW_OUTCOME:-$outcome}" "$trimmed_output" "$guard_dir" ) || :

pending_dir="$cwd/loop/pending"
mkdir -p "$pending_dir" 2>/dev/null || exit 0
printf '<!-- flush origin=precompact-hook session=%s ts=%s trigger=%s outcome=%s unverified=true -->\n' \
  "$session_id" "$timestamp" "$trigger" "$outcome" >"$block_tmp" || exit 0
if [[ "$outcome" == ok ]]; then
  printf '%s\n' "$bullet_payload" >>"$block_tmp" || exit 0
fi
cat "$block_tmp" >>"$pending_file" 2>/dev/null || exit 0
exit 0
