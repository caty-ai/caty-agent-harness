#!/usr/bin/env bash
set -euo pipefail

task_file=$1
workspace=$2
attempt_dir=$3
step_k=$4

attempt_name=$(basename "$attempt_dir")
behavior=${TR_MOCK_BEHAVIOR:-success}

if [[ -f "$workspace/mock-cases/$attempt_name" ]]; then
  behavior=$(cat "$workspace/mock-cases/$attempt_name")
elif [[ -f "$workspace/mock-behavior" ]]; then
  behavior=$(cat "$workspace/mock-behavior")
fi

artifact_dir=$(cd "$attempt_dir/../.." && pwd)
mkdir -p "$artifact_dir/out"

case "$behavior" in
  success|success-writing-step-result)
    next_hint=${TR_MOCK_NEXT_HINT-done}
    next_hint_null=${TR_MOCK_NEXT_HINT_NULL:-0}
    deviation=${TR_MOCK_DEVIATION:-}
    printf '{"task_id":"mock","step":%s}\n' "$step_k" >"$artifact_dir/out/delivery-receipt.json"
    python3 - "$attempt_dir/step-result.json" "$next_hint" "$next_hint_null" "$deviation" <<'PY'
import json, sys
_, path, next_hint, next_hint_null, deviation = sys.argv
with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "step_complete": True,
        "files_created": ["out/delivery-receipt.json"],
        "error_class": None,
        "deviation_report": deviation or None,
        "next_hint": None if next_hint_null == "1" else next_hint,
    }, f)
    f.write("\n")
PY
    ;;
  noncomplete)
    error_class=${TR_MOCK_ERROR_CLASS:-mock-error}
    if [[ -f "$workspace/mock-error-class" ]]; then
      error_class=$(cat "$workspace/mock-error-class")
    fi
    deviation=${TR_MOCK_DEVIATION:-}
    next_hint=${TR_MOCK_NEXT_HINT-retry}
    next_hint_null=${TR_MOCK_NEXT_HINT_NULL:-0}
    python3 - "$attempt_dir/step-result.json" "$error_class" "$deviation" "$next_hint" "$next_hint_null" <<'PY'
import json, sys
_, path, error_class, deviation, next_hint, next_hint_null = sys.argv
with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "step_complete": False,
        "files_created": [],
        "error_class": error_class,
        "deviation_report": deviation or None,
        "next_hint": None if next_hint_null == "1" else next_hint,
    }, f)
    f.write("\n")
PY
    ;;
  claim-missing|claim-escape|claim-absolute|claim-valid)
    next_hint=${TR_MOCK_NEXT_HINT-claimed}
    next_hint_null=${TR_MOCK_NEXT_HINT_NULL:-0}
    deviation=${TR_MOCK_DEVIATION:-}
    claim_path="out/missing.txt"
    if [[ "$behavior" = "claim-escape" ]]; then
      claim_path="../escape.txt"
    elif [[ "$behavior" = "claim-absolute" ]]; then
      claim_path="$artifact_dir/out/absolute.txt"
    elif [[ "$behavior" = "claim-valid" ]]; then
      claim_path="out/claimed.txt"
      printf 'claimed\n' >"$artifact_dir/$claim_path"
    fi
    python3 - "$attempt_dir/step-result.json" "$claim_path" "$next_hint" "$next_hint_null" "$deviation" <<'PY'
import json, sys
_, path, claim_path, next_hint, next_hint_null, deviation = sys.argv
with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "step_complete": True,
        "files_created": [claim_path],
        "error_class": None,
        "deviation_report": deviation or None,
        "next_hint": None if next_hint_null == "1" else next_hint,
    }, f)
    f.write("\n")
PY
    ;;
  receipt-symlink|receipt-directory|receipt-parent-symlink)
    printf 'claimed\n' >"$artifact_dir/out/claimed.txt"
    if [[ "$behavior" = receipt-symlink ]]; then
      printf 'outside\n' >"$artifact_dir/outside-receipt.json"
      ln -s "$artifact_dir/outside-receipt.json" "$artifact_dir/out/delivery-receipt.json"
    elif [[ "$behavior" = receipt-directory ]]; then
      mkdir -p "$artifact_dir/out/delivery-receipt.json"
      printf 'nested\n' >"$artifact_dir/out/delivery-receipt.json/value"
    else
      mkdir -p "$artifact_dir/outside"
      printf 'outside\n' >"$artifact_dir/outside/delivery-receipt.json"
      ln -s "$artifact_dir/outside" "$artifact_dir/out/link"
    fi
    python3 - "$attempt_dir/step-result.json" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({
        "step_complete": True,
        "files_created": ["out/claimed.txt"],
        "error_class": None,
        "deviation_report": None,
        "next_hint": "receipt-boundary",
    }, f)
    f.write("\n")
PY
    ;;
  hang)
    while :; do
      sleep 30
    done
    ;;
  infra)
    exit 111
    ;;
  auth-error)
    printf '401 Unauthorized\n' >&2
    exit 1
    ;;
  cli-not-logged-in)
    printf 'Not logged in · Please run /login\n'
    exit 1
    ;;
  unknown-error)
    printf 'unexpected upstream failure xyz123\n' >&2
    exit 1
    ;;
  empty-error)
    exit 1
    ;;
  no-result|no-step-result)
    exit 0
    ;;
  bad-json-result)
    printf '[]\n' >"$attempt_dir/step-result.json"
    exit 0
    ;;
  *)
    printf 'unknown mock behavior: %s\n' "$behavior" >&2
    exit 2
    ;;
esac
