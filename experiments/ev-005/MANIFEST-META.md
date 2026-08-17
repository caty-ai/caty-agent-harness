# EV-005 sealed manifest — metadata

- Files sealed: **281**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `84c76920da49d6306cdb56021fe3dc7b340b8aab8e53d1d17f75833fc75afa23`
- Git commit at generation: `858e5d5a6e9e22f39436ff58a99c97b32cf811e1`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
