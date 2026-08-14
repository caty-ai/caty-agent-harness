#!/usr/bin/env bash
set -euo pipefail

bundle=${1:-}
min_bytes=${VERIFIER_BUNDLE_MIN_BYTES:-200}

[[ $# -eq 1 && -n "$bundle" ]] || exit 64
if [[ ! "$min_bytes" =~ ^[1-9][0-9]{0,6}$ || "$min_bytes" -gt 1048576 ]]; then
  exit 64
fi
bundle_bytes=$(LC_ALL=C printf '%s' "$bundle" | wc -c | tr -d '[:space:]')
[[ "$bundle_bytes" =~ ^[0-9]+$ && "$bundle_bytes" -ge "$min_bytes" ]] || exit 64

[[ "${FABLE_CONFORMING_PROVIDER_PATH:-}" == /* \
  && -f "$FABLE_CONFORMING_PROVIDER_PATH" \
  && ! -L "$FABLE_CONFORMING_PROVIDER_PATH" \
  && -x "$FABLE_CONFORMING_PROVIDER_PATH" ]] || exit 69

provider_output=$(mktemp "${TMPDIR:-/tmp}/caty-verifier-output.XXXXXX")
validated_output=$(mktemp "${TMPDIR:-/tmp}/caty-verifier-validated.XXXXXX")
cleanup() {
  rm -f "$provider_output" "$validated_output"
}
trap cleanup EXIT HUP INT TERM

set +e
"$FABLE_CONFORMING_PROVIDER_PATH" "$bundle" >"$provider_output"
provider_status=$?
set -e
if ((provider_status != 0)); then
  printf 'provider exited %s\n' "$provider_status" >&2
  exit 70
fi

if ! LC_ALL=C awk '
  function count_exact(haystack, needle, count, position) {
    count = 0
    while ((position = index(haystack, needle)) != 0) {
      count++
      haystack = substr(haystack, position + length(needle))
    }
    return count
  }
  {
    sub(/\r$/, "")
    sub(/[[:space:]]+$/, "")
    lines[NR] = $0
    marker_count += count_exact($0, "VERDICT:")
    if ($0 ~ /^VERDICT: (pass|fail|inconclusive|rubric-invalid|needs-human|blocked-missing-artifact)$/) {
      anchor_count++
      verdict_number = NR
      verdict = $0
    }
  }
  END {
    if (marker_count != 1 || anchor_count != 1) {
      exit 1
    }
    for (line = verdict_number + 1; line <= NR; line++) {
      if (lines[line] != "") {
        print verdict
        print lines[line]
        exit 0
      }
    }
    exit 1
  }
' "$provider_output" >"$validated_output"; then
  exit 65
fi

cat "$validated_output"
