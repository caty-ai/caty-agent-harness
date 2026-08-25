#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/caty-pause-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
failures=0
coverage_file="$TMP/guarded-coverage"
: >"$coverage_file"

pass() { printf 'ok - %s\n' "$1"; }
fail_case() {
  printf 'not ok - %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

cover() {
  printf '%s\t%s\n' "$1" "$2" >>"$coverage_file"
}

file_signature() {
  local path=$1
  local stat_record
  local digest
  if stat_record=$(stat -c '%F|%s|%Y|%a' "$path" 2>/dev/null); then
    :
  else
    stat_record=$(stat -f '%HT|%z|%m|%Lp' "$path")
  fi
  digest=$(shasum -a 256 "$path" 2>/dev/null | awk '{print $1}' || true)
  [[ -n "$digest" ]] || digest=unreadable
  printf '%s|%s\n' "$stat_record" "$digest"
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail_case "$name" "expected=$expected actual=$actual"
  fi
}

capture_run() {
  local key=$1
  shift
  CAPTURE_STDOUT="$TMP/$key.stdout"
  CAPTURE_STDERR="$TMP/$key.stderr"
  set +e
  "$@" >"$CAPTURE_STDOUT" 2>"$CAPTURE_STDERR"
  CAPTURE_RC=$?
  set -e
  CAPTURE_OUT=$(cat "$CAPTURE_STDOUT")
  CAPTURE_ERR=$(cat "$CAPTURE_STDERR")
}

assert_paused_automation_capture() {
  local name=$1
  local workspace=$2
  local entrypoint=$3
  local expected_rc=${4:-0}
  assert_eq "$name exit" "$expected_rc" "$CAPTURE_RC"
  assert_eq "$name stdout is empty" "" "$CAPTURE_OUT"
  assert_eq "$name stderr is one stable record" \
    "status=paused workspace=$workspace entrypoint=$entrypoint" "$CAPTURE_ERR"
}

snapshot_workspace() {
  local workspace=$1
  snapshot_paths "$workspace" 1
}

snapshot_entire_workspace() {
  local workspace=$1
  snapshot_paths "$workspace" 0
}

snapshot_paths() {
  local workspace=$1
  local exclude_control=$2

  python3 - "$workspace" "$exclude_control" <<'PY'
import hashlib
import os
import stat
import sys

root = os.path.realpath(sys.argv[1])
exclude_control = sys.argv[2] == "1"
records = []

def add(path):
    rel = os.path.relpath(path, root)
    display = "." if rel == "." else "./" + rel
    if exclude_control and rel == ".":
        return
    if exclude_control and (rel == ".caty-agent-harness" or rel.startswith(".caty-agent-harness/")):
        return
    st = os.lstat(path)
    mode = st.st_mode
    if stat.S_ISREG(mode):
        kind = "file"
        try:
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
        except PermissionError:
            digest = "unreadable"
        target = "-"
    elif stat.S_ISDIR(mode):
        kind, digest, target = "dir", "-", "-"
    elif stat.S_ISLNK(mode):
        kind, digest, target = "symlink", "-", os.readlink(path)
    elif stat.S_ISFIFO(mode):
        kind, digest, target = "fifo", "-", "-"
    elif stat.S_ISSOCK(mode):
        kind, digest, target = "socket", "-", "-"
    elif stat.S_ISCHR(mode):
        kind, digest, target = "char", "-", "-"
    elif stat.S_ISBLK(mode):
        kind, digest, target = "block", "-", "-"
    else:
        kind, digest, target = "other", "-", "-"
    records.append((
        display,
        kind,
        format(stat.S_IMODE(mode), "04o"),
        str(st.st_size),
        str(st.st_mtime_ns),
        target,
        digest,
    ))

add(root)
for current, directories, files in os.walk(root, topdown=True, followlinks=False):
    directories.sort()
    files.sort()
    for name in directories + files:
        add(os.path.join(current, name))

for record in sorted(records):
    print("\t".join(record))
PY
}

new_workspace() {
  local name=$1
  local workspace="$TMP/$name"
  mkdir -p "$workspace"
  "$ROOT/install.sh" --workspace "$workspace" >/dev/null
  workspace=$(cd "$workspace" && pwd -P)
  printf '%s\n' "$workspace"
}

root_control_dir="$ROOT/.caty-agent-harness"
if [[ ! -e "$root_control_dir" && ! -L "$root_control_dir" ]]; then
  pass "pause contract starts with no harness control artifact in repository root"
else
  fail_case "pause contract starts with no harness control artifact in repository root" \
    "unexpected path: $root_control_dir"
fi

errexit_on=$(bash -c 'set -e; source "$1"; caty_pause_value_is_record_safe abc; case $- in *e*) printf on;; *) printf off;; esac' _ "$ROOT/scripts/lib-pause.sh")
errexit_off=$(bash -c 'set +e; source "$1"; caty_pause_value_is_record_safe abc; case $- in *e*) printf on;; *) printf off;; esac' _ "$ROOT/scripts/lib-pause.sh")
assert_eq "record-safe helper preserves enabled errexit" "on" "$errexit_on"
assert_eq "record-safe helper preserves disabled errexit" "off" "$errexit_off"

ws=$(new_workspace primary)
mkdir -p "$ws/loop/tasks/queue"
printf 'preserve queue\n' >"$ws/loop/tasks/queue/preserved.task.md"
printf 'preserve artifact\n' >"$ws/loop/artifacts/preserved.txt"
printf 'preserve pending\n' >"$ws/loop/pending/preserved.md"
printf 'preserve skill\n' >"$ws/skills/preserved.txt"
before=$(snapshot_workspace "$ws")
dry_before=$(snapshot_entire_workspace "$ws")

dry_output=$("$ROOT/install.sh" --disable --workspace "$ws" --dry-run)
dry_after=$(snapshot_entire_workspace "$ws")
assert_eq "disable dry-run reports canonical workspace" "workspace=$ws" "$(printf '%s\n' "$dry_output" | head -n1)"
assert_eq "disable dry-run preserves exact path, type, size, mtime, mode, and hash set" "$dry_before" "$dry_after"
[[ ! -e "$ws/.caty-agent-harness" ]] \
  && pass "disable dry-run does not create control directory" \
  || fail_case "disable dry-run does not create control directory" "control directory exists"

"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
marker="$ws/.caty-agent-harness/DISABLED"
[[ -f "$marker" && ! -L "$marker" ]] \
  && pass "disable creates a regular marker" \
  || fail_case "disable creates a regular marker" "missing or hostile marker"
grep -Fqx 'schema=caty-agent-harness-pause/v1' "$marker" \
  && pass "marker carries v1 schema" \
  || fail_case "marker carries v1 schema" "schema missing"
assert_eq "disable preserves operational data" "$before" "$(snapshot_workspace "$ws")"

marker_before=$(shasum -a 256 "$marker" | awk '{print $1}')
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
marker_after=$(shasum -a 256 "$marker" | awk '{print $1}')
assert_eq "disable is byte-preserving when already paused" "$marker_before" "$marker_after"

capture_run check-paused "$ROOT/install.sh" --check --workspace "$ws"
check_output=$CAPTURE_OUT
grep -Fqx 'state=paused-soft-unknown' <<<"$CAPTURE_OUT" \
  && pass "check reports unknown soft-bootstrap pause" \
  || fail_case "check reports unknown soft-bootstrap pause" "$CAPTURE_OUT"
grep -Fqx 'bootstrap_state=unknown' <<<"$CAPTURE_OUT" \
  && pass "check reports unknown bootstrap state" \
  || fail_case "check reports unknown bootstrap state" "$CAPTURE_OUT"
[[ "$CAPTURE_ERR" != *"state=paused-soft-unknown"* && "$CAPTURE_ERR" != *"bootstrap_state=unknown"* ]] \
  && pass "check machine tokens stay on stdout" \
  || fail_case "check machine tokens stay on stdout" "$CAPTURE_ERR"
[[ "$CAPTURE_OUT" != *"warning:"* ]] \
  && pass "check stdout contains no human warning records" \
  || fail_case "check stdout contains no human warning records" "$CAPTURE_OUT"
[[ "$CAPTURE_ERR" == *"warning:"* ]] \
  && pass "check human warnings are emitted on stderr" \
  || fail_case "check human warnings are emitted on stderr" "$CAPTURE_ERR"

enqueue_before=$(snapshot_workspace "$ws")
capture_run enqueue-paused "$ROOT/scripts/tr-enqueue" "$ROOT/tests/fixtures/task-basic.task.md" "$ws"
assert_paused_automation_capture "paused enqueue" "$ws" tr-enqueue 3
assert_eq "paused enqueue valid fixture leaves exact workspace snapshot" "$enqueue_before" "$(snapshot_workspace "$ws")"
cover scripts/tr-enqueue exit-3-status
[[ -f "$ws/loop/tasks/queue/preserved.task.md" ]] \
  && pass "paused enqueue preserves existing queue" \
  || fail_case "paused enqueue preserves existing queue" "queue entry missing"

model_sentinel="$TMP/model-called"
fake_model="$TMP/fake-model"
printf '%s\n' '#!/usr/bin/env bash' ': >"$MODEL_SENTINEL"' >"$fake_model"
chmod +x "$fake_model"
runner_before=$(snapshot_workspace "$ws")
capture_run runner-paused env MODEL_SENTINEL="$model_sentinel" TR_SPAWN_STEP="$fake_model" "$ROOT/scripts/task-runner.sh" "$ws"
assert_paused_automation_capture "paused task runner" "$ws" task-runner
assert_eq "paused task runner leaves exact workspace snapshot" "$runner_before" "$(snapshot_workspace "$ws")"
cover scripts/task-runner.sh exit-0-status
[[ ! -e "$model_sentinel" ]] \
  && pass "paused task runner does not start the configured model" \
  || fail_case "paused task runner does not start the configured model" "model sentinel exists"

printf 'producer=producer-model\nreviewer other-model %s\n' "$fake_model" >"$ws/loop/review.conf"
raw_review_receipts_before=$(awk 'END {print NR + 0}' "$ws/loop/promotions/runs.log" 2>/dev/null || printf '0\n')
capture_run raw-review-paused "$ROOT/scripts/raw-review.sh" --workspace "$ws"
assert_eq "paused raw review exits zero" "0" "$CAPTURE_RC"
assert_eq "paused raw review stdout is empty" "" "$CAPTURE_OUT"
assert_eq "paused raw review stderr is empty" "" "$CAPTURE_ERR"
raw_review_receipts_after=$(awk 'END {print NR + 0}' "$ws/loop/promotions/runs.log")
assert_eq "paused raw review appends exactly one receipt" "$((raw_review_receipts_before + 1))" "$raw_review_receipts_after"
grep -Fq ' error=skipped-paused' "$ws/loop/promotions/runs.log" \
  && pass "paused raw review records skipped-paused" \
  || fail_case "paused raw review records skipped-paused" "$(cat "$ws/loop/promotions/runs.log")"
[[ ! -e "$model_sentinel" ]] \
  && pass "paused raw review does not start the configured model" \
  || fail_case "paused raw review does not start the configured model" "model sentinel exists"
cover scripts/raw-review.sh exit-0-receipt

for hook in \
  adapters/claude-code/checkpoint-stop-hook.sh \
  adapters/claude-code/precompact-flush-hook.sh \
  adapters/codex/checkpoint-stop-hook.sh \
  adapters/kimi/checkpoint-stop-hook.sh; do
  hook_before=$(snapshot_workspace "$ws")
  printf '{"cwd":"%s","session_id":"pause-test-%s","trigger":"manual"}\n' "$ws" "${hook//\//-}" >"$TMP/hook-input"
  set +e
  "$ROOT/$hook" <"$TMP/hook-input" >"$TMP/hook.stdout" 2>"$TMP/hook.stderr"
  hook_rc=$?
  set -e
  assert_eq "paused hook allows silently: $hook rc" "0" "$hook_rc"
  assert_eq "paused hook allows silently: $hook stdout" "" "$(cat "$TMP/hook.stdout")"
  assert_eq "paused hook allows silently: $hook stderr" "" "$(cat "$TMP/hook.stderr")"
  assert_eq "paused hook leaves exact workspace snapshot: $hook" "$hook_before" "$(snapshot_workspace "$ws")"
  cover "$hook" exit-0-silent
done

sentinel_before=$(snapshot_workspace "$ws")
capture_run sentinel-paused "$ROOT/adapters/openclaw/sentinel-cron.sh" --workspace "$ws"
assert_paused_automation_capture "paused sentinel" "$ws" openclaw-sentinel-cron
assert_eq "paused sentinel mutates nothing" "$sentinel_before" "$(snapshot_workspace "$ws")"
cover adapters/openclaw/sentinel-cron.sh exit-0-status

deadman_before=$(snapshot_workspace "$ws")
capture_run deadman-paused "$ROOT/scripts/deadman-probe.sh" "$ws"
assert_paused_automation_capture "paused deadman probe" "$ws" deadman-probe
assert_eq "paused deadman leaves exact workspace snapshot" "$deadman_before" "$(snapshot_workspace "$ws")"
cover scripts/deadman-probe.sh exit-0-status

watchdog_before=$(snapshot_workspace "$ws")
capture_run watchdog-paused "$ROOT/adapters/hermes/stale-claim-watchdog.sh" --workspace "$ws"
assert_paused_automation_capture "paused watchdog" "$ws" hermes-stale-claim-watchdog
assert_eq "paused watchdog leaves exact workspace snapshot" "$watchdog_before" "$(snapshot_workspace "$ws")"
cover adapters/hermes/stale-claim-watchdog.sh exit-0-status

attempt_dir="$ws/loop/artifacts/pause-spawn/attempts/1"
mkdir -p "$attempt_dir"
printf 'paused prompt\n' >"$attempt_dir/prompt.md"
spawn_before=$(snapshot_workspace "$ws")
capture_run spawn-paused env MODEL_SENTINEL="$model_sentinel" HERMES_STEP_CMD="$fake_model" \
  "$ROOT/adapters/hermes/spawn_step.sh" "$TMP/missing-task-is-allowed-while-paused.md" "$ws" "$attempt_dir" 1
assert_paused_automation_capture "paused Hermes spawn" "$ws" hermes-spawn-step
assert_eq "paused Hermes spawn leaves exact workspace snapshot" "$spawn_before" "$(snapshot_workspace "$ws")"
cover adapters/hermes/spawn_step.sh exit-0-status

overflow_spawn_before=$(snapshot_workspace "$ws")
capture_run overflow-spawn-paused env MODEL_SENTINEL="$model_sentinel" OVF_STEP_CMD="$fake_model" \
  "$ROOT/adapters/claude-code/spawn_step.sh" "$TMP/missing-task-is-allowed-while-paused.md" "$ws" \
  "$TMP/missing-attempt-is-allowed-while-paused" 1
assert_paused_automation_capture "paused Claude Code overflow spawn" "$ws" overflow-spawn-step
assert_eq "paused Claude Code overflow spawn leaves exact workspace snapshot" \
  "$overflow_spawn_before" "$(snapshot_workspace "$ws")"
cover adapters/claude-code/spawn_step.sh exit-0-status

bundle_dir="$ws/loop/artifacts/pause-verify"
mkdir -p "$bundle_dir"
verify_before=$(snapshot_workspace "$ws")
capture_run verify-paused env MODEL_SENTINEL="$model_sentinel" VERIFIER_CMD="$fake_model" \
  "$ROOT/adapters/hermes/verify-job.sh" "$bundle_dir"
assert_paused_automation_capture "paused Hermes verifier" "$ws" hermes-verify-job
assert_eq "paused Hermes verifier leaves exact workspace snapshot" "$verify_before" "$(snapshot_workspace "$ws")"
cover adapters/hermes/verify-job.sh exit-0-status

input_dir="$TMP/openclaw-input"
mkdir -p "$input_dir"
distill_before=$(snapshot_workspace "$ws")
capture_run distill-paused env MODEL_SENTINEL="$model_sentinel" DISTILLER_CMD="$fake_model" \
  "$ROOT/adapters/openclaw/distill-audit.sh" --workspace "$ws" --input "$TMP/missing-input-is-allowed-while-paused"
assert_paused_automation_capture "paused OpenClaw distiller" "$ws" openclaw-distill-audit
assert_eq "paused OpenClaw distiller leaves exact workspace snapshot" "$distill_before" "$(snapshot_workspace "$ws")"
cover adapters/openclaw/distill-audit.sh exit-0-status

intake_before=$(snapshot_workspace "$ws")
capture_run intake-paused "$ROOT/adapters/claude-code/flush-intake.sh" "$ws"
assert_paused_automation_capture "paused Claude Code flush intake" "$ws" claude-code-flush-intake
assert_eq "paused Claude Code flush intake leaves exact workspace snapshot" \
  "$intake_before" "$(snapshot_workspace "$ws")"
cover adapters/claude-code/flush-intake.sh exit-0-status

hermes_intake_before=$(snapshot_workspace "$ws")
capture_run hermes-intake-paused "$ROOT/adapters/hermes/flush-intake.sh" "$ws"
assert_paused_automation_capture "paused Hermes flush intake" "$ws" hermes-flush-intake
assert_eq "paused Hermes flush intake leaves exact workspace snapshot" \
  "$hermes_intake_before" "$(snapshot_workspace "$ws")"
cover adapters/hermes/flush-intake.sh exit-0-status
[[ ! -e "$model_sentinel" ]] \
  && pass "all paused automated model paths make zero model calls" \
  || fail_case "all paused automated model paths make zero model calls" "model sentinel exists"

cron_copy="$ws/scripts/cron-wrapper.sh"
mkdir -p "$ws/scripts"
cp "$ROOT/templates/cron-wrapper.tmpl.sh" "$cron_copy"
chmod +x "$cron_copy"
deadman_marker="$ws/loop/.deadman/cron.marker"
cron_before=$(snapshot_workspace "$ws")
capture_run cron-paused env CATY_HARNESS_ROOT="$ROOT" TARGET="$TMP/missing-target-is-allowed-while-paused" \
  DEADMAN_MARKER="$deadman_marker" "$cron_copy" "$ws"
assert_paused_automation_capture "paused cron wrapper" "$ws" cron-wrapper
assert_eq "paused cron wrapper leaves exact workspace snapshot" "$cron_before" "$(snapshot_workspace "$ws")"
cover templates/cron-wrapper.tmpl.sh exit-0-status
[[ ! -e "$deadman_marker" ]] \
  && pass "paused cron wrapper does not touch deadman marker" \
  || fail_case "paused cron wrapper does not touch deadman marker" "marker exists"

enable_dry_before=$(snapshot_workspace "$ws")
enable_entire_before=$(snapshot_entire_workspace "$ws")
marker_dry_before=$(file_signature "$marker")
"$ROOT/install.sh" --enable --workspace "$ws" --dry-run >/dev/null
assert_eq "enable dry-run preserves exact path, type, size, mtime, mode, and hash set" "$enable_entire_before" "$(snapshot_entire_workspace "$ws")"
assert_eq "enable dry-run preserves marker type, size, mtime, mode, and hash" "$marker_dry_before" "$(file_signature "$marker")"
[[ -f "$marker" ]] \
  && pass "enable dry-run preserves marker" \
  || fail_case "enable dry-run preserves marker" "marker missing"

"$ROOT/install.sh" --enable --workspace "$ws" >/dev/null
[[ ! -e "$marker" ]] \
  && pass "enable removes only pause marker" \
  || fail_case "enable removes only pause marker" "marker remains"
assert_eq "enable preserves operational data" "$enable_dry_before" "$(snapshot_workspace "$ws")"
enabled_check=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
grep -Fqx 'state=enabled' <<<"$enabled_check" \
  && pass "check reports enabled" \
  || fail_case "check reports enabled" "$enabled_check"

instruction="$ws/AGENTS.md"
: >"$instruction"
"$ROOT/install.sh" --workspace "$ws" --append-bootstrap "$instruction" >/dev/null
grep -Fqx '# caty-agent-harness bootstrap v2' "$instruction" \
  && pass "fresh append writes the current v2 bootstrap marker" \
  || fail_case "fresh append writes the current v2 bootstrap marker" "current marker missing"
if ! grep -Fqx '# fable-loop bootstrap v1' "$instruction"; then
  pass "fresh append does not write the legacy v1 marker"
else
  fail_case "fresh append does not write the legacy v1 marker" "legacy marker present"
fi
grep -Fqx "$instruction" "$ws/.caty-agent-harness/instruction-files" \
  && pass "append records canonical instruction target" \
  || fail_case "append records canonical instruction target" "registry missing target"
idempotent_before=$(file_signature "$instruction")
idempotent_output=$("$ROOT/install.sh" --workspace "$ws" --append-bootstrap "$instruction")
assert_eq "current append is idempotent" "skip: bootstrap already present" \
  "$(printf '%s\n' "$idempotent_output" | tail -n 1)"
assert_eq "idempotent append preserves current instruction file exactly" "$idempotent_before" "$(file_signature "$instruction")"
assert_eq "idempotent append keeps one registry record" "1" \
  "$(grep -Fxc "$instruction" "$ws/.caty-agent-harness/instruction-files")"
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
current_check=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
grep -Fqx 'state=paused' <<<"$current_check" \
  && pass "current marker-aware bootstrap reports full paused state" \
  || fail_case "current marker-aware bootstrap reports full paused state" "$current_check"
grep -Fqx 'bootstrap_state=current' <<<"$current_check" \
  && pass "current marker-aware bootstrap is detected" \
  || fail_case "current marker-aware bootstrap is detected" "$current_check"
"$ROOT/install.sh" --enable --workspace "$ws" >/dev/null

legacy="$ws/LEGACY.md"
printf '%s\n' '# fable-loop bootstrap v1' >"$legacy"
printf '%s\n' "$legacy" >>"$ws/.caty-agent-harness/instruction-files"
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
legacy_check=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
grep -Fqx 'state=paused-partial-legacy-bootstrap' <<<"$legacy_check" \
  && pass "legacy bootstrap reports partial pause" \
  || fail_case "legacy bootstrap reports partial pause" "$legacy_check"
grep -Fqx 'bootstrap_state=legacy' <<<"$legacy_check" \
  && pass "legacy bootstrap state is detected" \
  || fail_case "legacy bootstrap state is detected" "$legacy_check"
"$ROOT/install.sh" --enable --workspace "$ws" >/dev/null

oldblock=$(new_workspace old-bootstrap-block)
oldblock_instruction="$oldblock/AGENTS.md"
{
  printf '%s\n' 'The loop below applies to dispatched work with a deliverable.'
  printf '%s\n' 'CONSULT at task start: read workspace STATE.md.'
  printf '%s\n' 'CHECKPOINT at task end: write a handoff, insert entry 1, and push previous Last session entries down verbatim.'
} >"$oldblock_instruction"
mkdir -p "$oldblock/.caty-agent-harness"
printf '%s\n' "$oldblock_instruction" >"$oldblock/.caty-agent-harness/instruction-files"
"$ROOT/install.sh" --disable --workspace "$oldblock" >/dev/null
capture_run oldblock-check "$ROOT/install.sh" --check --workspace "$oldblock"
grep -Fqx 'bootstrap_state=legacy' <<<"$CAPTURE_OUT" \
  && pass "pre-v2 markerless bootstrap block is detected as legacy" \
  || fail_case "pre-v2 markerless bootstrap block is detected as legacy" "$CAPTURE_OUT"

coexist=$(new_workspace coexist-bootstrap)
coexist_instruction="$coexist/AGENTS.md"
: >"$coexist_instruction"
"$ROOT/install.sh" --workspace "$coexist" --bootstrap-runtime codex \
  --append-bootstrap "$coexist_instruction" >/dev/null
printf '%s\n' '# fable-loop bootstrap v1' >>"$coexist_instruction"
"$ROOT/install.sh" --disable --workspace "$coexist" >/dev/null
capture_run coexist-check "$ROOT/install.sh" --check --workspace "$coexist"
grep -Fqx 'state=paused-partial-legacy-bootstrap' <<<"$CAPTURE_OUT" \
  && pass "coexisting current and legacy markers prefer partial legacy state" \
  || fail_case "coexisting current and legacy markers prefer partial legacy state" "$CAPTURE_OUT"
grep -Fqx 'bootstrap_state=legacy' <<<"$CAPTURE_OUT" \
  && pass "coexisting current and legacy markers classify legacy" \
  || fail_case "coexisting current and legacy markers classify legacy" "$CAPTURE_OUT"

hostile=$(new_workspace hostile)
mkdir -p "$hostile/.caty-agent-harness/DISABLED"
set +e
hostile_output=$("$ROOT/install.sh" --enable --workspace "$hostile" 2>&1)
hostile_rc=$?
set -e
assert_eq "enable rejects hostile marker" "2" "$hostile_rc"
[[ -d "$hostile/.caty-agent-harness/DISABLED" ]] \
  && pass "enable never removes hostile marker" \
  || fail_case "enable never removes hostile marker" "hostile marker changed"

unreadable=$(new_workspace unreadable)
"$ROOT/install.sh" --disable --workspace "$unreadable" >/dev/null
unreadable_marker="$unreadable/.caty-agent-harness/DISABLED"
chmod 000 "$unreadable_marker"
unreadable_signature=$(file_signature "$unreadable_marker")
set +e
unreadable_output=$("$ROOT/install.sh" --enable --workspace "$unreadable" 2>&1)
unreadable_rc=$?
set -e
assert_eq "enable rejects unreadable regular marker" "2" "$unreadable_rc"
grep -Fq 'refusing to remove unreadable or foreign pause marker' <<<"$unreadable_output" \
  && pass "unreadable marker error is explicit" \
  || fail_case "unreadable marker error is explicit" "$unreadable_output"
[[ -f "$unreadable_marker" ]] \
  && pass "enable never removes unreadable marker" \
  || fail_case "enable never removes unreadable marker" "marker missing"
assert_eq "unreadable marker is byte and metadata preserving" "$unreadable_signature" "$(file_signature "$unreadable_marker")"
capture_run unreadable-runner env TR_SPAWN_STEP="$fake_model" MODEL_SENTINEL="$model_sentinel" \
  "$ROOT/scripts/task-runner.sh" "$unreadable"
assert_paused_automation_capture "unreadable marker automation fails closed" "$unreadable" task-runner
printf '{"cwd":"%s","session_id":"unreadable-marker"}\n' "$unreadable" >"$TMP/unreadable-hook-input"
set +e
"$ROOT/adapters/claude-code/checkpoint-stop-hook.sh" <"$TMP/unreadable-hook-input" \
  >"$TMP/unreadable-hook.stdout" 2>"$TMP/unreadable-hook.stderr"
unreadable_hook_rc=$?
set -e
assert_eq "unreadable marker hook fails open" "0" "$unreadable_hook_rc"
assert_eq "unreadable marker hook stdout silent" "" "$(cat "$TMP/unreadable-hook.stdout")"
assert_eq "unreadable marker hook stderr silent" "" "$(cat "$TMP/unreadable-hook.stderr")"
chmod 600 "$unreadable_marker"

linked="$TMP/linked-workspace"
ln -s "$ws" "$linked"
uninitialized="$TMP/uninitialized"
mkdir -p "$uninitialized"
set +e
"$ROOT/install.sh" --disable --workspace "$linked" >/dev/null 2>&1
linked_rc=$?
"$ROOT/install.sh" --disable --workspace / >/dev/null 2>&1
root_rc=$?
"$ROOT/install.sh" --disable --workspace "$uninitialized" >/dev/null 2>&1
uninitialized_rc=$?
set -e
assert_eq "disable rejects symlink workspace" "2" "$linked_rc"
assert_eq "disable rejects root workspace" "2" "$root_rc"
assert_eq "disable rejects uninitialized workspace" "2" "$uninitialized_rc"

# Enabled runtime contracts remain unchanged in a separate workspace.
enabled_hooks=$(new_workspace enabled-hooks)
touch -t 202001010000 "$enabled_hooks/STATE.md"
printf 'changed after state\n' >"$enabled_hooks/enabled-change.txt"
for runtime in claude-code kimi; do
  hook="adapters/$runtime/checkpoint-stop-hook.sh"
  printf '{"cwd":"%s","session_id":"enabled-%s"}\n' "$enabled_hooks" "$runtime" >"$TMP/enabled-hook-input"
  set +e
  TMPDIR="$TMP/enabled-hook-guards" "$ROOT/$hook" <"$TMP/enabled-hook-input" >"$TMP/enabled-hook.stdout" 2>"$TMP/enabled-hook.stderr"
  hook_rc=$?
  set -e
  assert_eq "enabled $runtime hook retains blocking exit" "2" "$hook_rc"
  assert_eq "enabled $runtime hook stdout remains empty" "" "$(cat "$TMP/enabled-hook.stdout")"
  grep -Fq 'caty-agent-harness CHECKPOINT' "$TMP/enabled-hook.stderr" \
    && pass "enabled $runtime hook keeps checkpoint reason on stderr" \
    || fail_case "enabled $runtime hook keeps checkpoint reason on stderr" "$(cat "$TMP/enabled-hook.stderr")"
done
printf '{"cwd":"%s","session_id":"enabled-codex"}\n' "$enabled_hooks" >"$TMP/enabled-hook-input"
set +e
TMPDIR="$TMP/enabled-hook-guards" "$ROOT/adapters/codex/checkpoint-stop-hook.sh" \
  <"$TMP/enabled-hook-input" >"$TMP/enabled-codex.stdout" 2>"$TMP/enabled-codex.stderr"
codex_rc=$?
set -e
assert_eq "enabled Codex hook retains exit zero" "0" "$codex_rc"
assert_eq "enabled Codex hook stderr remains empty" "" "$(cat "$TMP/enabled-codex.stderr")"
python3 - "$TMP/enabled-codex.stdout" <<'PY' \
  && pass "enabled Codex hook emits block decision JSON" \
  || fail_case "enabled Codex hook emits block decision JSON" "$(cat "$TMP/enabled-codex.stdout")"
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f)
assert value["decision"] == "block"
assert "caty-agent-harness CHECKPOINT" in value["reason"]
PY

