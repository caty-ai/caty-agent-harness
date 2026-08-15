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

write_allowed_signers_for_key() {
  local public_key=$1
  printf '# updater-repo: %s\n' "$(cd "$ORIGIN" && pwd -P)" >"$ALLOWED"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$public_key")" >>"$ALLOWED"
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

  git init -q --bare "$ORIGIN"
  write_allowed_signers_for_key "$KEY.pub"
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
  export CATY_UPDATER_RELEASE_BRANCH=$BRANCH
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
  local kind=$1 name=$2 commit=$3 tag_date=${4:-2020-02-01T00:00:00Z}
  case "$kind" in
    signed)
      git -C "$SRC" config user.signingkey "$KEY"
      GIT_COMMITTER_DATE="$tag_date" git -C "$SRC" tag -s "$name" "$commit" -m "$name"
      ;;
    unpinned)
      git -C "$SRC" config user.signingkey "$OTHER_KEY"
      GIT_COMMITTER_DATE="$tag_date" git -C "$SRC" tag -s "$name" "$commit" -m "$name"
      git -C "$SRC" config user.signingkey "$KEY"
      ;;
    unsigned)
      GIT_COMMITTER_DATE="$tag_date" git -C "$SRC" tag -a "$name" "$commit" -m "$name"
      ;;
    lightweight)
      git -C "$SRC" tag "$name" "$commit"
      ;;
  esac
}

push_tag_only() { git -C "$SRC" push -q "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }
publish_branch_backed_release() {
  git -C "$SRC" push -q "$ORIGIN" "$BRANCH"
  push_tag_only "$1"
}
force_push_tag() { git -C "$SRC" push -q --force "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }
fetch_local_tag() { git -C "$REPO" fetch -q --no-tags "$ORIGIN" "refs/tags/$1:refs/tags/$1"; }

repo_state_key() {
  local repo_real repo_hash
  repo_real=$(cd "$REPO" && pwd -P)
  repo_hash=$(printf '%s' "$repo_real" | git hash-object --stdin)
  printf '%s-%s\n' "$(basename "$repo_real")" "${repo_hash:0:12}"
}
pin_path() { printf '%s/.claude/state/updater-pin/%s.json\n' "$HOME_DIR" "$(repo_state_key)"; }
ineligible_path() { printf '%s/.claude/state/updater-ineligible/%s.log\n' "$HOME_DIR" "$(repo_state_key)"; }
ledger_path() { printf '%s/.claude/state/installed-versions.log\n' "$HOME_DIR"; }
startup_failure_path() { printf '%s/.claude/state/updater-startup-failures/%s.log\n' "$HOME_DIR" "$(repo_state_key)"; }

append_ok_ledger() {
  local tag=$1
  printf '2020-01-01T00:00:00Z claire %s %s ok\n' "$(basename "$REPO")" "$tag" >>"$(ledger_path)"
}

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

make_foreign_release() {
  local label=$1 tag=$2
  local foreign_src=$BASE/foreign-src

  FOREIGN_SRC=$foreign_src
  git init -q "$FOREIGN_SRC"
  git -C "$FOREIGN_SRC" config user.name 'Foreign Fixture'
  git -C "$FOREIGN_SRC" config user.email fixture@example.invalid
  git -C "$FOREIGN_SRC" config gpg.format ssh
  git -C "$FOREIGN_SRC" config user.signingkey "$KEY"
  write_fake_install "$FOREIGN_SRC" pass
  mkdir -p "$FOREIGN_SRC/templates"
  cat >"$FOREIGN_SRC/templates/updater-cron.tmpl.sh" <<'FOREIGN_CRON_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
printf 'foreign fixture updater cron wrapper\n'
FOREIGN_CRON_WRAPPER
  printf '%s\n' "$label" >"$FOREIGN_SRC/VERSION.fixture"
  git -C "$FOREIGN_SRC" add -A
  GIT_AUTHOR_DATE=2020-03-01T00:00:00Z GIT_COMMITTER_DATE=2020-03-01T00:00:00Z \
    git -C "$FOREIGN_SRC" commit -qm "$label"
  FOREIGN_COMMIT=$(git -C "$FOREIGN_SRC" rev-parse HEAD)
  GIT_COMMITTER_DATE=2020-03-01T00:00:00Z \
    git -C "$FOREIGN_SRC" tag -s "$tag" "$FOREIGN_COMMIT" -m "$tag"
  git -C "$FOREIGN_SRC" push -q "$ORIGIN" "refs/tags/$tag:refs/tags/$tag"
}

run_issue54_updater_replay_case() {
  local legitimate_commit foreign_commit expected_reason output rc
  local verification_records moved_records install_failure_records
  local failure_reports failure_heartbeats success_heartbeats binding_lines sentinel_lines

  new_fixture issue54-updater-cross-repo-replay
  write_pin v1.0.0 "$BASE_COMMIT"

  commit_release legitimate-sibling pass
  legitimate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$legitimate_commit"
  publish_branch_backed_release v1.1.0

  make_foreign_release foreign-replay v9.9.9
  foreign_commit=$FOREIGN_COMMIT
  expected_reason="captured commit $foreign_commit is not on release branch origin/$BRANCH"

  output=$(CATY_UPDATER_RELEASE_BRANCH="$BRANCH" run_updater); rc=$?
  verification_records=$(grep -F 'v9.9.9 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc " verification-failure $expected_reason" || true)
  moved_records=$(grep -F 'v9.9.9 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc ' moved-tag' || true)
  install_failure_records=$(grep -F 'v9.9.9 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc ' install-failure ' || true)
  failure_reports=$(grep -Fc 'updater failed: claire repo v9.9.9' \
    "$LOGS/hot-inbox.log" 2>/dev/null || true)
  failure_heartbeats=$(grep -Fc "job-heartbeat updater-claire fail --reason $expected_reason" \
    "$LOGS/heartbeats.log" 2>/dev/null || true)
  success_heartbeats=$(grep -Fc 'job-heartbeat updater-claire ok --reason v1.1.0' \
    "$LOGS/heartbeats.log" 2>/dev/null || true)
  binding_lines=$(printf '%s\n' "$output" \
    | grep -Fc "family-updater: repository binding verified: $(cd "$ORIGIN" && pwd -P)" || true)
  sentinel_lines=0
  [[ ! -f "$SENTINEL" ]] || sentinel_lines=$(wc -l <"$SENTINEL")

  if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$legitimate_commit" \
    && "$foreign_commit" != "$legitimate_commit" && "$sentinel_lines" -eq 1 ]] \
    && grep -Fxq legitimate-sibling "$SENTINEL" \
    && grep -Fq '"version":"v1.1.0"' "$(pin_path)" \
    && grep -Fq "\"commit\":\"$legitimate_commit\"" "$(pin_path)" \
    && [[ "$verification_records" -eq 1 && "$moved_records" -eq 0 \
      && "$install_failure_records" -eq 0 && "$failure_reports" -eq 1 \
      && "$failure_heartbeats" -eq 1 && "$success_heartbeats" -eq 1 \
      && "$binding_lines" -eq 1 \
      && ! -e "$HOME_DIR/.claude/state/updater-signers-snapshot" ]]; then
    pass "cross-repo replay is refused while a release-branch sibling installs"
  else
    fail_case "cross-repo replay is refused while a release-branch sibling installs" \
      "foreign replay was accepted or sibling did not install: rc=$rc head=$(git -C "$REPO" rev-parse HEAD) expected-head=$legitimate_commit records=$verification_records/$moved_records/$install_failure_records reports=$failure_reports heartbeats=$failure_heartbeats/$success_heartbeats binding-lines=$binding_lines snapshot-dir=$(test -e "$HOME_DIR/.claude/state/updater-signers-snapshot" && echo yes || echo no) installs=$sentinel_lines output=$output"
  fi
}

run_issue54_bootstrap_replay_case() {
  local before after foreign_commit expected_reason cron_dest output rc

  new_fixture issue54-bootstrap-cross-repo-replay
  make_foreign_release foreign-bootstrap-replay v1.0.0
  foreign_commit=$FOREIGN_COMMIT
  fetch_local_tag v1.0.0
  before=$(git -C "$REPO" rev-parse HEAD)
  cron_dest=$BASE/cron/family-updater
  expected_reason="captured commit $foreign_commit is not on release branch origin/$BRANCH"

  output=$(HOME="$HOME_DIR" CATY_UPDATER_RELEASE_BRANCH="$BRANCH" "$BOOTSTRAP" \
    --repo-dir "$REPO" --allowed-signers "$ALLOWED" --initial-tag v1.0.0 \
    --cron-wrapper-dest "$cron_dest" 2>&1); rc=$?
  after=$(git -C "$REPO" rev-parse HEAD)
  if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$(pin_path)" \
    && ! -e "$cron_dest" ]] \
    && printf '%s\n' "$output" | grep -Fq "updater-bootstrap error: $expected_reason"; then
    pass "bootstrap refuses a foreign owner-named tag without checkout, pin, or wrapper"
  else
    fail_case "bootstrap refuses a foreign owner-named tag without checkout, pin, or wrapper" \
      "foreign replay was accepted: rc=$rc before=$before after=$after pin=$(test -e "$(pin_path)" && echo yes || echo no) wrapper=$(test -e "$cron_dest" && echo yes || echo no) output=$output"
  fi
}

validate_fixture_binding() {
  HOME="$HOME_DIR" bash -c '
    source "$1"
    trap updater_cleanup_allowed_signers_snapshot EXIT
    if updater_validate_allowed_signers "$2" "$3"; then
      printf "binding-ok:%s\n" "$UPDATER_REPOSITORY_IDENTITY"
    else
      printf "%s\n" "$UPDATER_VERIFY_REASON"
      exit 1
    fi
  ' _ "$ROOT/scripts/lib-updater-verify.sh" "$REPO" "$1" 2>&1
}

normalize_fixture_url() {
  HOME="$HOME_DIR" bash -c '
    source "$1"
    if updater_normalize_repo_url "$2" normalized; then
      printf "%s\n" "$normalized"
    else
      printf "refused\n"
      exit 1
    fi
  ' _ "$ROOT/scripts/lib-updater-verify.sh" "$1" 2>&1
}

run_issue54_binding_cases() {
  local identity output rc replacement snapshot_output snapshot_rc

  new_fixture issue54-binding-directive
  identity=$(cd "$ORIGIN" && pwd -P)
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -eq 0 && "$output" == "binding-ok:$identity" ]]; then
    pass "matching repository directive binds the signer snapshot"
  else
    fail_case "matching repository directive binds the signer snapshot" "rc=$rc output=$output"
  fi

  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >"$ALLOWED"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "allowed_signers has no repository binding directive (expected '# updater-repo: <identity>'): $ALLOWED" ]]; then
    pass "signer file without a repository directive is refused"
  else
    fail_case "signer file without a repository directive is refused" "rc=$rc output=$output"
  fi

  write_allowed_signers_for_key "$KEY.pub"
  printf '# updater-repo: %s\n' "$identity" >>"$ALLOWED"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "allowed_signers has multiple repository binding directives: $ALLOWED" ]]; then
    pass "multiple repository directives are refused"
  else
    fail_case "multiple repository directives are refused" "rc=$rc output=$output"
  fi

  printf '# updater-repo: %s/other\n' "$identity" >"$ALLOWED"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >>"$ALLOWED"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "allowed_signers repository binding mismatch: file declares '$identity/other', origin normalizes to '$identity'" ]]; then
    pass "mismatched repository directive is refused"
  else
    fail_case "mismatched repository directive is refused" "rc=$rc output=$output"
  fi

  printf '# updater-repo: %s\r\n' "$identity" >"$ALLOWED"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >>"$ALLOWED"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "repository binding directive has trailing whitespace or a CRLF line ending: $ALLOWED" ]]; then
    pass "CRLF repository directive is refused with the explicit reason"
  else
    fail_case "CRLF repository directive is refused with the explicit reason" "rc=$rc output=$output"
  fi

  printf '# updater-repo: %s \n' "$identity" >"$ALLOWED"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >>"$ALLOWED"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "repository binding directive has trailing whitespace or a CRLF line ending: $ALLOWED" ]]; then
    pass "trailing-space repository directive is refused"
  else
    fail_case "trailing-space repository directive is refused" "rc=$rc output=$output"
  fi

  output=$(validate_fixture_binding relative-allowed-signers); rc=$?
  if [[ "$rc" -ne 0 && "$output" == 'allowed_signers path must be absolute: relative-allowed-signers' ]]; then
    pass "relative allowed_signers path is refused before filesystem lookup"
  else
    fail_case "relative allowed_signers path is refused before filesystem lookup" "rc=$rc output=$output"
  fi

  new_fixture issue54-signer-snapshot
  commit_release snapshot-release pass
  tag_release signed v1.0.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.0.0
  fetch_local_tag v1.0.0
  replacement=$BASE/replacement-allowed-signers
  printf '# updater-repo: %s\n' "$(cd "$ORIGIN" && pwd -P)" >"$replacement"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$OTHER_KEY.pub")" >>"$replacement"
  snapshot_output=$(HOME="$HOME_DIR" bash -c '
    source "$1"
    trap updater_cleanup_allowed_signers_snapshot EXIT
    updater_validate_allowed_signers "$2" "$3" || { printf "%s\n" "$UPDATER_VERIFY_REASON"; exit 1; }
    cp "$4" "$3"
    updater_capture_verify_and_bind "$2" v1.0.0 "$UPDATER_ALLOWED_SIGNERS_SNAPSHOT" \
      || { printf "%s\n" "$UPDATER_VERIFY_REASON"; exit 1; }
    printf "%s\n" "$UPDATER_CAPTURED_COMMIT"
  ' _ "$ROOT/scripts/lib-updater-verify.sh" "$REPO" "$ALLOWED" "$replacement" 2>&1); snapshot_rc=$?
  if [[ "$snapshot_rc" -eq 0 && "$snapshot_output" == "$RELEASE_COMMIT" \
    && ! -e "$HOME_DIR/.claude/state/updater-signers-snapshot" ]]; then
    pass "verification consumes the validated signer snapshot after source replacement"
  else
    fail_case "verification consumes the validated signer snapshot after source replacement" \
      "rc=$snapshot_rc snapshot-dir=$(test -e "$HOME_DIR/.claude/state/updater-signers-snapshot" && echo yes || echo no) output=$snapshot_output"
  fi
}

