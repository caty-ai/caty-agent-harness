#!/usr/bin/env bash
set -euo pipefail

STATE_FOLD_LESSONS_CAP_DEFAULT=60
STATE_FOLD_FAILURES_CAP_DEFAULT=100
STATE_FOLD_LOCK_DIR=
STATE_FOLD_LOCK_OWNED=0
STATE_FOLD_LOCK_STALE_S=${DISTILL_STATE_LOCK_STALE_S:-1800}

file_mtime_epoch() {
  local path=$1
  stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path"
}

state_fold_trace() {
  local event=$1

  # Test-only seam for proving that intake budget rejection bypasses this pipeline.
  [[ -n "${STATE_FOLD_TEST_TRACE_FILE:-}" ]] || return 0
  printf '%s\n' "$event" >>"$STATE_FOLD_TEST_TRACE_FILE"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'state-fold infra error: sha256sum or shasum is required for deduplication\n' >&2
    return 1
  fi
}

sha256_text() {
  state_fold_trace sha256
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf 'state-fold infra error: sha256sum or shasum is required for deduplication\n' >&2
    return 1
  fi
}

state_fold_section_allowed() {
  local candidate=$1
  local section_headings=$2
  local heading
  local headings

  IFS='|' read -r -a headings <<<"$section_headings"
  for heading in ${headings[@]+"${headings[@]}"}; do
    if [[ "$candidate" == "$heading" ]]; then
      return 0
    fi
  done
  return 1
}

annotate_reply_dedup_keys() {
  local reply=$1
  local task_id=$2
  local annotated_reply=$3
  local source_marker=$4
  local section_headings=$5
  local section=
  local line
  local stripped_line
  local source_anchored_line
  local lesson_hash

  state_fold_trace annotate

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##\ ([A-Z_]+)[[:space:]]*$ ]]; then
      if state_fold_section_allowed "${BASH_REMATCH[1]}" "$section_headings"; then
        section=${BASH_REMATCH[1]}
      else
        section=other
      fi
    elif [[ "$line" =~ ^##\  ]]; then
      section=other
    fi

    stripped_line=$line
    if [[ "$section" != other && -n "$section" \
      && "$stripped_line" =~ ^(.*)\ \[dedup_key:\ [^]]*\]$ ]]; then
      stripped_line=${BASH_REMATCH[1]}
    fi

    source_anchored_line=$stripped_line
    if [[ "$source_anchored_line" =~ ^(.*)[[:space:]]+\[mech_check:\ (yes|no)\]$ ]]; then
      source_anchored_line=${BASH_REMATCH[1]}
    fi
    if [[ "$section" != other && -n "$section" \
      && "$source_anchored_line" =~ ^-\ [0-9]{4}-[0-9]{2}-[0-9]{2}\  \
      && "$source_anchored_line" == *" $source_marker" ]]; then
      lesson_hash=$(candidate_lesson_hash "$stripped_line")
      printf '%s [dedup_key: %s:%s]\n' "$stripped_line" "$task_id" "$lesson_hash" >>"$annotated_reply"
    else
      printf '%s\n' "$stripped_line" >>"$annotated_reply"
    fi
  done <"$reply"
}

normalize_state_candidate() {
  printf '%s\n' "$1" | awk '
    {
      $1 = $1
      sub(/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /, "")
      sub(/[[:space:]]+\[mech_check: (yes|no)\]$/, "")
      sub(/[[:space:]]+\(source: [a-z-]+\)$/, "")
      $1 = $1
      print
    }
  '
}

normalize_state_candidate_key_text() {
  local normalized
  normalized=$(normalize_state_candidate "$1")

  # NFKC supplies the compatibility folds required for NBSP and fullwidth
  # ASCII. Curly quotes are deliberately mapped separately because NFKC keeps
  # them distinct. Do not add case folding or broad confusable stripping here:
  # this representation is used only for dedup keys/comparisons, never storage.
  python3 -B - "$normalized" <<'PY'
import re
import sys
import unicodedata

SMART_QUOTES = str.maketrans({
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
})

value = unicodedata.normalize("NFKC", sys.argv[1]).translate(SMART_QUOTES)
# Compatibility spaces introduced by NFKC join the existing whitespace fold.
value = re.sub(r" +", " ", value).strip(" ")
sys.stdout.write(value + "\n")
PY
}

# Append-only compatibility: historical [dedup_key: ...] annotations are not
# recomputed or rewritten. A pre-rollout key can therefore admit one duplicate
# before a newly normalized key is recorded for later folds.
candidate_lesson_hash() {
  local normalized
  normalized=$(normalize_state_candidate_key_text "$1")
  sha256_text "$normalized"
}

extract_pending_dedup_keys() {
  local file=$1
  local output=$2
  local line
  local key

  while IFS= read -r line || [[ -n "$line" ]]; do
    key=
    if [[ "$line" =~ \ \[dedup_key:\ ([^]]+)\]$ ]]; then
      key=${BASH_REMATCH[1]}
    elif [[ "$line" =~ ^'<!-- carried dedup_key: '([^[:space:]]+)' -->'$ ]]; then
      key=${BASH_REMATCH[1]}
    fi
    if [[ "$key" =~ ^[0-9a-f]{64}:[0-9a-f]{64}$ ]]; then
      printf '%s\n' "$key" >>"$output"
    fi
  done <"$file"
}

