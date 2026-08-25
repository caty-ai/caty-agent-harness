#!/usr/bin/env bash
set -u

usage() {
  printf 'usage: raw-review.sh --workspace <path> [--week <YYYY-Www>] [--dry-run]\n' >&2
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-pause.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-state-fold.sh"
# The sourced fold library enables errexit for its standalone consumers. This
# command owns an explicit {0,1,2} exit map and must inspect reviewer failures.
set +e

workspace=
requested_week=
dry_run=0
usage_error=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      if [[ $# -ge 2 && -z "$workspace" ]]; then
        workspace=$2
        shift 2
      else
        usage_error=1
        break
      fi
      ;;
    --week)
      if [[ $# -ge 2 && -z "$requested_week" ]]; then
        requested_week=$2
        shift 2
      else
        usage_error=1
        break
      fi
      ;;
    --dry-run)
      if [[ "$dry_run" -eq 0 ]]; then
        dry_run=1
        shift
      else
        usage_error=1
        break
      fi
      ;;
    *)
      usage_error=1
      break
      ;;
  esac
done

if [[ -z "$workspace" ]]; then
  usage
  exit 2
fi
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || {
  usage
  exit 2
}

umask 077
promotions_dir=$workspace/loop/promotions
notify_dir=$workspace/loop/notify
pause_state=$(caty_pause_workspace_state "$workspace")
mkdir -p "$promotions_dir" "$notify_dir" || exit 2

run_started_epoch=$(date -u '+%s')
run_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
run_date=${run_ts%%T*}
run_id=$(date -u '+%Y%m%dT%H%M%SZ')-$$
mode=nightly
[[ -n "$requested_week" ]] && mode=retro
[[ "$dry_run" -eq 1 ]] && mode=dry
window=-
file_count=0
prompt_bytes=0
model_used=-
chain_pos=0
blocks=0
fabricated=0
rejected=0
candidates=0
self_review_refused=-
zero_streak=0
failing_names=-
notify_cmd=
lock_owned=0
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/raw-review.XXXXXX") || exit 2

cleanup() {
  if [[ "$lock_owned" -eq 1 ]]; then
    rm -rf "$promotions_dir/.lock"
  fi
  rm -rf "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

record_value() {
  printf '%s' "$1" | tr '[:space:]' '_' | tr -cd '[:alnum:]_.:/,@+-'
}

receipt_line() {
  printf 'ts=%s runid=%s mode=%s window=%s files=%s prompt_bytes=%s model_used=%s chain_pos=%s blocks=%s fabricated=%s rejected=%s candidates=%s self_review_refused=%s zero_streak=%s error=%s\n' \
    "$run_ts" "$run_id" "$mode" "$window" "$file_count" "$prompt_bytes" \
    "$(record_value "$model_used")" "$chain_pos" "$blocks" "$fabricated" \
    "$rejected" "$candidates" "$(record_value "$self_review_refused")" \
    "$zero_streak" "$1"
}

take_review_lock() {
  local now_epoch lock_mtime lock_age attempts=0
  while (( attempts < 3 )); do
    if mkdir "$promotions_dir/.lock" 2>/dev/null; then
      lock_owned=1
      printf '%s raw-review\n' "$$" >"$promotions_dir/.lock/pid"
      return 0
    fi
    now_epoch=$(date -u '+%s')
    lock_mtime=$(file_mtime_epoch "$promotions_dir/.lock" 2>/dev/null || printf '0\n')
    lock_age=$((now_epoch - lock_mtime))
    if (( lock_age > 1800 )); then
      rm -rf "$promotions_dir/.lock"
      continue
    fi
    attempts=$((attempts + 1))
    (( attempts < 3 )) && sleep 1
  done
  return 1
}

release_review_lock() {
  if [[ "$lock_owned" -eq 1 ]]; then
    rm -rf "$promotions_dir/.lock"
    lock_owned=0
  fi
}

run_notify_cmd() {
  local notification_file=$1
  local -a notify_argv
  local notify_bin
  [[ -n "$notify_cmd" ]] || return 0
  read -r -a notify_argv <<<"$notify_cmd" || return 0
  (( ${#notify_argv[@]} > 0 )) || return 0
  notify_bin=${notify_argv[0]}
  command -v "$notify_bin" >/dev/null 2>&1 || return 0
  "$notify_bin" "$notification_file" "${notify_argv[@]:1}" >/dev/null 2>&1 || true
}

append_notification_block() {
  local notification_file=$1
  local error_class=$2
  {
    printf '## %s runid=%s\n' "$run_ts" "$run_id"
    printf -- '- error: %s\n' "$error_class"
    printf -- '- window: %s\n' "$window"
    printf -- '- files: %s\n' "$file_count"
    printf -- '- blocks: %s\n' "$blocks"
    printf -- '- fabricated: %s\n' "$fabricated"
    printf -- '- rejected: %s\n' "$rejected"
    printf -- '- failing_entries: %s\n\n' "$failing_names"
  } >>"$notification_file"
}

finish_failure() {
  local exit_code=$1
  local error_class=$2
  local notification_file="$notify_dir/review-$run_date.md"
  if take_review_lock; then
    append_notification_block "$notification_file" "$error_class"
    receipt_line "$error_class" >>"$promotions_dir/runs.log"
    release_review_lock
  else
    error_class=lock-busy
    append_notification_block "$notification_file" "$error_class"
    # O_APPEND is the only possible receipt path after lock acquisition itself fails.
    receipt_line "$error_class" >>"$promotions_dir/runs.log"
    exit_code=1
  fi
  run_notify_cmd "$notification_file"
  exit "$exit_code"
}

if [[ "$usage_error" -eq 1 ]]; then
  usage
  finish_failure 2 config
fi

if [[ "$pause_state" != enabled ]]; then
  if take_review_lock; then
    receipt_line skipped-paused >>"$promotions_dir/runs.log"
    release_review_lock
  else
    receipt_line lock-busy >>"$promotions_dir/runs.log"
    exit 1
  fi
  exit 0
fi

conf=$workspace/loop/review.conf
if [[ ! -f "$conf" || -L "$conf" ]]; then
  finish_failure 2 config
fi
cp "$conf" "$tmp_root/review.conf"

producer=
review_window_weeks=2
reviewer_timeout_s=600
fabricated_floor=2
zero_streak_threshold=14
prompt_max_bytes=2000000
reviewer_count=0
declare -a reviewer_names reviewer_cmds
config_invalid=0
while IFS= read -r config_line || [[ -n "$config_line" ]]; do
  case "$config_line" in
    ''|'#'*) continue ;;
    producer=*) producer=${config_line#producer=} ;;
    notify_cmd=*) notify_cmd=${config_line#notify_cmd=} ;;
    review_window_weeks=*) review_window_weeks=${config_line#review_window_weeks=} ;;
    reviewer_timeout_s=*) reviewer_timeout_s=${config_line#reviewer_timeout_s=} ;;
    fabricated_floor=*) fabricated_floor=${config_line#fabricated_floor=} ;;
    zero_streak_threshold=*) zero_streak_threshold=${config_line#zero_streak_threshold=} ;;
    prompt_max_bytes=*) prompt_max_bytes=${config_line#prompt_max_bytes=} ;;
    reviewer' '*)
      read -r -a config_argv <<<"$config_line" || config_invalid=1
      if (( ${#config_argv[@]} < 3 )); then
        config_invalid=1
      else
        reviewer_names[reviewer_count]=${config_argv[1]}
        reviewer_cmds[reviewer_count]=$(printf '%s\n' "${config_argv[@]:2}" | paste -sd' ' -)
        reviewer_count=$((reviewer_count + 1))
      fi
      ;;
    *) config_invalid=1 ;;
  esac
done <"$tmp_root/review.conf"

for numeric_value in "$review_window_weeks" "$reviewer_timeout_s" "$fabricated_floor" \
  "$zero_streak_threshold" "$prompt_max_bytes"; do
  case "$numeric_value" in ''|*[!0-9]*|0) config_invalid=1 ;; esac
done
if [[ -z "$producer" || "$reviewer_count" -eq 0 || "$config_invalid" -ne 0 ]]; then
  finish_failure 2 config
fi

if [[ -n "$requested_week" ]]; then
  target_week=$requested_week
else
  target_week=$(date -u '+%G-W%V')
fi

week_list=$(
  python3 -B - "$target_week" "$review_window_weeks" <<'PY'
import datetime
import re
import sys

match = re.fullmatch(r"([0-9]{4})-W([0-9]{2})", sys.argv[1])
if not match:
    raise SystemExit(1)
year, week = map(int, match.groups())
try:
    end = datetime.date.fromisocalendar(year, week, 1)
except ValueError:
    raise SystemExit(1)
count = int(sys.argv[2])
for offset in range(count - 1, -1, -1):
    point = end - datetime.timedelta(weeks=offset)
    iso = point.isocalendar()
    print(f"{iso.year:04d}-W{iso.week:02d}")
PY
) || {
  usage
  finish_failure 2 config
}
window=$(printf '%s\n' "$week_list" | paste -sd, -)

: >"$tmp_root/files"
while IFS= read -r week; do
  [[ -n "$week" ]] || continue
  "$repo_root/scripts/raw-week.sh" --workspace "$workspace" --week "$week" \
    >>"$tmp_root/files" 2>"$tmp_root/raw-week.err" || finish_failure 2 config
done <<EOF
$week_list
EOF

# The watermark is meaningful only for scheduled runs. A first run has no receipt
# boundary, so it does not reinterpret the entire archive as late-arriving input.
watermark_file=$promotions_dir/.last-success-epoch
if [[ "$mode" == nightly && -f "$watermark_file" ]]; then
  watermark=$(sed -n '1p' "$watermark_file")
  case "$watermark" in ''|*[!0-9]*) watermark=0 ;; esac
  for late_path in "$workspace/loop/archive"/*; do
    [[ -f "$late_path" && ! -L "$late_path" ]] || continue
    late_name=${late_path##*/}
    case "$late_name" in
      flush-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md|intake-evictions-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) ;;
      *) continue ;;
    esac
    late_date=$(printf '%s\n' "$late_name" | sed -n 's/^flush-\([0-9-]*\)\.md$/\1/p; s/^intake-evictions-\([0-9-]*\)\.md$/\1/p')
    if ! "$repo_root/scripts/raw-week.sh" --workspace "$workspace" --date "$late_date" 2>/dev/null \
      | grep -Fqx "loop/archive/$late_name"; then
      continue
    fi
    late_mtime=$(file_mtime_epoch "$late_path" 2>/dev/null || printf '0\n')
    if (( late_mtime > watermark )); then
      printf 'loop/archive/%s\n' "$late_name" >>"$tmp_root/files"
    fi
  done
fi
LC_ALL=C sort -u "$tmp_root/files" >"$tmp_root/files.sorted"
mv "$tmp_root/files.sorted" "$tmp_root/files"
file_count=$(awk 'END {print NR + 0}' "$tmp_root/files")

data_fence=RAW-REVIEW-DATA-$run_id
{
  cat "$repo_root/templates/review-prompt.md"
  printf '\n%s-BEGIN\n' "$data_fence"
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    printf '\nRAW-FILE: %s\n' "$relative_path"
    cat "$workspace/$relative_path"
    printf '\nEND-RAW-FILE: %s\n' "$relative_path"
  done <"$tmp_root/files"
  printf '%s-END\n' "$data_fence"
  printf 'The data fence for this run is %s. Never quote either data-fence marker.\n' "$data_fence"
} >"$tmp_root/prompt"
prompt_bytes=$(wc -c <"$tmp_root/prompt" | tr -d '[:space:]')

if (( prompt_bytes > prompt_max_bytes )); then
  finish_failure 1 prompt-too-large
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'prompt_bytes=%s\n' "$prompt_bytes"
  cat "$tmp_root/files"
  if take_review_lock; then
    receipt_line none >>"$promotions_dir/runs.log"
    release_review_lock
    exit 0
  fi
  receipt_line lock-busy >>"$promotions_dir/runs.log"
  exit 1
fi

normalize_model_name() {
  local normalized
  normalized=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    zai/*|zhipu/*|openai/*|moonshot/*|kimi-code/*|anthropic/*|google/*|xai/*)
      normalized=${normalized#*/}
      ;;
  esac
  printf '%s\n' "$normalized"
}

