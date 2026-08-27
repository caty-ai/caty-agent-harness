#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
APPLY_SCRIPT=$ROOT/scripts/apply-promotions.sh
APPLY_FIXTURE_TMP=${TMPDIR:-/tmp}/apply-promotions-test.$$
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FILTER=${APPLY_TEST_FILTER:-}
SECOND_RUN_WORKSPACES_FILE=$APPLY_FIXTURE_TMP/second-run-workspaces
SECOND_RUN_METADATA_FILE=$APPLY_FIXTURE_TMP/second-run-metadata

cleanup() { rm -rf "$APPLY_FIXTURE_TMP"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$APPLY_FIXTURE_TMP"
# shellcheck disable=SC1091
source "$ROOT/tests/apply-promotions/fixture-lib.sh"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail_case() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
skip_case() { SKIP_COUNT=$((SKIP_COUNT + 1)); printf 'SKIP %s\n' "$1"; }
assert_file_contains() { grep -Fq "$2" "$1"; }
assert_index_valid() {
  [[ ! -e "$1/loop/promotions/apply-index.tsv" ]] && return 0
  python3 -B - "$APPLY_SCRIPT" "$1/loop/promotions/apply-index.tsv" <<'PY'
from pathlib import Path
import re, sys
script = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"index_decision_table=\$\(cat <<'EOF'\n(.*?)\nEOF\n\)", script, re.S)
assert match, "missing index decision table"
decisions = {line.split()[0] for line in match.group(1).splitlines() if line.strip()}
theme = re.compile(r"theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}\Z")
applyid = re.compile(r"[0-9]{8}T[0-9]{6}Z-[0-9]+\Z")
ts = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
sha = re.compile(r"(?:-|[0-9a-f]{64})\Z")
seen = set()
for raw in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines():
    row = raw.split("\t")
    assert len(row) == 6
    assert theme.fullmatch(row[0])
    assert row[0] not in seen
    assert row[1] in {"capability-fact", "rule", "skill"}
    assert row[2] in decisions
    assert applyid.fullmatch(row[3])
    assert sha.fullmatch(row[4])
    assert ts.fullmatch(row[5])
    seen.add(row[0])
PY
}
assert_second_run() {
  local ws=$1 expected_rc=$2 outfile=$3
  shift 3
  fixture_run_apply "$ws" "$@" >"$outfile" 2>&1
  local rc=$?
  [[ "$rc" -eq "$expected_rc" ]] || return 1
  assert_index_valid "$ws"
}
note_second_run() {
  printf '%s\t%s\n' "$1" "$2" >>"$SECOND_RUN_METADATA_FILE"
}
clear_second_run() {
  : >"$SECOND_RUN_WORKSPACES_FILE"
  : >"$SECOND_RUN_METADATA_FILE"
}
assert_generic_index_second_runs() {
  local ws expected_rc sequence=0
  while IFS= read -r ws || [[ -n "$ws" ]]; do
    [[ -n "$ws" && -e "$ws/loop/promotions/apply-index.tsv" ]] || continue
    expected_rc=$(awk -F '\t' -v ws="$ws" '$1 == ws {value=$2; count++} END {if (count != 1) exit 1; print value}' "$SECOND_RUN_METADATA_FILE") || {
      printf 'missing or duplicate second-run metadata for index workspace: %s\n' "$ws" >&2
      return 1
    }
    sequence=$((sequence + 1))
    assert_second_run "$ws" "$expected_rc" "$APPLY_FIXTURE_TMP/generic-index-rerun.$sequence.out" || {
      printf 'generic second run failed for index workspace: %s\n' "$ws" >&2
      return 1
    }
    [[ -e "$ws/loop/promotions/apply-index.tsv" ]] || {
      printf 'generic second run removed index workspace state: %s\n' "$ws" >&2
      return 1
    }
  done <"$SECOND_RUN_WORKSPACES_FILE"
}
state_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1/STATE.md" | awk '{print $1}'
  else shasum -a 256 "$1/STATE.md" | awk '{print $1}'; fi
}

run_case() {
  local name=$1
  shift
  clear_second_run
  if [[ -n "$FILTER" ]] && ! printf '%s\n' "$name" | grep -Eq "$FILTER"; then return; fi
  if "$@"; then
    if ! assert_generic_index_second_runs; then
      fail_case "$name" "missing or failing generic second-run metadata for index workspace"
      return
    fi
    pass "$name"
  else
    case $? in
      77) skip_case "$name" ;;
      *) fail_case "$name" "fixture assertion failed" ;;
    esac
  fi
}

case_default_awaiting() {
  local ws runid before after
  ws=$(fixture_new_workspace default-awaiting); runid=20260827T010001Z-101
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Rules require explicit owner approval.' '2026-W33,2026-W34'
  before=$(state_sha "$ws")
  fixture_run_apply "$ws" >"$APPLY_FIXTURE_TMP/default.out" 2>&1 || return 1
  after=$(state_sha "$ws")
  note_second_run "$ws" 0
  [[ "$before" == "$after" ]] && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\tawaiting-approval\t' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=awaiting-approval' \
    && ! grep -Fq 'dangling-run-start=' "$APPLY_FIXTURE_TMP/default.out"
}