run_issue54_normalization_cases() {
  local identity output rc probe_cred token_surface multi_url token_fakebin

  new_fixture issue54-normalization
  identity=$(cd "$ORIGIN" && pwd -P)
  for accepted in \
    'git@GitHub.COM:Org/Repo.git/' \
    'ssh://git@GitHub.COM:22/Org/Repo.git/' \
    'https://user:token-value@GitHub.COM:443/Org/Repo.git/'; do
    output=$(normalize_fixture_url "$accepted"); rc=$?
    if [[ "$rc" -eq 0 && "$output" == github.com/org/repo && "$output" != *token-value* ]]; then
      pass "accepted host origin normalizes without userinfo: ${accepted%%:*}"
    else
      fail_case "accepted host origin normalizes without userinfo: ${accepted%%:*}" "rc=$rc output=$output"
    fi
  done
  for accepted in "$ORIGIN" "file://$ORIGIN" "file://localhost$ORIGIN"; do
    output=$(normalize_fixture_url "$accepted"); rc=$?
    if [[ "$rc" -eq 0 && "$output" == "$identity" ]]; then
      pass "accepted local origin resolves to its physical path"
    else
      fail_case "accepted local origin resolves to its physical path" "rc=$rc output=$output"
    fi
  done
  for refused in \
    'ssh://git@example.invalid:2222/org/repo.git' \
    'https://example.invalid:444/org/repo.git' \
    'ssh://git@[2001:db8::1]:22/org/repo.git' \
    'git://example.invalid/org/repo.git' \
    'relative/repo.git' \
    'file://remotehost/absolute/repo.git' \
    'https://example.invalid/org/repo.git?mirror=1'; do
    output=$(normalize_fixture_url "$refused"); rc=$?
    if [[ "$rc" -ne 0 && "$output" == refused ]]; then
      pass "unsupported origin shape is refused"
    else
      fail_case "unsupported origin shape is refused" "rc=$rc output=$output"
    fi
  done

  new_fixture issue54-token-origin
  probe_cred='issue54-well-formed-token'
  git -C "$REPO" remote set-url origin "https://user:$probe_cred@example.invalid/org/repo.git"
  printf '# updater-repo: example.invalid/org/repo\n' >"$ALLOWED"
  printf 'fixture@example.invalid %s\n' "$(sed -n '1p' "$KEY.pub")" >>"$ALLOWED"
  write_pin v0.0.0 "$BASE_COMMIT"
  token_fakebin=$BASE/token-fakebin
  mkdir -p "$token_fakebin"
  cat >"$token_fakebin/git" <<'TOKEN_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == *" fetch "* ]]; then
  printf 'simulated transport failure for %s\n' "$*" >&2
  exit 71
fi
exec "$REAL_GIT" "$@"
TOKEN_GIT_SHIM
  chmod +x "$token_fakebin/git"
  output=$(PATH="$token_fakebin:$PATH" REAL_GIT="$REAL_GIT" run_updater); rc=$?
  token_surface=$(grep -R -F "$probe_cred" "$HOME_DIR/.claude/state" "$LOGS" 2>/dev/null || true)
  if [[ "$rc" -ne 0 && "$output" != *"$probe_cred"* && -z "$token_surface" ]] \
    && printf '%s\n' "$output" | grep -Fq 'branch fetch failed'; then
    pass "well-formed credential origin is accepted without exposing its token on transport failure"
  else
    fail_case "well-formed credential origin is accepted without exposing its token on transport failure" \
      "rc=$rc output-token=$(case $output in *$probe_cred*) echo yes;; *) echo no;; esac) state-token=$(test -n "$token_surface" && echo yes || echo no)"
  fi

  new_fixture issue54-malformed-token-origin
  probe_cred='issue54-secret-token'
  git -C "$REPO" remote set-url origin "https://user:$probe_cred@[broken/origin.git"
  write_pin v0.0.0 "$BASE_COMMIT"
  output=$(run_updater); rc=$?
  token_surface=$(grep -R -F "$probe_cred" "$HOME_DIR/.claude/state" "$LOGS" 2>/dev/null || true)
  if [[ "$rc" -ne 0 && "$output" != *"$probe_cred"* && -z "$token_surface" ]] \
    && printf '%s\n' "$output" | grep -Fq "cannot normalize origin URL for repository binding: $REPO"; then
    pass "malformed credential origin is refused without exposing its token"
  else
    fail_case "malformed credential origin is refused without exposing its token" \
      "rc=$rc output-token=$(case $output in *$probe_cred*) echo yes;; *) echo no;; esac) state-token=$(test -n "$token_surface" && echo yes || echo no)"
  fi

  new_fixture issue54-multiple-origin-urls
  multi_url=$BASE/second-origin.git
  git init -q --bare "$multi_url"
  git -C "$REPO" config --add remote.origin.url "$multi_url"
  output=$(validate_fixture_binding "$ALLOWED"); rc=$?
  if [[ "$rc" -ne 0 && "$output" == "cannot determine origin URL for repository binding: $REPO" ]]; then
    pass "multiple origin URLs are refused"
  else
    fail_case "multiple origin URLs are refused" "rc=$rc output=$output"
  fi
}

