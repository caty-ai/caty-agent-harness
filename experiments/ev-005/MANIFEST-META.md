# EV-005 sealed manifest — metadata

- Files sealed: **265**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `50ad5b7ea23fef1f3f14490a5e8f98f76913784bcf4776773e8db4403c5c6a13`
- Git commit at generation: `f6e97c3fc934402ed3e6c3c13fb992bdb11e1827`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
