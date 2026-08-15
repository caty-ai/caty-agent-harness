# EV-005 sealed manifest — metadata

- Files sealed: **264**
- Manifest digest (SHA-256 of `MANIFEST.sha256`): `46ae2491a97f85e29a3512b4236a8934955e8256e5ae218db9749572c70f3a77`
- Git commit at generation: `0a5b57d6cc47be9a2ec6e028c8cdb5d3457e9e5c`
- Generator: `tools/seal-manifest.py` (stdlib only, deterministic, fail-closed on
  a missing scope entry or a symlink inside the scope).

## Verify

    python3 tools/seal-manifest.py experiments/ev-005 --check

Exit 0 means every sealed file matches its recorded digest and no file was added to
or removed from the sealed scope. Any post-sealing change requires the §10
amendment procedure; the amendment note records the new manifest digest.

## Seal history

Each seal keeps its own timestamp proof; superseded seals are not deleted, because the point of
timestamping is to preserve what was committed to *before* a change.

| seal | tag | commit | manifest digest | proof |
| --- | --- | --- | --- | --- |
| v1 (original) | `ev-005-sealed-v1` | `53d2795` | `c6a16e89…` | `seals/MANIFEST-v1.sha256.ots` over `seals/MANIFEST-v1.sha256` — confirmed in the Bitcoin blockchain (tx `ace1195d…`, awaiting depth) |
| v2 (after amendment A-1) | `ev-005-sealed-v2` | `fb15eb4` | `46ae2491…` | `MANIFEST.sha256.ots` over the current `MANIFEST.sha256` |

Verify either one:

    ots verify experiments/ev-005/MANIFEST.sha256.ots
    ots verify experiments/ev-005/seals/MANIFEST-v1.sha256.ots -f experiments/ev-005/seals/MANIFEST-v1.sha256

Upgrade a proof once its calendars attest: `ots upgrade <proof>`.