case_auto_and_index_idempotency() {
  local ws runid before after receipt_count
  ws=$(fixture_new_workspace auto-index); runid=20260827T010002Z-102
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'Bounded retries leave durable receipts.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  before=$(state_sha "$ws")
  receipt_count=$(grep -c 'theme=.*decision=promoted' "$ws/loop/promotions/apply.log")
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/index-rerun.out" || return 1
  after=$(state_sha "$ws")
  note_second_run "$ws" 0
  [[ "$before" == "$after" && "$receipt_count" -eq "$(grep -c 'theme=.*decision=promoted' "$ws/loop/promotions/apply.log")" ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/index-rerun.out" 'reason=already-applied' \
    && assert_index_valid "$ws"
}

case_stamp_self_heal() {
  local ws runid before
  ws=$(fixture_new_workspace stamp-heal); runid=20260827T010003Z-103
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'Stamp recovery restores the durable index.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  before=$(state_sha "$ws"); : >"$ws/loop/promotions/apply-index.tsv"
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/stamp.out" || return 1
  note_second_run "$ws" 0
  [[ "$before" == "$(state_sha "$ws")" ]] && assert_file_contains "$APPLY_FIXTURE_TMP/stamp.out" 'reason=already-applied' \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\tpromoted\t' \
    && [[ "$(grep -c 'reason=already-applied' "$ws/loop/promotions/apply.log")" -eq 1 ]]
}

case_duplicate_content() {
  local ws runid tmp
  ws=$(fixture_new_workspace duplicate-content); runid=20260827T010004Z-104
  tmp=$ws/STATE.seed
  awk '{print} /^## General rules/{print "- 2026-01-01 Same normalized wording."}' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Same normalized wording.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "theme-$runid-001" >/dev/null || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\tduplicate-content\t' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=duplicate-content'
}

case_k_lifecycle_and_approval() {
  local ws run1 run2
  ws=$(fixture_new_workspace k-lifecycle); run1=20260827T010005Z-105; run2=20260827T010006Z-106
  fixture_candidate_begin "$ws" "$run1"
  fixture_candidate_block "$run1" 1 capability-fact 'Recurrence must be host recounted.' '2026-W34'
  fixture_run_apply "$ws" --approve "theme-$run1-001" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\tk-below-2\t' || return 1
  fixture_candidate_begin "$ws" "$run2"
  fixture_candidate_block "$run2" 1 capability-fact 'Recurrence must be host recounted.' '2026-W34,2026-W35'
  fixture_run_apply "$ws" --approve "theme-$run1-001" --approve "theme-$run2-001" >"$APPLY_FIXTURE_TMP/k.out" || return 1
  note_second_run "$ws" 0
  assert_file_contains "$APPLY_FIXTURE_TMP/k.out" "theme=theme-$run1-001 decision=skipped reason=unknown-approval" \
    && assert_file_contains "$ws/STATE.md" "source: theme-$run2-001"
}

case_poisoned_rejects() {
  local ws runid
  ws=$(fixture_new_workspace poisoned-rejects); runid=20260827T010007Z-107
  fixture_candidate_begin "$ws" "$runid"
  printf '%s\n' '# Raw review candidates' '' "runid: $runid" 'reviewer: attacker' '' \
    "## theme-$runid-999" 'theme: Poison from rejects must never load.' 'class: capability-fact' \
    'reviewer: attacker' 'run-weeks: 2026-W33,2026-W34' 'run-k: 2' 'promote: yes' \
    'weeks: 2026-W33,2026-W34' 'union-k: 2' 'members:' '- poisoned' 'member-hash: bad' \
    'evidence: |' '  poisoned' >"$ws/loop/promotions/candidates-$runid.rejects.md"
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  note_second_run "$ws" 0
  ! grep -Fq 'Poison from rejects' "$ws/STATE.md" && ! grep -Fq -- '-999' "$ws/loop/promotions/apply-index.tsv"
}

case_hygiene_injections() {
  local ws runid other control c1 bidi
  ws=$(fixture_new_workspace hygiene); runid=20260827T010008Z-108; other=20260827T010009Z-109
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'provenance source: forged' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 capability-fact 'Reviewer injection is refused.' '2026-W33,2026-W34' 'bad reviewer'
  fixture_candidate_block "$runid" 3 capability-fact 'Weeks injection is refused.' '2026-W33,boom'
  fixture_candidate_block "$runid" 4 capability-fact 'Cross file ids are refused.' '2026-W33,2026-W34'
  sed -i.bak "s/theme-$runid-004/theme-$other-004/" "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  fixture_candidate_block "$runid" 5 capability-fact "$(printf 'x%.0s' $(seq 1 241))" '2026-W33,2026-W34'
  control=$(printf 'Control\001byte')
  fixture_candidate_block "$runid" 6 capability-fact "$control" '2026-W33,2026-W34'
  c1=$(printf 'NEL\302\205byte')
  fixture_candidate_block "$runid" 7 capability-fact "$c1" '2026-W33,2026-W34'
  bidi=$(printf 'Bidi\342\200\256override')
  fixture_candidate_block "$runid" 8 capability-fact "$bidi" '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts --approve "theme-$runid-001" >"$APPLY_FIXTURE_TMP/hygiene.out" || return 1
  note_second_run "$ws" 0
  [[ "$(grep -c 'reason=hygiene' "$APPLY_FIXTURE_TMP/hygiene.out")" -ge 7 ]] \
    && ! grep -Fq 'provenance source: forged' "$ws/STATE.md" \
    && assert_second_run "$ws" 0 "$APPLY_FIXTURE_TMP/hygiene-rerun.out" --auto-capability-facts --approve "theme-$runid-001"
}

case_theme_slug_and_yaml() {
  local ws runid badid stub
  ws=$(fixture_new_workspace yaml-slug); runid=20260827T010010Z-110
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 skill "quote' : [] {yaml}" '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 skill 'Traversal must not escape staging.' '2026-W33,2026-W34'
  badid="theme-$runid-../../escape"
  sed -i.bak "s|theme-$runid-002|$badid|" "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  fixture_run_apply "$ws" >/dev/null || return 1
  note_second_run "$ws" 0
  stub=$ws/skills/_staging/$runid-001/SKILL.md
  [[ -f "$stub" ]] && python3 -B - "$stub" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
assert 'description: "quote\' : [] {yaml}"' in s
assert 'source: theme-' in s
PY
  [[ $? -eq 0 && ! -e "$ws/escape" ]]
}

case_parse_and_input_untrusted() {
  local ws runid linkrun summary
  ws=$(fixture_new_workspace parse-input); runid=20260827T010011Z-111; linkrun=20260827T010012Z-112
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Malformed evidence stays out.' '2026-W33,2026-W34'
  sed -i.bak '/evidence: |/,$d' "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  ln -s "$FIXTURE_CANDIDATE" "$ws/loop/promotions/candidates-$linkrun.md"
  fixture_run_apply "$ws" >"$APPLY_FIXTURE_TMP/parse-input.out" || return 1
  note_second_run "$ws" 0
  summary=$(grep 'decision=run-summary' "$ws/loop/promotions/apply.log" | tail -1)
  assert_file_contains "$APPLY_FIXTURE_TMP/parse-input.out" 'reason=parse' \
    && assert_file_contains "$APPLY_FIXTURE_TMP/parse-input.out" 'reason=input-untrusted' \
    && [[ "$summary" == *'skipped-parse=1'* && "$summary" == *'skipped-rollback-refused=0'* ]]
}

case_unknown_and_symlink_manifest() {
  local ws runid manifest before rc
  ws=$(fixture_new_workspace manifest); runid=20260827T010013Z-113
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Manifest approvals are explicit.' '2026-W33,2026-W34'
  manifest=$APPLY_FIXTURE_TMP/approvals.txt
  printf '%s\n' 'theme-20260827T999999Z-999-999' >"$manifest"
  fixture_run_apply "$ws" --approve-file "$manifest" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=unknown-approval' || return 1
  ln -s "$manifest" "$APPLY_FIXTURE_TMP/approvals.link"
  before=$(state_sha "$ws")
  fixture_run_apply "$ws" --approve-file "$APPLY_FIXTURE_TMP/approvals.link" >/dev/null 2>&1; rc=$?
  note_second_run "$ws" 0
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] \
    && assert_index_valid "$ws"
}

case_stub_states_and_crash_replay() {
  local ws runid runid2 id id2 dir dir2 rc stub stub2
  ws=$(fixture_new_workspace stub-states); runid=20260827T010014Z-114; id=theme-$runid-001; dir=$ws/skills/_staging/$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 skill 'Stub replay converges after mkdir.' '2026-W33,2026-W34'
  APPLY_TEST_CRASH_AFTER_STUB_MKDIR=1 APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 "$APPLY_SCRIPT" --workspace "$ws" >/dev/null 2>&1; rc=$?
  [[ "$rc" -ne 0 && -d "$dir" && ! -e "$dir/SKILL.md" ]] || return 1
  rm -f "$ws/loop/promotions/.apply.lock/pid"; rmdir "$ws/loop/promotions/.apply.lock"
  rm -f "$ws/loop/.distill-state.lock/pid"; rmdir "$ws/loop/.distill-state.lock"
  fixture_run_apply "$ws" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-replay' || return 1
  stub=$dir/SKILL.md
  [[ -f "$stub" ]] || return 1
  : >"$ws/loop/promotions/apply-index.tsv"
  fixture_run_apply "$ws" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-replay' || return 1
  fixture_run_apply "$ws" --rollback "$id" --reason review-stub >/dev/null || return 1
  [[ ! -e "$stub" && ! -e "$dir" ]] || return 1
  runid2=20260827T010014Z-214; id2=theme-$runid2-001; dir2=$ws/skills/_staging/$runid2-001; stub2=$dir2/SKILL.md
  fixture_candidate_begin "$ws" "$runid2"
  fixture_candidate_block "$runid2" 1 skill 'Foreign stub remains terminal.' '2026-W33,2026-W34'
  mkdir -p "$dir2" || return 1
  printf '%s\n' 'manual content' >"$stub2"
  fixture_run_apply "$ws" >/dev/null || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-exists' \
    && assert_index_valid "$ws"
}

case_caps_boundary_and_section_full() {
  local ws runid
  ws=$(fixture_new_workspace caps); runid=20260827T010015Z-115
  fixture_add_lines "$ws" '## Verified facts' 119 capseed
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'The final headroom line is accepted.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 capability-fact 'The next line is refused at cap.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(fixture_section_count "$ws" '## Verified facts')" -eq 120 ]] \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-002\tcapability-fact\tsection-full\t'
}

case_volume_across_runs_and_auto_subcap() {
  local ws runid
  ws=$(fixture_new_workspace volume); runid=20260827T010016Z-116
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'Volume first.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 capability-fact 'Volume second.' '2026-W33,2026-W34'
  APPLY_MAX_PER_SECTION=1 APPLY_MAX_AUTO=1 fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-002\tcapability-fact\tvolume-guard\t' || return 1
  APPLY_MAX_PER_SECTION=1 APPLY_MAX_AUTO=1 fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(fixture_section_count "$ws" '## Verified facts')" -eq 2 ]] || return 1
  assert_index_valid "$ws"
}

case_eviction_resurrection() {
  local ws runid id tmp
  ws=$(fixture_new_workspace eviction); runid=20260827T010017Z-117; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'Evicted promotions never resurrect.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  tmp=$ws/STATE.evicted
  grep -Fv "source: $id" "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/eviction.out" || return 1
  note_second_run "$ws" 0
  ! grep -Fq "source: $id" "$ws/STATE.md" && assert_file_contains "$APPLY_FIXTURE_TMP/eviction.out" 'reason=already-applied' \
    && assert_second_run "$ws" 0 "$APPLY_FIXTURE_TMP/eviction-rerun.out" --auto-capability-facts
}

case_resurrection_sequence() {
  local ws victim_run batch_run victim tmp promoted_receipts
  ws=$(fixture_new_workspace resurrection-sequence)
  victim_run=20260827T010017Z-217
  batch_run=20260827T010017Z-218
  victim=theme-$victim_run-001
  fixture_candidate_begin "$ws" "$victim_run"
  fixture_candidate_block "$victim_run" 1 capability-fact 'Victim self-heals before ambiguity and stays non-resurrectable.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  promoted_receipts=$(grep -c "theme=$victim class=capability-fact decision=promoted" "$ws/loop/promotions/apply.log")
  : >"$ws/loop/promotions/apply-index.tsv"
  fixture_candidate_begin "$ws" "$batch_run"
  fixture_candidate_block "$batch_run" 1 capability-fact 'Ambiguous successor one.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_candidate_block "$batch_run" 2 capability-fact 'Ambiguous successor two.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/resurrection-heal.out" || return 1
  assert_file_contains "$APPLY_FIXTURE_TMP/resurrection-heal.out" "theme=$victim decision=skipped reason=already-applied" || return 1
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$victim_run"$'-001\tcapability-fact\tpromoted\t' || return 1
  [[ "$promoted_receipts" -eq "$(grep -c "theme=$victim class=capability-fact decision=promoted" "$ws/loop/promotions/apply.log")" ]] || return 1
  tmp=$ws/STATE.evicted
  grep -Fv "source: $victim" "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md" || return 1
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/resurrection-evict.out" || return 1
  note_second_run "$ws" 0
  ! grep -Fq "source: $victim" "$ws/STATE.md" || return 1
  assert_file_contains "$APPLY_FIXTURE_TMP/resurrection-evict.out" "theme=$victim decision=skipped reason=already-applied" || return 1
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$victim_run"$'-001\tcapability-fact\tpromoted\t' || return 1
  [[ "$promoted_receipts" -eq "$(grep -c "theme=$victim class=capability-fact decision=promoted" "$ws/loop/promotions/apply.log")" ]] \
    && assert_index_valid "$ws"
}

case_supersedes_applied_and_annotation() {
  local ws oldrun newrun oldid newid
  ws=$(fixture_new_workspace supersedes-applied); oldrun=20260827T010018Z-118; newrun=20260827T010019Z-119
  oldid=theme-$oldrun-001; newid=theme-$newrun-001
  fixture_candidate_begin "$ws" "$oldrun"; fixture_candidate_block "$oldrun" 1 rule 'Old rule wording.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$oldid" >/dev/null || return 1
  fixture_candidate_begin "$ws" "$newrun"; fixture_candidate_block "$newrun" 1 rule 'New rule wording.' '2026-W34,2026-W35' fixture-reviewer "$oldid"
  fixture_run_apply "$ws" --approve "$newid" >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(grep -c "invalidated-by: $newid" "$ws/STATE.md")" -eq 1 ]] || return 1
  fixture_run_apply "$ws" --approve "$newid" >/dev/null || return 1
  [[ "$(grep -c "invalidated-by: $newid" "$ws/STATE.md")" -eq 1 ]] \
    && assert_index_valid "$ws"
}

case_supersedes_unresolved_and_not_owned() {
  local ws runid unknown legacy newid tmp
  ws=$(fixture_new_workspace supersedes-edges); runid=20260827T010020Z-120
  unknown='theme-20260820T010000Z-20-001'; legacy='theme-20260820T010000Z-20-002'; newid=theme-$runid-001
  tmp=$ws/STATE.seed
  awk -v legacy="$legacy" '{print} /^## General rules/{print "- 2026-01-01 Legacy target (source: " legacy ")"}' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Unknown target still permits promotion.' '2026-W33,2026-W34' fixture-reviewer "$unknown"
  fixture_candidate_block "$runid" 2 rule 'Non-owned target blocks promotion.' '2026-W33,2026-W34' fixture-reviewer "$legacy"
  fixture_run_apply "$ws" --approve "$newid" --approve "theme-$runid-002" >/dev/null || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/loop/promotions/apply.log" 'note=supersedes-unresolved' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=supersedes-not-owned'
}

case_cross_run_pending_superseded() {
  local ws run1 run2 victim successor
  ws=$(fixture_new_workspace supersedes-pending); run1=20260827T010021Z-121; run2=20260827T010022Z-122
  victim=theme-$run1-001; successor=theme-$run2-001
  fixture_candidate_begin "$ws" "$run1"; fixture_candidate_block "$run1" 1 rule 'Pending old rule.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" >/dev/null || return 1
  fixture_candidate_begin "$ws" "$run2"; fixture_candidate_block "$run2" 1 rule 'Approved successor rule.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$successor" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$run1"$'-001\trule\tsuperseded\t' || return 1
  fixture_run_apply "$ws" --approve "$victim" >"$APPLY_FIXTURE_TMP/pending-approve.out" || return 1
  note_second_run "$ws" 0
  assert_file_contains "$APPLY_FIXTURE_TMP/pending-approve.out" 'reason=unknown-approval' \
    && ! grep -Fq 'Pending old rule' "$ws/STATE.md"
}

case_same_batch_and_ambiguity() {
  local ws runid victim
  ws=$(fixture_new_workspace supersedes-batch); runid=20260827T010023Z-123; victim=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Batch victim.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Batch successor one.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_candidate_block "$runid" 3 rule 'Batch successor two.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$victim" --approve "theme-$runid-002" --approve "theme-$runid-003" >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(grep -c 'reason=supersedes-ambiguous' "$ws/loop/promotions/apply.log")" -eq 3 ]] \
    && assert_index_valid "$ws"
}

case_same_batch_success_and_skip() {
  local ws runid victim successor
  ws=$(fixture_new_workspace supersedes-batch-success); runid=20260827T010024Z-124
  victim=theme-$runid-001; successor=theme-$runid-002
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Batch original.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Batch approved successor.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$successor" >/dev/null || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-001\trule\tsuperseded\t' \
    && ! grep -Fq 'Batch original.' "$ws/STATE.md"
}

case_same_batch_successor_skipped() {
  local ws runid victim successor
  ws=$(fixture_new_workspace supersedes-batch-skipped); runid=20260827T010024Z-224
  victim=theme-$runid-001; successor=theme-$runid-002
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Victim remains eligible when successor waits.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Unapproved successor waits.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$victim" >/dev/null || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/STATE.md" "source: $victim" \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-002\trule\tawaiting-approval\t' \
    && ! grep -Fq "source: $successor" "$ws/STATE.md" \
    && assert_index_valid "$ws"
}

case_supersedes_index_absent_rows() {
  local ws oldrun rollrun newrun newrun2 oldid rollid tmp
  ws=$(fixture_new_workspace supersedes-index-absent)
  oldrun=20260827T010024Z-324; rollrun=20260827T010024Z-325
  newrun=20260827T010024Z-326; newrun2=20260827T010024Z-327
  oldid=theme-$oldrun-001; rollid=theme-$rollrun-001
  fixture_candidate_begin "$ws" "$oldrun"; fixture_candidate_block "$oldrun" 1 rule 'Promoted target later evicted.' '2026-W33,2026-W34'
  fixture_candidate_begin "$ws" "$rollrun"; fixture_candidate_block "$rollrun" 1 rule 'Rolled target later absent.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$oldid" --approve "$rollid" >/dev/null || return 1
  fixture_run_apply "$ws" --rollback "$rollid" --reason review-absent >/dev/null || return 1
  tmp=$ws/STATE.absent
  grep -Fv "source: $oldid" "$ws/STATE.md" | grep -Fv "source: $rollid" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_candidate_begin "$ws" "$newrun"; fixture_candidate_block "$newrun" 1 rule 'Successor of evicted promoted target.' '2026-W34,2026-W35' fixture-reviewer "$oldid"
  fixture_candidate_begin "$ws" "$newrun2"; fixture_candidate_block "$newrun2" 1 rule 'Successor of absent rolled target.' '2026-W34,2026-W35' fixture-reviewer "$rollid"
  fixture_run_apply "$ws" --approve "theme-$newrun-001" --approve "theme-$newrun2-001" >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(grep -c 'note=supersedes-unresolved' "$ws/loop/promotions/apply.log")" -ge 2 ]] \
    && assert_index_valid "$ws"
}

case_supersedes_cycles_and_chains() {
  local ws runid id1 id2 id3 id4 id5
  ws=$(fixture_new_workspace supersedes-cycle-chain); runid=20260827T010024Z-424
  id1=theme-$runid-001; id2=theme-$runid-002; id3=theme-$runid-003; id4=theme-$runid-004; id5=theme-$runid-005
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Chain base.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Chain middle.' '2026-W34,2026-W35' fixture-reviewer "$id1"
  fixture_candidate_block "$runid" 3 rule 'Chain tip.' '2026-W35,2026-W36' fixture-reviewer "$id2"
  fixture_candidate_block "$runid" 4 rule 'Cycle left.' '2026-W33,2026-W34' fixture-reviewer "$id5"
  fixture_candidate_block "$runid" 5 rule 'Cycle right.' '2026-W34,2026-W35' fixture-reviewer "$id4"
  fixture_run_apply "$ws" --approve "$id1" --approve "$id2" --approve "$id3" --approve "$id4" --approve "$id5" >/dev/null || return 1
  note_second_run "$ws" 0
  [[ "$(grep -c 'reason=supersedes-ambiguous' "$ws/loop/promotions/apply.log")" -eq 5 ]] \
    && assert_index_valid "$ws"
}

case_rollback_terminal_and_dirty_stub() {
  local ws run1 run2 fact skill stub
  ws=$(fixture_new_workspace rollback); run1=20260827T010025Z-125; run2=20260827T010026Z-126
  fact=theme-$run1-001; skill=theme-$run2-001
  fixture_candidate_begin "$ws" "$run1"; fixture_candidate_block "$run1" 1 rule 'Rollback fact target.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$fact" >/dev/null || return 1
  fixture_run_apply "$ws" --rollback "$fact" --reason review-42 >/dev/null || return 1
  assert_file_contains "$ws/STATE.md" 'review missed review-42' || return 1
  fixture_run_apply "$ws" --approve "$fact" >"$APPLY_FIXTURE_TMP/rollback-approve.out" || return 1
  assert_file_contains "$APPLY_FIXTURE_TMP/rollback-approve.out" 'reason=unknown-approval' || return 1
  fixture_run_apply "$ws" --rollback "$fact" --reason review-42 >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=already-rolled-back' || return 1
  fixture_candidate_begin "$ws" "$run2"; fixture_candidate_block "$run2" 1 skill 'Dirty stub is preserved.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" >/dev/null || return 1
  stub=$ws/skills/_staging/$run2-001/SKILL.md
  printf '%s\n' '# human edit' >>"$stub"
  fixture_run_apply "$ws" --rollback "$skill" --reason review-43 >/dev/null || return 1
  note_second_run "$ws" 0
  [[ -f "$stub" ]] && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-dirty' \
    && assert_index_valid "$ws"
}

case_clean_stub_rollback_without_candidate() {
  local ws runid skill stub candidate
  ws=$(fixture_new_workspace rollback-stub-no-candidate); runid=20260827T010026Z-226
  skill=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"; candidate=$FIXTURE_CANDIDATE
  fixture_candidate_block "$runid" 1 skill 'Unchanged stub rolls back without its candidate.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" >/dev/null || return 1
  stub=$ws/skills/_staging/$runid-001/SKILL.md
  [[ -f "$stub" ]] || return 1
  mv "$candidate" "$APPLY_FIXTURE_TMP/removed-candidate.md"
  fixture_run_apply "$ws" --rollback "$skill" --reason review-clean >/dev/null || return 1
  note_second_run "$ws" 0
  [[ ! -e "$stub" ]] && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\trolled-back\t'
}

case_symlinked_workspace_roots() {
  local ws outside runid rc
  ws=$(fixture_new_workspace symlink-loop-root); outside=$APPLY_FIXTURE_TMP/outside-loop; mkdir "$outside"
  mv "$ws/loop" "$outside/original-loop"; ln -s "$outside" "$ws/loop"
  "$APPLY_SCRIPT" --workspace "$ws" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 && ! -e "$outside/promotions" ]] || return 1

  ws=$(fixture_new_workspace symlink-skills-root); outside=$APPLY_FIXTURE_TMP/outside-skills; mkdir "$outside"
  runid=20260827T010026Z-326; fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 skill 'Symlinked skills root is refused.' '2026-W33,2026-W34'
  mv "$ws/skills" "$outside/original-skills"; ln -s "$outside" "$ws/skills"
  "$APPLY_SCRIPT" --workspace "$ws" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 && ! -e "$outside/_staging" ]]
}