run_issue54_reachability_cases() {
  local candidate_commit expected output rc before anchor_branch
  local merge_fakebin merge_records wrong_reason revparse_fakebin revparse_records
  local endpoint_fakebin evil_origin

  new_fixture issue54-tag-only-reachability
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release tag-only-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  push_tag_only v1.1.0
  before=$(git -C "$REPO" rev-parse HEAD)
  expected="captured commit $candidate_commit is not on release branch origin/$BRANCH"
  output=$(run_updater); rc=$?
  if [[ "$rc" -ne 0 && $(git -C "$REPO" rev-parse HEAD) == "$before" \
    && ! -e "$SENTINEL" ]] && printf '%s\n' "$output" | grep -Fq "$expected"; then
    pass "tag-only reachable commit is refused"
  else
    fail_case "tag-only reachable commit is refused" "rc=$rc output=$output"
  fi

  new_fixture issue54-pruned-release-anchor
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release anchored-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  push_tag_only v1.1.0
  anchor_branch=release-anchor
  git -C "$SRC" push -q "$ORIGIN" "HEAD:refs/heads/$anchor_branch"
  output=$(CATY_UPDATER_RELEASE_BRANCH="$anchor_branch" run_updater --dry-run); rc=$?
  git -C "$SRC" push -q "$ORIGIN" ":refs/heads/$anchor_branch"
  output2=$(CATY_UPDATER_RELEASE_BRANCH="$anchor_branch" run_updater --dry-run); rc2=$?
  if [[ "$rc" -eq 0 && "$rc2" -ne 0 ]] \
    && printf '%s\n' "$output2" | grep -Fq "release ref refs/remotes/origin/$anchor_branch is unavailable: $REPO" \
    && ! git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$anchor_branch"; then
    pass "deleted release anchor is pruned and cannot vouch on the next tick"
  else
    fail_case "deleted release anchor is pruned and cannot vouch on the next tick" "rc=$rc/$rc2 output=$output output2=$output2"
  fi

  new_fixture issue54-invalid-release-branch
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release invalid-branch-candidate pass
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.1.0
  output=$(CATY_UPDATER_RELEASE_BRANCH='bad..branch' run_updater); rc=$?
  if [[ "$rc" -ne 0 ]] && printf '%s\n' "$output" | grep -Fq 'invalid release branch name configured' \
    && printf '%s\n' "$output" | grep -Fqv 'bad..branch'; then
    pass "invalid release branch config is refused without echoing its value"
  else
    fail_case "invalid release branch config is refused without echoing its value" "rc=$rc output=$output"
  fi

  new_fixture issue54-merge-base-error
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release merge-error-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  publish_branch_backed_release v1.1.0
  merge_fakebin=$BASE/merge-fakebin
  mkdir -p "$merge_fakebin"
  cat >"$merge_fakebin/git" <<'MERGE_ERROR_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == *" merge-base --is-ancestor "* ]]; then
  exit 71
fi
exec "$REAL_GIT" "$@"
MERGE_ERROR_GIT_SHIM
  chmod +x "$merge_fakebin/git"
  expected="reachability check failed (git error) for $candidate_commit against origin/$BRANCH"
  output=$(PATH="$merge_fakebin:$PATH" REAL_GIT="$REAL_GIT" run_updater); rc=$?
  merge_records=$(grep -F 'v1.1.0 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc " verification-failure $expected" || true)
  wrong_reason=$(printf '%s\n' "$output" | grep -Fc 'is not on release branch' || true)
  if [[ "$rc" -ne 0 && "$merge_records" -eq 1 && "$wrong_reason" -eq 0 ]] \
    && printf '%s\n' "$output" | grep -Fq "$expected"; then
    pass "merge-base operational failure has a distinct fatal reason"
  else
    fail_case "merge-base operational failure has a distinct fatal reason" \
      "rc=$rc records=$merge_records wrong-reason=$wrong_reason output=$output"
  fi

  new_fixture issue54-release-ref-rev-parse-error
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release rev-parse-error-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  publish_branch_backed_release v1.1.0
  revparse_fakebin=$BASE/revparse-fakebin
  mkdir -p "$revparse_fakebin"
  cat >"$revparse_fakebin/git" <<'REV_PARSE_ERROR_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == "-C $REV_PARSE_REPO rev-parse --verify refs/remotes/origin/$REV_PARSE_BRANCH" ]]; then
  exit 71
fi
exec "$REAL_GIT" "$@"
REV_PARSE_ERROR_GIT_SHIM
  chmod +x "$revparse_fakebin/git"
  expected="reachability check failed (git error) for $candidate_commit against origin/$BRANCH"
  output=$(PATH="$revparse_fakebin:$PATH" REAL_GIT="$REAL_GIT" \
    REV_PARSE_REPO="$REPO" REV_PARSE_BRANCH="$BRANCH" run_updater); rc=$?
  revparse_records=$(grep -F 'v1.1.0 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc " verification-failure $expected" || true)
  wrong_reason=$(printf '%s\n' "$output" | grep -Fc 'release ref refs/remotes/origin/' || true)
  if [[ "$rc" -ne 0 && "$revparse_records" -eq 1 && "$wrong_reason" -eq 0 ]] \
    && printf '%s\n' "$output" | grep -Fq "$expected"; then
    pass "release-ref rev-parse operational failure has the git-error reason"
  else
    fail_case "release-ref rev-parse operational failure has the git-error reason" \
      "rc=$rc records=$revparse_records wrong-reason=$wrong_reason output=$output"
  fi

  new_fixture issue54-captured-endpoint
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release endpoint-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  publish_branch_backed_release v1.1.0
  evil_origin=$BASE/evil-origin.git
  git init -q --bare "$evil_origin"
  endpoint_fakebin=$BASE/endpoint-fakebin
  mkdir -p "$endpoint_fakebin"
  cat >"$endpoint_fakebin/git" <<'ENDPOINT_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == "-C $BIND_REPO remote get-url --all origin" ]]; then
  output=$($REAL_GIT "$@") || exit $?
  "$REAL_GIT" -C "$BIND_REPO" remote set-url origin "$EVIL_ORIGIN"
  printf '%s\n' "$output"
  exit 0
fi
exec "$REAL_GIT" "$@"
ENDPOINT_GIT_SHIM
  chmod +x "$endpoint_fakebin/git"
  output=$(PATH="$endpoint_fakebin:$PATH" REAL_GIT="$REAL_GIT" BIND_REPO="$REPO" \
    EVIL_ORIGIN="$evil_origin" run_updater); rc=$?
  if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$candidate_commit" ]]; then
    pass "network operations stay bound to the endpoint captured at validation"
  else
    fail_case "network operations stay bound to the endpoint captured at validation" "rc=$rc output=$output"
  fi
}

run_issue54_retry_case() {
  local candidate_commit expected output rc dedupe_rc recovery_rc
  local reports failure_heartbeats failure_records clear_records sentinel_lines

  new_fixture issue54-reachability-retry
  write_pin v1.0.0 "$BASE_COMMIT"
  commit_release retry-candidate pass
  candidate_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$candidate_commit"
  push_tag_only v1.1.0
  expected="captured commit $candidate_commit is not on release branch origin/$BRANCH"
  output=$(run_updater); rc=$?
  run_updater >/dev/null; dedupe_rc=$?
  reports=$(grep -Fc 'updater failed: claire repo v1.1.0' "$LOGS/hot-inbox.log" 2>/dev/null || true)
  failure_heartbeats=$(grep -Fc "job-heartbeat updater-claire fail --reason $expected" \
    "$LOGS/heartbeats.log" 2>/dev/null || true)
  git -C "$SRC" push -q "$ORIGIN" "$BRANCH"
  run_updater >/dev/null; recovery_rc=$?
  failure_records=$(grep -F 'v1.1.0 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc ' verification-failure captured commit ' || true)
  clear_records=$(grep -F 'v1.1.0 ' "$(ineligible_path)" 2>/dev/null \
    | grep -Fc ' verification-failure-cleared' || true)
  sentinel_lines=0
  [[ ! -f "$SENTINEL" ]] || sentinel_lines=$(wc -l <"$SENTINEL")
  if [[ "$rc" -ne 0 && "$dedupe_rc" -ne 0 && "$recovery_rc" -eq 0 \
    && "$reports" -eq 1 && "$failure_heartbeats" -eq 1 \
    && "$failure_records" -eq 1 && "$clear_records" -eq 1 \
    && "$sentinel_lines" -eq 1 && $(git -C "$REPO" rev-parse HEAD) == "$candidate_commit" ]]; then
    pass "reachability refusal deduplicates, retries, clears, and installs after branch recovery"
  else
    fail_case "reachability refusal deduplicates, retries, clears, and installs after branch recovery" \
      "rc=$rc/$dedupe_rc/$recovery_rc reports=$reports heartbeats=$failure_heartbeats records=$failure_records clears=$clear_records installs=$sentinel_lines output=$output"
  fi
}

case "${ISSUE54_REPLAY_CASE:-all}" in
  updater)
    run_issue54_updater_replay_case
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  bootstrap)
    run_issue54_bootstrap_replay_case
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  binding)
    run_issue54_binding_cases
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  normalization)
    run_issue54_normalization_cases
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  reachability)
    run_issue54_reachability_cases
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  retry)
    run_issue54_retry_case
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
    ;;
  none)
    ;;
  all)
    run_issue54_updater_replay_case
    run_issue54_bootstrap_replay_case
    run_issue54_binding_cases
    run_issue54_normalization_cases
    run_issue54_reachability_cases
    run_issue54_retry_case
    ;;
  *)
    printf 'unknown ISSUE54_REPLAY_CASE: %s (expected updater, bootstrap, binding, normalization, reachability, retry, or none)\n' \
      "$ISSUE54_REPLAY_CASE" >&2
    exit 2
    ;;
