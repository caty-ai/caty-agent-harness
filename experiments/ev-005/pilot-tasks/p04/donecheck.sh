#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
FIXTURE='.ev005-fixtures/provider-opener-stub.py'
PROVIDER='adapters/hermes/examples/verifier-provider.py'
SUITE='tests/hermes-verifier-examples.test.sh'
BUNDLE='This bundle is intentionally longer than the configured verifier floor and is delivered as argv one.'

run_isolated() (
  local env_root rc
  env_root=$(mktemp -d "${TMPDIR:-/tmp}/ev005-p04.XXXXXX") || return 1
  trap 'rm -rf "$env_root"' EXIT HUP INT TERM
  if ! mkdir -p "$env_root/home" "$env_root/tmp"; then
    return 1
  fi
  HOME="$env_root/home" TMPDIR="$env_root/tmp" PYTHONDONTWRITEBYTECODE=1 "$@"
  rc=$?
  return "$rc"
)

pass_check() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  failures=$((failures + 1))
}

run_check() {
  local check_id pass_msg fail_msg
  check_id=$1
  pass_msg=$2
  fail_msg=$3
  shift 3
  if "$@" >/dev/null 2>&1; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

check_provider_base_behavior() {
  run_isolated env FIXTURE="$FIXTURE" PROVIDER="$PROVIDER" BUNDLE="$BUNDLE" bash -eu <<'SH'
expected_output='VERDICT: pass
stub accepted the request URL'
request_url=$TMPDIR/request-url.marker
request_key=$TMPDIR/request-key.marker
request_count=$TMPDIR/request-count.marker
out=$TMPDIR/provider.out
err=$TMPDIR/provider.err
zai_base='https://api.z.ai/api/anthropic'

run_case() {
  local base expected_url rc
  base=$1
  expected_url=$2
  rm -f "$request_url" "$request_key" "$request_count" "$out" "$err"
  set +e
  if [ -n "$base" ]; then
    ANTHROPIC_API_KEY=fixture VERIFIER_API_BASE="$base" \
      REQUEST_URL_MARKER="$request_url" REQUEST_KEY_MARKER="$request_key" \
      REQUEST_COUNT_MARKER="$request_count" \
      python3 "$FIXTURE" "$PROVIDER" "$BUNDLE" >"$out" 2>"$err"
  else
    env -u VERIFIER_API_BASE ANTHROPIC_API_KEY=fixture \
      REQUEST_URL_MARKER="$request_url" REQUEST_KEY_MARKER="$request_key" \
      REQUEST_COUNT_MARKER="$request_count" \
      python3 "$FIXTURE" "$PROVIDER" "$BUNDLE" >"$out" 2>"$err"
  fi
  rc=$?
  set -e
  [ "$rc" -eq 0 ]
  [ "$(cat "$out")" = "$expected_output" ]
  [ "$(cat "$request_url")" = "$expected_url" ]
  [ "$(cat "$request_key")" = 'fixture' ]
  [ "$(cat "$request_count")" = '1' ]
  [ ! -s "$err" ]
}

run_case '' 'https://api.anthropic.com/v1/messages'
run_case "$zai_base" "$zai_base/v1/messages"
run_case "$zai_base/" "$zai_base/v1/messages"
SH
}

check_invalid_api_bases() {
  run_isolated env FIXTURE="$FIXTURE" PROVIDER="$PROVIDER" BUNDLE="$BUNDLE" bash -eu <<'SH'
out=$TMPDIR/provider.out
err=$TMPDIR/provider.err

for invalid_base in \
  'http://api.example.test' \
  'https://' \
  'https://api.example.test/embedded space' \
  "$(printf 'https://api.example.test/embedded\tcontrol')"; do
  rm -f "$out" "$err"
  set +e
  ANTHROPIC_API_KEY=fixture VERIFIER_API_BASE="$invalid_base" \
    python3 "$FIXTURE" "$PROVIDER" "$BUNDLE" >"$out" 2>"$err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || exit 1
  ! grep -q '^VERDICT:' "$out" || exit 1
  grep -Fqx 'provider API base is invalid' "$err" || exit 1
done
SH
}

check_provider_wire_contract() {
  run_isolated env FIXTURE="$FIXTURE" PROVIDER="$PROVIDER" BUNDLE="$BUNDLE" bash -eu <<'SH'
expected_output='VERDICT: pass
stub accepted the request URL'
request_url=$TMPDIR/request-url.marker
request_key=$TMPDIR/request-key.marker
request_count=$TMPDIR/request-count.marker
out=$TMPDIR/provider.out
err=$TMPDIR/provider.err

rm -f "$request_url" "$request_key" "$request_count" "$out" "$err"
ANTHROPIC_API_KEY=legacy-key \
  REQUEST_URL_MARKER="$request_url" REQUEST_KEY_MARKER="$request_key" \
  REQUEST_COUNT_MARKER="$request_count" \
  python3 "$FIXTURE" "$PROVIDER" "$BUNDLE" >"$out" 2>"$err"
[ "$(cat "$out")" = "$expected_output" ]
[ "$(cat "$request_key")" = 'legacy-key' ]
[ "$(cat "$request_count")" = '1' ]
[ ! -s "$err" ]

rm -f "$request_url" "$request_key" "$request_count" "$out" "$err"
VERIFIER_API_KEY=preferred-key ANTHROPIC_API_KEY=legacy-key \
  REQUEST_URL_MARKER="$request_url" REQUEST_KEY_MARKER="$request_key" \
  REQUEST_COUNT_MARKER="$request_count" \
  python3 "$FIXTURE" "$PROVIDER" "$BUNDLE" >"$out" 2>"$err"
[ "$(cat "$out")" = "$expected_output" ]
[ "$(cat "$request_key")" = 'preferred-key' ]
[ "$(cat "$request_count")" = '1' ]
[ ! -s "$err" ]

python3 - <<'PY'
from pathlib import Path

text = Path("adapters/hermes/examples/verifier-provider.py").read_text(encoding="utf-8")
needles = [
    'os.environ.get("VERIFIER_API_KEY", "")',
    'os.environ.get("ANTHROPIC_API_KEY", "")',
    '"anthropic-version": "2023-06-01"',
    '"x-api-key": api_key',
    'os.environ.get("VERIFIER_TEMPERATURE", "0")',
    'os.environ.get("VERIFIER_HTTP_TIMEOUT_S", "120")',
]
if any(needle not in text for needle in needles):
    raise SystemExit(1)
PY
SH
}

check_install_vendor_docs() {
  run_isolated python3 - <<'PY'
from pathlib import Path

text = Path("adapters/hermes/INSTALL.md").read_text(encoding="utf-8")
needles = [
    "VERIFIER_API_KEY",
    "Anthropic remains the default",
    "`https://api.anthropic.com`.",
    "Z.ai GLM 5.2",
    "VERIFIER_API_KEY=<Z.ai member key>",
    "VERIFIER_MODEL=glm-5.2",
    "VERIFIER_API_BASE=https://api.z.ai/api/anthropic",
]
if any(needle not in text for needle in needles):
    raise SystemExit(1)
PY
}

check_install_reattest_docs() {
  run_isolated python3 - <<'PY'
from pathlib import Path

text = Path("adapters/hermes/INSTALL.md").read_text(encoding="utf-8")
needles = [
    "vendor, model, or endpoint change",
    "Re-run the attester",
    "provider configuration",
]
if any(needle not in text for needle in needles):
    raise SystemExit(1)
PY
}

check_example_suite_coverage() {
  run_isolated env SUITE="$SUITE" bash -eu <<'SH'
log=$TMPDIR/hermes-verifier-examples.log
grep -Fq 'default_base_output' "$SUITE"
grep -Fq 'zai_base_output' "$SUITE"
grep -Fq 'trailing_slash_output' "$SUITE"
grep -Fq 'invalid_base_guard_ok' "$SUITE"
bash "$SUITE" >"$log" 2>&1
grep -Fq 'Summary:' "$log"
grep -Eq 'Summary: [0-9]+ PASS, 0 FAIL' "$log"
SH
}

run_check a01 'provider honors the configurable base and normalized messages path' \
  'provider base selection or path normalization is wrong' \
  check_provider_base_behavior
run_check a02 'provider rejects malformed or unsafe API bases before I/O' \
  'provider accepts or misreports an invalid API base' \
  check_invalid_api_bases
run_check a03 'provider keeps the Anthropic wire contract unchanged' \
  'provider no longer uses the Anthropic wire contract or caller key env' \
  check_provider_wire_contract
run_check a04 'install guide names the default and alternate verifier endpoints' \
  'install guide is missing the default or alternate endpoint configuration' \
  check_install_vendor_docs
run_check a05 'install guide records the re-attest rule for endpoint swaps' \
  'install guide is missing the configuration-change re-attest guidance' \
  check_install_reattest_docs
run_check a06 'focused verifier example regression coverage passes with the new endpoint cases' \
  'focused verifier example regression coverage is missing or failing' \
  check_example_suite_coverage

[ "$failures" -eq 0 ]