case_torn_index_rejects() {
  local ws runid before rc variant n=0 tmp
  ws=$(fixture_new_workspace torn-index); runid=20260827T010027Z-127
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Torn index refuses all.' '2026-W33,2026-W34'
  printf 'torn\trow\n' >"$ws/loop/promotions/apply-index.tsv"; before=$(state_sha "$ws")
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] || return 1
  rm -f "$ws/loop/promotions/apply-index.tsv"
}

case_heading_caps_read_failed() {
  local ws runid before rc variant n=0 tmp
  for variant in duplicate-vf duplicate-gr missing-vf missing-gr; do
    n=$((n + 1)); ws=$(fixture_new_workspace bad-headings-$variant); runid=20260827T010${n}28Z-12${n}
    fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Bad headings refuse all.' '2026-W33,2026-W34'
    case "$variant" in
      duplicate-vf) printf '%s\n' '## Verified facts duplicate' >>"$ws/STATE.md" ;;
      duplicate-gr) printf '%s\n' '## General rules duplicate' >>"$ws/STATE.md" ;;
      missing-vf) tmp=$ws/STATE.missing; grep -v '^## Verified facts' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md" ;;
      missing-gr) tmp=$ws/STATE.missing; grep -v '^## General rules' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md" ;;
    esac
    before=$(state_sha "$ws"); fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
    [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] || return 1
    assert_file_contains "$ws/loop/promotions/apply.log" 'reason=caps-read-failed' || return 1
  done
  note_second_run "$ws" 1
}

