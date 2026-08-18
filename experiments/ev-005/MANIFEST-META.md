# EV-005 sealed manifest — metadata

- Files sealed: **281**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `b88e8f096aab21ba1f617e923c179d7d9fe82727f4b2fc1bf82959a81196228c`
- Git commit at generation: `2b0c34e0aa5744f19e050aaea6fde29e4403ef9e`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.
