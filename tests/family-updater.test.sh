#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UPDATER=${UPDATER_UNDER_TEST:-$ROOT/scripts/family-updater}
BOOTSTRAP=${BOOTSTRAP_UNDER_TEST:-$ROOT/scripts/updater-bootstrap}
TMP_ROOT=${TMPDIR:-/tmp}/family-updater-test.$$
REAL_GIT=$(command -v git)
PASS_COUNT=0
FAIL_COUNT=0

cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP_ROOT"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail_case() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

assert_true() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail_case "$name" "assertion failed: $*"; fi
}

assert_contains() {
  local name=$1 file=$2 text=$3
  if [[ -f "$file" ]] && grep -Fq "$text" "$file"; then
    pass "$name"
  else
    fail_case "$name" "missing '$text' in $file"
  fi
}

write_fake_install() {
  local src=$1 result=$2
  cat >"$src/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [[ -n "${UPDATER_INSTALL_SENTINEL:-}" ]]; then
  printf '%s\n' "$(sed -n '1p' "$repo_dir/VERSION.fixture")" >>"$UPDATER_INSTALL_SENTINEL"
fi
if [[ -f "$repo_dir/.fixture-install-fails" ]]; then
  printf 'fixture install check failed\n'
  exit 1
fi
printf 'ok: fixture install check passed\n'
INSTALL
  chmod +x "$src/install.sh"
  if [[ "$result" == fail ]]; then
    printf 'fail\n' >"$src/.fixture-install-fails"
  else
    rm -f "$src/.fixture-install-fails"
  fi
}

new_fixture() {
  local name=$1
  name=${name// /-}
  BASE=$TMP_ROOT/$name
  ORIGIN=$BASE/origin.git
  SRC=$BASE/src
  REPO=$BASE/repo
  HOME_DIR=$BASE/home
  FMA=$BASE/fma
  LOGS=$BASE/logs
  WS=$BASE/ws
  KEY=$BASE/key
  OTHER_KEY=$BASE/other-key
  ALLOWED=$HOME_DIR/.claude/state/updater-allowed-signers
  SENTINEL=$BASE/install-sentinel.log

  mkdir -p "$BASE" "$HOME_DIR/.claude/state" "$FMA" "$LOGS" "$WS"
  ssh-keygen -q -t ed25519 -N '' -f "$KEY"
  ssh-keygen -q -t ed25519 -N '' -f "$OTHER_KEY"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >"$ALLOWED"

  git init -q --bare "$ORIGIN"
  git init -q "$SRC"
  git -C "$SRC" config user.name Fixture
  git -C "$SRC" config user.email fixture@example.invalid
  git -C "$SRC" config gpg.format ssh
  git -C "$SRC" config user.signingkey "$KEY"
  write_fake_install "$SRC" pass
  printf 'base\n' >"$SRC/VERSION.fixture"
  git -C "$SRC" add -A
  GIT_AUTHOR_DATE=2020-01-01T00:00:00Z GIT_COMMITTER_DATE=2020-01-01T00:00:00Z \
    git -C "$SRC" commit -qm base
  BASE_COMMIT=$(git -C "$SRC" rev-parse HEAD)
  BRANCH=$(git -C "$SRC" rev-parse --abbrev-ref HEAD)
  git -C "$SRC" remote add origin "$ORIGIN"
  git -C "$SRC" push -q origin "$BRANCH"
  git clone -q --no-tags "$ORIGIN" "$REPO"
  git -C "$REPO" checkout -q --detach "$BASE_COMMIT"

  cat >"$FMA/job-heartbeat" <<EOF
#!/usr/bin/env bash
printf '%s\n' "job-heartbeat \$*" >>"$LOGS/heartbeats.log"
EOF
  cat >"$FMA/hot-inbox-post" <<EOF
#!/usr/bin/env bash
printf '%s\n' "hot-inbox-post \$*" >>"$LOGS/hot-inbox.log"
EOF
  chmod +x "$FMA/job-heartbeat" "$FMA/hot-inbox-post"
}

commit_release() {
  local label=$1 result=${2:-pass}
  write_fake_install "$SRC" "$result"
  mkdir -p "$SRC/templates"
  cat >"$SRC/templates/updater-cron.tmpl.sh" <<'CRON_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture updater cron wrapper\n'
CRON_WRAPPER
  printf '%s\n' "$label" >"$SRC/VERSION.fixture"
  git -C "$SRC" add -A
  GIT_AUTHOR_DATE=2020-02-01T00:00:00Z GIT_COMMITTER_DATE=2020-02-01T00:00:00Z \
    git -C "$SRC" commit -qm "$label"
  RELEASE_COMMIT=$(git -C "$SRC" rev-parse HEAD)
}

tag_release() {
  local kind=$1 name=$2 commit=$3
  case "$kind" in
    signed)
      git -C "$SRC" config user.signingkey "$KEY"
      GIT_COMMITTER_DATE=2020-02-01T00:00:00Z git -C "$SRC" tag -s "$name" "$commit" -m "$name"
      ;;
    unpinned)
      git -C "$SRC" config user.signingkey "$OTHER_KEY"
      GIT_COMMITTER_DATE=2020-02-01T00:00:00Z git -C "$SRC" tag -s "$name" "$commit" -m "$name"
      git -C "$SRC" config user.signingkey "$KEY"
      ;;
    unsigned)
      GIT_COMMITTER_DATE=2020-02-01T00:00:00Z git -C "$SRC" tag -a "$name" "$commit" -m "$name"
      ;;
    lightweight)
      git -C "$SRC" tag "$name" "$commit"
      ;;
  esac
}

