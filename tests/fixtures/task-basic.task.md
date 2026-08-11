---
id: tr-basic
title: basic task runner fixture
issued_by: test
created: 2026-07-04T00:00:00Z
attempts_budget: 4
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Create a delivery receipt for the task runner fixture.

## Done-when
```donecheck
test -s "$ARTIFACT_DIR/out/delivery-receipt.json"
grep -q '"task_id"' "$ARTIFACT_DIR/out/delivery-receipt.json"
```

## Step plan
1. Write the delivery receipt.
2. Deliver + capture receipt.

## Resources
none

## Non-goals
none
