#!/usr/bin/env bash
# shellcheck shell=bash
# Shared flush-intake core. Adapter entry points validate and pause-guard the
# workspace before sourcing this file.

(return 0 2>/dev/null) || {
  printf 'flush-intake core must be sourced from a guarded adapter entry\n' >&2
  exit 2
}
[[ "${CATY_INTAKE_GUARDED_ENTRY:-}" == 1 ]] || {
  printf 'flush-intake core must be sourced from a guarded adapter entry\n' >&2
  exit 2
}

usage() {
  printf 'Usage: flush-intake.sh <workspace-dir>\n' >&2
}

parse_flush_file() {
  local file=$1
  local is_today=$2
  local torn_today=$3

  LC_ALL=C tr -d '\000-\010\013-\037' <"$file" \
    | LC_ALL=C awk -v is_today="$is_today" -v torn_today="$torn_today" \
    -v max_bullet_bytes="$max_bullet_bytes" '
    function valid_date(value, parts) {
      if (value !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
      split(value, parts, "-")
      return parts[2] >= 1 && parts[2] <= 12 && parts[3] >= 1 && parts[3] <= 31
    }
    function parse_header(    count,fields,i,value) {
      block_date = ""
      outcome = ""
      count = split(header, fields, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (fields[i] ~ /^ts=/) {
          value = fields[i]
          sub(/^ts=/, "", value)
          if (length(value) >= 10 && valid_date(substr(value, 1, 10))) {
            block_date = substr(value, 1, 10)
          }
        } else if (fields[i] ~ /^outcome=/) {
          value = fields[i]
          sub(/^outcome=/, "", value)
          if (value ~ /^[A-Za-z0-9_-]+$/) outcome = value
        }
      }
      valid = (block_date != "" && outcome != "")
    }
    function emit_block(final_block,    i) {
      if (!have_header) return
      if (final_block && is_today && torn_today) {
        if (valid && outcome == "ok") {
          for (i = 1; i <= bullet_count; i++) {
            printf "D%c%s%c%s%c%s\n", 28, block_date, 28, bullets[i], 28, header
          }
        }
      } else if (!valid) {
        print "M"
      } else if (outcome == "ok") {
        for (i = 1; i <= bullet_count; i++) {
          printf "C%c%s%c%s%c%s\n", 28, block_date, 28, bullets[i], 28, header
        }
      }
      delete bullets
      bullet_count = 0
    }
    {
      line = $0
      if (line ~ /^<!--[[:space:]]*flush[[:space:]]/) {
        emit_block(0)
        header = line
        have_header = 1
        bullet_count = 0
        parse_header()
        if (valid) saw_valid_header = 1
        print "B"
        next
      }
      if (line ~ /^[[:space:]]*[-*+][[:space:]]+/) {
        text = line
        sub(/^[[:space:]]*[-*+][[:space:]]+/, "", text)
        sub(/[[:space:]]+$/, "", text)
        if (!saw_valid_header) {
          print "H"
        } else if (valid && outcome == "ok" && text != "") {
          if (length(text) > max_bullet_bytes) {
            print "O"
          } else {
            bullets[++bullet_count] = text
          }
        }
      }
    }
    END {emit_block(1)}
  '
}

write_receipt() {
  local lock_status=$1
  local marker_status=$2
  local timestamp

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  printf 'ts=%s files_scanned=%s blocks=%s candidates=%s folded=%s deduped=%s evicted_by_cap=%s eviction_archive=%s dropped_oversize=%s deferred=%s headerless_bullets=%s torn_lines=%s quarantined=%s lock=%s marker=%s error=%s%s\n' \
    "$timestamp" "$files_scanned" "$blocks" "$candidates" "$folded" "$deduped" \
    "$evicted_by_cap" "$eviction_archive" "$dropped_oversize" "$deferred" \
    "$headerless_bullets" "$torn_lines" \
    "$quarantined" "$lock_status" "$marker_status" "$receipt_error" "$quarantined_paths" \
    >>"$receipt_file"
}

snapshot_evicted_lessons() {
  local source_state=$1
  local additions=$2
  local cap=$3
  local destination=$4

  awk -v additions="$additions" -v cap="$cap" '
    /^## / {
      if (in_lessons) exit
      if (index($0, "## Lessons learned") == 1) {
        in_lessons = 1
      }
      next
    }
    in_lessons {lines[++count] = $0}
    END {
      while ((getline line < additions) > 0) {
        lines[++count] = line
      }
      close(additions)
      evicted = count - cap
      for (i = 1; i <= evicted; i++) print lines[i]
    }
  ' "$source_state" >"$destination"
}

