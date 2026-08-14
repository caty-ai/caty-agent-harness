#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

ALLOWLIST_PATH='.ev005-fixtures/release-model-allowlist.tsv'
failures=0
tmp_filelist=''
tmp_raw=''
tmp_residual=''

ALLOW_SCOPE_EN='Caty Agent Harness is the vertical axis in Family OS, the maintainers'\'' multi-agent environment: it strengthens an individual agent'\''s ability to learn across work and finish multi-step work. Family Memory Architecture (FMA) is the horizontal axis: it coordinates memory, schedules, and provenance across agents. The two roles are orthogonal, not competing. (Family OS and FMA live in private repositories; their names appear here only to explain this project'\''s scope boundary.)'
ALLOW_SCOPE_JA='Caty Agent Harness は、maintainer たちのマルチエージェント環境 Family OS の縦軸です。個々の agent が仕事をまたいで学び、複数 step の仕事を完走する力を強くします。Family Memory Architecture（FMA）は横軸で、複数 agent 間の memory、schedule、provenance をつなぎます。役割は直交しており、競合しません。（Family OS と FMA は private repository にあり、名前はこのプロジェクトの範囲の境界を説明するためだけに登場します。）'
ALLOW_STATUS_EN='- This is the public Caty AI release repository. Development happens in a private working repository; releases land here as clean snapshots.'
ALLOW_STATUS_JA='- ここは Caty AI の public release repository です。開発は private の作業リポジトリで行い、リリースはクリーンなスナップショットとしてここに置かれます。'

cleanup() {
  [ -n "$tmp_filelist" ] && [ -f "$tmp_filelist" ] && rm -f "$tmp_filelist"
  [ -n "$tmp_raw" ] && [ -f "$tmp_raw" ] && rm -f "$tmp_raw"
  [ -n "$tmp_residual" ] && [ -f "$tmp_residual" ] && rm -f "$tmp_residual"
}

trap cleanup EXIT HUP INT TERM

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

require_file() {
  if [ ! -f "$1" ]; then
    fail_check "$2" "missing file $1"
    return 1
  fi
  return 0
}

check_contains() {
  local id file needle reason
  id=$1
  file=$2
  needle=$3
  reason=$4
  require_file "$file" "$id" || return
  if grep -Fq -- "$needle" "$file"; then
    pass_check "$id" "$reason"
  else
    fail_check "$id" "missing pattern [$needle] in $file"
  fi
}

check_contains_all() {
  local id file reason needle
  id=$1
  file=$2
  reason=$3
  shift 3
  require_file "$file" "$id" || return
  for needle in "$@"; do
    if ! grep -Fq -- "$needle" "$file"; then
      fail_check "$id" "missing pattern [$needle] in $file"
      return
    fi
  done
  pass_check "$id" "$reason"
}

check_absent() {
  local id file needle reason
  id=$1
  file=$2
  needle=$3
  reason=$4
  require_file "$file" "$id" || return
  if grep -Fq -- "$needle" "$file"; then
    fail_check "$id" "forbidden pattern [$needle] present in $file"
  else
    pass_check "$id" "$reason"
  fi
}

check_regex_absent() {
  local id file regex reason
  id=$1
  file=$2
  regex=$3
  reason=$4
  require_file "$file" "$id" || return
  if grep -Eq -- "$regex" "$file"; then
    fail_check "$id" "forbidden regex [$regex] matched in $file"
  else
    pass_check "$id" "$reason"
  fi
}

is_user_markdown() {
  return 0
}

is_historical_exclusion() {
  case "$1" in
    DESIGN.md|DESIGN-task-runner.md|docs/governance-rules.md|docs/updater-rollout.md) return 0 ;;
    *) return 1 ;;
  esac
}

