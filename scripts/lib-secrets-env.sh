# shellcheck shell=bash
# Source-only SECRETS_ENV acceptance rules shared by install.sh and cron wrappers.
# This library intentionally has no source-time side effects or shell-option changes.

secrets_env_file_shape_reasons() {
  local secrets_path=$1
  local current_uid owner_uid mode

  if [[ -L "$secrets_path" ]]; then
    printf 'must not be a symlink\n'
    return 0
  fi

  current_uid=$(id -u)
  if ! owner_uid=$(stat -c "%u" "$secrets_path" 2>/dev/null || stat -f "%u" "$secrets_path" 2>/dev/null); then
    printf 'owner uid could not be determined\n'
  elif [[ "$owner_uid" != "$current_uid" ]]; then
    printf 'owner uid %s does not match current uid %s\n' "$owner_uid" "$current_uid"
  fi

  if ! mode=$(stat -c "%a" "$secrets_path" 2>/dev/null || stat -f "%Lp" "$secrets_path" 2>/dev/null); then
    printf 'permissions could not be determined\n'
  else
    case "$mode" in
      400|0400|600|0600) ;;
      *)
        printf 'permissions must be 0600 or 0400; has %s\n' "$mode"
        ;;
    esac
  fi
}

secrets_env_first_nul_line() {
  local secrets_path=$1

  LC_ALL=C od -An -v -t u1 "$secrets_path" 2>/dev/null | awk '
    BEGIN { line_number = 1 }
    {
      for (field = 1; field <= NF; field++) {
        if (!found && $field == 0) {
          first_match = line_number
          found = 1
        }
        if ($field == 10) {
          line_number++
        }
      }
    }
    END {
      if (found) {
        print first_match
      }
    }
  '
}

secrets_env_classify_line() {
  local raw_line=$1
  local line value first_char last_char inner_value

  SECRETS_ENV_KEY=
  SECRETS_ENV_VALUE=
  line=${raw_line%$'\r'}

  if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
    return 1
  fi
  if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    return 3
  fi

  SECRETS_ENV_KEY=${BASH_REMATCH[1]}
  value=${BASH_REMATCH[2]}
  case "$SECRETS_ENV_KEY" in
    BASH_ENV|ENV|SHELLOPTS|BASHOPTS|IFS|PS4|CDPATH|GLOBIGNORE|PATH|BASH_XTRACEFD|\
    PAGER|EDITOR|VISUAL|PERL5OPT|PERL5LIB|PERLLIB|PERL5DB|PERL5SHELL|\
    PYTHONSTARTUP|PYTHONPATH|PYTHONHOME|PYTHONWARNINGS|PYTHONBREAKPOINT|\
    RUBYOPT|RUBYLIB|NODE_OPTIONS|NODE_PATH|\
    NODE_REPL_EXTERNAL_MODULE|GIT_SSH|GIT_SSH_COMMAND|GIT_EXTERNAL_DIFF|GIT_PAGER|\
    GIT_EDITOR|GIT_ASKPASS|SSH_ASKPASS|GIT_PROXY_COMMAND|GIT_CONFIG_GLOBAL|\
    GIT_CONFIG_SYSTEM|GIT_CONFIG_COUNT|GIT_CONFIG_PARAMETERS|GIT_EXEC_PATH|\
    GIT_ALTERNATE_OBJECT_DIRECTORIES|LESSOPEN|LESSCLOSE|BASH_FUNC_*|LD_*|DYLD_*)
      return 2
      ;;
  esac

  if (( ${#value} >= 2 )); then
    first_char=${value:0:1}
    last_char=${value: -1}
    if [[ "$first_char" == "$last_char" && ( "$first_char" == "'" || "$first_char" == '"' ) ]]; then
      inner_value=${value:1:${#value}-2}
      if [[ "$inner_value" != *"$first_char"* ]]; then
        value=$inner_value
      fi
    fi
  fi
  # This global is the sourceable-library result consumed by both callers.
  # shellcheck disable=SC2034
  SECRETS_ENV_VALUE=$value
  return 0
}
