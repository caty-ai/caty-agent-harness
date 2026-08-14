#!/usr/bin/env python3
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path.cwd()
READMES = ("README.md", "README.ja.md", "README.zh.md", "README.th.md")
MARKER_RE = re.compile(r"^<!-- family:generated:([a-z0-9-]+):start -->$", re.MULTILINE)


def generated_region(path):
    text = path.read_text(encoding="utf-8")
    license_pos = text.find('<a id="license"></a>')
    if license_pos < 0:
        raise ValueError("license anchor missing")
    matches = []
    for start in MARKER_RE.finditer(text):
        block = start.group(1)
        if block == "family-footer":
            continue
        end_marker = "<!-- family:generated:%s:end -->" % block
        end = text.find(end_marker, start.end())
        if end < 0 or end > license_pos:
            continue
        after = text[end + len(end_marker) : license_pos]
        if re.fullmatch(r"\s*---\s*", after):
            body_start = start.end()
            body = text[body_start:end].strip("\r\n")
            matches.append((block, body))
    if len(matches) != 1:
        raise ValueError("expected one generated table immediately before license")
    return matches[0]


def load_tools():
    sys.path.insert(0, str(ROOT / "tools"))
    import family_footer
    import render

    registry = json.loads((ROOT / "registry/modules.json").read_text(encoding="utf-8"))
    return family_footer, render, registry


def check_placement(filename):
    generated_region(ROOT / filename)


def check_content():
    _footer, render, registry = load_tools()
    for filename in READMES:
        block, body = generated_region(ROOT / filename)
        expected = render.render_block(block, registry, pathlib.Path(filename)).strip("\r\n")
        if body != expected:
            raise ValueError("generated content mismatch: %s" % filename)
    source = (ROOT / "tools/render.py").read_text(encoding="utf-8")
    if "module_table" not in source:
        raise ValueError("existing table builder is not used")


def check_map_rows():
    _footer, _render, registry = load_tools()
    map_name = registry["footer_text"]["map_name"]
    self_link = "https://github.com/%s" % registry["map_repo"]
    for filename, lang in zip(READMES, registry["languages"]):
        _block, body = generated_region(ROOT / filename)
        rows = [line for line in body.splitlines() if line.startswith("|")]
        data_rows = [line for line in rows if not line.startswith("| ---")][1:]
        if not data_rows or ("**%s**" % map_name[lang]) not in data_rows[0]:
            raise ValueError("map row is not bold: %s" % filename)
        if self_link in data_rows[0]:
            raise ValueError("map row is self-linked: %s" % filename)


def check_stale_detection():
    with tempfile.TemporaryDirectory(prefix="ev005-t10-") as tmp:
        replica = pathlib.Path(tmp) / "repo"
        shutil.copytree(ROOT, replica, ignore=shutil.ignore_patterns(".git"))
        target = replica / "README.md"
        text = target.read_text(encoding="utf-8")
        block, body = generated_region(ROOT / "README.md")
        target.write_text(text.replace(body, body + "\n| stale |", 1), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "tools/render.py", "--check"],
            cwd=replica,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            raise ValueError("stale content was accepted")


def check_member_footer():
    footer, _render, registry = load_tools()
    for module in registry["modules"]:
        if footer.footer_enabled(module):
            for lang in registry["languages"]:
                rendered = footer.render_region(registry, module, lang, "\n")
                map_name = registry["footer_text"]["map_name"][lang]
                map_link = "[%s](https://github.com/%s)" % (map_name, registry["map_repo"])
                host_bold = "**%s**" % module["name"]
                host_link = "[%s](https://github.com/%s)" % (module["name"], module["repo"])
                if map_link not in rendered or host_bold not in rendered or host_link in rendered:
                    raise ValueError("member footer default behavior changed")


def main(argv):
    if not argv:
        return 2
    mode = argv[0]
    if mode == "placement" and len(argv) == 2 and argv[1] in READMES:
        check_placement(argv[1])
    elif mode == "content" and len(argv) == 1:
        check_content()
    elif mode == "map-row" and len(argv) == 1:
        check_map_rows()
    elif mode == "stale" and len(argv) == 1:
        check_stale_detection()
    elif mode == "member-footer" and len(argv) == 1:
        check_member_footer()
    else:
        return 2
    return 0


try:
    raise SystemExit(main(sys.argv[1:]))
except (OSError, ValueError, KeyError, ImportError, json.JSONDecodeError):
    raise SystemExit(1)
