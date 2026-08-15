#!/usr/bin/env python3
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = pathlib.Path(__file__).resolve().parents[3]
TASKS_ROOT = ROOT / "tasks"
NEGPROBE_DIR = pathlib.Path(__file__).resolve().parent
INDEX_PATH = NEGPROBE_DIR / "index.tsv"

REPO_MAP = {
    "caty-ai/caty-agent-harness": pathlib.Path("/Users/shojikumaru/claude-workspace/caty-agent-harness"),
    "caty-ai/family-os": pathlib.Path("/Users/shojikumaru/claude-workspace/family-os-caty"),
    "caty-ai/family-memory-architecture": pathlib.Path("/Users/shojikumaru/claude-workspace/fma-public"),
    "caty-ai/context-kit": pathlib.Path("/Users/shojikumaru/claude-workspace/context-kit"),
    "caty-ai/self-growth-loop": pathlib.Path("/Users/shojikumaru/claude-workspace/self-growth-loop-catyai"),
}

ROUTE_B_TASKS = {"t14"}


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def append_text(path: pathlib.Path, text: str) -> None:
    existing = read_text(path)
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_text(path, existing + text)


def append_html_comment(path: pathlib.Path, *lines: str) -> None:
    body = "\n".join(lines)
    append_text(path, f"<!-- ev005-negprobe\n{body}\n-->\n")


def append_shell_comment(path: pathlib.Path, *lines: str) -> None:
    body = "\n".join(f"# {line}" for line in lines)
    append_text(path, f"{body}\n")


def append_plain(path: pathlib.Path, *lines: str) -> None:
    append_text(path, "\n".join(lines) + "\n")


def replace_once(path: pathlib.Path, old: str, new: str) -> None:
    text = read_text(path)
    if old not in text:
        raise RuntimeError(f"pattern not found in {path}: {old}")
    write_text(path, text.replace(old, new, 1))


def insert_before(path: pathlib.Path, marker: str, snippet: str) -> None:
    text = read_text(path)
    if marker not in text:
        raise RuntimeError(f"marker not found in {path}: {marker}")
    write_text(path, text.replace(marker, snippet + marker, 1))


