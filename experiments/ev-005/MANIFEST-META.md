# EV-005 sealed manifest — metadata

- Files sealed: **264**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `82eaf48bd4bd6c065a531cd045323818c45f0d91d589909cf0ffe577c212416d`
- Git commit at generation: `d3dc6e15f94f7ca9d0dd161d9e319a8287322c5e`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.

| v3 (after amendment A-2) | `ev-005-sealed-v3` | (see below) | `82eaf48b…` | `MANIFEST.sha256.ots` over the current `MANIFEST.sha256`; v2 proof preserved as `seals/MANIFEST-v2.sha256.ots` over `seals/MANIFEST-v2.sha256` |
