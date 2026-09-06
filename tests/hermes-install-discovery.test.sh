#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/caty-hermes-install-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
failures=0
DOC="$ROOT/adapters/hermes/INSTALL.md"

pass() { printf 'ok - %s\n' "$1"; }
fail_case() {
  printf 'not ok - %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}
assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail_case "$name" "expected=$expected actual=$actual"
  fi
}

for required in 'hermes profile show' "sed -n 's/^Path:[[:space:]]*//p'" '[ -f "$SOUL" ]'; do
  if grep -Fq "$required" "$DOC"; then
    pass "INSTALL.md contains $required"
  else
    fail_case "INSTALL.md contains $required" 'required guidance missing'
  fi
done
if grep -Fq '/absolute/path/to/profile-system-instructions.md' "$DOC"; then
  fail_case 'unresolvable bootstrap placeholder is absent' 'placeholder remains'
else
  pass 'unresolvable bootstrap placeholder is absent'
fi

# Extract executable lines only from sh fences, not explanatory prose.
shell_lines=$(awk '
  /^   ```sh$/ { in_sh=1; next }
  /^   ```$/ { in_sh=0 }
  in_sh { sub(/^   /, ""); print }
' "$DOC")
profile_line=$(printf '%s\n' "$shell_lines" | grep -F 'PROFILE_HOME=' || true)
soul_line=$(printf '%s\n' "$shell_lines" | grep -F 'SOUL=' || true)
guard_line=$(printf '%s\n' "$shell_lines" | grep -F '[ -n "$PROFILE_HOME" ] &&' || true)
extraction_ok=1
for line in "$profile_line" "$soul_line" "$guard_line"; do
  if [[ -z "$line" || "$line" == *$'\n'* ]]; then
    fail_case 'discovery extraction is nonempty and unique' "extracted=$line"
    extraction_ok=0
  fi
done

if [[ "$extraction_ok" == 1 ]]; then
  pass 'discovery extraction is nonempty and unique'
  mkdir -p "$TMP/bin" "$TMP/home"
  cat >"$TMP/bin/hermes" <<'SH'
#!/bin/sh
if [ "$#" -ne 3 ] || [ "$1" != profile ] || [ "$2" != show ] || [ "$3" != default ]; then
  exit 1
fi
printf '\n'
cat <<EOF
Profile: default
Path:    $HERMES_TEST_HOME
Model:   gpt-5.6-sol (openai-codex)
Gateway: stopped
Skills:  70
.env:    exists
SOUL.md: exists
EOF
SH
  chmod +x "$TMP/bin/hermes"

  run_discovery() (
    export PATH="$TMP/bin:$PATH" HERMES_TEST_HOME="$TMP/home"
    PROFILE=$1
    # Match the documented POSIX shell: a failed pipeline must reach the guard.
    set +e
    set +o pipefail
    eval "$profile_line"
    eval "$soul_line"
    eval "$guard_line"
    guard_rc=$?
    printf '%s\n' "$SOUL"
    exit "$guard_rc"
  )

  touch "$TMP/home/SOUL.md"
  set +e
  resolved=$(run_discovery default 2>"$TMP/present.stderr")
  present_rc=$?
  set -e
  assert_eq 'existing SOUL.md passes the documented guard' '0' "$present_rc"
  assert_eq 'multiple Path spaces resolve the exact SOUL.md path' "$TMP/home/SOUL.md" "$resolved"

  rm "$TMP/home/SOUL.md"
  set +e
  run_discovery default >"$TMP/missing.stdout" 2>"$TMP/missing.stderr"
  missing_rc=$?
  run_discovery nonexistent >"$TMP/nonexistent.stdout" 2>"$TMP/nonexistent.stderr"
  nonexistent_rc=$?
  set -e
  for scenario in missing nonexistent; do
    if [[ "$scenario" == missing ]]; then
      rc=$missing_rc
    else
      rc=$nonexistent_rc
    fi
    if [[ "$rc" != 0 ]]; then
      pass "$scenario fails closed"
    else
      fail_case "$scenario fails closed" 'guard exited zero'
    fi
    if grep -Fq 'stop:' "$TMP/$scenario.stderr"; then
      pass "$scenario prints stop: on stderr"
    else
      fail_case "$scenario prints stop: on stderr" "$(cat "$TMP/$scenario.stderr")"
    fi
  done
fi

printf 'Hermes install discovery summary: %s failure(s)\n' "$failures"
if (( failures )); then
  exit 1
fi
