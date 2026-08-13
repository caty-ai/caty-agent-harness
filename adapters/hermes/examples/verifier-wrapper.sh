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
cleanup() {
  rm -f "$provider_output"
}
trap cleanup EXIT HUP INT TERM

set +e
"$FABLE_CONFORMING_PROVIDER_PATH" "$bundle" >"$provider_output"
provider_status=$?
set -e
((provider_status == 0)) || exit "$provider_status"

verdict_lines=$(awk '/^VERDICT:/ {count++} END {print count + 0}' "$provider_output")
((verdict_lines == 1)) || exit 65
case "$(sed -n '1p' "$provider_output")" in
  'VERDICT: pass'|'VERDICT: fail'|'VERDICT: needs-human') ;;
  *) exit 65 ;;
esac

cat "$provider_output"
