#!/usr/bin/env bash
set -euo pipefail

# Caty Agent Harness updater cron wrapper template v1
#
# Copy this file next to a checked-out harness clone, set REPO_DIR to the
# absolute clone path, and run it from cron. It validates wrapper-level
# assumptions before execing the clone's scripts/family-updater.

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

fail() {
  printf 'updater-cron infra error: %s\n' "$1" >&2
  exit 3
}

REPO_DIR=${REPO_DIR:-/absolute/path/to/caty-agent-harness}
WORKSPACE=${WORKSPACE:-$PWD}
AGENT=${AGENT:-${USER:-unknown}}
RING=${RING:-stable}
SOAK_HOURS=${SOAK_HOURS:-24}

if [[ -z "${FMA_SCRIPTS_DIR:-}" ]]; then
  fail "FMA_SCRIPTS_DIR is not set; set it to the reporter directory (for example, /path/to/family-memory-architecture/scripts)"
fi

if [[ "$REPO_DIR" != /* ]]; then
  fail "REPO_DIR must be an absolute path: $REPO_DIR"
fi
if [[ ! -d "$REPO_DIR/.git" ]]; then
  fail "REPO_DIR is not a git clone: $REPO_DIR"
fi
if [[ ! -x "$REPO_DIR/scripts/family-updater" ]]; then
  fail "family-updater is not executable: $REPO_DIR/scripts/family-updater"
fi

exec "$REPO_DIR/scripts/family-updater" \
  --repo-dir "$REPO_DIR" \
  --workspace "$WORKSPACE" \
  --agent "$AGENT" \
  --ring "$RING" \
  --soak-hours "$SOAK_HOURS" \
  --fma-scripts-dir "$FMA_SCRIPTS_DIR"
