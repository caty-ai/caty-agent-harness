#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

fail=0

pass() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  fail=1
}

require_file() {
  if [ ! -f "$1" ]; then
    fail_check "$2" "missing file $1"
    return 1
  fi
  return 0
}

check_contains_many() {
  local id reason file pattern
  id=$1
  reason=$2
  file=$3
  shift 3
  require_file "$file" "$id" || return
  for pattern in "$@"; do
    if ! grep -Fq -- "$pattern" "$file"; then
      fail_check "$id" "missing pattern [$pattern] in $file"
      return
    fi
  done
  pass "$id" "$reason"
}

check_contains() {
  check_contains_many "$1" "$2" "$3" "$4"
}

check_absent_many() {
  local id reason file pattern
  id=$1
  reason=$2
  file=$3
  shift 3
  require_file "$file" "$id" || return
  for pattern in "$@"; do
    if grep -Fq -- "$pattern" "$file"; then
      fail_check "$id" "forbidden pattern [$pattern] present in $file"
      return
    fi
  done
  pass "$id" "$reason"
}

check_contains a01 "agent guide states the repository is public" \
  "docs/agent-guide.md" 'This repository is public at <https://github.com/caty-ai/caty-agent-harness>'
check_contains a02 "agent guide states that no invitation is needed" \
  "docs/agent-guide.md" 'no invitation is needed'
check_absent_many a03 "agent guide drops the forthcoming-public-home note" \
  "docs/agent-guide.md" 'The public home will be'
check_contains a04 "hermes install says to clone the public repository" \
  "adapters/hermes/INSTALL.md" 'Clone the public repository into a stable local path.'
check_contains a05 "hermes install includes the public clone command" \
  "adapters/hermes/INSTALL.md" 'git clone https://github.com/caty-ai/caty-agent-harness.git'
check_absent_many a06 "hermes install drops the old private-repository text" \
  "adapters/hermes/INSTALL.md" 'Clone this private repository into a stable local path.'
check_absent_many a07 "hermes install drops the old invitation-or-deploy-key access text" \
  "adapters/hermes/INSTALL.md" 'Access is by repo invite or deploy key.'
check_contains a08 "openclaw install says to clone the public repository" \
  "adapters/openclaw/INSTALL.md" 'Clone the public repository into a stable local path.'
check_contains a09 "openclaw install includes the public clone command" \
  "adapters/openclaw/INSTALL.md" 'git clone https://github.com/caty-ai/caty-agent-harness.git'
check_absent_many a10 "openclaw install drops the old private-repository text" \
  "adapters/openclaw/INSTALL.md" 'Clone this private repository into a stable local path.'
check_absent_many a11 "openclaw install drops the old invitation-or-deploy-key access text" \
  "adapters/openclaw/INSTALL.md" 'Access is by repo invite or deploy key.'
check_absent_many a12 "agent guide drops the old clone-auth troubleshooting row" \
  "docs/agent-guide.md" "Clone fails with auth error | Repo is private and this account isn't invited"
check_contains a13 "claude adapter includes the self-contained macOS scheduling explanation" \
  "adapters/claude-code/INSTALL.md" 'The Phase-1 pilot on 2026-07-19 therefore adopted'
check_contains a14 "claude adapter includes the self-contained host-hook explanation" \
  "adapters/claude-code/INSTALL.md" 'The Phase-1 pilot on 2026-07-19 established the need to'
check_absent_many a15 "claude adapter drops the old tracker-number citation" \
  "adapters/claude-code/INSTALL.md" '#43'
check_contains a16 "design document labels itself as a historical design record" \
  "DESIGN.md" 'Historical design record.'
check_contains a17 "design document says its legacy issue references point to the pre-publication private tracker" \
  "DESIGN.md" 'pre-publication private tracker'
check_contains a18 "task-runner design document labels itself as a historical design record" \
  "DESIGN-task-runner.md" 'Historical design record.'
check_contains a19 "task-runner design document says its legacy issue references point to the pre-publication private tracker" \
  "DESIGN-task-runner.md" 'pre-publication private tracker'
check_contains a20 "governance rules labels itself as a historical design record" \
  "docs/governance-rules.md" 'Historical design record.'
check_contains a21 "governance rules says its legacy references point to the pre-publication private trackers and working repositories" \
  "docs/governance-rules.md" 'pre-publication private trackers and working repositories'
check_contains a22 "updater rollout labels itself as a historical design record" \
  "docs/updater-rollout.md" 'Historical design record.'
check_contains a23 "updater rollout uses the placeholder deployment-inventory heading" \
  "docs/updater-rollout.md" '## Deployment inventory example'
check_contains a24 "updater rollout uses the placeholder deployment-inventory row" \
  "docs/updater-rollout.md" '| `<agent>` | `<host>` | `<cron-or-launchd schedule>` | `/path/to/caty-agent-harness` | `<host>-updater-ro` |'
check_absent_many a25 "updater rollout drops the old verified-deployments heading" \
  "docs/updater-rollout.md" '## Verified deployments — actual paths'
check_absent_many a26 "updater rollout drops the old concrete deployment row" \
  "docs/updater-rollout.md" '| Claire (canary) | VPS | cron `:17` | `/path/to/clones/caty-agent-harness` | read-only deploy key |'

if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
