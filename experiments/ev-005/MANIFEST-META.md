# EV-005 sealed manifest — metadata

- Files sealed: **281**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `29c300b9b5dbdf002187ed19104d64041595cb4d5cdc0d34c2c33c72626365a9`
- Git commit at generation: `9e4474c5a4b7ff3ad1b2858e1cf79fc76e397d4e`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
