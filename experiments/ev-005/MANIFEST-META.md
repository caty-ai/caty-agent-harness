# EV-005 sealed manifest — metadata

- Files sealed: **265**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `6018082bab203d5bcb524074f4960af023a9536c8f0ffce03ae5f8ecf154a8f9`
- Git commit at generation: `a94920e34e40c308ff7cc72510dedc1eaee5ce1a`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