def write_binary(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def transform_family_table(path: pathlib.Path) -> None:
    text = read_text(path)
    start = "<a id=\"family-os\"></a>\n"
    end = "<a id=\"acknowledgments\"></a>\n"
    start_index = text.find(start)
    end_index = text.find(end, start_index)
    if start_index < 0 or end_index < 0:
        raise RuntimeError(f"family section markers missing in {path}")
    section = text[start_index:end_index]
    lines = section.splitlines(keepends=True)
    replacements = 0
    for index, line in enumerate(lines):
        if line.startswith("|"):
            lines[index] = "¦" + line[1:]
            replacements += 1
    if replacements != 11:
        raise RuntimeError(f"expected 11 table-line replacements in {path}, got {replacements}")
    new_section = "".join(lines)
    write_text(path, text[:start_index] + new_section + text[end_index:])


def append_t09_surface_tests(path: pathlib.Path) -> None:
    append_text(
        path,
        """

def test_surface_default_gid_probe():
    \"\"\"enforce_generated_artifact_permissions gid issues assertFalse\"\"\"
    pass


def test_surface_pinned_gid_probe():
    \"\"\"enforce_generated_artifact_permissions gid issues FMA_EXPECT_OWNER assert\"\"\"
    pass
""".lstrip(),
    )


def append_t16_surface_tests(path: pathlib.Path) -> None:
    append_text(
        path,
        """

def test_surface_mode0600_accept():
    if False:
        os.chmod("fixture-env", 0o600)
        parse_supermemory_env("fixture-env")
        self.assertTrue(True)


def test_surface_mode0644_reject():
    if False:
        os.chmod("fixture-env", 0o644)
        parse_supermemory_env("fixture-env")
        self.assertRaisesRegex(RuntimeError, "0600")
""".lstrip(),
    )


def task_paths(root: pathlib.Path, *parts: str) -> pathlib.Path:
    return root.joinpath(*parts)


TASK_METADATA = {
    "t01": {
        "route": "a",
        "expected_result": "unexpected-pass",
        "summary": "Append missing needles as HTML comments to four docs; make test still passes on pre tree.",
        "expected_fails": "",
    },
    "t02": {
        "route": "a",
        "expected_result": "unexpected-pass",
        "summary": "Append README/agent-guide surface strings as comments without changing behavior.",
        "expected_fails": "",
    },
    "t03": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append AUTH none declaration comment to review-labels workflow.",
        "expected_fails": "a01",
    },
    "t04": {
        "route": "a",
        "expected_result": "unexpected-pass",
        "summary": "Append x-collector/pipeline HTML comment to docs/trial-isolation.md.",
        "expected_fails": "",
    },
    "t05": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append positive-only needles across example/docs/install files while forbidden legacy strings remain.",
        "expected_fails": "a06,a07,a08,a09,a18,a19,a22,a23,a27,a30,a31,a33,a37",
    },
    "t06": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append public-flow and historical-record needles while forbidden private wording remains.",
        "expected_fails": "a03,a04,a07,a08,a11,a12,a15,a27,a28,a29",
    },
    "t07": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append public-name strings as comments while retired strings remain in place.",
        "expected_fails": "a02,a04,a06,a08,a10,a12,a14,a16,a18,a20,a22,a24,a26,a28,a30,a32,a34,a36,a37",
    },
    "t08": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append public-name strings as comments while retired strings remain in place.",
        "expected_fails": "a02,a04,a06,a08,a10,a12,a14,a16,a18,a20,a22,a24,a26,a28,a30,a34,a36,a38,a40,a42,a44,a46,a48,a50,a52,a54,a56,a58,a60,a62",
    },
    "t09": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append two no-op test functions carrying AST coverage tokens.",
        "expected_fails": "a01",
    },
    "t10": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Insert empty generated block before README license anchor.",
        "expected_fails": "a02,a03,a04,a05,a06,a08",
    },
    "t11": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Add executable fake secrets regression script with discovery markers.",
        "expected_fails": "a04,a05,a06,a07",
    },
    "t12": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Swap yaml import for __import__ indirection only.",
        "expected_fails": "a02,a03,a04,a05,a06,a07,a08,a09,a10,a11",
    },
    "t13": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Replace leading pipe on English duplicated family-table rows only.",
        "expected_fails": "a10,a11,a12,a18,a19,a20",
    },
    "t14": {
        "route": "b",
        "expected_result": "impossibility-record",
        "summary": "Route-b only; strict JSON singleton/typed-field equality leaves no superficial satisfaction path.",
        "expected_fails": "",
    },
    "t15": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append README smoke-fixture line only.",
        "expected_fails": "a01,a02,a03",
    },
    "t16": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append unreachable mode-check test functions carrying AST tokens.",
        "expected_fails": "a02,a06",
    },
    "t17": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append deadman probe token comment to tests/deadman-probe.test.sh.",
        "expected_fails": "a01,a02,a03,a05,a06,a07",
    },
    "t18": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Rename existing self-growth-loop id to context-kit in registry/modules.json.",
        "expected_fails": "a07,a08,a09,a10,a11,a12,a13,a14",
    },
    "t19": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append secrets-env token comment to tests/deadman-probe.test.sh.",
        "expected_fails": "a01,a02,a03",
    },
    "t20": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create empty docs/evidence.md.",
        "expected_fails": "a02,a03,a04,a05,a06,a07,a08,a09",
    },
    "t21": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append verified-skills wording and template comment only.",
        "expected_fails": "a03,a06",
    },
    "t22": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create one-byte hero asset only.",
        "expected_fails": "a05,a06,a08,a09",
    },
    "t23": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append regression-token comments to task-runner and enqueue tests.",
        "expected_fails": "a01,a02,a03,a04,a05,a06",
    },
    "t24": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create zero-byte publication gate file only.",
        "expected_fails": "a05,a06,a08,a13,a14,a15,a16,a17,a18,a19,a20,a21,a22",
    },
    "t25": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append one allowed_signers documentation line only.",
        "expected_fails": "a02,a04,a05,a06",
    },
    "t26": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create token-only cli-conventions note.",
        "expected_fails": "a05,a06",
    },
    "t27": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create 8-section FOR-AGENTS skeleton with bogus repo tour row.",
        "expected_fails": "a08",
    },
    "t28": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Append trust-boundary sentence only.",
        "expected_fails": "a02,a03,a04,a05,a06,a07,a08,a10",
    },
    "t29": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create minimal SVG shell only.",
        "expected_fails": "a01,a02,a03,a04,a05,a06,a07,a08,a09,a10,a13",
    },
    "t30": {
        "route": "a",
        "expected_result": "expected-fail",
        "summary": "Create no-op Makefile test/lint targets only.",
        "expected_fails": "a03,a04,a05,a06,a07,a08",
    },
}


