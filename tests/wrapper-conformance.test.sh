#!/usr/bin/env bash
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VERIFY_SCRIPT=$ROOT/adapters/hermes/verify-job.sh
DISTILL_SCRIPT=$ROOT/adapters/openclaw/distill-audit.sh
INSTALL_SCRIPT=$ROOT/install.sh
TMP_ROOT=${TMPDIR:-/tmp}/wrapper-conformance-test.$$
PASS_COUNT=0
FAIL_COUNT=0

source "$ROOT/tests/lib-wrapper-conformance-fixture.sh"
source "$ROOT/scripts/lib-wrapper-conformance.sh"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

make_bundle() {
  ws=$TMP_ROOT/ws-$1
  bundle=$ws/loop/artifacts/task-one
  mkdir -p "$bundle"
  printf '# State\n' >"$ws/STATE.md"
  printf 'request\n' >"$bundle/request.md"
  printf 'rubric\n' >"$bundle/rubric.md"
  printf 'result\n' >"$bundle/result.md"
  printf 'manifest\n' >"$bundle/manifest.md"
  printf 'evidence\n' >"$bundle/evidence.md"
  printf '{}\n' >"$bundle/metadata.json"
  printf '%s\n' "$bundle"
}

make_distill_ws() {
  ws=$TMP_ROOT/distill-ws-$1
  mkdir -p "$ws/loop/pending" "$ws/skills/_staging" "$ws/input"
  {
    printf '%s\n' '## Verified facts'
    printf '%s\n' '## General rules'
    printf '%s\n' '## Open failures'
    printf '%s\n' '## Lessons learned'
    printf '%s\n' '## Last session'
  } >"$ws/STATE.md"
  printf 'transcript\n' >"$ws/input/session.log"
  printf '%s\n' "$ws"
}

write_pass_verifier_wrapper() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'fixture pass'
SH
  chmod +x "$path"
}

write_waiting_verifier_wrapper() {
  path=$1
  started_file=$2
  release_file=$3
  cat >"$path" <<SH
#!/usr/bin/env bash
printf '%s\n' started >"$started_file"
while [ ! -f "$release_file" ]; do
  sleep 1
done
printf '%s\n' 'VERDICT: pass'
printf '%s\n' 'fixture pass after staged wait'
SH
  chmod +x "$path"
}

write_fail_verifier_wrapper() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: fail'
printf '%s\n' 'original wrapper replaced after staging'
SH
  chmod +x "$path"
}

write_distiller_wrapper() {
  path=$1
  cat >"$path" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
## LESSONS
- 2026-07-24 conformance distiller lesson (source: distill-audit)
## OPEN_FAILURES
## SKILL_DRAFTS
OUT
SH
  chmod +x "$path"
}

write_exec_sentinel_wrapper() {
  path=$1
  sentinel=$2
  kind=$3
  cat >"$path" <<SH
#!/usr/bin/env bash
printf '%s\n' '$kind executed' >>"$sentinel"
case "$kind" in
  verifier)
    printf '%s\n' 'VERDICT: pass'
    printf '%s\n' 'sentinel verifier pass'
    ;;
  distiller)
    cat <<'OUT'
## LESSONS
## OPEN_FAILURES
## SKILL_DRAFTS
OUT
    ;;
  *)
    printf '%s\n' 'fixture provider'
    ;;
esac
SH
  chmod +x "$path"
}

write_exec_sentinel_probe() {
  path=$1
  sentinel=$2
  cat >"$path" <<SH
#!/usr/bin/env bash
set -eu
printf '%s\n' 'probe executed' >>"$sentinel"
printf 'provider_id=%s\n' "\${PROBE_PROVIDER_ID:-fixture-provider}"
printf 'provider_version=%s\n' "\${PROBE_PROVIDER_VERSION:-fixture-v1}"
printf 'provider_path=%s\n' "\${PROBE_PROVIDER_PATH:?}"
printf '%s\n' 'provider_launch=host-staged-env'
printf '%s\n' 'provider_relocatable=pass'
printf '%s\n' 'fresh_session=pass'
printf '%s\n' 'persistence_off=pass'
printf '%s\n' 'input_mode=host-inline'
printf '%s\n' 'tool_requests=auto-deny'
printf '%s\n' 'action_requests=auto-deny'
printf '%s\n' 'permission_requests=auto-deny'
printf '%s\n' 'workspace_access=none'
SH
  chmod +x "$path"
}

