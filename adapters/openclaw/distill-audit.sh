#!/usr/bin/env bash
set -euo pipefail

# DISTILLER_CMD must be exactly one absolute wrapper-script path with fresh
# conformance evidence. Legacy multi-token commands are rejected.

usage() {
  printf 'Usage: distill-audit.sh --workspace <ws> --input <dir> [--input <dir> ...]\n' >&2
}

infra_fail() {
  printf 'distill-audit infra error: %s\n' "$1" >&2
  exit 3
}

injection_size_check() {
  local workspace_root=${1:-}
  local pending=${2:-}
  local names=(AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md MEMORY.md HEARTBEAT.md STATE.md)
  local caps=(5000 4000 4000 2000 8000 11000 2000 11000)
  local entries=()
  local entry
  local name
  local value
  local malformed=0
  local matched
  local i
  local file
  local chars
  local cap
  local warn_threshold
  local line
  local timestamp

  if [[ -z "$workspace_root" || -z "$pending" ]]; then
    return 0
  fi

  if [[ -n "${DISTILL_SIZE_CAPS:-}" ]]; then
    IFS=',' read -r -a entries <<<"${DISTILL_SIZE_CAPS:-}" || true
    for entry in "${entries[@]}"; do
      if [[ "$entry" != *=* ]]; then
        malformed=1
        continue
      fi
      name=${entry%%=*}
      value=${entry#*=}
      while [[ "$name" =~ ^[[:space:]] ]]; do
        name=${name#?}
      done
      while [[ "$name" =~ [[:space:]]$ ]]; do
        name=${name%?}
      done
      while [[ "$value" =~ ^[[:space:]] ]]; do
        value=${value#?}
      done
      while [[ "$value" =~ [[:space:]]$ ]]; do
        value=${value%?}
      done
      if [[ -z "$name" || ! "$value" =~ ^[0-9]+$ ]]; then
        malformed=1
        continue
      fi
      value=$((10#$value))
      matched=0
      for ((i = 0; i < ${#names[@]}; i++)); do
        if [[ "$name" == "${names[$i]}" ]]; then
          caps[i]=$value
          matched=1
          break
        fi
      done
      if [[ "$matched" -eq 0 ]]; then
        malformed=1
      fi
    done
    if [[ "$malformed" -eq 1 ]]; then
      printf 'injection_size_check: ignoring malformed DISTILL_SIZE_CAPS entries\n' >&2 || true
    fi
  fi

  for ((i = 0; i < ${#names[@]}; i++)); do
    name=${names[$i]}
    cap=${caps[$i]:-0}
    if [[ ! "$cap" =~ ^[0-9]+$ ]]; then
      cap=0
    fi
    cap=$((10#$cap))

    file="$workspace_root/$name"
    if [[ ! -f "$file" ]]; then
      continue
    fi

    chars=$(wc -m <"$file" 2>/dev/null) || chars=0
    chars=${chars//[[:space:]]/}
    if [[ ! "$chars" =~ ^[0-9]+$ ]]; then
      chars=0
    fi
    chars=$((10#$chars))

    warn_threshold=$((cap * 8 / 10))
    line=
    if (( chars > cap )); then
      line="VIOLATION: $name $chars chars > cap $cap"
    elif (( chars >= warn_threshold )); then
      line="WARNING: $name $chars chars >= 80% of cap $cap"
    fi

    if [[ -n "$line" ]]; then
      printf '%s\n' "$line" || true
      timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '0000-00-00T00:00:00Z')
      printf '%s %s\n' "$timestamp" "$line" >>"$pending/distill-runs.log" || true
    fi
  done

  return 0
}

write_skill_drafts() {
  local reply_file=$1
  local staging=$2
  local date_stamp=$3
  local count_file=$4
  local rejected_drafts=$5

  awk -v staging="$staging" -v date_stamp="$date_stamp" -v count_file="$count_file" -v rejected_drafts="$rejected_drafts" '
    BEGIN {
      while ((getline rejected_name < rejected_drafts) > 0) {
        rejected[rejected_name] = 1
      }
      close(rejected_drafts)
    }
    function close_skill() {
      if (name == "") {
        return
      }
      if (name in rejected) {
        return
      }
      draft_dir = staging "/" name
      skill_file = draft_dir "/SKILL.md"
      if (system("[ -e \"" draft_dir "\" ]") == 0) {
        print "skip: " draft_dir
      } else {
        system("mkdir -p \"" draft_dir "\"")
        description = first_proc
        if (description == "") {
          description = "Draft skill from distillation audit"
        }
        print "---" > skill_file
        print "name: " name >> skill_file
        print "description: " description >> skill_file
        print "trigger: " trigger >> skill_file
        print "status: draft" >> skill_file
        print "source: distill-audit " date_stamp >> skill_file
        print "---" >> skill_file
        print "" >> skill_file
        printf "%s", procedure >> skill_file
        print "" >> skill_file
        print "## Verification" >> skill_file
        print "(draft: define a concrete check before promotion — see skills/_staging/SKILL.tmpl.md)" >> skill_file
        close(skill_file)
        created++
      }
    }
    /^## SKILL_DRAFTS[[:space:]]*$/ {in_skills = 1; next}
    /^## / {if (in_skills) {close_skill(); in_skills = 0}; next}
    in_skills && /^### [a-z0-9][a-z0-9-]*[a-z0-9]$/ {
      close_skill()
      name = substr($0, 5)
      trigger = ""
      procedure = ""
      first_proc = ""
      saw_trigger = 0
      next
    }
    in_skills && name != "" && /^trigger:[[:space:]]*/ {
      trigger = $0
      sub(/^trigger:[[:space:]]*/, "", trigger)
      saw_trigger = 1
      next
    }
    in_skills && name != "" && saw_trigger && /^(source_task_id|target_skill|files_created):[[:space:]]*/ {next}
    in_skills && name != "" && saw_trigger {
      procedure = procedure $0 "\n"
      if (first_proc == "" && $0 !~ /^[[:space:]]*$/) {
        first_proc = $0
      }
      next
    }
    END {
      if (in_skills) {
        close_skill()
      }
      print created + 0 > count_file
      close(count_file)
    }
  ' "$reply_file"
}

is_safe_workspace_relative_path() {
  local path=$1

  if [[ -z "$path" || "$path" == /* ]]; then
    return 1
  fi

  case "/$path/" in
    */../*)
      return 1
      ;;
  esac

  return 0
}

check_draft_integrity() {
  local reply_file=$1
  local selected_list=$2
  local workspace_root=$3
  local task_id=$4
  local date_stamp=$5
  local rejected_drafts=$6
  local integrity_failures=$7
  local declarations="$integrity_failures.declarations"
  local draft_name
  local field
  local value
  local path
  local compact_value
  local selected_path
  local matched
  local failure_line
  local failure_hash

  : >"$rejected_drafts"
  : >"$integrity_failures"

  awk '
    /^## SKILL_DRAFTS[[:space:]]*$/ {in_skills = 1; name = ""; saw_trigger = 0; next}
    /^## / {in_skills = 0; name = ""; saw_trigger = 0; next}
    in_skills && /^### / {name = substr($0, 5); saw_trigger = 0; next}
    in_skills && name != "" && /^trigger:[[:space:]]*/ {saw_trigger = 1; next}
    in_skills && name != "" && saw_trigger && /^(source_task_id|target_skill|files_created):[[:space:]]*/ {
      field = $0
      sub(/:.*/, "", field)
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      print name "\t" field "\t" value
    }
  ' "$reply_file" >"$declarations" || true

  while IFS=$'\t' read -r draft_name field value || [[ -n "$draft_name" ]]; do
    value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    matched=1

    case "$field" in
      files_created)
        compact_value=${value//[[:space:]]/}
        if [[ -z "$compact_value" \
          || "$compact_value" == ,* \
          || "$compact_value" == *, \
          || "$compact_value" == *,,* ]]; then
          matched=0
        else
          IFS=',' read -r -a declared_paths <<<"$value"
          for path in "${declared_paths[@]}"; do
            path=$(printf '%s' "$path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if ! is_safe_workspace_relative_path "$path" || [[ ! -f "$workspace_root/$path" ]]; then
              matched=0
              value=$path
              break
            fi
          done
        fi
        ;;
      target_skill)
        if [[ ! "$value" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || [[ "$value" != "$draft_name" ]]; then
          matched=0
        fi
        ;;
      source_task_id)
        matched=0
        while IFS=$'\t' read -r _mtime _size selected_path || [[ -n "$selected_path" ]]; do
          if [[ "$value" == "$selected_path" || "$value" == "${selected_path##*/}" ]]; then
            matched=1
            break
          fi
        done <"$selected_list"
        ;;
    esac

    if [[ "$matched" -eq 0 ]]; then
      if ! grep -Fqx -- "$draft_name" "$rejected_drafts"; then
        printf '%s\n' "$draft_name" >>"$rejected_drafts"
      fi
      failure_line="- $date_stamp distill integrity mismatch: skill $draft_name declares $field=$value not found (source: distill-audit)"
      failure_hash=$(candidate_lesson_hash "$failure_line")
      printf '%s [dedup_key: %s:%s]\n' "$failure_line" "$task_id" "$failure_hash" >>"$integrity_failures"
    fi
  done <"$declarations"

  rm -f "$declarations"
  return 0
}

append_integrity_failures() {
  local reply_file=$1
  local integrity_failures=$2
  local output_file=$3

  if [[ ! -s "$integrity_failures" ]]; then
    return 0
  fi

  awk -v failures="$integrity_failures" '
    /^## OPEN_FAILURES[[:space:]]*$/ {
      print
      while ((getline line < failures) > 0) {
        print line
      }
      close(failures)
      next
    }
    {print}
  ' "$reply_file" >"$output_file" || return 0
  mv -f "$output_file" "$reply_file" || true
  return 0
}

workspace=
input_dirs=()

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
    --input)
      if (($# < 2)); then
        usage
        exit 2
      fi
      input_dirs+=("$2")
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$workspace" || ${#input_dirs[@]} -eq 0 ]]; then
  usage
  exit 2
fi

if [[ ! -d "$workspace" ]]; then
  usage
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-classify.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-bounded.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-wrapper-conformance.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-pause.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-state-fold.sh"
workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || {
  usage
  exit 2
}
pause_state=$(caty_pause_workspace_state "$workspace")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace" openclaw-distill-audit
  exit 0
fi
for input_dir in "${input_dirs[@]}"; do
  if [[ ! -d "$input_dir" ]]; then
    usage
    exit 2
  fi
done
distiller_cmd=${DISTILLER_CMD:-}
distiller_id=${DISTILLER_ID:-$distiller_cmd}
state_file="$workspace/STATE.md"
state_dir=$(cd "$(dirname "$state_file")" && pwd)
state_tmp_file="$state_dir/.STATE.md.tmp.$$"
marker_file="$workspace/loop/.distill-last-run"
pending_dir="$workspace/loop/pending"
staging_dir=${STAGING_DIR:-$workspace/skills/_staging}

if [[ ! -d "$pending_dir" ]]; then
  usage
  exit 2
fi

tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$tmp_root/distill-audit.XXXXXX")
# shellcheck disable=SC2329
cleanup() {
  release_state_lock
  rm -f "$state_tmp_file"
  rm -f "${distiller_tmp_file:-}"
  rm -rf "$work_dir"
  wrapper_conformance_cleanup_stage "$WRAPPER_CONFORMANCE_STAGE_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

candidate_list="$work_dir/candidates.tsv"
: >"$candidate_list"

if [[ -e "$marker_file" ]]; then
  for input_dir in "${input_dirs[@]}"; do
    find "$input_dir" -type f -newer "$marker_file" -exec sh -c '
      for path do
        case "${path##*/}" in
          *.trajectory.jsonl|*.trajectory.jsonl.*|heartbeat.json|heartbeat.json.*|heartbeat-state.json|heartbeat-state.json.*|catalog.json|catalog.json.*|skills-catalog.json|skills-catalog.json.*|sessions.json|sessions.json.*)
            continue
            ;;
        esac
        mtime=$(stat -c "%Y" "$path" 2>/dev/null || stat -f "%m" "$path")
        size=$(wc -c <"$path" | tr -d "[:space:]")
        printf "%s\t%s\t%s\n" "$mtime" "$size" "$path"
      done
    ' sh {} + >>"$candidate_list"
  done
else
  for input_dir in "${input_dirs[@]}"; do
    find "$input_dir" -type f -mtime -1 -exec sh -c '
      for path do
        case "${path##*/}" in
          *.trajectory.jsonl|*.trajectory.jsonl.*|heartbeat.json|heartbeat.json.*|heartbeat-state.json|heartbeat-state.json.*|catalog.json|catalog.json.*|skills-catalog.json|skills-catalog.json.*|sessions.json|sessions.json.*)
            continue
            ;;
        esac
        mtime=$(stat -c "%Y" "$path" 2>/dev/null || stat -f "%m" "$path")
        size=$(wc -c <"$path" | tr -d "[:space:]")
        printf "%s\t%s\t%s\n" "$mtime" "$size" "$path"
      done
    ' sh {} + >>"$candidate_list"
  done
fi

LC_ALL=C sort -n "$candidate_list" >"$work_dir/candidates.sorted.tsv"
mv "$work_dir/candidates.sorted.tsv" "$candidate_list"
files_scanned=$(wc -l <"$candidate_list" | tr -d '[:space:]')

if [[ "$files_scanned" -eq 0 ]]; then
  printf 'nothing to distill\n'
  touch "$marker_file"
  exit 0
fi

if ! wrapper_conformance_gate distiller DISTILLER_CMD "$distiller_cmd"; then
  infra_fail "wrapper conformance failed: $WRAPPER_CONFORMANCE_REASON"
fi
distiller_id=${DISTILLER_ID:-$WRAPPER_CONFORMANCE_WRAPPER_PATH}
distiller_argv=("$WRAPPER_CONFORMANCE_STAGED_PATH")

mkdir -p "$staging_dir"
find "$pending_dir" -maxdepth 1 -name '.distill-*.tmp.*' -mtime +1 -delete

cap_bytes=100000
per_file_bytes=60000
selected_list="$work_dir/selected.tsv"
cp "$candidate_list" "$selected_list"

while :; do
  total_bytes=$(
    awk -F '\t' -v per_file_bytes="$per_file_bytes" '{
      bytes = $2
      if (bytes > per_file_bytes) {
        bytes = per_file_bytes
      }
      total += bytes + length("--- " $3 " ---") + 80
    } END {print total + 0}' "$selected_list"
  )
  if [[ "$total_bytes" -le "$cap_bytes" ]]; then
    break
  fi
  sed '1d' "$selected_list" >"$work_dir/selected.next.tsv"
  mv "$work_dir/selected.next.tsv" "$selected_list"
done

selected_count=$(wc -l <"$selected_list" | tr -d '[:space:]')
dropped_count=$((files_scanned - selected_count))
# The sorted mtime/size/path list is the deterministic identity of this input batch.
task_id=$(sha256_file "$selected_list")
utc_date=$(date -u '+%Y-%m-%d')
prompt_file="$work_dir/prompt.md"

{
  printf '%s\n' 'Role: retrospective distillation auditor.'
  printf '%s\n' "Current UTC date: $utc_date"
  printf '%s\n' 'You are reading the day'\''s agent transcripts and outcomes for OpenClaw.'
  printf '%s\n' 'Extract only unverified operational observations and draft reusable procedures.'
  printf '%s\n' 'Concrete things to extract when present: errors and their apparent causes; commands that failed and what worked instead; discovered host facts (paths, auth states, versions, timezones); configuration decisions and their reasons; workarounds worth repeating.'
  printf '%s\n' 'On a day with real activity expect roughly 3-10 bullets; return empty sections ONLY when the inputs genuinely contain no such events. If the day has no durable learning, returning all sections empty is the correct and desired outcome, not a failure; never invent or pad observations to appear productive.'
  printf '%s\n' 'For each observation, classify the outcome as success, partial, fail, or uncertain in the fact wording without changing the bullet format. Verified evidence takes priority over heuristic inference; when evidence is absent, use uncertain rather than confidently claiming success or fail.'
  printf '%s\n' 'Do not save transient, environment-dependent failures (network blips, rate limits, one-off timeouts) as durable lessons.'
  printf '%s\n' 'Do not save negative absolute claims about a tool ("X does not work") — they stay wrong after the tool is fixed.'
  printf '%s\n' 'If a retry or workaround fixed it, save the FIX (the retry pattern), not the failure.'
  printf '%s\n' 'Observations violating these rules may be recorded ONLY as dated entries in Open failures — never in General rules, Verified facts, or skills.'
  printf '%s\n' 'This audit is retrospective distillation, not verification.'
  printf '%s\n' 'Do not claim verification of any fact, task, or skill; transcript-derived observations are unverified by definition because the maker reasoning trail is visible.'
  printf '\n%s\n' 'Your reply MUST contain exactly these three top-level sections, in this order:'
  printf '%s\n' '## LESSONS'
  printf '%s\n' '## OPEN_FAILURES'
  printf '%s\n' '## SKILL_DRAFTS'
  printf '%s\n' 'Forbid any other top-level sections.'
  printf '%s\n' 'LESSONS and OPEN_FAILURES: each line must be a dated one-line bullet of the form:'
  printf '%s\n' "- YYYY-MM-DD <one fact> (source: distill-audit)"
  printf '%s\n' 'SKILL_DRAFTS: zero or more blocks, each starting with ### <kebab-case-name>, followed by a trigger: line, followed by a short procedure. After trigger:, a block may optionally declare source_task_id: <value>, target_skill: <kebab-name>, and/or files_created: <ws-relative path>[, <ws-relative path>...].'
  printf '%s\n' 'These declarations are verified against reality. A block declaring a reference that does not exist is not turned into a skill and goes to Open failures; if unsure, omit declaration fields because omission is safe and has no effect.'
  printf '%s\n' 'If there is no content for a section, leave the section header present with no bullets or blocks.'
  if [[ "$dropped_count" -gt 0 ]]; then
    printf '\n%s\n' "[truncated: $dropped_count files dropped]"
  fi
  printf '\n%s\n' 'Collected files:'
  while IFS=$'\t' read -r _mtime size path; do
    printf '%s\n' "--- $path ---"
    if [[ "$size" -gt "$per_file_bytes" ]]; then
      printf '[truncated: showing last %s bytes of %s]\n' "$per_file_bytes" "$size"
      tail -c "$per_file_bytes" "$path"
    else
      cat "$path"
    fi
    printf '\n'
  done <"$selected_list"
} >"$prompt_file"

prompt=$(cat "$prompt_file")
reply_file="$pending_dir/distill-$utc_date.md"
distiller_tmp_file=$(mktemp "$pending_dir/.distill-$utc_date.md.tmp.XXXXXX")
distiller_stderr="$work_dir/distiller.stderr"
distill_timeout_s=$(resolve_timeout_env DISTILL_TIMEOUT_S 600)
distill_grace_s=$(resolve_timeout_env DISTILL_GRACE_S 10 1)

set +e
FABLE_CONFORMING_PROVIDER_PATH="$WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH" \
run_bounded "$distill_timeout_s" "$distill_grace_s" "${distiller_argv[@]}" "$prompt" \
  >"$distiller_tmp_file" 2>"$distiller_stderr"
distiller_status=$?
set -e

if [[ "$distiller_status" -ne 0 ]]; then
  failure_class=$(classify_failure "$distiller_status" "$distiller_stderr")
  cat "$distiller_stderr" >&2
  printf 'distill-audit.sh: call-site=distiller class=%s\n' "$failure_class" >&2
  exit 1
fi

if [[ -s "$distiller_tmp_file" ]] && [[ -n "$(tail -c1 "$distiller_tmp_file")" ]]; then
  printf '\n' >>"$distiller_tmp_file"
fi
# Serialize the prior-key snapshot, STATE fold, and pending replacement so two
# overlapping cron runs cannot both decide that the same key is new. The pending
# record is persisted only after its annotated observations have been folded.
take_state_lock "$workspace" openclaw-distill-audit
prior_dedup_keys="$work_dir/prior-dedup-keys.txt"
snapshot_pending_dedup_keys "$pending_dir" "$prior_dedup_keys" \
  'distill-*.md' 'intake-*.md'
annotated_reply_file="$work_dir/reply.annotated.md"
: >"$annotated_reply_file"
annotate_reply_dedup_keys "$distiller_tmp_file" "$task_id" "$annotated_reply_file" \
  '(source: distill-audit)' 'LESSONS OPEN_FAILURES'

rejected_drafts="$work_dir/rejected-drafts.txt"
integrity_failures="$work_dir/integrity-failures.txt"
check_draft_integrity "$annotated_reply_file" "$selected_list" "$workspace" "$task_id" "$utc_date" "$rejected_drafts" "$integrity_failures" || true
append_integrity_failures "$annotated_reply_file" "$integrity_failures" "$work_dir/reply.with-integrity.md" || true

lessons_file="$work_dir/lessons.txt"
failures_file="$work_dir/failures.txt"
: >"$lessons_file"
: >"$failures_file"

split_annotated_reply_sections "$annotated_reply_file" "$lessons_file" "$failures_file" \
  '(source: distill-audit)' 'LESSONS OPEN_FAILURES'

deduped_lessons="$work_dir/lessons.deduped.txt"
deduped_failures="$work_dir/failures.deduped.txt"
deduped_lessons_keys="$work_dir/lessons.deduped.keys"
deduped_failures_keys="$work_dir/failures.deduped.keys"
batch_hashes="$work_dir/batch.hashes"
normalized_lessons_state="$work_dir/state.lessons.normalized"
normalized_failures_state="$work_dir/state.failures.normalized"
: >"$deduped_lessons"
: >"$deduped_failures"
: >"$deduped_lessons_keys"
: >"$deduped_failures_keys"
: >"$batch_hashes"
snapshot_state_normalized_candidates "$state_file" "$normalized_lessons_state" \
  '## Lessons learned'
snapshot_state_normalized_candidates "$state_file" "$normalized_failures_state" \
  '## Open failures'

lessons_cap=$STATE_FOLD_LESSONS_CAP_DEFAULT
failures_cap=$STATE_FOLD_FAILURES_CAP_DEFAULT

while IFS=$'\t' read -r key line; do
  if [[ -n "$line" && -n "$key" ]] \
    && ! state_fold_candidate_is_duplicate "$key" "$line" "$prior_dedup_keys" \
      "$batch_hashes" "$state_file" "$normalized_lessons_state"; then
    printf '%s\n' "$line" >>"$deduped_lessons"
    printf '%s\n' "$key" >>"$deduped_lessons_keys"
    printf '%s\n' "${key##*:}" >>"$batch_hashes"
  fi
done <"$lessons_file"

while IFS=$'\t' read -r key line; do
  if [[ -n "$line" && -n "$key" ]] \
    && ! state_fold_candidate_is_duplicate "$key" "$line" "$prior_dedup_keys" \
      "$batch_hashes" "$state_file" "$normalized_failures_state"; then
    printf '%s\n' "$line" >>"$deduped_failures"
    printf '%s\n' "$key" >>"$deduped_failures_keys"
    printf '%s\n' "${key##*:}" >>"$batch_hashes"
  fi
done <"$failures_file"

lessons_added=$(wc -l <"$deduped_lessons" | tr -d '[:space:]')
failures_added=$(wc -l <"$deduped_failures" | tr -d '[:space:]')

if [[ "$lessons_added" -gt 0 || "$failures_added" -gt 0 ]]; then
  append_state_sections "$state_file" "$deduped_lessons" "$deduped_failures" \
    "$state_tmp_file" "$lessons_cap" "$failures_cap" "$work_dir/evicted-count.txt"
  mv -f "$state_tmp_file" "$state_file"
fi

drafts_count_file="$work_dir/drafts-created.txt"
: >"$drafts_count_file"
write_skill_drafts "$annotated_reply_file" "$staging_dir" "$utc_date" "$drafts_count_file" "$rejected_drafts"
drafts_created=$(cat "$drafts_count_file")

if [[ -e "$reply_file" ]]; then
  carried_dedup_keys="$work_dir/carried-dedup-keys.txt"
  : >"$carried_dedup_keys"
  extract_pending_dedup_keys "$reply_file" "$carried_dedup_keys"
  while IFS= read -r key; do
    printf '<!-- carried dedup_key: %s -->\n' "$key" >>"$annotated_reply_file"
  done <"$carried_dedup_keys"
fi
atomic_write_file "$annotated_reply_file" "$reply_file"

lessons_lines=$(section_count "## Lessons learned" "$state_file")
failures_lines=$(section_count "## Open failures" "$state_file")
release_state_lock

if [[ "$lessons_lines" -gt "$lessons_cap" ]]; then
  printf 'WARNING: Lessons learned over cap\n'
fi

if [[ "$failures_lines" -gt "$failures_cap" ]]; then
  printf 'WARNING: Open failures over cap\n'
fi

injection_size_check "$workspace" "$pending_dir"

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '%s | files_scanned=%s | lessons_added=%s | failures_added=%s | drafts_created=%s | distiller=%s\n' \
  "$timestamp" "$files_scanned" "$lessons_added" "$failures_added" "$drafts_created" "$distiller_id" \
  >>"$pending_dir/distill-runs.log"

touch "$marker_file"
exit 0
