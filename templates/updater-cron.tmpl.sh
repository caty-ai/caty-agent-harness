#!/usr/bin/env bash
set -euo pipefail

# Caty Agent Harness updater cron wrapper template v3
#
# Copy this file next to a checked-out harness clone, set REPO_DIR to the
# absolute clone path, and run it from cron. It validates wrapper-level
# assumptions before execing the clone's scripts/family-updater.
# Optional CATY_WRAPPER_EXTRA_PATH appends absolute directories to the pinned
# system PATH for user-local CLI installs on Linux/WSL2. Appending prevents those
# directories from shadowing system tools.
#
# CATY_UPDATER_RELEASE_BRANCH selects the branch every update must be reachable
# from (default: main). It is not validated here; it passes through exec to
# family-updater. Set it in the crontab environment when this deployment's
# release branch is not main, or every tick refuses with an unavailable
# release ref.

fail() {
  printf 'updater-cron infra error: %s\n' "$1" >&2
  exit 3
}

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
if [[ -n "${CATY_WRAPPER_EXTRA_PATH:-}" ]]; then
  extra_path_remainder=$CATY_WRAPPER_EXTRA_PATH
  while :; do
    case "$extra_path_remainder" in
      *:*)
        extra_path_entry=${extra_path_remainder%%:*}
        extra_path_remainder=${extra_path_remainder#*:}
        extra_path_has_more=1
        ;;
      *)
        extra_path_entry=$extra_path_remainder
        extra_path_remainder=
        extra_path_has_more=0
        ;;
    esac
    if [[ -z "$extra_path_entry" || "$extra_path_entry" != /* ]]; then
      fail "CATY_WRAPPER_EXTRA_PATH entry must be non-empty and absolute: '$extra_path_entry'"
    fi
    if (( extra_path_has_more == 0 )); then
      break
    fi
  done
  PATH="$PATH:$CATY_WRAPPER_EXTRA_PATH"
fi
export PATH

REPO_DIR=${REPO_DIR:-/absolute/path/to/caty-agent-harness}
WORKSPACE=${WORKSPACE:-$PWD}
AGENT=${AGENT:-${USER:-unknown}}
RING=${RING:-stable}
SOAK_HOURS=${SOAK_HOURS:-24}
ALLOWED_SIGNERS=${CATY_UPDATER_ALLOWED_SIGNERS:-$HOME/.claude/state/updater-allowed-signers}

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

repo_real=$(cd "$REPO_DIR" && pwd -P)
repo_name=$(basename "$repo_real")
repo_hash=$(printf '%s' "$repo_real" | git hash-object --stdin) || fail "cannot hash physical REPO_DIR path"
repo_state_key="$repo_name-${repo_hash:0:12}"
pin_path="$HOME/.claude/state/updater-pin/$repo_state_key.json"
if [[ ! -r "$pin_path" ]]; then
  fail "verified updater pin is missing; run scripts/updater-bootstrap before enabling this wrapper: $pin_path"
fi
if [[ ! -r "$ALLOWED_SIGNERS" || ! -s "$ALLOWED_SIGNERS" ]]; then
  fail "allowed_signers file is absent, unreadable, or empty: $ALLOWED_SIGNERS"
fi

exec "$REPO_DIR/scripts/family-updater" \
  --repo-dir "$REPO_DIR" \
  --workspace "$WORKSPACE" \
  --agent "$AGENT" \
  --ring "$RING" \
  --soak-hours "$SOAK_HOURS" \
  --allowed-signers "$ALLOWED_SIGNERS" \
  --fma-scripts-dir "$FMA_SCRIPTS_DIR"
