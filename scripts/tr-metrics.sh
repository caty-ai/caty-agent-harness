#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: tr-metrics.sh <workspace-dir>\n' >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

workspace=$(cd "$1" && pwd)
python3 - "$workspace" <<'PY'
import glob
import os
import sys

workspace = sys.argv[1]
tasks_root = os.path.join(workspace, "loop", "tasks")
out_path = os.path.join(workspace, "METRICS.md")

def task_meta(path):
    meta = {}
    try:
        with open(path, encoding="utf-8") as f:
            in_fm = False
            for raw in f:
                line = raw.rstrip("\n")
                if line == "---":
                    if not in_fm:
                        in_fm = True
                        continue
                    break
                if in_fm and ":" in line:
                    key, value = line.split(":", 1)
                    value = value.strip()
                    if value in ("null", "~"):
                        value = ""
                    meta[key.strip()] = value
    except OSError:
        pass
    return meta

tasks = []
parents = {}
for status in ("delivered", "dlq"):
    for directory in sorted(glob.glob(os.path.join(tasks_root, status, "*"))):
        if not os.path.isdir(directory):
            continue
        task_files = sorted(glob.glob(os.path.join(directory, "*.task.md")))
        meta = task_meta(task_files[0]) if task_files else {}
        task_id = meta.get("id") or os.path.basename(directory)
        parent = meta.get("parent_id") or ""
        tasks.append((task_id, status))
        parents[task_id] = parent

rows = []
for task_id, status in tasks:
    chain = [task_id]
    seen = {task_id}
    current = task_id
    for _ in range(20):
        parent = parents.get(current, "")
        if not parent or parent in seen:
            break
        chain.append(parent)
        seen.add(parent)
        if parent not in parents:
            break
        current = parent
    rows.append((task_id, status, " -> ".join(reversed(chain))))

delivered = sum(1 for _, status, _ in rows if status == "delivered")
dlq = sum(1 for _, status, _ in rows if status == "dlq")
total = delivered + dlq
rate = "0.0%" if total == 0 else "%.1f%%" % (delivered * 100.0 / total)

lines = []
lines.append("# Task Runner Metrics")
lines.append("")
lines.append("| metric | value |")
lines.append("| --- | ---: |")
lines.append("| delivered | %d |" % delivered)
lines.append("| dlq | %d |" % dlq)
lines.append("| completion_rate | %s |" % rate)
lines.append("")
lines.append("## Baseline")
lines.append("")
lines.append("| label | source |")
lines.append("| --- | --- |")
lines.append("| B0 | estimate |")
lines.append("")
lines.append("## Parent Chains")
lines.append("")
lines.append("| task_id | status | chain |")
lines.append("| --- | --- | --- |")
for task_id, status, chain in sorted(rows):
    lines.append("| %s | %s | %s |" % (task_id, status, chain))
lines.append("")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
PY
