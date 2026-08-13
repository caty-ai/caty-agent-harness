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
if ((provider_status != 0)); then
  printf 'provider exited %s\n' "$provider_status" >&2
  exit 70
fi

verdict_line=$(sed -n '1p' "$provider_output")
reason_line=$(sed -n '2p' "$provider_output")
case "$verdict_line" in
  'VERDICT: pass'|'VERDICT: fail'|'VERDICT: inconclusive'|'VERDICT: rubric-invalid'|'VERDICT: needs-human'|'VERDICT: blocked-missing-artifact') ;;
  *) exit 65 ;;
esac
[[ -n "${reason_line//[[:space:]]/}" ]] || exit 65
if tail -n +2 "$provider_output" | grep -Fq 'VERDICT:'; then
  exit 65
fi

printf '%s\n%s\n' "$verdict_line" "$reason_line"
