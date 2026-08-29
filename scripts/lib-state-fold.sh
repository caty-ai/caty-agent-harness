#!/usr/bin/env bash
set -euo pipefail

STATE_FOLD_LESSONS_CAP_DEFAULT=60
STATE_FOLD_FAILURES_CAP_DEFAULT=100
STATE_FOLD_VERIFIED_CAP_DEFAULT=120
STATE_FOLD_RULES_CAP_DEFAULT=80
STATE_FOLD_LOCK_DIR=
STATE_FOLD_LOCK_OWNED=0
STATE_FOLD_LOCK_STALE_S=${DISTILL_STATE_LOCK_STALE_S:-1800}
LAST_SESSION_ENTRIES=0
LAST_SESSION_EVICTED=0
LAST_SESSION_SYNTHESIZED_HANDOFFS=0
LAST_SESSION_FOLD_REASON=none
STATE_CAPS_VERIFIED_EVICTED=0
STATE_CAPS_RULES_EVICTED=0
STATE_CAPS_FOLD_REASON=none

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
  # Keep this shell-local for byte-wise bash regex matching only. Child
  # processes intentionally retain the ambient locale so valid keys do not drift.
  local LC_ALL=C

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
      if lesson_hash=$(candidate_lesson_hash "$stripped_line"); then
        printf '%s [dedup_key: %s:%s]\n' "$stripped_line" "$task_id" "$lesson_hash" >>"$annotated_reply"
      fi
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
  if ! normalized=$(normalize_state_candidate "$1"); then
    return 1
  fi
  if [[ -n "$1" && -z "$normalized" ]]; then
    return 1
  fi

  # NFKC intentionally has a broad compatibility effect, not just the NBSP and
  # fullwidth-ASCII folds needed here. For example, it maps x²/x₂ to x2,
  # ①/⑴ to 1/(1), Ⅷ to VIII, 𝐀 to A, ㎠ to cm2, and ｱｲ to アイ; it also
  # equates composed/decomposed forms such as e + combining acute and é, and
  # ligatures such as ﬁ and fi. Curly quotes are deliberately mapped separately
  # because NFKC keeps them distinct.
  # The dangerous distinctions remain closed: Latin A versus Greek Α, Latin a
  # versus Cyrillic а, case differences, and hyphen versus en dash remain
  # distinct keys. Do not add case folding or broad confusable stripping here:
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
try:
    sys.stdout.buffer.write((value + "\n").encode("utf-8"))
except UnicodeEncodeError:
    sys.exit(1)
PY
}

# Append-only compatibility: historical [dedup_key: ...] annotations are not
# recomputed or rewritten. A pre-rollout key can therefore admit one duplicate
# before a newly normalized key is recorded for later folds.
candidate_lesson_hash() {
  local normalized
  if ! normalized=$(normalize_state_candidate_key_text "$1"); then
    return 1
  fi
  [[ -n "$normalized" ]] || return 1
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
  local normalized

  LC_ALL=C awk -v section_headings="$section_headings" '
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
    if normalized=$(normalize_state_candidate_key_text "$line"); then
      [[ -n "$normalized" ]] && printf '%s\n' "$normalized" >>"$output"
    fi
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

  normalized=$(normalize_state_candidate_key_text "$candidate_line") || return 1
  [[ -n "$normalized" ]] || return 1
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
  cp "$source_file" "$tmp_file" || { rm -f "$tmp_file"; return 1; }
  # Verify before rename: catches ENOSPC mid-copy and short reads.
  if ! cmp -s "$source_file" "$tmp_file"; then rm -f "$tmp_file"; return 1; fi
  # The destination must be a regular file or absent, never a directory.
  if [ -e "$destination" ] && [ ! -f "$destination" ]; then rm -f "$tmp_file"; return 1; fi
  mv -f "$tmp_file" "$destination" || { rm -f "$tmp_file"; return 1; }
}

