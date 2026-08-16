# EV-005 sealed manifest — metadata

- Files sealed: **265**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `3b18d81738afaa3435f82c292b59e011dc9636a8be7e270b1c872aeb4239821a`
- Git commit at generation: `769e9087bd4d8d73163837d972314ec4f03ff8b5`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
