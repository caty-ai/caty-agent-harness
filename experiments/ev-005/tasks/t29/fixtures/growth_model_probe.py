#!/usr/bin/env python3
"""Read-only structural probes for the five-stage growth-model task."""

from __future__ import annotations

import pathlib
import re
import sys
import xml.etree.ElementTree as ET


READMES = {
    "README.md": ("Implemented", "Planned", "Relationship"),
    "README.ja.md": ("実装済み", "計画中", "関係"),
    "README.zh.md": ("已实现", "计划中", "关系"),
    "README.th.md": ("นำไปใช้แล้ว", "อยู่ในแผน", "ความสัมพันธ์"),
}
CANONICAL = ("docs/growth-model.md", "docs/growth-model.ja.md")
SVG_PATH = pathlib.Path("assets/readme/growth-stages.svg")


def read(path: str | pathlib.Path) -> str:
    return pathlib.Path(path).read_text(encoding="utf-8")


def growth_section(path: str) -> str:
    text = read(path)
    start = text.find('<a id="growth"></a>')
    end = text.find('<a id="map"></a>', start + 1)
    if start < 0 or end < 0:
        raise ValueError(f"missing growth/map anchors: {path}")
    return text[start:end]


def stage_rows(text: str) -> dict[int, list[str]]:
    rows: dict[int, list[str]] = {}
    for line in text.splitlines():
        match = re.match(r"^\|\s*([1-5])\s*\|", line)
        if not match:
            continue
        number = int(match.group(1))
        if number not in rows:
            rows[number] = [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
    return rows


def canonical() -> bool:
    for path in CANONICAL:
        text = read(path)
        rows = stage_rows(text)
        if set(rows) != {1, 2, 3, 4, 5}:
            return False
        header_lines = [line.lower() for line in text.splitlines() if line.startswith("|")]
        if path.endswith(".ja.md"):
            valid_header = any("誰が決めるか" in line and "実装状態" in line and "証拠" in line for line in header_lines)
        else:
            valid_header = any("who decides" in line and "delivery" in line and "evidence" in line for line in header_lines)
        if not valid_header:
            return False
    return True


def subjects() -> bool:
    for path in CANONICAL:
        text = read(path)
        mappings: dict[str, str] = {}
        for line in text.splitlines():
            cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
            if len(cells) >= 3 and cells[0] in {"I", "WE", "THEY"}:
                mappings[cells[0]] = cells[1]
        if set(mappings) != {"I", "WE", "THEY"}:
            return False
        if not re.search(r"1\D+4", mappings["I"]):
            return False
        if "5" not in mappings["WE"]:
            return False
        if not re.search(r"beyond|outside|モデル.*先", mappings["THEY"], re.IGNORECASE):
            return False
        if not re.search(r"THEY.{0,120}(outside|beyond|5段階の外)", re.sub(r"\s+", " ", text), re.IGNORECASE):
            return False
    return True


def readiness() -> bool:
    for path in CANONICAL:
        text = read(path)
        heading = text.find("Relationship Readiness")
        if heading < 0:
            return False
        context = text[max(0, heading - 300) : heading + 700]
        if not re.search(r"second axis|第2軸|第二の軸|もう1つの軸", context, re.IGNORECASE):
            return False
    return True


def readme_stages() -> bool:
    return all(set(stage_rows(growth_section(path))) == {1, 2, 3, 4, 5} for path in READMES)


def claim_strength() -> bool:
    for path, (implemented, planned, _relationship) in READMES.items():
        rows = stage_rows(growth_section(path))
        row3 = " | ".join(rows.get(3, []))
        row4 = " | ".join(rows.get(4, []))
        if implemented not in row3 or "docs/evidence.md#" not in row3:
            return False
        if planned not in row4 or "docs/evidence.md#" in row4:
            return False
    return True


def svg_tree() -> tuple[ET.Element, str, str]:
    source = read(SVG_PATH)
    root = ET.fromstring(source)
    visible = " ".join(part.strip() for part in root.itertext() if part.strip())
    return root, source, visible


def svg_labels() -> bool:
    root, _source, visible = svg_tree()
    if root.tag.rsplit("}", 1)[-1] != "svg" or root.attrib.get("role") != "img":
        return False
    if re.search(r"[^\x00-\x7f]", visible.replace("→", "")):
        return False
    for number in ("1", "2", "3", "4", "5"):
        if not re.search(rf"(?<!\d){number}(?!\d)", visible):
            return False
    canonical_names = [stage_rows(read("docs/growth-model.md"))[number][1] for number in range(1, 6)]
    for name in canonical_names:
        tokens = [token.lower() for token in re.findall(r"[A-Za-z]+", name) if token.lower() not in {"being", "of", "the"}]
        if not tokens or max(tokens, key=len) not in visible.lower():
            return False
    return True


def svg_styles() -> bool:
    _root, source, visible = svg_tree()
    required_source = (".planned", "stroke-dasharray", ".focus")
    required_visible = ("solid", "implemented", "dashed", "planned", "orange", "focus", "not a state")
    return all(token in source for token in required_source) and all(token in visible for token in required_visible)


def svg_boundary() -> bool:
    _root, source, visible = svg_tree()
    rows = stage_rows(read("docs/growth-model.md"))
    stage_tokens = []
    for number in (4, 5):
        tokens = [token.lower() for token in re.findall(r"[A-Za-z]+", rows[number][1]) if token.lower() not in {"being", "of", "the"}]
        if not tokens:
            return False
        stage_tokens.append(max(tokens, key=len))
    lowered = source.lower()
    stage4 = lowered.find(stage_tokens[0])
    boundary = source.find('class="boundary"')
    stage5 = lowered.find(stage_tokens[1])
    return "I → WE" in visible and 0 <= stage4 < boundary < stage5


def adjacency() -> bool:
    for path, (_implemented, _planned, relationship) in READMES.items():
        lines = growth_section(path).splitlines()
        image_indexes = [index for index, line in enumerate(lines) if "assets/readme/growth-stages.svg" in line]
        if len(image_indexes) != 1:
            return False
        following = [line for line in lines[image_indexes[0] + 1 :] if line.strip()]
        if not following or not following[0].startswith("|") or relationship not in following[0]:
            return False
        if len([cell for cell in re.split(r"(?<!\\)\|", following[0].strip().strip("|"))]) != 6:
            return False
        if set(stage_rows("\n".join(following))) != {1, 2, 3, 4, 5}:
            return False
    return True


def stage_one_evidence() -> bool:
    for path in CANONICAL:
        row = stage_rows(read(path)).get(1, [])
        if not row or row[-1] != "—":
            return False
    return True


def parity() -> bool:
    shapes = []
    for path in READMES:
        section = growth_section(path)
        rows = stage_rows(section)
        shapes.append((section.count("assets/readme/growth-stages.svg"), tuple(sorted(rows)), tuple(len(rows[n]) for n in sorted(rows))))
    return len(set(shapes)) == 1 and shapes[0] == (1, (1, 2, 3, 4, 5), (6, 6, 6, 6, 6))


CHECKS = {
    "canonical": canonical,
    "subjects": subjects,
    "readiness": readiness,
    "readme-stages": readme_stages,
    "claim-strength": claim_strength,
    "svg-labels": svg_labels,
    "svg-styles": svg_styles,
    "svg-boundary": svg_boundary,
    "adjacency": adjacency,
    "stage-one-evidence": stage_one_evidence,
    "parity": parity,
}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in CHECKS:
        return 2
    try:
        return 0 if CHECKS[sys.argv[1]]() else 1
    except (ET.ParseError, OSError, UnicodeError, ValueError):
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
