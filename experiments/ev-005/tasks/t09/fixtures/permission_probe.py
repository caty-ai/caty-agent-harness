#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import os
import pathlib
import stat
import sys
import tempfile
from unittest import mock


SCRIPT = pathlib.Path("scripts/family-hot-generate")


def load_generator():
    loader = importlib.machinery.SourceFileLoader("ev005_family_hot_generate", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def exercise(policy):
    module = load_generator()
    with tempfile.TemporaryDirectory(prefix="ev005-t09-") as tmp:
        artifact = pathlib.Path(tmp) / "family-hot.md"
        artifact.write_text("probe\n", encoding="utf-8")
        actual = artifact.stat()
        environment = os.environ.copy()
        if policy.startswith("pinned-"):
            environment["FMA_EXPECT_OWNER"] = "expected-user:expected-group"
        else:
            environment.pop("FMA_EXPECT_OWNER", None)
        if policy == "pinned-uid":
            expected = (actual.st_uid + 1, actual.st_gid, "expected-user", "expected-group")
        else:
            expected = (actual.st_uid, actual.st_gid + 1, "expected-user", "expected-group")
        with mock.patch.dict(module.os.environ, environment, clear=True):
            with mock.patch.object(module, "expected_artifact_owner", return_value=expected):
                with mock.patch.object(module.os, "geteuid", return_value=1):
                    issues = module.enforce_generated_artifact_permissions([artifact])
        if stat.S_IMODE(artifact.stat().st_mode) != 0o600:
            return False
        return not issues if policy == "default" else bool(issues)


if len(sys.argv) != 2 or sys.argv[1] not in {"default", "pinned-uid", "pinned-gid"}:
    raise SystemExit(2)
raise SystemExit(0 if exercise(sys.argv[1]) else 1)