def apply_t01(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "docs", "engineering.md"),
        "producers only",
        "must also schedule the consumer, `adapters/claude-code/flush-intake.sh`",
        "two to four times per day",
        "LaunchAgent in the `gui/<uid>` domain",
        "touches `loop/.deadman/distill.marker`",
        "INSTALL.md](../adapters/claude-code/INSTALL.md) for the full setup steps",
    )
    append_html_comment(
        task_paths(root, "docs", "reference.md"),
        "`loop/pending/intake-runs.log`",
        "append-only",
        "INSTALL.md](../adapters/claude-code/INSTALL.md) for the full ledger format",
    )
    append_html_comment(
        task_paths(root, "docs", "engineering.ja.md"),
        "producer に過ぎません",
        "`adapters/claude-code/flush-intake.sh` の定期実行",
        "`21600`〜`43200`",
        "`gui/<uid>` domain の LaunchAgent",
        "`loop/.deadman/distill.marker` を touch します",
    )
    append_html_comment(
        task_paths(root, "docs", "reference.ja.md"),
        "`loop/pending/intake-runs.log`",
        "`loop/archive/` は append-only",
    )


def apply_t02(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "README.md"),
        "macOS: ✅ tested",
        "Linux: ⚠️ expected to work",
        "| Windows | ❌ not supported",
        "WSL",
        "![runtime: bash 3.2+]",
        "![platform: macOS | Linux]",
        "![status: public preview]",
    )
    append_html_comment(
        task_paths(root, "README.ja.md"),
        "macOS: ✅ テスト済み",
        "Linux: ⚠️ 動作見込み",
        "| Windows | ❌ 非対応",
        "WSL",
        "![runtime: bash 3.2+]",
        "![platform: macOS | Linux]",
        "![status: public preview]",
    )
    append_html_comment(
        task_paths(root, "README.zh.md"),
        "macOS：✅ 已测试",
        "Linux：⚠️ 预计可用",
        "| Windows | ❌ 不支持",
        "WSL",
        "![runtime: bash 3.2+]",
        "![platform: macOS | Linux]",
        "![status: public preview]",
    )
    append_html_comment(
        task_paths(root, "README.th.md"),
        "macOS: ✅ ทดสอบแล้ว",
        "Linux: ⚠️ คาดว่าจะใช้งานได้",
        "| Windows | ❌ ไม่รองรับ",
        "WSL",
        "![runtime: bash 3.2+]",
        "![platform: macOS | Linux]",
        "![status: public preview]",
    )
    append_html_comment(
        task_paths(root, "docs", "agent-guide.md"),
        "run the bundled example",
        "templates/examples/img-pilot.task.md.",
        'scripts/loop-init --workspace "$WORKSPACE"',
        'scripts/tr-enqueue templates/examples/img-pilot.task.md "$WORKSPACE"',
        'TR_SPAWN_STEP="$STEP_PROVIDER" scripts/task-runner.sh "$WORKSPACE"',
    )


def apply_t03(root: pathlib.Path) -> None:
    append_shell_comment(task_paths(root, ".github", "workflows", "review-labels.yml"), "RISK_PATHS_AUTH='none'")


def apply_t04(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "docs", "trial-isolation.md"),
        "caty-ai/x-collector",
        "https://github.com/caty-ai/x-collector",
        "through that pipeline",
        "inherit collection controls",
    )


