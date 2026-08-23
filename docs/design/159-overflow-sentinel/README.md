# Design lane: #159 overflow sentinel (DRAFT — not merged, not shipped)

Status: **design phase**. These documents passed the upstream design review (3 heterogeneous
seats, 3 rounds, cumulative GO — see `reviews/ADJUDICATION-r3-FINAL.md`) and are published here
as a draft PR so the design referenced by issue #159 has a durable, reviewable home.

- `DESIGN.md` — overflow sentinel design v0.4 (trigger predicate, tap contract, thresholds,
  fire log schema, v1 = recommend-only)
- `EV008-PREREG.md` — pre-registration draft v0.2 for the 3-arm validation experiment
  (not yet sealed; sealing happens after the quota/schedule plan is fixed)
- `EV008-LITE-RESULTS.md` — exploratory lite results (3 live runs + zero-cost replay
  calibration; grounds the go decision for the full run)
- `reviews/` — full review record: per-round adjudications and verbatim seat outputs
  (kimi-k3 / grok-4.6 / glm-5.3 panel + advisory opinions)

Raw experiment data (transcripts, sealed corpora, per-run artifacts) intentionally stays on the
local rig per the maintainers' current publication policy; summary numbers quoted here match the
correction comments already posted on #129 / #159.

File paths inside these documents refer to the local experiment rig and are kept verbatim for
provenance; they are not expected to resolve in this repository.
