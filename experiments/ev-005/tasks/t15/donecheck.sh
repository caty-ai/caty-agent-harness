#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

failures=0
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t15.XXXXXX") || {
  echo "CHECK a01 FAIL could not create isolated fixture-probe root"
  echo "CHECK a02 FAIL could not create isolated fixture-probe root"
  echo "CHECK a03 FAIL could not create isolated fixture-probe root"
  echo "CHECK a04 FAIL earlier fixture-probe setup failed"
  exit 1
}
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

POINTER_KIND=''
POINTER_VALUE=''

pass_check() {
  echo "CHECK $1 PASS $2"
}

fail_check() {
  echo "CHECK $1 FAIL $2"
  failures=$((failures + 1))
}

try_fixture_command() {
  local probe_root probe_home probe_tmp rc
  probe_root=$(mktemp -d "$TEMP_ROOT/probe.XXXXXX") || return 1
  probe_home="$probe_root/home"
  probe_tmp="$probe_root/tmp"
  if ! mkdir -p "$probe_home" "$probe_tmp"; then
    rm -rf "$probe_root"
    return 1
  fi
  HOME="$probe_home" TMPDIR="$probe_tmp" PYTHONDONTWRITEBYTECODE=1 \
    "$@" >/dev/null 2>&1
  rc=$?
  rm -rf "$probe_root"
  return "$rc"
}

