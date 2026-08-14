#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

ROOT=$(pwd)
MODE=${1:-}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ev005-t17.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

make_workspace() {
  ws=$1
  mkdir -p "$ws/loop/tasks/queue" || return 1
  printf '# State\n' >"$ws/STATE.md" || return 1
}

run_failed_push() {
  ws="$TMP_ROOT/push-ws"
  make_workspace "$ws" || return 1
  cp tests/fixtures/task-basic.task.md "$ws/loop/tasks/queue/tr-basic.task.md" || return 1
  helper="$TMP_ROOT/push-helper.sh"
  cat >"$helper" <<'EOF'
#!/bin/bash
printf 'fixture push stdout\n'
printf 'fixture push stderr\n' >&2
exit 7
EOF
  chmod +x "$helper" || return 1
  set +e
  TR_SPAWN_STEP="$ROOT/tests/fixtures/mock-spawn-step.sh" \
    TR_MOCK_BEHAVIOR=auth-error TR_PUSH_CMD="$helper" \
    bash "$ROOT/scripts/task-runner.sh" "$ws" \
    >"$TMP_ROOT/push.out" 2>"$TMP_ROOT/push.err"
  runner_rc=$?
  set -e
  dest="$ws/loop/tasks/dlq/tr-basic"
  report="$dest/REPORT.md"
  log="$dest/push.log"
}

case "$MODE" in
  push-record)
    run_failed_push || exit 1
    [ -f "$log" ] \
      && grep -Fq 'fixture push stdout' "$log" \
      && grep -Fq 'fixture push stderr' "$log" \
      && grep -Eq '^push: rc=7 ' "$log"
    ;;
  push-visible)
    run_failed_push || exit 1
    [ "$runner_rc" -eq 0 ] \
      && [ -f "$dest/push-failed" ] \
      && grep -Eq '^push: failed rc=7 ' "$report" \
      && grep -Fq 'warning: push failed rc=7:' "$TMP_ROOT/push.err"
    ;;
  timeout)
    ws="$TMP_ROOT/timeout-ws"
    make_workspace "$ws" || exit 1
    cat >"$ws/loop/tasks/queue/tr-timeout.task.md" <<'EOF'
---
id: tr-timeout
title: configurable timeout fixture
issued_by: test
created: 2000-01-01T00:00:00Z
attempts_budget: 4
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
---

## Goal
Exercise the completion-gate timeout.

## Done-when
```donecheck
sleep 3
test -e "$ARTIFACT_DIR/out/never-created"
```

## Step plan
1. Wait for the configured timeout.
EOF
    set +e
    TR_SPAWN_STEP="$ROOT/tests/fixtures/mock-spawn-step.sh" \
      TR_MOCK_BEHAVIOR=success TR_DONECHECK_TIMEOUT_S=1 \
      bash "$ROOT/scripts/task-runner.sh" "$ws" >/dev/null 2>&1
    set -e
    reason="$ws/loop/artifacts/tr-timeout/attempts/001/verify-reason"
    log="$ws/loop/artifacts/tr-timeout/attempts/001/donecheck.log"
    grep -Fqx 'donecheck timed out after 1s' "$reason" \
      && grep -Fqx 'donecheck timed out after 1s' "$log"
    ;;
  metrics)
    ws="$TMP_ROOT/metrics-ws"
    mkdir -p "$ws/loop/tasks/delivered" "$ws/loop/tasks/dlq" || exit 1
    bash "$ROOT/scripts/tr-metrics.sh" "$ws" >/dev/null 2>&1 || exit 1
    [ -f "$ws/METRICS.md" ] && ! grep -Fq '| B0 | estimate |' "$ws/METRICS.md"
    ;;
  *)
    exit 2
    ;;
esac
