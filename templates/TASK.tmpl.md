---
id: {{TASK_ID}}
title: {{TITLE}}
issued_by: example-operator
created: {{CREATED_UTC}}
attempts_budget: 8
time_budget_min: 30
escalate_to: example-operator
verify: mechanical
parent_id: null
---

## Goal

{{GOAL}}

## Done-when

<!--
donecheck contract:
- The driver runs this block with bash -euo pipefail.
- cwd is the workspace root.
- TASK_ID, TASK_FILE, and ARTIFACT_DIR are exported.
- Assertions are READ-ONLY and may not create, edit, move, or delete files.
- Runtime timeout is 60 seconds.
- stdout and stderr are captured to the attempt's donecheck.log.
- Include a delivery-receipt assertion; delivery is the terminal weak-model failure mode.
-->

```donecheck
test -s "$ARTIFACT_DIR/out/delivery-receipt.json" || { echo "FAIL: delivery receipt exists"; exit 1; }
```

## Step plan

1. {{STEP_1}}
2. deliver + capture receipt in "$ARTIFACT_DIR/out/delivery-receipt.json"

## Resources

- {{RESOURCE_PATH_OR_ENV_NAME}}

## Non-goals

- {{NON_GOAL}}

<!--
DLQ re-enqueue rule: manual re-enqueue must use a NEW id and set parent_id to the
DLQ task's id. Never reuse a DLQ id.
-->
