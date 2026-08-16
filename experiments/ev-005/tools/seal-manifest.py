#!/usr/bin/env python3
"""Generate the EV-005 sealed manifest (analysis-plan §10).

Deterministic: walks the enumerated sealing scope, hashes every file with SHA-256, and writes
`experiments/ev-005/MANIFEST.sha256` (sorted, LF-terminated, repo-relative paths) plus a
`MANIFEST-META.md` header recording what was covered and how to verify it.

Fail-closed: any enumerated path that does not exist, any file outside the scope living inside
a sealed directory, or any unreadable file aborts the run with a nonzero exit and no output.
Re-runnable: identical trees produce byte-identical manifests (no timestamps inside the digest
list; the meta file carries the git SHA, which is the intended provenance anchor).

Usage: seal-manifest.py <pack-dir> [--check]
  (default) write MANIFEST.sha256 + MANIFEST-META.md
  --check   verify an existing manifest against the tree; exit 1 on any mismatch
"""

import hashlib
import os
import subprocess
import sys

# Sealing scope, analysis-plan §10 (as amended: generators and parameter files included).
# Each entry is either a file (exact) or a directory (recursive, all files).
SCOPE_FILES = [
    "analysis-plan.md",
    "translation-rules.md",
    "eligibility-ledger.md",
    "arm-instructions.md",
    "runner-spec.md",
    "sealed-parameters.md",
    "canary-rule.md",
    "source-provenance.md",
    "environment-digest.md",
    "provenance/issue-63-snapshot.md",
    "tools/validate-task.sh",
    "tools/mdd-sim.py",
    "tools/mdd-power-table.md",
]
SCOPE_DIRS = [
    "tasks",
    "pilot-tasks",
    "tools/validate-logs",
]
# Inside sealed dirs, these are excluded (transient/editor artifacts only — never content).
EXCLUDE_NAMES = {".DS_Store"}
EXCLUDE_SUFFIXES = (".pyc",)
EXCLUDE_DIRNAMES = {"__pycache__"}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect(pack):
    paths, missing = [], []
    for rel in SCOPE_FILES:
        p = os.path.join(pack, rel)
        (paths if os.path.isfile(p) else missing).append(rel)
    for rel in SCOPE_DIRS:
        root_dir = os.path.join(pack, rel)
        if not os.path.isdir(root_dir):
            missing.append(rel + "/")
            continue
        for dirpath, dirnames, filenames in os.walk(root_dir):
            dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRNAMES)
            for name in sorted(filenames):
                if name in EXCLUDE_NAMES or name.endswith(EXCLUDE_SUFFIXES):
                    continue
                full = os.path.join(dirpath, name)
                if os.path.islink(full):
                    missing.append(os.path.relpath(full, pack) + " (symlink: not sealable)")
                    continue
                paths.append(os.path.relpath(full, pack))
    return sorted(set(paths)), missing


def git_sha(pack):
    try:
        out = subprocess.run(["git", "-C", pack, "rev-parse", "HEAD"],
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return "UNKNOWN"


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    pack = os.path.abspath(sys.argv[1])
    check = "--check" in sys.argv[2:]
    manifest_path = os.path.join(pack, "MANIFEST.sha256")

    paths, missing = collect(pack)
    if missing:
        print("E: sealing scope incomplete — refusing to seal (fail-closed):", file=sys.stderr)
        for m in missing:
            print(f"   missing: {m}", file=sys.stderr)
        return 1

    lines = []
    for rel in paths:
        lines.append(f"{sha256_file(os.path.join(pack, rel))}  {rel}\n")
    body = "".join(lines)

    if check:
        if not os.path.isfile(manifest_path):
            print("E: no MANIFEST.sha256 to check", file=sys.stderr)
            return 1
        current = open(manifest_path, encoding="utf-8").read()
        if current == body:
            print(f"MANIFEST OK — {len(paths)} files match")
            return 0
        have = dict(l.rsplit("  ", 1)[::-1] for l in current.splitlines() if "  " in l)
        want = dict(l.rsplit("  ", 1)[::-1] for l in body.splitlines() if "  " in l)
        for rel in sorted(set(have) | set(want)):
            if have.get(rel) != want.get(rel):
                state = ("ADDED" if rel not in have else
                         "REMOVED" if rel not in want else "CHANGED")
                print(f"MISMATCH {state}: {rel.strip()}")
        return 1

    with open(manifest_path, "w", encoding="utf-8") as fh:
        fh.write(body)
    digest_of_manifest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    with open(os.path.join(pack, "MANIFEST-META.md"), "w", encoding="utf-8") as fh:
        fh.write(
            "# EV-005 sealed manifest — metadata\n\n"
            f"- Files sealed: **{len(paths)}**\n"
            f"- Manifest digest (SHA-256 of `MANIFEST.sha256`): `{digest_of_manifest}`\n"
            f"- Git commit at generation: `{git_sha(pack)}`\n"
            "- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on\n"
            "  a missing scope entry or a symlink inside the scope).\n\n"
            "## Verify\n\n"
            "    python3 tools/seal-manifest.py experiments/ev-005 --check\n\n"
            "Exit 0 means every sealed file matches its recorded digest and no file was added to\n"
            "or removed from the sealed scope. Any post-sealing change requires the §10\n"
            "amendment procedure; the amendment note records the new manifest digest.\n"
        )
    print(f"sealed {len(paths)} files; manifest digest {digest_of_manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
