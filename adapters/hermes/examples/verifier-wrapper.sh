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

if ! python3 - "$provider_output" >"$validated_output" <<'PY'
import re
import sys
import unicodedata

path = sys.argv[1]
allowed = {
    "pass",
    "fail",
    "inconclusive",
    "rubric-invalid",
    "needs-human",
    "blocked-missing-artifact",
}
verdict_re = re.compile(r"^VERDICT: ([a-z-]+)$")
marker_re = re.compile(r"VERDICT\s*:")


def sanitize_reason(line: str) -> str:
    return re.sub(r"[\x01-\x08\x0b-\x1f\x7f]", "", line).rstrip("\r\t\v\f ")


def reason_is_empty(line: str) -> bool:
    scratch = line.encode("utf-8")
    for empty_bytes in (
        b" ",
        b"\t",
        b"\v",
        b"\f",
        b"\r",
        b"\xc2\xa0",
        b"\xe3\x80\x80",
        b"\xe2\x80\x8b",
    ):
        scratch = scratch.replace(empty_bytes, b"")
    return scratch == b""


try:
    raw = open(path, "rb").read()
except OSError:
    raise SystemExit(1)

if b"\x00" in raw:
    raise SystemExit(1)

try:
    text = raw.decode("utf-8")
except UnicodeDecodeError:
    raise SystemExit(1)

raw_lines = text.split("\n")
normalized_lines = [
    unicodedata.normalize("NFKC", line.replace("\r", "")) for line in raw_lines
]
marker_count = sum(len(marker_re.findall(line)) for line in normalized_lines)
if marker_count != 1 or not normalized_lines:
    raise SystemExit(1)

match = verdict_re.fullmatch(normalized_lines[0])
if match is None or match.group(1) not in allowed:
    raise SystemExit(1)

if len(raw_lines) < 2:
    raise SystemExit(1)
reason = sanitize_reason(raw_lines[1].replace("\r", ""))
if reason == "" or reason_is_empty(reason):
    raise SystemExit(1)

print(normalized_lines[0])
print(reason)
PY
then
  exit 65
fi

cat "$validated_output" || exit 65
