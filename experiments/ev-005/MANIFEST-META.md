# EV-005 sealed manifest — metadata

- Files sealed: **265**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `0412a43a5eaa021599b5a9e7fa5b2ddae0abe230efee11941f229631d28ef72e`
- Git commit at generation: `8c0b895db53e7bdb416f8e3473943ff1d5bd94fe`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
