#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
APPLY_SCRIPT=$ROOT/scripts/apply-promotions.sh
APPLY_FIXTURE_TMP=${TMPDIR:-/tmp}/apply-promotions-test.$$
PASS_COUNT=0
FAIL_COUNT=0
FILTER=${APPLY_TEST_FILTER:-}

cleanup() { rm -rf "$APPLY_FIXTURE_TMP"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$APPLY_FIXTURE_TMP"
# shellcheck disable=SC1091
source "$ROOT/tests/apply-promotions/fixture-lib.sh"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail_case() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
assert_file_contains() { grep -Fq "$2" "$1"; }
state_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1/STATE.md" | awk '{print $1}'
  else shasum -a 256 "$1/STATE.md" | awk '{print $1}'; fi
}

run_case() {
  local name=$1
  shift
  if [[ -n "$FILTER" ]] && ! printf '%s\n' "$name" | grep -Eq "$FILTER"; then return; fi
  if "$@"; then pass "$name"; else fail_case "$name" "fixture assertion failed"; fi
}

case_default_awaiting() {
  local ws runid before after
  ws=$(fixture_new_workspace default-awaiting); runid=20260827T010001Z-101
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Rules require explicit owner approval.' '2026-W33,2026-W34'
  before=$(state_sha "$ws")
  fixture_run_apply "$ws" >"$APPLY_FIXTURE_TMP/default.out" 2>&1 || return 1
  after=$(state_sha "$ws")
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
  [[ "$before" == "$after" && "$receipt_count" -eq "$(grep -c 'theme=.*decision=promoted' "$ws/loop/promotions/apply.log")" ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/index-rerun.out" 'reason=already-applied'
}

case_stamp_self_heal() {
  local ws runid before
  ws=$(fixture_new_workspace stamp-heal); runid=20260827T010003Z-103
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'Stamp recovery restores the durable index.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
  before=$(state_sha "$ws"); : >"$ws/loop/promotions/apply-index.tsv"
  fixture_run_apply "$ws" --auto-capability-facts >"$APPLY_FIXTURE_TMP/stamp.out" || return 1
  [[ "$before" == "$(state_sha "$ws")" ]] && assert_file_contains "$APPLY_FIXTURE_TMP/stamp.out" 'reason=already-applied' \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'\tpromoted\t'
}

case_duplicate_content() {
  local ws runid tmp
  ws=$(fixture_new_workspace duplicate-content); runid=20260827T010004Z-104
  tmp=$ws/STATE.seed
  awk '{print} /^## General rules/{print "- 2026-01-01 Same normalized wording."}' "$ws/STATE.md" >"$tmp" && mv "$tmp" "$ws/STATE.md"
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Same normalized wording.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "theme-$runid-001" >/dev/null || return 1
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
  ! grep -Fq 'Poison from rejects' "$ws/STATE.md" && ! grep -Fq -- '-999' "$ws/loop/promotions/apply-index.tsv"
}

case_hygiene_injections() {
  local ws runid other control
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
  fixture_run_apply "$ws" --auto-capability-facts --approve "theme-$runid-001" >"$APPLY_FIXTURE_TMP/hygiene.out" || return 1
  [[ "$(grep -c 'reason=hygiene' "$APPLY_FIXTURE_TMP/hygiene.out")" -ge 5 ]] \
    && ! grep -Fq 'provenance source: forged' "$ws/STATE.md"
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
  local ws runid linkrun
  ws=$(fixture_new_workspace parse-input); runid=20260827T010011Z-111; linkrun=20260827T010012Z-112
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Malformed evidence stays out.' '2026-W33,2026-W34'
  sed -i.bak '/evidence: |/,$d' "$FIXTURE_CANDIDATE" && rm -f "$FIXTURE_CANDIDATE.bak"
  ln -s "$FIXTURE_CANDIDATE" "$ws/loop/promotions/candidates-$linkrun.md"
  fixture_run_apply "$ws" >"$APPLY_FIXTURE_TMP/parse-input.out" || return 1
  assert_file_contains "$APPLY_FIXTURE_TMP/parse-input.out" 'reason=parse' \
    && assert_file_contains "$APPLY_FIXTURE_TMP/parse-input.out" 'reason=input-untrusted'
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
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]]
}