# Missing or syntactically broken pause helpers must fail open for every hook.
for hook in \
  adapters/claude-code/checkpoint-stop-hook.sh \
  adapters/claude-code/precompact-flush-hook.sh \
  adapters/codex/checkpoint-stop-hook.sh \
  adapters/kimi/checkpoint-stop-hook.sh; do
  fake_root="$TMP/fail-open-${hook//\//-}"
  mkdir -p "$fake_root/$(dirname "$hook")"
  cp "$ROOT/$hook" "$fake_root/$hook"
  printf '{"cwd":"%s","session_id":"missing-helper","trigger":"manual"}\n' "$enabled_hooks" >"$TMP/fail-open-input"
  set +e
  "$fake_root/$hook" <"$TMP/fail-open-input" >"$TMP/fail-open.stdout" 2>"$TMP/fail-open.stderr"
  missing_helper_rc=$?
  set -e
  assert_eq "hook missing helper fails open: $hook rc" "0" "$missing_helper_rc"
  assert_eq "hook missing helper is silent: $hook stdout" "" "$(cat "$TMP/fail-open.stdout")"
  assert_eq "hook missing helper is silent: $hook stderr" "" "$(cat "$TMP/fail-open.stderr")"
  mkdir -p "$fake_root/scripts"
  printf '%s\n' 'this is not valid shell syntax (' >"$fake_root/scripts/lib-pause.sh"
  set +e
  "$fake_root/$hook" <"$TMP/fail-open-input" >"$TMP/fail-open.stdout" 2>"$TMP/fail-open.stderr"
  broken_helper_rc=$?
  set -e
  assert_eq "hook broken helper fails open: $hook rc" "0" "$broken_helper_rc"
  assert_eq "hook broken helper is silent: $hook stdout" "" "$(cat "$TMP/fail-open.stdout")"
  assert_eq "hook broken helper is silent: $hook stderr" "" "$(cat "$TMP/fail-open.stderr")"
