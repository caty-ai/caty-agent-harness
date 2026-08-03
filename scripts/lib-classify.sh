#!/usr/bin/env bash

_classify_read_bounded() {
  local file=$1
  local size=''
  local LC_ALL=C
  export LC_ALL

  if [[ -z "$file" || ! -e "$file" ]]; then
    return 0
  fi
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    printf 'classify_failure: unreadable evidence: %s\n' "$file" >&2
    return 0
  fi

  if ! size=$(wc -c <"$file" 2>/dev/null); then
    printf 'classify_failure: unreadable evidence: %s\n' "$file" >&2
    return 0
  fi
  size=$(printf '%s' "$size" | tr -d '[:space:]')

  if (( size <= 131072 )); then
    if ! cat "$file" 2>/dev/null; then
      printf 'classify_failure: unreadable evidence: %s\n' "$file" >&2
    fi
    return 0
  fi

  # A marker fully outside the first and last 64 KiB windows is not seen.
  if ! head -c 65536 "$file" 2>/dev/null; then
    printf 'classify_failure: unreadable evidence: %s\n' "$file" >&2
    return 0
  fi
  printf '\n'
  if ! tail -c 65536 "$file" 2>/dev/null; then
    printf 'classify_failure: unreadable evidence: %s\n' "$file" >&2
  fi
}

classify_failure() {
  local exit_code=$1
  local stderr_file=$2
  local stdout_file=${3:-}
  local stderr_message=''
  local stdout_message=''
  local stderr_cleaned=''
  local stdout_cleaned=''
  local LC_ALL=C
  export LC_ALL

  case "$exit_code" in
    124|137)
      printf '%s\n' transient
      return 0
      ;;
  esac

  stderr_message=$(_classify_read_bounded "$stderr_file")
  stdout_message=$(_classify_read_bounded "$stdout_file")
  stderr_cleaned=$(printf '%s' "$stderr_message" | tr -d '[:space:]')
  stdout_cleaned=$(printf '%s' "$stdout_message" | tr -d '[:space:]')

  # Stderr is the authoritative diagnostics stream. If it matches any bucket,
  # its verdict wins; stdout is consulted only when stderr matches no bucket.
  case "$stderr_message" in
    *' 408 '*|*'"status":408'*|*'"status": 408'*|*'408 Request Timeout'*|*'status code 408'*|*' 429 '*|*'"status":429'*|*'"status": 429'*|*'429 Too Many Requests'*|*'status code 429'*|*'returned error: 429'*|*'"code":429'*|*'"code": 429'*|*'rate_limit_error'*)
      printf '%s\n' transient
      return 0
      ;;
    *'context_length_exceeded'*|*'context length exceeded'*|*'context-length-exceeded'*|*'context overflow'*|*'maximum context length'*|*'too many tokens'*)
      printf '%s\n' context-overflow
      return 0
      ;;
    *' 401 '*|*'"status":401'*|*'"status": 401'*|*'401 Unauthorized'*|*'status code 401'*|*' 403 '*|*'"status":403'*|*'"status": 403'*|*'403 Forbidden'*|*'status code 403'*|*'authentication_error'*|*'invalid_api_key'*|*'invalid api key'*|*'unauthorized'*|*'forbidden'*|*'Not logged in'*|*'not logged in'*|*'Please run /login'*|*'login required'*|*'Login required'*)
      printf '%s\n' deterministic-auth
      return 0
      ;;
    *'invalid_request_error'*|*'invalid request'*|*'invalid input'*|*'invalid parameter'*|*'invalid model'*|*'400 Bad Request'*|*'status code 400'*|*'returned error: 400'*|*'"status":400'*|*'"status": 400'*|*'"code":400'*|*'"code": 400'*|*'422 Unprocessable Entity'*|*'status code 422'*|*'returned error: 422'*|*'"status":422'*|*'"status": 422'*|*'"code":422'*|*'"code": 422'*)
      printf '%s\n' deterministic-input
      return 0
      ;;
  esac

  # Stdout intentionally excludes prose-prone markers: bare space-delimited 4xx
  # numbers; unauthorized/forbidden; invalid api key/request/input/parameter/model;
  # context length/overflow/token prose variants; and lowercase login banners.
  case "$stdout_message" in
    *'"status":408'*|*'"status": 408'*|*'408 Request Timeout'*|*'status code 408'*|*'"status":429'*|*'"status": 429'*|*'429 Too Many Requests'*|*'status code 429'*|*'returned error: 429'*|*'"code":429'*|*'"code": 429'*|*'rate_limit_error'*)
      printf '%s\n' transient
      return 0
      ;;
    *'context_length_exceeded'*)
      printf '%s\n' context-overflow
      return 0
      ;;
    *'"status":401'*|*'"status": 401'*|*'401 Unauthorized'*|*'status code 401'*|*'"status":403'*|*'"status": 403'*|*'403 Forbidden'*|*'status code 403'*|*'authentication_error'*|*'invalid_api_key'*|*'Not logged in'*|*'Please run /login'*|*'Login required'*)
      printf '%s\n' deterministic-auth
      return 0
      ;;
    *'invalid_request_error'*|*'400 Bad Request'*|*'status code 400'*|*'returned error: 400'*|*'"status":400'*|*'"status": 400'*|*'"code":400'*|*'"code": 400'*|*'422 Unprocessable Entity'*|*'status code 422'*|*'returned error: 422'*|*'"status":422'*|*'"status": 422'*|*'"code":422'*|*'"code": 422'*)
      printf '%s\n' deterministic-input
      return 0
      ;;
  esac

  if [[ -z "$stderr_cleaned" && -z "$stdout_cleaned" ]]; then
    printf '%s\n' degenerate
  else
    printf '%s\n' transient
  fi
}
