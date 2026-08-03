#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/family-updater-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

write_fake_install() {
  src=$1
  result=$2

  cat >"$src/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: install.sh --check --workspace <dir>\n'
}

workspace=$PWD
check_mode=0

while (($# > 0)); do
  case "$1" in
    --check)
      check_mode=1
      shift
      ;;
    --workspace)
      (($# >= 2)) || { usage >&2; exit 2; }
      workspace=$2
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$check_mode" -eq 1 ]] || { usage >&2; exit 2; }
if [[ -f "$(dirname "$0")/.fixture-install-fails" ]]; then
  printf 'fixture install check failed\n'
  exit 1
fi
printf 'check: workspace %s\n' "$workspace"
printf 'ok: fixture install check passed\n'
EOF
  chmod +x "$src/install.sh"
  if [ "$result" = "fail" ]; then
    printf 'fail\n' >"$src/.fixture-install-fails"
  else
    rm -f "$src/.fixture-install-fails"
  fi
}

commit_tag() {
  src=$1
  tag=$2
  date_value=$3
  result=$4

  write_fake_install "$src" "$result"
  printf '%s %s\n' "$tag" "$result" >"$src/VERSION.fixture"
  git -C "$src" add -A >/dev/null 2>&1
  GIT_AUTHOR_DATE="$date_value" GIT_COMMITTER_DATE="$date_value" \
    git -C "$src" commit -m "$tag" >/dev/null
  GIT_COMMITTER_DATE="$date_value" git -C "$src" tag -a "$tag" -m "$tag"
}

make_fma_shims() {
  fma_dir=$1
  log_dir=$2

  mkdir -p "$fma_dir" "$log_dir"
  cat >"$fma_dir/job-heartbeat" <<EOF
#!/usr/bin/env bash
printf '%s\n' "job-heartbeat \$*" >>"$log_dir/heartbeats.log"
EOF
  cat >"$fma_dir/hot-inbox-post" <<EOF
#!/usr/bin/env bash
printf '%s\n' "hot-inbox-post \$*" >>"$log_dir/hot-inbox.log"
EOF
  chmod +x "$fma_dir/job-heartbeat" "$fma_dir/hot-inbox-post"
}

make_fixture() {
  name=$1
  target_result=$2
  checkout_tag=$3
  v10_date=${4:-2020-01-01T00:00:00Z}
  v11_date=${5:-2020-01-02T00:00:00Z}
  v12_date=${6:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
  v10_result=${7:-pass}
  v11_result=${8:-pass}
  base=$TMP_ROOT/$name
  origin=$base/origin.git
  src=$base/src
  repo=$base/repo
  ws=$base/ws
  home=$base/home
  fma=$base/fma
  logs=$base/fma-logs

  mkdir -p "$base" "$ws" "$home"
  git init -q --bare "$origin"
  git init -q "$src"
  git -C "$src" config user.name "Fixture"
  git -C "$src" config user.email "fixture@example.invalid"

  commit_tag "$src" v1.0.0 "$v10_date" "$v10_result"
  commit_tag "$src" v1.1.0 "$v11_date" "$v11_result"
  commit_tag "$src" v1.2.0 "$v12_date" "$target_result"
  git -C "$src" remote add origin "$origin"
  branch=$(git -C "$src" rev-parse --abbrev-ref HEAD)
  git -C "$src" push -q --tags origin "$branch"

  git clone -q "$origin" "$repo" >/dev/null 2>&1
  git -C "$repo" checkout --detach "$checkout_tag" >/dev/null 2>&1
  make_fma_shims "$fma" "$logs"
  printf '%s\n' "$base"
}

repo_for() {
  printf '%s\n' "$1/repo"
}

src_for() {
  printf '%s\n' "$1/src"
}

home_for() {
  printf '%s\n' "$1/home"
}

fma_for() {
  printf '%s\n' "$1/fma"
}

logs_for() {
  printf '%s\n' "$1/fma-logs"
}

ws_for() {
  printf '%s\n' "$1/ws"
}

ledger_for() {
  printf '%s\n' "$1/home/.claude/state/installed-versions.log"
}

current_tag() {
  git -C "$1" describe --tags --exact-match 2>/dev/null
}

run_updater() {
  base=$1
  ring=$2
  soak=$3
  shift 3
  HOME=$(home_for "$base") "$ROOT/scripts/family-updater" \
    --repo-dir "$(repo_for "$base")" \
    --workspace "$(ws_for "$base")" \
    --agent claire \
    --ring "$ring" \
    --soak-hours "$soak" \
    --fma-scripts-dir "$(fma_for "$base")" \
    "$@" 2>&1
}

assert_file_contains() {
  name=$1
  file=$2
  expected=$3

  if [ -f "$file" ] && grep -Fq "$expected" "$file"; then
    pass "$name"
  else
    fail_case "$name" "missing '$expected' in $file"
  fi
}

base=$(make_fixture normal pass v1.0.0)
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ]; then
  pass "normal update moves to newest canary tag"
else
  fail_case "normal update moves to newest canary tag" "rc=$rc output=$output"
fi
assert_file_contains "normal update sends ok heartbeat" "$(logs_for "$base")/heartbeats.log" "job-heartbeat updater-claire ok --reason v1.2.0"
assert_file_contains "normal update appends ok ledger" "$(ledger_for "$base")" "claire repo v1.2.0 ok"

base=$(make_fixture semver-filter pass v1.0.0)
src=$(src_for "$base")
commit_tag "$src" v1.3.0-rc1 "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" pass
commit_tag "$src" latest "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" pass
commit_tag "$src" 1.4.0 "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" pass
git -C "$src" push -q --tags origin "$(git -C "$src" rev-parse --abbrev-ref HEAD)"
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ]; then
  pass "canary ignores prerelease and non-semver tags"