case_stub_states_and_crash_replay() {
  local ws runid id dir rc
  ws=$(fixture_new_workspace stub-states); runid=20260827T010014Z-114; id=theme-$runid-001; dir=$ws/skills/_staging/$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 skill 'Stub replay converges after mkdir.' '2026-W33,2026-W34'
  APPLY_TEST_CRASH_AFTER_STUB_MKDIR=1 APPLY_LOCK_SLEEP_S=0 APPLY_STATE_LOCK_SLEEP_S=0 "$APPLY_SCRIPT" --workspace "$ws" >/dev/null 2>&1; rc=$?
  [[ "$rc" -ne 0 && -d "$dir" && ! -e "$dir/SKILL.md" ]] || return 1
  rm -f "$ws/loop/promotions/.apply.lock/pid"; rmdir "$ws/loop/promotions/.apply.lock"
  rm -f "$ws/loop/.distill-state.lock/pid"; rmdir "$ws/loop/.distill-state.lock"
  fixture_run_apply "$ws" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-replay' || return 1
  : >"$ws/loop/promotions/apply-index.tsv"
  fixture_run_apply "$ws" >/dev/null || return 1
  assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-exists'
}

case_caps_boundary_and_section_full() {
  local ws runid
  ws=$(fixture_new_workspace caps); runid=20260827T010015Z-115
  fixture_add_lines "$ws" '## Verified facts' 119 capseed
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 capability-fact 'The final headroom line is accepted.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 capability-fact 'The next line is refused at cap.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null || return 1
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
  [[ "$(fixture_section_count "$ws" '## Verified facts')" -eq 2 ]]
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
  ! grep -Fq "source: $id" "$ws/STATE.md" && assert_file_contains "$APPLY_FIXTURE_TMP/eviction.out" 'reason=already-applied'
}

case_supersedes_applied_and_annotation() {
  local ws oldrun newrun oldid newid
  ws=$(fixture_new_workspace supersedes-applied); oldrun=20260827T010018Z-118; newrun=20260827T010019Z-119
  oldid=theme-$oldrun-001; newid=theme-$newrun-001
  fixture_candidate_begin "$ws" "$oldrun"; fixture_candidate_block "$oldrun" 1 rule 'Old rule wording.' '2026-W33,2026-W34'
  fixture_run_apply "$ws" --approve "$oldid" >/dev/null || return 1
  fixture_candidate_begin "$ws" "$newrun"; fixture_candidate_block "$newrun" 1 rule 'New rule wording.' '2026-W34,2026-W35' fixture-reviewer "$oldid"
  fixture_run_apply "$ws" --approve "$newid" >/dev/null || return 1
  [[ "$(grep -c "invalidated-by: $newid" "$ws/STATE.md")" -eq 1 ]] || return 1
  fixture_run_apply "$ws" --approve "$newid" >/dev/null || return 1
  [[ "$(grep -c "invalidated-by: $newid" "$ws/STATE.md")" -eq 1 ]]
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
  assert_file_contains "$APPLY_FIXTURE_TMP/pending-approve.out" 'reason=unknown-approval' && ! grep -Fq 'Pending old rule' "$ws/STATE.md"
}

case_same_batch_and_ambiguity() {
  local ws runid victim
  ws=$(fixture_new_workspace supersedes-batch); runid=20260827T010023Z-123; victim=theme-$runid-001
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Batch victim.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Batch successor one.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_candidate_block "$runid" 3 rule 'Batch successor two.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$victim" --approve "theme-$runid-002" --approve "theme-$runid-003" >/dev/null || return 1
  [[ "$(grep -c 'reason=supersedes-ambiguous' "$ws/loop/promotions/apply.log")" -eq 3 ]]
}

