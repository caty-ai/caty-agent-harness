---
id: tr-tiny-budget
title: tiny budget task runner fixture
issued_by: test
created: 2026-07-04T00:00:01Z
attempts_budget: 4
time_budget_min: 0
escalate_to: test
verify: mechanical
parent_id: null
---

## Goal
Exercise active time budget exhaustion.

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
