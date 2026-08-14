#!/usr/bin/env python3
"""Read-only structural checks for the local CI workflow deployment."""

from __future__ import annotations

import pathlib
import re
import sys


WORKFLOWS = {
    "test-lint": pathlib.Path(".github/workflows/test-lint.yml"),
    "gitleaks": pathlib.Path(".github/workflows/gitleaks.yml"),
    "pr-size": pathlib.Path(".github/workflows/pr-size.yml"),
    "history": pathlib.Path(".github/workflows/history-check.yml"),
    "review": pathlib.Path(".github/workflows/review-labels.yml"),
}


def read(key: str) -> str:
    return WORKFLOWS[key].read_text(encoding="utf-8")


def contains_all(text: str, needles: tuple[str, ...]) -> bool:
    return all(needle in text for needle in needles)


def common() -> bool:
    if not pathlib.Path("Makefile").is_file() or not all(path.is_file() for path in WORKFLOWS.values()):
        return False
    for path in WORKFLOWS.values():
        text = path.read_text(encoding="utf-8")
        if re.search(r"(?m)^\s*pull_request_target:\s*$", text):
            return False
        if not re.search(r"(?m)^on:\s*$", text) or not re.search(r"(?m)^\s+pull_request:\s*$", text):
            return False
        if not re.search(r"(?m)^permissions:\s*$", text) or not re.search(r"(?m)^jobs:\s*$", text):
            return False
        if not re.search(r"(?m)^\s+runs-on:\s+", text):
            return False
    names = "\n".join(path.read_text(encoding="utf-8") for path in WORKFLOWS.values())
    for check_name in ("test", "lint", "gitleaks", "history-check", "risk-review-gate"):
        if not re.search(rf"(?m)^\s+name:\s+{re.escape(check_name)}\s*$", names):
            return False
    return True


def test_lint() -> bool:
    text = read("test-lint")
    return contains_all(text, ("set -euo pipefail", "make test", "make lint", "exit 1")) and bool(
        re.search(r"(?m)^\s+name:\s+test\s*$", text)
        and re.search(r"(?m)^\s+name:\s+lint\s*$", text)
    )


def gitleaks() -> bool:
    text = read("gitleaks")
    return contains_all(text, ("set -euo pipefail", "git merge-base", "sha256sum -c", "gitleaks git", "exit 1"))


def pr_size() -> bool:
    text = read("pr-size")
    return contains_all(text, ("set -euo pipefail", "MAX_LINES", "-gt \"$MAX_LINES\"", "size-exempt", "exit 1"))


def history() -> bool:
    text = read("history")
    return contains_all(text, ("set -euo pipefail", "git merge-base", "history-check", "exit 1"))


def review() -> bool:
    text = read("review")
    required = (
        "set -euo pipefail",
        "detect-risk-paths",
        "risk-review-gate",
        ".github/risk-reviewers.txt",
        "risk-reviewed",
        "needs-risk-review",
        "EVENT_ACTION",
        "exit 1",
    )
    if not contains_all(text, required):
        return False
    def job_block(name: str) -> str:
        match = re.search(
            rf"(?ms)^  {re.escape(name)}:\s*$.*?(?=^  [A-Za-z0-9_-]+:\s*$|\Z)",
            text,
        )
        return match.group(0) if match else ""

    gate = job_block("gate")
    labels = job_block("labels")
    if not gate or not labels:
        return False
    if not re.search(r"(?m)^\s+needs:\s+detect\s*$", gate) or re.search(r"(?m)^\s+needs:.*labels", gate):
        return False
    if not re.search(r"(?m)^\s+name:\s+risk-review-gate\s*$", gate):
        return False
    if not re.search(r"(?m)^\s+needs:\s+detect\s*$", labels):
        return False
    if not re.search(r"(?m)^\s+name:\s+apply-visibility-labels\s*$", labels):
        return False
    # Both write-side visibility-label steps are advisory and cannot decide the gate.
    return len(re.findall(r"(?m)^\s+continue-on-error:\s+true\s*$", labels)) >= 2


CHECKS = {
    "common": common,
    "test-lint": test_lint,
    "gitleaks": gitleaks,
    "pr-size": pr_size,
    "history": history,
    "review": review,
}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in CHECKS:
        return 2
    try:
        return 0 if CHECKS[sys.argv[1]]() else 1
    except (OSError, UnicodeError):
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
