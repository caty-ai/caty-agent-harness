---
id: tr-time-boundary
title: time boundary task runner fixture
issued_by: test
created: 2026-07-23T00:00:00Z
attempts_budget: 4
time_budget_min: 10
escalate_to: test
verify: mechanical
parent_id: null
---

## Goal
Exercise the nonzero active-time budget boundary.

## Done-when
```donecheck
test -s "$ARTIFACT_DIR/out/delivery-receipt.json"
grep -q '"task_id"' "$ARTIFACT_DIR/out/delivery-receipt.json"
```

## Step plan
1. Try work without satisfying the donecheck.
2. Deliver + capture receipt.

## Resources
none

## Non-goals
none