push_tag() { git -C "$SRC" push -q "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }
force_push_tag() { git -C "$SRC" push -q --force "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }
fetch_local_tag() { git -C "$REPO" fetch -q --no-tags "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }

pin_path() { printf '%s/.claude/state/updater-pin/%s.json\n' "$HOME_DIR" "$(basename "$REPO")"; }
ineligible_path() { printf '%s/.claude/state/updater-ineligible/%s.log\n' "$HOME_DIR" "$(basename "$REPO")"; }

write_pin() {
  local version=$1 commit=$2 path
  path=$(pin_path)
  mkdir -p "$(dirname "$path")"
  chmod 700 "$(dirname "$path")"
  printf '{"version":"%s","commit":"%s","updated_at":"2020-01-01T00:00:00Z"}\n' "$version" "$commit" >"$path"
  chmod 600 "$path"
}

run_updater() {
  if [[ "${BASELINE_FOCUSED:-0}" == 1 ]]; then
    HOME="$HOME_DIR" UPDATER_INSTALL_SENTINEL="$SENTINEL" "$UPDATER" \
      --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary \
      --soak-hours 0 --fma-scripts-dir "$FMA" "$@" 2>&1
  else
    HOME="$HOME_DIR" UPDATER_INSTALL_SENTINEL="$SENTINEL" "$UPDATER" \
      --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary \
      --soak-hours 0 --allowed-signers "$ALLOWED" --fma-scripts-dir "$FMA" "$@" 2>&1
  fi
}

make_candidate() {
  local kind=$1
  commit_release candidate pass
  CANDIDATE_COMMIT=$RELEASE_COMMIT
  CANDIDATE_TAG=v1.1.0
  if [[ "$kind" == rebound ]]; then
    tag_release signed v1.1.0 "$CANDIDATE_COMMIT"
    local genuine_oid
    genuine_oid=$(git -C "$SRC" rev-parse refs/tags/v1.1.0)
    CANDIDATE_TAG=v9.9.9
    git -C "$SRC" update-ref "refs/tags/$CANDIDATE_TAG" "$genuine_oid"
  else
    if [[ "$kind" == valid || "$kind" == below ]]; then
      tag_release signed "$CANDIDATE_TAG" "$CANDIDATE_COMMIT"
    else
      tag_release "$kind" "$CANDIDATE_TAG" "$CANDIDATE_COMMIT"
    fi
  fi
  push_tag "$CANDIDATE_TAG"
}

run_side_path_variant() {
  local kind=$1 mode=$2 expected=$3 label=$4
  local before after output rc floor_commit

  new_fixture "$label"
  floor_commit=$BASE_COMMIT
  if [[ "$kind" == equal-different ]]; then
    commit_release floor-identity pass
    floor_commit=$RELEASE_COMMIT
    commit_release candidate pass
    CANDIDATE_COMMIT=$RELEASE_COMMIT
    CANDIDATE_TAG=v1.1.0
    tag_release signed "$CANDIDATE_TAG" "$CANDIDATE_COMMIT"
    push_tag "$CANDIDATE_TAG"
  else
    make_candidate "$kind"
  fi

  case "$kind" in
    below) write_pin v2.0.0 "$BASE_COMMIT" ;;
    equal-different) write_pin v1.1.0 "$floor_commit" ;;
    valid)
      if [[ "$mode" == current ]]; then write_pin "$CANDIDATE_TAG" "$CANDIDATE_COMMIT"; else write_pin v0.0.0 "$BASE_COMMIT"; fi
      ;;
    *) write_pin v0.0.0 "$BASE_COMMIT" ;;
  esac

  if [[ "$mode" == current ]]; then
    fetch_local_tag "$CANDIDATE_TAG"
    git -C "$REPO" checkout -q --detach "$CANDIDATE_COMMIT"
  fi
  before=$(git -C "$REPO" rev-parse HEAD)
  if [[ "$mode" == dry ]]; then
    output=$(run_updater --dry-run); rc=$?
  else
    output=$(run_updater); rc=$?
  fi
  after=$(git -C "$REPO" rev-parse HEAD)

  if [[ "$expected" == accept ]]; then
    if [[ "$rc" -eq 0 && "$before" == "$after" && ! -e "$SENTINEL" ]]; then
      pass "$label"
    else
      fail_case "$label" "rc=$rc before=$before after=$after output=$output"
    fi
  else
    if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]]; then
      pass "$label"
    else
      fail_case "$label" "rc=$rc before=$before after=$after sentinel=$(test -e "$SENTINEL" && echo yes || echo no) output=$output"
    fi
  fi
}

