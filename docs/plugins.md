# Known Plugins

Registry of automation plugins attached to this engine per
[plugin-convention.md](plugin-convention.md). Dual bookkeeping: each entry here has a
matching `INTEGRATION.md` in the plugin repo.

| Plugin | Repo | Status | Seams used | Owner |
|---|---|---|---|---|
| self-growth-loop (tool/tech adoption: sense→propose→trial→council→adopt) | private | active: ledger, growth-lint, and ops cron live; trial runner shipped | data plane active; enqueue + results active (task ids `sgl-trial-*`) | the maintainers |
| persona-growth-loop (persona **overlay** growth: observation → nightly delayed-reward proposals) | private | contracts frozen 2026-08-02; implementation staged behind checkpoint gates — all automated overlay writes forbidden until the governance and per-face GO checkpoints pass | data plane: aggregates only, no raw phrase bodies. Enqueue/results/templates unused. Growth-write is NOT a harness seam — it is a separate plugin↔pack-repo contract | the maintainers |
