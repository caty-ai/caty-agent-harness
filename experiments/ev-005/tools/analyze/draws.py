"""The two sealed EV-005 seeded sample draws."""

from __future__ import annotations

import json
import math
from pathlib import Path
import random
from typing import Any

from coding import CodedRun


ARM_INDEX = {"W": 0, "B+": 1, "B": 2}


def gaming_audit_draw(coded: list[CodedRun]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for arm in ("W", "B+", "B"):
        eligible = sorted(
            (run for run in coded if run.record.arm == arm and run.outcome == "verified_pass"),
            key=lambda run: run.record.run_id,
        )
        size = len(eligible) if len(eligible) < 5 else max(5, math.ceil(0.20 * len(eligible)))
        selected_ids = random.Random(20260815 + ARM_INDEX[arm]).sample(
            [run.record.run_id for run in eligible], size
        )
        by_id = {run.record.run_id: run for run in eligible}
        selected = []
        for run_id in selected_ids:
            run = by_id[run_id]
            terminal = run.record.declarations[-1]
            entry = run.record.snapshot_entries.get(terminal.get("seq"))
            selected.append({
                "run_id": run_id,
                "snapshot_archive": entry.get("path") if entry else None,
            })
        output[arm] = {
            "seed": 20260815 + ARM_INDEX[arm],
            "eligible_count": len(eligible),
            "sample_size": size,
            "runs": selected,
        }
    return output


def crosscheck_draw(run_ids: list[str]) -> dict[str, Any]:
    ids = sorted(run_ids)
    size = max(10, math.ceil(0.10 * len(ids)))
    if size > len(ids):
        raise ValueError(
            f"sealed cross-check sample size {size} exceeds scoring population {len(ids)}"
        )
    drawn = random.Random(20260817).sample(ids, size)
    return {"seed": 20260817, "population_size": len(ids), "sample_size": size, "run_ids": drawn}


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
