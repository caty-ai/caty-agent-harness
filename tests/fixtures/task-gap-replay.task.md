---
id: tr-gap
title: gap replay fixture
issued_by: test
created: 2026-07-19T00:00:00Z
attempts_budget: 5
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal
Exercise replay of a failed mechanical gate.

## Done-when
```donecheck
cat "$ARTIFACT_DIR/gate-output"
exit 1
```

## Step plan
1. Make a first attempt.
2. Make a second attempt.
3. Make a third attempt.
4. Make a fourth attempt.
5. Make a fifth attempt.

## Resources
none

## Non-goals
none