else
  fail_case "canary ignores prerelease and non-semver tags" "rc=$rc output=$output"
fi

base=$(make_fixture stable-skip pass v1.0.0)
output=$(run_updater "$base" stable 1)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.1.0" ]; then
  pass "stable ring skips too-fresh tag"
else
  fail_case "stable ring skips too-fresh tag" "rc=$rc output=$output"
fi
output=$(run_updater "$base" canary 1)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ]; then
  pass "canary takes too-fresh tag"
else
  fail_case "canary takes too-fresh tag" "rc=$rc output=$output"
fi

base=$(make_fixture canary-soak-ignored pass v1.0.0)
output=$(run_updater "$base" canary 999)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ]; then
  pass "canary ignores soak hours"
else
  fail_case "canary ignores soak hours" "rc=$rc output=$output"
fi

now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
base=$(make_fixture stable-no-old-tags pass v1.0.0 "$now" "$now" "$now")
before_head=$(git -C "$(repo_for "$base")" rev-parse HEAD)
output=$(run_updater "$base" stable 1)
rc=$?
after_head=$(git -C "$(repo_for "$base")" rev-parse HEAD)
if [ "$rc" -eq 0 ] \
  && [ "$before_head" = "$after_head" ] \
  && printf '%s\n' "$output" | grep -Fq "family-updater: no stable tag old enough for 1 hour soak; already up to date"; then
  pass "stable exits zero when no tag satisfies soak"
else
  fail_case "stable exits zero when no tag satisfies soak" "rc=$rc output=$output"
fi
if [ ! -f "$(logs_for "$base")/hot-inbox.log" ]; then
  pass "stable soak skip does not post hot-inbox"
else
  fail_case "stable soak skip does not post hot-inbox" "unexpected hot-inbox log"
fi

base=$(make_fixture rollback fail v1.1.0)
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -ne 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.1.0" ]; then
  pass "check failure rolls back to previous tag"
else
  fail_case "check failure rolls back to previous tag" "rc=$rc output=$output"
fi
assert_file_contains "failure sends fail heartbeat" "$(logs_for "$base")/heartbeats.log" "job-heartbeat updater-claire fail --reason fixture install check failed"
if [ -f "$(logs_for "$base")/hot-inbox.log" ] && [ "$(wc -l <"$(logs_for "$base")/hot-inbox.log")" -eq 1 ]; then
  pass "failure posts exactly one hot-inbox caution"
