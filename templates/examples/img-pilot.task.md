---
id: img-pilot-20260706-001
title: Generate and deliver a local SVG image card
issued_by: example-operator
created: 2026-07-06T00:00:00Z
attempts_budget: 8
time_budget_min: 60
escalate_to: example-operator
verify: mechanical
parent_id: null
receipt: out/delivery-receipt.json
---

## Goal

Generate a self-contained SVG image card using only local tools, then deliver it with a JSON receipt.

## Done-when

```donecheck
test -s "$ARTIFACT_DIR/out/image.svg" || { echo "FAIL: SVG image exists"; exit 1; }
grep -Fq '<svg xmlns="http://www.w3.org/2000/svg"' "$ARTIFACT_DIR/out/image.svg" || { echo "FAIL: SVG root element"; exit 1; }
grep -Fq 'Caty Agent Harness image pilot' "$ARTIFACT_DIR/out/image.svg" || { echo "FAIL: image pilot label"; exit 1; }
test -s "$ARTIFACT_DIR/out/delivery-receipt.json" || { echo "FAIL: delivery receipt exists"; exit 1; }
python3 - "$ARTIFACT_DIR/out/delivery-receipt.json" "$TASK_ID" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    receipt = json.load(handle)
expected = {
    "artifact": "out/image.svg",
    "status": "delivered",
    "task_id": sys.argv[2],
}
if receipt != expected:
    raise SystemExit("FAIL: delivery receipt content")
PY
```

## Step plan

1. Use bash or Python 3's standard library to create a self-contained image card at "$ARTIFACT_DIR/out/image.svg"; include an SVG root element and the visible text `Caty Agent Harness image pilot`.
2. Validate the SVG with the Done-when checks, then deliver + capture a JSON receipt at "$ARTIFACT_DIR/out/delivery-receipt.json" with exactly the keys and values checked above.

## Resources

- ARTIFACT_DIR
- bash
- python3 standard library

## Non-goals

- Do not call network services or image-generation backends.
- Do not create alternate image formats.
- Do not modify workspace state outside the named artifact paths.
