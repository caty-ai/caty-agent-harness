# Design lane: #159 overflow sentinel (design record — not yet shipped as a product feature)

Status: design **v0.5** — upstream design review passed (3 heterogeneous seats, 3 rounds,
cumulative GO — see `reviews/ADJUDICATION-r3-FINAL.md`), and the validation experiment
**EV-008 completed on 2026-08-25 with a default-on GO declaration** (owner decision; results,
the four GO conditions, and three mandatory caveats are transcribed in `DESIGN.md` §0).
Implementation is tracked separately from this design lane.

- `DESIGN.md` — overflow sentinel design v0.5 (trigger predicate, tap contract, thresholds,
  fire log schema, v1 = recommend-only; §0 = EV-008 results and GO declaration as current state)
- `EV008-PREREG.md` — **pre-sealing rolling draft snapshot (DRAFT v0.3, published for
  provenance)**. The sealed instrument actually governing the run (`EV008-PREREG-DRAFT.md`
  SEALED v1.0 + per-module seal ledger + r4/r5 adjudications) stays on the local rig per the
  publication policy below. Account-operations details are redacted in the published copy.
- `EV008-LITE-RESULTS.md` — exploratory lite results (3 live runs + zero-cost replay
  calibration; exploratory only — superseded statements are flagged in a banner note)
- `reviews/` — review record: per-round adjudications and verbatim seat outputs of the
  kimi-k3 / grok-4.6 / glm-5.3 panel, plus the codex advisory opinion verbatim
  (`out-codex-r2.md`); the fable/opus advisory opinions are summarized inside the
  adjudications rather than included verbatim.

Raw experiment data (transcripts, sealed corpora, per-run artifacts) intentionally stays on the
local rig per the maintainers' current publication policy; summary numbers quoted here match the
correction comments already posted on #129 / #159.

File paths inside these documents refer to the local experiment rig and are kept verbatim for
provenance; they are not expected to resolve in this repository.
