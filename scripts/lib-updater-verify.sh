#!/usr/bin/env bash

# Shared trust gate for family-updater and updater-bootstrap. Callers provide
# reporting; this file owns the ordered object, name, floor, and checkout checks.

UPDATER_VERIFY_REASON=
UPDATER_CAPTURED_TAG=
UPDATER_CAPTURED_TAG_OID=
UPDATER_CAPTURED_COMMIT=
UPDATER_CAPTURED_EPOCH=
UPDATER_FLOOR_VERSION=
UPDATER_FLOOR_COMMIT=
UPDATER_REMOTE_TAGS=
UPDATER_MOVED_TAGS=
UPDATER_SYNC_FAILURE_HANDLED=0

updater_is_semver() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

updater_semver_components() {
  local value=${1#v}
  local output_var=$2
  local major=${value%%.*}
  local rest=${value#*.}
  local minor=${rest%%.*}
  local patch=${rest#*.}

  while [[ ${#major} -gt 1 && ${major#0} != "$major" ]]; do major=${major#0}; done
  while [[ ${#minor} -gt 1 && ${minor#0} != "$minor" ]]; do minor=${minor#0}; done
  while [[ ${#patch} -gt 1 && ${patch#0} != "$patch" ]]; do patch=${patch#0}; done
  printf -v "$output_var" '%s %s %s' "$major" "$minor" "$patch"
}

updater_numeric_component_compare() {
  local left=$1
  local right=$2

  if (( ${#left} > ${#right} )); then
    printf '1\n'
  elif (( ${#left} < ${#right} )); then
    printf '%s\n' '-1'
  elif [[ "$left" == "$right" ]]; then
    printf '0\n'
  elif [[ "$left" > "$right" ]]; then
    printf '1\n'
  else
    printf '%s\n' '-1'
  fi
}

updater_semver_compare() {
  local left_parts right_parts
  local left_component right_component comparison
  local index
  local -a left right

  updater_semver_components "$1" left_parts
  updater_semver_components "$2" right_parts
  read -r -a left <<<"$left_parts"
  read -r -a right <<<"$right_parts"
  for index in 0 1 2; do
    left_component=${left[$index]}
    right_component=${right[$index]}
    comparison=$(updater_numeric_component_compare "$left_component" "$right_component")
    if [[ "$comparison" != 0 ]]; then
      printf '%s\n' "$comparison"
      return 0
    fi
  done
  printf '0\n'
}

updater_sort_semvers_desc() {
  local values=$1
  local value swap
  local i
  local -a sorted

  sorted=()
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    sorted+=("$value")
    i=$((${#sorted[@]} - 1))
    while (( i > 0 )) && [[ $(updater_semver_compare "${sorted[$i]}" "${sorted[$((i - 1))]}") -gt 0 ]]; do
      swap=${sorted[$((i - 1))]}
      sorted[$((i - 1))]=${sorted[$i]}
      sorted[$i]=$swap
      i=$((i - 1))
    done
  done <<<"$values"
  if (( ${#sorted[@]} > 0 )); then
    printf '%s\n' "${sorted[@]}"
  fi
}

updater_repo_name() {
  basename "$(cd "$1" && pwd -P)"
}

updater_repo_state_key() {
  local repo_real repo_name path_hash

  repo_real=$(cd "$1" && pwd -P) || return 1
  repo_name=$(basename "$repo_real")
  path_hash=$(printf '%s' "$repo_real" | git hash-object --stdin) || return 1
  printf '%s-%s\n' "$repo_name" "${path_hash:0:12}"
}

updater_default_pin_path() {
  printf '%s/.claude/state/updater-pin/%s.json\n' "$HOME" "$(updater_repo_state_key "$1")"
}

updater_default_ineligible_path() {
  printf '%s/.claude/state/updater-ineligible/%s.log\n' "$HOME" "$(updater_repo_state_key "$1")"
}

updater_path_is_outside_repo() {
  local repo_real signers_dir signers_real

  repo_real=$(cd "$1" && pwd -P) || return 1
  signers_dir=$(dirname "$2")
  signers_real=$(cd "$signers_dir" 2>/dev/null && pwd -P) || return 1
  signers_real="$signers_real/$(basename "$2")"
  [[ "$signers_real" != "$repo_real" && "$signers_real" != "$repo_real/"* ]]
}

updater_check_capabilities() {
  local repo=$1
  local version_text major minor probe_output ssh_probe

  version_text=$(git --version 2>/dev/null) || {
    UPDATER_VERIFY_REASON="git capability check failed: git --version is unavailable"
    return 1
  }
  if [[ ! "$version_text" =~ ([0-9]+)\.([0-9]+) ]]; then
    UPDATER_VERIFY_REASON="git capability check failed: cannot parse version: $version_text"
    return 1
  fi
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  if (( major < 2 || (major == 2 && minor < 34) )); then
    UPDATER_VERIFY_REASON="git 2.34 or newer is required for SSH signature verification (found $major.$minor)"
    return 1
  fi

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    UPDATER_VERIFY_REASON="SSH signature verification is unavailable: ssh-keygen is not installed"
    return 1
  fi
  ssh_probe=$(ssh-keygen -Y 2>&1 || true)
  if printf '%s\n' "$ssh_probe" | grep -Eiq 'unknown option.*Y|illegal option.*Y'; then
    UPDATER_VERIFY_REASON="SSH signature verification is unavailable: ssh-keygen lacks -Y signature support"
    return 1
  fi

  probe_output=$(git -C "$repo" -c gpg.format=ssh verify-tag 0000000000000000000000000000000000000000 2>&1 || true)
  if printf '%s\n' "$probe_output" | grep -Eiq 'unsupported .*gpg\.format|unknown .*gpg\.format|invalid value.*ssh'; then
    UPDATER_VERIFY_REASON="SSH signature verification is unavailable in this git installation"
    return 1
  fi
}

updater_validate_allowed_signers() {
  local repo=$1
  local path=$2

  if [[ ! -f "$path" || ! -r "$path" || ! -s "$path" ]]; then
    UPDATER_VERIFY_REASON="allowed_signers file is absent, unreadable, or empty: $path"
    return 1
  fi
  if [[ -L "$path" ]]; then
    UPDATER_VERIFY_REASON="allowed_signers must not be a symlink: $path"
    return 1
  fi
  if ! updater_path_is_outside_repo "$repo" "$path"; then
    UPDATER_VERIFY_REASON="allowed_signers must live outside the repository: $path"
    return 1
  fi
}

updater_prepare_private_dir() {
  local dir=$1

  if ! mkdir -p "$dir" || ! chmod 700 "$dir"; then
    UPDATER_VERIFY_REASON="cannot prepare updater state directory: $dir"
    return 1
  fi
}

updater_write_pin() {
  local path=$1
  local version=$2
  local commit=$3
  local dir tmp timestamp

  dir=$(dirname "$path")
  updater_prepare_private_dir "$dir" || return 1
  tmp=$(mktemp "$dir/.updater-pin.tmp.XXXXXX") || {
    UPDATER_VERIFY_REASON="cannot create atomic pin temporary file beside: $path"
    return 1
  }
  chmod 600 "$tmp" || {
    rm -f "$tmp"
    UPDATER_VERIFY_REASON="cannot set mode 0600 on pin temporary file: $tmp"
    return 1
  }
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! printf '{"version":"%s","commit":"%s","updated_at":"%s"}\n' "$version" "$commit" "$timestamp" >"$tmp"; then
    rm -f "$tmp"
    UPDATER_VERIFY_REASON="cannot write pin temporary file for: $path"
    return 1
  fi
  if ! mv -f "$tmp" "$path" || ! chmod 600 "$path"; then
    rm -f "$tmp"
    UPDATER_VERIFY_REASON="cannot atomically replace pin file: $path"
    return 1
  fi
}

updater_read_pin() {
  local path=$1
  local line line_count version commit timestamp
  local pin_regex='^\{"version":"(v[0-9]+\.[0-9]+\.[0-9]+)","commit":"([0-9a-f]{40})","updated_at":"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)"\}$'

  if [[ -L "$path" || ! -f "$path" || ! -r "$path" ]]; then
    UPDATER_VERIFY_REASON="updater pin file is unreadable: $path"
    return 1
  fi
  IFS= read -r line <"$path" || {
    UPDATER_VERIFY_REASON="updater pin file is unparsable or malformed: $path"
    return 1
  }
  line_count=$(wc -l <"$path" | tr -d '[:space:]')
  if [[ "$line_count" != 1 || ! "$line" =~ $pin_regex ]]; then
    UPDATER_VERIFY_REASON="updater pin file is unparsable or malformed: $path"
    return 1
  fi
  version=${BASH_REMATCH[1]}
  commit=${BASH_REMATCH[2]}
  timestamp=${BASH_REMATCH[3]}
  if [[ ! "$timestamp" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$ ]]; then
    UPDATER_VERIFY_REASON="updater pin file is unparsable or malformed: $path"
    return 1
  fi
  UPDATER_FLOOR_VERSION=$version
  UPDATER_FLOOR_COMMIT=$commit
}

updater_load_or_seed_floor() {
  local repo=$1
  local path=$2
  local prefetch_head=$3
  local ledger=$4
  local persist_seed=${5:-1}
  local repo_name tag recorded_commit

  if [[ -e "$path" || -L "$path" ]]; then
    updater_read_pin "$path"
    return $?
  fi

  repo_name=$(updater_repo_name "$repo")
  tag=$(awk -v repo="$repo_name" '
    NF == 5 && $3 == repo && $5 == "ok" {tag=$4}
    END {if (tag != "") print tag}
  ' "$ledger" 2>/dev/null || true)
  if [[ -z "$tag" ]] || ! updater_is_semver "$tag"; then
    UPDATER_VERIFY_REASON="updater pin is absent and the install ledger has no usable ok entry for this repository; bootstrap with scripts/updater-bootstrap: $path"
    return 1
  fi

  recorded_commit=$(git -C "$repo" rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)
  if [[ "$recorded_commit" != "$prefetch_head" ]]; then
    UPDATER_VERIFY_REASON="updater pin is absent and the install ledger tag does not point at pre-fetch HEAD; bootstrap with scripts/updater-bootstrap: $path"
    return 1
  fi

  if [[ "$persist_seed" -eq 1 ]]; then
    updater_write_pin "$path" "$tag" "$prefetch_head" || return 1
  fi
  UPDATER_FLOOR_VERSION=$tag
  UPDATER_FLOOR_COMMIT=$prefetch_head
}

updater_is_moved_tag_ineligible() {
  local path=$1
  local name=$2

  [[ -f "$path" ]] && awk -v name="$name" \
    '$1 == name && $3 == "moved-tag" {found=1; exit} END {exit found ? 0 : 1}' "$path"
}

# Moved-tag records are the only persistent selection exclusion. Verification
# failures in this same append-only log are report-dedupe state and are retried.
updater_mark_ineligible() {
  local path=$1
  local name=$2
  local reason=$3
  local dir timestamp

  if updater_is_moved_tag_ineligible "$path" "$name"; then
    return 1
  fi
  dir=$(dirname "$path")
  updater_prepare_private_dir "$dir" || return 2
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! printf '%s %s %s\n' "$name" "$timestamp" "$reason" >>"$path" || ! chmod 600 "$path"; then
    UPDATER_VERIFY_REASON="cannot append updater ineligible record: $path"
    return 2
  fi
  return 0
}

updater_has_verification_failure() {
  local path=$1
  local name=$2

  [[ -f "$path" ]] && awk -v name="$name" '
    $1 == name {
      if ($3 == "verification-failure") active=1
      else if ($3 == "verification-failure-cleared") active=0
    }
    END {exit active ? 0 : 1}
  ' "$path"
}

# Returns 0 when a new record was appended, 1 when an active record already
# deduplicates this name, and 2 on a state-file failure.
updater_mark_verification_failure() {
  local path=$1
  local name=$2
  local reason=$3
  local dir timestamp

  if updater_has_verification_failure "$path" "$name"; then
    return 1
  fi
  dir=$(dirname "$path")
  updater_prepare_private_dir "$dir" || return 2
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! printf '%s %s verification-failure %s\n' "$name" "$timestamp" "$reason" >>"$path" \
    || ! chmod 600 "$path"; then
    UPDATER_VERIFY_REASON="cannot append updater verification-failure record: $path"
    return 2
  fi
  return 0
}

# Clearing is represented by another record so the state file remains
# append-only. Returns 0 when appended, 1 when there was nothing active to
# clear, and 2 on a state-file failure.
updater_clear_verification_failure() {
  local path=$1
  local name=$2
  local dir timestamp

  if ! updater_has_verification_failure "$path" "$name"; then
    return 1
  fi
  dir=$(dirname "$path")
  updater_prepare_private_dir "$dir" || return 2
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! printf '%s %s verification-failure-cleared\n' "$name" "$timestamp" >>"$path" \
    || ! chmod 600 "$path"; then
    UPDATER_VERIFY_REASON="cannot append updater verification-failure clear record: $path"
    return 2
  fi
  return 0
}

updater_has_install_failure() {
  local path=$1
  local name=$2
  local commit=$3

  [[ -f "$path" ]] && awk -v name="$name" -v commit="$commit" \
    '$1 == name && $3 == "install-failure" && $4 == commit {found=1; exit}
     END {exit found ? 0 : 1}' "$path"
}

# Install failures are selection exclusions for one exact release identity.
# A different commit OID is a different pair and is not suppressed here.
updater_mark_install_failure() {
  local path=$1
  local name=$2
  local commit=$3
  local dir timestamp

  if updater_has_install_failure "$path" "$name" "$commit"; then
    return 1
  fi
  dir=$(dirname "$path")
  updater_prepare_private_dir "$dir" || return 2
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! printf '%s %s install-failure %s\n' "$name" "$timestamp" "$commit" >>"$path" \
    || ! chmod 600 "$path"; then
    UPDATER_VERIFY_REASON="cannot append updater install-failure record: $path"
    return 2
  fi
  return 0
}

updater_remote_oid_for() {
  local records=$1
  local wanted=$2
  local name oid

  while IFS=$'\t' read -r name oid; do
    if [[ "$name" == "$wanted" ]]; then
      printf '%s\n' "$oid"
      return 0
    fi
  done <<<"$records"
  return 1
}

updater_remote_record_name() {
  local line=$1
  local ref=$2
  local name hash

  if [[ "$ref" == refs/tags/* ]]; then
    name=${ref#refs/tags/}
  fi
  if [[ -n "${name:-}" && "$name" != *[[:space:]]* ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  hash=$(printf '%s' "$line" | git hash-object --stdin) || return 1
  printf 'remote-record-%s\n' "${hash:0:12}"
}

# Record and report a remote-listing failure once per offending name. Returns
# nonzero so the caller preserves the contract's fail-closed stop.
updater_fail_remote_listing() {
  local path=$1
  local name=$2
  local reason=$3
  local dry_run=$4
  local mark_rc

  UPDATER_VERIFY_REASON=$reason
  if [[ "$dry_run" -eq 1 ]]; then
    return 1
  fi
  if ! declare -F updater_report_ineligible >/dev/null 2>&1; then
    UPDATER_VERIFY_REASON="updater reporting callback is unavailable for: $reason"
    return 1
  fi
  if updater_mark_verification_failure "$path" "$name" "$reason"; then
    updater_report_ineligible "$name" "$reason"
    UPDATER_SYNC_FAILURE_HANDLED=1
  else
    mark_rc=$?
    if [[ "$mark_rc" -eq 1 ]]; then
      UPDATER_SYNC_FAILURE_HANDLED=1
    fi
  fi
  return 1
}

# Fetches branches without tags, validates the remote tag listing, identifies
# moved names, then installs all absent tag refs in one atomic ref-update batch.
# A failed atomic fetch can leave unreachable objects, but it installs no new
# refs/tags; object-store cleanup is git gc housekeeping, not a trust property.
updater_sync_remote_tags() {
  local repo=$1
  local ineligible_path=$2
  local dry_run=${3:-0}
  local output line oid ref name extra local_oid mark_rc reason record_name
  local names= records= candidates=
  local -a refspecs

  UPDATER_MOVED_TAGS=
  UPDATER_SYNC_FAILURE_HANDLED=0

  if ! git -C "$repo" fetch --no-tags --prune origin '+refs/heads/*:refs/remotes/origin/*'; then
    UPDATER_VERIFY_REASON="branch fetch failed"
    return 1
  fi
  if ! output=$(git -C "$repo" ls-remote --refs --tags origin); then
    UPDATER_VERIFY_REASON="git ls-remote --refs --tags origin failed"
    return 1
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    oid= ref= extra=
    IFS=$'\t' read -r oid ref extra <<<"$line"
    if [[ -n "$extra" || ! "$oid" =~ ^[0-9a-f]{40}$ || "$ref" != refs/tags/* || "$ref" == *'^{}' ]]; then
      reason="unparsable remote tag record: $line"
      record_name=$(updater_remote_record_name "$line" "$ref") || record_name=remote-record-unavailable
      updater_fail_remote_listing "$ineligible_path" "$record_name" "$reason" "$dry_run"
      return 1
    fi
    name=${ref#refs/tags/}
    if ! updater_is_semver "$name"; then
      printf 'family-updater: skipping non-semver remote tag name: %s\n' "$name"
      continue
    fi
    if printf '%s\n' "$names" | grep -Fxq "$name"; then
      reason="duplicate remote tag name: $name"
      updater_fail_remote_listing "$ineligible_path" "$name" "$reason" "$dry_run"
      return 1
    fi
    names=${names:+$names$'\n'}$name
    records=${records:+$records$'\n'}$name$'\t'$oid
  done <<<"$output"

  while IFS=$'\t' read -r name oid; do
    [[ -n "$name" ]] || continue
    if local_oid=$(git -C "$repo" show-ref --verify --hash "refs/tags/$name" 2>/dev/null); then
      if [[ "$local_oid" != "$oid" ]]; then
        UPDATER_MOVED_TAGS=${UPDATER_MOVED_TAGS:+$UPDATER_MOVED_TAGS$'\n'}$name
        if [[ "$dry_run" -eq 1 ]]; then
          continue
        fi
        if ! declare -F updater_report_ineligible >/dev/null 2>&1; then
          UPDATER_VERIFY_REASON="updater reporting callback is unavailable for moved tag: $name"
          return 1
        fi
        updater_mark_ineligible "$ineligible_path" "$name" "moved-tag" || mark_rc=$?
        mark_rc=${mark_rc:-0}
        if [[ "$mark_rc" -eq 0 ]]; then
          updater_report_ineligible "$name" "moved tag: local $local_oid differs from remote $oid"
        elif [[ "$mark_rc" -eq 2 ]]; then
          return 1
        fi
        mark_rc=
      fi
    else
      candidates=${candidates:+$candidates$'\n'}$name
    fi
  done <<<"$records"

  refspecs=()
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    refspecs+=("refs/tags/$name:refs/tags/$name")
  done <<<"$candidates"
  if (( ${#refspecs[@]} > 0 )); then
    if ! git -C "$repo" fetch --atomic --no-tags origin "${refspecs[@]}"; then
      UPDATER_VERIFY_REASON="atomic candidate tag fetch failed; no new tag refs were installed"
      return 1
    fi
  fi

  UPDATER_REMOTE_TAGS=$records
}

updater_header_from_object() {
  local object=$1
  local output_var=$2
  local line header_value=

  while IFS= read -r line; do
    [[ -n "$line" ]] || break
    header_value=${header_value:+$header_value$'\n'}$line
  done <<<"$object"
  printf -v "$output_var" '%s' "$header_value"
}

# B-ALG steps 2-4. The ref is resolved exactly once here. Every later object
# operation uses the captured tag-object OID or peeled commit OID.
updater_capture_verify_and_bind() {
  local repo=$1
  local name=$2
  local allowed_signers=$3
  local tag_oid type commit object header line embedded= epoch= tag_count=0

  if ! tag_oid=$(git -C "$repo" rev-parse --verify "refs/tags/$name"); then
    UPDATER_VERIFY_REASON="cannot capture tag ref: $name"
    return 1
  fi
  type=$(git -C "$repo" cat-file -t "$tag_oid" 2>/dev/null || true)
  if [[ "$type" != tag ]]; then
    UPDATER_VERIFY_REASON="tag is lightweight or not annotated: $name"
    return 1
  fi
  if ! commit=$(git -C "$repo" rev-parse --verify "$tag_oid^{commit}"); then
    UPDATER_VERIFY_REASON="annotated tag does not peel to a commit: $name"
    return 1
  fi
  if ! git -C "$repo" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$allowed_signers" verify-tag "$tag_oid" >/dev/null 2>&1; then
    UPDATER_VERIFY_REASON="SSH signature verification failed: $name"
    return 1
  fi
  if ! object=$(git -C "$repo" cat-file tag "$tag_oid"); then
    UPDATER_VERIFY_REASON="cannot read verified tag object: $name"
    return 1
  fi
  updater_header_from_object "$object" header
  while IFS= read -r line; do
    if [[ "$line" == 'tag '* ]]; then
      embedded=${line#tag }
      tag_count=$((tag_count + 1))
    elif [[ "$line" =~ ^tagger\ .*\ ([0-9]+)\ [+-][0-9]{4}$ ]]; then
      epoch=${BASH_REMATCH[1]}
    fi
  done <<<"$header"
  if [[ "$tag_count" -ne 1 || "$embedded" != "$name" ]]; then
    UPDATER_VERIFY_REASON="verified tag object name does not exactly match ref $name (embedded: ${embedded:-missing})"
    return 1
  fi
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    UPDATER_VERIFY_REASON="verified tag has no usable tagger timestamp: $name"
    return 1
  fi

  UPDATER_CAPTURED_TAG=$name
  UPDATER_CAPTURED_TAG_OID=$tag_oid
  UPDATER_CAPTURED_COMMIT=$commit
  UPDATER_CAPTURED_EPOCH=$epoch
}

# B-ALG step 5. Equality binds the version to the recorded commit identity.
updater_check_floor() {
  local name=$1
  local commit=$2
  local comparison

  comparison=$(updater_semver_compare "$name" "$UPDATER_FLOOR_VERSION")
  if [[ "$comparison" -lt 0 ]]; then
    UPDATER_VERIFY_REASON="tag $name is below installed floor $UPDATER_FLOOR_VERSION"
    return 1
  fi
  if [[ "$comparison" -eq 0 && "$commit" != "$UPDATER_FLOOR_COMMIT" ]]; then
    UPDATER_VERIFY_REASON="tag $name equals floor version but commit differs from recorded OID"
    return 1
  fi
}

# B-ALG step 6. Checkout and the identity assertion both use the captured OID.
updater_checkout_captured_commit() {
  local repo=$1
  local commit=$2
  local head

  if ! git -C "$repo" checkout --detach "$commit" >/dev/null; then
    UPDATER_VERIFY_REASON="checkout of captured commit $commit failed"
    return 1
  fi
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
  if [[ "$head" != "$commit" ]]; then
    UPDATER_VERIFY_REASON="checkout identity mismatch: expected $commit, found ${head:-unreadable}"
    return 1
  fi
}
