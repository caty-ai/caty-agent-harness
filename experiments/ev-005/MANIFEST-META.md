# EV-005 sealed manifest — metadata

- Files sealed: **264**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `c6a16e8981f16121174baf112c0cb88abb27fa2bd470e25cce77869cc1899ee6`
- Git commit at generation: `186bcb7a8c794d6ff36fa3915525cac5c2467286`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