consider_candidate() {
  local candidate_date=$1
  local text=$2
  local target=$3
  local source_header=$4
  local section
  local line
  local task_id
  local lesson_hash
  local composite_key
  local normalized_target
  local candidate_reply="$work_dir/candidate.reply"
  local annotated_reply="$work_dir/candidate.annotated"
  local split_lessons="$work_dir/candidate.lessons"
  local split_failures="$work_dir/candidate.failures"

  candidates=$((candidates + 1))
  if (( budget_used >= max_fold )); then
    deferred=$((deferred + 1))
    return 1
  fi

  task_id=$(sha256_text "$source_header")
  line="- $candidate_date $text (source: flush-intake)"
  if [[ "$target" == lessons ]]; then
    section=LESSONS
  else
    section=OPEN_FAILURES
  fi
  printf '## %s\n%s\n' "$section" "$line" >"$candidate_reply"
  : >"$annotated_reply"
  : >"$split_lessons"
  : >"$split_failures"
  annotate_reply_dedup_keys "$candidate_reply" "$task_id" "$annotated_reply" \
    '(source: flush-intake)' 'LESSONS|OPEN_FAILURES'
  split_annotated_reply_sections "$annotated_reply" "$split_lessons" "$split_failures" \
    '(source: flush-intake)' 'LESSONS|OPEN_FAILURES'
  if [[ "$target" == lessons ]]; then
    IFS=$'\t' read -r composite_key line <"$split_lessons"
  else
    IFS=$'\t' read -r composite_key line <"$split_failures"
  fi
  lesson_hash=${composite_key##*:}
  if [[ "$target" == lessons ]]; then
    normalized_target=$normalized_lessons_state
  else
    normalized_target=$normalized_failures_state
  fi

  if state_fold_candidate_is_duplicate "$composite_key" "$line" "$prior_hashes" \
    "$batch_hashes" "$state_file" "$normalized_target"; then
    deduped=$((deduped + 1))
    return 0
  fi
  if [[ "$target" == lessons ]]; then
    printf '%s\n' "$line" >>"$accepted_lessons"
  else
    printf '%s\n' "$line" >>"$accepted_failures"
  fi
  printf '%s\n' "$composite_key" >>"$accepted_keys"
  printf '%s\n' "$lesson_hash" >>"$batch_hashes"
  budget_used=$((budget_used + 1))
  folded=$((folded + 1))
  return 0
}

[[ -n "${workspace:-}" && -d "$workspace" ]] || {
  usage
  exit 2
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-state-fold.sh"
adapter_identity=${adapter_identity:-"${CATY_INTAKE_ADAPTER:?}-flush-intake"}

state_file="$workspace/STATE.md"
pending_dir="$workspace/loop/pending"
archive_dir="$workspace/loop/archive"
artifacts_dir="$workspace/loop/artifacts"
deadman_dir="$workspace/loop/.deadman"
receipt_file="$pending_dir/intake-runs.log"
for required_path in "$state_file" "$pending_dir" "$archive_dir" "$artifacts_dir"; do
  [[ -e "$required_path" ]] || {
    usage
    exit 2
  }
done

max_fold=${INTAKE_MAX_FOLD:-$((STATE_FOLD_LESSONS_CAP_DEFAULT / 2))}
max_bullet_bytes=${INTAKE_MAX_BULLET_BYTES:-512}
lock_attempts=${INTAKE_LOCK_ATTEMPTS:-30}
lock_sleep=${INTAKE_LOCK_SLEEP_S:-1}
if [[ ! "$max_fold" =~ ^[0-9]+$ || ! "$lock_attempts" =~ ^[1-9][0-9]*$ \
  || ! "$max_bullet_bytes" =~ ^[1-9][0-9]{0,6}$ ]]; then
  usage
  exit 2
fi
max_fold=$((10#$max_fold))
lock_attempts=$((10#$lock_attempts))
max_bullet_bytes=$((10#$max_bullet_bytes))
if ((max_bullet_bytes > 1048576)); then
  usage
  exit 2
fi

files_scanned=0
blocks=0
candidates=0
folded=0
deduped=0
evicted_by_cap=0
eviction_archive=none
dropped_oversize=0
deferred=0
headerless_bullets=0
torn_lines=0
quarantined=0
quarantined_paths=
receipt_error=none

# Only old debris is swept so a concurrent process cannot lose a live temp file.
find "$pending_dir" -maxdepth 1 -type f -name '.intake-*.tmp.*' -mtime +1 -delete

if ! take_state_lock "$workspace" "$adapter_identity" "$lock_attempts" "$lock_sleep"; then
  write_receipt busy untouched
  exit 0
fi

tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$tmp_root/flush-intake.XXXXXX")
state_tmp="$workspace/.STATE.md.tmp.$$"
marker_tmp="$deadman_dir/.distill.marker.tmp.$$"
# shellcheck disable=SC2329
cleanup() {
  release_state_lock
  rm -f "$state_tmp" "$marker_tmp"
  rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

prior_hashes="$work_dir/prior.hashes"
batch_hashes="$work_dir/batch.hashes"
normalized_lessons_state="$work_dir/state.lessons.normalized"
normalized_failures_state="$work_dir/state.failures.normalized"
accepted_lessons="$work_dir/lessons.txt"
accepted_failures="$work_dir/failures.txt"
accepted_keys="$work_dir/keys.txt"
actions_file="$work_dir/actions.txt"
files_file="$work_dir/files.txt"
: >"$batch_hashes"
: >"$accepted_lessons"
: >"$accepted_failures"
: >"$accepted_keys"
: >"$actions_file"
snapshot_pending_dedup_keys "$pending_dir" "$prior_hashes" \
  'distill-*.md' 'intake-*.md'
snapshot_state_normalized_candidates "$state_file" "$normalized_lessons_state" \
  '## Lessons learned'
snapshot_state_normalized_candidates "$state_file" "$normalized_failures_state" \
  '## Open failures'

find "$pending_dir" -maxdepth 1 -type f -name 'flush-*.md' -print \
  | LC_ALL=C sort >"$files_file"
today=$(date -u '+%Y-%m-%d')
budget_used=0

while IFS= read -r flush_file || [[ -n "$flush_file" ]]; do
  [[ -n "$flush_file" ]] || continue
  files_scanned=$((files_scanned + 1))
  basename=${flush_file##*/}
  file_date=${basename#flush-}
  file_date=${file_date%.md}
  file_malformed=0
  file_deferred=0
  if [[ ! "$basename" =~ ^flush-[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$ ]]; then
    file_malformed=1
  fi
  is_today=0
  [[ "$file_date" == "$today" ]] && is_today=1
  torn_today=0
  has_newline=1
  if [[ -s "$flush_file" && -n "$(tail -c 1 "$flush_file")" ]]; then
    has_newline=0
  fi
  events_file="$work_dir/events.txt"
  if [[ "$has_newline" -eq 0 && "$is_today" -eq 0 ]]; then
    torn_lines=$((torn_lines + 1))
    sed '$d' "$flush_file" >"$work_dir/complete-lines.txt"
    parse_flush_file "$work_dir/complete-lines.txt" 0 0 >"$events_file"
  else
    if [[ "$has_newline" -eq 0 && "$is_today" -eq 1 ]]; then
      torn_today=1
      file_deferred=1
    fi
    parse_flush_file "$flush_file" "$is_today" "$torn_today" >"$events_file"
  fi

  while IFS=$'\034' read -r event field_one field_two field_three || [[ -n "$event" ]]; do
    case "$event" in
      B)
        blocks=$((blocks + 1))
        ;;
      H)
        headerless_bullets=$((headerless_bullets + 1))
        ;;
      M)
        file_malformed=1
        ;;
      D)
        candidates=$((candidates + 1))
        deferred=$((deferred + 1))
        file_deferred=1
        ;;
      O)
        candidates=$((candidates + 1))
        dropped_oversize=$((dropped_oversize + 1))
        ;;
      C)
        candidate_date=$field_one
        if ! consider_candidate "$candidate_date" "$field_two" lessons "$field_three"; then
          file_deferred=1
        fi
        ;;
    esac
  done <"$events_file"

  action=keep
  action_path=
  if [[ "$file_malformed" -eq 1 && "$file_deferred" -eq 0 ]]; then
    action_path="loop/artifacts/${basename%.md}.malformed.md"
    if consider_candidate "$today" \
      "flush intake quarantined malformed file $action_path" failures \
      "<!-- flush-intake quarantine path=$action_path -->"; then
      action=quarantine
    else
      file_deferred=1
    fi
  elif [[ "$file_malformed" -eq 0 && "$file_deferred" -eq 0 \
    && "$file_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$file_date" < "$today" ]]; then
    action=archive
    action_path="loop/archive/$basename"
  fi
  printf '%s\034%s\034%s\n' "$action" "$flush_file" "$action_path" >>"$actions_file"
done <"$files_file"

eviction_file="$work_dir/evicted.txt"
evicted_lessons_file="$work_dir/evicted-lessons.txt"
printf '0\n' >"$eviction_file"
if [[ -s "$accepted_lessons" || -s "$accepted_failures" ]]; then
  snapshot_evicted_lessons "$state_file" "$accepted_lessons" \
    "$STATE_FOLD_LESSONS_CAP_DEFAULT" "$evicted_lessons_file"
  append_rc=0
  append_state_sections "$state_file" "$accepted_lessons" "$accepted_failures" \
    "$state_tmp" "$STATE_FOLD_LESSONS_CAP_DEFAULT" "$STATE_FOLD_FAILURES_CAP_DEFAULT" \
    "$eviction_file" || append_rc=$?
  if [[ "$append_rc" -ne 0 ]]; then
    rm -f "$state_tmp"
    folded=0
    if [[ "$append_rc" -eq 4 ]]; then
      receipt_error=missing-section
    else
      receipt_error=state-append
    fi
    write_receipt acquired untouched
    exit 1
  fi
  evicted_by_cap=$(cat "$eviction_file")
  if [[ -s "$evicted_lessons_file" ]]; then
    eviction_archive="loop/archive/intake-evictions-$today.md"
    eviction_archive_path="$workspace/$eviction_archive"
    printf '<!-- intake eviction adapter=%s ts=%s -->\n' \
      "$adapter_identity" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >>"$eviction_archive_path"
    cat "$evicted_lessons_file" >>"$eviction_archive_path"
  fi
  mv -f "$state_tmp" "$state_file"
  if [[ ${INTAKE_TEST_CRASH_AFTER_STATE:-0} == 1 ]]; then
    exit 75
  fi
fi

if [[ -s "$accepted_keys" ]]; then
  ledger_file="$pending_dir/intake-$today.md"
  ledger_source="$work_dir/ledger.txt"
  if [[ -f "$ledger_file" ]]; then
    cp "$ledger_file" "$ledger_source"
  else
    : >"$ledger_source"
  fi
  while IFS= read -r composite_key || [[ -n "$composite_key" ]]; do
    printf '<!-- carried dedup_key: %s -->\n' "$composite_key" >>"$ledger_source"
  done <"$accepted_keys"
  atomic_write_file "$ledger_source" "$ledger_file"
fi

while IFS=$'\034' read -r action source_path relative_path || [[ -n "$action" ]]; do
  case "$action" in
    archive)
      destination="$workspace/${relative_path}"
      if [[ -e "$destination" ]]; then
        cat "$source_path" >>"$destination"
        rm -f "$source_path"
      else
        mv "$source_path" "$destination"
      fi
      ;;
    quarantine)
      destination="$workspace/${relative_path}"
      if [[ -e "$destination" ]]; then
        cat "$source_path" >>"$destination"
        rm -f "$source_path"
      else
        mv "$source_path" "$destination"
      fi
      quarantined=$((quarantined + 1))
      quarantined_paths="$quarantined_paths quarantined_path=$relative_path"
      ;;
  esac
done <"$actions_file"

mkdir -p "$deadman_dir"
: >"$marker_tmp"
write_receipt acquired touched
mv -f "$marker_tmp" "$deadman_dir/distill.marker"
release_state_lock
exit 0