else
  fail_case "failure posts exactly one hot-inbox caution" "hot-inbox log missing or wrong line count"
fi
assert_file_contains "failure appends fail ledger" "$(ledger_for "$base")" "claire repo v1.2.0 fail"

now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
base=$(make_fixture rollback-also-fails fail v1.1.0 "2020-01-01T00:00:00Z" "2020-01-02T00:00:00Z" "$now" pass fail)
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -ne 0 ] && [ "$(current_tag "$(repo_for "$base")")" = "v1.1.0" ]; then
  pass "rollback also fails stays on rollback tag"
else
  fail_case "rollback also fails stays on rollback tag" "rc=$rc output=$output"
fi
assert_file_contains "rollback also fails is visible in hot-inbox" "$(logs_for "$base")/hot-inbox.log" "rollback to v1.1.0 ALSO failed its check"
if [ -f "$(logs_for "$base")/hot-inbox.log" ] && [ "$(wc -l <"$(logs_for "$base")/hot-inbox.log")" -eq 1 ]; then
  pass "rollback also fails posts exactly one hot-inbox caution"
else
  fail_case "rollback also fails posts exactly one hot-inbox caution" "hot-inbox log missing or wrong line count"
fi

base=$(make_fixture already pass v1.2.0)
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "already up to date exits zero"
else
  fail_case "already up to date exits zero" "rc=$rc output=$output"
fi
assert_file_contains "already up to date sends ok heartbeat" "$(logs_for "$base")/heartbeats.log" "job-heartbeat updater-claire ok --reason v1.2.0"
if [ ! -f "$(logs_for "$base")/hot-inbox.log" ]; then
  pass "already up to date does not post hot-inbox"
else
  fail_case "already up to date does not post hot-inbox" "unexpected hot-inbox log"
fi
# No-op runs intentionally skip the ledger so repeated cron heartbeats do not
# duplicate installed-version entries.
if [ ! -f "$(ledger_for "$base")" ]; then
  pass "already up to date skips ledger"
else
  fail_case "already up to date skips ledger" "unexpected ledger entry"
fi

base=$(make_fixture already-dry-run pass v1.2.0)
output=$(run_updater "$base" canary 24 --dry-run)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fq "dry-run: already at v1.2.0, nothing to do" \
  && [ ! -f "$(ledger_for "$base")" ] \
  && [ ! -f "$(logs_for "$base")/heartbeats.log" ] \
  && [ ! -f "$(logs_for "$base")/hot-inbox.log" ]; then
  pass "dry-run already current leaves reporters and ledger untouched"
else
  fail_case "dry-run already current leaves reporters and ledger untouched" "rc=$rc output=$output"
fi

base=$(make_fixture fetch-failure pass v1.0.0)
repo=$(repo_for "$base")
before_head=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" remote set-url origin "$base/missing-origin.git"
output=$(run_updater "$base" canary 24)
rc=$?
after_head=$(git -C "$repo" rev-parse HEAD)
if [ "$rc" -ne 0 ] && [ "$before_head" = "$after_head" ]; then
  pass "fetch failure exits nonzero without moving HEAD"
else
  fail_case "fetch failure exits nonzero without moving HEAD" "rc=$rc output=$output"
fi
assert_file_contains "fetch failure sends fail heartbeat" "$(logs_for "$base")/heartbeats.log" "job-heartbeat updater-claire fail --reason git fetch failed"
if [ -f "$(logs_for "$base")/hot-inbox.log" ] && [ "$(wc -l <"$(logs_for "$base")/hot-inbox.log")" -eq 1 ]; then
  pass "fetch failure posts exactly one hot-inbox caution"
else
  fail_case "fetch failure posts exactly one hot-inbox caution" "hot-inbox log missing or wrong line count"
fi
assert_file_contains "fetch failure appends fail ledger" "$(ledger_for "$base")" "claire repo fetch-failed fail"