def apply_t05(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "templates", "examples", "img-pilot.task.md"),
        "out/image.svg",
        '<svg xmlns="http://www.w3.org/2000/svg"',
        '"artifact": "out/image.svg"',
        "- bash",
        "- python3 standard library",
        "issued_by: example-operator",
        "escalate_to: example-operator",
    )
    append_html_comment(
        task_paths(root, "adapters", "codex", "INSTALL.md"),
        "~/path/to/your/AGENTS.md",
        "Replace this placeholder with the operator's own",
    )
    append_html_comment(
        task_paths(root, "adapters", "kimi", "INSTALL.md"),
        "~/path/to/your/AGENTS.md",
        "operator's own agent charter file path during setup.",
    )
    append_html_comment(
        task_paths(root, "adapters", "hermes", "INSTALL.md"),
        "/path/to/secrets/cron.env",
        "/path/to/hermes-home/profiles/example/workspace",
    )
    append_html_comment(
        task_paths(root, "templates", "TASK.tmpl.md"),
        "issued_by: example-operator",
        "escalate_to: example-operator",
    )
    append_shell_comment(
        task_paths(root, "scripts", "family-updater"),
        "fma_scripts_dir=${FMA_SCRIPTS_DIR:-}",
        "When omitted, reporting is disabled with a warning.",
        "Set FMA_SCRIPTS_DIR or pass --fma-scripts-dir <dir>.",
    )
    append_shell_comment(
        task_paths(root, "templates", "updater-cron.tmpl.sh"),
        "FMA_SCRIPTS_DIR is not set; set it to the reporter directory",
        "/path/to/family-memory-architecture/scripts",
    )
    append_shell_comment(
        task_paths(root, "install.sh"),
        "remote home directory",
        "inspect configured",
        "env-supplied external ones",
        "mutate the checked workspace",
    )


def apply_t06(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "docs", "agent-guide.md"),
        "repository is public",
        "caty-ai/caty-agent-harness",
        "no invitation is needed",
    )
    append_html_comment(
        task_paths(root, "adapters", "hermes", "INSTALL.md"),
        "Clone the public repository",
        "git clone https://github.com/caty-ai/caty-agent-harness.git",
    )
    append_html_comment(
        task_paths(root, "adapters", "openclaw", "INSTALL.md"),
        "Clone the public repository",
        "git clone https://github.com/caty-ai/caty-agent-harness.git",
    )
    append_html_comment(
        task_paths(root, "adapters", "claude-code", "INSTALL.md"),
        "Keychain",
        "LaunchAgent",
        "PreToolUse",
        "isolate",
        "hooks",
    )
    replace_once(
        task_paths(root, "docs", "agent-guide.md"),
        "Clone fails with auth error",
        "`Clone fails with auth error`",
    )
    for rel in (
        ("DESIGN.md",),
        ("DESIGN-task-runner.md",),
        ("docs", "governance-rules.md"),
        ("docs", "updater-rollout.md"),
    ):
        append_html_comment(task_paths(root, *rel), "Historical design record.")
    append_plain(
        task_paths(root, "docs", "updater-rollout.md"),
        "## Deployment inventory",
        "",
        "historical record",
    )


def apply_t07(root: pathlib.Path) -> None:
    append_html_comment(task_paths(root, "DESIGN.md"), "# Caty Agent Harness v0.2 — Minimal Self-Improving Loop Harness for OpenClaw & Hermes Agent")
    append_html_comment(
        task_paths(root, "DESIGN-task-runner.md"),
        "Parent: Issue #8 (EPIC). Companion to DESIGN.md (harness v0.2); does not restate it.",
        "The harness loop guards the QUALITY of finished work; task-runner DRIVES work to",
        "verify: mechanical` and are excluded from k≥2 promotion until a real harness",
    )
    append_html_comment(
        task_paths(root, "SYNTHESIS.md"),
        "# Cross-Review Synthesis & Adjudication — harness design v0.1 → v0.2",
        "the R1–R15 in this file are harness v0.2 design-review resolutions",
    )
    append_html_comment(
        task_paths(root, "SYNTHESIS-task-runner.md"),
        "until a real harness VERIFY",
        "attempts_budget` vs the harness's N=3 verify retries named distinctly",
    )
    append_html_comment(
        task_paths(root, "docs", "governance-rules.md"),
        "> pre-publication private tracker #26",
        "| Synthesis R1–R15 | `SYNTHESIS.md` | harness v0.1→v0.2 design review resolutions (verifier, STATE.md, rubric discipline) |",
        "| v1.0 source | pre-publication private tracker #26 (issue body) |",
        "| Amendment issue | pre-publication private tracker #123 |",
    )
    append_html_comment(
        task_paths(root, "docs", "updater-rollout.md"),
        "From: Alpha · SoT: pre-publication private tracker Issue #36",
        "> Path correction (install learning, pre-publication private tracker #40): the cron line below shows",
    )
    append_shell_comment(
        task_paths(root, "scripts", "lib-wrapper-conformance.sh"),
        'stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/caty-wrapper-stage.XXXXXX") || {',
    )
    append_shell_comment(
        task_paths(root, "scripts", "attest-wrapper"),
        'scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/caty-attest-wrapper.XXXXXX")',
        'probe_stdout=$(mktemp "${TMPDIR:-/tmp}/caty-attest-wrapper.stdout.XXXXXX")',
        'probe_stderr=$(mktemp "${TMPDIR:-/tmp}/caty-attest-wrapper.stderr.XXXXXX")',
    )