build_user_markdown_list() {
  local path
  if [ -n "$tmp_filelist" ] && [ -f "$tmp_filelist" ] && [ -s "$tmp_filelist" ]; then
    return 0
  fi
  [ -n "$tmp_filelist" ] && [ -f "$tmp_filelist" ] && rm -f "$tmp_filelist"
  tmp_filelist=$(mktemp "${TMPDIR:-/tmp}/t06-files.XXXXXX") || return 1
  : >"$tmp_filelist"
  git ls-files '*.md' | while IFS= read -r path; do
    is_user_markdown "$path" || continue
    is_historical_exclusion "$path" && continue
    case "$path" in
      tests/fixtures/*) continue ;;
    esac
    printf '%s\n' "$path"
  done >"$tmp_filelist"
  [ -s "$tmp_filelist" ]
}

check_allowlist_line_count() {
  local count
  [ -f "$ALLOWLIST_PATH" ] || return 1
  count=$(grep -Ec '^[^#[:space:]]' "$ALLOWLIST_PATH") || return 1
  [ "$count" -eq 4 ]
}

allowlist_has_exact_entry() {
  local path exact_line tab raw
  path=$1
  exact_line=$2
  tab=$(printf '\t')
  raw=$path$tab$exact_line
  grep -Fqx -- "$raw" "$ALLOWLIST_PATH"
}

file_has_exact_line() {
  local path exact_line
  path=$1
  exact_line=$2
  [ -f "$path" ] || return 1
  grep -Fqx -- "$exact_line" "$path"
}

check_allowlist_exact_entry() {
  local id path exact_line reason
  id=$1
  path=$2
  exact_line=$3
  reason=$4
  require_file "$ALLOWLIST_PATH" "$id" || return
  require_file "$path" "$id" || return
  if ! allowlist_has_exact_entry "$path" "$exact_line"; then
    fail_check "$id" "allowlist is missing exact entry for $path"
    return
  fi
  if ! file_has_exact_line "$path" "$exact_line"; then
    fail_check "$id" "named file does not contain allowlisted exact line in $path"
    return
  fi
  pass_check "$id" "$reason"
}

line_allowed() {
  local path content allow_path allow_content allow_note tab
  path=$1
  content=$2
  tab=$(printf '\t')
  [ -f "$ALLOWLIST_PATH" ] || return 1
  while IFS="$tab" read -r allow_path allow_content allow_note; do
    case "$allow_path" in
      ''|'#'*) continue ;;
    esac
    if [ "$path" = "$allow_path" ] && [ "$content" = "$allow_content" ]; then
      return 0
    fi
  done <"$ALLOWLIST_PATH"
  return 1
}

check_surface_absent() {
  local id regex reason file rc line path rest content
  id=$1
  regex=$2
  reason=$3
  require_file "$ALLOWLIST_PATH" "$id" || return
  build_user_markdown_list || {
    fail_check "$id" "could not enumerate tracked user-facing markdown"
    return
  }
  tmp_raw=$(mktemp "${TMPDIR:-/tmp}/t06-raw.XXXXXX") || {
    fail_check "$id" "could not create temp file"
    return
  }
  tmp_residual=$(mktemp "${TMPDIR:-/tmp}/t06-residual.XXXXXX") || {
    fail_check "$id" "could not create temp file"
    rm -f "$tmp_raw"
    tmp_raw=''
    return
  }
  : >"$tmp_raw"
  : >"$tmp_residual"
  while IFS= read -r file; do
    if [ ! -f "$file" ]; then
      fail_check "$id" "missing file $file"
      rm -f "$tmp_raw" "$tmp_residual"
      tmp_raw=''
      tmp_residual=''
      return
    fi
    grep -HniE -- "$regex" "$file" >>"$tmp_raw"
    rc=$?
    if [ "$rc" -gt 1 ]; then
      fail_check "$id" "grep failed for $file"
      rm -f "$tmp_raw" "$tmp_residual"
      tmp_raw=''
      tmp_residual=''
      return
    fi
  done <"$tmp_filelist"
  while IFS= read -r line; do
    path=${line%%:*}
    rest=${line#*:}
    content=${rest#*:}
    if line_allowed "$path" "$content"; then
      continue
    fi
    printf '%s\n' "$line" >>"$tmp_residual"
  done <"$tmp_raw"
  if [ ! -s "$tmp_residual" ]; then
    pass_check "$id" "$reason"
  else
    fail_check "$id" "$reason"
  fi
  rm -f "$tmp_raw" "$tmp_residual"
  tmp_raw=''
  tmp_residual=''
}

check_updater_inventory_genericized() {
  local file
  file='docs/updater-rollout.md'
  awk '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }
    function placeholder_cell(s,    t) {
      t = trim(s)
      return t ~ /^`<[^>]+>(-[A-Za-z0-9_-]+)?`$/
    }
    function path_cell(s,    t) {
      t = trim(s)
      return t ~ /^`\/path\/to\/[^`|]+`$/
    }
    BEGIN {
      in_inventory = 0
      seen_header = 0
      row_count = 0
    }
    /Deployment inventory/ {
      in_inventory = 1
    }
    in_inventory && /^\| Agent \| Host \| Trigger \| Deploy clone \| Credential \|$/ {
      seen_header = 1
      next
    }
    in_inventory && seen_header && /^\| --- \| --- \| --- \| --- \| --- \|$/ {
      next
    }
    in_inventory && seen_header && /^\|/ {
      n = split($0, cells, /\|/)
      if (n != 7) {
        exit 1
      }
      if (!placeholder_cell(cells[2]) || !placeholder_cell(cells[3]) || !placeholder_cell(cells[4]) || !path_cell(cells[5]) || !placeholder_cell(cells[6])) {
        exit 1
      }
      row_count++
      next
    }
    in_inventory && seen_header && !/^\|/ {
      exit (row_count > 0 ? 0 : 1)
    }
    END {
      if (!in_inventory || !seen_header || row_count == 0) {
        exit 1
      }
    }
  ' "$file"
}

check_updater_inventory_dated() {
  local file
  file='docs/updater-rollout.md'
  awk '
    BEGIN {
      in_inventory = 0
      found = 0
    }
    /Deployment inventory/ {
      in_inventory = 1
    }
    in_inventory && /^## / && $0 !~ /Deployment inventory/ {
      exit(found ? 0 : 1)
    }
    in_inventory && /dated internal record|historical record|dated record/ {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$file"
}

check_updater_inventory_disjunction() {
  check_updater_inventory_genericized || check_updater_inventory_dated
}

check_agent_guide_troubleshooting_shape() {
  awk '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      in_table = 0
      row_count = 0
      ok = 0
    }
    /^## Troubleshooting$/ {
      in_table = 1
      next
    }
    in_table && row_count == 0 && /^[[:space:]]*$/ {
      next
    }
    in_table && /^\|/ {
      if ($0 ~ /^\| --- / || $0 ~ /^\| Symptom \| Meaning \| Do \|$/) {
        next
      }
      row_count++
      n = split($0, cells, /\|/)
      if (n != 5) {
        exit 1
      }
      symptom = trim(cells[2])
      meaning = trim(cells[3])
      if (meaning !~ /^—$/ && symptom !~ /`[^`]+`/) {
        exit 1
      }
      next
    }
    in_table && !/^\|/ {
      if (row_count == 0) {
        exit 1
      }
      ok = 1
      exit 0
    }
    END {
      if (ok) {
        exit 0
      }
      if (!in_table || row_count == 0) {
        exit 1
      }
      exit 1
    }
  ' docs/agent-guide.md
}

check_contains_all "a01" "docs/agent-guide.md" "agent guide states that the repository is public with the public repo identifier" "repository is public" "caty-ai/caty-agent-harness"
check_contains "a02" "docs/agent-guide.md" "no invitation is needed" "agent guide states that no invitation is needed"
check_absent "a03" "docs/agent-guide.md" "private repo or a network problem" "agent guide drops the old missing-access diagnosis"
check_absent "a04" "docs/agent-guide.md" "public home will be" "agent guide drops the transitional forthcoming-home note"

check_contains "a05" "adapters/hermes/INSTALL.md" "Clone the public repository" "hermes install uses the public clone flow"
check_contains "a06" "adapters/hermes/INSTALL.md" "git clone https://github.com/caty-ai/caty-agent-harness.git" "hermes install includes the public clone command"
check_absent "a07" "adapters/hermes/INSTALL.md" "private repository" "hermes install drops the old private-repository wording"
check_absent "a08" "adapters/hermes/INSTALL.md" "repo invite or deploy key" "hermes install drops the invite-or-deploy-key wording"

check_contains "a09" "adapters/openclaw/INSTALL.md" "Clone the public repository" "openclaw install uses the public clone flow"
check_contains "a10" "adapters/openclaw/INSTALL.md" "git clone https://github.com/caty-ai/caty-agent-harness.git" "openclaw install includes the public clone command"
check_absent "a11" "adapters/openclaw/INSTALL.md" "private repository" "openclaw install drops the old private-repository wording"
check_absent "a12" "adapters/openclaw/INSTALL.md" "repo invite or deploy key" "openclaw install drops the invite-or-deploy-key wording"

check_contains_all "a13" "adapters/claude-code/INSTALL.md" "claude adapter explains the macOS scheduler constraint with small behavioral fragments" "Keychain" "LaunchAgent"
check_contains_all "a14" "adapters/claude-code/INSTALL.md" "claude adapter explains the hook-isolation failure mode with small behavioral fragments" "PreToolUse" "isolate" "hooks"
check_regex_absent "a15" "adapters/claude-code/INSTALL.md" '#[[:digit:]]+' "claude adapter drops numbered citations from those explanations"

check_contains "a16" "DESIGN.md" "Historical design record." "design document is explicitly labeled historical"
check_contains "a17" "DESIGN-task-runner.md" "Historical design record." "task-runner design document is explicitly labeled historical"
check_contains "a18" "docs/governance-rules.md" "Historical design record." "governance rules are explicitly labeled historical"
check_contains "a19" "docs/updater-rollout.md" "Historical design record." "updater rollout is explicitly labeled historical"

if check_updater_inventory_disjunction; then
  pass_check "a20" "updater rollout satisfies the genericized-or-dated inventory disjunction"
else
  fail_check "a20" "updater rollout does not satisfy the genericized-or-dated inventory disjunction"
fi
build_user_markdown_list || {
  fail_check "a21" "could not enumerate tracked user-facing markdown"
}
if [ -n "$tmp_filelist" ] && grep -Fxq -- "docs/plugin-convention.md" "$tmp_filelist"; then
  pass_check "a21" "plugin convention is included in the repo-wide public policy sweep"
else
  fail_check "a21" "plugin convention is missing from the repo-wide public policy sweep"
fi

if check_allowlist_line_count; then
  pass_check "a22" "allowlist contains exactly four recorded exception lines"
else
  fail_check "a22" "allowlist does not contain exactly four recorded exception lines"
fi
check_allowlist_exact_entry "a23" "docs/engineering.md" "$ALLOW_SCOPE_EN" "allowlist records the english scope-boundary exception exactly"
check_allowlist_exact_entry "a24" "docs/engineering.ja.md" "$ALLOW_SCOPE_JA" "allowlist records the japanese scope-boundary exception exactly"
check_allowlist_exact_entry "a25" "docs/engineering.md" "$ALLOW_STATUS_EN" "allowlist records the english release-status exception exactly"
check_allowlist_exact_entry "a26" "docs/engineering.ja.md" "$ALLOW_STATUS_JA" "allowlist records the japanese release-status exception exactly"

check_surface_absent "a27" 'private[[:space:]-]+repo([^[:alpha:]]|$)|private([[:space:]-]+working)?[[:space:]-]+repositor(y|ies)|private の作業リポジトリ' "no private-access wording remains outside the recorded allowlist"
check_surface_absent "a28" 'repo invite|deploy key' "no invite-or-deploy-key onboarding wording remains outside the recorded allowlist"
check_surface_absent "a29" 'private[[:space:]-]+issue(s)?|private[[:space:]-]+tracker(s)?|public home will be' "no private citation framing or forthcoming-home note remains outside the recorded allowlist"

if check_agent_guide_troubleshooting_shape; then
  pass_check "a30" "agent-guide troubleshooting rows with non-dash meanings carry observed-literal symptom cells"
else
  fail_check "a30" "agent-guide troubleshooting table is missing observed-literal symptom cells"
fi

[ "$failures" -eq 0 ]
