#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/scripts/activation-manifest.tsv"
failures=0

fail_case() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

for required_command in awk find grep sed sort head cut mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'required test command is missing: %s\n' "$required_command" >&2
    exit 2
  fi
done

audit_pre_guard_operations() {
  local source_file=$1
  local guard_literal=$2

  awk -v guard_literal="$guard_literal" '
    function forbidden(line) {
      gsub(/[0-9]*>\/dev\/null/, "", line)
      gsub(/2>&1/, "", line)
      gsub(/>&2/, "", line)
      gsub(/\(\([^)]*\)\)/, "", line)
      if (line ~ /(^|[[:space:];|&])(mkdir|touch|rm|mv|cp|chmod|chown|ln|install|tee|mktemp)([[:space:]]|$)/) return 1
      if (line ~ /(^|[[:space:];|&])(run_bounded|wrapper_conformance_gate|append_[A-Za-z0-9_]*|write_[A-Za-z0-9_]*|deliver_[A-Za-z0-9_]*)([[:space:]]|\(|$)/) return 1
      if (line ~ /(^|[^<])>>?[^&]/) return 1
      return 0
    }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
    index($0, guard_literal) {
      found_guard = 1
      exit
    }
    /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ {
      in_function = 1
      next
    }
    in_function {
      if ($0 ~ /^}[[:space:]]*$/) in_function = 0
      next
    }
    forbidden($0) {
      printf "%s:%s\n", NR, $0
      violation = 1
      exit
    }
    END {
      if (violation) exit 1
      if (!found_guard) exit 2
    }
  ' "$source_file"
}

candidates=$(mktemp "${TMPDIR:-/tmp}/activation-candidates.XXXXXX")
trap 'rm -f "$candidates"' EXIT
{
  while IFS= read -r script_file; do
    IFS= read -r first_line <"$script_file" || true
    if [[ -x "$script_file" || "$first_line" == '#!'* ]]; then
      printf '%s\n' "$script_file"
    fi
  done < <(find "$ROOT/scripts" -type f -print)
  while IFS= read -r adapter_file; do
    IFS= read -r first_line <"$adapter_file" || true
    if [[ -x "$adapter_file" || "$first_line" == '#!'* ]]; then
      printf '%s\n' "$adapter_file"
    fi
  done < <(find "$ROOT/adapters" -type f -print)
  while IFS= read -r template_file; do
    IFS= read -r first_line <"$template_file" || true
    if [[ -x "$template_file" || "$first_line" == '#!'* ]]; then
      printf '%s\n' "$template_file"
    fi
  done < <(find "$ROOT/templates" -type f -print)
} | sed "s|^$ROOT/||" | LC_ALL=C sort -u >"$candidates"

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if ! awk -F '\t' -v path="$path" '$1 == path {found=1} END {exit found ? 0 : 1}' "$MANIFEST"; then
    fail_case "candidate is registered or exempt: $path"
  else
    pass "candidate is registered or exempt: $path"
  fi
done <"$candidates"

documented_candidates=$(mktemp "${TMPDIR:-/tmp}/activation-documented.XXXXXX")
: >"$documented_candidates"
{
  printf '%s\n' "$ROOT/INSTALL.md"
  find "$ROOT/adapters" -type f -name INSTALL.md -print
  find "$ROOT/templates" -type f -print
} | while IFS= read -r documentation_file; do
  set +e
  grep -Eho '(scripts|adapters)/[A-Za-z0-9._/-]+' "$documentation_file" >>"$documented_candidates"
  grep_status=$?
  set -e
  if [[ "$grep_status" -gt 1 ]]; then
    printf 'failed to inspect documented entry points: %s\n' "$documentation_file" >&2
    exit 2
  fi
done

while IFS= read -r documented; do
  [[ -n "$documented" ]] || continue
  if ! awk -F '\t' -v path="$documented" '$1 == path {found=1} END {exit found ? 0 : 1}' "$MANIFEST"; then
    fail_case "documented/template entry point is registered: $documented"
  fi
done < <(
  while IFS= read -r path; do
    while [[ ! -f "$ROOT/$path" && "$path" == *[.,:\;\)] ]]; do
      path=${path%?}
    done
    [[ -f "$ROOT/$path" && ( -x "$ROOT/$path" || "$path" == adapters/*/*.sh ) ]] \
      && printf '%s\n' "$path"
  done <"$documented_candidates" | LC_ALL=C sort -u
)

while IFS=$'\t' read -r path entry_class workspace_resolution paused_contract reason guard_literal forbidden_literal; do
  [[ -n "$path" && "$path" != \#* ]] || continue
  [[ -f "$ROOT/$path" ]] || {
    fail_case "manifest path exists: $path"
    continue
  }
  if [[ "$entry_class" == guarded ]]; then
    if ! grep -Fq 'lib-pause.sh' "$ROOT/$path" \
      || ! grep -Fq 'caty_pause_workspace_state' "$ROOT/$path"; then
      fail_case "guarded entry point calls shared pause guard: $path"
    else
      pass "guarded entry point calls shared pause guard: $path"
    fi
    guard_line=$(awk -v literal="$guard_literal" \
      '$0 !~ /^[[:space:]]*#/ && index($0, literal) {print NR; exit}' "$ROOT/$path")
    forbidden_line=$(grep -nF -- "$forbidden_literal" "$ROOT/$path" | head -n 1 | cut -d: -f1)
    if [[ -z "$guard_line" || -z "$forbidden_line" || "$guard_line" -ge "$forbidden_line" ]]; then
      fail_case "pause guard precedes first forbidden operation: $path"
    else
      pass "pause guard precedes first forbidden operation: $path"
    fi
    if audit_output=$(audit_pre_guard_operations "$ROOT/$path" "$guard_literal" 2>&1); then
      pass "no unregistered top-level side effect precedes pause guard: $path"
    else
      fail_case "no unregistered top-level side effect precedes pause guard: $path ($audit_output)"
    fi
  fi
done <"$MANIFEST"

negative_fixture=$(mktemp "${TMPDIR:-/tmp}/activation-negative.XXXXXX")
for forbidden_fixture in \
  'touch /tmp/forbidden-before-pause' \
  'run_bounded 10 1 fake-provider' \
  'printf "verdict=pass\n" >>"$VERIFY_LOG"'; do
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$forbidden_fixture"
    printf '%s\n' 'caty_pause_workspace_state "$workspace"'
  } >"$negative_fixture"
  if audit_pre_guard_operations "$negative_fixture" caty_pause_workspace_state >/dev/null 2>&1; then
    fail_case "negative fixture detects pre-guard operation: $forbidden_fixture"
  else
    pass "negative fixture detects pre-guard operation: $forbidden_fixture"
  fi
done

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# caty_pause_workspace_state "$workspace" is only documentation'
  printf '%s\n' 'touch /tmp/forbidden-after-comment-only-guard'
  printf '%s\n' 'caty_pause_workspace_state "$workspace"'
} >"$negative_fixture"
if audit_pre_guard_operations "$negative_fixture" caty_pause_workspace_state >/dev/null 2>&1; then
  fail_case "comment-only guard cannot hide a pre-guard mutation"
else
  pass "comment-only guard cannot hide a pre-guard mutation"
fi

if (( failures )); then
  printf '%s activation manifest test(s) failed\n' "$failures" >&2
  exit 1
fi