def apply_t08(root: pathlib.Path) -> None:
    append_html_comment(
        task_paths(root, "adapters", "claude-code", "INSTALL.md"),
        "cwd for a Caty Agent Harness",
        "governed, headless capture attempt per session.",
    )
    append_shell_comment(
        task_paths(root, "adapters", "claude-code", "checkpoint-stop-hook.sh"),
        "# Caty Agent Harness CHECKPOINT enforcement",
        "turn in a Caty Agent Harness workspace",
        'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"',
        "caty-agent-harness CHECKPOINT",
    )
    append_shell_comment(
        task_paths(root, "adapters", "claude-code", "precompact-flush-hook.sh"),
        "# Caty Agent Harness pre-destruction memory flush",
        'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"',
        "memory-flush extractor for a Caty Agent Harness workspace",
    )
    append_html_comment(
        task_paths(root, "adapters", "codex", "INSTALL.md"),
        "Caty Agent",
        "cwd for a Caty Agent Harness",
    )
    append_shell_comment(
        task_paths(root, "adapters", "codex", "checkpoint-stop-hook.sh"),
        "# Caty Agent Harness CHECKPOINT enforcement",
        "turn in a Caty Agent Harness workspace",
        'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"',
        "caty-agent-harness CHECKPOINT",
    )
    append_html_comment(
        task_paths(root, "adapters", "kimi", "INSTALL.md"),
        "Caty Agent Harness CHECKPOINT enforcement",
        "cwd for a Caty Agent Harness workspace",
    )
    append_shell_comment(
        task_paths(root, "adapters", "kimi", "checkpoint-stop-hook.sh"),
        "# Caty Agent Harness CHECKPOINT enforcement",
        "turn in a Caty Agent Harness workspace",
        'guard_dir="${TMPDIR:-/tmp}/caty-agent-harness-hook"',
        "caty-agent-harness CHECKPOINT",
    )
    append_html_comment(task_paths(root, "docs", "plugin-convention.md"), "Caty Agent Harness is a **generic completion engine**")
    append_shell_comment(task_paths(root, "templates", "cron-wrapper.tmpl.sh"), "TARGET=${TARGET:-/absolute/path/to/caty-agent-harness-target}")
    append_text(
        task_paths(root, "templates", "launchd.tmpl.plist"),
        "\n<!-- ev005-negprobe\nCaty Agent Harness LaunchAgent template v1\n<string>com.example.caty-agent-harness-tick</string>\n<string>/absolute/path/to/caty-agent-harness-target</string>\n-->\n",
    )
    append_shell_comment(
        task_paths(root, "templates", "updater-cron.tmpl.sh"),
        "Caty Agent Harness updater cron wrapper",
        "REPO_DIR=${REPO_DIR:-/absolute/path/to/caty-agent-harness}",
    )
    append_shell_comment(
        task_paths(root, "tests", "pause-contract.test.sh"),
        "grep -Fq 'caty-agent-harness CHECKPOINT' \"$TMP/enabled-hook.stderr\" \\",
        'assert "caty-agent-harness CHECKPOINT" in value["reason"]',
        "grep -Fq 'caty-agent-harness CHECKPOINT' \"$TMP/multiworkspace-hook.stderr\" \\",
    )


def apply_t09(root: pathlib.Path) -> None:
    append_t09_surface_tests(task_paths(root, "scripts", "tests", "test_family_hot_generate.py"))


def apply_t10(root: pathlib.Path) -> None:
    marker = "<a id=\"license\"></a>\n"
    snippet = "<!-- family:generated:unknown:start -->\n<!-- family:generated:unknown:end -->\n---\n"
    insert_before(task_paths(root, "README.md"), marker, snippet)


