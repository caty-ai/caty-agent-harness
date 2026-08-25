# Benchmark — sealed, pre-registered, machine-scored

[English](benchmark.md) | [日本語](benchmark.ja.md) ｜ back to the [front page](../README.md)

This page carries the full numbers behind the README claim — including the
places where the harness did **not** win. One benchmark lane exists per model;
new lanes are added as they are measured (tracking:
[#129](https://github.com/caty-ai/caty-agent-harness/issues/129)).

---

## What was measured

The failure this product exists for: an AI that says **"done!" without having
done the work**. We measured it on context-overflow workloads — jobs whose
reading volume exceeds one context window (M ≈ 150K and L ≈ 300K tokens; the
S ≈ 75K size fits in-context and serves as the control).

- **Verified completion** (`task_resolved`): the run passed a sealed machine
  gate (schema + *measured* read coverage from transcripts + verbatim-quote
  existence + degenerate-answer lint) **and** scored 20/20 against a hidden
  answer key.
- **Completion hallucination**: a structured completion claim (full deliverable
  written) whose *measured* coverage shows the corpus was not actually read.
  Self-reported "I read everything" logs are never trusted — the tool-call
  transcript is.

## Lane 1 — Claude Haiku 4.5 (2026-08)

Setup: 3 task genres (fictional-corpus research / real-OSS code questions on a
pinned VS Code checkout / CSV extraction) × 3 sizes (S≈75K, M≈150K, L≈300K
tokens) × 5 independent instances × arms. Arms: **bare** (single best-effort
prompt, up to 10 attempts), **harness** (`install.sh` full install, task-file
operation, product defaults), and a **naive-retry control** (bare + previous
answers fed back, M size only). Equal token caps per size for every arm. Both
arms were restricted to the same three tools — Read, Glob, Write; **no
search** — to force actual reading; results do not extrapolate to
search-enabled operation. Attempt units differ by design: bare had a safety
cap of 10 attempts, the harness ran product-default budgets (16 attempts /
90 min at S/M, 24 / 150 min at L). 14 of bare's 30 M/L runs ended on its
attempt cap; the token caps — the binding resource — were identical for every
arm.
Order: hypotheses and analysis pre-registered → corpora, graders and runners
hash-sealed (`SEAL-MANIFEST`, 185 files) → then the runs. Scoring is machines
only; near-miss adjudication was done arm-blind (54 candidates, 3 accepted —
one per arm).

### Primary result — verified completion on M/L (context-overflow) sizes

| | bare | harness |
|---|---|---|
| Verified completion, M/L pooled (n=30/arm) | 4/30 (13%, CI 5–30%) | **13/30 (43%, CI 27–61%)** |

Effect **+30 pt**, stratified exact test **p = 0.0079** (the rig's
pre-registered exact test). Naive-retry control:
2/15 (13%) at comparable cost to bare — retrying alone does not close the gap.

Per genre (M/L pooled): research 4/10 → 7/10 · code questions 0/10 → **6/10** ·
CSV **0/10 → 0/10** (see limitations).

### Completion hallucination — the headline number

"Completion hallucination" here means a completion claim whose *measured*
coverage shows the corpus was not actually read. Both pools, labeled:

| unread completion claims (per claim) | bare | harness |
|---|---|---|
| context-overflow sizes M/L (30 runs/arm) | 222/226 (**98%**) | 2/26 (**8%**) |
| all sizes S+M+L (45 runs/arm) | 247/263 (94%) | 2/41 (5%) |

The failure shapes are qualitatively different: bare's failed claims are
overwhelmingly *unread* claims. The harness almost always reads everything
before claiming anything — 2 of its 19 unverified deliveries (all sizes)
contained unread files, and both were caught — and when it cannot progress it
stops honestly (no-progress) instead of declaring success.

We split hallucination three ways (M/L pool) and **only the completion kind
collapsed — and within it, specifically the unread shape**:

| hallucination kind (M/L) | bare | harness |
|---|---|---|
| false completion — claimed done, delivery not verified (per claim) | 222/226 (98%) | 13/26 (50%) |
| …of which unread-type (measured coverage gap) | 222/226 (98%) | 2/26 (8%) |
| wrong answers (per-item error rate) | 22–31% | 24–38% |
| unsupported quotes (quote doesn't back the answer, totals) | 138 | 166 |

The harness does not make the model smarter per answer — wrong answers and
loose quotes remain, and half of its overflow-size deliveries still failed
verification. What collapses is the **unread claim**: saying "done" without
having done the reading.

### Time and cost (totals per 15 runs)

| size | bare | harness |
|---|---|---|
| M | 2.3 h / 122M tokens | **1.3 h / 50M tokens** |
| L | 3.9 h / 241M tokens | **2.3 h / 98M tokens** |

Bare burns its budget re-reading the corpus on every failed retry; the harness
resolves in fewer, structured attempts. At overflow sizes it is **cheaper and
faster while completing 3× as often**.

### Verified completion by size (all genres)

| size | bare | harness |
|---|---|---|
| S (≈75K) | 10/15 (67%) | 9/15 (60%) |
| M (≈150K) | 4/15 (27%) | 8/15 (53%) |
| L (≈300K) | **0/15 (0%)** | **5/15 (33%)** |

## Limitations — read these before quoting the numbers

- **CSV genre: both arms 0/10 at M/L.** Verbatim-quote transcription of CSV
  rows exceeds what Haiku 4.5 reliably does; the gate catches it in both arms.
  This stratum detects no arm difference — we say so instead of dropping it.
  Aggregation-style work (sums, group-bys) is **unevaluated**: the CSV genre
  tests extraction/transcription only.
- **S size shows no advantage** (67% vs 60%): if the job fits comfortably, the
  bare model is fine. The product's value starts where context overflows.
- **Single model.** Everything above is Haiku 4.5. Other model lanes are
  planned ([#129](https://github.com/caty-ai/caty-agent-harness/issues/129))
  and will be added to the README table as they are measured.
- **43% is not 100%.** The harness failed 17/30 M/L runs — honestly (verified
  stop or gate-rejected delivery), but it failed. The claim is *verified
  completion and honest reporting*, not perfection.
- All runs executed in the author's environment. Two transient CLI outage
  bursts occurred; affected sequences were re-run under the pre-registered
  infra procedure. Two sequences needed a second re-run — one more than the
  procedure's default, recorded as a deviation. Final data contains zero
  infra-terminated runs.

## Reproduce / audit

Design (5-seat cross-model review), pre-registration, raw writeback and the
adjudication log live in
[harness#100](https://github.com/caty-ai/caty-agent-harness/issues/100)
(final results comment).

The scored aggregate is now in this repository at
[`docs/benchmark/ev006-aggregate.json`](benchmark/ev006-aggregate.json). Its
SHA-256 is
`61dad2cb43a11ce8ae9f6b0e82d492c71b6b46eae27a07418fd90fa673cf3848`.
It contains scores only: `cells` has one row for each of the 105 benchmark
runs, while `table` is a pre-aggregated summary. The recomputation script uses
`cells`, not `table`. The file does not contain transcripts or prompts. Raw
per-run artifacts (transcripts, gates, scores, ledgers) remain retained offline
and available on request — they are too large to vendor into this repository.

The rig's seal manifest is `corpora/main/SEAL-MANIFEST.txt`: 185 files, sealed
at `2026-08-19T03:36:09Z`, with scope `corpora/main tools runner
(py/md/json/sh) + design v3 + PREREGISTRATION`. The manifest itself is not
vendored; its SHA-256 is
`f31e9af832d7ac54922f5176228172aecadd080ff46f8d6a73e331d598389cb0`, so a
reader who requests the corpus can verify that they received what was
measured.

From the repository root, recompute the published headline and size results:

```sh
python3 docs/benchmark/recompute.py
```

```text
Primary result (M/L pooled)
  bare verified completion: 4/30 (13%)
  harness verified completion: 13/30 (43%)
  bare unread completion claims: 222/226 (98%)
  harness unread completion claims: 2/26 (8%)
Verified completion by size
  S: bare 10/15 (67%), harness 9/15 (60%)
  M: bare 4/15 (27%), harness 8/15 (53%)
  L: bare 0/15 (0%), harness 5/15 (33%)
```

That vendored aggregate backs the headline verified-completion and completion-
hallucination figures, the per-size and per-genre splits, the token/time
reductions, the Wilson confidence intervals, and the other per-run derivations
on this page from the same 105 scored runs. Two numbers do not come from this
file: `p = 0.0079` and the "3 accepted" out of the 54 near-miss candidates.
Those come from the rig's pre-registered scoring and adjudication, documented
in [harness#100](https://github.com/caty-ai/caty-agent-harness/issues/100).
For the figures the script covers, if the script's output disagrees with the
prose, the prose is wrong.

---

<a id="ev-008"></a>

## EV-008 — overflow sentinel, per-model activation profiles (2026-08)

A separate sealed, pre-registered experiment on the **overflow sentinel**
(adaptive activation — [design issue
#159](https://github.com/caty-ai/caty-agent-harness/issues/159)): instead of
running the harness always-on, a sentinel watches the measured per-turn
context level and fires only when a threshold (80K tokens or 50 % of the
window, whichever is lower) is crossed — stopping the run and decomposing the
job before the context overflows.

Setup: per model, 4 sealed cells (M/L sizes × 2 instances), arms **bare** /
**always-on harness** / **sentinel**, 20 hidden-key questions per cell.
Pre-registration, seal ledger, per-run ledgers and sentinel event logs live
with the rig; the numbers below were regenerated deterministically from the
primary ledgers (`step5-reconcile.py`) on 2026-08-25. Design and review
records: [#159](https://github.com/caty-ai/caty-agent-harness/issues/159).

### Result matrix

| Model | Cells | Sentinel fires | Correctness (fired cells) | sentinel/bare token ratio (median of 4 pairs) |
|---|---|---|---|---|
| claude-sonnet-5 (confirmatory) | 4 | 4/4 | 20/20 all | **0.801** (0.286 / 0.710 / 0.892 / 1.114) |
| claude-opus-5 (descriptive, post-GO) | 4 | 4/4 | 20/20 all | **0.923** (0.726 / 0.913 / 0.932 / 0.940) |
| claude-haiku-4.5 (descriptive) | 4 | 4/4 | 19–20/20 | 0.35 (phase-confound caveat below) |
| gpt-5.6-luna / Codex (confirmatory) | — | **0/127 turns** (M4 38 + diagnostics 45 + M4′ 44) | n/a (never fired) | tap-overhead geometric mean **0.9944** ≤ 1.05 (M4′, n=3/pair M-tier) |
| qwen3.8-max (confirmatory no-fire) | 4 | **0/4** (max injected 68.8K–79.7K @ 80K) | n/a (never fired) | no-fire endpoint — ratio not the endpoint |
| grok-4.6 (descriptive, candidate) | 4 | 4/4 (turns 6/6/6/8) | 20/20 all | **2.145** (1.611 / 1.775 / 2.514 / 4.057) — fires correctly, never pays |

Absolute token charge per cell (sonnet / opus, bare → sentinel; transcribed
from the `step5-reconcile.py` re-run of 2026-08-25):

| Cell | sonnet bare → sentinel | opus bare → sentinel |
|---|---|---|
| M-i2 | 2,904,275 → 3,236,215 (+11 %) | 4,562,380 → 4,254,102 (−7 %) |
| M-i3 | 3,475,997 → 3,101,258 (−11 %) | 4,302,965 → 3,927,008 (−9 %) |
| L-i2 | 16,597,756 → 4,746,361 (−71 %) | 11,288,180 → 8,192,586 (−27 %) |
| L-i3 | 7,581,249 → 5,385,942 (−29 %) | 6,992,297 → 6,574,909 (−6 %) |

The saving scales with job size: sonnet's L-band cells cut 71 % / 29 % while
its M-band cells sit at −11 % / +11 % — a bare run that overflows has to
re-read what fell out of context, so the bigger the job, the more waste the
sentinel's decomposition avoids.

The default-on GO decision (2026-08-25) rests on four pre-registered
conditions: codex fire rate 0 (0/127; rule-of-three 95 % upper bound
2.4 %/turn) · codex tap-overhead GM ≤ 1.05 (0.9944) · sonnet all-pair median
< 1.0 (0.801) · no consistent harmful false-fire (1/4 pairs only). qwen adds
a second no-fire lane: 0 fires across 669 sentinel turn events
(102/116/205/246 per cell; recounted from the per-run sentinel event logs,
quarantined partial excluded, 2026-08-25) — 95 % upper bound ≈0.45 %/turn.

### Read these before quoting (inseparable from the GO)

1. **The codex condition FAILed first.** M4 (n=1 per pair) came out at
   geometric mean **1.337** — a pre-registered FAIL, sent back per protocol.
   Diagnostics attributed it to run-to-run variance (repeat ratios 0.44–1.81;
   arm difference vanishes at pooled n=4). The passing 0.9944 comes from M4′
   (n=3 per M-tier pair, a data-informed post-design sealed via a 3-seat
   delta review). The FAIL is history to carry, not to erase.
2. **The stretch goal was missed.** sonnet's median 0.801 met the decision
   threshold (<1.0) but not the pre-registered stretch goal (<0.8) — by
   0.001.
3. **Residual uncertainty is real.** Standard cells are n=1 per pair (only
   M4′ M-tier is n=3). Between-run SD ≈ 30–40 % of the mean at M-tier; even
   at n=3 the ratio SE is ≈25 % — 0.9944 is "inside the threshold", not
   "clearly below it".

### Third finding — firing is not the same as paying

grok-4.6 is the measured counter-example to "it fires, so switch it on": the
sentinel fires early (turn 6–8), decomposition works, correctness holds
20/20 — and the median cost ratio is still 2.145, because bare grok runs are
extremely cheap (0.76–2.4M tokens where sonnet bare burns 2.9–16.6M). The
default-on judgement is economic (sentinel vs bare), not mechanical (does it
fire). Default-on is not recommended for this profile.

### Blind telemetry paths

Through the current shim, glm / muse report all-zero per-turn usage and kimi
emits no usage at all. No live water level → no sentinel. Profiling a new
model starts with one live run confirming every telemetry field carries real
values (mock passes do not exercise the live path — measured the hard way).

### Deviations and re-runs (all recorded in the rig's correction ledger)

- Two cells were re-run under the pre-registered infra procedure (opus L-i3:
  a hook mis-wiring blocked all Write tool calls, zero task writes possible;
  qwen L-i2: provider quota interruption). Partial first-attempt evidence is
  quarantined alongside the re-run records. A sensitivity check (2026-08-25)
  confirms the core confirmatory numbers (0.801 / 0.9944 / 0/127) contain
  **zero re-run data**.
- haiku's lane predates a mid-experiment protocol revision: its sentinel arm
  ran entirely after, bare/always entirely before (arm/phase confound).
  Completion rates are flat across the boundary, but haiku's token-economy
  figure cannot be fully deconfounded — treat 0.35 as descriptive only.
- One primary ledger file (haiku L-i1 bare) is missing from the archive; its
  token figure is carried from the module report (the score file survives).

The full final report, pre-registration with its correction ledger, and the
per-model module reports live with the rig and are surfaced through
[#159](https://github.com/caty-ai/caty-agent-harness/issues/159).