case_same_batch_success_and_skip() {
  local ws runid victim successor
  ws=$(fixture_new_workspace supersedes-batch-success); runid=20260827T010024Z-124
  victim=theme-$runid-001; successor=theme-$runid-002
  fixture_candidate_begin "$ws" "$runid"
  fixture_candidate_block "$runid" 1 rule 'Batch original.' '2026-W33,2026-W34'
  fixture_candidate_block "$runid" 2 rule 'Batch approved successor.' '2026-W34,2026-W35' fixture-reviewer "$victim"
  fixture_run_apply "$ws" --approve "$successor" >/dev/null || return 1
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
  assert_file_contains "$ws/STATE.md" "source: $victim" \
    && assert_file_contains "$ws/loop/promotions/apply-index.tsv" $'theme-'"$runid"$'-002\trule\tawaiting-approval\t' \
    && ! grep -Fq "source: $successor" "$ws/STATE.md"
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
  [[ "$(grep -c 'note=supersedes-unresolved' "$ws/loop/promotions/apply.log")" -ge 2 ]]
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
  [[ "$(grep -c 'reason=supersedes-ambiguous' "$ws/loop/promotions/apply.log")" -eq 5 ]]
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
  [[ -f "$stub" ]] && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=stub-dirty'
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

case_torn_index_and_headings() {
  local ws runid before rc variant n=0 tmp
  ws=$(fixture_new_workspace torn-index); runid=20260827T010027Z-127
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Torn index refuses all.' '2026-W33,2026-W34'
  printf 'torn\trow\n' >"$ws/loop/promotions/apply-index.tsv"; before=$(state_sha "$ws")
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] || return 1
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
  [[ "$before_lines" -eq "$(grep -c "source: $id" "$ws/STATE.md")" ]] \
    && assert_file_contains "$APPLY_FIXTURE_TMP/crash-replay.out" 'dangling-run-start='
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
  [[ "$rc" -eq 1 && "$before" == "$(state_sha "$ws")" ]] && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=lock-busy'
}

case_paused() {
  local ws runid before rc
  ws=$(fixture_new_workspace paused); runid=20260827T010033Z-133
  fixture_candidate_begin "$ws" "$runid"; fixture_candidate_block "$runid" 1 capability-fact 'Paused workspaces never mutate.' '2026-W33,2026-W34'
  mkdir -p "$ws/.caty-agent-harness"; : >"$ws/.caty-agent-harness/DISABLED"; before=$(state_sha "$ws")
  fixture_run_apply "$ws" --auto-capability-facts >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 && "$before" == "$(state_sha "$ws")" ]] && assert_file_contains "$ws/loop/promotions/apply.log" 'reason=skipped-paused'
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

case_replay_corpus() {
  local corpus=${APPLY_REPLAY_CORPUS:-} ws base
  [[ -n "$corpus" ]] || { printf 'INFO replay-real-corpus not configured (APPLY_REPLAY_CORPUS unset)\n'; return 0; }
  [[ -f "$corpus" && ! -L "$corpus" ]] || return 1
  base=${corpus##*/}
  printf '%s\n' "$base" | grep -Eq '^candidates-[0-9]{8}T[0-9]{6}Z-[0-9]+\.md$' || return 1
  ws=$(fixture_new_workspace corpus-replay)
  cp "$corpus" "$ws/loop/promotions/$base"
  fixture_run_apply "$ws" >/dev/null
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
run_case '[reason:stub-replay + stub-exists] mkdir crash converges and existing stub is terminal' case_stub_states_and_crash_replay
run_case '[reason:section-full] cap-1 accepts exactly one without eviction' case_caps_boundary_and_section_full
run_case '[reason:volume-guard] per-section and auto sub-cap reset across runs' case_volume_across_runs_and_auto_subcap
run_case '[eviction-resurrection] apply-index prevents replay after line eviction' case_eviction_resurrection
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
run_case '[reason:caps-read-failed] torn index and duplicate heading abort with zero STATE bytes' case_torn_index_and_headings
run_case '[phase-2-crash] same-hold index survives missing receipts and replay converges' case_phase2_crash_replay
run_case '[reason:lock-busy/apply] apply-exclusive contention writes zero STATE bytes' lock_case 0
run_case '[reason:lock-busy/promotions] snapshot-lock contention writes zero STATE bytes' lock_case 1
run_case '[reason:lock-busy/state] state-lock contention writes zero STATE bytes' lock_case 2
run_case '[reason:skipped-paused] paused workspace exits zero without mutation' case_paused
run_case '[no-intermediate-overcap] live STATE never exposes an over-cap section' case_no_intermediate_overcap
run_case '[guarded-atomic-path] STATE publish has one locked atomic write and no fold call' case_static_state_guard
run_case '[replay-real-corpus] env-gated private corpus replay' case_replay_corpus

printf '\nApply Promotions Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
