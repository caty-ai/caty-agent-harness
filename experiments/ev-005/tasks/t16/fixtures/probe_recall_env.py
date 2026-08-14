#!/usr/bin/env python3
"""Read-only behavior and regression-shape probes for the recall env file."""

import ast
import importlib.machinery
import importlib.util
import os
import sys
import tempfile
from pathlib import Path


sys.dont_write_bytecode = True
REPO_ROOT = Path.cwd()
RECALL_PATH = REPO_ROOT / "scripts" / "recall"
TEST_PATH = REPO_ROOT / "scripts" / "tests" / "test_recall.py"
KEY_LINE = "SUPERMEMORY_CC_API_KEY=fixture-key\n"


def load_recall():
    loader = importlib.machinery.SourceFileLoader("ev005_recall_probe", str(RECALL_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def write_env(path, mode):
    path.write_text(KEY_LINE, encoding="utf-8")
    os.chmod(path, mode)


def probe_accept():
    recall = load_recall()
    with tempfile.TemporaryDirectory(prefix="ev005-t16-accept-") as tmp:
        path = Path(tmp) / "env"
        write_env(path, 0o600)
        return recall.parse_supermemory_env(path) == "fixture-key"


def probe_reject():
    recall = load_recall()
    with tempfile.TemporaryDirectory(prefix="ev005-t16-reject-") as tmp:
        path = Path(tmp) / "env"
        write_env(path, 0o644)
        try:
            recall.parse_supermemory_env(path)
        except Exception as exc:  # The public error type may be implemented differently.
            message = str(exc)
            return "0600" in message and ("0644" in message or "mode" in message.lower())
    return False


def called_name(call):
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def function_closure(function, functions):
    pending = [function]
    seen = set()
    result = []
    while pending:
        current = pending.pop()
        marker = id(current)
        if marker in seen:
            continue
        seen.add(marker)
        result.append(current)
        for node in ast.walk(current):
            if isinstance(node, ast.Call):
                helper = functions.get(called_name(node))
                if helper is not None:
                    pending.append(helper)
    return result


def chmod_modes(nodes):
    modes = set()
    for function in nodes:
        for node in ast.walk(function):
            if not isinstance(node, ast.Call) or called_name(node) != "chmod":
                continue
            if len(node.args) >= 2 and isinstance(node.args[1], ast.Constant):
                value = node.args[1].value
                if isinstance(value, int) and not isinstance(value, bool):
                    modes.add(value)
    return modes


def call_names(nodes):
    return {
        called_name(node)
        for function in nodes
        for node in ast.walk(function)
        if isinstance(node, ast.Call)
    }


def probe_test_shape(wanted):
    try:
        tree = ast.parse(TEST_PATH.read_text(encoding="utf-8"), filename=str(TEST_PATH))
    except (OSError, SyntaxError, UnicodeError):
        return False
    functions = {
        node.name: node
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    tests = [function for name, function in functions.items() if name.startswith("test_")]
    for test in tests:
        closure = function_closure(test, functions)
        names = call_names(closure)
        modes = chmod_modes(closure)
        if "parse_supermemory_env" not in names:
            continue
        if wanted == "accept":
            if 0o600 in modes and names.intersection({"assertEqual", "assertIs", "assertTrue"}):
                return True
        elif wanted == "reject":
            if any(mode != 0o600 for mode in modes) and names.intersection(
                {"assertRaises", "assertRaisesRegex"}
            ):
                return True
    return False


def main(argv):
    if len(argv) != 2:
        return 2
    mode = argv[1]
    if mode == "accept":
        ok = probe_accept()
    elif mode == "reject":
        ok = probe_reject()
    elif mode == "test-accept":
        ok = probe_test_shape("accept")
    elif mode == "test-reject":
        ok = probe_test_shape("reject")
    else:
        return 2
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