done

# A partial/sentinel-only bootstrap is never classified current.
partial=$(new_workspace partial-bootstrap)
partial_instruction="$partial/PARTIAL.md"
{
  printf '%s\n' '# fable-loop bootstrap v1'
  printf '%s\n' 'BEGIN CATY AGENT HARNESS BOOTSTRAP v2'
  printf '%s\n' 'CATY PAUSE AWARE v1'
  printf '%s\n' 'END CATY AGENT HARNESS BOOTSTRAP v2'
  printf '%s\n' '# nonfunctional comment: `.caty-agent-harness/DISABLED` If it exists'
  printf '%s\n' '# nonfunctional comment: skip all harness instructions'
} >"$partial_instruction"
mkdir -p "$partial/.caty-agent-harness"
printf '%s\n' "$partial_instruction" >"$partial/.caty-agent-harness/instruction-files"
"$ROOT/install.sh" --disable --workspace "$partial" >/dev/null
capture_run partial-check "$ROOT/install.sh" --check --workspace "$partial"
grep -Fqx 'bootstrap_state=legacy' <<<"$CAPTURE_OUT" \
  && pass "sentinel-only bootstrap is legacy, not current" \
  || fail_case "sentinel-only bootstrap is legacy, not current" "$CAPTURE_OUT"

