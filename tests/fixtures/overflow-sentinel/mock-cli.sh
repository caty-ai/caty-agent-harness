#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${MOCK_STDIN_PATH:-}" ]]; then
  cat >"$MOCK_STDIN_PATH"
else
  cat >/dev/null
fi
if [[ -n "${MOCK_CWD_PATH:-}" ]]; then
  pwd >"$MOCK_CWD_PATH"
fi
if [[ -n "${MOCK_ENV_PATH:-}" ]]; then
  printf '%s' "${MOCK_MARKER:-}" >"$MOCK_ENV_PATH"
fi
printf '%s\n' "${MOCK_STDERR:-mock stderr}" >&2
if [[ -n "${MOCK_STREAM_FILE:-}" ]]; then
  cat "$MOCK_STREAM_FILE"
else
  printf '%s' "${MOCK_STDOUT:-mock stdout}"
fi
if [[ -n "${MOCK_STEP_RESULT:-}" ]]; then
  printf '%s\n' "$MOCK_STEP_RESULT" >"$ATTEMPT_DIR/step-result.json"
fi
if [[ -n "${MOCK_SLEEP_S:-}" ]]; then
  sleep "$MOCK_SLEEP_S"
fi
if [[ -n "${MOCK_ALIVE_PATH:-}" ]]; then
  printf 'alive\n' >"$MOCK_ALIVE_PATH"
fi
exit "${MOCK_EXIT:-0}"