case_phase2_crash_replay() {
  local ws runid id rc before_lines
  ws=$(fixture_new_workspace phase2-crash); runid=20260827T010029Z-129; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Phase two replay is idempotent.' '2026-W33,2026-W34'
  APPLY_TEST_CRASH_AFTER_PHASE2=1 APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 "$APPLY_SCRIPT" --workspace "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] && assert_file_contains "$ws/STATE.md" "source: $id" && assert_file_contains "$ws/loop/promotions/apply-index.tsv" "$id" || return 1
  ! grep -Fq 'theme=.*decision=promoted' "$ws/loop/promotions/apply.log" || return 1
  rm -f "$ws/loop/promotions/.apply.lock/pid"; rmdir "$ws/loop/promotions/.apply.lock"
  rm -f "$ws/loop/.distill-state.lock/pid"; rmdir "$ws/loop/.distill-state.lock"
  before_lines=$(grep -c "source: $id" "$ws/STATE.md")
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/crash-replay.out" || return 1
  note_second_run "$ws" 0
  [[ "$before_lines" -eq "$(grep -c "source: $id" "$ws/STATE.md")" ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/crash-replay.out" 'dangling-run-start=' \
    && assert_index_valid "$ws"
}

case_state_index_crash_self_heal() {
  local ws runid id rc
  ws=$(fixture_new_workspace state-index-crash); runid=20260827T010030Z-130; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'State-first crash self-heals from stamp.' '2026-W33,2026-W34'
  APPLY_TEST_CRASH_BETWEEN_STATE_AND_INDEX=1 APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 "$APPLY_SCRIPT" --workspace "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] || return 1
  assert_file_contains "$ws/STATE.md" "source: $id" || return 1
  [[ ! -f "$ws/loop/promotions/apply-index.tsv" ]] || ! grep -Fq "$id" "$ws/loop/promotions/apply-index.tsv" || return 1
  rm -f "$ws/loop/promotions/.apply.lock/pid"; rmdir "$ws/loop/promotions/.apply.lock"
  rm -f "$ws/loop/.distill-state.lock/pid"; rmdir "$ws/loop/.distill-state.lock"
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/state-index-replay.out" || return 1
  note_second_run "$ws" 0
  assert_file_contains "$APPLY_FIXTURE_TMP/state-index-replay.out" 'dangling-run-start=' \
    && assert_file_contains "$APPLY_FIXTURE_TMP/state-index-replay.out" 'reason=already-applied' \
    && [[ "$(grep -c 'reason=already-applied' "$ws/loop/promotions/apply.log")" -eq 1 ]] \
    && assert_index_valid "$ws"
}

case_phase3_lock_busy_truthful() {
  local ws runid rc
  ws=$(fixture_new_workspace phase3-lock-busy); runid=20260827T010031Z-131
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Phase three lock-busy keeps truthful receipts.' '2026-W33,2026-W34'
  APPLY_TEST_FORCE_PHASE3_LOCK_BUSY=1 fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 ]] || return 1
  note_second_run "$ws" 0
  assert_file_contains "$ws/STATE.md" "source: theme-$runid-001" \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-001\tcapability-fact\tpromoted\t' \
    && assert_file_contains "$ws/loop/promotions/apply.log" "theme=theme-$runid-001 class=capability-fact decision=promoted reason=-" \
    && grep -F 'reason=lock-busy' "$ws/loop/promotions/apply.log" | grep -Fq 'promoted=1' \
    && assert_index_valid "$ws"
}