run_fixture_check() {
  local check_id=$1
  local pass_msg=$2
  local fail_msg=$3
  shift 3
  if try_fixture_command "$@"; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

write_pointer_candidates() {
  local doc
  : >"$TEMP_ROOT/pointer-lines"
  for doc in README.md README.ja.md README.th.md README.zh.md docs/repository-map.md; do
    [ -f "$doc" ] || continue
    awk -v doc="$doc" '
      /^##[[:space:]]/ {
        section = ""
        heading = $0
        while (match(heading, /`[^`]+`/)) {
          token = substr(heading, RSTART + 1, RLENGTH - 2)
          if (token !~ /^--/ && token ~ /\/$/) {
            section = token
            break
          }
          heading = substr(heading, RSTART + RLENGTH)
        }
        if (section == "") {
          heading = $0
          sub(/^##[[:space:]]+/, "", heading)
          split(heading, heading_fields, /[[:space:]]+/)
          if (heading_fields[1] !~ /^--/ && heading_fields[1] ~ /\/$/) {
            section = heading_fields[1]
          }
        }
      }
      {
        lower = tolower($0)
        if (index(lower, "fixture") &&
            (index(lower, "validator") || index(lower, "smoke"))) {
          section_field = section
          if (section_field == "") section_field = "."
          printf "%s\t%d\t%s\t%s\n", doc, NR, section_field, $0
        }
      }
    ' "$doc" >>"$TEMP_ROOT/pointer-lines" || return 1
  done
}

resolve_fixture_pointer() {
  local count section text token token_count path_value section_value
  local old_ifs pointer_doc pointer_line
  write_pointer_candidates || return 1
  count=$(wc -l <"$TEMP_ROOT/pointer-lines" | tr -d ' ')
  [ "$count" -eq 1 ] || return 1

  old_ifs=$IFS
  IFS=$(printf '\t')
  read -r pointer_doc pointer_line section text <"$TEMP_ROOT/pointer-lines" || {
    IFS=$old_ifs
    return 1
  }
  IFS=$old_ifs
  : "$pointer_doc" "$pointer_line"
  [ -n "$text" ] || return 1
  [ "$section" = . ] && section=''

  printf '%s\n' "$text" | awk -F '`' '{ for (i = 2; i <= NF; i += 2) print $i }' \
    >"$TEMP_ROOT/pointer-tokens" || return 1
  token_count=0
  while IFS= read -r token; do
    if printf '%s\n' "$token" \
        | grep -Eq '^--[A-Za-z0-9][A-Za-z0-9_-]*(=[A-Za-z0-9_./:+-]+)?$'; then
      POINTER_KIND=flag
      POINTER_VALUE=$token
      token_count=$((token_count + 1))
    elif printf '%s\n' "$token" \
        | grep -Eq '^[A-Za-z0-9_./+-]+/$'; then
      POINTER_KIND=path
      POINTER_VALUE=${token%/}
      token_count=$((token_count + 1))
    fi
  done <"$TEMP_ROOT/pointer-tokens"
  [ "$token_count" -eq 1 ] || return 1

  if [ "$POINTER_KIND" = flag ]; then
    return 0
  fi

  path_value=$POINTER_VALUE
  while [ "${path_value#./}" != "$path_value" ]; do
    path_value=${path_value#./}
  done
  case "$path_value" in
    ''|/*|..|../*|*/..|*/../*) return 1 ;;
  esac

  case "$path_value" in
    */*) ;;
    *)
      section_value=${section%/}
      while [ "${section_value#./}" != "$section_value" ]; do
        section_value=${section_value#./}
      done
      case "$section_value" in
        '') ;;
        /*|..|../*|*/..|*/../*) return 1 ;;
        *) path_value="$section_value/$path_value" ;;
      esac
      ;;
  esac
  [ -d "$path_value" ] || return 1
  POINTER_VALUE=$path_value
}

run_discovered_path_validator() {
  local check_id=$1
  local validator=$2
  local pass_msg=$3
  local fail_msg=$4
  local candidate candidate_kind option found

  [ -f "scripts/$validator" ] || {
    fail_check "$check_id" "$fail_msg"
    return
  }
  case "$validator" in
    injection-budget-check)
      candidate_kind='file'
      option=--manifest
      ;;
    injection-lint)
      candidate_kind=directory
      option=--manifest-dir
      ;;
    watchdog)
      candidate_kind='file'
      option=--jobs-manifest
      ;;
    *)
      fail_check "$check_id" "$fail_msg"
      return
      ;;
  esac

  if [ "$candidate_kind" = file ]; then
    find "$POINTER_VALUE" -type f -print | LC_ALL=C sort \
      >"$TEMP_ROOT/$validator.candidates" || {
        fail_check "$check_id" "$fail_msg"
        return
      }
  else
    find "$POINTER_VALUE" -type f -print \
      | sed 's#/[^/]*$##' \
      | LC_ALL=C sort -u >"$TEMP_ROOT/$validator.candidates" || {
        fail_check "$check_id" "$fail_msg"
        return
      }
  fi

  found=0
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ "$candidate_kind" = directory ]; then
      if try_fixture_command python3 "scripts/$validator" \
          "$option" "$candidate" --all; then
        found=1
        break
      fi
    elif try_fixture_command python3 "scripts/$validator" "$option" "$candidate"; then
      found=1
      break
    fi
  done <"$TEMP_ROOT/$validator.candidates"

  if [ "$found" -eq 1 ]; then
    pass_check "$check_id" "$pass_msg"
  else
    fail_check "$check_id" "$fail_msg"
  fi
}

run_resolved_validator() {
  local check_id=$1
  local validator=$2
  local pass_msg=$3
  local fail_msg=$4
  if [ "$POINTER_KIND" = path ]; then
    run_discovered_path_validator "$check_id" "$validator" "$pass_msg" "$fail_msg"
  else
    [ -f "scripts/$validator" ] || {
      fail_check "$check_id" "$fail_msg"
      return
    }
    run_fixture_check "$check_id" "$pass_msg" "$fail_msg" \
      python3 "scripts/$validator" "$POINTER_VALUE"
  fi
}

if resolve_fixture_pointer; then
  run_resolved_validator "a01" "injection-budget-check" \
    "injection-budget-check accepts its documented bundled input" \
    "injection-budget-check documented bundled input is missing or does not exit 0"
  run_resolved_validator "a02" "injection-lint" \
    "injection-lint accepts its documented bundled input" \
    "injection-lint documented bundled input is missing or does not exit 0"
  run_resolved_validator "a03" "watchdog" \
    "watchdog accepts its documented bundled input" \
    "watchdog documented bundled input is missing or does not exit 0"
  pass_check "a04" "one README or repository-map line resolves the fixture path or flag"
else
  fail_check "a01" "could not uniquely resolve a documented fixture path or flag"
  fail_check "a02" "could not uniquely resolve a documented fixture path or flag"
  fail_check "a03" "could not uniquely resolve a documented fixture path or flag"
  fail_check "a04" "no unique README or repository-map line resolves the fixture path or flag"
fi

[ "$failures" -eq 0 ]
