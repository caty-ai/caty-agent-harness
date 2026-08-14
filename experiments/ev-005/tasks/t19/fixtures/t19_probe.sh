#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

ROOT=$(pwd)
MODE=${1:-}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t19.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

workspace="$TMP_ROOT/workspace"
mkdir -p "$workspace/loop/.deadman" || exit 1
printf '# State\n## Open failures\n## Last session\n' >"$workspace/STATE.md" || exit 1

wrapper="$TMP_ROOT/cron-wrapper.sh"
cp templates/cron-wrapper.tmpl.sh "$wrapper" || exit 1
chmod +x "$wrapper" || exit 1

target="$TMP_ROOT/target.sh"
cat >"$target" <<'EOF'
#!/bin/bash
printf '%s\n' "${SAFE_VALUE-unset}" >"$TARGET_OUTPUT"
printf 'ran\n' >"$TARGET_RAN"
EOF
chmod +x "$target" || exit 1
export TARGET_OUTPUT="$TMP_ROOT/target.out"
export TARGET_RAN="$TMP_ROOT/target.ran"

run_wrapper() {
  secrets=$1
  set +e
  TARGET="$target" CATY_HARNESS_ROOT="$ROOT" CATY_WORKSPACE="$workspace" \
    SECRETS_ENV="$secrets" "$wrapper" \
    >"$TMP_ROOT/wrapper.out" 2>"$TMP_ROOT/wrapper.err"
  wrapper_rc=$?
  set -e
}

case "$MODE" in
  assignment)
    secrets="$TMP_ROOT/assignment.env"
    printf 'SAFE_VALUE=plain-value\n' >"$secrets"
    chmod 600 "$secrets"
    run_wrapper "$secrets"
    [ "$wrapper_rc" -eq 0 ] \
      && [ "$(cat "$TARGET_OUTPUT" 2>/dev/null)" = plain-value ]
    ;;
  inert)
    side_effect="$TMP_ROOT/would-have-run"
    secrets="$TMP_ROOT/inert.env"
    printf 'SAFE_VALUE=$(touch "%s")\n' "$side_effect" >"$secrets"
    chmod 600 "$secrets"
    run_wrapper "$secrets"
    expected='$(touch "'"$side_effect"'")'
    [ "$wrapper_rc" -eq 0 ] \
      && [ ! -e "$side_effect" ] \
      && [ "$(cat "$TARGET_OUTPUT" 2>/dev/null)" = "$expected" ]
    ;;
  symlink)
    source_file="$TMP_ROOT/source.env"
    secrets="$TMP_ROOT/link.env"
    printf 'SAFE_VALUE=plain-value\n' >"$source_file"
    chmod 600 "$source_file"
    ln -s "$source_file" "$secrets"
    run_wrapper "$secrets"
    [ "$wrapper_rc" -ne 0 ] \
      && [ ! -e "$TARGET_RAN" ] \
      && grep -Fq 'SECRETS_ENV' "$TMP_ROOT/wrapper.err" \
      && grep -Fqi 'symlink' "$TMP_ROOT/wrapper.err"
    ;;
  *)
    exit 2
    ;;
esac