# Hostile pause objects fail closed for automation and fail open for hooks.
for hostile_kind in symlink fifo directory control-symlink; do
  hostile_ws=$(new_workspace "hostile-$hostile_kind")
  if [[ "$hostile_kind" == control-symlink ]]; then
    hostile_target="$TMP/hostile-control-target"
    mkdir -p "$hostile_target"
    ln -s "$hostile_target" "$hostile_ws/.caty-agent-harness"
  else
    mkdir -p "$hostile_ws/.caty-agent-harness"
    if [[ "$hostile_kind" == symlink ]]; then
      ln -s "$TMP/hostile-marker-target" "$hostile_ws/.caty-agent-harness/DISABLED"
    elif [[ "$hostile_kind" == directory ]]; then
      mkdir "$hostile_ws/.caty-agent-harness/DISABLED"
    else
      mkfifo "$hostile_ws/.caty-agent-harness/DISABLED"
    fi
  fi
  capture_run "hostile-runner-$hostile_kind" env TR_SPAWN_STEP="$fake_model" MODEL_SENTINEL="$model_sentinel" \
    "$ROOT/scripts/task-runner.sh" "$hostile_ws"
  assert_paused_automation_capture "hostile $hostile_kind automation" "$hostile_ws" task-runner
  printf '{"cwd":"%s","session_id":"hostile-%s"}\n' "$hostile_ws" "$hostile_kind" >"$TMP/hostile-hook-input"
  set +e
  "$ROOT/adapters/claude-code/checkpoint-stop-hook.sh" <"$TMP/hostile-hook-input" \
    >"$TMP/hostile-hook.stdout" 2>"$TMP/hostile-hook.stderr"
  hostile_hook_rc=$?
  set -e
  assert_eq "hostile $hostile_kind hook fails open" "0" "$hostile_hook_rc"
  assert_eq "hostile $hostile_kind hook stdout silent" "" "$(cat "$TMP/hostile-hook.stdout")"
  assert_eq "hostile $hostile_kind hook stderr silent" "" "$(cat "$TMP/hostile-hook.stderr")"
  set +e
  "$ROOT/install.sh" --enable --workspace "$hostile_ws" >/dev/null 2>&1
  hostile_enable_rc=$?
  set -e
  assert_eq "hostile $hostile_kind enable refuses mutation" "2" "$hostile_enable_rc"
