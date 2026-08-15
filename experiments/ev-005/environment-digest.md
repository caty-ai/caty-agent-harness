# EV-005 environment digest (analysis-plan §2, §10; runner-spec §6)

Status: in the sealing scope; manifest pending. Both cells verified 2026-08-15 by their
operators against the shipped image artifact; operator reports and the author's acceptance are
in family-vault `20_projects/ev-005/env-prep/{alec,cero}-env-prep.md`.

| field | main-series cell (operator: Alec) | crossover cell (operator: Cero) |
| --- | --- | --- |
| image tag | `ev005-validate:v3-arm64` | `ev005-validate:v3-amd64` |
| image ID (sha256) | `c1859bf00f07c768f91786fe88920d804dc661a1299edd953e72ab710b70c331` | `09fe0422da1342751365965cc8733113cbba9510fc7049c72368da3a299d1b41` |
| base, pinned by OCI index digest | `python:3.12-slim@sha256:dd29372629eeba2dd003fd9e9d35a5b8236c44727875a0364254b5127af88e65` | same |
| in-image toolchain | Python 3.12.14 / node v20.19.2 / ripgrep 14.1.1 / GNU Make 4.4.1 / git 2.47.3 | same (verified independently) |
| container host | Colima 0.10.1 (Virtualization.Framework); Docker Engine 29.2.1, CLI 29.5.2 | Docker Engine 29.3.1 (Community), containerd 2.2.2, runc 1.3.4 |
| host OS / arch | macOS 26.5.2 (25F84) / arm64 | Ubuntu 24.04.4, kernel 6.8.0-90 / x86_64 |
| capacity | 10 cores / 32 GiB RAM / 168 GiB free | 96 cores / 377 GiB RAM / 1.4 TiB free |

Distribution rule: images are built once from the pinned Dockerfile, shipped as
`docker save` archives, and `docker load`ed at each cell. **Local rebuilds are prohibited** —
a rebuild produces a different image ID and breaks the digest recorded here.

## Run invariants (both cells)

- `--init` is **mandatory**. Without it, PID 1 lacks normal signal semantics and suites that
  sweep descendants on SIGTERM fail spuriously (measured: FMA suite 402/403 without `--init`,
  403/403 with it).
- `HOME=/root`, run-private and **passwd-consistent** — the guarantee the t12 r4-1 exemption
  depends on, and the reason runs are container-mandatory: a bare-metal macOS cell cannot
  provide a fresh HOME and passwd consistency simultaneously (upstream evidence: FMA#18).
- uid 0 inside the container; network, `gh`, and web access blocked at the wrapper.
- Each run's audit-log header records `env_fingerprint` (image ID + cell id + per-run HOME path)
  so drift is detectable post hoc.
- Runs are **serialized per cell**. Measured failure mode: a 120 s gate timed out purely from
  concurrent host load, and passed in 24 s on the same tree once the host was quiet.

## Registered as a limitation, not pooled away

The two cells differ in CPU architecture and container host. The design already assigns the main
series to the mac-mini cell and the descriptive crossover to the VPS cell with **no pooling**
(§4), so cell and model are confounded by construction and the crossover carries no α claim.
The mini cell's 10 cores are the scheduling constraint for run planning.