if [[ "${BASELINE_FOCUSED:-0}" == 1 ]]; then
  # These are the same security assertions used below. They intentionally fail
  # against dfbc094 and provide destructive before/after evidence for #12.
  run_side_path_variant rebound current reject "pre-fix probe: rebound-name must be rejected"
  run_side_path_variant below current reject "pre-fix probe: below-floor tag must be rejected"

  new_fixture pre-fix-moved
  commit_release old-moved pass
  old_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$old_commit"
  push_tag v1.1.0
  fetch_local_tag v1.1.0
  git -C "$SRC" tag -d v1.1.0 >/dev/null
  commit_release moved pass
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  force_push_tag v1.1.0
  commit_release legitimate pass
  legitimate_commit=$RELEASE_COMMIT
  tag_release signed v1.2.0 "$legitimate_commit"
  push_tag v1.2.0
  write_pin v1.0.0 "$BASE_COMMIT"
  output=$(run_updater); rc=$?
  if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$legitimate_commit" ]]; then
    pass "pre-fix probe: moved tag must not wedge legitimate newer update"
  else
    fail_case "pre-fix probe: moved tag must not wedge legitimate newer update" "rc=$rc head=$(git -C "$REPO" rev-parse HEAD) output=$output"
  fi

  new_fixture pre-fix-rollback
  commit_release rollback-base pass
  rollback_commit=$RELEASE_COMMIT
  tag_release signed v1.0.0 "$rollback_commit"
  push_tag v1.0.0
  fetch_local_tag v1.0.0
  git -C "$REPO" checkout -q --detach "$rollback_commit"
  commit_release broken-target fail
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  push_tag v1.1.0
  write_pin v1.0.0 "$rollback_commit"
  baseline_fakebin=$BASE/fakebin
  mismatch_state=$BASE/mismatch-count
  mkdir -p "$baseline_fakebin"
  cat >"$baseline_fakebin/git" <<'BASELINE_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == "-C $MISMATCH_REPO rev-parse HEAD" ]]; then
  count=0
  [[ -f "$MISMATCH_STATE" ]] && count=$(sed -n '1p' "$MISMATCH_STATE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$MISMATCH_STATE"
  if [[ "$count" -eq 3 ]]; then
    printf '%040d\n' 0
    exit 0
  fi
fi
exec "$REAL_GIT" "$@"
BASELINE_GIT_SHIM
  chmod +x "$baseline_fakebin/git"
  output=$(PATH="$baseline_fakebin:$PATH" REAL_GIT="$REAL_GIT" MISMATCH_REPO="$REPO" MISMATCH_STATE="$mismatch_state" run_updater); rc=$?
  sentinel_lines=$(wc -l <"$SENTINEL" 2>/dev/null || printf '0')
  if [[ "$rc" -ne 0 && "$sentinel_lines" -eq 1 ]]; then
    pass "pre-fix probe: rollback install requires an identity assertion"
  else
    fail_case "pre-fix probe: rollback install requires an identity assertion" "rc=$rc install-lines=$sentinel_lines output=$output"
  fi

  printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
  [[ "$FAIL_COUNT" -eq 0 ]]
  exit $?
fi

# B1 side paths: every current/dry-run result is preceded by the full gate.
run_side_path_variant valid current accept "already-current valid signed tag accepted"
run_side_path_variant unsigned current reject "already-current unsigned tag rejected before success"
run_side_path_variant unpinned current reject "already-current unpinned-key tag rejected before success"
run_side_path_variant rebound current reject "already-current rebound-name attack M2 rejected"
run_side_path_variant below current reject "already-current below-floor tag rejected"
run_side_path_variant equal-different current reject "already-current equal-version different-OID rejected"

run_side_path_variant valid dry accept "dry-run valid signed tag verifies without checkout"
run_side_path_variant unsigned dry reject "dry-run unsigned tag rejected"
run_side_path_variant unpinned dry reject "dry-run unpinned-key tag rejected"
run_side_path_variant rebound dry reject "dry-run rebound-name attack rejected"
run_side_path_variant below dry reject "dry-run below-floor tag rejected"
run_side_path_variant equal-different dry reject "dry-run equal-version different-OID rejected"

# Explicit lightweight/legacy rejection (legacy pins are rollback-only).
new_fixture legacy-lightweight
commit_release legacy pass
CANDIDATE_COMMIT=$RELEASE_COMMIT
tag_release lightweight v0.2.2 "$CANDIDATE_COMMIT"
push_tag v0.2.2
write_pin v0.1.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]]; then
  pass "legacy lightweight tag refused as update target with no install"