done

# Pause is a next-entry-boundary barrier: it never kills already-running work.
boundary=$(new_workspace next-boundary)
boundary_task="$TMP/tr-boundary.task.md"
next_task="$TMP/tr-next.task.md"
sed 's/^time_budget_min: 5$/time_budget_min: 15/' "$ROOT/tests/fixtures/task-basic.task.md" >"$boundary_task"
sed 's/^id: tr-basic$/id: tr-next/' "$boundary_task" >"$next_task"
"$ROOT/scripts/tr-enqueue" "$boundary_task" "$boundary" >/dev/null
"$ROOT/scripts/tr-enqueue" "$next_task" "$boundary" >/dev/null
boundary_provider="$TMP/blocking-spawn-step.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'printf "call\n" >>"$BOUNDARY_CALLS"'
  printf '%s\n' ': >"$BOUNDARY_STARTED"'
  printf '%s\n' 'while [[ ! -e "$BOUNDARY_RELEASE" ]]; do sleep 0.05; done'
  printf '%s\n' 'exec "$BOUNDARY_DELEGATE" "$@"'
} >"$boundary_provider"
chmod +x "$boundary_provider"
boundary_calls="$TMP/boundary-calls"
boundary_started="$TMP/boundary-started"
boundary_release="$TMP/boundary-release"
env BOUNDARY_CALLS="$boundary_calls" BOUNDARY_STARTED="$boundary_started" \
  BOUNDARY_RELEASE="$boundary_release" BOUNDARY_DELEGATE="$ROOT/tests/fixtures/mock-spawn-step.sh" \
  TR_SPAWN_STEP="$boundary_provider" "$ROOT/scripts/task-runner.sh" "$boundary" \
  >"$TMP/boundary-run.stdout" 2>"$TMP/boundary-run.stderr" &
