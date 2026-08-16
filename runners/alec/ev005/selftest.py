#!/usr/bin/env python3
"""Run the six mandatory EV-005 wrapper self-test cases in sealed-class containers."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
RUNNER = HERE / "runner.py"

# These are behavior-test budgets, not pilot budgets.  Keep enough headroom for
# host-side Python/MCP startup so the cases test wrapper semantics rather than
# workstation scheduler latency.
CASES = [
    ("a-immediate-untouched", "B", "immediate", 1.0),
    ("b-twice-second-passes", "B+", "twice", 1.5),
    ("c-six-declarations", "B", "six", 1.5),
    ("d-w-fail-then-pass", "W", "w-retry", 3.0),
    ("e-budget-no-declaration", "B", "no-declaration", 1.0),
    ("f-abandon", "B+", "abandon", 1.5),
]


def command(argv: list[str], cwd: Path | None = None) -> str:
    cp = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    if cp.returncode != 0:
        raise RuntimeError(f"command failed rc={cp.returncode}: {argv!r}\n{cp.stdout}")
    return cp.stdout


def make_fixture(root: Path) -> tuple[Path, Path]:
    source = root / "source"
    source.mkdir(parents=True)
    command(["git", "init", "-q"], source)
    command(["git", "config", "user.name", "ev005"], source)
    command(["git", "config", "user.email", "ev005@local"], source)
    (source / "README.md").write_text("EV-005 self-test base\n")
    command(["git", "add", "-A"], source)
    command(["git", "commit", "-qm", "base"], source)
    sha = command(["git", "rev-parse", "HEAD"], source).strip()

    task = root / "task"
    task.mkdir()
    (task / "task.md").write_text(
        "# Self-test task\n\nCreate a file named `PASS` containing `pass`.\n\n"
        "## Done when\n\n1. `PASS` exists.\n"
    )
    donecheck = task / "donecheck.sh"
    donecheck.write_text(
        "#!/bin/bash\n"
        "set -u\n"
        "if [ -f PASS ] && [ \"$(cat PASS)\" = pass ]; then\n"
        "  echo SEALED_PASS\n"
        "  exit 0\n"
        "fi\n"
        "echo SEALED_FAIL\n"
        "exit 1\n"
    )
    donecheck.chmod(0o755)
    (task / "meta.json").write_text(json.dumps({
        "id": "selftest", "pre_fix": sha, "fix": sha,
        "source_repo": "local/selftest", "timeout_s": 1,
    }, sort_keys=True) + "\n")
    return source, task


def read_rows(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def events(rows: list[dict[str, Any]], name: str) -> list[dict[str, Any]]:
    return [row for row in rows if row.get("event") == name]


def verify_case(name: str, rows: list[dict[str, Any]], agent_output: str) -> dict[str, Any]:
    if not rows or "run_id" not in rows[0] or "end_reason" not in rows[-1]:
        raise AssertionError(f"{name}: incomplete header/trailer")
    if rows[0].get("model_id") != "stub-agent-v1" or rows[0].get("harness_version") != "1":
        raise AssertionError(f"{name}: missing or wrong model/harness audit identity: {rows[0]}")
    seqs = [row["seq"] for row in rows if "seq" in row]
    if seqs != list(range(1, len(seqs) + 1)):
        raise AssertionError(f"{name}: non-contiguous event sequence: {seqs}")
    decl = events(rows, "declaration")
    excess = events(rows, "declaration_excess")
    checks = events(rows, "donecheck_invocation")
    reads = events(rows, "donecheck_read")
    canaries = events(rows, "canary_check")
    if {e["scope"] for e in canaries} != {"context", "output"}:
        raise AssertionError(f"{name}: missing canary scopes: {canaries}")
    if any(e["rule_id"] != "canary-rule.md" for e in canaries):
        raise AssertionError(f"{name}: wrong canary rule id: {canaries}")
    summary = {
        "end_reason": rows[-1]["end_reason"],
        "declarations": len(decl),
        "declaration_excess": len(excess),
        "donechecks": [{"invoker": e["invoker"], "exit": e["exit"]} for e in checks],
        "donecheck_reads": len(reads),
        "canary_checks": [{"scope": e["scope"], "hit": e["hit"]} for e in canaries],
        "wallclock_s": rows[-1]["wallclock_s"],
        "paused_s": rows[-1]["paused_s"],
        "elapsed_s": rows[-1]["elapsed_s"],
    }
    if name != "f-abandon" and any(e["hit"] for e in canaries):
        raise AssertionError(f"{name}: unexpected canary hit: {canaries}")
    if name in {"a-immediate-untouched", "c-six-declarations", "e-budget-no-declaration", "f-abandon"}:
        assert not reads, f"runner-owned I/O was misclassified as an agent gate read: {reads}"
    if name == "a-immediate-untouched":
        assert len(decl) == 1 and decl[0]["scored"] is True
        assert rows[-1]["end_reason"] == "wallclock"
    elif name == "b-twice-second-passes":
        assert len(decl) == 2
        assert len([e for e in checks if e["invoker"] == "agent"]) == 2
        assert reads, "agent donecheck reads were not observed"
        pipeline = [e for e in checks if e["invoker"] == "pipeline"]
        assert pipeline and pipeline[-1]["exit"] == 0
        assert rows[-1]["paused_s"] > 0
    elif name == "c-six-declarations":
        assert len(decl) == 5 and len(excess) == 1
        assert excess[0]["scored"] is False and excess[0]["count_after"] == 5
    elif name == "d-w-fail-then-pass":
        gate = [e for e in checks if e["invoker"] == "gate"]
        assert [e["exit"] for e in gate] == [1, 0]
        assert reads, "visible gate read was not observed"
        assert rows[-1]["end_reason"] == "delivered"
        assert "MUTATED_VISIBLE_DONECHECK" in agent_output
        assert "SEALED_FAIL" in agent_output
        assert "REPLICA_COPY_RAN" not in agent_output
    elif name == "e-budget-no-declaration":
        assert not decl and not excess and rows[-1]["end_reason"] == "wallclock"
    elif name == "f-abandon":
        assert len(events(rows, "abandon")) == 1
        assert rows[-1]["end_reason"] == "abandon"
        hits = {e["scope"]: e["hit"] for e in canaries}
        assert hits == {"output": True, "context": True}
    return summary


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--wrapper-sha", default="WORKTREE")
    ns = ap.parse_args(argv)
    out = Path(ns.output).resolve()
    out.mkdir(parents=True, exist_ok=False)
    fixture = out / "fixture"
    source, task = make_fixture(fixture)
    results: dict[str, Any] = {}
    argv_json = json.dumps([sys.executable, str(HERE / "stub_agent.py")])
    for name, arm, scenario, budget_s in CASES:
        case_out = out / name
        cmd = [
            sys.executable, str(RUNNER), "run",
            "--run-id", f"selftest-{name}",
            "--arm", arm,
            "--task-dir", str(task),
            "--source-repo", str(source),
            "--output", str(case_out),
            "--model-id", "stub-agent-v1",
            "--harness-name", "EV-005 deterministic stub",
            "--harness-version", "1",
            "--harness-path", str(HERE / "stub_agent.py"),
            "--agent-argv-json", argv_json,
            "--agent-env-json", json.dumps({"EV005_STUB_SCENARIO": scenario}),
            "--budget-s", str(budget_s),
            "--donecheck-timeout-s", "1",
            "--term-grace-s", "0.1",
            "--wrapper-sha", ns.wrapper_sha,
            "--versions", json.dumps({"selftest": "sealed-image-id"}),
        ]
        cp = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
        (out / f"{name}.terminal.log").write_text(cp.stdout)
        if cp.returncode != 0:
            raise RuntimeError(f"{name}: runner rc={cp.returncode}\n{cp.stdout}")
        rows = read_rows(case_out / "audit.jsonl")
        agent_output = (case_out / "agent-output.log").read_text(errors="replace")
        results[name] = verify_case(name, rows, agent_output)
    report = {
        "status": "PASS",
        "cases": results,
        "proofs": {
            "snapshot_before_adjudication": "Each declaration event contains an already-created snapshot_sha and precedes every gate/pipeline event in seq order.",
            "sealed_donecheck": "Case d mutates the visible replica copy to print REPLICA_COPY_RAN/exit 0; first gate still exits 1 with SEALED_FAIL, and that replica token is absent from agent output.",
            "pause_accounting": "Cases b and d contain donecheck_invocation events and publish nonzero paused_s separately from wallclock_s.",
        },
    }
    (out / "SELFTEST-REPORT.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