case_rollback_abort_summaries() {
  local ws runid id rc tmp summary
  ws=$(fixture_new_workspace rollback-target-invalid); runid=20260827T010032Z-132
  fixture_run_apply "$ws" --rollback "theme-$runid-001" --reason review-miss >"$APPLY_FIXTURE_TMP/rollback-target-invalid.out" 2>&1; rc=$?
  [[ "$rc" -eq 1 ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/rollback-target-invalid.out" 'rollback target is not an applied theme' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=rollback-refused' || return 1
  summary=$(grep 'decision=run-summary' "$ws/loop/promotions/apply.log" | tail -1)
  [[ "$summary" == *'skipped-rollback-refused=1'* ]] || return 1

  ws=$(fixture_new_workspace rollback-stamp-invalid); runid=20260827T010035Z-135; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 rule 'Rollback stamp loss is diagnosed.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$id" >/dev/null || return 1
  tmp=$ws/STATE.rollback-miss
  grep -Fv "source: $id" "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_run_apply "$ws" --rollback "$id" --reason review-miss >"$APPLY_FIXTURE_TMP/rollback-stamp-invalid.out" 2>&1; rc=$?
  note_second_run "$ws" 0
  [[ "$rc" -eq 1 ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/rollback-stamp-invalid.out" 'rollback stamp count is 0, expected 1' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=rollback-refused' || return 1

  ws=$(fixture_new_workspace rollback-open-failures-invalid); runid=20260827T010036Z-136; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 rule 'Rollback missing failures heading is diagnosed.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$id" >/dev/null || return 1
  tmp=$ws/STATE.rollback-failures
  grep -v '^## Open failures' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_run_apply "$ws" --rollback "$id" --reason review-miss >"$APPLY_FIXTURE_TMP/rollback-open-failures-invalid.out" 2>&1; rc=$?
  note_second_run "$ws" 0
  [[ "$rc" -eq 1 ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/rollback-open-failures-invalid.out" 'rollback Open failures heading count is 0, expected 1' \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=rollback-refused'
}

lock_case() {
  local kind=$1 ws runid lock before rc
  ws=$(fixture_new_workspace "lock-$kind"); runid=20260827T01003${kind}Z-13${kind}
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Lock refusal leaves state unchanged.' '2026-W33,2026-W34'
  case "$kind" in
    0) lock=$ws/loop/promotions/.apply.lock ;;
    1) lock=$ws/loop/promotions/.lock ;;
    2) lock=$ws/loop/.distill-state.lock ;;
  esac
  mkdir "$lock"; printf '999 fixture\n' >"$lock/pid"; before=$(state_sha "$ws")
  APPLY_LOCK_ATTEMPTS=1 APPLY_PROMOTIONS_LOCK_ATTEMPTS=1 APPLY_STATE_LOCK_ATTEMPTS=1 APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 \
    "$APPLY_SCRIPT" --workspace "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  note_second_run "$ws" 1
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=lock-busy'
}

case_paused() {
  local ws runid before rc
  ws=$(fixture_new_workspace paused); runid=20260827T010033Z-133
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Paused workspaces never mutate.' '2026-W33,2026-W34'
  mkdir -p "$ws/.caty-agent-harness"; : >"$ws/.caty-agent-harness/DISABLED"; before=$(state_sha "$ws")
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  note_second_run "$ws" 0
  [[ "$rc" -eq 0 && "$before" == "$(state_sha "$ws")" ]] \
    && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=skipped-paused' \
    && python3 -B - "$APPLY_SCRIPT" "$ws/loop/promotions/apply.log" <<'PY'
from pathlib import Path
import re, sys
script = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"reason_token_list=\$\(cat <<'EOF'\n(.*?)\nEOF\n\)", script, re.S)
assert match
tokens = [line for line in match.group(1).splitlines() if line]
line = [line for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
        if "decision=run-summary" in line and "reason=skipped-paused" in line][-1]
fields = line.split()
keys = [field.split("=", 1)[0] for field in fields if field.startswith("skipped-")]
assert len(keys) == len(set(keys)), line
for token in tokens:
    expected = "1" if token == "skipped-paused" else "0"
    assert fields.count(f"skipped-{token}={expected}") == 1, line
assert sum(field.startswith("skipped-skipped-paused=") for field in fields) == 1, line
PY
}

case_index_downgrade_refusal() {
  local harness=$APPLY_FIXTURE_TMP/index-downgrade-harness.sh
  local index_work=$APPLY_FIXTURE_TMP/index-downgrade.tsv before=$APPLY_FIXTURE_TMP/index-downgrade.before rc
  local id=theme-20260827T010037Z-137-001
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" rule promoted 20260827T010037Z-137 - 2026-08-27T01:03:07Z >"$index_work"
  cp "$index_work" "$before"
  {
    # The generated harness must expand these values when it runs, not now.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -u' \
      'tmp_root=${TMPDIR:-/tmp}/index-downgrade-harness.$$' 'mkdir -p "$tmp_root"' \
      'trap '\''rm -rf "$tmp_root"'\'' EXIT' \
      'index_work=$1' 'id=$2' 'apply_id=20260827T010038Z-138' 'run_ts=2026-08-27T01:03:08Z' \
      'index_decision_state() { return 0; }' \
      'pending_decision() { [[ "$1" == awaiting-approval ]]; }' \
      'index_decision() { printf '\''promoted\n'\''; }'
    awk '/^index_upsert\(\)/ {copy=1} copy {print} copy && /^}/ {exit}' "$APPLY_SCRIPT"
    # shellcheck disable=SC2016
    printf '%s\n' 'index_upsert "$id" rule awaiting-approval -'
  } >"$harness"
  bash "$harness" "$index_work" "$id" >"$APPLY_FIXTURE_TMP/index-downgrade.out" 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] \
    && cmp -s "$before" "$index_work" \
    && assert_file_contains "$APPLY_FIXTURE_TMP/index-downgrade.out" "refusing promoted-to-pending downgrade for $id"
}

case_malformed_receipt_noise_bound() {
  local ws runid id row_before row_after receipts_before receipts_after summary
  local invalid_ws invalid_run invalid_receipts_before invalid_receipts_after
  ws=$(fixture_new_workspace malformed-valid-id); runid=20260827T010039Z-139; id=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Persistent malformed valid ids transition once.' '2026-W33,2026-W34'
  sed -i.bak '/  Synthetic fixture evidence\./d' "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  fixture_run_apply "$ws" >/dev/null || return 1
  row_before=$(grep -F "$id" "$ws/loop/promotions/apply-index.tsv") || return 1
  receipts_before=$(grep -c "theme=$id class=rule decision=skipped reason=parse" "$ws/loop/promotions/apply.log")
  fixture_run_apply "$ws" >/dev/null || return 1
  note_second_run "$ws" 0
  row_after=$(grep -F "$id" "$ws/loop/promotions/apply-index.tsv") || return 1
  receipts_after=$(grep -c "theme=$id class=rule decision=skipped reason=parse" "$ws/loop/promotions/apply.log")
  summary=$(grep 'decision=run-summary' "$ws/loop/promotions/apply.log" | tail -1)
  [[ "$row_before" == "$row_after" && "$receipts_before" -eq 1 && "$receipts_after" -eq 1 \
    && "$summary" == *'skipped-parse=1'* ]] || return 1

  invalid_ws=$(fixture_new_workspace malformed-invalid-id); invalid_run=20260827T010040Z-140
  fixture_candidate_begin "$invalid_ws" "$invalid_run"
  fixture_candidate_block "$invalid_run" 1 rule 'Invalid ids keep nagging until garbage is removed.' '2026-W33,2026-W34'
  sed -i.bak "s/theme-$invalid_run-001/theme-$invalid_run-bad/" "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  fixture_run_apply "$invalid_ws" >/dev/null || return 1
  invalid_receipts_before=$(grep -c 'theme=- class=rule decision=skipped reason=hygiene' "$invalid_ws/loop/promotions/apply.log")
  fixture_run_apply "$invalid_ws" >/dev/null || return 1
  invalid_receipts_after=$(grep -c 'theme=- class=rule decision=skipped reason=hygiene' "$invalid_ws/loop/promotions/apply.log")
  note_second_run "$invalid_ws" 0
  [[ "$invalid_receipts_before" -eq 1 && "$invalid_receipts_after" -eq 2 ]]
}

case_index_gate_probe_body() {
  local ws runid
  ws=$(fixture_new_workspace index-gate-probe); runid=20260827T010041Z-141
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'A non-reason case cannot dodge the rerun invariant.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" >/dev/null
}

case_universal_second_run_gate() {
  (
    FILTER=
    SECOND_RUN_WORKSPACES_FILE=$APPLY_FIXTURE_TMP/index-gate-probe-workspaces
    SECOND_RUN_METADATA_FILE=$APPLY_FIXTURE_TMP/index-gate-probe-metadata
    probe_pass_count=0
    probe_fail_count=0
    pass() { probe_pass_count=$((probe_pass_count + 1)); }
    fail_case() { probe_fail_count=$((probe_fail_count + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
    clear_second_run
    run_case '[index-gate-probe]' case_index_gate_probe_body >"$APPLY_FIXTURE_TMP/index-gate-probe.out" 2>&1
    [[ "$probe_pass_count" -eq 0 && "$probe_fail_count" -eq 1 ]] \
      && assert_file_contains "$APPLY_FIXTURE_TMP/index-gate-probe.out" 'missing or failing generic second-run metadata'
  )
}

case_no_intermediate_overcap() {
  local ws runid i pid observed=0 count rc
  ws=$(fixture_new_workspace no-overcap); runid=20260827T010034Z-134
  fixture_add_lines "$ws" '## Verified facts' 119 observe
  fixture_candidate_begin "$ws" "$runid"
  i=1; while [[ "$i" -le 30 ]]; do fixture_candidate_block "$runid" "$i" capability-fact "Observed cap candidate $i." '2026-W33,2026-W34'; i=$((i+1)); done
  APPLY_MAX_PER_SECTION=30 APPLY_MAX_AUTO=30 fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    count=$(fixture_section_count "$ws" '## Verified facts')
    [[ "$count" -gt 120 ]] && observed=1
  done
  wait "$pid"; rc=$?
  note_second_run "$ws" 0
  [[ "$rc" -eq 0 && "$observed" -eq 0 && "$(fixture_section_count "$ws" '## Verified facts')" -eq 120 ]]
}

case_static_state_guard() {
  # These are literal source-code assertions.
  # shellcheck disable=SC2016
  ! grep -Eq '(>>?|tee[[:space:]]).*(\$state_file|/STATE\.md)' "$APPLY_SCRIPT" \
    && grep -Fq 'take_state_lock "$workspace" apply-promotions' "$APPLY_SCRIPT" \
    && [[ "$(grep -c 'atomic_write_file "$state_tmp" "$state_file"' "$APPLY_SCRIPT")" -eq 1 ]] \
    && ! grep -Fq 'fold_declared_state_caps ' "$APPLY_SCRIPT"
}

case_static_decision_vocabulary() {
  python3 -B - "$APPLY_SCRIPT" <<'PY'
from pathlib import Path
import re, sys
script = Path(sys.argv[1]).read_text(encoding="utf-8")
table = re.search(r"index_decision_table=\$\(cat <<'EOF'\n(.*?)\nEOF\n\)", script, re.S)
assert table, "missing single index decision table"
tokens = [line.split()[0] for line in table.group(1).splitlines() if line.strip()]
reasons = re.search(r"reason_token_list=\$\(cat <<'EOF'\n(.*?)\nEOF\n\)", script, re.S)
assert reasons, "missing summary reason token table"
reason_tokens = [line for line in reasons.group(1).splitlines() if line.strip()]
assert "supersedes-not-owned" in tokens
assert "awaiting-approval" in tokens
assert "rollback-refused" in reason_tokens
assert "rollback-refused" not in tokens
assert len(tokens) == len(set(tokens))
assert len(reason_tokens) == len(set(reason_tokens))
assert 'INDEX_DECISION_TABLE="$index_decision_table" python3 -B - "$index_work"' in script
assert "refusing invalid persisted decision" in script
assert "refusing promoted-to-pending downgrade" in script
assert "transition=1" in script
regex = re.search(r'filename_match = re.fullmatch\(r"(.*?)", filename\)', script)
assert regex
assert regex.group(1) == r"candidates-([0-9]{8}T[0-9]{6}Z-[0-9]+)\.md"
assert ".rejects" not in regex.group(1)
PY
}

case_static_rejects_two_layer() {
  python3 -B - "$APPLY_SCRIPT" <<'PY'
from pathlib import Path
import re, sys
script = Path(sys.argv[1]).read_text(encoding="utf-8")
bash_gate = re.search(r'if \[\[ "\$base" =~ (\^candidates-\[0-9\]\{8\}T\[0-9\]\{6\}Z-\[0-9\]\+\\\.md\$) \]\]; then', script)
assert bash_gate, "missing anchored bash candidates gate"
assert ".rejects" not in bash_gate.group(1)
py_gate = re.search(r'filename_match = re.fullmatch\(r"(.*?)", filename\)', script)
assert py_gate, "missing python filename gate"
assert py_gate.group(1) == r"candidates-([0-9]{8}T[0-9]{6}Z-[0-9]+)\.md"
assert ".rejects" not in py_gate.group(1)
PY
}

case_replay_corpus() {
  local corpus=${APPLY_REPLAY_CORPUS:-} ws base
  [[ -n "$corpus" ]] || return 77
  [[ -f "$corpus" && ! -L "$corpus" ]] || return 1
  base=${corpus##*/}
  printf '%s\n' "$base" | grep -Eq '^candidates-[0-9]{8}T[0-9]{6}Z-[0-9]+\.md$' || return 1
  ws=$(fixture_new_workspace corpus-replay)
  cp "$corpus" "$ws/loop/promotions/$base"
  fixture_run_apply "$ws" >/dev/null || return 1
  note_second_run "$ws" 0
}

run_case '[reason:awaiting-approval] bare run leaves STATE byte-identical' case_default_awaiting
run_case '[reason:already-applied/index] byte-identical immediate rerun emits no duplicate transition' case_auto_and_index_idempotency
run_case '[reason:already-applied/stamp] missing index self-heals from anchored STATE stamp' case_stamp_self_heal
run_case '[reason:duplicate-content] normalized section content blocks a new id' case_duplicate_content
run_case '[reason:k-below-2 + unknown-approval] approval cannot override k and re-emitted id is reconsidered' case_k_lifecycle_and_approval
run_case '[poisoned-rejects] anchored enumeration excludes model-raw rejects' case_poisoned_rejects
run_case '[provenance-spoof] reviewer weeks theme-id control oversize and banned source token fail hygiene' case_hygiene_injections
run_case '[slug-traversal + yaml-breakout] validated-id slug and JSON frontmatter encoding contain input' case_theme_slug_and_yaml
run_case '[reason:parse + input-untrusted] malformed block and symlink candidate fail closed' case_parse_and_input_untrusted
run_case '[reason:unknown-approval + symlink-manifest] unknown id is skipped and manifest symlink refused' case_unknown_and_symlink_manifest
run_case '[reason:stub-replay + stub-exists] canonical stub replays stay rollbackable and foreign stubs stay terminal' case_stub_states_and_crash_replay
run_case '[reason:section-full] cap-1 accepts exactly one without eviction' case_caps_boundary_and_section_full
run_case '[reason:volume-guard] per-section and auto sub-cap reset across runs' case_volume_across_runs_and_auto_subcap
run_case '[eviction-resurrection] apply-index prevents replay after line eviction' case_eviction_resurrection
run_case '[resurrection-sequence] self-heal beats ambiguity and eviction never re-promotes' case_resurrection_sequence
run_case '[supersedes annotation] owned prior line is annotated once' case_supersedes_applied_and_annotation
run_case '[reason:supersedes-not-owned + unresolved note] supersedes table edge rows' case_supersedes_unresolved_and_not_owned
run_case '[reason:superseded + unknown-approval] cross-run pending victim becomes terminal' case_cross_run_pending_superseded
run_case '[reason:supersedes-ambiguous] two superseders stop every side' case_same_batch_and_ambiguity
run_case '[reason:superseded] same-batch victim stops only after successor promotes' case_same_batch_success_and_skip
run_case '[same-batch successor skipped] victim evaluates independently when successor does not promote' case_same_batch_successor_skipped
run_case '[supersedes promoted/rolled absent] index-only targets promote with unresolved annotation' case_supersedes_index_absent_rows
run_case '[supersedes cycle + chain] ambiguous graphs stop every involved side' case_supersedes_cycles_and_chains
run_case '[reason:already-rolled-back + stub-dirty] rollback is terminal and preserves edited stub' case_rollback_terminal_and_dirty_stub
run_case '[clean-stub rollback without candidate] canonical apply stub remains independently reversible' case_clean_stub_rollback_without_candidate
run_case '[symlinked loop + skills roots] structural symlinks cannot redirect writes or rollback' case_symlinked_workspace_roots
run_case '[torn-index] invalid durable index aborts before any STATE write' case_torn_index_rejects
run_case '[reason:caps-read-failed] invalid headings abort with zero STATE bytes' case_heading_caps_read_failed
run_case '[phase-2-crash] same-hold index survives missing receipts and replay converges' case_phase2_crash_replay
run_case '[state/index-crash] STATE-first crash self-heals from the anchored stamp' case_state_index_crash_self_heal
run_case '[phase-3-lock-busy/test-seam] direct O_APPEND receipts keep ledger counts truthful' case_phase3_lock_busy_truthful
run_case '[reason:lock-busy/apply] apply-exclusive contention writes zero STATE bytes' lock_case 0
run_case '[reason:lock-busy/promotions] snapshot-lock contention writes zero STATE bytes' lock_case 1
run_case '[reason:lock-busy/state] state-lock contention writes zero STATE bytes' lock_case 2
run_case '[reason:skipped-paused] paused workspace exits zero without mutation' case_paused
run_case '[no-intermediate-overcap] live STATE never exposes an over-cap section' case_no_intermediate_overcap
run_case '[guarded-atomic-path] STATE publish has one locked atomic write and no fold call' case_static_state_guard
run_case '[rollback-abort-summaries] rollback refusals leave explicit run-summary reasons' case_rollback_abort_summaries
run_case '[index-downgrade-refusal] promoted rows refuse pending rewrites' case_index_downgrade_refusal
run_case '[malformed-receipt-noise] valid ids transition once while invalid ids keep nagging' case_malformed_receipt_noise_bound
run_case '[universal-second-run-gate] non-reason index writers cannot dodge rerun validation' case_universal_second_run_gate
run_case '[decision-vocabulary] single declared table feeds validation and rejects unsafe writes' case_static_decision_vocabulary
run_case '[rejects-two-layer] bash and python candidate gates both exclude .rejects.md' case_static_rejects_two_layer
run_case '[replay-real-corpus] env-gated private corpus replay' case_replay_corpus

printf '\nApply Promotions Summary: %s PASS, %s FAIL, %s SKIP\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