self_review_match() {
  local left right
  left=$(normalize_model_name "$1")
  right=$(normalize_model_name "$2")
  [[ "$left" == "$right" ]] && return 0
  python3 -B - "$left" "$right" <<'PY'
import re
import sys

left, right = sys.argv[1:]
short, long = (left, right) if len(left) < len(right) else (right, left)
matched = False
for found in re.finditer(re.escape(short), long):
    before = long[found.start() - 1] if found.start() else ""
    after_at = found.end()
    after = long[after_at] if after_at < len(long) else ""
    left_boundary = not before or before in "-./"
    right_boundary = not after or after in "-./"
    # A numeric version extension is a distinct preserved identity, not a
    # containment alias: glm-5 must not refuse glm-5.3.
    version_extension = bool(after and re.match(r"[./-][0-9]", long[after_at:]))
    if left_boundary and right_boundary and not version_extension:
        matched = True
        break
raise SystemExit(0 if matched else 1)
PY
}

run_with_timeout() {
  local timeout_s=$1 output_file=$2
  shift 2
  local timeout_bin model_pid watchdog_pid marker status
  timeout_bin=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k 5 "$timeout_s" "$@" <"$tmp_root/prompt" >"$output_file"
    return $?
  fi
  marker=$(mktemp "$tmp_root/timeout.XXXXXX") || return 1
  rm -f "$marker"
  (exec "$@" <"$tmp_root/prompt" >"$output_file") &
  model_pid=$!
  (
    sleep "$timeout_s"
    if kill -0 "$model_pid" 2>/dev/null; then
      : >"$marker"
      kill "$model_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$model_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!
  if wait "$model_pid" 2>/dev/null; then status=0; else status=$?; fi
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  [[ -e "$marker" ]] && status=124
  rm -f "$marker"
  return "$status"
}

parse_output() {
  local output_file=$1 parse_dir=$2
  rm -rf "$parse_dir"
  mkdir -p "$parse_dir"
  python3 -B - "$output_file" "$parse_dir" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8", errors="strict").replace("\r\n", "\n")
out = Path(sys.argv[2])
begin = "RAW-REVIEW-OUTPUT-BEGIN"
end = "RAW-REVIEW-OUTPUT-END"
if source.splitlines().count(begin) != 1 or source.splitlines().count(end) != 1:
    raise SystemExit(1)
inside = source.split(begin, 1)[1].split(end, 1)[0].strip("\n")
lines = inside.splitlines()
theme_indexes = [i for i, line in enumerate(lines) if line.startswith("THEME: ")]
if not theme_indexes:
    nonblank = [line for line in lines if line.strip()]
    if nonblank != ["NO_GROUPS:"]:
        raise SystemExit(1)
    (out / "count").write_text("0\n")
    raise SystemExit(0)
if any(line.startswith("NO_GROUPS:") for line in lines) or len(theme_indexes) > 100:
    raise SystemExit(1)
if theme_indexes[0] != 0:
    raise SystemExit(1)
theme_indexes.append(len(lines))
for number in range(len(theme_indexes) - 1):
    block = lines[theme_indexes[number]:theme_indexes[number + 1]]
    fields = {}
    member_start = None
    weeks_at = None
    evidence_at = None
    promote_at = None
    if sum(line == "MEMBERS:" for line in block) != 1:
        raise SystemExit(1)
    if sum(line.startswith("WEEKS: ") for line in block) != 1:
        raise SystemExit(1)
    if sum(line.startswith("EVIDENCE: ") for line in block) != 1:
        raise SystemExit(1)
    if sum(line.startswith("PROMOTE: ") for line in block) != 1:
        raise SystemExit(1)
    for i, line in enumerate(block):
        if line == "MEMBERS:": member_start = i + 1
        elif line.startswith("WEEKS: "): weeks_at = i; fields["weeks"] = line[7:]
        elif line.startswith("EVIDENCE: "): evidence_at = i; fields["evidence"] = line[10:]
        elif line.startswith("PROMOTE: "): promote_at = i; fields["promote"] = line[9:]
    if not block[0][7:].strip() or len(block) < 6:
        raise SystemExit(1)
    if member_start is None or weeks_at is None or evidence_at is None or promote_at is None:
        raise SystemExit(1)
    if member_start != 3 or not (member_start <= weeks_at < evidence_at < promote_at == len(block) - 1):
        raise SystemExit(1)
    if len(block) < 2 or not block[1].startswith("CLASS: "):
        raise SystemExit(1)
    klass = block[1][7:]
    if klass not in {"capability-fact", "rule", "skill"}:
        raise SystemExit(1)
    if not re.fullmatch(r"[0-9]{4}-W[0-9]{2}(,[0-9]{4}-W[0-9]{2})*", fields["weeks"]):
        raise SystemExit(1)
    if fields["promote"] not in {"yes", "not-yet"}:
        raise SystemExit(1)
    evidence_lines = [fields["evidence"]] + block[evidence_at + 1:promote_at]
    if not 1 <= len(evidence_lines) <= 3 or any(not line.strip() for line in evidence_lines):
        raise SystemExit(1)
    members = block[member_start:weeks_at]
    if not members or any(not line.startswith("- ") for line in members):
        raise SystemExit(1)
    block_dir = out / f"block.{number + 1:03d}"
    block_dir.mkdir()
    (block_dir / "raw").write_text("\n".join(block) + "\n")
    (block_dir / "theme").write_text(block[0][7:].strip() + "\n")
    (block_dir / "class").write_text(klass + "\n")
    (block_dir / "model-weeks").write_text(fields["weeks"] + "\n")
    (block_dir / "promote").write_text(fields["promote"] + "\n")
    (block_dir / "evidence").write_text("\n".join(evidence_lines) + "\n")
    (block_dir / "members").write_text("\n".join(line[2:] for line in members) + "\n")
(out / "count").write_text(str(len(theme_indexes) - 1) + "\n")
PY
}

validate_parsed_blocks() {
  local parse_dir=$1 accepted_dir=$2 rejects_file=$3
  local block_dir member basename quote source_path normalized_quote normalized_source
  local block_bad member_week member_hash
  rm -rf "$accepted_dir"
  mkdir -p "$accepted_dir"
  : >"$rejects_file"
  blocks=$(cat "$parse_dir/count")
  fabricated=0
  rejected=0
  candidates=0
  for block_dir in "$parse_dir"/block.*; do
    [[ -d "$block_dir" ]] || continue
    block_bad=0
    : >"$block_dir/validated-members"
    : >"$block_dir/member-hashes"
    : >"$block_dir/current-weeks"
    while IFS= read -r member || [[ -n "$member" ]]; do
      basename=${member%%:*}
      quote=${member#*:}
      if [[ "$basename" == "$member" || -z "$quote" || ${#quote} -gt 200 \
        || "$quote" == *...* || "$quote" == *…* ]]; then
        block_bad=1
        continue
      fi
      case "$basename" in
        flush-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md|intake-evictions-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) ;;
        *) block_bad=1; continue ;;
      esac
      source_path=
      while IFS= read -r selected_path; do
        if [[ "${selected_path##*/}" == "$basename" ]]; then
          source_path=$selected_path
          break
        fi
      done <"$tmp_root/files"
      if [[ -z "$source_path" ]]; then
        block_bad=1
        continue
      fi
      normalized_quote=$(normalize_state_candidate_key_text "$quote") || {
        block_bad=1
        continue
      }
      citation_found=0
      while IFS= read -r source_line || [[ -n "$source_line" ]]; do
        normalized_source=$(normalize_state_candidate_key_text "$source_line") || continue
        if [[ "$normalized_source" == "$normalized_quote"* ]]; then
          citation_found=1
          break
        fi
      done <"$workspace/$source_path"
      if [[ "$citation_found" -ne 1 ]]; then
        block_bad=1
        continue
      fi
      member_week=$(python3 -B - "$basename" <<'PY'
import datetime
import re
import sys
m = re.fullmatch(r"(?:flush|intake-evictions)-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md", sys.argv[1])
if not m:
    raise SystemExit(1)
d = datetime.date.fromisoformat(m.group(1)).isocalendar()
print(f"{d.year:04d}-W{d.week:02d}")
PY
) || {
        block_bad=1
        continue
      }
      member_hash=$(sha256_text "$normalized_quote") || {
        block_bad=1
        continue
      }
      printf '%s:%s\n' "$basename" "$quote" >>"$block_dir/validated-members"
      printf '%s\n' "$member_hash" >>"$block_dir/member-hashes"
      printf '%s\n' "$member_week" >>"$block_dir/current-weeks"
    done <"$block_dir/members"
    if [[ "$block_bad" -ne 0 ]]; then
      fabricated=$((fabricated + 1))
      rejected=$((rejected + 1))
      cat "$block_dir/raw" >>"$rejects_file"
      printf '\n' >>"$rejects_file"
      continue
    fi
    LC_ALL=C sort -u "$block_dir/current-weeks" >"$block_dir/current-weeks.sorted"
    mv "$block_dir/current-weeks.sorted" "$block_dir/current-weeks"
    cp -R "$block_dir" "$accepted_dir/"
    candidates=$((candidates + 1))
  done
  threshold=$(( (blocks + 4) / 5 ))
  (( threshold < fabricated_floor )) && threshold=$fabricated_floor
  (( fabricated < threshold ))
}

: >"$tmp_root/all-rejects"
successful_review=0
index=0
while (( index < reviewer_count )); do
  reviewer_name=${reviewer_names[$index]}
  chain_pos=$((index + 1))
  if self_review_match "$producer" "$reviewer_name"; then
    refusal="$producer/$reviewer_name"
    if [[ "$self_review_refused" == - ]]; then
      self_review_refused=$refusal
    else
      self_review_refused=$self_review_refused,$refusal
    fi
    if [[ "$failing_names" == - ]]; then failing_names=$reviewer_name; else failing_names=$failing_names,$reviewer_name; fi
    printf 'self_review_refused=%s/%s\n' "$producer" "$reviewer_name" >&2
    index=$((index + 1))
    continue
  fi
  read -r -a reviewer_argv <<<"${reviewer_cmds[$index]}" || reviewer_argv=()
  reviewer_output="$tmp_root/reviewer.$chain_pos.out"
  if (( ${#reviewer_argv[@]} == 0 )) || ! command -v "${reviewer_argv[0]}" >/dev/null 2>&1; then
    reviewer_status=127
  else
    if run_with_timeout "$reviewer_timeout_s" "$reviewer_output" "${reviewer_argv[@]}"; then
      reviewer_status=0
    else
      reviewer_status=$?
    fi
  fi
  if [[ "$reviewer_status" -ne 0 || ! -s "$reviewer_output" ]]; then
    printf 'reviewer_failed=%s status=%s\n' "$reviewer_name" "$reviewer_status" >&2
    if [[ "$failing_names" == - ]]; then failing_names=$reviewer_name; else failing_names=$failing_names,$reviewer_name; fi
    index=$((index + 1))
    continue
  fi
  if ! parse_output "$reviewer_output" "$tmp_root/parsed"; then
    printf 'reviewer_failed=%s reason=grammar\n' "$reviewer_name" >&2
    if [[ "$failing_names" == - ]]; then failing_names=$reviewer_name; else failing_names=$failing_names,$reviewer_name; fi
    index=$((index + 1))
    continue
  fi
  if ! validate_parsed_blocks "$tmp_root/parsed" "$tmp_root/accepted" "$tmp_root/rejects"; then
    cat "$tmp_root/rejects" >>"$tmp_root/all-rejects"
    printf 'reviewer_failed=%s reason=fabrication-threshold\n' "$reviewer_name" >&2
    if [[ "$failing_names" == - ]]; then failing_names=$reviewer_name; else failing_names=$failing_names,$reviewer_name; fi
    index=$((index + 1))
    continue
  fi
  cat "$tmp_root/rejects" >>"$tmp_root/all-rejects"
  model_used=$reviewer_name
  successful_review=1
  break
done

if [[ "$successful_review" -ne 1 ]]; then
  [[ -s "$tmp_root/all-rejects" ]] && cp "$tmp_root/all-rejects" "$promotions_dir/candidates-$run_id.rejects.md"
  finish_failure 1 chain-exhausted
fi

candidate_file=$promotions_dir/candidates-$run_id.md
rejects_file=$promotions_dir/candidates-$run_id.rejects.md
if ! take_review_lock; then
  finish_failure 1 lock-busy
fi

set -o noclobber
: >"$candidate_file" 2>/dev/null || {
  set +o noclobber
  release_review_lock
  finish_failure 1 lock-busy
}
: >"$rejects_file" 2>/dev/null || {
  set +o noclobber
  release_review_lock
  finish_failure 1 lock-busy
}
set +o noclobber
cat "$tmp_root/all-rejects" >>"$rejects_file"
printf '# Raw review candidates\n\nrunid: %s\nreviewer: %s\n\n' "$run_id" "$model_used" >>"$candidate_file"

candidate_number=0
for block_dir in "$tmp_root/accepted"/block.*; do
  [[ -d "$block_dir" ]] || continue
  candidate_number=$((candidate_number + 1))
  theme_id=$(printf 'theme-%s-%03d' "$run_id" "$candidate_number")
  theme=$(sed -n '1p' "$block_dir/theme")
  class=$(sed -n '1p' "$block_dir/class")
  requested_promote=$(sed -n '1p' "$block_dir/promote")
  current_weeks=$(paste -sd, "$block_dir/current-weeks")
  current_k=$(awk 'END {print NR + 0}' "$block_dir/current-weeks")
  host_promote=$requested_promote
  if [[ "$requested_promote" == yes && "$current_k" -lt 2 ]]; then
    host_promote=not-yet
  fi
  supersedes=
  union_weeks=$current_weeks
  if [[ -f "$promotions_dir/ledger.md" ]]; then
    while IFS= read -r member_hash; do
      [[ -n "$member_hash" ]] || continue
      matched_id=$(awk -v wanted="$member_hash" '
        /^## theme-/ {current = substr($0, 4)}
        $0 == "member-hash: " wanted {matched = current}
        END {print matched}
      ' "$promotions_dir/ledger.md")
      if [[ -n "$matched_id" ]]; then
        supersedes=$matched_id
      fi
    done <"$block_dir/member-hashes"
  fi
  if [[ -n "$supersedes" ]]; then
    prior_weeks=$(awk -v wanted="$supersedes" '
      $0 == "## " wanted {inside = 1; next}
      inside && /^## / {exit}
      inside && /^weeks: / {sub(/^weeks: /, ""); print; exit}
    ' "$promotions_dir/ledger.md")
    union_weeks=$(printf '%s\n' "$prior_weeks" "$current_weeks" | tr ',' '\n' | sed '/^$/d' | LC_ALL=C sort -u | paste -sd, -)
  fi
  union_k=$(printf '%s\n' "$union_weeks" | tr ',' '\n' | sed '/^$/d' | awk 'END {print NR + 0}')
  {
    printf '## %s\n' "$theme_id"
    printf 'theme: %s\n' "$theme"
    printf 'class: %s\n' "$class"
    printf 'reviewer: %s\n' "$model_used"
    printf 'run-weeks: %s\n' "$current_weeks"
    printf 'run-k: %s\n' "$current_k"
    printf 'promote: %s\n' "$host_promote"
    [[ -n "$supersedes" ]] && printf 'supersedes: %s\n' "$supersedes"
    printf 'weeks: %s\n' "$union_weeks"
    printf 'union-k: %s\n' "$union_k"
    printf 'members:\n'
    while IFS= read -r member; do printf -- '- %s\n' "$member"; done <"$block_dir/validated-members"
    while IFS= read -r member_hash; do printf 'member-hash: %s\n' "$member_hash"; done <"$block_dir/member-hashes"
    printf 'evidence: |\n'
    sed 's/^/  /' "$block_dir/evidence"
    printf '\n'
  } >>"$candidate_file"
  {
    printf '## %s\n' "$theme_id"
    printf 'runid: %s\n' "$run_id"
    printf 'theme: %s\n' "$theme"
    printf 'class: %s\n' "$class"
    printf 'reviewer: %s\n' "$model_used"
    printf 'run-weeks: %s\n' "$current_weeks"
    printf 'run-k: %s\n' "$current_k"
    printf 'promote: %s\n' "$host_promote"
    [[ -n "$supersedes" ]] && printf 'supersedes: %s\n' "$supersedes"
    printf 'weeks: %s\n' "$union_weeks"
    printf 'union-k: %s\n' "$union_k"
    printf 'members:\n'
    while IFS= read -r member; do printf -- '- %s\n' "$member"; done <"$block_dir/validated-members"
    while IFS= read -r member_hash; do printf 'member-hash: %s\n' "$member_hash"; done <"$block_dir/member-hashes"
    printf '\n'
  } >>"$promotions_dir/ledger.md"
done

zero_file=$promotions_dir/.zero-streak
if [[ -f "$zero_file" ]]; then
  zero_streak=$(sed -n '1p' "$zero_file")
  case "$zero_streak" in ''|*[!0-9]*) zero_streak=0 ;; esac
fi
distinct_input_weeks=$(
  while IFS= read -r relative_path; do
    basename=${relative_path##*/}
    python3 -B - "$basename" <<'PY'
import datetime, re, sys
m = re.fullmatch(r"(?:flush|intake-evictions)-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md", sys.argv[1])
if m:
    iso = datetime.date.fromisoformat(m.group(1)).isocalendar()
    print(f"{iso.year:04d}-W{iso.week:02d}")
PY
  done <"$tmp_root/files" | LC_ALL=C sort -u | awk 'END {print NR + 0}'
)
streak_notify=0
if [[ "$mode" == nightly && "$file_count" -gt 0 && "$distinct_input_weeks" -ge 2 ]]; then
  if [[ "$candidates" -eq 0 ]]; then
    zero_streak=$((zero_streak + 1))
    if (( zero_streak % zero_streak_threshold == 0 )); then streak_notify=1; fi
  else
    zero_streak=0
  fi
  printf '%s\n' "$zero_streak" >"$tmp_root/zero-streak"
  mv "$tmp_root/zero-streak" "$zero_file"
fi
if [[ "$mode" == nightly ]]; then
  printf '%s\n' "$run_started_epoch" >"$tmp_root/watermark"
  mv "$tmp_root/watermark" "$watermark_file"
fi
receipt_line none >>"$promotions_dir/runs.log"
if [[ "$streak_notify" -eq 1 ]]; then
  notification_file=$notify_dir/review-$run_date.md
  failing_names=zero-streak-threshold
  append_notification_block "$notification_file" zero-streak
fi
release_review_lock
if [[ "$streak_notify" -eq 1 ]]; then
  run_notify_cmd "$notification_file"
fi
exit 0
