#!/usr/bin/env python3
"""Replica-local behavior probes for the family-map publication gate."""

import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path.cwd()
GATE = ROOT / "tools" / "check_publication_gate.py"
READMES = {
    "en": "README.md",
    "ja": "README.ja.md",
    "zh": "README.zh.md",
    "th": "README.th.md",
}


def load_registry(root=ROOT):
    return json.loads((root / "registry" / "modules.json").read_text(encoding="utf-8"))


def one_module(registry, module_id):
    matches = [module for module in registry["modules"] if module.get("id") == module_id]
    if len(matches) != 1:
        raise AssertionError("module entry is not unique")
    return matches[0]


def check_readme(lang):
    registry = load_registry()
    module = one_module(registry, "self-growth-loop")
    assert module.get("repo") == "caty-ai/self-growth-loop"
    assert module.get("status") == "published"
    assert module.get("license") == "MIT"
    label = registry["status_labels"]["published"][lang]
    lines = (ROOT / READMES[lang]).read_text(encoding="utf-8").splitlines()
    assert any("github.com/caty-ai/self-growth-loop" in line and label in line for line in lines)


def check_preparing(lang):
    registry = load_registry()
    module = one_module(registry, "persona-growth-loop")
    assert module.get("status") == "preparing"
    label = registry["status_labels"]["preparing"][lang]
    lines = (ROOT / READMES[lang]).read_text(encoding="utf-8").splitlines()
    candidates = [line for line in lines if "Persona Growth Loop" in line]
    assert candidates
    assert any(label in line and "github.com" not in line and "](http" not in line for line in candidates)


def check_retired_repo():
    registry = load_registry()
    expected = "sho" + "jikumaru/self-growth-loop"
    matches = [entry for entry in registry.get("retired_repos", []) if entry.get("repo") == expected]
    assert len(matches) == 1


def fixture_registry():
    return {
        "languages": ["en"],
        "map_repo": "caty-ai/family-map",
        "status_labels": {"published": {"en": "published, MIT"}},
        "modules": [
            {
                "id": "alpha-module",
                "name": "Alpha Module",
                "repo": "caty-ai/alpha-module",
                "status": "published",
                "license": "MIT",
            }
        ],
        "retired_repos": [{"repo": "sho" + "jikumaru/retired-module"}],
    }


def seed_fixture(root):
    (root / "registry").mkdir()
    (root / "assets").mkdir()
    (root / "registry" / "modules.json").write_text(
        json.dumps(fixture_registry(), ensure_ascii=False), encoding="utf-8"
    )
    (root / "README.md").write_text(
        "Alpha Module — https://github.com/caty-ai/alpha-module — published, MIT\n",
        encoding="utf-8",
    )
    (root / "assets" / "map.svg").write_text(
        "<svg><text>Alpha Module</text></svg>\n", encoding="utf-8"
    )


def set_negative(root, mode):
    if mode == "reject-name":
        payload = "Sho" + "ji"
    elif mode == "reject-approval":
        payload = "approved" + " by owner"
    elif mode == "reject-home-path":
        payload = "/" + "Users" + "/person/private.txt"
    elif mode == "reject-host":
        payload = "local" + "host:9000"
    elif mode == "reject-email":
        payload = "person" + "@example.com"
    elif mode == "reject-personal-repo":
        payload = "https://github.com/" + "sho" + "jikumaru/unlisted-module"
    elif mode == "reject-missing-label":
        payload = "Alpha Module — https://github.com/caty-ai/alpha-module\n"
    elif mode == "reject-svg-state":
        (root / "README.md").write_text("Alpha Module\n", encoding="utf-8")
        return
    else:
        raise AssertionError("unknown negative mode")
    (root / "README.md").write_text(payload + "\n", encoding="utf-8")


def run_gate(root):
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    return subprocess.run(
        [sys.executable, "-B", str(GATE), "--root", str(root)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )


def behavior(mode):
    assert GATE.is_file()
    with tempfile.TemporaryDirectory(prefix="ev005-t24-") as temp:
        root = pathlib.Path(temp)
        seed_fixture(root)
        if mode != "clean":
            set_negative(root, mode)
        result = run_gate(root)
        if mode == "clean":
            assert result.returncode == 0, result.stdout
        else:
            assert result.returncode != 0, result.stdout
            assert "FAILED" in result.stdout, result.stdout


def check_suffixes():
    suffixes = ("md", "json", "py", "yml", "yaml", "svg", "sh")
    for suffix in suffixes:
        with tempfile.TemporaryDirectory(prefix="ev005-t24-suffix-") as temp:
            root = pathlib.Path(temp)
            seed_fixture(root)
            (root / ("negative." + suffix)).write_text(
                "/" + "Users" + "/person/private.txt\n", encoding="utf-8"
            )
            result = run_gate(root)
            assert result.returncode != 0, suffix + " escaped publication scan"


def check_workflow_ci():
    text = (ROOT / ".github" / "workflows" / "family-links.yml").read_text(encoding="utf-8")
    assert "  publication-gate:" in text
    assert "python3 -B tools/check_publication_gate.py\n" in text
    assert "python3 -B tools/check_publication_gate.py --selftest\n" in text
    assert "needs: [registry, family-footer, publication-gate, links]" in text


def main():
    mode = sys.argv[1]
    if mode.startswith("readme-"):
        check_readme(mode.removeprefix("readme-"))
    elif mode.startswith("preparing-"):
        check_preparing(mode.removeprefix("preparing-"))
    elif mode == "retired-repo":
        check_retired_repo()
    elif mode == "scan-suffixes":
        check_suffixes()
    elif mode == "workflow-ci":
        check_workflow_ci()
    else:
        behavior(mode)


if __name__ == "__main__":
    main()
