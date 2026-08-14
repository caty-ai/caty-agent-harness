#!/usr/bin/env python3
import ast
import pathlib


path = pathlib.Path("scripts/tests/test_family_hot_generate.py")
try:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source)
except (OSError, SyntaxError, UnicodeError):
    raise SystemExit(1)

tests = []
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_"):
        segment = ast.get_source_segment(source, node) or ""
        tests.append(segment)

default_covered = any(
    "enforce_generated_artifact_permissions" in test
    and "gid" in test.lower()
    and "issues" in test
    and "FMA_EXPECT_OWNER" not in test
    and ("assertEqual" in test or "assertFalse" in test)
    for test in tests
)
pinned_covered = any(
    "enforce_generated_artifact_permissions" in test
    and "gid" in test.lower()
    and "issues" in test
    and "FMA_EXPECT_OWNER" in test
    and "assert" in test
    for test in tests
)

raise SystemExit(0 if default_covered and pinned_covered else 1)