attest_route_fixture() {
  route=$1
  name=$2
  wrapper_path=$3
  evidence_path=${4:-}

  provider_path=$TMP_ROOT/$name-provider.sh
  probe_path=$TMP_ROOT/$name-probe.sh
  conformance_write_provider "$provider_path"
  conformance_write_probe "$probe_path"
  conformance_attest_wrapper "$ROOT" "$route" "$wrapper_path" "$provider_path" "$probe_path" "fixture-$name" "fixture-$name-v1" "$evidence_path"
  LAST_PROVIDER_PATH=$provider_path
  LAST_PROBE_PATH=$probe_path
}

rewrite_evidence_value() {
  file=$1
  key=$2
  value=$3

  python3 - "$file" "$key" "$value" <<'PY'
import sys

path, key, value = sys.argv[1:4]
lines = open(path, encoding="utf-8").read().splitlines()
written = False
with open(path, "w", encoding="utf-8") as target:
    for line in lines:
        if line.startswith(f"{key}="):
            target.write(f"{key}={value}\n")
            written = True
        else:
            target.write(f"{line}\n")
if not written:
    raise SystemExit(1)
PY
}

remove_evidence_key() {
  file=$1
  key=$2

  python3 - "$file" "$key" <<'PY'
import sys

path, key = sys.argv[1:3]
lines = open(path, encoding="utf-8").read().splitlines()
with open(path, "w", encoding="utf-8") as target:
    for line in lines:
        if not line.startswith(f"{key}="):
            target.write(f"{line}\n")
PY
}

expect_library_failure() {
  name=$1
  route=$2
  wrapper_path=$3
  evidence_path=$4
  needle=$5

  set +e
  wrapper_conformance_readonly "$route" TEST_CMD "$wrapper_path" "$evidence_path"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && printf '%s\n' "$WRAPPER_CONFORMANCE_REASON" | grep -Fq "$needle"; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc reason=$WRAPPER_CONFORMANCE_REASON"
  fi
}

expect_library_success() {
  name=$1
  route=$2
  wrapper_path=$3
  evidence_path=$4

  set +e
  wrapper_conformance_readonly "$route" TEST_CMD "$wrapper_path" "$evidence_path"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    pass "$name"
  else
    fail_case "$name" "rc=$rc reason=$WRAPPER_CONFORMANCE_REASON"
  fi
}