def apply_t11(root: pathlib.Path) -> None:
    path = task_paths(root, "tests", "surface-secrets.test.sh")
    write_text(
        path,
        """#!/bin/bash
# SECRETS_ENV install.sh --check wrapper symlink embedded NUL interpreter-control reject accept
exit 0
""",
    )
    os.chmod(path, 0o755)


def apply_t12(root: pathlib.Path) -> None:
    replace_once(task_paths(root, "scripts", "content-lint"), "import yaml", 'yaml = __import__("yaml")')


def apply_t13(root: pathlib.Path) -> None:
    transform_family_table(task_paths(root, "README.md"))


def apply_t15(root: pathlib.Path) -> None:
    append_plain(task_paths(root, "README.md"), "Validator smoke fixture: `docs/`.")


def apply_t16(root: pathlib.Path) -> None:
    append_t16_surface_tests(task_paths(root, "scripts", "tests", "test_recall.py"))


def apply_t17(root: pathlib.Path) -> None:
    append_shell_comment(
        task_paths(root, "tests", "deadman-probe.test.sh"),
        "deadman-probe.sh cron-wrapper.tmpl.sh launchd.tmpl.plist DEADMAN_CHECKS .marker exit 1",
    )


def apply_t18(root: pathlib.Path) -> None:
    replace_once(task_paths(root, "registry", "modules.json"), '"id": "self-growth-loop"', '"id": "context-kit"')


def apply_t19(root: pathlib.Path) -> None:
    append_shell_comment(
        task_paths(root, "tests", "deadman-probe.test.sh"),
        "cron-wrapper.tmpl.sh SECRETS_ENV touch KEY=VALUE chmod 600 ln -s symlink",
    )


def apply_t20(root: pathlib.Path) -> None:
    write_text(task_paths(root, "docs", "evidence.md"), "")


def apply_t21(root: pathlib.Path) -> None:
    replace_once(task_paths(root, "DESIGN.md"), "verifier_id", "verifier_id for verified skills")
    append_shell_comment(task_paths(root, "skills", "_staging", "SKILL.tmpl.md"), "verified_at: verifier_id: promotion")


def apply_t22(root: pathlib.Path) -> None:
    write_binary(task_paths(root, "assets", "readme", "hero.png"), b"x")


def apply_t23(root: pathlib.Path) -> None:
    append_shell_comment(
        task_paths(root, "tests", "task-runner.test.sh"),
        "TR_STEP_TIMEOUT_S",
        "TR_GRACE_S",
        "corrupt state.json",
        "quoted-id",
        "invalid-created",
    )
    append_shell_comment(
        task_paths(root, "tests", "tr-enqueue.test.sh"),
        "missing-created",
        "invalid-created",
        "copy-failure",
    )


def apply_t24(root: pathlib.Path) -> None:
    write_text(task_paths(root, "tools", "check_publication_gate.py"), "")


def apply_t25(root: pathlib.Path) -> None:
    append_plain(task_paths(root, "docs", "updater-rollout.md"), "SSH signing uses allowed_signers outside the repository.")


def apply_t26(root: pathlib.Path) -> None:
    write_text(
        task_paths(root, "docs", "cli-conventions.md"),
        """## Output prefixes and streams

Machine output stays on stdout while `warning: ` stays on stderr.
Legacy `WARN:` and `WARNING:` forms are frozen deviations for outlier and defer cases.

## Exit codes

| code | meaning |
| --- | --- |
| `0` | success |
| `1` | task failure; `tr-enqueue` uses 1 for contractual queue errors |
| `2` | usage error and known deviation documentation |

Optional machine `FAIL` output exits 0 when the surrounding command is advisory.

## Surface inventory

- missing path:
- scripts/tr-enqueue
- scripts/task-runner.sh
- scripts/family-updater
- tests/check-tickprobe.test.sh
- tests/pause-contract.test.sh
- tests/tr-enqueue.test.sh
- tests/skill-lint.test.sh
- tests/cli-conventions.test.sh

stdout carries machine output and stderr carries human `warning:` text.
""",
    )