else
  fail_case "legacy lightweight tag refused as update target with no install" "rc=$rc output=$output"
fi

# Numeric comparison must not become lexicographic: v0.10.0 is above v0.9.0.
new_fixture numeric-floor
commit_release numeric pass
numeric_commit=$RELEASE_COMMIT
tag_release signed v0.10.0 "$numeric_commit"
push_tag v0.10.0
write_pin v0.9.0 "$BASE_COMMIT"
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$numeric_commit" ]]; then
  pass "floor comparison is numeric per semver component"
else
  fail_case "floor comparison is numeric per semver component" "rc=$rc output=$output"
fi

# One moved tag is excluded, reported once, and does not wedge a valid update.
new_fixture moved-continues
commit_release old-moved pass
old_moved_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$old_moved_commit"
old_moved_oid=$(git -C "$SRC" rev-parse refs/tags/v1.1.0)
push_tag v1.1.0
fetch_local_tag v1.1.0
git -C "$SRC" tag -d v1.1.0 >/dev/null
commit_release moved-content pass
new_moved_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$new_moved_commit"
force_push_tag v1.1.0
commit_release legitimate pass
legit_commit=$RELEASE_COMMIT
tag_release signed v1.2.0 "$legit_commit"
push_tag v1.2.0
write_pin v1.0.0 "$BASE_COMMIT"
output=$(run_updater); rc=$?
first_reports=$(grep -Fc "updater failed: claire repo v1.1.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
output2=$(run_updater); rc2=$?
second_reports=$(grep -Fc "updater failed: claire repo v1.1.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
local_moved_oid=$(git -C "$REPO" rev-parse refs/tags/v1.1.0)
if [[ "$rc" -eq 0 && "$rc2" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$legit_commit" \
  && "$local_moved_oid" == "$old_moved_oid" \
  && "$first_reports" -eq 1 && "$second_reports" -eq 1 ]]; then
  pass "moved tag stays local and ineligible, reports once, legitimate newer tag installs"
else
  fail_case "moved tag stays local and ineligible, reports once, legitimate newer tag installs" "rc=$rc rc2=$rc2 reports=$first_reports/$second_reports output=$output"
fi

# Two moved names produce two alerts total, not two alerts per tick.
new_fixture two-moved
for moved_name in v1.1.0 v1.2.0; do
  commit_release "old-$moved_name" pass
  tag_release signed "$moved_name" "$RELEASE_COMMIT"
  push_tag "$moved_name"
  fetch_local_tag "$moved_name"
done
for moved_name in v1.1.0 v1.2.0; do
  git -C "$SRC" tag -d "$moved_name" >/dev/null
  commit_release "new-$moved_name" pass
  tag_release signed "$moved_name" "$RELEASE_COMMIT"
  force_push_tag "$moved_name"
done
commit_release valid-newer pass
valid_newer_commit=$RELEASE_COMMIT
tag_release signed v1.3.0 "$valid_newer_commit"
push_tag v1.3.0
write_pin v1.0.0 "$BASE_COMMIT"
run_updater >/dev/null; rc=$?
run_updater >/dev/null; rc2=$?
reports_11=$(grep -Fc "updater failed: claire repo v1.1.0" "$LOGS/hot-inbox.log" || true)
reports_12=$(grep -Fc "updater failed: claire repo v1.2.0" "$LOGS/hot-inbox.log" || true)
if [[ "$rc" -eq 0 && "$rc2" -eq 0 && "$reports_11" -eq 1 && "$reports_12" -eq 1 ]]; then
  pass "two offending names report once each and never repeat on next tick"
else
  fail_case "two offending names report once each and never repeat on next tick" "rc=$rc/$rc2 reports=$reports_11/$reports_12"
fi

# A verification failure deduplicates its report but must be retried after an
# out-of-band allowed_signers rotation. Passing the gate clears the dedupe state
# so a later failure for the same name reports again.
new_fixture signer-rotation-recovery
commit_release installed-key-a pass
floor_commit=$RELEASE_COMMIT
tag_release signed v0.2.3 "$floor_commit"
push_tag v0.2.3
fetch_local_tag v0.2.3
git -C "$REPO" checkout -q --detach "$floor_commit"
write_pin v0.2.3 "$floor_commit"
commit_release rotated-key-b pass
rotated_commit=$RELEASE_COMMIT
tag_release unpinned v0.3.0 "$rotated_commit"
push_tag v0.3.0

output=$(run_updater); rc=$?
first_reports=$(grep -Fc "updater failed: claire repo v0.3.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
first_head=$(git -C "$REPO" rev-parse HEAD)
run_updater >/dev/null; dedupe_rc=$?
dedupe_reports=$(grep -Fc "updater failed: claire repo v0.3.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$OTHER_KEY.pub")" >>"$ALLOWED"
output2=$(run_updater); rc2=$?
second_reports=$(grep -Fc "updater failed: claire repo v0.3.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
second_head=$(git -C "$REPO" rev-parse HEAD)
clear_records=$(grep -F 'v0.3.0 ' "$(ineligible_path)" 2>/dev/null | grep -Fc ' verification-failure-cleared' || true)

# Remove key B again: because the successful tick cleared the dedupe state,
# this later failure must emit a fresh report.
printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >"$ALLOWED"
run_updater >/dev/null; rc3=$?
third_reports=$(grep -Fc "updater failed: claire repo v0.3.0" "$LOGS/hot-inbox.log" 2>/dev/null || true)
sentinel_lines=0
[[ ! -f "$SENTINEL" ]] || sentinel_lines=$(wc -l <"$SENTINEL")
if [[ "$rc" -eq 0 && "$first_head" == "$floor_commit" && "$first_reports" -eq 1 \
  && "$dedupe_rc" -eq 0 && "$dedupe_reports" -eq 1 \
  && "$rc2" -eq 0 && "$second_head" == "$rotated_commit" && "$second_reports" -eq 1 \
  && "$clear_records" -eq 1 && "$sentinel_lines" -eq 1 \
  && "$rc3" -ne 0 && "$third_reports" -eq 2 ]]; then
  pass "signer rotation retries a verification failure, installs, clears dedupe, and can report again"
else
  fail_case "signer rotation retries a verification failure, installs, clears dedupe, and can report again" \
    "rc=$rc/$dedupe_rc/$rc2/$rc3 heads=$first_head/$second_head reports=$first_reports/$dedupe_reports/$second_reports/$third_reports clears=$clear_records installs=$sentinel_lines output2=$output2"
fi

# Git shim supports deterministic transport/capability/identity failures.
FAKEBIN=$TMP_ROOT/fakebin
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/git" <<'GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "${FAKE_OLD_GIT:-0}" == 1 && "${1:-}" == --version ]]; then
  printf 'git version 2.33.9\n'
  exit 0
fi
if [[ "${FAKE_LS_REMOTE:-0}" == 1 && "$*" == *" ls-remote "* ]]; then
  exit 71
fi
if [[ "${EXTRA_BAD_REFSPEC:-0}" == 1 && "$*" == *" fetch --atomic "* ]]; then
  exec "$REAL_GIT" "$@" 'refs/tags/v404.0.0:refs/tags/v404.0.0'
fi
if [[ -n "${MISMATCH_REPO:-}" && "$*" == "-C $MISMATCH_REPO rev-parse HEAD" ]]; then
  count=0
  [[ -f "$MISMATCH_STATE" ]] && count=$(sed -n '1p' "$MISMATCH_STATE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$MISMATCH_STATE"
  if [[ "$count" -eq 3 ]]; then
    printf '%040d\n' 0
    exit 0
  fi
fi
exec "$REAL_GIT" "$@"
GIT_SHIM
chmod +x "$FAKEBIN/git"

new_fixture ls-remote-failure
commit_release candidate pass
tag_release signed v1.1.0 "$RELEASE_COMMIT"
push_tag v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" FAKE_LS_REMOTE=1 run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] && printf '%s\n' "$output" | grep -Fq 'ls-remote'; then
  pass "ls-remote failure stops without checkout or install"
else
  fail_case "ls-remote failure stops without checkout or install" "rc=$rc output=$output"
fi

new_fixture atomic-partial-failure
commit_release one pass
tag_release signed v1.1.0 "$RELEASE_COMMIT"
push_tag v1.1.0
commit_release two pass
tag_release signed v1.2.0 "$RELEASE_COMMIT"
push_tag v1.2.0
write_pin v1.0.0 "$BASE_COMMIT"
before_tags=$(git -C "$REPO" tag | sort)
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" EXTRA_BAD_REFSPEC=1 run_updater); rc=$?
after_tags=$(git -C "$REPO" tag | sort)
if [[ "$rc" -ne 0 && "$before_tags" == "$after_tags" && ! -e "$SENTINEL" ]]; then
  pass "failed multi-candidate atomic fetch installs no new local tag refs"
else
  fail_case "failed multi-candidate atomic fetch installs no new local tag refs" "rc=$rc before=[$before_tags] after=[$after_tags] output=$output"
fi

# Rollback uses the full pre-update OID and runs install only after asserting it.
new_fixture rollback-success
commit_release rollback-base pass
rollback_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$rollback_commit"
push_tag v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$rollback_commit"
commit_release broken-target fail
broken_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$broken_commit"
push_tag v1.1.0
write_pin v1.0.0 "$rollback_commit"
output=$(run_updater); rc=$?
sentinel_lines=$(wc -l <"$SENTINEL" 2>/dev/null || printf '0')
if [[ "$rc" -ne 0 && $(git -C "$REPO" rev-parse HEAD) == "$rollback_commit" && "$sentinel_lines" -eq 2 ]] \
  && grep -Fxq broken-target "$SENTINEL" && grep -Fxq rollback-base "$SENTINEL"; then
  pass "rollback to exact pre-update OID succeeds and only then runs rollback install"
else
  fail_case "rollback to exact pre-update OID succeeds and only then runs rollback install" "rc=$rc lines=$sentinel_lines output=$output"
fi

new_fixture rollback-identity-mismatch
commit_release rollback-base pass
rollback_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$rollback_commit"
push_tag v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$rollback_commit"
commit_release broken-target fail
tag_release signed v1.1.0 "$RELEASE_COMMIT"
push_tag v1.1.0
write_pin v1.0.0 "$rollback_commit"
MISMATCH_STATE=$BASE/mismatch-count
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" MISMATCH_REPO="$REPO" MISMATCH_STATE="$MISMATCH_STATE" run_updater); rc=$?
sentinel_lines=$(wc -l <"$SENTINEL" 2>/dev/null || printf '0')
if [[ "$rc" -ne 0 && "$sentinel_lines" -eq 1 ]] && printf '%s\n' "$output" | grep -Fq 'rollback identity mismatch'; then
  pass "rollback identity mismatch executes no rollback install.sh"
else
  fail_case "rollback identity mismatch executes no rollback install.sh" "rc=$rc lines=$sentinel_lines output=$output"
fi

# Bootstrap: exact owner tag only, substituted/rebound content rejected.
new_fixture bootstrap-exact
commit_release owner-initial pass
owner_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$owner_commit"
push_tag v1.0.0
commit_release newer-not-selected pass
newer_commit=$RELEASE_COMMIT
tag_release signed v2.0.0 "$newer_commit"
push_tag v2.0.0
fetch_local_tag v1.0.0
fetch_local_tag v2.0.0
cron_dest=$BASE/cron/family-updater
output=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 --cron-wrapper-dest "$cron_dest" 2>&1); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$owner_commit" ]] \
  && grep -Fq '"version":"v1.0.0"' "$(pin_path)" \
  && [[ -x "$cron_dest" ]] \
  && cmp -s "$REPO/templates/updater-cron.tmpl.sh" "$cron_dest"; then
  pass "fresh clone bootstrap installs exactly owner-named tag then enables cron"
else
  fail_case "fresh clone bootstrap installs exactly owner-named tag then enables cron" "rc=$rc output=$output"
fi

new_fixture bootstrap-cron-retry
commit_release retry-owner pass
retry_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$retry_commit"
push_tag v1.0.0
fetch_local_tag v1.0.0
blocked_parent=$BASE/cron-parent
printf 'not a directory\n' >"$blocked_parent"
retry_cron_dest=$blocked_parent/family-updater
output=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 --cron-wrapper-dest "$retry_cron_dest" 2>&1); rc=$?
pin_after_failure=$(pin_path)
rm -f "$blocked_parent"
mkdir -p "$blocked_parent"
output2=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 --cron-wrapper-dest "$retry_cron_dest" 2>&1); rc2=$?
if [[ "$rc" -ne 0 && -f "$pin_after_failure" ]] \
  && grep -Fq '"version":"v1.0.0"' "$pin_after_failure" \
  && grep -Fq "\"commit\":\"$retry_commit\"" "$pin_after_failure" \
  && [[ "$rc2" -eq 0 && -x "$retry_cron_dest" ]] \
  && cmp -s "$REPO/templates/updater-cron.tmpl.sh" "$retry_cron_dest"; then
  pass "bootstrap retries cron install when the existing pin has the same identity"
else
  fail_case "bootstrap retries cron install when the existing pin has the same identity" "rc=$rc/$rc2 output=$output output2=$output2"
fi

new_fixture bootstrap-different-pin
commit_release different-pin-owner pass
different_pin_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$different_pin_commit"
push_tag v1.0.0
fetch_local_tag v1.0.0
write_pin v1.0.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
different_pin_cron_dest=$BASE/cron/family-updater
output=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 --cron-wrapper-dest "$different_pin_cron_dest" 2>&1); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$different_pin_cron_dest" ]] \
  && printf '%s\n' "$output" | grep -Fq 'updater pin already exists; bootstrap will not replace it'; then
  pass "bootstrap still refuses an existing pin with a different identity"
else
  fail_case "bootstrap still refuses an existing pin with a different identity" "rc=$rc before=$before after=$after output=$output"
fi

new_fixture bootstrap-substituted
commit_release attacker-content pass
attacker_commit=$RELEASE_COMMIT
tag_release unsigned v1.0.0 "$attacker_commit"
push_tag v1.0.0
fetch_local_tag v1.0.0
before=$(git -C "$REPO" rev-parse HEAD)
output=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 2>&1); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$(pin_path)" ]]; then
  pass "fresh clone attacker-substituted unsigned content is refused"
else
  fail_case "fresh clone attacker-substituted unsigned content is refused" "rc=$rc output=$output"
fi

new_fixture bootstrap-rebound
commit_release genuine-old pass
genuine_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$genuine_commit"
genuine_oid=$(git -C "$SRC" rev-parse refs/tags/v1.0.0)
git -C "$SRC" update-ref refs/tags/v9.9.9 "$genuine_oid"
push_tag v9.9.9
fetch_local_tag v9.9.9
before=$(git -C "$REPO" rev-parse HEAD)
rebound_cron_dest=$BASE/cron/family-updater
output=$(HOME="$HOME_DIR" "$BOOTSTRAP" --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v9.9.9 --cron-wrapper-dest "$rebound_cron_dest" 2>&1); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$(pin_path)" && ! -e "$rebound_cron_dest" ]] \
  && printf '%s\n' "$output" | grep -Fq 'does not exactly match'; then
  pass "bootstrap rejects a rebound initial tag"
else
  fail_case "bootstrap rejects a rebound initial tag" "rc=$rc output=$output"
fi

# Capability and signer-pin failures are explicit and fail closed.
new_fixture capability-old-git
write_pin v0.0.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" FAKE_OLD_GIT=1 run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" ]] && printf '%s\n' "$output" | grep -Fq 'git 2.34 or newer is required'; then
  pass "simulated old git fails closed with capability message"