base=$(make_fixture dirty-worktree pass v1.0.0)
repo=$(repo_for "$base")
before_head=$(git -C "$repo" rev-parse HEAD)
printf 'local change\n' >>"$repo/VERSION.fixture"
output=$(run_updater "$base" canary 24)
rc=$?
after_head=$(git -C "$repo" rev-parse HEAD)
if [ "$rc" -ne 0 ] && [ "$before_head" = "$after_head" ]; then
  pass "dirty worktree exits nonzero without moving HEAD"
else
  fail_case "dirty worktree exits nonzero without moving HEAD" "rc=$rc output=$output"
fi
assert_file_contains "dirty worktree posts refusal message" "$(logs_for "$base")/hot-inbox.log" "repo has local modifications, refusing to update"
assert_file_contains "dirty worktree appends fail ledger" "$(ledger_for "$base")" "claire repo v1.2.0 fail"

base=$(make_fixture lock-held pass v1.0.0)
repo=$(repo_for "$base")
before_head=$(git -C "$repo" rev-parse HEAD)
mkdir "$repo/.family-updater.lock"
printf '%s\n' "$$" >"$repo/.family-updater.lock/pid"
output=$(run_updater "$base" canary 24)
rc=$?
after_head=$(git -C "$repo" rev-parse HEAD)
rm -rf "$repo/.family-updater.lock"
if [ "$rc" -ne 0 ] && [ "$before_head" = "$after_head" ]; then
  pass "live lock exits nonzero without moving HEAD"
else
  fail_case "live lock exits nonzero without moving HEAD" "rc=$rc output=$output"
fi
assert_file_contains "live lock sends fail heartbeat" "$(logs_for "$base")/heartbeats.log" "job-heartbeat updater-claire fail --reason lock held by live pid"

base=$(make_fixture stale-lock pass v1.0.0)
repo=$(repo_for "$base")
mkdir "$repo/.family-updater.lock"
printf '%s\n' 999999 >"$repo/.family-updater.lock/pid"
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(current_tag "$repo")" = "v1.2.0" ] \
  && [ ! -d "$repo/.family-updater.lock" ]; then
  pass "stale lock is reclaimed and released"
else
  fail_case "stale lock is reclaimed and released" "rc=$rc output=$output"
fi

base=$(make_fixture missing-fma pass v1.0.0)
missing_dir=$base/missing-fma
output=$(HOME=$(home_for "$base") "$ROOT/scripts/family-updater" \
  --repo-dir "$(repo_for "$base")" \
  --workspace "$(ws_for "$base")" \
  --agent claire \
  --ring canary \
  --fma-scripts-dir "$missing_dir" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ] \
  && [ -f "$(ledger_for "$base")" ] \
  && printf '%s\n' "$output" | grep -Fq "warning: reporter script missing"; then
  pass "missing fma dir warns but update succeeds"
else
  fail_case "missing fma dir warns but update succeeds" "rc=$rc output=$output"
fi

base=$(make_fixture failing-heartbeat pass v1.0.0)
cat >"$(fma_for "$base")/job-heartbeat" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$(fma_for "$base")/job-heartbeat"
output=$(run_updater "$base" canary 24)
rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(current_tag "$(repo_for "$base")")" = "v1.2.0" ] \
  && printf '%s\n' "$output" | grep -Fq "warning: heartbeat reporter failed"; then
  pass "failing heartbeat reporter warns but update succeeds"
else
  fail_case "failing heartbeat reporter warns but update succeeds" "rc=$rc output=$output"
fi

base=$(make_fixture dry-run pass v1.0.0)
before_head=$(git -C "$(repo_for "$base")" rev-parse HEAD)
output=$(run_updater "$base" canary 24 --dry-run)
rc=$?
after_head=$(git -C "$(repo_for "$base")" rev-parse HEAD)
if [ "$rc" -eq 0 ] \
  && [ "$before_head" = "$after_head" ] \
  && [ ! -f "$(ledger_for "$base")" ] \
  && [ ! -f "$(logs_for "$base")/heartbeats.log" ] \
  && [ ! -f "$(logs_for "$base")/hot-inbox.log" ]; then
  pass "dry-run leaves head ledger and reporters untouched"
else
  fail_case "dry-run leaves head ledger and reporters untouched" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
