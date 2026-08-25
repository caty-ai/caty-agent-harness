#!/usr/bin/env python3
"""This file is the evidence; the prose is the claim.

If they disagree, the documentation is wrong.
"""

import hashlib
import json
import sys
from pathlib import Path


AGGREGATE_PATH = Path(__file__).resolve().parent / "ev006-aggregate.json"
EXPECTED_SHA256 = "61dad2cb43a11ce8ae9f6b0e82d492c71b6b46eae27a07418fd90fa673cf3848"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def percentage(part, whole):
    return round(100 * part / whole)


def ratio(part, whole):
    return f"{part}/{whole} ({percentage(part, whole)}%)"


def percent_change(part, whole):
    return f"{100 * (part / whole - 1):+.1f}%".replace("-", "−")


def main():
    try:
        aggregate_bytes = AGGREGATE_PATH.read_bytes()
    except FileNotFoundError:
        return fail(f"benchmark aggregate is missing: {AGGREGATE_PATH}")
    except OSError as exc:
        return fail(f"cannot read benchmark aggregate {AGGREGATE_PATH}: {exc}")

    actual_sha256 = hashlib.sha256(aggregate_bytes).hexdigest()
    # An edited aggregate must not quietly produce different numbers under the
    # same filename.
    if actual_sha256 != EXPECTED_SHA256:
        return fail(
            "benchmark aggregate sha256 mismatch\n"
            f"expected: {EXPECTED_SHA256}\n"
            f"actual:   {actual_sha256}\n"
            "Numbers from an unverified aggregate are a claim, not evidence."
        )

    try:
        cells = json.loads(aggregate_bytes)["cells"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        return fail(f"verified benchmark aggregate has invalid cell data: {exc}")

    arms = ("bare", "harness")
    overflow = {
        arm: [
            cell
            for cell in cells
            if cell["arm"] == arm and cell["tier"] in ("M", "L")
        ]
        for arm in arms
    }

    print("Primary result (M/L pooled)")
    for arm in arms:
        arm_cells = overflow[arm]
        print(
            f"  {arm} verified completion: "
            f"{ratio(sum(cell['resolved'] for cell in arm_cells), len(arm_cells))}"
        )
    for arm in arms:
        arm_cells = overflow[arm]
        unread_claims = sum(cell["n_claims_coverage_gap"] for cell in arm_cells)
        claims = sum(cell["n_claims"] for cell in arm_cells)
        print(f"  {arm} unread completion claims: {ratio(unread_claims, claims)}")

    print("Verified completion by size")
    for tier in ("S", "M", "L"):
        results = []
        for arm in arms:
            arm_cells = [
                cell
                for cell in cells
                if cell["arm"] == arm and cell["tier"] == tier
            ]
            resolved = sum(cell["resolved"] for cell in arm_cells)
            results.append(f"{arm} {ratio(resolved, len(arm_cells))}")
        print(f"  {tier}: {', '.join(results)}")

    print("EV-006 charge tokens")
    for label, tiers in (("M", ("M",)), ("L", ("L",)), ("M/L pooled", ("M", "L"))):
        totals = {
            arm: sum(
                cell["charge_tokens"]
                for cell in cells
                if cell["arm"] == arm and cell["tier"] in tiers
            )
            for arm in arms
        }
        print(
            f"  {label}: bare {totals['bare']:,} → harness {totals['harness']:,} "
            f"({percent_change(totals['harness'], totals['bare'])})"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
