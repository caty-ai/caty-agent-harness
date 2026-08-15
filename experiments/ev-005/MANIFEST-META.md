# EV-005 sealed manifest — metadata

- Files sealed: **264**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `46ae2491a97f85e29a3512b4236a8934955e8256e5ae218db9749572c70f3a77`
- Git commit at generation: `0a5b57d6cc47be9a2ec6e028c8cdb5d3457e9e5c`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