boundary_pid=$!
for _ in $(seq 1 200); do
  [[ -e "$boundary_started" ]] && break
  sleep 0.05
done
[[ -e "$boundary_started" ]] \
  && pass "enabled entry starts before mid-flight pause" \
  || fail_case "enabled entry starts before mid-flight pause" "provider did not start"
"$ROOT/install.sh" --disable --workspace "$boundary" >/dev/null
kill -0 "$boundary_pid" 2>/dev/null \
  && pass "disable does not kill in-flight process" \
  || fail_case "disable does not kill in-flight process" "runner exited during pause"
: >"$boundary_release"
set +e
wait "$boundary_pid"
boundary_rc=$?
set -e
assert_eq "in-flight invocation finishes normally" "0" "$boundary_rc"
assert_eq "in-flight invocation makes exactly one provider call" "1" "$(wc -l <"$boundary_calls" | tr -d ' ')"
[[ -f "$boundary/loop/tasks/delivered/tr-basic/tr-basic.task.md" ]] \
  && pass "in-flight task reaches delivered state after pause" \
  || fail_case "in-flight task reaches delivered state after pause" "delivery missing"
[[ -f "$boundary/loop/tasks/queue/tr-next.task.md" ]] \
  && pass "next queued task waits behind pause barrier" \
  || fail_case "next queued task waits behind pause barrier" "next task moved"
