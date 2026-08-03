---
id: img-pilot-20260706-001
title: Generate and deliver pilot PNG image
issued_by: sho-alpha
created: 2026-07-06T00:00:00Z
attempts_budget: 8
time_budget_min: 60
escalate_to: sho
verify: mechanical
parent_id: null
---

## Goal

Generate one pilot PNG image through the Luca image-generation workflow and deliver it with a captured receipt.

## Done-when

```donecheck
test -s "$ARTIFACT_DIR/out/image.png" || { echo "FAIL: image exists"; exit 1; }
head -c8 "$ARTIFACT_DIR/out/image.png" | grep -q $'\x89PNG' || { echo "FAIL: PNG magic bytes"; exit 1; }
test -s "$ARTIFACT_DIR/out/delivery-receipt.json" || { echo "FAIL: delivery receipt exists"; exit 1; }
```

## Step plan

1. Create the image request sidecar at "$ARTIFACT_DIR/out/image-request.json" before calling the backend.
2. Generate the image and save it to "$ARTIFACT_DIR/out/image.png".
3. Inspect "$ARTIFACT_DIR/out/image.png" with the PNG magic-byte check from Done-when.
4. deliver + capture receipt in "$ARTIFACT_DIR/out/delivery-receipt.json".

## Resources

- ARTIFACT_DIR
- FAMILY_PUSH_CHANNEL
- LUCA_IMAGE_BACKEND

## Non-goals

- Do not create alternate image formats.
- Do not perform vision-rubric scoring.
- Do not modify workspace state outside the named artifact paths.
