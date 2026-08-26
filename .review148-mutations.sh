#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TMP_ROOT=$(mktemp -d /tmp/review148-mutations.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
mkdir -p "$TMP_ROOT/base"
git -C "$ROOT" archive HEAD | tar -x -C "$TMP_ROOT/base"

run_case() {
  local name=$1
  local case_dir=$TMP_ROOT/$name
  cp -R "$TMP_ROOT/base" "$case_dir"
  shift
  if ! (cd "$case_dir" && "$@"); then
    printf '%s mutation_failed\n' "$name"
    return
  fi
  (cd "$case_dir" && bash tests/raw-review.test.sh) >"$TMP_ROOT/$name.out" 2>&1
  local rc=$?
  printf '%s rc=%s summary=%s\n' "$name" "$rc" "$(tail -n 1 "$TMP_ROOT/$name.out")"
  grep '^FAIL ' "$TMP_ROOT/$name.out" | head -n 4 || true
}

mutate_stub_call() {
  perl -0pi -e 's/if run_with_timeout "\$reviewer_timeout_s" "\$reviewer_output" "\$\{reviewer_argv\[@\]\}"; then/if true; then/' scripts/raw-review.sh
  grep -Fq 'if true; then' scripts/raw-review.sh
}

mutate_vacuous_accept() {
  perl -0pi -e 's/    nonblank = \[line for line in lines if line\.strip\(\)\]\n    if nonblank != \["NO_GROUPS:"\]:\n        raise SystemExit\(1\)\n//' scripts/raw-review.sh
  ! grep -Fq 'nonblank != ["NO_GROUPS:"]' scripts/raw-review.sh
}

mutate_drop_evictions() {
  perl -0pi -e 's/(  file_basename=\$\{raw_path##\*\/\}\n)/$1  [[ "$file_basename" == intake-evictions-* ]] \&\& continue\n/' scripts/raw-week.sh
  grep -Fq 'file_basename" == intake-evictions-*' scripts/raw-week.sh
}

mutate_truncate_prompt() {
  perl -0pi -e 's/    cat "\$workspace\/\$relative_path"/    head -c 20 "\$workspace\/\$relative_path"/' scripts/raw-review.sh
  grep -Fq 'head -c 20' scripts/raw-review.sh
}

mutate_notify_overwrite() {
  perl -0pi -e 's/  \} >>"\$notification_file"/  } >"\$notification_file"/' scripts/raw-review.sh
  grep -Fq '} >"$notification_file"' scripts/raw-review.sh
}

run_case requested_stub_review_call mutate_stub_call
run_case requested_vacuous_accept mutate_vacuous_accept
run_case own_drop_evictions mutate_drop_evictions
run_case own_truncate_prompt mutate_truncate_prompt
run_case own_notify_overwrite mutate_notify_overwrite