esac

new_fixture delta4-startup-pin-dedupe
tag_release signed v1.0.0 "$BASE_COMMIT"
publish_branch_backed_release v1.0.0
fetch_local_tag v1.0.0
startup_output=
startup_rcs=
for tick in 1 2 3; do
  output=$(run_updater); rc=$?
  startup_output=${startup_output:+$startup_output$'\n'}$output
  startup_rcs="$startup_rcs $rc"
done
first_reports=$(grep -Fc 'updater failed: claire repo pin-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
first_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
first_errors=$(printf '%s\n' "$startup_output" | grep -Fc 'family-updater error: updater pin is absent and the install ledger has no usable ok entry' || true)
first_fail_ledger=$(grep -Fc ' pin-failed fail' "$(ledger_path)" 2>/dev/null || true)

write_pin v1.0.0 "$BASE_COMMIT"
recovery_output=$(run_updater); recovery_rc=$?
rm -f "$(pin_path)"
recurrence_output=$(run_updater); recurrence_rc=$?
total_reports=$(grep -Fc 'updater failed: claire repo pin-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
total_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
total_errors=$(printf '%s\n%s\n' "$startup_output" "$recurrence_output" | grep -Fc 'family-updater error: updater pin is absent and the install ledger has no usable ok entry' || true)
total_fail_ledger=$(grep -Fc ' pin-failed fail' "$(ledger_path)" 2>/dev/null || true)
failure_records=$(grep -Fc 'pin-failed ' "$(startup_failure_path)" 2>/dev/null || true)
clear_records=$(grep -F 'pin-failed ' "$(startup_failure_path)" 2>/dev/null | grep -Fc ' verification-failure-cleared' || true)
if [[ "$startup_rcs" == ' 1 1 1' && "$first_reports" -eq 1 \
  && "$first_fail_heartbeats" -eq 1 && "$first_errors" -eq 3 \
  && "$first_fail_ledger" -eq 1 && "$recovery_rc" -eq 0 \
  && "$recurrence_rc" -eq 1 && "$total_reports" -eq 2 \
  && "$total_fail_heartbeats" -eq 2 && "$total_errors" -eq 4 \
  && "$total_fail_ledger" -eq 2 && "$failure_records" -eq 3 \
  && "$clear_records" -eq 1 ]]; then
  pass "startup pin failure reports once across three ticks, clears on recovery, and reports on recurrence"
else
  fail_case "startup pin failure reports once across three ticks, clears on recovery, and reports on recurrence" \
    "rcs=[$startup_rcs]/$recovery_rc/$recurrence_rc reports=$first_reports/$total_reports heartbeats=$first_fail_heartbeats/$total_fail_heartbeats errors=$first_errors/$total_errors ledger=$first_fail_ledger/$total_fail_ledger records=$failure_records clears=$clear_records recovery=$recovery_output"
fi

new_fixture delta4-dry-run-diagnostic
commit_release installed pass
installed_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$installed_commit"
publish_branch_backed_release v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$installed_commit"
append_ok_ledger v1.0.0
ledger_before=$(cksum "$(ledger_path)")
commit_release rejected pass
tag_release unsigned v1.1.0 "$RELEASE_COMMIT"
publish_branch_backed_release v1.1.0
output=$(run_updater --dry-run); rc=$?
ledger_after=$(cksum "$(ledger_path)")
if [[ "$rc" -eq 0 && "$ledger_before" == "$ledger_after" \
  && ! -e "$(pin_path)" && ! -e "$(ineligible_path)" \
  && ! -e "$(startup_failure_path)" && ! -e "$LOGS/heartbeats.log" \
  && ! -e "$LOGS/hot-inbox.log" ]] \
  && printf '%s\n' "$output" | grep -Fq 'family-updater error: SSH signature verification failed: v1.1.0'; then
  pass "dry-run prints candidate rejection while writing and reporting nothing"
else
  fail_case "dry-run prints candidate rejection while writing and reporting nothing" \
    "rc=$rc pin=$(test -e "$(pin_path)" && echo yes || echo no) ineligible=$(test -e "$(ineligible_path)" && echo yes || echo no) startup=$(test -e "$(startup_failure_path)" && echo yes || echo no) output=$output"
fi

if [[ "${DELTA4_FOCUSED:-0}" == 1 ]]; then
  printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
  [[ "$FAIL_COUNT" -eq 0 ]]
  exit $?
fi

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
  publish_branch_backed_release "$CANDIDATE_TAG"
}

if [[ "${SKIP_DELTA2_CASES:-0}" == 0 ]]; then
  # E1: a remote-supplied high name at the installed commit is not trusted as
  # floor evidence. The machine-authored ledger supplies the installed name.
  for poison_kind in unsigned lightweight; do
    new_fixture "delta2-floor-poison-$poison_kind"
    commit_release installed pass
    installed_commit=$RELEASE_COMMIT
    tag_release signed v0.2.3 "$installed_commit"
    publish_branch_backed_release v0.2.3
    fetch_local_tag v0.2.3
    git -C "$REPO" checkout -q --detach "$installed_commit"
    append_ok_ledger v0.2.3
    tag_release "$poison_kind" v99.0.0 "$installed_commit"
    publish_branch_backed_release v99.0.0
    fetch_local_tag v99.0.0
    commit_release genuine pass
    genuine_commit=$RELEASE_COMMIT
    tag_release signed v0.3.0 "$genuine_commit"
    publish_branch_backed_release v0.3.0
    output=$(run_updater); rc=$?
    if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$genuine_commit" ]] \
      && grep -Fq '"version":"v0.3.0"' "$(pin_path)"; then
      pass "ledger floor ignores $poison_kind high tag at installed HEAD"
    else
      fail_case "ledger floor ignores $poison_kind high tag at installed HEAD" "rc=$rc head=$(git -C "$REPO" rev-parse HEAD) output=$output"
    fi
  done

  new_fixture delta2-floor-no-ledger
  tag_release lightweight v99.0.0 "$BASE_COMMIT"
  publish_branch_backed_release v99.0.0
  fetch_local_tag v99.0.0
  output=$(run_updater); rc=$?
  if [[ "$rc" -ne 0 && ! -e "$(pin_path)" ]] \
    && printf '%s\n' "$output" | grep -Fq 'scripts/updater-bootstrap'; then
    pass "floor seed without a usable ledger fails closed and names bootstrap"
  else
    fail_case "floor seed without a usable ledger fails closed and names bootstrap" "rc=$rc pin=$(test -e "$(pin_path)" && echo yes || echo no) output=$output"
  fi

  new_fixture delta2-dry-run-state
  commit_release installed pass
  installed_commit=$RELEASE_COMMIT
  tag_release signed v1.0.0 "$installed_commit"
  publish_branch_backed_release v1.0.0
  fetch_local_tag v1.0.0
  git -C "$REPO" checkout -q --detach "$installed_commit"
  append_ok_ledger v1.0.0
  ledger_before=$(cksum "$(ledger_path)")
  commit_release invalid pass
  tag_release unsigned v1.1.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.1.0
  output=$(run_updater --dry-run); rc=$?
  ledger_after=$(cksum "$(ledger_path)")
  if [[ "$rc" -eq 0 && "$ledger_before" == "$ledger_after" \
    && ! -e "$(pin_path)" && ! -e "$(ineligible_path)" \
    && ! -e "$LOGS/heartbeats.log" && ! -e "$LOGS/hot-inbox.log" ]]; then
    pass "dry-run writes no pin, dedupe, ledger, heartbeat, or hot-inbox state"
  else
    fail_case "dry-run writes no pin, dedupe, ledger, heartbeat, or hot-inbox state" \
      "rc=$rc pin=$(test -e "$(pin_path)" && echo yes || echo no) ineligible=$(test -e "$(ineligible_path)" && echo yes || echo no) output=$output"
  fi

  # CP2 v3.3: plain and rc-shaped non-semver names are outside candidate
  # selection. They are skipped locally without reporting or persistent state.
  new_fixture delta3-non-semver-skip
  write_pin v0.0.0 "$BASE_COMMIT"
  commit_release genuine pass
  genuine_commit=$RELEASE_COMMIT
  tag_release lightweight latest "$genuine_commit"
  publish_branch_backed_release latest
  tag_release lightweight v1.2.3-rc1 "$genuine_commit"
  publish_branch_backed_release v1.2.3-rc1
  tag_release signed v0.3.0 "$genuine_commit"
  publish_branch_backed_release v0.3.0
  output=$(run_updater); rc=$?
  first_head=$(git -C "$REPO" rev-parse HEAD)
  parse_rcs=$rc
  for tick in 2 3; do
    run_updater >/dev/null
    parse_rcs="$parse_rcs $?"
  done
  latest_reports=$(grep -Fc 'latest' "$LOGS/hot-inbox.log" 2>/dev/null || true)
  rc_reports=$(grep -Fc 'v1.2.3-rc1' "$LOGS/hot-inbox.log" 2>/dev/null || true)
  latest_records=$(grep -Fc 'latest' "$(ineligible_path)" 2>/dev/null || true)
  rc_records=$(grep -Fc 'v1.2.3-rc1' "$(ineligible_path)" 2>/dev/null || true)
  if [[ "$parse_rcs" == '0 0 0' && "$first_head" == "$genuine_commit" \
    && $(git -C "$REPO" rev-parse HEAD) == "$genuine_commit" \
    && "$latest_reports" -eq 0 && "$rc_reports" -eq 0 \
    && "$latest_records" -eq 0 && "$rc_records" -eq 0 ]] \
    && ! git -C "$REPO" show-ref --verify --quiet refs/tags/latest \
    && ! git -C "$REPO" show-ref --verify --quiet refs/tags/v1.2.3-rc1 \
    && printf '%s\n' "$output" | grep -Fq 'family-updater: skipping non-semver remote tag name: latest' \
    && printf '%s\n' "$output" | grep -Fq 'family-updater: skipping non-semver remote tag name: v1.2.3-rc1'; then
    pass "non-semver and rc-shaped remote names skip without reports while genuine release installs"
  else
    fail_case "non-semver and rc-shaped remote names skip without reports while genuine release installs" \
      "rcs=[$parse_rcs] first-head=$first_head head=$(git -C "$REPO" rev-parse HEAD) reports=$latest_reports/$rc_reports records=$latest_records/$rc_records output=$output"
  fi

  # A deterministic ls-remote shim injects duplicate and peeled records that
  # --refs should normally suppress. Both must remain fail-closed.
  parse_fakebin=$BASE/parse-fakebin
  mkdir -p "$parse_fakebin"
  cat >"$parse_fakebin/git" <<'PARSE_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == *" ls-remote --refs --tags "* ]]; then
  output=$($REAL_GIT "$@") || exit $?
  printf '%s\n' "$output"
  first=$(printf '%s\n' "$output" | sed -n '1p')
  if [[ "${INJECT_DUPLICATE:-0}" == 1 ]]; then
    printf '%s\n' "$first"
  elif [[ "${INJECT_PEELED:-0}" == 1 ]]; then
    oid=${first%%$'\t'*}
    ref=${first#*$'\t'}
    printf '%s\t%s^{}\n' "$oid" "$ref"
  elif [[ "${INJECT_NONSEMVER_DUP:-0}" == 1 ]]; then
    oid=${first%%$'\t'*}
    printf '%s\trefs/tags/latest\n' "$oid"
    printf '%s\trefs/tags/latest\n' "$oid"
  fi
  exit 0
fi
exec "$REAL_GIT" "$@"
PARSE_GIT_SHIM
  chmod +x "$parse_fakebin/git"
  for injection in duplicate peeled; do
    new_fixture "delta2-parse-$injection"
    write_pin v0.0.0 "$BASE_COMMIT"
    commit_release candidate pass
    tag_release signed v1.1.0 "$RELEASE_COMMIT"
    publish_branch_backed_release v1.1.0
    before=$(git -C "$REPO" rev-parse HEAD)
    parse_rcs=
    for tick in 1 2 3; do
      if [[ "$injection" == duplicate ]]; then
        output=$(PATH="$parse_fakebin:$PATH" REAL_GIT="$REAL_GIT" INJECT_DUPLICATE=1 run_updater)
      else
        output=$(PATH="$parse_fakebin:$PATH" REAL_GIT="$REAL_GIT" INJECT_PEELED=1 run_updater)
      fi
      parse_rcs="$parse_rcs $?"
    done
    if [[ "$injection" == duplicate ]]; then
      expected='duplicate remote tag name'
    else
      expected='unparsable remote tag record'
    fi
    after=$(git -C "$REPO" rev-parse HEAD)
    reports=$(grep -Fc "$expected" "$LOGS/hot-inbox.log" 2>/dev/null || true)
    if [[ "$parse_rcs" == ' 1 1 1' && "$before" == "$after" && "$reports" -eq 1 ]]; then
      pass "$injection remote tag record fails closed and reports once across three ticks"
    else
      fail_case "$injection remote tag record fails closed and reports once across three ticks" \
        "rcs=[$parse_rcs] reports=$reports output=$output"
    fi
  done

  new_fixture delta3-parse-non-semver-duplicate
  write_pin v0.0.0 "$BASE_COMMIT"
  commit_release genuine pass
  genuine_commit=$RELEASE_COMMIT
  tag_release signed v0.3.0 "$genuine_commit"
  publish_branch_backed_release v0.3.0
  output=$(PATH="$parse_fakebin:$PATH" REAL_GIT="$REAL_GIT" INJECT_NONSEMVER_DUP=1 run_updater); rc=$?
  reports=$(grep -Fc 'latest' "$LOGS/hot-inbox.log" 2>/dev/null || true)
  ineligible_records=$(grep -Fc 'latest' "$(ineligible_path)" 2>/dev/null || true)
  skip_notes=$(printf '%s\n' "$output" | grep -Fc 'family-updater: skipping non-semver remote tag name: latest' || true)
  if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$genuine_commit" \
    && "$reports" -eq 0 && "$ineligible_records" -eq 0 && "$skip_notes" -eq 2 ]]; then
    pass "duplicated non-semver records are skipped outside duplicate detection"
  else
    fail_case "duplicated non-semver records are skipped outside duplicate detection" \
      "rc=$rc head=$(git -C "$REPO" rev-parse HEAD) reports=$reports records=$ineligible_records notes=$skip_notes output=$output"
  fi

  # E3: one broken (name, commit) pair is tried once, rolled back once, and
  # then skipped without repeating checkout or reports.
  new_fixture delta2-install-failure-once
  commit_release installed pass
  installed_commit=$RELEASE_COMMIT
  tag_release signed v1.0.0 "$installed_commit"
  publish_branch_backed_release v1.0.0
  fetch_local_tag v1.0.0
  git -C "$REPO" checkout -q --detach "$installed_commit"
  write_pin v1.0.0 "$installed_commit"
  commit_release broken fail
  broken_commit=$RELEASE_COMMIT
  tag_release signed v1.1.0 "$broken_commit"
  publish_branch_backed_release v1.1.0
  install_rcs=
  for tick in 1 2 3; do
    run_updater >/dev/null
    install_rcs="$install_rcs $?"
  done
  installs=$(wc -l <"$SENTINEL" 2>/dev/null || printf '0')
  reports=$(grep -Fc 'updater failed: claire repo v1.1.0' "$LOGS/hot-inbox.log" 2>/dev/null || true)
  install_failure_records=$(awk -v commit="$broken_commit" \
    '$1 == "v1.1.0" && $3 == "install-failure" && $4 == commit {count++} END {print count+0}' \
    "$(ineligible_path)" 2>/dev/null || printf '0')
  if HOME="$HOME_DIR" bash -c \
    'source "$1"; updater_has_install_failure "$2" v1.1.0 0000000000000000000000000000000000000000' \
    _ "$ROOT/scripts/lib-updater-verify.sh" "$(ineligible_path)"; then
    different_pair_suppressed=1
  else
    different_pair_suppressed=0
  fi
  if [[ "$install_rcs" == ' 1 0 0' && "$installs" -eq 2 && "$reports" -eq 1 \
    && "$install_failure_records" -eq 1 && "$different_pair_suppressed" -eq 0 \
    && $(git -C "$REPO" rev-parse HEAD) == "$installed_commit" ]]; then
    pass "install failure reports once and exact pair causes no repeated checkout churn"
  else
    fail_case "install failure reports once and exact pair causes no repeated checkout churn" \
      "rcs=[$install_rcs] installs=$installs reports=$reports records=$install_failure_records different-pair=$different_pair_suppressed"
  fi

  # E7: fail only the second candidate refspec. A single atomic batch leaves
  # the first ref absent; a per-candidate loop would install it before failing.
  new_fixture delta2-atomic-second
  commit_release first pass
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.1.0
  commit_release second pass
  tag_release signed v1.2.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.2.0
  write_pin v1.0.0 "$BASE_COMMIT"
  atomic_fakebin=$BASE/atomic-fakebin
  atomic_counter=$BASE/atomic-counter
  mkdir -p "$atomic_fakebin"
  cat >"$atomic_fakebin/git" <<'ATOMIC_GIT_SHIM'
#!/usr/bin/env bash
set -u
if [[ "$*" == *" fetch --atomic "* ]]; then
  args=()
  for arg in "$@"; do
    if [[ "$arg" == refs/tags/*:refs/tags/* ]]; then
      count=0
      [[ ! -f "$ATOMIC_COUNTER" ]] || count=$(sed -n '1p' "$ATOMIC_COUNTER")
      count=$((count + 1))
      printf '%s\n' "$count" >"$ATOMIC_COUNTER"
      if [[ "$count" -eq 2 ]]; then
        arg='refs/tags/v404.0.0:refs/tags/v404.0.0'
      fi
    fi
    args+=("$arg")
  done
  exec "$REAL_GIT" "${args[@]}"
fi
exec "$REAL_GIT" "$@"
ATOMIC_GIT_SHIM
  chmod +x "$atomic_fakebin/git"
  output=$(PATH="$atomic_fakebin:$PATH" REAL_GIT="$REAL_GIT" ATOMIC_COUNTER="$atomic_counter" run_updater); rc=$?
  if [[ "$rc" -ne 0 ]] && ! git -C "$REPO" show-ref --verify --quiet refs/tags/v1.1.0 \
    && ! git -C "$REPO" show-ref --verify --quiet refs/tags/v1.2.0; then
    pass "second-candidate fetch failure leaves first and second tag refs absent"
  else
    fail_case "second-candidate fetch failure leaves first and second tag refs absent" "rc=$rc tags=[$(git -C "$REPO" tag | sort)] output=$output"
  fi

  if [[ "${DELTA2_FOCUSED:-0}" == 1 ]]; then
    printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
  fi
fi

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
    publish_branch_backed_release "$CANDIDATE_TAG"
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
  publish_branch_backed_release v1.1.0
  fetch_local_tag v1.1.0
  git -C "$SRC" tag -d v1.1.0 >/dev/null
  commit_release moved pass
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  force_push_tag v1.1.0
  commit_release legitimate pass
  legitimate_commit=$RELEASE_COMMIT
  tag_release signed v1.2.0 "$legitimate_commit"
  publish_branch_backed_release v1.2.0
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
  publish_branch_backed_release v1.0.0
  fetch_local_tag v1.0.0
  git -C "$REPO" checkout -q --detach "$rollback_commit"
  commit_release broken-target fail
  tag_release signed v1.1.0 "$RELEASE_COMMIT"
  publish_branch_backed_release v1.1.0
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
publish_branch_backed_release v0.2.2
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
publish_branch_backed_release v0.10.0
write_pin v0.9.0 "$BASE_COMMIT"
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$numeric_commit" ]]; then
  pass "floor comparison is numeric per semver component"
else
  fail_case "floor comparison is numeric per semver component" "rc=$rc output=$output"
fi

# Reverse numeric direction: v0.9.0 must be refused below a v0.10.0 floor.
new_fixture numeric-floor-reverse
commit_release lower-numeric pass
lower_numeric_commit=$RELEASE_COMMIT
tag_release signed v0.9.0 "$lower_numeric_commit"
publish_branch_backed_release v0.9.0
write_pin v0.10.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] \
  && printf '%s\n' "$output" | grep -Fq 'tag v0.9.0 is below installed floor v0.10.0'; then
  pass "floor comparison refuses v0.9.0 below v0.10.0"
else
  fail_case "floor comparison refuses v0.9.0 below v0.10.0" "rc=$rc output=$output"
fi

# One moved tag is excluded, reported once, and does not wedge a valid update.
new_fixture moved-continues
commit_release old-moved pass
old_moved_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$old_moved_commit"
old_moved_oid=$(git -C "$SRC" rev-parse refs/tags/v1.1.0)
publish_branch_backed_release v1.1.0
fetch_local_tag v1.1.0
git -C "$SRC" tag -d v1.1.0 >/dev/null
commit_release moved-content pass
new_moved_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$new_moved_commit"
force_push_tag v1.1.0
commit_release legitimate pass
legit_commit=$RELEASE_COMMIT
tag_release signed v1.2.0 "$legit_commit"
publish_branch_backed_release v1.2.0
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
  publish_branch_backed_release "$moved_name"
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
publish_branch_backed_release v1.3.0
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
publish_branch_backed_release v0.2.3
fetch_local_tag v0.2.3
git -C "$REPO" checkout -q --detach "$floor_commit"
write_pin v0.2.3 "$floor_commit"
commit_release rotated-key-b pass
rotated_commit=$RELEASE_COMMIT
tag_release unpinned v0.3.0 "$rotated_commit"
publish_branch_backed_release v0.3.0

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
write_allowed_signers_for_key "$KEY.pub"
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
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" FAKE_LS_REMOTE=1 run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] && printf '%s\n' "$output" | grep -Fq 'ls-remote'; then
  pass "ls-remote failure stops without checkout or install"
else
  fail_case "ls-remote failure stops without checkout or install" "rc=$rc output=$output"
fi

# Rollback uses the full pre-update OID and runs install only after asserting it.
new_fixture rollback-success
commit_release rollback-base pass
rollback_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$rollback_commit"
publish_branch_backed_release v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$rollback_commit"
commit_release broken-target fail
broken_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$broken_commit"
publish_branch_backed_release v1.1.0
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
publish_branch_backed_release v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$rollback_commit"
commit_release broken-target fail
tag_release signed v1.1.0 "$RELEASE_COMMIT"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$rollback_commit"
MISMATCH_STATE=$BASE/mismatch-count
output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" MISMATCH_REPO="$REPO" MISMATCH_STATE="$MISMATCH_STATE" run_updater); rc=$?
sentinel_lines=$(wc -l <"$SENTINEL" 2>/dev/null || printf '0')
if [[ "$rc" -ne 0 && "$sentinel_lines" -eq 1 ]] && printf '%s\n' "$output" | grep -Fq 'rollback identity mismatch'; then
  pass "rollback identity mismatch executes no rollback install.sh"
else
  fail_case "rollback identity mismatch executes no rollback install.sh" "rc=$rc lines=$sentinel_lines output=$output"
fi

# Reinstated operational coverage from the pre-CP2 suite.
new_fixture stable-soak-skip
commit_release fresh pass
fresh_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$fresh_commit" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(HOME="$HOME_DIR" UPDATER_INSTALL_SENTINEL="$SENTINEL" "$UPDATER" \
  --repo-dir "$REPO" --workspace "$WS" --agent claire --ring stable \
  --soak-hours 1 --allowed-signers "$ALLOWED" --fma-scripts-dir "$FMA" 2>&1); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -eq 0 && "$before" == "$after" && ! -e "$LOGS/hot-inbox.log" ]] \
  && printf '%s\n' "$output" | grep -Fq 'no stable tag old enough for 1 hour soak'; then
  pass "stable-ring soak skip leaves HEAD unchanged and sends no hot-inbox"
else
  fail_case "stable-ring soak skip leaves HEAD unchanged and sends no hot-inbox" "rc=$rc output=$output"
fi
output=$(HOME="$HOME_DIR" UPDATER_INSTALL_SENTINEL="$SENTINEL" "$UPDATER" \
  --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary \
  --soak-hours 999 --allowed-signers "$ALLOWED" --fma-scripts-dir "$FMA" 2>&1); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$fresh_commit" ]]; then
  pass "canary ignores soak hours"
else
  fail_case "canary ignores soak hours" "rc=$rc output=$output"
fi

new_fixture live-lock
write_pin v0.0.0 "$BASE_COMMIT"
mkdir "$REPO/.family-updater.lock"
printf '%s\n' "$$" >"$REPO/.family-updater.lock/pid"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
rm -rf "$REPO/.family-updater.lock"
if [[ "$rc" -ne 0 && "$before" == "$after" ]] \
  && grep -Fq 'lock held by live pid' "$LOGS/heartbeats.log"; then
  pass "live lock refuses the run and sends a failure heartbeat"
else
  fail_case "live lock refuses the run and sends a failure heartbeat" "rc=$rc output=$output"
fi

new_fixture stale-lock
commit_release candidate pass
stale_lock_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$stale_lock_commit"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
mkdir "$REPO/.family-updater.lock"
printf '%s\n' 999999 >"$REPO/.family-updater.lock/pid"
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$stale_lock_commit" \
  && ! -d "$REPO/.family-updater.lock" ]]; then
  pass "stale lock is reclaimed and released"
else
  fail_case "stale lock is reclaimed and released" "rc=$rc output=$output"
fi

new_fixture dirty-worktree
commit_release candidate pass
tag_release signed v1.1.0 "$RELEASE_COMMIT"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
printf 'local change\n' >>"$REPO/VERSION.fixture"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] \
  && grep -Fq 'repo has local modifications, refusing to update' "$LOGS/hot-inbox.log" \
  && grep -Fq ' v1.1.0 fail' "$(ledger_path)"; then
  pass "dirty worktree refuses checkout and records the failure"
else
  fail_case "dirty worktree refuses checkout and records the failure" "rc=$rc output=$output"
fi

new_fixture already-current
commit_release current pass
current_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$current_commit"
publish_branch_backed_release v1.1.0
fetch_local_tag v1.1.0
git -C "$REPO" checkout -q --detach "$current_commit"
write_pin v1.1.0 "$current_commit"
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && ! -e "$(ledger_path)" && ! -e "$LOGS/hot-inbox.log" ]] \
  && grep -Fq 'job-heartbeat updater-claire ok --reason v1.1.0' "$LOGS/heartbeats.log"; then
  pass "already-up-to-date sends heartbeat but skips ledger and hot-inbox"
else
  fail_case "already-up-to-date sends heartbeat but skips ledger and hot-inbox" "rc=$rc output=$output"
fi

new_fixture missing-reporter
commit_release candidate pass
missing_reporter_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$missing_reporter_commit"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
FMA=$BASE/missing-fma
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$missing_reporter_commit" ]] \
  && printf '%s\n' "$output" | grep -Fq 'warning: reporter script missing'; then
  pass "missing reporters warn while a valid update succeeds"
else
  fail_case "missing reporters warn while a valid update succeeds" "rc=$rc output=$output"
fi

new_fixture failing-reporter
commit_release candidate pass
failing_reporter_commit=$RELEASE_COMMIT
tag_release signed v1.1.0 "$failing_reporter_commit"
publish_branch_backed_release v1.1.0
write_pin v1.0.0 "$BASE_COMMIT"
cat >"$FMA/job-heartbeat" <<'FAILING_REPORTER'
#!/usr/bin/env bash
exit 1
FAILING_REPORTER
chmod +x "$FMA/job-heartbeat"
output=$(run_updater); rc=$?
if [[ "$rc" -eq 0 && $(git -C "$REPO" rev-parse HEAD) == "$failing_reporter_commit" ]] \
  && printf '%s\n' "$output" | grep -Fq 'warning: heartbeat reporter failed'; then
  pass "failing heartbeat reporter warns while a valid update succeeds"
else
  fail_case "failing heartbeat reporter warns while a valid update succeeds" "rc=$rc output=$output"
fi

new_fixture rollback-also-fails
commit_release failing-base fail
failing_base_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$failing_base_commit"
publish_branch_backed_release v1.0.0
fetch_local_tag v1.0.0
git -C "$REPO" checkout -q --detach "$failing_base_commit"
write_pin v1.0.0 "$failing_base_commit"
commit_release broken-target fail
tag_release signed v1.1.0 "$RELEASE_COMMIT"
publish_branch_backed_release v1.1.0
output=$(run_updater); rc=$?
report_lines=$(wc -l <"$LOGS/hot-inbox.log" 2>/dev/null || printf '0')
if [[ "$rc" -ne 0 && $(git -C "$REPO" rev-parse HEAD) == "$failing_base_commit" \
  && "$report_lines" -eq 1 ]] && grep -Fq 'ALSO failed its check' "$LOGS/hot-inbox.log"; then
  pass "rollback check failure produces one caution with the ALSO-failed shape"
else
  fail_case "rollback check failure produces one caution with the ALSO-failed shape" "rc=$rc reports=$report_lines output=$output"
fi

state_collision_base=$TMP_ROOT/state-key-collision
mkdir -p "$state_collision_base/one/repo" "$state_collision_base/two/repo" "$state_collision_base/home"
first_state_path=$(HOME="$state_collision_base/home" bash -c \
  'source "$1"; updater_default_pin_path "$2"' _ "$ROOT/scripts/lib-updater-verify.sh" "$state_collision_base/one/repo")
second_state_path=$(HOME="$state_collision_base/home" bash -c \
  'source "$1"; updater_default_pin_path "$2"' _ "$ROOT/scripts/lib-updater-verify.sh" "$state_collision_base/two/repo")
if [[ "$first_state_path" != "$second_state_path" \
  && $(basename "$first_state_path") == repo-*.json \
  && $(basename "$second_state_path") == repo-*.json ]]; then
  pass "same-basename clones receive distinct physical-path state keys"
else
  fail_case "same-basename clones receive distinct physical-path state keys" "$first_state_path == $second_state_path"
fi

# Bootstrap: exact owner tag only, substituted/rebound content rejected.
new_fixture bootstrap-exact
commit_release owner-initial pass
owner_commit=$RELEASE_COMMIT
tag_release signed v1.0.0 "$owner_commit"
publish_branch_backed_release v1.0.0
commit_release newer-not-selected pass
newer_commit=$RELEASE_COMMIT
tag_release signed v2.0.0 "$newer_commit"
publish_branch_backed_release v2.0.0
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
publish_branch_backed_release v1.0.0
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
publish_branch_backed_release v1.0.0
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
publish_branch_backed_release v1.0.0
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
publish_branch_backed_release v9.9.9
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
capability_output=
capability_rcs=
for tick in 1 2 3; do
  output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" FAKE_OLD_GIT=1 run_updater); rc=$?
  capability_output=${capability_output:+$capability_output$'\n'}$output
  capability_rcs="$capability_rcs $rc"
done
first_reports=$(grep -Fc 'updater failed: claire repo capability-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
first_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
first_errors=$(printf '%s\n' "$capability_output" | grep -Fc 'family-updater error: git 2.34 or newer is required' || true)
recovery_output=$(run_updater); recovery_rc=$?
recurrence_output=$(PATH="$FAKEBIN:$PATH" REAL_GIT="$REAL_GIT" FAKE_OLD_GIT=1 run_updater); recurrence_rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
total_reports=$(grep -Fc 'updater failed: claire repo capability-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
total_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
clear_records=$(grep -F 'capability-failed ' "$(startup_failure_path)" 2>/dev/null | grep -Fc ' verification-failure-cleared' || true)
if [[ "$capability_rcs" == ' 1 1 1' && "$recovery_rc" -eq 0 && "$recurrence_rc" -eq 1 \
  && "$before" == "$after" && "$first_reports" -eq 1 && "$total_reports" -eq 2 \
  && "$first_fail_heartbeats" -eq 1 && "$total_fail_heartbeats" -eq 2 \
  && "$first_errors" -eq 3 && "$clear_records" -eq 1 ]]; then
  pass "capability failure reports once, stays visible each tick, clears, and can report again"
else
  fail_case "capability failure reports once, stays visible each tick, clears, and can report again" \
    "rcs=[$capability_rcs]/$recovery_rc/$recurrence_rc reports=$first_reports/$total_reports heartbeats=$first_fail_heartbeats/$total_fail_heartbeats errors=$first_errors clears=$clear_records output=$recurrence_output"
fi

new_fixture missing-signers
write_pin v0.0.0 "$BASE_COMMIT"
missing=$BASE/does-not-exist
signers_output=
signers_rcs=
for tick in 1 2 3; do
  output=$(HOME="$HOME_DIR" "$UPDATER" --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary --allowed-signers "$missing" --fma-scripts-dir "$FMA" 2>&1); rc=$?
  signers_output=${signers_output:+$signers_output$'\n'}$output
  signers_rcs="$signers_rcs $rc"
done
first_reports=$(grep -Fc 'updater failed: claire repo signers-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
first_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
first_errors=$(printf '%s\n' "$signers_output" | grep -Fc "family-updater error: allowed_signers file is absent, unreadable, or empty: $missing" || true)
recovery_output=$(run_updater); recovery_rc=$?
recurrence_output=$(HOME="$HOME_DIR" "$UPDATER" --repo-dir "$REPO" --workspace "$WS" --agent claire --ring canary --allowed-signers "$missing" --fma-scripts-dir "$FMA" 2>&1); recurrence_rc=$?
total_reports=$(grep -Fc 'updater failed: claire repo signers-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
total_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
clear_records=$(grep -F 'signers-failed ' "$(startup_failure_path)" 2>/dev/null | grep -Fc ' verification-failure-cleared' || true)
if [[ "$signers_rcs" == ' 1 1 1' && "$recovery_rc" -eq 0 && "$recurrence_rc" -eq 1 \
  && "$first_reports" -eq 1 && "$total_reports" -eq 2 \
  && "$first_fail_heartbeats" -eq 1 && "$total_fail_heartbeats" -eq 2 \
  && "$first_errors" -eq 3 && "$clear_records" -eq 1 ]]; then
  pass "signer failure reports once, stays visible each tick, clears, and can report again"
else
  fail_case "signer failure reports once, stays visible each tick, clears, and can report again" \
    "rcs=[$signers_rcs]/$recovery_rc/$recurrence_rc reports=$first_reports/$total_reports heartbeats=$first_fail_heartbeats/$total_fail_heartbeats errors=$first_errors clears=$clear_records output=$recurrence_output"
fi

new_fixture invalid-ineligible-state
write_pin v0.0.0 "$BASE_COMMIT"
invalid_state=$(ineligible_path)
mkdir -p "$(dirname "$invalid_state")" "$invalid_state"
state_output=
state_rcs=
for tick in 1 2 3; do
  output=$(run_updater); rc=$?
  state_output=${state_output:+$state_output$'\n'}$output
  state_rcs="$state_rcs $rc"
done
first_reports=$(grep -Fc 'updater failed: claire repo state-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
first_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
first_errors=$(printf '%s\n' "$state_output" | grep -Fc "family-updater error: updater ineligible log is not a regular file: $invalid_state" || true)
rmdir "$invalid_state"
recovery_output=$(run_updater); recovery_rc=$?
mkdir "$invalid_state"
recurrence_output=$(run_updater); recurrence_rc=$?
total_reports=$(grep -Fc 'updater failed: claire repo state-failed' "$LOGS/hot-inbox.log" 2>/dev/null || true)
total_fail_heartbeats=$(grep -Fc 'job-heartbeat updater-claire fail ' "$LOGS/heartbeats.log" 2>/dev/null || true)
clear_records=$(grep -F 'state-failed ' "$(startup_failure_path)" 2>/dev/null | grep -Fc ' verification-failure-cleared' || true)
if [[ "$state_rcs" == ' 1 1 1' && "$recovery_rc" -eq 0 && "$recurrence_rc" -eq 1 \
  && "$first_reports" -eq 1 && "$total_reports" -eq 2 \
  && "$first_fail_heartbeats" -eq 1 && "$total_fail_heartbeats" -eq 2 \
  && "$first_errors" -eq 3 && "$clear_records" -eq 1 ]]; then
  pass "state failure reports once, stays visible each tick, clears, and can report again"
else
  fail_case "state failure reports once, stays visible each tick, clears, and can report again" \
    "rcs=[$state_rcs]/$recovery_rc/$recurrence_rc reports=$first_reports/$total_reports heartbeats=$first_fail_heartbeats/$total_fail_heartbeats errors=$first_errors clears=$clear_records output=$recurrence_output"
fi

new_fixture startup-dedupe-state-invalid
write_pin v0.0.0 "$BASE_COMMIT"
dedupe_path=$(startup_failure_path)
mkdir -p "$(dirname "$dedupe_path")"
ln -s "$BASE/dedupe-target" "$dedupe_path"
before=$(git -C "$REPO" rev-parse HEAD)
output=$(run_updater); rc=$?
after=$(git -C "$REPO" rev-parse HEAD)
if [[ "$rc" -ne 0 && "$before" == "$after" && ! -e "$SENTINEL" ]] \
  && printf '%s\n' "$output" | grep -Fq "updater startup failure log is not a readable, writable regular file: $dedupe_path"; then
  pass "invalid startup dedupe state fails closed before update work"
else
  fail_case "invalid startup dedupe state fails closed before update work" "rc=$rc output=$output"
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
