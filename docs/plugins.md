# Known Plugins

Registry of automation plugins attached to this engine per
[plugin-convention.md](plugin-convention.md). Dual bookkeeping: each entry here has a
matching `INTEGRATION.md` in the plugin repo.

| Plugin | Repo | Status | Seams used | Owner |
|---|---|---|---|---|
| self-growth-loop (tool/tech adoption: sense→propose→trial→council→adopt) | [caty-ai/self-growth-loop](https://github.com/caty-ai/self-growth-loop) | active: ledger, growth-lint, and ops cron live; trial runner shipped | data plane active; enqueue + results active (task ids `sgl-trial-*`) | the maintainers |
| persona-growth-loop (persona **overlay** growth: observation → nightly delayed-reward proposals) | [caty-ai/persona-growth-loop](https://github.com/caty-ai/persona-growth-loop) (public since 2026-08-14, MIT; latest v0.3.0) | local-face nightly loop live in production since 2026-08-05; engine-face observation live, injection behind its approval gate | data plane: aggregates only, no raw phrase bodies. Enqueue/results/templates unused. Growth-write is NOT a harness seam — it is a separate plugin↔pack-repo contract (plugin `INTEGRATION.md` pins `HARNESS_VERSION=v0.2.2`) | the maintainers |