bundle=$(make_bundle missing-evidence)
wrapper=$TMP_ROOT/missing-evidence-wrapper.sh
write_pass_verifier_wrapper "$wrapper"
set +e
output=$(VERIFIER_CMD="$wrapper" bash "$VERIFY_SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 5 ] \
  && printf '%s\n' "$output" | grep -q 'wrapper conformance failed: missing evidence' \
  && [ ! -e "$TMP_ROOT/ws-missing-evidence/loop/VERIFY.log.md" ]; then
  pass "missing conformance evidence blocks an existing verifier wrapper"
else
  fail_case "missing conformance evidence blocks an existing verifier wrapper" "rc=$rc output=$output"
fi

bundle=$(make_bundle missing-evidence-and-artifact)
wrapper=$TMP_ROOT/missing-evidence-and-artifact-wrapper.sh
write_pass_verifier_wrapper "$wrapper"
rm "$bundle/metadata.json"
set +e
output=$(VERIFIER_CMD="$wrapper" bash "$VERIFY_SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 5 ] \
  && printf '%s\n' "$output" | grep -q 'wrapper conformance failed: missing evidence' \
  && [ ! -e "$TMP_ROOT/ws-missing-evidence-and-artifact/loop/VERIFY.log.md" ]; then
  pass "missing evidence fails before a missing-artifact verdict"
else
  fail_case "missing evidence fails before a missing-artifact verdict" "rc=$rc output=$output"
fi

bundle=$(make_bundle missing-evidence-and-over-cap)
wrapper=$TMP_ROOT/missing-evidence-and-over-cap-wrapper.sh
write_pass_verifier_wrapper "$wrapper"
{
  i=0
  while [ "$i" -lt 200 ]; do
    printf 'required-request-line-%04d\n' "$i"
    i=$((i + 1))
  done
} >"$bundle/request.md"
set +e
output=$(HERMES_VERIFY_BUNDLE_MAX_BYTES=1024 VERIFIER_CMD="$wrapper" bash "$VERIFY_SCRIPT" "$bundle" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 5 ] \
  && printf '%s\n' "$output" | grep -q 'wrapper conformance failed: missing evidence' \
  && [ ! -e "$TMP_ROOT/ws-missing-evidence-and-over-cap/loop/VERIFY.log.md" ]; then
  pass "missing evidence fails before an over-cap verdict"
else
  fail_case "missing evidence fails before an over-cap verdict" "rc=$rc output=$output"
fi

bundle=$(make_bundle valid-verifier)
wrapper=$TMP_ROOT/valid-verifier-wrapper.sh
evidence=$TMP_ROOT/valid-verifier.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier valid-verifier "$wrapper"
cp "${wrapper}.conformance" "$evidence"
output=$(VERIFIER_CMD="$wrapper" bash "$VERIFY_SCRIPT" "$bundle" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$output" | grep -q 'VERDICT: pass'; then
  pass "valid conformance evidence allows verifier execution"
else
  fail_case "valid conformance evidence allows verifier execution" "rc=$rc output=$output"
fi
expect_library_success "library accepts explicit evidence path" verifier "$wrapper" "$evidence"

ws=$(make_distill_ws valid-distiller)
distiller=$TMP_ROOT/valid-distiller-wrapper.sh
write_distiller_wrapper "$distiller"
attest_route_fixture distiller valid-distiller "$distiller"
output=$(DISTILLER_CMD="$distiller" bash "$DISTILL_SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -Fqx -- '- 2026-07-24 conformance distiller lesson (source: distill-audit)' "$ws/STATE.md"; then
  pass "valid conformance evidence allows distiller execution"
else
  fail_case "valid conformance evidence allows distiller execution" "rc=$rc output=$output"
fi

ws=$(make_distill_ws missing-distill-evidence)
distiller=$TMP_ROOT/missing-distill-evidence-wrapper.sh
write_distiller_wrapper "$distiller"
rm -rf "$ws/skills/_staging"
old_pending_tmp="$ws/loop/pending/.distill-old.tmp.fixture"
printf '%s\n' keep >"$old_pending_tmp"
touch -t 202001010000 "$old_pending_tmp"
before_state=$(cat "$ws/STATE.md")
set +e
output=$(DISTILLER_CMD="$distiller" bash "$DISTILL_SCRIPT" --workspace "$ws" --input "$ws/input" 2>&1)
rc=$?
set -e
after_state=$(cat "$ws/STATE.md")
if [ "$rc" -eq 3 ] \
  && printf '%s\n' "$output" | grep -q 'wrapper conformance failed: missing evidence' \
  && [ "$before_state" = "$after_state" ] \
  && ! find "$ws/loop/pending" -name 'distill-*.md' -print | grep -q . \
  && [ -f "$old_pending_tmp" ] \
  && [ ! -d "$ws/skills/_staging" ] \
  && [ ! -d "$ws/loop/.distill-state.lock" ]; then
  pass "missing distiller evidence fails before model execution or workspace mutation"
else
  fail_case "missing distiller evidence fails before model execution or workspace mutation" "rc=$rc output=$output"
fi

wrapper=$TMP_ROOT/malformed-wrapper.sh
evidence=$TMP_ROOT/malformed-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier malformed-wrapper "$wrapper" "$evidence"
printf '%s\n' 'not-a-kv-record' >"$evidence"
expect_library_failure "malformed evidence record fails closed" verifier "$wrapper" "$evidence" 'malformed evidence record'

wrapper=$TMP_ROOT/duplicate-wrapper.sh
evidence=$TMP_ROOT/duplicate-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier duplicate-wrapper "$wrapper" "$evidence"
printf '%s\n' 'route=verifier' >>"$evidence"
expect_library_failure "duplicate evidence key fails closed" verifier "$wrapper" "$evidence" 'duplicate evidence key: route'

wrapper=$TMP_ROOT/missing-field-wrapper.sh
evidence=$TMP_ROOT/missing-field-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier missing-field-wrapper "$wrapper" "$evidence"
remove_evidence_key "$evidence" provider_version
expect_library_failure "missing evidence field fails closed" verifier "$wrapper" "$evidence" 'missing evidence key: provider_version'

wrapper=$TMP_ROOT/unsupported-schema-wrapper.sh
evidence=$TMP_ROOT/unsupported-schema-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier unsupported-schema-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" schema 'fable-wrapper-conformance/v0'
expect_library_failure "unsupported schema fails closed" verifier "$wrapper" "$evidence" 'unsupported evidence schema'

wrapper=$TMP_ROOT/persistence-wrapper.sh
evidence=$TMP_ROOT/persistence-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier persistence-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" persistence_off fail
expect_library_failure "persistence enabled fails closed" verifier "$wrapper" "$evidence" 'persistence_off must equal pass'

wrapper=$TMP_ROOT/fresh-session-wrapper.sh
evidence=$TMP_ROOT/fresh-session-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier fresh-session-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" fresh_session fail
expect_library_failure "non-fresh session fails closed" verifier "$wrapper" "$evidence" 'fresh_session must equal pass'

wrapper=$TMP_ROOT/tool-requests-wrapper.sh
evidence=$TMP_ROOT/tool-requests-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier tool-requests-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" tool_requests ask
expect_library_failure "non-auto-denied tool requests fail closed" verifier "$wrapper" "$evidence" 'tool_requests must equal auto-deny'

wrapper=$TMP_ROOT/action-requests-wrapper.sh
evidence=$TMP_ROOT/action-requests-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier action-requests-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" action_requests ask
expect_library_failure "non-auto-denied action requests fail closed" verifier "$wrapper" "$evidence" 'action_requests must equal auto-deny'

wrapper=$TMP_ROOT/permission-requests-wrapper.sh
evidence=$TMP_ROOT/permission-requests-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier permission-requests-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" permission_requests ask
expect_library_failure "non-auto-denied permission requests fail closed" verifier "$wrapper" "$evidence" 'permission_requests must equal auto-deny'

wrapper=$TMP_ROOT/input-mode-wrapper.sh
evidence=$TMP_ROOT/input-mode-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier input-mode-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" input_mode transcript
expect_library_failure "non-host-inline input mode fails closed" verifier "$wrapper" "$evidence" 'input_mode must equal host-inline'

wrapper=$TMP_ROOT/provider-launch-wrapper.sh
evidence=$TMP_ROOT/provider-launch-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier provider-launch-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" provider_launch live-path
expect_library_failure "non-staged provider launch fails closed" verifier "$wrapper" "$evidence" 'provider_launch must equal host-staged-env'

wrapper=$TMP_ROOT/provider-relocatable-wrapper.sh
evidence=$TMP_ROOT/provider-relocatable-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier provider-relocatable-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" provider_relocatable fail
expect_library_failure "non-relocatable provider fails closed" verifier "$wrapper" "$evidence" 'provider_relocatable must equal pass'

wrapper=$TMP_ROOT/workspace-wrapper.sh
evidence=$TMP_ROOT/workspace-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier workspace-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" workspace_access read-only
expect_library_failure "workspace access exposure fails closed" verifier "$wrapper" "$evidence" 'workspace_access must equal none'

current_now=$(date '+%s')

wrapper=$TMP_ROOT/stale-wrapper.sh
evidence=$TMP_ROOT/stale-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier stale-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" checked_at_epoch "$((current_now - 20))"
rewrite_evidence_value "$evidence" expires_at_epoch "$((current_now - 10))"
expect_library_failure "stale evidence fails closed" verifier "$wrapper" "$evidence" 'stale evidence is not accepted'
set +e
WRAPPER_CONFORMANCE_NOW_EPOCH="$((current_now - 15))" \
  wrapper_conformance_readonly verifier TEST_CMD "$wrapper" "$evidence"
rc=$?
set -e
if [ "$rc" -ne 0 ] && printf '%s\n' "$WRAPPER_CONFORMANCE_REASON" | grep -Fq 'stale evidence is not accepted'; then
  pass "production clock cannot be overridden to revive stale evidence"
else
  fail_case "production clock cannot be overridden to revive stale evidence" "rc=$rc reason=$WRAPPER_CONFORMANCE_REASON"
fi

wrapper=$TMP_ROOT/future-wrapper.sh
evidence=$TMP_ROOT/future-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier future-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" checked_at_epoch "$((current_now + 10))"
rewrite_evidence_value "$evidence" expires_at_epoch "$((current_now + 20))"
expect_library_failure "future evidence fails closed" verifier "$wrapper" "$evidence" 'future evidence is not accepted'

wrapper=$TMP_ROOT/route-mismatch-wrapper.sh
evidence=$TMP_ROOT/route-mismatch-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier route-mismatch-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" route distiller
expect_library_failure "route mismatch fails closed" verifier "$wrapper" "$evidence" 'route mismatch'

wrapper=$TMP_ROOT/path-mismatch-wrapper.sh
evidence=$TMP_ROOT/path-mismatch-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier path-mismatch-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" wrapper_path "$TMP_ROOT/other-wrapper.sh"
expect_library_failure "wrapper path mismatch fails closed" verifier "$wrapper" "$evidence" 'wrapper path mismatch'

wrapper=$TMP_ROOT/wrapper-content-wrapper.sh
evidence=$TMP_ROOT/wrapper-content-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier wrapper-content-wrapper "$wrapper" "$evidence"
printf '%s\n' '# content changed' >>"$wrapper"
expect_library_failure "wrapper content hash mismatch fails closed" verifier "$wrapper" "$evidence" 'wrapper content hash mismatch'

wrapper=$TMP_ROOT/provider-content-wrapper.sh
evidence=$TMP_ROOT/provider-content-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier provider-content-wrapper "$wrapper" "$evidence"
printf '%s\n' '# provider changed' >>"$LAST_PROVIDER_PATH"
expect_library_failure "provider content hash mismatch fails closed" verifier "$wrapper" "$evidence" 'provider content hash mismatch'

wrapper=$TMP_ROOT/probe-content-wrapper.sh
evidence=$TMP_ROOT/probe-content-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier probe-content-wrapper "$wrapper" "$evidence"
printf '%s\n' '# probe changed' >>"$LAST_PROBE_PATH"
expect_library_failure "probe content hash mismatch fails closed" verifier "$wrapper" "$evidence" 'probe content hash mismatch'

wrapper=$TMP_ROOT/permission-wrapper.sh
evidence=$TMP_ROOT/permission-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier permission-wrapper "$wrapper" "$evidence"
chmod 666 "$evidence"
expect_library_failure "group-writable evidence fails closed" verifier "$wrapper" "$evidence" 'evidence must not be group- or world-writable'

fake_stat_bin=$TMP_ROOT/fake-stat-bin
fake_stat_log=$TMP_ROOT/fake-stat.log
mkdir -p "$fake_stat_bin"
cat >"$fake_stat_bin/stat" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >>"$fake_stat_log"
case "\$1" in
  -c)
    printf '%s %s\n' "$(id -u)" 755
    exit 0
    ;;
  -f)
    printf '%s\n' '? ?'
    exit 0
    ;;
esac
exit 1
SH
chmod +x "$fake_stat_bin/stat"
set +e
PATH="$fake_stat_bin:$PATH" wrapper_conformance_validate_trusted_file_mode wrapper_path "$wrapper"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ "$(sed -n '1p' "$fake_stat_log")" = -c ]; then
  pass "ownership probe selects GNU stat semantics before BSD fallback"
else
  fail_case "ownership probe selects GNU stat semantics before BSD fallback" "rc=$rc reason=$WRAPPER_CONFORMANCE_REASON log=$(cat "$fake_stat_log" 2>/dev/null)"
fi

wrapper=$TMP_ROOT/ttl-wrapper.sh
evidence=$TMP_ROOT/ttl-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier ttl-wrapper "$wrapper" "$evidence"
ttl_checked_at=$(sed -n 's/^checked_at_epoch=//p' "$evidence")
rewrite_evidence_value "$evidence" expires_at_epoch "$((ttl_checked_at + WRAPPER_CONFORMANCE_MAX_TTL_S + 1))"
expect_library_failure "TTL beyond seven days fails closed" verifier "$wrapper" "$evidence" 'attestation TTL exceeds 604800 seconds'

wrapper=$TMP_ROOT/overflow-wrapper.sh
evidence=$TMP_ROOT/overflow-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier overflow-wrapper "$wrapper" "$evidence"
rewrite_evidence_value "$evidence" checked_at_epoch 99999999999999999999
expect_library_failure "oversized timestamp fails closed before arithmetic" verifier "$wrapper" "$evidence" 'checked_at_epoch must be a bounded unsigned integer'

wrapper=$TMP_ROOT/unknown-key-wrapper.sh
evidence=$TMP_ROOT/unknown-key-wrapper.evidence
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier unknown-key-wrapper "$wrapper" "$evidence"
printf '%s\n' 'unexpected=true' >>"$evidence"
expect_library_failure "unknown evidence key fails closed" verifier "$wrapper" "$evidence" 'unknown evidence key: unexpected'

wrapper=$TMP_ROOT/multiline-command-wrapper.sh
write_pass_verifier_wrapper "$wrapper"
attest_route_fixture verifier multiline-command-wrapper "$wrapper"
set +e
wrapper_conformance_readonly verifier TEST_CMD "$wrapper"$'\nignored'
rc=$?
set -e
if [ "$rc" -ne 0 ] && printf '%s\n' "$WRAPPER_CONFORMANCE_REASON" | grep -Fq 'must be exactly one absolute wrapper path'; then
  pass "newline-separated command tokens fail closed"
else
  fail_case "newline-separated command tokens fail closed" "rc=$rc reason=$WRAPPER_CONFORMANCE_REASON"
fi

self_wrapper=$TMP_ROOT/self-attest-wrapper.sh
self_probe=$TMP_ROOT/self-attest-probe.sh
write_pass_verifier_wrapper "$self_wrapper"
conformance_write_probe "$self_probe"
set +e
self_output=$(
  PROBE_PROVIDER_PATH="$self_wrapper" \
    "$ROOT/scripts/attest-wrapper" --route verifier --wrapper "$self_wrapper" \
      --probe "$self_probe" 2>&1
)
self_rc=$?
set -e
if [ "$self_rc" -ne 0 ] \
  && printf '%s\n' "$self_output" | grep -Fq 'wrapper_path and provider_path must identify distinct files'; then
  pass "attester rejects wrapper self-identification as provider"
else
  fail_case "attester rejects wrapper self-identification as provider" "rc=$self_rc output=$self_output"
fi

alias_wrapper=$TMP_ROOT/alias-wrapper.sh
alias_probe=$TMP_ROOT/alias-probe.sh
write_pass_verifier_wrapper "$alias_wrapper"
ln "$alias_wrapper" "$alias_probe"
set +e
alias_output=$(
  "$ROOT/scripts/attest-wrapper" --route verifier --wrapper "$alias_wrapper" \
    --probe "$alias_probe" 2>&1
)
alias_rc=$?
set -e
if [ "$alias_rc" -ne 0 ] \
  && printf '%s\n' "$alias_output" | grep -Fq 'wrapper_path and probe_path must identify distinct files'; then
  pass "attester rejects a hard-link probe alias"
else
  fail_case "attester rejects a hard-link probe alias" "rc=$alias_rc output=$alias_output"
fi

noisy_probe_wrapper=$TMP_ROOT/noisy-probe-wrapper.sh
noisy_probe_provider=$TMP_ROOT/noisy-probe-provider.sh
noisy_probe=$TMP_ROOT/noisy-probe.sh
write_pass_verifier_wrapper "$noisy_probe_wrapper"
conformance_write_provider "$noisy_probe_provider"
cat >"$noisy_probe" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'provider_id=%s\n' fixture-provider
printf 'provider_version=%s\n' fixture-v1
printf 'provider_path=%s\n' "${PROBE_PROVIDER_PATH:?}"
printf '%s\n' 'provider_launch=host-staged-env'
printf '%s\n' 'provider_relocatable=pass'
printf '%s\n' 'fresh_session=pass'
printf '%s\n' 'persistence_off=pass'
printf '%s\n' 'input_mode=host-inline'
printf '%s\n' 'tool_requests=auto-deny'
printf '%s\n' 'action_requests=auto-deny'
printf '%s\n' 'permission_requests=auto-deny'
printf '%s\n' 'workspace_access=none'
while :; do
  printf '%s\n' 'unbounded diagnostic output' >&2
done
SH
chmod +x "$noisy_probe"
set +e
noisy_probe_start=$SECONDS
noisy_probe_output=$(
  PROBE_PROVIDER_PATH="$noisy_probe_provider" ATTEST_TIMEOUT_S=20 \
    "$ROOT/scripts/attest-wrapper" --route verifier --wrapper "$noisy_probe_wrapper" \
      --probe "$noisy_probe" 2>&1
)
noisy_probe_rc=$?
noisy_probe_elapsed=$((SECONDS - noisy_probe_start))
set -e
if [ "$noisy_probe_rc" -ne 0 ] \
  && [ "$noisy_probe_elapsed" -lt 10 ] \
  && printf '%s\n' "$noisy_probe_output" | grep -Fq 'probe stderr exceeds 4096 bytes'; then
  pass "attester terminates a probe at the stderr I/O cap"
else
  fail_case "attester terminates a probe at the stderr I/O cap" "rc=$noisy_probe_rc elapsed=$noisy_probe_elapsed output=$noisy_probe_output"
fi

collision_wrapper=$TMP_ROOT/evidence-collision-wrapper.sh
collision_provider=$TMP_ROOT/evidence-collision-provider.sh
collision_probe=$TMP_ROOT/evidence-collision-probe.sh
write_pass_verifier_wrapper "$collision_wrapper"
conformance_write_provider "$collision_provider"
conformance_write_probe "$collision_probe"
set +e
collision_output=$(
  PROBE_PROVIDER_PATH="$collision_provider" \
    "$ROOT/scripts/attest-wrapper" --route verifier --wrapper "$collision_wrapper" \
      --probe "$collision_probe" --evidence "$collision_wrapper" 2>&1
)
collision_rc=$?
set -e
if [ "$collision_rc" -ne 0 ] \
  && printf '%s\n' "$collision_output" | grep -Fq 'evidence_path must not identify the wrapper or probe' \
  && grep -Fq 'VERDICT: pass' "$collision_wrapper"; then
  pass "attester refuses to overwrite a trust input with evidence"
else
  fail_case "attester refuses to overwrite a trust input with evidence" "rc=$collision_rc output=$collision_output"
fi

provider_wrapper=$TMP_ROOT/staged-provider-wrapper.sh
provider_original=$TMP_ROOT/staged-provider-original.sh
provider_probe=$TMP_ROOT/staged-provider-probe.sh
provider_started=$TMP_ROOT/staged-provider.started
provider_release=$TMP_ROOT/staged-provider.release
provider_output=$TMP_ROOT/staged-provider.output
provider_rc_file=$TMP_ROOT/staged-provider.rc
provider_bundle=$(make_bundle staged-provider)
cat >"$provider_wrapper" <<SH
#!/usr/bin/env bash
printf '%s\n' started >"$provider_started"
while [ ! -f "$provider_release" ]; do
  sleep 1
done
"\${FABLE_CONFORMING_PROVIDER_PATH:?}"
SH
chmod +x "$provider_wrapper"
write_pass_verifier_wrapper "$provider_original"
conformance_write_probe "$provider_probe"
conformance_attest_wrapper "$ROOT" verifier "$provider_wrapper" "$provider_original" "$provider_probe" staged-provider staged-provider-v1
(
  VERIFIER_CMD="$provider_wrapper" bash "$VERIFY_SCRIPT" "$provider_bundle" >"$provider_output" 2>&1
  printf '%s\n' "$?" >"$provider_rc_file"
) &
provider_verify_pid=$!
tries=0
while [ ! -f "$provider_started" ] && [ "$tries" -lt 30 ]; do
  sleep 1
  tries=$((tries + 1))
done
write_fail_verifier_wrapper "$provider_original"
printf '%s\n' release >"$provider_release"
wait "$provider_verify_pid"
provider_rc=$(cat "$provider_rc_file")
provider_result=$(cat "$provider_output")
if [ "$provider_rc" -eq 0 ] \
  && printf '%s\n' "$provider_result" | grep -q 'VERDICT: pass' \
  && ! printf '%s\n' "$provider_result" | grep -q 'original wrapper replaced after staging'; then
  pass "provider replacement after gate does not affect the staged provider"
else
  fail_case "provider replacement after gate does not affect the staged provider" "rc=$provider_rc output=$provider_result"
fi

bundle=$(make_bundle staged-wrapper)
wrapper=$TMP_ROOT/staged-wrapper.sh
started_file=$TMP_ROOT/staged-wrapper.started
release_file=$TMP_ROOT/staged-wrapper.release
output_file=$TMP_ROOT/staged-wrapper.output
rc_file=$TMP_ROOT/staged-wrapper.rc
write_waiting_verifier_wrapper "$wrapper" "$started_file" "$release_file"
attest_route_fixture verifier staged-wrapper "$wrapper"
(
  VERIFIER_CMD="$wrapper" bash "$VERIFY_SCRIPT" "$bundle" >"$output_file" 2>&1
  printf '%s\n' "$?" >"$rc_file"
) &
verify_pid=$!
tries=0
while [ ! -f "$started_file" ] && [ "$tries" -lt 30 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ ! -f "$started_file" ]; then
  fail_case "wrapper staging barrier becomes observable" "wrapper did not start within 30 seconds"
  printf '%s\n' release >"$release_file"
fi
write_fail_verifier_wrapper "$wrapper"
printf '%s\n' 'release' >"$release_file"
wait "$verify_pid"
rc=$(cat "$rc_file")
output=$(cat "$output_file")
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'VERDICT: pass' \
  && ! printf '%s\n' "$output" | grep -q 'original wrapper replaced after staging'; then
  pass "wrapper replacement after staging does not affect the executed copy"
else
  fail_case "wrapper replacement after staging does not affect the executed copy" "rc=$rc output=$output"
fi

ws=$TMP_ROOT/install-check-ws
"$INSTALL_SCRIPT" --workspace "$ws" >/dev/null 2>&1
sentinel=$TMP_ROOT/install-check.executed
verifier_wrapper=$TMP_ROOT/install-check-verifier.sh
distiller_wrapper=$TMP_ROOT/install-check-distiller.sh
verifier_provider=$TMP_ROOT/install-check-verifier-provider.sh
distiller_provider=$TMP_ROOT/install-check-distiller-provider.sh
verifier_probe=$TMP_ROOT/install-check-verifier-probe.sh
distiller_probe=$TMP_ROOT/install-check-distiller-probe.sh
write_exec_sentinel_wrapper "$verifier_wrapper" "$sentinel" verifier
write_exec_sentinel_wrapper "$distiller_wrapper" "$sentinel" distiller
write_exec_sentinel_wrapper "$verifier_provider" "$sentinel" provider
write_exec_sentinel_wrapper "$distiller_provider" "$sentinel" provider
write_exec_sentinel_probe "$verifier_probe" "$sentinel"
write_exec_sentinel_probe "$distiller_probe" "$sentinel"
conformance_attest_wrapper "$ROOT" verifier "$verifier_wrapper" "$verifier_provider" "$verifier_probe" install-verifier install-verifier-v1
conformance_attest_wrapper "$ROOT" distiller "$distiller_wrapper" "$distiller_provider" "$distiller_probe" install-distiller install-distiller-v1
rm -f "$sentinel"
output=$(VERIFIER_CMD="$verifier_wrapper" DISTILLER_CMD="$distiller_wrapper" "$INSTALL_SCRIPT" --check --workspace "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -Fqx 'learning path: adapter=hermes | route=verifier conformance | PASS' \
  && printf '%s\n' "$output" | grep -Fqx 'learning path: adapter=openclaw | route=distiller conformance | PASS' \
  && [ ! -e "$sentinel" ]; then
  pass "install.sh --check validates conformance by reading and hashing only"
else
  fail_case "install.sh --check validates conformance by reading and hashing only" "rc=$rc output=$output sentinel=$(cat "$sentinel" 2>/dev/null)"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