last_session_parse_snapshot() {
  local snapshot=$1
  local parse_dir=$2

  : >"$parse_dir/before"
  : >"$parse_dir/preamble"
  : >"$parse_dir/after"
  awk -v parse_dir="$parse_dir" '
    function is_boundary(value) {
      return value ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / \
        || value ~ /^- task id:/
    }
    {
      if (!saw_heading && index($0, "## Last session") == 1) {
        saw_heading = 1
        in_section = 1
        print > (parse_dir "/before")
        next
      }
      if (!saw_heading) {
        print > (parse_dir "/before")
        next
      }
      if (in_section && /^## /) {
        in_section = 0
      }
      if (!in_section) {
        print > (parse_dir "/after")
        next
      }
      if (is_boundary($0)) {
        entries++
        if ($0 ~ /^- task id:/) legacy++
        else current++
      }
      if (entries == 0) {
        print > (parse_dir "/preamble")
      } else {
        print > sprintf("%s/entry.%04d", parse_dir, entries)
      }
    }
    END {
      printf "%d %d %d %d\n", saw_heading + 0, entries + 0, legacy + 0, current + 0
    }
  ' "$snapshot" >"$parse_dir/summary"
}

last_session_first_date() {
  local entry=$1
  local fallback=$2
  local value

  value=$({ grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$entry" || true; } | head -n 1)
  printf '%s\n' "${value:-$fallback}"
}

last_session_task_id() {
  local entry=$1
  local value

  value=$(awk -F '|' '
    NR == 1 && $0 ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \| / {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$entry")
  if [[ -z "$value" ]]; then
    value=$(sed -n 's/.*task id:[[:space:]]*\([^;]*\).*/\1/p' "$entry" | head -n 1)
  fi
  value=$(printf '%s\n' "$value" | awk '{$1 = $1; print}')
  printf '%s\n' "${value:-unknown}"
}

last_session_legacy_field() {
  local entry=$1
  local label=$2
  local fallback=$3
  local value

  value=$(sed -n "s/.*$label:[[:space:]]*\([^;]*\).*/\\1/p" "$entry" | head -n 1)
  value=$(printf '%s\n' "$value" | awk '{$1 = $1; print}')
  printf '%s\n' "${value:-$fallback}"
}

last_session_pointer() {
  local entry=$1

  sed -n 's/.*handoff:[[:space:]]*\([^ |]*\).*/\1/p' "$entry" | head -n 1
}

last_session_pointer_is_usable() {
  local workspace=$1
  local pointer=$2
  local basename

  case "$pointer" in
    loop/handoffs/*.md) ;;
    *) return 1 ;;
  esac
  basename=${pointer#loop/handoffs/}
  [[ -n "$basename" && "$basename" != */* && "$basename" != *..* \
    && -f "$workspace/$pointer" && ! -L "$workspace/$pointer" ]]
}

last_session_create_handoff() {
  local workspace=$1
  local source_file=$2
  local entry_date=$3
  local handoff_dir="$workspace/loop/handoffs"
  local suffix=
  local candidate
  local target
  local tmp_file
  local attempt=1

  mkdir -p "$handoff_dir" || return 1
  while :; do
    if (( attempt == 1 )); then
      suffix=
    else
      suffix="-$attempt"
    fi
    candidate="$entry_date-migrated$suffix.md"
    target="$handoff_dir/$candidate"
    tmp_file="$handoff_dir/.${candidate}.tmp.$$"
    cp "$source_file" "$tmp_file" || {
      rm -f "$tmp_file"
      return 1
    }
    # Publishing a fully written temp file with link(2) gives portable,
    # atomic exclusive-create behavior on bash 3.2-era systems.
    if ln "$tmp_file" "$target" 2>/dev/null; then
      rm -f "$tmp_file"
      LAST_SESSION_CREATED_HANDOFF="$target"
      LAST_SESSION_CREATED_POINTER="loop/handoffs/$candidate"
      return 0
    fi
    rm -f "$tmp_file"
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      return 1
    fi
    attempt=$((attempt + 1))
  done
}

state_fold_atomic_archive_append() {
  local source_file=$1
  local archive_file=$2
  local archive_dir
  local archive_name
  local tmp_file
  local before_bytes=0
  local source_bytes
  local expected_bytes
  local actual_bytes

  archive_dir=$(cd "$(dirname "$archive_file")" && pwd)
  archive_name=${archive_file##*/}
  tmp_file="$archive_dir/.$archive_name.tmp.$$"
  if [[ -f "$archive_file" ]]; then
    cp "$archive_file" "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    if ! before_bytes=$(wc -c <"$archive_file" | tr -d '[:space:]'); then
      rm -f "$tmp_file"
      return 1
    fi
  else
    : >"$tmp_file" || { rm -f "$tmp_file"; return 1; }
  fi
  if ! source_bytes=$(wc -c <"$source_file" | tr -d '[:space:]'); then
    rm -f "$tmp_file"
    return 1
  fi
  cat "$source_file" >>"$tmp_file" || {
    rm -f "$tmp_file"
    return 1
  }
  expected_bytes=$((before_bytes + source_bytes))
  if ! actual_bytes=$(wc -c <"$tmp_file" | tr -d '[:space:]'); then
    rm -f "$tmp_file"
    return 1
  fi
  if [[ "$actual_bytes" -ne "$expected_bytes" ]]; then
    rm -f "$tmp_file"
    return 1
  fi
  if [[ "$source_bytes" -gt 0 ]] \
    && ! tail -c "$source_bytes" "$tmp_file" | cmp -s - "$source_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  if [[ "$before_bytes" -gt 0 ]] \
    && ! head -c "$before_bytes" "$tmp_file" | cmp -s - "$archive_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  # The destination must be a regular file or absent, never a directory.
  if [ -e "$archive_file" ] && [ ! -f "$archive_file" ]; then
    rm -f "$tmp_file"
    return 1
  fi
  mv -f "$tmp_file" "$archive_file" || { rm -f "$tmp_file"; return 1; }
}

fold_declared_state_caps() {
  local workspace=$1
  local state_file=$2
  local work_dir=$3
  local adapter=$4
  local fold_date=${5:-$(date -u '+%Y-%m-%d')}
  local snapshot="$work_dir/state-caps.snapshot"
  local rebuilt="$work_dir/state-caps.rebuilt"
  local verified_evictions="$work_dir/state-caps.verified"
  local rules_evictions="$work_dir/state-caps.rules"
  local archive_payload="$work_dir/state-caps.archive"
  local archived_payload="$work_dir/state-caps.archived"
  local summary_file="$work_dir/state-caps.summary"
  local summary
  local has_verified
  local has_rules
  local archive_file
  local timestamp
  local payload_lines_before
  local payload_lines_after
  local archive_payload_lines
  local verified_archived_lines=0
  local rules_archived_lines=0

  STATE_CAPS_VERIFIED_EVICTED=0
  STATE_CAPS_RULES_EVICTED=0
  STATE_CAPS_FOLD_REASON=none
  : >"$verified_evictions"
  : >"$rules_evictions"
  : >"$archive_payload" || {
    STATE_CAPS_FOLD_REASON=archive-payload
    return 1
  }
  cp "$state_file" "$snapshot" || {
    STATE_CAPS_FOLD_REASON=snapshot
    return 1
  }
  if ! awk -v verified_cap="$STATE_FOLD_VERIFIED_CAP_DEFAULT" \
    -v rules_cap="$STATE_FOLD_RULES_CAP_DEFAULT" \
    -v verified_evictions="$verified_evictions" -v rules_evictions="$rules_evictions" \
    -v summary_file="$summary_file" '
    function flush_section(    cap,eviction_file,start,i) {
      if (section == "") return
      if (section == "verified") {
        cap = verified_cap
        eviction_file = verified_evictions
      } else {
        cap = rules_cap
        eviction_file = rules_evictions
      }
      start = 1
      if (section_count > cap) start = section_count - cap + 1
      for (i = 1; i < start; i++) {
        print section_lines[i] >> eviction_file
        if (section == "verified") verified_evicted++
        else rules_evicted++
      }
      close(eviction_file)
      for (i = start; i <= section_count; i++) print section_lines[i]
      delete section_lines
      section_count = 0
      section = ""
    }
    {
      if (/^## /) {
        flush_section()
        print
        if (index($0, "## Verified facts") == 1) {
          section = "verified"
          has_verified++
          preamble = 1
          next
        }
        if (index($0, "## General rules") == 1) {
          section = "rules"
          has_rules++
          preamble = 1
          next
        }
        next
      }
      if (section != "") {
        if (preamble && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*<!--.*-->[[:space:]]*$/)) {
          print
        } else {
          preamble = 0
          section_lines[++section_count] = $0
        }
      } else {
        print
      }
    }
    END {
      flush_section()
      printf "%d %d %d %d\n", has_verified + 0, has_rules + 0, \
        verified_evicted + 0, rules_evicted + 0 > summary_file
      close(summary_file)
    }
  ' "$snapshot" >"$rebuilt"; then
    STATE_CAPS_FOLD_REASON=parse
    return 1
  fi
  summary=$(cat "$summary_file")
  read -r has_verified has_rules STATE_CAPS_VERIFIED_EVICTED \
    STATE_CAPS_RULES_EVICTED <<EOF
$summary
EOF
  if [[ "$has_verified" -gt 1 || "$has_rules" -gt 1 ]]; then
    STATE_CAPS_FOLD_REASON=duplicate-heading
    return 1
  fi
  if [[ "$has_verified" -ne 1 && "$has_rules" -ne 1 ]]; then
    STATE_CAPS_FOLD_REASON=missing-sections
    return 1
  fi
  if [[ "$has_verified" -ne 1 ]]; then
    STATE_CAPS_FOLD_REASON=missing-verified-facts
    return 1
  fi
  if [[ "$has_rules" -ne 1 ]]; then
    STATE_CAPS_FOLD_REASON=missing-general-rules
    return 1
  fi
  if [[ "$STATE_CAPS_VERIFIED_EVICTED" -eq 0 \
    && "$STATE_CAPS_RULES_EVICTED" -eq 0 ]]; then
    return 0
  fi
  if ! cmp -s "$snapshot" "$state_file"; then
    STATE_CAPS_FOLD_REASON=concurrent-writer
    return 1
  fi

  archive_file="$workspace/loop/archive/intake-evictions-$fold_date.md"
  if [[ -e "$archive_file" || -L "$archive_file" ]]; then
    if [[ ! -f "$archive_file" || -L "$archive_file" ]]; then
      STATE_CAPS_FOLD_REASON=archive-target
      return 1
    fi
  fi
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if [[ "$STATE_CAPS_VERIFIED_EVICTED" -gt 0 ]]; then
    payload_lines_before=$(wc -l <"$archive_payload" | tr -d '[:space:]') || {
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    }
    if ! printf '<!-- caps eviction section=verified-facts adapter=%s ts=%s -->\n' \
      "$adapter" "$timestamp" >>"$archive_payload"; then
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    fi
    if ! cat "$verified_evictions" >>"$archive_payload"; then
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    fi
    payload_lines_after=$(wc -l <"$archive_payload" | tr -d '[:space:]') || {
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    }
    verified_archived_lines=$((payload_lines_after - payload_lines_before - 1))
  fi
  if [[ "$STATE_CAPS_RULES_EVICTED" -gt 0 ]]; then
    payload_lines_before=$(wc -l <"$archive_payload" | tr -d '[:space:]') || {
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    }
    if ! printf '<!-- caps eviction section=general-rules adapter=%s ts=%s -->\n' \
      "$adapter" "$timestamp" >>"$archive_payload"; then
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    fi
    if ! cat "$rules_evictions" >>"$archive_payload"; then
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    fi
    payload_lines_after=$(wc -l <"$archive_payload" | tr -d '[:space:]') || {
      STATE_CAPS_FOLD_REASON=archive-payload
      return 1
    }
    rules_archived_lines=$((payload_lines_after - payload_lines_before - 1))
  fi
  if ! state_fold_atomic_archive_append "$archive_payload" "$archive_file"; then
    STATE_CAPS_FOLD_REASON=archive-append
    return 1
  fi
  if ! cmp -s "$snapshot" "$state_file"; then
    STATE_CAPS_FOLD_REASON=concurrent-writer
    return 1
  fi
  archive_payload_lines=$(wc -l <"$archive_payload" | tr -d '[:space:]') || {
    STATE_CAPS_FOLD_REASON=archive-integrity
    return 1
  }
  if ! tail -n "$archive_payload_lines" "$archive_file" >"$archived_payload" \
    || ! cmp -s "$archive_payload" "$archived_payload" \
    || [[ "$verified_archived_lines" -ne "$STATE_CAPS_VERIFIED_EVICTED" ]] \
    || [[ "$rules_archived_lines" -ne "$STATE_CAPS_RULES_EVICTED" ]]; then
    STATE_CAPS_FOLD_REASON=archive-integrity
    return 1
  fi
  if ! atomic_write_file "$rebuilt" "$state_file"; then
    STATE_CAPS_FOLD_REASON=state-rename
    return 1
  fi
  return 0
}

fold_last_session_index() {
  local workspace=$1
  local state_file=$2
  local work_dir=$3
  local fold_date=${4:-$(date -u '+%Y-%m-%d')}
  local mode=${5:-all}
  local parse_dir="$work_dir/last-session"
  local snapshot="$work_dir/last-session.snapshot"
  local rebuilt="$work_dir/last-session.rebuilt"
  local archive_entries="$work_dir/last-session.archive"
  local migration_body="$work_dir/last-session.migration"
  local summary
  local has_heading
  local entry_count
  local legacy_count
  local current_count
  local migration=0
  local kept_count
  local i
  local entry_file
  local pointer
  local entry_date
  local task_id
  local next_action
  local blockers
  local artifact
  local archive_week
  local archive_file
  local created_files="$work_dir/last-session.created"

  LAST_SESSION_ENTRIES=0
  LAST_SESSION_EVICTED=0
  LAST_SESSION_SYNTHESIZED_HANDOFFS=0
  LAST_SESSION_FOLD_REASON=none
  LAST_SESSION_CREATED_HANDOFF=
  LAST_SESSION_CREATED_POINTER=
  mkdir -p "$parse_dir" "$workspace/loop/handoffs" || {
    LAST_SESSION_FOLD_REASON=handoff-dir
    return 1
  }
  : >"$created_files"
  : >"$archive_entries"
  : >"$migration_body"
  cp "$state_file" "$snapshot" || {
    LAST_SESSION_FOLD_REASON=snapshot
    return 1
  }
  last_session_parse_snapshot "$snapshot" "$parse_dir" || {
    LAST_SESSION_FOLD_REASON=parse
    return 1
  }
  summary=$(cat "$parse_dir/summary")
  read -r has_heading entry_count legacy_count current_count <<EOF
$summary
EOF
  if [[ "$has_heading" -ne 1 ]]; then
    LAST_SESSION_FOLD_REASON=missing-section
    return 1
  fi
  if [[ "$entry_count" -eq 0 ]]; then
    return 0
  fi
  if [[ "$legacy_count" -gt 1 && "$current_count" -eq 0 ]]; then
    migration=1
  elif [[ "$mode" == legacy-only ]]; then
    LAST_SESSION_ENTRIES=$entry_count
    return 0
  fi

  if ! cmp -s "$snapshot" "$state_file"; then
    LAST_SESSION_FOLD_REASON=concurrent-writer
    return 1
  fi

  kept_count=$entry_count
  (( kept_count > 20 )) && kept_count=20
  LAST_SESSION_ENTRIES=$kept_count
  if [[ "$migration" -eq 1 ]]; then
    i=1
    while (( i <= entry_count )); do
      cat "$(printf '%s/entry.%04d' "$parse_dir" "$i")" >>"$migration_body"
      i=$((i + 1))
    done
    entry_date=$(last_session_first_date "$parse_dir/entry.0001" "$fold_date")
    if ! last_session_create_handoff "$workspace" "$migration_body" "$entry_date"; then
      LAST_SESSION_FOLD_REASON=handoff-write
      return 1
    fi
    printf '%s\n' "$LAST_SESSION_CREATED_HANDOFF" >>"$created_files"
    pointer=$LAST_SESSION_CREATED_POINTER
    LAST_SESSION_SYNTHESIZED_HANDOFFS=1
    cat "$parse_dir/before" "$parse_dir/preamble" >"$rebuilt"
    task_id=$(last_session_task_id "$parse_dir/entry.0001")
    next_action=$(last_session_legacy_field "$parse_dir/entry.0001" 'next action' none)
    blockers=$(last_session_legacy_field "$parse_dir/entry.0001" blockers none)
    artifact=$(last_session_legacy_field "$parse_dir/entry.0001" 'last verified artifact path' none)
    printf -- '- %s | %s | next: %s | blockers: %s | artifact: %s | handoff: %s\n' \
      "$entry_date" "$task_id" "$next_action" "$blockers" "$artifact" "$pointer" >>"$rebuilt"
    i=2
    while (( i <= kept_count )); do
      entry_file=$(printf '%s/entry.%04d' "$parse_dir" "$i")
      entry_date=$(last_session_first_date "$entry_file" "$fold_date")
      task_id=$(last_session_task_id "$entry_file")
      printf -- '- %s | %s | handoff: %s\n' "$entry_date" "$task_id" "$pointer" >>"$rebuilt"
      i=$((i + 1))
    done
    cat "$parse_dir/after" >>"$rebuilt"
    cp "$migration_body" "$archive_entries"
    LAST_SESSION_EVICTED=$entry_count
  else
    cat "$parse_dir/before" "$parse_dir/preamble" "$parse_dir/entry.0001" >"$rebuilt"
    i=2
    while (( i <= kept_count )); do
      entry_file=$(printf '%s/entry.%04d' "$parse_dir" "$i")
      pointer=$(last_session_pointer "$entry_file")
      if ! last_session_pointer_is_usable "$workspace" "$pointer"; then
        entry_date=$(last_session_first_date "$entry_file" "$fold_date")
        if ! last_session_create_handoff "$workspace" "$entry_file" "$entry_date"; then
          while IFS= read -r LAST_SESSION_CREATED_HANDOFF; do
            [[ -n "$LAST_SESSION_CREATED_HANDOFF" ]] && rm -f "$LAST_SESSION_CREATED_HANDOFF"
          done <"$created_files"
          LAST_SESSION_FOLD_REASON=handoff-write
          return 1
        fi
        printf '%s\n' "$LAST_SESSION_CREATED_HANDOFF" >>"$created_files"
        pointer=$LAST_SESSION_CREATED_POINTER
        LAST_SESSION_SYNTHESIZED_HANDOFFS=$((LAST_SESSION_SYNTHESIZED_HANDOFFS + 1))
      fi
      entry_date=$(last_session_first_date "$entry_file" "$fold_date")
      task_id=$(last_session_task_id "$entry_file")
      printf -- '- %s | %s | handoff: %s\n' "$entry_date" "$task_id" "$pointer" >>"$rebuilt"
      i=$((i + 1))
    done
    cat "$parse_dir/after" >>"$rebuilt"
    if (( entry_count > 20 )); then
      i=21
      while (( i <= entry_count )); do
        cat "$(printf '%s/entry.%04d' "$parse_dir" "$i")" >>"$archive_entries"
        i=$((i + 1))
      done
      LAST_SESSION_EVICTED=$((entry_count - 20))
    fi
  fi

  if [[ -s "$archive_entries" ]]; then
    archive_week=$(date -u '+%G-W%V')
    archive_file="$workspace/loop/archive/last-session-$archive_week.md"
    if ! state_fold_atomic_archive_append "$archive_entries" "$archive_file"; then
      while IFS= read -r LAST_SESSION_CREATED_HANDOFF; do
        [[ -n "$LAST_SESSION_CREATED_HANDOFF" ]] && rm -f "$LAST_SESSION_CREATED_HANDOFF"
      done <"$created_files"
      LAST_SESSION_FOLD_REASON=archive-append
      return 1
    fi
  fi
  if ! atomic_write_file "$rebuilt" "$state_file"; then
    while IFS= read -r LAST_SESSION_CREATED_HANDOFF; do
      [[ -n "$LAST_SESSION_CREATED_HANDOFF" ]] && rm -f "$LAST_SESSION_CREATED_HANDOFF"
    done <"$created_files"
    LAST_SESSION_FOLD_REASON=state-rename
    return 1
  fi
  return 0
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
