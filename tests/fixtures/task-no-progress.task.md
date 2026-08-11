---
id: tr-no-progress
title: no-progress stop fixture
issued_by: test
created: 2026-07-19T00:00:00Z
attempts_budget: 6
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Exercise the no-progress donecheck stop rule.

## Done-when
```donecheck
if [[ -f "$ARTIFACT_DIR/gate-pass" ]]; then
  exit 0
fi
cat "$ARTIFACT_DIR/gate-output"
if [[ -f "$ARTIFACT_DIR/gate-remove-log" ]]; then
  rm -f "$(find "$ARTIFACT_DIR/attempts" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)/donecheck.log"
fi
exit "$(cat "$ARTIFACT_DIR/gate-exit" 2>/dev/null || echo 1)"
```

## Step plan
1. Make a first attempt.
2. Make a second attempt.
3. Make a third attempt.

## Resources
none

## Non-goals
none