snapshot_pending_dedup_keys() {
  local pending=$1
  local output=$2
  shift 2
  local pattern
  local file
  local composite_file="$output.composite.$$"
  local key

  : >"$output"
  : >"$composite_file"
  for pattern in "$@"; do
    while IFS= read -r -d '' file; do
      extract_pending_dedup_keys "$file" "$composite_file"
    done < <(find "$pending" -maxdepth 1 -type f -name "$pattern" -print0)
  done
  while IFS= read -r key || [[ -n "$key" ]]; do
    printf '%s\n' "${key##*:}" >>"$output"
  done <"$composite_file"
  rm -f "$composite_file"
}

snapshot_state_normalized_candidates() {
  local state_file=$1
  local output=$2
  local section_headings=$3
  local raw_file="$output.raw.$$"
  local line

  awk -v section_headings="$section_headings" '
    BEGIN {
      count = split(section_headings, headings, "|")
      for (i = 1; i <= count; i++) allowed[headings[i]] = 1
    }
    /^## / {
      section = ""
      for (heading in allowed) {
        if (index($0, heading) == 1) {
          section = heading
          break
        }
      }
      next
    }
    section != "" && /^- / {print}
  ' "$state_file" >"$raw_file"

  : >"$output"
  while IFS= read -r line || [[ -n "$line" ]]; do
    normalize_state_candidate_key_text "$line" >>"$output"
  done <"$raw_file"
  rm -f "$raw_file"
}

state_fold_candidate_is_duplicate() {
  local composite_key=$1
  local candidate_line=$2
  local prior_hashes=$3
  local batch_hashes=$4
  local state_file=$5
  local normalized_state=$6
  local lesson_hash=${composite_key##*:}
  local normalized

  state_fold_trace dedup

  normalized=$(normalize_state_candidate_key_text "$candidate_line")
  grep -Fqx -- "$lesson_hash" "$prior_hashes" \
    || grep -Fqx -- "$lesson_hash" "$batch_hashes" \
    || grep -Fqx -- "$normalized" "$normalized_state" \
    || grep -Fqx -- "$candidate_line" "$state_file"
}

split_annotated_reply_sections() {
  local reply=$1
  local lessons_file=$2
  local failures_file=$3
  local source_marker=$4
  local section_headings=$5

  state_fold_trace split

  awk -v lessons="$lessons_file" -v failures="$failures_file" \
    -v source_marker="$source_marker" -v section_headings="$section_headings" '
    BEGIN {
      count = split(section_headings, headings, "|")
      for (i = 1; i <= count; i++) {
        allowed[headings[i]] = 1
      }
    }
    /^## [A-Z_]+[[:space:]]*$/ {
      heading = $0
      sub(/^## /, "", heading)
      sub(/[[:space:]]*$/, "", heading)
      section = (heading in allowed) ? heading : "other"
      next
    }
    /^## / {section = "other"; next}
    (section in allowed) {
      if (match($0, / \[dedup_key: [^]]+\]$/)) {
        line = substr($0, 1, RSTART - 1)
        key = substr($0, RSTART + 13, RLENGTH - 14)
        normalized_line = line
        sub(/[[:space:]]+\[mech_check: (yes|no)\]$/, "", normalized_line)
        if (normalized_line ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / &&
            substr(normalized_line, length(normalized_line) - length(source_marker) + 1) == source_marker &&
            split(key, p, ":") == 2 && length(p[1]) == 64 && length(p[2]) == 64 &&
            p[1] ~ /^[0-9a-f]+$/ && p[2] ~ /^[0-9a-f]+$/) {
          if (section == "LESSONS") {
            print key "\t" line > lessons
          } else if (section == "OPEN_FAILURES") {
            print key "\t" line > failures
          }
        }
      }
    }
  ' "$reply"
}