def apply_t27(root: pathlib.Path) -> None:
    write_text(
        task_paths(root, "FOR-AGENTS.md"),
        """## 1. Opening

This guide helps a visiting reader take a 5-minute or 30-minute tour.
Automatic discovery is not guaranteed.

## 2. Authority

1. `registry/modules.json`
2. `docs/growth-model.md`
3. `docs/evidence.md`
4. README

## 3. State Vocabulary

delivery, visibility, evidence, license, implemented, planned, unknown, published, preparing, private, observed, unverified

## 4. Evaluation Frame

Check consistency, philosophy, plain and durable technology, state discipline, and structural human gates.

## 5. Repository Tour

| Repository | Role | Verification |
| --- | --- | --- |
| https://github.com/caty-ai/not-real | bogus role | bogus verification |

## 6. Counter-Evidence

Open a public issue and use only public evidence.

## 7. Handoff Schema

claim:
state:
evidence:
confidence:
unresolved:

Stop rule: do not infer beyond unresolved evidence.
Inference is prohibited when unresolved.

## 8. Human Handoff

> Fork the idea
""",
    )


def apply_t28(root: pathlib.Path) -> None:
    append_plain(
        task_paths(root, "DESIGN-task-runner.md"),
        "Trust boundary: mechanical enforcement is delegated to the operator; residual risks include arbitrary shell as the runner user, privilege, sandbox, post-enqueue mutation, setsid, and inability to attest provider contents.",
    )


def apply_t29(root: pathlib.Path) -> None:
    write_text(task_paths(root, "assets", "readme", "growth-stages.svg"), '<svg role="img"></svg>')


def apply_t30(root: pathlib.Path) -> None:
    write_text(
        task_paths(root, "Makefile"),
        ".PHONY: test lint\n\ntest:\n\t@true\n\nlint:\n\t@true\n",
    )


APPLY_FUNCS = {
    "t01": apply_t01,
    "t02": apply_t02,
    "t03": apply_t03,
    "t04": apply_t04,
    "t05": apply_t05,
    "t06": apply_t06,
    "t07": apply_t07,
    "t08": apply_t08,
    "t09": apply_t09,
    "t10": apply_t10,
    "t11": apply_t11,
    "t12": apply_t12,
    "t13": apply_t13,
    "t15": apply_t15,
    "t16": apply_t16,
    "t17": apply_t17,
    "t18": apply_t18,
    "t19": apply_t19,
    "t20": apply_t20,
    "t21": apply_t21,
    "t22": apply_t22,
    "t23": apply_t23,
    "t24": apply_t24,
    "t25": apply_t25,
    "t26": apply_t26,
    "t27": apply_t27,
    "t28": apply_t28,
    "t29": apply_t29,
    "t30": apply_t30,
}


def task_repo(task_dir: pathlib.Path) -> pathlib.Path:
    meta = json.loads((task_dir / "meta.json").read_text(encoding="utf-8"))
    source_repo = meta["source_repo"]
    return REPO_MAP[source_repo]


def task_timeout(task_dir: pathlib.Path) -> int:
    meta = json.loads((task_dir / "meta.json").read_text(encoding="utf-8"))
    return int(meta.get("timeout_s", 120))


def task_pre_sha(task_dir: pathlib.Path) -> str:
    meta = json.loads((task_dir / "meta.json").read_text(encoding="utf-8"))
    return meta["pre_fix"]


