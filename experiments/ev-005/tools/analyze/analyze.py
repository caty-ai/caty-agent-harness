#!/usr/bin/env python3
"""Command-line entry point for the sealed EV-005 analysis pipeline."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

# Running this file directly places this directory on sys.path, which keeps the
# package usable despite the sealed parent directory's hyphenated name.
from coding import audit_adjudications, code_run
from draws import write_json
from load import InputValidationError, load_analysis_data
from reexec import (
    CommandRunner, registered_image_id, reexecute_record, subprocess_runner,
    verify_image, write_reexecution_log,
)
from report import build_report, write_reports
from stats import load_sealed_tail_prob


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze one EV-005 series deterministically")
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--series", choices=("main", "crossover"), required=True)
    parser.add_argument("--out-root", type=Path, required=True)
    parser.add_argument("--tasks-dir", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument(
        "--reexec", choices=("docker", "non-registered-dry-run"), default="docker",
    )
    parser.add_argument("--image", default="ev005-validate:v3-amd64")
    parser.add_argument(
        "--check-bug-removals", default="",
        help="comma-separated task ids upheld by the registered human adjudication",
    )
    return parser.parse_args(argv)


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def run(
    ns: argparse.Namespace, *, command_runner: CommandRunner = subprocess_runner,
) -> int:
    pack = ns.pack.resolve()
    out_root = ns.out_root.resolve()
    tasks_dir = ns.tasks_dir.resolve()
    report_dir = ns.report_dir.resolve()
    if _inside(report_dir, out_root):
        raise ValueError("--report-dir must not be inside sealed --out-root")
    removed = {part.strip() for part in ns.check_bug_removals.split(",") if part.strip()}
    data = load_analysis_data(
        out_root, tasks_dir, ns.series,
        require_snapshots=ns.reexec == "docker",
    )
    unknown = removed - set(data.tasks)
    if unknown:
        raise ValueError(f"unknown check-bug removal task ids: {sorted(unknown)}")
    if len(removed) == len(data.tasks):
        raise ValueError("check-bug removals cannot remove the entire analysis set")

    image_id: str | None = None
    sealed_image_id = registered_image_id(pack)
    if ns.reexec == "docker":
        image_id = verify_image(ns.image, sealed_image_id, command_runner)
    reexec_rows = []
    provisional = []
    for record in data.runs:
        if ns.reexec == "docker" and record.retention_failure is None:
            bundle = reexecute_record(
                record, data.tasks[record.task_id], ns.image, command_runner,
            )
            terminal, first = bundle.terminal, bundle.first
            reexec_rows.extend(bundle.log_rows)
        else:
            terminal, first = audit_adjudications(record)
        provisional.append(code_run(record, terminal, first, removed_tasks=removed))
    candidate_tasks = {
        run.record.task_id for run in provisional if run.candidate_reasons
    }
    unjustified = removed - candidate_tasks
    if unjustified:
        raise ValueError(
            "check-bug removals lack a pipeline candidate row: " + ", ".join(sorted(unjustified))
        )

    tail_prob = load_sealed_tail_prob(pack)
    report, gaming, crosscheck = build_report(
        data=data, coded=provisional, pack=pack, out_root=out_root,
        series=ns.series, mode=ns.reexec, image=ns.image,
        image_id=image_id if image_id is not None else sealed_image_id,
        removed_tasks=removed, tail_prob=tail_prob,
    )
    report_dir.mkdir(parents=True, exist_ok=True)
    write_reexecution_log(report_dir / "pipeline-reexec.jsonl", reexec_rows)
    write_json(report_dir / "gaming-audit-sample.json", gaming)
    if crosscheck is not None:
        write_json(report_dir / "crosscheck-sample.json", crosscheck)
    write_reports(report_dir, report)
    return 0


def main(
    argv: list[str] | None = None, *, command_runner: CommandRunner = subprocess_runner,
) -> int:
    try:
        return run(parse_args(argv), command_runner=command_runner)
    except InputValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"analysis failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
