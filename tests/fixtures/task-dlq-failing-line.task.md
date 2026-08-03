---
id: tr-failing-line
title: failing donecheck line fixture
issued_by: test
created: 2026-07-20T00:00:00Z
attempts_budget: 4
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
---

## Goal
Exercise DLQ reporting of the actual failed donecheck assertion.

## Done-when
```donecheck
test -s "$ARTIFACT_DIR/out/delivery-receipt.json"
test -s "$ARTIFACT_DIR/out/missing-receipt.json"
```

## Step plan
1. Write the delivery receipt.

## Resources
none

## Non-goals
none