boundary_before_next=$(snapshot_workspace "$boundary")
capture_run boundary-next env BOUNDARY_CALLS="$boundary_calls" BOUNDARY_STARTED="$boundary_started" \
  BOUNDARY_RELEASE="$boundary_release" BOUNDARY_DELEGATE="$ROOT/tests/fixtures/mock-spawn-step.sh" \
  TR_SPAWN_STEP="$boundary_provider" "$ROOT/scripts/task-runner.sh" "$boundary"
assert_paused_automation_capture "next invocation after mid-flight pause" "$boundary" task-runner
assert_eq "next paused invocation makes zero additional provider calls" "1" "$(wc -l <"$boundary_calls" | tr -d ' ')"
assert_eq "next paused invocation leaves exact workspace snapshot" "$boundary_before_next" "$(snapshot_workspace "$boundary")"

# UTF-8 locale coverage exercises locale-stable control-character rejection.
set +e
available_locales=$(locale -a 2>/dev/null)
locale_list_rc=$?
set -e
if (( locale_list_rc != 0 )); then
  fail_case "locale availability can be queried" \
    "locale -a exited $locale_list_rc"
elif grep -Ei '^en_US\.(UTF-8|utf8)$' <<<"$available_locales" >/dev/null; then
  set +e
  # Pin Apple's bash 3.2 semantics even when a Homebrew bash shadows PATH.
  env LC_ALL=en_US.UTF-8 /bin/bash -c \
    'source "$1" || exit 99; caty_pause_value_is_record_safe "$2"' \
    _ "$ROOT/scripts/lib-pause.sh" $'unsafe\nrecord'
  locale_record_safe_rc=$?
  set -e
  assert_eq "en_US UTF-8 rejects newline record value" "1" "$locale_record_safe_rc"

  locale_unsafe_parent="$TMP/"$'locale-unsafe\nphysical-parent'
  mkdir -p "$locale_unsafe_parent/initialized"
  "$ROOT/scripts/loop-init" --workspace "$locale_unsafe_parent/initialized" >/dev/null
  ln -s "$locale_unsafe_parent" "$TMP/locale-safe-ancestor"
  capture_run locale-unsafe-physical env LC_ALL=en_US.UTF-8 /bin/bash \
    "$ROOT/install.sh" --disable --workspace "$TMP/locale-safe-ancestor/initialized"
  assert_eq "en_US UTF-8 rejects safe alias to newline physical parent" "2" "$CAPTURE_RC"
  assert_eq "en_US UTF-8 unsafe physical parent emits no stdout records" "" "$CAPTURE_OUT"
  assert_eq "en_US UTF-8 unsafe physical parent stdout is empty at byte level" \
    "0" "$(wc -c <"$CAPTURE_STDOUT" | tr -d ' ')"
  assert_eq "en_US UTF-8 unsafe physical parent stderr is exact invalid workspace path" \
    "invalid workspace path" "$CAPTURE_ERR"
  assert_eq "en_US UTF-8 unsafe physical parent error remains one line" \
    "1" "$(wc -l <"$CAPTURE_STDERR" | tr -d ' ')"