else
  fail_case "simulated old git fails closed with capability message" "rc=$rc output=$output"
fi

new_fixture missing-signers
write_pin v0.0.0 "$BASE_COMMIT"
missing=$BASE/does-not-exist
output=$(HOME="$HOME_DIR" "$UPDATER" --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary --allowed-signers "$missing" --fma-scripts-dir "$FMA" 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s\n' "$output" | grep -Fq "allowed_signers file is absent, unreadable, or empty: $missing"; then
  pass "missing allowed_signers fails closed and names the file"
else
  fail_case "missing allowed_signers fails closed and names the file" "rc=$rc output=$output"
fi

new_fixture repo-local-signers
write_pin v0.0.0 "$BASE_COMMIT"
cp "$ALLOWED" "$REPO/allowed_signers"
output=$(HOME="$HOME_DIR" "$UPDATER" --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary --allowed-signers "$REPO/allowed_signers" --fma-scripts-dir "$FMA" 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s\n' "$output" | grep -Fq 'must live outside the repository'; then
  pass "repository-local allowed_signers is refused"
else
  fail_case "repository-local allowed_signers is refused" "rc=$rc output=$output"
fi

new_fixture bootstrap-required
output=$(run_updater); rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s\n' "$output" | grep -Fq 'scripts/updater-bootstrap'; then
  pass "absent floor at non-semver HEAD fails closed and names bootstrap"
else
  fail_case "absent floor at non-semver HEAD fails closed and names bootstrap" "rc=$rc output=$output"
fi

new_fixture malformed-pin
malformed_pin=$(pin_path)
mkdir -p "$(dirname "$malformed_pin")"
printf '{"version":"v1.0.0","commit":"not-an-oid","updated_at":"not-a-time"}\n' >"$malformed_pin"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] \
  && printf '%s\n' "$output" | grep -Fq "updater pin file is unparsable or malformed: $malformed_pin"; then
  pass "malformed pin fails closed, names the file, and executes no install"
else
  fail_case "malformed pin fails closed, names the file, and executes no install" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