def build_replica(task_dir: pathlib.Path, dest: pathlib.Path) -> None:
    repo = task_repo(task_dir)
    pre_sha = task_pre_sha(task_dir)
    dest.mkdir(parents=True, exist_ok=True)
    archive = subprocess.Popen(
        ["git", "-C", str(repo), "archive", pre_sha],
        stdout=subprocess.PIPE,
        env={**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"},
    )
    try:
        tar = subprocess.run(["tar", "-x", "-C", str(dest)], stdin=archive.stdout, check=True)
    finally:
        if archive.stdout is not None:
            archive.stdout.close()
    rc = archive.wait()
    if tar.returncode != 0 or rc != 0:
        raise RuntimeError(f"git archive failed for {task_dir.name}")
    subprocess.run(["git", "-C", str(dest), "init", "-q"], check=True)
    subprocess.run(
        ["git", "-C", str(dest), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "add", "-A"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["git", "-C", str(dest), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "commit", "-qm", "task snapshot"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def inject_donecheck(task_dir: pathlib.Path, replica: pathlib.Path) -> None:
    shutil.copy2(task_dir / "donecheck.sh", replica / ".ev005-donecheck.sh")
    fixtures = task_dir / "fixtures"
    if fixtures.is_dir():
        shutil.copytree(fixtures, replica / ".ev005-fixtures")


def run_probe(task_id: str, task_dir: pathlib.Path) -> None:
    metadata = TASK_METADATA[task_id]
    log_path = NEGPROBE_DIR / f"{task_id}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    work_root = pathlib.Path(tempfile.mkdtemp(prefix=f"ev005-negprobe-{task_id}-", dir=os.environ.get("TMPDIR", "/tmp")))
    try:
        replica = work_root / "repo"
        build_replica(task_dir, replica)
        APPLY_FUNCS[task_id](replica)
        inject_donecheck(task_dir, replica)
        subprocess.run(
            ["git", "-C", str(replica), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "add", "-A"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["git", "-C", str(replica), "-c", "user.name=ev005", "-c", "user.email=ev005@local", "commit", "-qm", "apply negprobe"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        timeout_s = task_timeout(task_dir)
        env = {
            **os.environ,
            "LC_ALL": "C",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
        }
        started = time.time()
        with log_path.open("w", encoding="utf-8") as handle:
            handle.write(
                f"== negprobe {task_id} route={metadata['route']} expected={metadata['expected_result']} "
                f"repo={task_repo(task_dir)} pre={task_pre_sha(task_dir)} timeout_s={timeout_s} ==\n"
            )
            handle.write(f"EDIT {metadata['summary']}\n")
            if metadata["expected_fails"]:
                handle.write(f"EXPECT_FAILS {metadata['expected_fails']}\n")
            else:
                handle.write("EXPECT_FAILS none-recorded\n")
            handle.flush()
            try:
                proc = subprocess.run(
                    ["bash", ".ev005-donecheck.sh"],
                    cwd=replica,
                    env=env,
                    stdout=handle,
                    stderr=subprocess.STDOUT,
                    timeout=timeout_s,
                )
                rc = proc.returncode
                timeout_hit = False
            except subprocess.TimeoutExpired:
                rc = 124
                timeout_hit = True
            duration = int(time.time() - started)
            dirty = subprocess.run(
                ["git", "-C", str(replica), "status", "--porcelain"],
                env=env,
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            handle.write(f"RUN {task_id} negprobe exit={rc} dur={duration}s\n")
            if dirty:
                handle.write("DIRTY_TREE " + dirty.replace("\n", " | ") + "\n")
            expected = metadata["expected_result"]
            if timeout_hit:
                outcome = "TIMEOUT"
            elif rc == 0 and expected == "unexpected-pass":
                outcome = "UNEXPECTED_PASS_CONFIRMED"
            elif rc == 0 and expected != "unexpected-pass":
                outcome = "UNEXPECTED_PASS"
            elif rc != 0 and expected == "unexpected-pass":
                outcome = "EXPECTED_UNEXPECTED_PASS_DID_NOT_MATERIALIZE"
            else:
                outcome = "EXPECTED_FAIL_CONFIRMED"
            handle.write(f"NEGPROBE_RESULT {outcome}\n")
    finally:
        shutil.rmtree(work_root, ignore_errors=True)


def write_index() -> None:
    rows = ["task\troute\texpected_result\tlog_path\tsummary\texpected_fails"]
    for task_id in sorted(TASK_METADATA):
        meta = TASK_METADATA[task_id]
        log_path = "" if meta["route"] == "b" else str((NEGPROBE_DIR / f"{task_id}.log").relative_to(ROOT))
        rows.append(
            "\t".join(
                [
                    task_id,
                    meta["route"],
                    meta["expected_result"],
                    log_path,
                    meta["summary"],
                    meta["expected_fails"],
                ]
            )
        )
    write_text(INDEX_PATH, "\n".join(rows) + "\n")


def main(argv: list[str]) -> int:
    tasks = [arg for arg in argv[1:] if arg]
    if not tasks:
        tasks = [f"t{index:02d}" for index in range(1, 31) if f"t{index:02d}" not in ROUTE_B_TASKS]
    unknown = [task for task in tasks if task not in TASK_METADATA or task in ROUTE_B_TASKS]
    if unknown:
        print(f"unknown or non-route-a tasks: {', '.join(unknown)}", file=sys.stderr)
        return 2
    write_index()
    for task_id in tasks:
        print(f"START {task_id}", flush=True)
        run_probe(task_id, TASKS_ROOT / task_id)
        print(f"DONE {task_id}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
