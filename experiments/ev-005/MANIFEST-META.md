# EV-005 sealed manifest — metadata

- Files sealed: **265**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `98574a9f5aae147f98cc5b6e0557a30391ee1a3191d00f1d7a46199ba9d2e03b`
- Git commit at generation: `963e22aaba4988748ae3b4dff5f157b5ce293074`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