else
  if [[ "$(uname -s)" == "Darwin" ]]; then
    fail_case "en_US.UTF-8 locale available on macOS" \
      "locale -a lists no en_US.UTF-8/utf8"
  else
    pass "en_US UTF-8 locale unavailable # SKIP locale-sensitive path safety regressions"
  fi
fi

# Unsafe logical and physical paths are rejected without multiline status records.
unsafe_direct="$TMP/"$'unsafe\nworkspace'
mkdir -p "$unsafe_direct"
set +e
"$ROOT/install.sh" --disable --workspace "$unsafe_direct" >"$TMP/unsafe.stdout" 2>"$TMP/unsafe.stderr"
unsafe_rc=$?
set -e
assert_eq "newline workspace is rejected" "2" "$unsafe_rc"
assert_eq "newline workspace emits no stdout records" "" "$(cat "$TMP/unsafe.stdout")"
assert_eq "newline workspace error remains one line" "1" "$(wc -l <"$TMP/unsafe.stderr" | tr -d ' ')"
set +e
"$ROOT/install.sh" --disable --workspace "" >"$TMP/empty-workspace.stdout" 2>"$TMP/empty-workspace.stderr"
empty_workspace_rc=$?
set -e
assert_eq "empty workspace is rejected" "2" "$empty_workspace_rc"
assert_eq "empty workspace emits no stdout records" "" "$(cat "$TMP/empty-workspace.stdout")"
assert_eq "empty workspace error remains one line" "1" "$(wc -l <"$TMP/empty-workspace.stderr" | tr -d ' ')"

unsafe_parent="$TMP/"$'unsafe\nphysical-parent'
mkdir -p "$unsafe_parent/initialized"
"$ROOT/scripts/loop-init" --workspace "$unsafe_parent/initialized" >/dev/null
ln -s "$unsafe_parent" "$TMP/safe-ancestor"
set +e
"$ROOT/install.sh" --disable --workspace "$TMP/safe-ancestor/initialized" >"$TMP/unsafe.stdout" 2>"$TMP/unsafe.stderr"
unsafe_physical_rc=$?
set -e
assert_eq "safe alias to newline physical parent is rejected" "2" "$unsafe_physical_rc"
assert_eq "unsafe physical parent emits no stdout records" "" "$(cat "$TMP/unsafe.stdout")"
safe_append_ws=$(new_workspace safe-append)
unsafe_append_parent="$TMP/"$'unsafe\nappend-parent'
mkdir -p "$unsafe_append_parent"
ln -s "$unsafe_append_parent" "$TMP/safe-append-parent"
set +e
"$ROOT/install.sh" --workspace "$safe_append_ws" --bootstrap-runtime codex \
  --append-bootstrap "$TMP/safe-append-parent/AGENTS.md" >"$TMP/unsafe-append.stdout" 2>"$TMP/unsafe-append.stderr"
unsafe_append_rc=$?
set -e
assert_eq "append target with unsafe physical parent is rejected" "2" "$unsafe_append_rc"
[[ ! -e "$unsafe_append_parent/AGENTS.md" ]] \
  && pass "unsafe append creates no instruction file" \
  || fail_case "unsafe append creates no instruction file" "file exists"
[[ ! -e "$safe_append_ws/.caty-agent-harness/instruction-files" ]] \
  && pass "unsafe append cannot inject registry records" \
  || fail_case "unsafe append cannot inject registry records" "registry exists"

other=$(new_workspace other)
"$ROOT/install.sh" --disable --workspace "$ws" >/dev/null
[[ ! -e "$other/.caty-agent-harness/DISABLED" ]] \
  && pass "pause is scoped to one workspace" \
  || fail_case "pause is scoped to one workspace" "other workspace paused"
touch -t 202001010000 "$other/STATE.md"
printf 'other workspace changed\n' >"$other/other-change.txt"
printf '{"cwd":"%s","session_id":"multiworkspace-enabled-other"}\n' "$other" >"$TMP/multiworkspace-hook-input"
set +e
TMPDIR="$TMP/multiworkspace-hook-guards" "$ROOT/adapters/claude-code/checkpoint-stop-hook.sh" \
  <"$TMP/multiworkspace-hook-input" >"$TMP/multiworkspace-hook.stdout" 2>"$TMP/multiworkspace-hook.stderr"
multiworkspace_hook_rc=$?
set -e
assert_eq "other enabled workspace entrypoint remains active while selected workspace is paused" "2" "$multiworkspace_hook_rc"
assert_eq "other enabled hook stdout remains empty" "" "$(cat "$TMP/multiworkspace-hook.stdout")"
grep -Fq 'caty-agent-harness CHECKPOINT' "$TMP/multiworkspace-hook.stderr" \
  && pass "other enabled workspace produces its normal checkpoint behavior" \
  || fail_case "other enabled workspace produces its normal checkpoint behavior" "$(cat "$TMP/multiworkspace-hook.stderr")"

while IFS=$'\t' read -r manifest_path manifest_class _ manifest_contract _; do
  [[ -n "$manifest_path" && "$manifest_path" != \#* && "$manifest_class" == guarded ]] || continue
  actual_contract=$(awk -F '\t' -v path="$manifest_path" '$1 == path {print $2; exit}' "$coverage_file")
  if [[ -n "$actual_contract" ]]; then
    pass "paused contract has a runtime test: $manifest_path"
  else
    fail_case "paused contract has a runtime test: $manifest_path" "coverage missing"
  fi
  assert_eq "runtime assertion matches manifest contract: $manifest_path" "$manifest_contract" "$actual_contract"
done <"$ROOT/scripts/activation-manifest.tsv"

if [[ ! -e "$root_control_dir" && ! -L "$root_control_dir" ]]; then
  pass "pause contract leaves no harness control artifact in repository root"
else
  fail_case "pause contract leaves no harness control artifact in repository root" \
    "unexpected path: $root_control_dir"
fi

if (( failures )); then
  printf '%s pause contract test(s) failed\n' "$failures" >&2
  exit 1
fi
