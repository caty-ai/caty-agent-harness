---
id: tr-basic
title: attempts budget fixture
issued_by: test
created: 2026-07-19T00:00:00Z
attempts_budget: 4
time_budget_min: 5
escalate_to: test
verify: mechanical
parent_id: null
---

## Goal
Exercise attempts-budget precedence with changing gate evidence.

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

## Resources
none

## Non-goals
none
