#!/usr/bin/env bash

# Shared donecheck and interpreter contracts. Callers are responsible for
# turning the extractor status into the user-facing enqueue/verification error.

caty_extract_donecheck() {
  local task_file=$1
  local out_file=$2

  python3 -B - "$task_file" "$out_file" <<'PY'
import re
import sys

task_file, out_file = sys.argv[1:3]
try:
    with open(task_file, "rb") as handle:
        text = handle.read().decode("utf-8")
except UnicodeDecodeError:
    sys.exit(3)
except OSError:
    sys.exit(6)

# The task grammar is line-oriented and normalizes CRLF before matching or
# emitting the extracted bytes.
text = text.replace("\r\n", "\n")
lines = text.split("\n")
opener = re.compile(r"^```donecheck[\t\v\f\r ]*$")
closer = re.compile(r"^```[\t\v\f\r ]*$")

openers = []
for index, line in enumerate(lines):
    if opener.fullmatch(line):
        openers.append(index)

if not openers:
    sys.exit(2)
if len(openers) != 1:
    sys.exit(4)

start = openers[0]
end = None
for index in range(start + 1, len(lines)):
    line = lines[index]
    if closer.fullmatch(line):
        end = index
        break
if end is None:
    sys.exit(5)

with open(out_file, "wb") as handle:
    content = "\n".join(lines[start + 1:end])
    if end > start + 1:
        content += "\n"
    handle.write(content.encode("utf-8"))
PY
}

caty_donecheck_error() {
  case "$1" in
    2) printf '%s\n' 'missing donecheck block' ;;
    3) printf '%s\n' 'task file is not valid UTF-8' ;;
    4) printf '%s\n' 'multiple donecheck blocks' ;;
    5) printf '%s\n' 'unclosed donecheck block' ;;
    *) printf 'donecheck extraction failed (exit %s)\n' "$1" ;;
  esac
}

caty_valid_receipt() {
  local value=$1
  local old_ifs segment first=1 segments=0

  printf '%s\n' "$value" | grep -Eq '^out/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$' || return 1
  old_ifs=$IFS
  IFS=/
  # Intentional word splitting: the regex above has already excluded empty
  # segments and all characters outside the frozen receipt grammar.
  # shellcheck disable=SC2086
  set -- $value
  IFS=$old_ifs
  for segment in "$@"; do
    segments=$((segments + 1))
    if [ "$first" -eq 1 ]; then
      [ "$segment" = out ] || return 1
      first=0
      continue
    fi
    [ "$segment" != . ] && [ "$segment" != .. ] || return 1
  done
  [ "$segments" -ge 2 ]
}

caty_resolve_command() {
  local name=$1
  local resolved parent
  resolved=$(command -v "$name" 2>/dev/null) || return 1
  case "$resolved" in
    /*) ;;
    */*)
      parent=$(cd -P -- "$(dirname "$resolved")" 2>/dev/null && pwd) || return 1
      resolved=$parent/$(basename "$resolved")
      ;;
    *) return 1 ;;
  esac
  [ -x "$resolved" ] || return 1
  printf '%s\n' "$resolved"
}

caty_read_interpreters() {
  local record=$1
  local line key value count=0 bash_value='' perl_value=''

  [ -f "$record" ] && [ -r "$record" ] || {
    printf 'invalid interpreter record: file=%s value=<unreadable>\n' "$record" >&2
    return 1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    count=$((count + 1))
    key=${line%%=*}
    value=${line#*=}
    [ "$line" != "$key" ] || {
      printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$line" >&2
      return 1
    }
    case "$key" in
      TR_BASH)
        [ -z "$bash_value" ] || {
          printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$line" >&2
          return 1
        }
        bash_value=$value
        ;;
      TR_PERL)
        [ -z "$perl_value" ] || {
          printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$line" >&2
          return 1
        }
        perl_value=$value
        ;;
      *)
        printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$line" >&2
        return 1
        ;;
    esac
  done <"$record"

  [ "$count" -eq 2 ] || {
    printf 'invalid interpreter record: file=%s value=<expected-two-lines>\n' "$record" >&2
    return 1
  }
  for value in "$bash_value" "$perl_value"; do
    case "$value" in
      /*) ;;
      *)
        printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$value" >&2
        return 1
        ;;
    esac
    [ -x "$value" ] || {
      printf 'invalid interpreter record: file=%s value=%s\n' "$record" "$value" >&2
      return 1
    }
  done

  TR_BASH=$bash_value
  TR_PERL=$perl_value
  export TR_BASH TR_PERL
}

caty_load_interpreters() {
  local workspace=$1
  local record="$workspace/loop/.tr-interpreters"
  local bash_value perl_value tmp

  if [ ! -e "$record" ]; then
    bash_value=$(caty_resolve_command bash) || {
      printf 'cannot resolve interpreter: file=%s value=bash\n' "$record" >&2
      return 1
    }
    perl_value=$(caty_resolve_command perl) || {
      printf 'cannot resolve interpreter: file=%s value=perl\n' "$record" >&2
      return 1
    }
    mkdir -p "$workspace/loop" || return 1
    tmp="$record.tmp.$$.$RANDOM"
    if (umask 077; set -C; printf 'TR_BASH=%s\nTR_PERL=%s\n' "$bash_value" "$perl_value" >"$tmp") 2>/dev/null; then
      if ! mv -n "$tmp" "$record" 2>/dev/null; then
        rm -f "$tmp"
      fi
      # BSD mv -n returns success when it declines to replace. Remove the
      # losing temporary record and always re-read the winner.
      rm -f "$tmp"
    fi
  fi
  caty_read_interpreters "$record"
}