section_count() {
  local section=$1
  local file=$2

  awk -v section="$section" '
    index($0, section) == 1 {in_section = 1; next}
    in_section && /^## / {exit}
    in_section {count++}
    END {print count + 0}
  ' "$file"
}

append_state_sections() {
  local state_file=$1
  local lessons_file=$2
  local failures_file=$3
  local tmp_file=$4
  local lessons_cap=${5:-$STATE_FOLD_LESSONS_CAP_DEFAULT}
  local failures_cap=${6:-$STATE_FOLD_FAILURES_CAP_DEFAULT}
  local eviction_file=${7:-}

  if [[ -s "$lessons_file" ]] \
    && ! grep -q '^## Lessons learned' "$state_file"; then
    return 4
  fi
  if [[ -s "$failures_file" ]] \
    && ! grep -q '^## Open failures' "$state_file"; then
    return 4
  fi

  awk -v lessons="$lessons_file" -v failures="$failures_file" \
    -v lessons_cap="$lessons_cap" -v failures_cap="$failures_cap" \
    -v eviction_file="$eviction_file" '
    function append_file(path) {
      while ((getline line < path) > 0) {
        section_lines[++section_count] = line
      }
      close(path)
    }
    function flush_section(    cap,start,i) {
      if (section == "") {
        return
      }
      if (section == "lessons") {
        append_file(lessons)
        cap = lessons_cap
      } else if (section == "failures") {
        append_file(failures)
        cap = failures_cap
      } else {
        cap = section_count
      }
      start = 1
      if (section_count > cap) {
        start = section_count - cap + 1
        evicted_total += start - 1
      }
      for (i = start; i <= section_count; i++) {
        print section_lines[i]
      }
      delete section_lines
      section_count = 0
      section = ""
    }
    {
      if (/^## /) {
        flush_section()
        print
        if (index($0, "## Lessons learned") == 1) {
          section = "lessons"
          next
        } else if (index($0, "## Open failures") == 1) {
          section = "failures"
          next
        }
        next
      }
      if (section != "") {
        section_lines[++section_count] = $0
      } else {
        print
      }
    }
    END {
      flush_section()
      if (eviction_file != "") {
        print evicted_total + 0 > eviction_file
        close(eviction_file)
      }
    }
  ' "$state_file" >"$tmp_file"
}

atomic_write_file() {
  local source_file=$1
  local destination=$2
  local destination_dir
  local destination_name
  local tmp_file

  destination_dir=$(cd "$(dirname "$destination")" && pwd)
  destination_name=${destination##*/}
  tmp_file="$destination_dir/.$destination_name.tmp.$$"
  cp "$source_file" "$tmp_file"
  mv -f "$tmp_file" "$destination"
}

take_state_lock() {
  local workspace=$1
  local caller=$2
  local max_attempts=${3:-0}
  local sleep_seconds=${4:-1}
  local stale_seconds=${5:-$STATE_FOLD_LOCK_STALE_S}
  local attempts=0
  local now_epoch
  local lock_mtime
  local lock_age

  STATE_FOLD_LOCK_DIR="$workspace/loop/.distill-state.lock"
  STATE_FOLD_LOCK_OWNED=0
  while ! mkdir "$STATE_FOLD_LOCK_DIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    now_epoch=$(date '+%s')
    lock_mtime=$(file_mtime_epoch "$STATE_FOLD_LOCK_DIR" 2>/dev/null || printf '0\n')
    lock_age=$((now_epoch - lock_mtime))
    if (( lock_age > stale_seconds )); then
      rm -rf "$STATE_FOLD_LOCK_DIR"
    fi
    sleep "$sleep_seconds"
    if (( max_attempts > 0 && attempts >= max_attempts )); then
      STATE_FOLD_LOCK_DIR=
      return 1
    fi
  done
  STATE_FOLD_LOCK_OWNED=1
  printf '%s %s\n' "$$" "$caller" >"$STATE_FOLD_LOCK_DIR/pid"
}

release_state_lock() {
  if [[ "${STATE_FOLD_LOCK_OWNED:-0}" -eq 1 && -n "${STATE_FOLD_LOCK_DIR:-}" ]]; then
    rm -rf "$STATE_FOLD_LOCK_DIR"
    STATE_FOLD_LOCK_OWNED=0
    STATE_FOLD_LOCK_DIR=
  fi
}
