# Benchmark — sealed, pre-registered, machine-scored

[English](benchmark.md) | [日本語](benchmark.ja.md) ｜ back to the [front page](../README.md)

This page carries the full numbers behind the README claim — including the
places where the harness did **not** win. One benchmark lane exists per model;
new lanes are added as they are measured (tracking:
[#129](https://github.com/caty-ai/caty-agent-harness/issues/129)).

## The five experiment families — how to read this page

1. **EV-006 — bare vs the shipped harness.** Does external machinery rescue
   completion? Main run on claude-haiku-4.5 (the headline 13%→43%); the **P1
   model swap** repeats the sealed design on sonnet-5 / opus-5 and answers
   "was that just because haiku is weak?" — see [EV-006 P1](#ev-006-p1).
2. **EV-008 — bare vs the overflow sentinel** (adaptive activation instead of
   always-on). Per-model activation profiles, the default-on GO conditions,
   and an **n=3 repetition addendum** with confidence intervals — see
   [EV-008](#ev-008) and [the addendum](#ev-008-n3).
3. **P2-WIN — bare models only.** Where does completion stop as jobs outgrow
   the window, and what does failure look like — see [P2-WIN](#p2-win).
4. **EV-009 — bare vs harness inside the overflow bands.** The intervention
   arm P2-WIN deliberately left out: 8 sealed hold-out runs (including the
   pre-registered honest-failure branch), zero deviations — see
   [EV-009](#ev-009).
5. **EV-007 / EV-007b / EV-007c — the learning loop.** Does "review, then
   promote" stop the same mistake coming back? Three lanes, three sealed runs.
   The first two produced **no learning-effect number at all**: EV-007's review
   fail-closed twice and the run terminated; EV-007b built a trap-injected
   instrument that finally *does* produce repeat mistakes (in the learning arm, 8
   of 8 mistake classes recurring in every round) and ran its sealed main run on
   it — and all three of that run's review turns also fail-closed, so nothing was
   promoted in either lane. **EV-007c is the third lane and the first with
   learning events** — 3 turns, 3 reviews, 6 promotions, 2 approved rules on
   v0.25.0 — so it is also the first in which the sealed pass/fail line could be
   evaluated. It was: outcome row 8, **fail — the pre-registered line was not
   met** (learning-arm repeat rate 0.667 vs 0.727, DiD +0.050). Measured once,
   n = 1. See [EV-007](#ev-007).

Every main run here was sealed and pre-registered before it started, EV-007b's
main run (sealed 2026-09-04, pin `v0.24.0`) and EV-007c's (sealed 2026-09-05, pin
`v0.25.0`) included; EV-007b's calibration pilots and the instrument search ran
pre-seal under a pre-written rule, its three post-seal corrections are ledgered as
superseding records, and EV-007c recorded no post-seal correction at all.
Everything is machine-scored, and reported with its limitations attached —
including the places where the harness did not win.

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

<a id="ev-006"></a>

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
- **Single model.** Everything above is Haiku 4.5. Further completion-rate
  lanes are tracked in
  [#129](https://github.com/caty-ai/caty-agent-harness/issues/129); measured
  cross-model EV-008 profiles live in the [matrix below](#ev-008) and the
  README's per-model section.
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
EV-006 charge tokens
  M: bare 122,050,790 → harness 49,631,455 (−59.3%)
  L: bare 241,179,467 → harness 98,312,729 (−59.2%)
  M/L pooled: bare 363,230,257 → harness 147,944,184 (−59.3%)
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

<a id="ev-006-p1"></a>

## EV-006 P1 — the model swap: was the rescue just haiku being weak? (2026-08)

The external question after the main run: "+30pt appeared on a weak model —
would it survive on strong ones?" P1 repeats the sealed design (same corpora,
goals, budgets, scoring; only the model field swapped, original seal hash
untouched) on **claude-sonnet-5** (90 seqs) and **claude-opus-5** (60 seqs,
M/L only). Public record: [#129 comment](https://github.com/caty-ai/caty-agent-harness/issues/129#issuecomment-5457130272).

`correct_resolved` = correct against the hidden answer key with delivery verified — the pre-registered secondary endpoint (the primary, `task_resolved`, is discussed below).

| Model | Completion, bare vs harness | Efficiency, bare÷harness median charge |
|---|---|---|
| claude-haiku-4.5 (main run) | 13% vs 43% (M/L pooled, task_resolved) | tokens −59% |
| claude-sonnet-5 | 28/30 vs 28/30 — dead even (correct_resolved) | S 0.52× · M 0.63× · **L 2.40×** |
| claude-opus-5 | 30/30 vs 30/30 — full ceiling, zero false completions (correct_resolved) | M 1.17× · **L 1.46×** |

Read before quoting:

- The completion rescue is **haiku-band-only** — strong models complete these
  jobs bare. What they gain instead is **same-accuracy token savings emerging
  at the L band** (a ratio above 1.0 = the harness used fewer tokens; sonnet's
  S/M cells sit below 1.0 — the harness used more tokens where the job fits
  comfortably).
- On the primary `task_resolved` metric, sonnet's harness arm shows −27pt —
  entirely p2 read-coverage-style violations (the known selective-reading
  artifact; the pre-registered secondary endpoint `correct_resolved` corrects
  it, and the near-miss ledger for P1 is empty). Both metrics are reported.
- The pilot's n=1 opus-L ratio overshot the final value; it converged to
  **1.46×** at n=15 — a live demonstration of why single-pair ratios are
  unreliable (see also the [EV-008 n=3 addendum](#ev-008-n3)).
- opus never overflowed on this corpus band (perfect ceiling) — which is what
  motivated [P2-WIN](#p2-win): find where the band actually is.

---

<a id="ev-008"></a>

## EV-008 — overflow sentinel, per-model activation profiles (2026-08)

A separate sealed, pre-registered experiment on the **overflow sentinel**
(adaptive activation — [design issue
#159](https://github.com/caty-ai/caty-agent-harness/issues/159)): instead of
running the harness always-on, a sentinel watches the measured per-turn
context level and fires only when a threshold (80K tokens or 50 % of the
window, whichever is lower) is crossed — stopping the run and decomposing the
job before the context overflows. Sentinel v1 later shipped as an opt-in
feature for the claude-code runtime in v0.17.0
([#180](https://github.com/caty-ai/caty-agent-harness/issues/180),
implementing [#159](https://github.com/caty-ai/caty-agent-harness/issues/159)),
but the EV-008 numbers here remain rig pre-measurements taken ahead of that
implementation and have not been re-measured on the shipped implementation.

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
| gemini-3.7-flash (descriptive, M6 addendum — outside the pre-registered GO conditions) | 4 | 4/4 (turns 31/36/75/82; max injected 82.1K–90.6K @ 80K) | mixed — see the per-cell table below | ratio median not quoted: only 1 pair (M-i2) completed on both arms — cannot support an efficiency claim |

Expressed as a reduction, the ratio converts as `1 − median(sentinel/bare)`,
with the minus sign showing lower token charge:
sonnet **0.801** → −20%; opus **0.923** → −8% (rounded to whole percent).

Absolute token charge per cell (sonnet / opus, bare → sentinel; transcribed
from the `step5-reconcile.py` re-run of 2026-08-25):

| Cell | sonnet bare → sentinel | opus bare → sentinel |
|---|---|---|
| M-i2 | 2,904,275 → 3,236,215 (+11 %) | 4,562,380 → 4,254,102 (−7 %) |
| M-i3 | 3,475,997 → 3,101,258 (−11 %) | 4,302,965 → 3,927,008 (−9 %) |
| L-i2 | 16,597,756 → 4,746,361 (−71 %) | 11,288,180 → 8,192,586 (−27 %) |
| L-i3 | 7,581,249 → 5,385,942 (−29 %) | 6,992,297 → 6,574,909 (−6 %) |

Bare-arm correctness in that 2026-08-25 reconcile was 20/20 for both sonnet
and opus in every cell (M-i2, M-i3, L-i2, L-i3); their sentinel arms likewise
scored 20/20 in all four cells.

The saving scales with job size: sonnet's L-band cells cut 71 % / 29 % while
its M-band cells sit at −11 % / +11 % — a bare run that overflows has to
re-read what fell out of context, so the bigger the job, the more waste the
sentinel's decomposition avoids.

gemini-3.7-flash per cell (descriptive, firing type — early onset; outside
the pre-registered GO conditions; transcribed from the M6 addendum reconcile,
2026-08-25):

| Cell | bare charge (correct) | sentinel charge (correct) | note |
|---|---|---|---|
| M-i2 | 24,293,164 (20/20) | 11,000,858 (20/20) | both arms completed |
| M-i3 | 10,505,090 (19/20) | 11,169,170 (0/20) | sentinel child steps stalled (headless command-permission denial loop — model behaviour, not a rig fault) |
| L-i2 | 24,978,973 (0/20 — token-budget collapse) | 7,514,166 (0/20) | bare collapsed; sentinel child stalled (same cause as M-i3) |
| L-i3 | 33,149,893 (0/20 — token-budget collapse) | 19,619,857 (20/20) | **decomposition rescued completion** |

Read honestly: bare gemini collapses in the L band (2/2 cells hit the token
budget with no answers written). The sentinel fired 4/4 and rescued L-i3
outright — but 2 of 4 sentinel cells still scored 0 because the decomposed
child steps kept requesting the shell permission that headless execution
auto-denies. No token-ratio median is quoted for this model: with only one
pair completed on both arms, the ratio cannot support an efficiency claim.

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

<a id="ev-008-n3"></a>

### The n=3 repetition addendum — putting intervals on the single-run ratios (2026-08-29)

The FINAL report's stated residual uncertainty was that standard-cell pair
ratios were n=1 with run-to-run SD ≈ 30–40% of the mean. The addendum re-ran
the 4 standard cells × 2 arms × 2 extra reps per model under the sealed
module conditions (rep1 = the sealed main-run results, reused; account
rotation across reps; pre-registered locally with its own seal before
launch). 16/16 new runs driver-ok; all 16 sentinel runs fired. Public
record: [#159 comment](https://github.com/caty-ai/caty-agent-harness/issues/159#issuecomment-5457351973).

Pooled pair ratio (12 log-ratios per model, t-based 95% CI, df=11):

| Model | pooled GM | 95% CI | verdict (pre-registered rule) |
|---|---|---|---|
| claude-sonnet-5 | **0.617** | [0.439, 0.867] | savings confirmed — robustly below 1.0 |
| claude-opus-5 | **0.806** | [0.651, **0.997**] | savings confirmed — but the upper bound is 0.997: a razor-thin exclusion, not a comfortable one |

- The single-run medians (sonnet 0.801, opus 0.923) sat inside these
  spreads; individual reps ranged **0.28–1.50 under identical conditions** —
  the n=1 caveat was warranted.
- Correctness: 15/16 new runs 20/20; one 19/20 (same lone-miss pattern as the
  main run). Disclosed; no endpoint impact.
- This tightens the shipped claim: sentinel token savings on window-firing
  models is now backed by n=3 with intervals, not single runs. The sentinel
  itself remains **opt-in** on the shipped claude-code runtime (v0.17.0,
  `OVF_SENTINEL=shadow|active`, unset = byte-identical passthrough) and has
  not been re-measured on the shipped implementation.

---

<a id="p2-win"></a>

## P2-WIN — where run completion stopped: three size bands on bare models (2026-08)

A third sealed, pre-registered experiment, run on the same rig and corpus
family as EV-006. **Bare models only — no harness, no sentinel.** Instead of
measuring an intervention, it characterizes the jobs: at what job size do runs
stop completing, and what does the failure look like when they do? All 18
scheduled runs executed (2 models × 3 bands × 3 seeds), zero infra failures,
one recorded operational deviation (a slot change in the opus phase, in the
deviations ledger).

"Completion" on this page is the run's sealed protocol gate
(`protocol_accept`) — a different metric from EV-006's *verified completion*
(`task_resolved`); the two are not comparable across pages. The claim level
was frozen in the pre-registration before any run: descriptive tables only —
no tests, no effect sizes, no generalization beyond the n=2 hold-out seeds per
cell. Every number below is machine-computed by the sealed formulas (frozen
checkpoint tool).

Setup: synthetic research corpora from a sealed generator at three sizes —
**XL ≈ 600K**, **XXL ≈ 1.2M**, **XXXL ≈ 2.4M** tokens (for scale, 1.2M is
roughly 1.2× the product-default context window of the measured models).
Within a seed the bands are nested supersets sharing the same 20 hidden-key
questions; **seeds differ — each seed is a different corpus**. Two hold-out
seeds (9103/9104) decide every judgement; a third seed (9102), already used in
the earlier probe phase, is therefore treated as a calibration seed in this
study — its cell runs here are fresh P2-WIN runs, not reused probe data, and
they are disclosed separately, never pooled into a judgement. Each cell ran up
to 10 cold-start attempts under a per-band token budget (44M / 88M / 176M);
the budget is a stop trigger evaluated after each attempt completes, not a
hard cap — overruns are possible. Attempts are independent re-samples with no
feedback between them, not learning retries.

### Completion (k/2 hold-out seeds, terminal reason in parentheses)

| Band | claude-sonnet-5 | claude-opus-5 |
|---|---|---|
| XL (≈600K) | **2/2** | **2/2** |
| XXL (≈1.2M) | 0/2 (token budget ×2) | **1/2** (one completed; one hit token budget) |
| XXXL (≈2.4M) | 0/2 (token budget / attempts budget) | 0/2 (attempts budget ×2) |

### Transfer band — the frozen rule, then the result

The rule, sealed before the runs: a "transfer band" (the smallest band with
0/2 completion) may be reported **only** when both hold-out seeds agree and
the pattern is monotonic in band size. Otherwise the report is **no unique
transfer**, and no band is named in prose either.

- **sonnet**: both seeds agree (XL completes, XXL/XXXL do not), monotonic →
  **transfer band = XXL** — as a description of this table, not a cliff
  position for the model.
- **opus**: the two hold-out seeds — same band and protocol, different
  corpora — disagreed in one band (one completed, one did not; the table
  shows which) → **no unique transfer**. Per the frozen rule, no band is
  named as the transfer. At XXXL both seeds were 0/2.
- Calibration seed 9102 (sonnet: completed XL only; opus: completed XL and
  XXL) is shown for context and used in no judgement.

### Attempt-1 read coverage (coverage_001 — share of corpus *files* read, per ticket)

| Band | sonnet 9103 / 9104 | opus 9103 / 9104 |
|---|---|---|
| XL | 1.000 / 1.000 | 1.000 / 1.000 |
| XXL | 0.905 / 0.161 | 0.181 / **1.000** |
| XXXL | 0.294 / 0.139 | 0.041 / 0.024 |

![Scatter plot of the 12 sealed P2-WIN hold-out runs. x-axis: share of corpus files read on attempt 1, log scale from 2% to 100%. y-axis: probe score out of 20 against the hidden answer key. The opus 2.4M-band points sit at 2–4% coverage yet score 20/20; one sonnet point scores 3/20 despite 90% read; five points sit at 100% coverage and 20/20, dodged horizontally for visibility.](../assets/readme/p2win-coverage-vs-score.svg)

The picture the table compresses: **the probe score alone cannot tell whether
the files were read.** The plotted opus ≈2.4M-band tickets read 2–4% of the
files and still scored 20/20, while the deepest low-score outlier is a sonnet
burn-through ticket that *had* read ~90% of the corpus. In these 12 runs, only
the measured read coverage separated reading from scoring. (Sealed values
only: coverage from the report's coverage_001 table above, scores from the
per-run `score.json`. Descriptive — no intervention claim.) The follow-up
experiment inside these two bands is [EV-009](#ev-009).

### Degradation bits (k/2 hold-out cells where the bit fired)

| Band | sonnet repeat-gate / correct<20 | opus repeat-gate / correct<20 |
|---|---|---|
| XL | 0/2 · 0/2 | 0/2 · 0/2 |
| XXL | 0/2 · 1/2 | 0/2 · 1/2 |
| XXXL | 0/2 · 1/2 | 0/2 · 1/2 |

### Two failure shapes (per-ticket descriptions — not model laws)

- **Burn-through (sonnet tickets)**: past the band, these tickets keep trying
  to read and burn the token budget — 3 of sonnet's 4 non-completing hold-out
  cells ended on token budget. Answer quality dropped in some tickets (one XXL
  ticket fell to 3/20 on attempt 1; one XXXL ticket slipped 19→18).
- **Early cut (opus tickets)**: at XXXL, all three seeds show the same shape —
  from attempt 1 the run reads only a few dozen files (attempt-1 file-count
  coverage 0.02–0.04), submits early, and consumes all 10 attempts that way.
  Across all 30 opus XXXL attempts (3 seeds × 10, including calibration seed
  9102 — which is not part of the transfer judgement) opus still scored
  **19–20/20 with zero repeat-gate firings**: these tickets abandon the
  reading, not the answering.
- Where correctness dipped below 20/20 elsewhere, the shape was mostly a
  single dropped needle (19/20); genuine answer degradation appears only in
  the sonnet tickets above and in isolated repeat-gate firings on the
  calibration seed.

### Cost

Total charge ≈1.429 B tokens (sonnet 971.3 M + opus 457.8 M), under the 2.5 B
stop trigger. Heaviest observed cell: 327.4 M (XXXL) — over that band's 176 M
budget because the budget is evaluated after each attempt completes (see
Setup).

### What this feeds — design material for #159, not claims

1. In these runs, answer correctness was a weak overload signal — opus kept
   scoring 19–20/20 at 2.4× its window while barely reading. The observable
   candidate signals were **read-coverage progress** and **early submission**;
   whether they work as detectors is to be tested in #159, not established
   here.
2. One band split the two hold-out seeds (same band and protocol, different
   corpora — the table shows which) — in these runs a per-band binary did not
   describe the boundary, which points the threshold design toward a
   continuous headroom quantity.
3. The two failure shapes have opposite cost structures (token budget binds
   first vs attempt budget binds first) — budget guards likely need per-model
   consideration.

All three feed the data-derived-threshold design tracked in
[#159](https://github.com/caty-ai/caty-agent-harness/issues/159); none is a
claim beyond these 18 runs.

### Limitations — read these before quoting

- **n=2 hold-out seeds per cell, and each seed is a different corpus.**
  opus's 1/2 split says "the seeds disagreed" and nothing more — corpus
  difficulty differences are an unexcluded alternative explanation.
- Bands, metrics and the calibration seed were chosen using earlier probe
  runs — selection information is in the design. The probe data is quarantined
  from every table here.
- **Bare arm only.** No harness or sentinel comparison is made or implied.
- Non-completions include budget censoring — that is why terminal reasons are
  printed in the main table.

### Reproduce / audit

Pre-registration (`PREREGISTRATION-P2WIN.md` v2) with seal ledger
(`SEAL-P2WIN.txt`, SHA-256
`eb9b9582daa5113f86688183f6f44de12f20f8006eeaaab34b9f8b85769c709e`), the
deviations ledger, the review records (3 first-round seats + delta reviews,
one delta recovered by transcript, and the panel record), per-run telemetry
and transcripts live with the rig and are retained offline, available on
request — the same retention policy as EV-006. Anchor: https://github.com/caty-ai/caty-agent-harness/issues/129#issuecomment-5463745355.

---

<a id="ev-009"></a>

## EV-009 — bare vs harness inside the overflow bands (2026-08)

P2-WIN mapped where bare runs stop completing; it deliberately made no
intervention claim. EV-009 is the missing intervention arm: the same corpus
cells, inside the two overflow bands (**XXL ≈ 1.2M**, **XXXL ≈ 2.4M** tokens),
run under the harness's staged decomposition. **Eight sealed runs** (sonnet /
opus × XXL / XXXL × hold-out seeds 9103 / 9104), pre-registered and sealed
before any run — the pre-registration went through a 3-seat blind review that
converged on one CRITICAL (a results-path collision the pilot could not have
caught) and was re-sealed as v2 — then executed same-day in series: **zero
infra failures, zero deviations** (the deviations ledger stayed empty). The
bare comparators are the sealed P2-WIN values, transcribed — not re-run.

**Read this first — it is a regime comparison, not a controlled A/B.** The
bare cells ran under P2-WIN's envelope (token budget 88M / 176M, up to 10
cold-start attempts); the harness cells ran under a band-scaled envelope
(token budget 100M / 200M, attempt caps 42 / 83, plan of 33–67 stages). Three
of the four bare cells were budget-censored under their smaller envelope. The
arm effect and the envelope effect are **not separated**; every statement
below is a per-cell description, not a general law.

"Verified completion" here is the **experiment gate** (`protocol_accept`:
read-verification over the union of all stages, plus the final answers) — not
the harness's own `delivered` status, which is roster-based and does not
verify reading (the 9102 pilot demonstrated exactly that gap, which is why the
endpoint was pinned to the gate in the pre-registration). It is also not the
same bit as bare's single-attempt gate; comparisons hold within a
corpus/seed cell only.

### Primary — verified completion k/2 (terminal decomposition in parentheses)

| Cell | bare (P2-WIN, sealed) | harness (EV-009) |
|---|---|---|
| sonnet XXL | 0/2 (token budget ×2) | 0/2 (delivered ×2 — gate refused on read-verification: honest failure ×2) |
| opus XXL | 1/2 (one token budget) | **2/2** |
| sonnet XXXL | 0/2 (token budget / attempts budget) | 0/2 (delivered ×2 — honest failure ×2) |
| opus XXXL | 0/2 (attempts budget ×2; read coverage 0.02–0.04) | **2/2** |

Because bare opus completed one XXL seed, "the cells bare could not complete"
is not a grouping this table supports — read it cell by cell.

### The honest-failure branch (sonnet) — a pre-registered outcome, not an accident

In all four sonnet runs the harness **delivered**: 20/20 correct on the
hidden key, every quote valid, zero unsupported answers. The experiment gate
then refused verified completion in all four, listing the ~10–12% of corpus
files that appeared in the processing roster without ever being read
(targeted-search behaviour, same shape as the 9102 pilot). This branch was
pre-registered as a publishable outcome, and it doubles as a negative control
on the instrument: within these eight runs, the same gate passed 4 and
refused 4 — it discriminated; it did not rubber-stamp.

### Per-run detail (sealed formulas; unread = files in roster never read)

| model | band | seed | unread / total | read rate | correct | attempts / plan | charge (tokens) | wall |
|---|---|---|---|---|---|---|---|---|
| sonnet | XXL | 9103 | 43/430 | 0.900 | 20/20 | 33/33 | 21,814,452 | 27 min |
| sonnet | XXL | 9104 | 44/429 | 0.897 | 20/20 | 34/34 | 22,023,118 | 28 min |
| opus | XXL | 9103 | **0/430** | **1.000** | 20/20 | 33/33 | 38,278,099 | 32 min |
| opus | XXL | 9104 | **0/429** | **1.000** | 20/20 | 34/34 | 32,763,706 | 30 min |
| sonnet | XXXL | 9103 | 108/879 | 0.877 | 20/20 | 68/67 | 55,908,895 | 60 min |
| sonnet | XXXL | 9104 | 97/848 | 0.886 | 20/20 | 66/66 | 53,226,271 | 57 min |
| opus | XXXL | 9103 | **0/879** | **1.000** | 20/20 | 67/67 | 83,751,901 | 65 min |
| opus | XXXL | 9104 | **0/848** | **1.000** | 20/20 | 66/66 | 82,977,825 | 64 min |

Across the 8 runs: **160/160 correct, zero unsupported answers.** The four
opus runs read 100% of the corpus files with attempts exactly equal to plan
stages (zero wasted attempts) — in P2-WIN the same model's XXXL tickets read
2–4% of the files and kept submitting (the scatter figure in the
[P2-WIN section](#p2-win) shows those bare runs). Coverage is computed on
different planes across arms (bare: attempt-1 gate; harness: run-union
telemetry) — a sealed, footnoted difference.

### Cost and resources

Total charge **390,744,267 tokens** — 32.6% of the pre-registered 1.2B cap
(the stop rule never fired). Per band: XXL ≈ 22M (sonnet) / ≈ 35M (opus) per
run; XXXL ≈ 55M (sonnet) / ≈ 83M (opus) per run. For reference, the heaviest
bare runs in these bands charged up to 98.7M (XXL) and 327.4M (XXXL) — a
regime-caveated reference only (different envelopes; the 327.4M maximum is a
sonnet calibration run). **Per-cell, same-seed cost goes both ways**: opus
XXXL 9103 — bare charged 104.9M and failed, harness charged 83.8M and
completed; opus XXXL 9104 — bare was budget-censored at 28.8M and failed,
harness charged 83.0M. No cost-ratio claim is made. Wall clock: 8 runs in
series, ~6 h (27–65 min per run).

### Calibration (9102) — shown for context, used in no judgement

| model | band | terminal | gate | correct | charge |
|---|---|---|---|---|---|
| sonnet | XXL | delivered | refused (76/417 unread) | 20/20 | 21,081,555 |
| opus | XXXL | delivered | **accepted** (868/868 read) | 20/20 | 92,601,550 |

The pilot informed the design (band-scaled budgets, gate-pinned endpoint) and
is disclosed in the pre-registration's data-informed-design section.

### Read these before quoting (inseparable from the tables)

1. **Regime comparison** — bare and harness ran under different budget
   envelopes; arm and envelope effects are not separated.
2. Hold-out n=2 per cell. Per-cell descriptions and k/2 only — no tests, no
   effect sizes, no model-general laws, no claim that these bands generalize.
3. `protocol_accept` is not the same bit across arms; coverage is computed on
   different planes across arms.
4. Band-scaled budgets and the gate-pinned endpoint came from the 9102 pilot
   (data-informed design, fully disclosed pre-seal).
5. The harness's own `delivered` does not verify reading — that is a finding,
   not a footnote: it is why the endpoint is the experiment gate.

### Reproduce / audit

Pre-registration `PREREGISTRATION-EV009.md` v2 + seal `SEAL-EV009.txt`
(28 files, SHA-256) · 3-seat blind review r1 + delta (`reviews-ev009/`,
adjudication included) · run log `RUN-LOG.txt` · report `EV009-REPORT.md`
(machine-computed from the sealed §2 formulas) · primary data
`results/ev009/{sonnet,opus}/harness/*/` (ledger / gate / score / telemetry +
attempt transcripts), private experiments tree, summarized in
[#235](https://github.com/caty-ai/caty-agent-harness/issues/235).

---

<a id="ev-007"></a>

## EV-007 / EV-007b / EV-007c — the learning loop: does "review, then promote" stop repeated mistakes? (2026-08/09)

The other half of the README claim is that the harness **learns from raw
experience so the next job gets better**. Three lanes were run at it, and they
stop in three different places:

1. **EV-007 — no learning event (instrument failure).** The review fail-closed on
   both sealed attempts and the run terminated with
   `unmeasurable-no-learning-event`; underneath, the instrument had dissolved
   because the product itself got better between pins.
2. **EV-007b — no learning event (review citation check vs flush format).** It
   rebuilt the instrument as a trap-injected corpus that does produce repeat
   mistakes, sealed its pre-registration and ran the full main run — and reached
   the same terminal outcome when all three loop turns fail-closed, this time with
   a mechanism: the review's citation check could not cite the lines the Stop hook
   writes.
3. **EV-007c — learning events, and a measured fail of the line.** On v0.25.0,
   with that mechanism fixed, the same sealed series produced 3 reviews, 6
   promotions and 2 approved rules, so the pre-registered pass/fail line was
   evaluable for the first time. Sealed outcome **row 8 — fail: the line was not
   met** (repeat rate 0.667 vs 0.727; DiD +0.050), with the sealed attribution
   rule **met**.

This section publishes all three stops, their causes, the instrument that finally
worked, and the product changes the lanes produced — the same rule as everywhere
else on this page: the runs that did not deliver a headline get written down too.

**Read this first.** Nothing below is evidence that the learning loop has no
effect, and nothing below is evidence that it has one. What EV-007c adds is a
*measured* result where there was none: one sealed line, evaluated once at n = 1
on a one-bit-per-class instrument, and not met — which is a fail of that line, not
a verdict on the loop. EV-007 stopped on an
**instrument failure**, whose largest single cause is the
product's own improvement between pins: on the 2026-08-19 pin the harness averaged 13.6 wrong
answers per job across the five `p3-M` instances (`p3-M-i1` itself: 14/20, 6 wrong,
7 invalid quotes), on v0.21.1 EV-007's own before-block still made mistakes on it (B 73/80, C 72/80 —
all in j1–j3b; the scored feeder jobs j4–j7 were 20/20, with C-j4 excluded as an
empty run), and by the P0.7 pilot the same `p3-M-i1` scored 20/20
in all four jobs (invalid quotes 0/0/0/5). The measuring stick dissolved because the thing being
measured got better. EV-007b then **rebuilt the measuring stick** — a
trap-injected corpus on which harness + haiku makes the same 8 mistake classes
in every job of the learning arm — and stopped for a different reason: the review step could not
cite the raw layer it was given, so EV-007b's loop promoted nothing to measure.
EV-007c re-ran that same sealed series on `v0.25.0`, where the review can cite;
the loop promoted, the line was evaluated, and the line was not met.

### What was measured

EV-007's pre-registration (sealed 2026-08-27, pin `v0.21.1`) states the claim as:
*"This run measures whether the learning loop as shipped changes downstream task
performance."* Owner design decision **C5** fixed the axis: *"the essential value
of distillation is never repeating the same mistake across future jobs — an asset
that compounds"*, so the primary analysis is **longitudinal** (repeat-mistake rate
before vs after one promotion boundary), not an endpoint race between arms.

Three arms, one task model (claude-haiku-4.5), one persistent workspace per
harness arm:

| arm | what it is |
|---|---|
| A `bare` | model without the harness; fresh workspace per job — the rig/scorer anchor, not a memory condition |
| B `harness-no-learning` | full harness, lessons/rules channel off (no hooks, no intake, no review); episodic channel open by design |
| C `harness-learning` | full harness + raw layer → cross-model review → apply, under the sealed rule-approval policy |

**EV-007b** (successor, home issue
[#264](https://github.com/caty-ai/caty-agent-harness/issues/264)) keeps C5's
headline wording and changes the **count axis**: instead of a calendar boundary
that needs two ISO weeks to promote anything, three same-day learning rounds —
before = round 1, after = the final block — with B and C at 8 jobs each and A
reduced to 2 anchor jobs. Its pre-registration **was sealed** at v0.3.4 on
2026-09-04T11:36Z (sha256 `fff51f7d…be8811`), after a four-seat blind
pre-registration review whose cumulative verdict was GO-WITH-MINOR, and pinned
to `v0.24.0` (`90a602f`). Three post-seal changes were made, each as a
**superseding record in the §7 correction ledger** on an owner decision — the
sealed copy itself was never edited, and none of the three touched the pass/fail
line, the mistake definition, the series or the outcome taxonomy (they are
listed under *Deviations and correction ledger* below).

### Result matrix — EV-007: no learning event

The run executed its sealed clauses to the terminal one:

| sealed clause | event | date | outcome |
|---|---|---|---|
| §5 cannot-measure fallback | before-block j1–j3 yields <3 true-misquotes in the learning arm | 2026-08-28 | extension fired → j3b run in all arms |
| §5 cannot-measure fallback (2nd) | extended before-block j1–j3b still <3 | 2026-08-29 | headline declared **inconclusive** (mechanical) |
| §5 clobber probe | j6 and j7 blocks both in `loop/archive/` after intake | 2026-09-01 | **PASS** |
| §4 review | nightly `raw-review.sh`, single reviewer chain | 2026-09-01 | **fail-closed** (`fabricated=2/4`; threshold `fabricated_floor=2`, `fabricated_pct=50`) |
| §4 fail-close handling | one sealed retry after the next UTC rollover | 2026-09-02 | retry **fail-closed** (`fabricated=3/4`) |
| §4 terminal clause | no learning event → headline unmeasurable → after-block j8–j10 cancelled → run terminates | 2026-09-02 | applied verbatim |

Promotions = **0**, approved rules = **0**. Under the sealed attribution rule
nothing in this run can be attributed to "review, then promote", in either
direction, and there is no after-block in any arm.

The before-block the headline would have been computed on (j1–j3b, 4 jobs and 80
scored items per arm):

| arm | correct | gate-level NG | true-misquotes | mean charge |
|---|---|---|---|---|
| A `bare` | 53/80 (0.662) | 14/80 (0.175) | 14 | 9,126,484 |
| B `harness-no-learning` | 73/80 (0.912) | 0/80 | 0 | 1,806,126 |
| C `harness-learning` | 72/80 (0.900) | 1/80 (0.013) | 1 | 3,531,493 |

That last column of zeros is the finding, and it is why the denominator was
degenerate. Score-level `quote_invalid` per job, in order j1, j2, j3, j3b, j4,
j5, j6, j7: bare **8, 0, 6, 0, 0, 1, 6, 0**; both harness arms **0 in every
job** (15/15 scored harness jobs at score level; 14/15 at gate level — the one
exception is a correct answer with an invalid quote). The harness attempt loop
plus gate feedback removes scorable quote mistakes **within** a job, so the trap
instrument that generates mistake variance on the bare arm generates almost none
under the harness. Arms B and C are indistinguishable on it, and B has the
learning loop switched off — this says nothing about learning.

### Result matrix — EV-007b instrument search: no level qualified (pre-seal)

Everything in this subsection happened **before** the seal, while EV-007b was
still looking for an instrument on which harness + haiku still makes mistakes.
It ran a localization pilot (P0.7) and a two-round
difficulty ladder; the pre-written qualification rule was **mistake(job) = wrong
answer ∪ invalid quote, per question id; a level qualifies if both jobs have ≥2
mistakes and ≥10/20 correct**.

| stage | corpus | posture | correct (2 jobs) | mistakes per job | charge (P0.7: per job; ladder: 2-job total) |
|---|---|---|---|---|---|
| P0.7 | `p3-M-i1` | sentinel active ×2 | 20/20, 20/20 | 0, 0 | 3.69M, 4.25M |
| P0.7 | `p3-M-i1` | sentinel off ×2 | 20/20, 20/20 | 0, 5 (Q06–Q10 invalid quotes) | 4.12M, 4.16M |
| ladder r1 | `p3-S-i1` | active | 19/20, 20/20 | 1, 0 | 4,092,993 |
| ladder r1 | `p2-L-i1` | active | 20/20, 19/20 | 0, 1 | 11,517,917 |
| ladder r1 | `p3-L-i1` | active | 20/20, 19/20 | 0, 1 | 12,622,123 |
| ladder r2 | `p2xxl-L-i9102` (≈1.2M tokens, 33 stages) | active | 20/20, 20/20 | 0, 0 | 44,873,830 |
| ladder r2 | `p2xxxl-L-i9102` (≈2.4M tokens, 66 stages) | active | 20/20, 20/20 | 1, 0 | 87,437,650 |

**No level qualifies** — not one reaches 2 mistakes in both jobs. P0.7 also
falsified its own hypothesis: the overflow sentinel is not the scrubber (the
`neither` decision), and neither is the attempt loop (two of the four jobs
delivered in exactly the plan-step count, with no retries and no mistakes).

The finding, stated as narrowly as the data allows: **harness + haiku scored 19–20/20 on every instrument tried — one instance each of
`p3-M`, `p3-S`, `p2-L`, `p3-L` on v0.21.1 (P0.7, ladder r1) and the EV-009 `xxl` / `xxxl`
calibration instances (~1.2M / ~2.4M tokens) on v0.24.0 (ladder r2) — so none of the
instruments tried has the repeat-mistake population the claim needs.** That is a statement
about the instances tried, not about every corpus in those families. Per the owner's stop rule the run was not sealed
at that point; there was no automatic fall-through to the next instrument option. For the
overflow-band corpora themselves see [EV-009](#ev-009); those tables are not
repeated here.

**A later option did qualify.** On the owner's 2026-09-04 decision the lane
built option 2, a **trap-injected** instrument — `p3trap-M-i1` = the sealed
`p3-M-i1` with rule-bearing contradictory records added (design
`EV007B-TRAP-DESIGN.md` v0.2, 3-seat design review 3/3 GO-WITH-MINOR, corpus
re-sealed before use; 48 of 51 ledger files byte-identical to the sealed
`p3-M-i1`, plus the erratum file `addenda/ledger-addenda.csv`). Its 2-job pilot,
run under the same pre-written rule, **qualified**: both jobs ≥2 mistakes
(11, 7) and ≥10/20 correct (10, 13). That instrument is what the sealed main run
below was executed on.

### Result matrix — EV-007b main run: no learning event (2026-09-04, pin v0.24.0)

The run executed the full sealed series — R1 → turn 1 → R2 → turn 2 → R3 →
turn 3 → final block — 18 jobs, all of them, 11:37–17:20 UTC on 2026-09-04. The
sealed §8 outcome taxonomy is first-match-wins:

| # | outcome | this run |
|---|---|---|
| 1 | stopped-by-rig (preflight / probe / D4 / cap-breach / round-failure exit) | **no** — no rig exit fired; the ledger's terminal note is `run_rounds-end` at 17:20:10Z |
| 2 | unmeasurable-by-budget (final block incomplete in a harness arm) | **no** — all four final-block harness jobs reached a terminal state |
| 3 | inconclusive-adequacy (`r1-adequacy … verdict=inconclusive`) | **no** — `arm=C classes=8 verdict=ok` |
| **4** | **unmeasurable-no-learning-event** (all three loop turns `learning_event=none`) | **YES** — R1, R2 and R3 review fail-closed on both attempts; promotions **0**, approved rules **0** |

Under the sealed attribution rule **nothing in this run can be attributed to
"review, then promote", in either direction.**

**Per job** (mistake = `correct is False ∪ quote_valid is False` per question id,
scorer fields, no classifier; T1 = the 5 erratum-file trap classes, T2 = the 3
in-file supersession trap classes, plain = the other 12 items):

| arm | job | correct | mistakes (T1\|T2\|plain) | invalid quotes | attempts | terminal | charge |
|---|---|---|---|---|---|---|---|
| A `bare` | r1a | 6/20 | 14 (5\|3\|6) | 1 | 9/10 | token_budget | 10,163,624 |
| A | fin | 6/20 | 14 (5\|3\|6) | 0 | 7/10 | token_budget | 11,123,859 |
| B `harness-no-learning` | r1j1 | 11/20 | 9 (5\|2\|2) | 0 | 5/16 | delivered | 1,685,858 |
| B | r1j2 | 13/20 | 13 (5\|2\|6) | 11 | 4/16 | delivered | 1,946,874 |
| B | r2j1 | 13/20 | 7 (5\|2\|0) | 0 | 5/16 | delivered | 4,244,223 |
| B | r2j2 | 12/20 | 8 (5\|3\|0) | 0 | 4/16 | delivered | 3,123,192 |
| B | r3j1 | 0/0 *(empty run)* | — | — | 6/16 | dlq / no-progress | 3,029,500 |
| B | r3j2 | 11/20 | 9 (5\|1\|3) | 0 | 6/16 | delivered | 3,250,543 |
| B | finj1 | 11/20 | 9 (5\|2\|2) | 1 | 4/16 | delivered | 1,674,649 |
| B | finj2 | 0/0 *(empty run)* | — | — | 6/16 | dlq / no-progress | 2,228,851 |
| C `harness-learning` | r1j1 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 3,888,457 |
| C | r1j2 | 12/20 | 8 (5\|3\|0) | 0 | 4/16 | delivered | 4,966,731 |
| C | r2j1 | 9/20 | 11 (5\|3\|3) | 0 | 4/16 | delivered | 4,169,965 |
| C | r2j2 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 4,462,117 |
| C | r3j1 | 9/20 | 11 (5\|3\|3) | 0 | 5/16 | delivered | 4,165,421 |
| C | r3j2 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 3,963,140 |
| C | finj1 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 4,897,058 |
| C | finj2 | 12/20 | 11 (5\|3\|3) | 5 | 4/16 | delivered | 4,448,798 |

**The instrument worked.** Every T1 class was a mistake in **all 14 scored
harness jobs and both bare jobs** (14/14 + 2/2), and no arm ever applied an
erratum; arm C made exactly the 8 trap classes in R1, R2, R3 and the final block
— 8/8 recurring every time. So a learning event, had one happened, would have
had a live population to act on. T2 varies only in arm B (Q04 and Q19 solved in
some B jobs). The plain-item mistakes are invalid-quote episodes (B r1j2: 11
invalid quotes; C finj2: 5), not wrong answers.

**Headline contrast — descriptive only.** Outcome row 4 fired, so the sealed
attribution rule forbids reading any of these numbers as a result about
learning. They are printed for completeness — §5 reports the supporting and
secondary figures beside the headline, and under row 4 the headline itself is
descriptive only — never as a result. Block = union
over the block's two jobs; `m(X)` = classes ÷ 20; before = R1, after = the final
block:

| arm | before classes | after classes | recurring | `m(before)` | `m(after)` | repeat rate |
|---|---|---|---|---|---|---|
| B `harness-no-learning` | 14 | 9 | 9 | 0.700 | 0.450 | 0.643 (9/14) |
| C `harness-learning` | 8 (= the 8 trap classes exactly) | 11 | 8 | 0.400 | 0.550 | 1.000 (8/8) |

`DiD = (0.550 − 0.400) − (0.450 − 0.700) = +0.400` (**+0.400**) (the sealed line required
`< 0`); the ratio conjunct C 1.000 ≤ B/3 = 0.214 is not met. **Neither is a
finding.** The contrast is unattributable, and its main driver is arithmetic:
B's after-block is a single job, because the other one was an empty run. The
no-harm guard (T = 10 pp correct-rate drop, X = 50 % abstain share) is intact in
both arms — B 24/40 → 11/20, a 5.0 pp drop; C 24/40 → 24/40, 0.0 pp; abstains
**0** in both.

**Per-round curve** (R1 classes recurring in round *n* ÷ R1 classes):

| arm | R1 classes | R2 | R3 | final |
|---|---|---|---|---|
| B | 14 | 0.571 | 0.643 | 0.643 |
| C | 8 | **1.000** | **1.000** | **1.000** |

**Loop health — three turns, six fail-closed reviewer calls, zero promotions:**

| turn | intake | archive-dayfile | review attempt 1 (GLM-5.3 lead) | review attempt 2 (Kimi K3 lead) | apply |
|---|---|---|---|---|---|
| 1 | `runs=1 drained_by=steady-state-after-fold` | `move blocks=2 archive_blocks=2` | `blocks=2 fabricated=2 candidates=0 error=chain-exhausted` | `blocks=3 fabricated=3 candidates=0 chain-exhausted` | skipped (`review-fail-closed`) |
| 2 | `runs=2` (2 folded) | `append blocks=2 archive_blocks=4` | `blocks=3 fabricated=3 candidates=0 chain-exhausted` | same | skipped |
| 3 | `runs=2` (1 folded) | `append blocks=1 archive_blocks=5` | `blocks=3 fabricated=3 candidates=0 chain-exhausted` | same | skipped |

Every receipt carries `model_used=- chain_pos=2`, i.e. **both** reviewers failed
on **every** attempt: six reviewer calls, six `reason=fabrication-threshold`
failures, `candidates=0` throughout.

**Empty runs.** Two of the eight B jobs (r3j1, finj2) ended `dlq / no-progress`
after 6 attempts with 16/20 answers and no recorded read coverage. Per the P0
Decision 1 rule they are scored 0/0, excluded from every denominator, and
counted here. C had **0** empty runs. This is why B's after-block is one job and
C's is two.

**The mechanism — this run's product finding.** The reviewers did read the
lessons and grouped them into sensible themes; then **every member citation
failed** `scripts/raw-review.sh`'s citation check. That check requires the quote
to be a *prefix* of the canonicalized source line; canonicalization strips a
leading `- `, a leading date and `[tag]`s, but **not** the
`(2026-09-04, ev007b-C-r1j1) ` prefix that the pin's Stop hook writes on every
flush line — and any quote longer than 200 characters is rejected outright. The
reviewers quoted from the lesson text after that prefix, or quoted over 200
characters, so 100 % of blocks came back "fabricated"; with `blocks > 0 &&
candidates == 0` the reviewer fails regardless of the configured
`fabricated_floor=4` / `fabricated_pct=75`. Separately, the other learning
channel *was* live and moved nothing: intake folded **6** lines into arm C's
`STATE.md` "Lessons learned" (3 after R1, 2 after R2, 1 after R3), and every
later C job read them — but none of them is the trap bit, and the R1 lesson is
the *wrong* bit for T2 ("query extraction must include all matching rows", which
instructs the model to include the superseded row).

**Post-seal corrections (superseding records, §7 ledger; the sealed copy was not
edited):**

| id | recorded | supersedes | superseding rule | why | decided |
|---|---|---|---|---|---|
| A | 15:16:15Z | "intake drains to `files_scanned=0`" | drained = `files_scanned=0` **or** a steady-state receipt (`folded=0 ∧ deduped=candidates`) after a `folded>0` receipt in the same phase | `flush-intake.sh` never archives the current UTC day's file, so `files_scanned` stays 1 all day and R1's turn was skipped although intake had folded everything | owner, 2026-09-04 |
| B | 15:16:15Z | cap 45M | cap **75M** | 45M was sized from the arm-B pilot alone; R1 measured A 10.2M / B 1.8M / C 4.4M per job → 18 jobs ≈ 70M | owner, 2026-09-04 |
| C | 15:37:28Z | "the reviewed set is everything *pending* inside the window" | loop turn = intake → **archive-dayfile** (the product's own next-day archive action, append-or-move, applied at the turn) → review → apply | `raw-week.sh` lists `loop/archive/` only, so on a same-day series the nightly review's input is empty at every turn (the R1 re-run saw `files=0`); scratch-proven before adoption | owner, 2026-09-04 |

Also ledgered, and not corrections: an **orchestrator stop at 12:04:17Z** (the R2
wave was killed 90 s in, both jobs retired, workspace leftovers relocated
byte-exact, no denominator affected); an **orchestrator hold at 15:21:15Z**
pending the owner's decision on correction C; and a rig-seal re-check
(`shasum -c` over the sealed 114-file block) in which **exactly two** files
differed — `runner/run_round.sh` and `runner/run_rounds.sh` — both recorded with
before/after hashes in the ledger records, 112/114 unchanged.

**Cost of the main run:**

| line | charge tokens |
|---|---|
| A `bare` (2 jobs) | 21,287,483 |
| B (8 jobs) | 21,183,690 |
| C (8 jobs) | 34,961,687 |
| retired (the R2 wave killed at 12:04Z, 2 dirs, in no denominator) | 485,015 |
| **run total, inside the 75M cap (correction B)** | **77,917,875 — 103.9 % of the cap** |
| pre-run spend, reported outside the cap | 191,696,045 (P0.7 16.2M · ladder r1 28.2M + r2 132.3M, plus the 11.1M aborted XXL attempt · trap pilot 3.9M) |

The cap gate held exactly as sealed: it ran before every launch (`phase=cap-gate
status=ok` ×5, the last at 54,029,675 before the final block) and no launch
happened at or over 75M. The overshoot **is** the final block (24,373,215) —
the sealed "worst-case overshoot is the round in flight". `tools/charge_sum.py`
reports 78,402,890 because it double-counts one relocated stream copy
(485,015); the single-counted figure above is the reportable one.

### Result matrix — EV-007c main run: learning events, sealed line not met (2026-09-05, pin v0.25.0)

EV-007c is the third lane: the same sealed series, the same instrument
(`p3trap-M-i1`, `corpus_seal=verified` at both preflights), the same three arms
and the same metrics as EV-007b, re-run on pin `v0.25.0` (`23ab781`) — the pin
that carries the #274 citation-contract fix. Its pre-registration was sealed on
2026-09-05 (sha256 `931601d8…7fed31`) and **no post-seal correction** was
recorded. This is the first run of the family in which the loop produced
learning events at all — three turns, three successful reviews, six promotions,
two approved rules — and therefore the first in which the sealed pass/fail line
could be evaluated. It was evaluated, and it was **not met**: the learning arm's
repeat-mistake rate is 0.667 against 0.727 in the no-learning arm (the line
required ≤ 1/3 of B's), and the difference-in-differences is **+0.050** (the line
required strictly `< 0`).

18 jobs, all executed, all delivered; **0 empty runs**, 0 retired, 0
infra-failed. Task model `claude-haiku-4.5`, sentinel `active`, Tier-M budgets
(`attempts_budget` 16, `token_budget` 10M), cap **85M** (owner decision at seal)
with the gate before every launch. Slot pools by number only: B {7,5} — the probe
placed B on slot **6** in R1 (`swap-to-spare`; slot 7 read 5h 97 %, the sealed
known limitation) and on 5 from R2; C {1,4}; A 6. D4-normalized profiles were
verified before every round (`phase=d4-verify status=ok` ×4). Timeline (UTC,
2026-09-05): seal 16:22:46; R1 16:22–16:50; turn 1 16:50–16:54; R2 16:54–17:13;
turn 2 17:13–17:17; R3 17:17–17:43; turn 3 17:43–17:47; final block 17:47–18:15;
`run_rounds-end` 18:15:20 — one launch, one process, no resume, no hold, no
orchestrator stop.

The sealed §8 outcome taxonomy is first-match-wins:

| # | outcome | condition | this run |
|---|---|---|---|
| 1 | stopped-by-rig | preflight / probe / D4 / cap-breach / round-failure exit | **no** — no exit 3/4/5/6/7/8; `note=run_rounds-end` 18:15:20Z |
| 2 | unmeasurable-by-budget | final block did not complete in both harness arms | **no** — all four final-block harness jobs delivered (0 empty runs in the whole run) |
| 3 | inconclusive-adequacy | `r1-adequacy … verdict=inconclusive` | **no** — `arm=C classes=9 verdict=ok` (B: 11) |
| 4 | unmeasurable-no-learning-event | all three loop turns `learning_event=none` | **no** — every turn reviewed (GLM-5.3, `chain_pos=1`, `error=none`) and applied; promotions 2 / 3 / 1 |
| 5 | pass-with-harm (void) | ratio conjunct ∧ DiD < 0 ∧ a no-harm breach | **no** — DiD is +0.050 (not < 0); no guard breached |
| 6 | pass | ratio conjunct ∧ DiD < 0 ∧ no-harm intact ∧ attribution met | **no** — neither conjunct met |
| 7 | pass-unattributed | 6 without the attribution rule | **no** |
| **8** | **fail** | everything else (measured, conjuncts not met) | **YES** — ratio 0.667 vs B/3 = 0.242 (not met); DiD +0.050 (not < 0); attribution rule **met** (≥1 `decision=promoted` and ≥1 approved rule before the final block: 6 and 2) |

**Outcome row 8 — fail: the pre-registered line was not met.** Under the sealed
attribution rule the contrast **is** attributable to "review, then promote" —
promotions and approved rules preceded the final block. That is the difference
between this run and EV-007b: the sealed rule allows the contrast to be read, and
it reads as a fail. What that does and does not mean at n = 1 is in *Read these
before quoting* below.

**Per job** (all 18; mistake = `correct is False ∪ quote_valid is False` per
question id, scorer fields, no classifier; `correct/20` from `score.json`,
mistake classes split T1 | T2 | plain, invalid quotes, attempts of budget,
terminal state, charge):

| arm | job | correct | mistakes (T1\|T2\|plain) | invalid quotes | attempts | terminal | charge |
|---|---|---|---|---|---|---|---|
| A | r1a | 4/20 | 16 (5\|3\|8) | 10 | 6/10 | token_budget | 12,311,818 |
| A | fin | 6/20 | 14 (5\|3\|6) | 10 | 7/10 | token_budget | 10,645,911 |
| B | r1j1 | 10/20 | 10 (5\|2\|3) | 0 | 5/16 | delivered | 2,624,371 |
| B | r1j2 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 3,864,768 |
| B | r2j1 | 12/20 | 8 (5\|2\|1) | 0 | 5/16 | delivered | 2,187,093 |
| B | r2j2 | 5/20 | 15 (5\|3\|7) | 0 | 5/16 | delivered | 2,226,521 |
| B | r3j1 | 12/20 | 8 (5\|3\|0) | 0 | 5/16 | delivered | 1,615,428 |
| B | r3j2 | 10/20 | 10 (5\|3\|2) | 1 | 4/16 | delivered | 2,328,726 |
| B | finj1 | 12/20 | 8 (5\|3\|0) | 0 | 4/16 | delivered | 2,023,729 |
| B | finj2 | 11/20 | 9 (5\|3\|1) | 0 | 5/16 | delivered | 2,011,641 |
| C | r1j1 | 11/20 | 9 (5\|2\|2) | 0 | 6/16 | delivered | 6,796,395 |
| C | r1j2 | 13/20 | 7 (5\|2\|0) | 0 | 5/16 | delivered | 4,982,191 |
| C | r2j1 | 13/20 | 7 (5\|2\|0) | 0 | 4/16 | delivered | 4,383,929 |
| C | r2j2 | 14/20 | 6 (5\|1\|0) | 0 | 5/16 | delivered | 3,969,517 |
| C | r3j1 | 15/20 | **5 (5\|0\|0)** | 0 | 5/16 | delivered | 5,188,836 |
| C | r3j2 | 15/20 | **5 (5\|0\|0)** | 0 | 4/16 | delivered | 4,854,826 |
| C | finj1 | 13/20 | 8 (5\|2\|1) | 2 | 5/16 | delivered | 4,610,259 |
| C | finj2 | 14/20 | 6 (5\|1\|0) | 0 | 5/16 | delivered | 2,445,037 |

Arm A is `bare`, B is `harness-no-learning`, C is `harness-learning`, as in every
lane of this section. `correct` + mistakes exceeds 20 only where a correct answer
carries an invalid quote — C finj1 (Q19: `correct=True quote_valid=False`). A's
10 invalid quotes per job are unknown/abstention in r1a and true misquotes in fin.

**Headline contrast — measured and attributable.** Block = union over the block's
two jobs; `m(X,β)` = classes ÷ 20; before = R1, after = the final block:

| arm | before-block classes (R1 union) | after-block classes (final union) | recurring | `m(before)` | `m(after)` | repeat rate |
|---|---|---|---|---|---|---|
| B `harness-no-learning` | 11 — Q02 Q04 Q06 Q09 Q11 Q12 Q13 Q14 Q15 Q16 Q19 | 9 — Q02 Q04 Q06 Q09 Q11 Q13 Q15 Q19 Q20 | 8 | 0.550 | 0.450 | **0.727** (8/11) |
| C `harness-learning` | 9 — Q02 Q04 Q06 Q09 Q11 Q13 Q14 Q15 Q16 | 8 — Q02 Q05 Q06 Q09 Q11 Q13 Q15 Q19 | 6 — Q02 Q06 Q09 Q11 Q13 Q15 | 0.450 | 0.400 | **0.667** (6/9) |

- `DiD = [m(C,after) − m(C,before)] − [m(B,after) − m(B,before)] = (0.400 − 0.450) − (0.450 − 0.550) = −0.050 − (−0.100) = +0.050` (**+0.050**; the sealed line requires `< 0`).
- Ratio conjunct: C 0.667 ≤ B/3 = 0.242 → **not met**.
- Descriptive secondary (mistake = true-misquote only): B before 0 classes → after
  0 (rate N/A); C before 0 → after 2 (Q06, Q19 — both in finj1; rate N/A).
- **What moved and what did not.** Both arms' before-blocks contained plain-item
  mistakes that vanished on their own by the final block (B: Q12 Q14 Q16; C: Q14
  Q16) — that is most of the `m()` improvement in both arms and all of it in B. On
  the trap classes: **B solved none of the 8 trap classes in any round** (T1 and T2
  are `1 1 1 1` in every B row of the per-class table below). **C solved Q04 (T2)
  in R3 and kept it solved in the final block, and solved Q11 (T2) in R3 but lost
  it again in both final jobs**; C never solved a T1 class. The C after-block also
  picked up three mistakes it did not have before — Q05 (plain, wrong answer,
  finj1), Q06 and Q19 (invalid quotes, finj1) — which is why the recurring count of
  6 sits on an after-block of 8. On the trap classes alone C went 7 → 7 (Q04 left,
  Q11 stayed, Q19 entered; 6 of the 7 R1 trap classes recurring) and B went 8 → 8;
  the headline was decided by the non-trap movement.
- **Empty runs (P0 Decision 1):** none in either arm. B r2j2 delivered 20 answers
  but scored 5/20 with the gate listing missing read coverage on most corpus files
  — it is a scored job, in every denominator, and the reason B's R2 union is 15
  classes.
- Arm A: r1a 4/20 (16 classes: the 8 traps + Q08 Q10 Q12 Q14 Q16 Q17 Q18 Q20), fin
  6/20 (14 classes: the 8 traps + Q12 Q14 Q16 Q17 Q18 Q20); both ended on
  `token_budget`.

**Per-round curve** (R1 classes recurring in round *n* ÷ R1 classes), with the
learning event that preceded each round:

| arm | R1 classes | R2 | R3 | final | round unions (R1/R2/R3/fin) | learning event before R2 / R3 / final |
|---|---|---|---|---|---|---|
| B | 11 | 1.000 (11) | 0.909 (10) | 0.727 (8) | 11 / 15 / 10 / 9 | none / none / none (arm has no loop) |
| C | 9 | 0.778 (7) | **0.556 (5)** | 0.667 (6) | 9 / 7 / 5 / 8 | **yes (2 promoted) / yes (3 promoted, 1 rule approved) / yes (1 rule approved)** |

**Per class**, 1 = mistake in either job of that round (C then B), rounds R1 R2 R3
final:

| q_id | class | C | B |
|---|---|---|---|
| Q02 | T1 | 1 1 1 1 | 1 1 1 1 |
| Q06 | T1 | 1 1 1 1 | 1 1 1 1 |
| Q09 | T1 | 1 1 1 1 | 1 1 1 1 |
| Q13 | T1 | 1 1 1 1 | 1 1 1 1 |
| Q15 | T1 | 1 1 1 1 | 1 1 1 1 |
| Q04 | T2 | 1 1 **0 0** | 1 1 1 1 |
| Q11 | T2 | 1 1 **0** 1 | 1 1 1 1 |
| Q19 | T2 | 0 0 0 1 | 1 1 1 1 |
| Q14 Q16 | plain | 1 0 0 0 | 1 1 1 0 |
| Q12 | plain | 0 0 0 0 | 1 1 0 0 |
| Q05 Q07 Q08 Q10 | plain | 0 0 0 0 (Q05: 0 0 0 1) | 0 1 0 0 |
| Q20 | plain | 0 0 0 0 | 0 0 0 1 |

- **T1 (erratum-file) is unmoved everywhere**: a mistake in all 16 scored harness
  jobs and both bare jobs. No arm ever applied an erratum, and — see the loop-health
  table below — no review candidate in any turn was about errata, because no job
  wrote an erratum lesson down.
- **T2 (in-file supersession) is where C moved.** After turn 2 promoted the rule
  *"Final superseded status row governs ledger answers"* (k = 3, approved) C's R3
  jobs answered Q04 and Q11 correctly in both jobs (the two `5 (5|0|0)` rows above
  — the only harness jobs in EV-007b or EV-007c with zero T2 mistakes; in EV-007b
  T2 was solved only partially, and only in B). In the final block Q04 stayed
  solved in both jobs; Q11 was wrong in both; Q19 (never a C mistake before) became
  one through an invalid quote in finj1. B never solved any T2 class in any of its
  8 jobs.
- The curve's dip to 0.556 and its recovery to 0.667 are one arm, one instrument,
  one bit per class; they are the observation, not a slope estimate.

**No-harm guard** (T = 10 pp correct-rate drop, X = 50 % abstain share) — intact
in both arms:

| arm | before correct | after correct | drop (pp) | after NG items | abstain | abstain share |
|---|---|---|---|---|---|---|
| B | 22/40 (0.550) | 23/40 (0.575) | −2.5 (rise) | 0 | 0 | N/A |
| C | 24/40 (0.600) | 27/40 (0.675) | −7.5 (rise) | 2 | 0 | 0 % |

No breach in either arm; the correct rate rose in both. Outcome row 5 is not
reachable (DiD not < 0).

**Loop health — three turns, three reviews, six promotions, two approved rules**
(arm C; receipts verbatim in `results-c/round-<R>/` and
`ws-c-C/loop/promotions/`):

| turn | intake (rule A) | archive-dayfile (rule C) | review (GLM-5.3 lead, attempt 1) | apply-auto | apply-approve |
|---|---|---|---|---|---|
| 1 | `runs=2 drained_by=steady-state-after-fold` (last receipt `candidates=9 deduped=9 folded=0`) | `move blocks=4 archive_blocks=4` | `prompt_bytes=5751 blocks=3 fabricated=1 rejected=1 candidates=2 chain_pos=1 error=none` | **promoted 2**: capability-fact `…86834-001` k=4 → Verified facts; skill `…86834-002` k=3 → `skills/_staging/` | skipped `no-awaiting-rules` |
| 2 | `runs=2` (`candidates=2 deduped=2`) | `append blocks=1 archive_blocks=5` | `prompt_bytes=6497 blocks=3 fabricated=0 candidates=3` | **promoted 2**: capability-fact `…88988-001` k=5 → Verified facts (supersedes the turn-1 fact, `invalidated-by` pointer written); skill `…88988-003` k=3 → staging | **approved 1**: rule `…88988-002` *"Final superseded status row governs ledger answers"* k=3 → General rules |
| 3 | `runs=2` (`candidates=2 deduped=2`) | `append blocks=2 archive_blocks=7` | `prompt_bytes=7406 blocks=3 fabricated=0 candidates=3` | promoted 0: capability-fact `…54377-001` and skill `…54377-003` **skipped `supersedes-ambiguous`** | **approved 1**: rule `…54377-002` *"Superseded final status row is authoritative"* k=3 → General rules (supersedes the turn-2 rule; `invalidated-by` written) |

**Reviewer calls: 3, fail-closes: 0.** Every receipt is `model_used=glm-5.3
chain_pos=1 error=none`; the Kimi K3 fallback was never invoked. Turn 1 rejected 1
of 3 blocks as fabricated; turns 2 and 3 rejected nothing. Contrast EV-007b on
v0.24.0: 6 calls, 6 fail-closes, 0 candidates. The #274 fix (the review's
canonicalization now strips the Stop hook's provenance stamp for comparison) is
what changed between the two runs, and the wiring re-check had predicted it
(`results-c/wiring/recheck-v0.25.0.md`: `fabricated=0 candidates=3`).

**What was promoted.** Promotions **6** (`decision=promoted` rows in
`apply-index.tsv`); approved rules **2** (`approve-manifest.txt` in round 2 and
round 3, one id each). The approval pass is the rig's own (`run_round.sh
apply-approve`, manifest-driven; the approver id is the constant the rig writes —
no human acted during the run, as sealed). The two approved rules are the same
bit, restated: *the last status row wins when a transaction's status is superseded
in-file* — exactly the T2 trap. The two Verified facts (*"answers concentrate in
middle-range files per step chunk"*) and the two staged skills (*"exact
account/status/date triple match extracts answers"*) describe the instrument's own
layout and extraction recipe — true of this corpus, not knowledge about anything
else. **Nothing about errata was ever a candidate**: the 15 folded lessons in arm
C's `STATE.md` are step-progress and file-map notes plus the supersession
observation; the model never wrote an erratum lesson, so the loop had nothing to
promote for T1. Turn 3's re-statements of the turn-2 fact and skill were parked as
`supersedes-ambiguous`, while the re-stated rule was promoted and the earlier rule
marked `invalidated-by` — three paraphrases of one theme produced two live lines
and two parked ones. Arm C's `STATE.md` at the end of the run: Verified facts 2 (1
live + 1 `invalidated-by`), General rules 2 (1 live + 1 `invalidated-by`), Open
failures 0, Lessons learned 15; arm B: 0 / 0 / 0 / 0. Contamination scope check: 0
untrailed in-scope bullets in every B and C `STATE-at-end.md`. Arm C wrote 34
handoff files (33/34 with all four restart fields); arm B, which has no Stop hook,
wrote 2 (2/2) and Last-session entries from r1j1 on — the model writing the
CHECKPOINT unprompted, as in EV-007b.

**Cost of the main run:**

| arm | jobs | charge | per job |
|---|---|---|---|
| A `bare` | 2 | 22,957,729 | r1a 12,311,818 · fin 10,645,911 |
| B | 8 | 18,882,277 | 2,624,371 · 3,864,768 · 2,187,093 · 2,226,521 · 1,615,428 · 2,328,726 · 2,023,729 · 2,011,641 |
| C | 8 | 37,230,990 | 6,796,395 · 4,982,191 · 4,383,929 · 3,969,517 · 5,188,836 · 4,854,826 · 4,610,259 · 2,445,037 |
| retired / infra-failed | 0 | 0 | — |
| **run total inside the cap** | 18 | **79,070,996** | = **93.0 % of the 85M cap** |
| pre-run spend outside the cap (sealed) | — | 0 | no pilot; the wiring re-check started no task-model session (1 GLM reviewer call) |

**The cap held and was not exceeded.** The gate ran before every launch
(`phase=cap-gate status=ok` ×4: 0 → 30,579,543 → 43,346,603 → 57,334,419) and the
final block cost 21,736,577, inside the 85M. `tools/charge_sum.py` and the
aggregator agree (79,070,996; no retired copies to double-count this time). C cost
1.97 × B (37.2M vs 18.9M; EV-007b: 1.65 ×), and per-job C charge did not decline
over the series (6.8 → 5.0 → 4.4 → 4.0 → 5.2 → 4.9 → 4.6 → 2.4M) while B stayed at
1.6–3.9M. Attempts per harness job were 4–6 of 16 in both arms; wall clock B
365–612 s, C 534–928 s, A 1,008 / 1,107 s. The 3 GLM-5.3 reviewer calls are not
Claude charge tokens and sit outside the cap.

**No post-seal correction.** The sealed copy was not edited and the §7 ledger of
EV-007c's pre-registration is **empty** — the first main run of the family with no
correction record. The rig-seal re-check (`shasum -c` over the sealed 116-file
block) passed **116/116**. EV-007b's three corrections (A the intake drain rule, B
the cap, C the archive-dayfile step) were folded into the EV-007c body *before*
the seal and ran as sealed; the `rule=section7-correction-A` / `-C` tokens on
every intake and archive receipt are those carried rule ids, not new records.

### The product changes these lanes produced

The lanes were not free of product results — they produced two shipped changes,
plus a live proof that the loop is wired.

**[#263](https://github.com/caty-ai/caty-agent-harness/issues/263) →
[#267](https://github.com/caty-ai/caty-agent-harness/pull/267), shipped in
v0.24.0: the promotion recurrence unit is distinct sessions.** The gate for
promoting a lesson to `General rules` / `Verified facts` was specified as
recurrence across *different jobs* in `docs/engineering.md` but implemented as
recurrence across *different ISO weeks* — the week was inherited from the weekly
cut of the raw layer, not chosen. A lesson that recurred twice in one afternoon
could not become a rule until a night after the next Monday; EV-007 needed a
two-week calendar to reach its single learning event, and terminated with none.
The unit is now configurable in `loop/review.conf`: `recurrence_unit=sessions`
(default) or `weeks`, `promote_min_k=2`, and an optional calendar-spread
requirement `promote_min_weeks=0` (off by default). See the review section of
[the reference](reference.md).

**[#274](https://github.com/caty-ai/caty-agent-harness/issues/274) →
[#275](https://github.com/caty-ai/caty-agent-harness/pull/275), shipped in
v0.25.0: raw-review's citation check canonicalizes the Stop hook's provenance
stamp.** This is the fix for the EV-007b main run's product finding. The citation
check requires a quote to be a prefix of the canonicalized source line, and the
canonicalization did not strip the `(date, task-id)` provenance stamp that
`adapters/claude-code/checkpoint-stop-hook.sh` writes on every flush line — so
quotes taken from the lesson text after that stamp were scored as fabricated, and
on v0.24.0 that turned 6 reviewer calls into 6 fail-closes with 0 candidates. With
the stamp canonicalized away, EV-007c's three reviewer calls returned 3 successful
reviews, 0 fail-closes, 9 blocks reviewed and 1 rejected as fabricated — the change from
"nothing to promote" to "6 promotions and 2 approved rules".

**Live wiring re-check on v0.24.0 — PASS 6/6.** Run on the pin
`90a602f`, in a fresh workspace seeded with real (re-dated) flush files, with
receipts: intake drained to `files_scanned=0`; the review receipt carries the new
`unit=sessions` field; apply promoted **16** themes, every one `unit=sessions`; a further *rule* theme whose two
members sit in the *same day's* file under two distinct `session=` ids cleared the k-gate
at `run-k: 2` (week count 1) and sat `awaiting-approval` (rules need the approval pass); the hold path was shown
counterfactually by re-applying the byte-identical candidates file with
`recurrence_unit=weeks`, which held exactly the 7 single-week multi-session
themes with the token `k-below-2`; a second apply promoted 0 with
`skipped-already-applied=16` (idempotent); and all 14 STATE.md lines (16 promotions minus the 2 skill-class themes, which go to
`skills/_staging/` rather than STATE.md) carry the full provenance trailer (`source: / reviewer: / weeks: / k= / unit=sessions /
approver:`). `## General rules` received 0 lines — every `rule` theme stayed
`awaiting-approval`, as designed.

**P0's original wiring proof (2026-08).** Before any of this, P0 checked that the
loop closes a full turn at all inside real task-runner jobs across a persistent
workspace: generation fired 4/4 jobs, the fold passed 4/4, and the folded content
appeared in the next job's prompt 4/4 — **PASS**. P0 also showed the moved content
was near-worthless, which is what the "review, then promote" design replaced. P0
was a wiring check and measures nothing about whether distillation helps.

### Read these before quoting

1. **Two lanes have no learning event; the third has one measured fail of a
   pre-registered line.** EV-007 and EV-007b each ended with **0 promotions and 0
   approved rules** — EV-007 has no after-block at all, and EV-007b's C-vs-B
   contrast is unattributable under the sealed attribution rule. EV-007c is
   different: **6 promotions, 2 approved rules, attribution rule met**, and the
   sealed line evaluated — outcome row 8, **fail: the pre-registered line was not
   met**. That is a result about *this line, on this instrument, once* (n = 1, one
   bit per class), not a demonstration that the loop does nothing. Do not read
   "the loop works" or "the loop is useless" out of this section; neither is
   supported.
2. **The instrument died because the product improved.** On the 2026-08-19 pin the
   harness averaged 13.6 wrong answers per job across the five `p3-M` instances (17.6
   across `p3-L`); in the EV-007b pilots on v0.21.1 the tried instances `p3-M-i1`, `p3-S-i1`,
   `p2-L-i1`, `p3-L-i1` scored 19–20/20 (EV-007's own before-block on the same pin
   ranged 16–20/20 per job — the mistakes were already disappearing within that run),
   and on v0.24.0 the two EV-009 instances scored 20/20. Difficulty scaling did not
   bring the mistakes back — even at ~2.4M tokens the two ladder levels produced
   0 and 1 mistakes across four jobs.
3. **Judge variance sat on the fail-close boundary.** The two EV-007 review runs
   consumed byte-identical prompts (`prompt_bytes=10437`, same three files, same
   window) and returned different verdicts, 2/4 and 3/4 fabricated, against a
   threshold of exactly 2 of 4. n=2 cannot separate reviewer non-determinism from
   a threshold sitting on the boundary; no cause is adjudicated. Separately, the
   fabrication check is mechanical (a citation-prefix check), and 4 of the 14
   reviewed raw blocks came from infra-failed jobs whose contradictory corpus
   claims made the input look fabricated. The guard firing is the shipped
   fail-closed design behaving as specified; whether a clean raw layer would have
   cleared review is **not determinable from this run**.
4. **Posture note (D4).** P0.7 and ladder round 1 ran with **un-normalized slot
   profiles**: the job slots had their `settings.json` / `CLAUDE.md` re-linked to
   the operator's user-global files, so those sessions carried 6 user-global
   SessionStart hooks and ≈67k tokens of injected baseline. This is recorded, not
   re-run. Ladder round 2 ran normalized (0 user-global hooks, 45.8k baseline at
   step 1). Read rounds 1 and 2 as measured under different postures.
5. **Eight product observations — from the wiring re-check and the EV-007b main
   run** — observations with
   issue pointers, not claims: (a) GLM-5.3 consumed its full 900 s reviewer
   timeout on both rounds of a ~142 KB nightly prompt and Kimi K3 produced the
   output at chain position 2 — a chain that puts GLM first pays ~15 min of dead
   leg per turn; (b) `apply-promotions.sh` gates on `k ≥ promote_min_k` alone and
   **ignores the reviewer's `promote: not-yet` field** — four such themes passed the k-gate anyway (the two
   capability-facts were promoted; the two rules sat `awaiting-approval`), so the
   reviewer cannot veto a promotion (design question for the
   [#201](https://github.com/caty-ai/caty-agent-harness/issues/201) /
   [#268](https://github.com/caty-ai/caty-agent-harness/issues/268) follow-ups);
   (c) `flush-intake.sh` never archives the current UTC day's flush file, so
   seeded or same-day material must be dated strictly before the run day or intake
   never drains; (d) and because `raw-week.sh` lists `loop/archive/` only, the
   consequence of (c) is that **a same-day loop cannot review its own day** —
   "nightly" means next-day (this is what correction C had to work around);
   (e) on v0.24.0, `scripts/raw-review.sh`'s citation check was a prefix match after a
   canonicalization that kept the Stop hook's `(date, task-id)` prefix (fixed by #274 in v0.25.0), and
   rejects quotes over 200 characters, and `blocks > 0 && candidates == 0` fails
   the reviewer regardless of floor/pct — on flush lines written by
   `adapters/claude-code/checkpoint-stop-hook.sh`, both reviewers failed 6/6
   calls; (f) `flush-intake.sh` folded step-progress notes ("Step 1 executed
   successfully …") into "Lessons learned" — the fold has no
   lesson-vs-progress filter; (g) in EV-007b, arm B (no hooks) nonetheless wrote
   one handoff and one Last-session entry, i.e. the model wrote the CHECKPOINT
   unprompted; (h) `tools/charge_sum.py` counts every
   `attempts/*/stream.jsonl` under a result dir including relocated copies —
   harmless for the gate (conservative), wrong for reporting.
6. **Arm B did not do what its recipe promised (EV-007).** B was designed to keep the
   episodic channel (Last session + handoffs) open while turning off only the
   lessons/rules channel; on disk it wrote 0 Last-session entries and 0 handoffs
   in all 8 jobs, because the CHECKPOINT demand comes from the Stop hook B does
   not have. The realized contrast is "no hooks" vs "hooks + raw layer".
7. **Instrument gaps.** Harness-arm `telemetry.json` recorded `events_total=0` in
   all 16 EV-007 harness jobs, so the gate's read-coverage check — and with it
   `task_resolved` and the residue-access count — is unmeasured for the harness
   arms; harness token usage had to be rebuilt from the attempt streams.
8. **The EV-007b instrument works on its pin (v0.24.0).** Unlike every earlier instance
   (19–20/20), `p3trap-M-i1` produced the same 8 mistake classes in all 14
   scored harness jobs and both bare jobs. The one-bit caveat is now measured
   rather than assumed: the trap is one shared decision per class — every T1
   class flipped together (never solved by anyone), and T2 flipped together in
   arm B.
9. **EV-007b's headline DiD is not a result.** `+0.400` and the 1.000 / 0.643 repeat
   rates are printed for completeness — §5 reports the supporting and secondary
   figures beside the headline, and under outcome row 4 the headline itself is
   descriptive only. They are never a result: row 4 forbids reading them as
   evidence about learning in either direction, and B's one-job after-block is
   their main driver.
10. **The review's citation contract and the Stop hook's flush format do not fit
    each other on v0.24.0.** This is the product finding of the EV-007b main run.
    Whether a review that *could* cite those lines would have promoted anything
    was **not determinable from that run**. It joins EV-007's "judge variance sat
    on the fail-close boundary" observation, this time with a mechanism — and it
    is the mismatch that #274 / PR #275 removed on v0.25.0, which is what made
    EV-007c's learning events possible.
11. **Same-day series need a host "night".** Two sealed sentences about
    intake/review timing turned out to be wrong (corrections A and C). Under C,
    arm C's loop turn contains one host step the shipped product performs only
    at the next UTC day: archiving the day-file. What EV-007b measured is
    therefore "review, then promote, **given that boundary**". Nothing in arm B
    was touched.
12. **The cap was exceeded by the round in flight (103.9 %).** As sealed, the
    gate only prevents launches; the overshoot was the final block. Correction
    B's projection was low by ≈3M.
13. **Posture and limits of the EV-007b main run.** All 18 jobs ran on D4-normalized
    slots (`d4-verify ok` ×4); the sealed known limitation "SPARE = A-slot
    overlap" materialized in the final block (arm B swapped to slot 6, the A
    slot); no usage limit was hit. Carried limits: one bit per class, the H5
    positional-recency / H6 lifecycle-wins residuals and A17, **no hold-out
    instance** (`p3trap-M-i2` was not built), and n = 1 run.

The remaining items are EV-007c's, from its report's own "read before quoting"
list:

14. **EV-007c's headline was decided by non-trap movement.** The sealed line was
    two conjuncts (C repeat rate ≤ B/3 **and** DiD < 0) at n = 1 on a
    one-bit-per-class instrument. C's rate is 0.667 vs B's 0.727; the DiD is
    +0.050 because B's before-block carried three plain-item mistakes (Q12 Q14
    Q16) that disappeared without any loop, while C's after-block acquired three
    new ones (Q05 wrong, Q06 and Q19 invalid quotes, all in finj1). **Neither
    movement is a trap class.** On the trap classes alone C went 7 → 7 (Q04
    solved, Q11 solved then lost, Q19 gained via a quote; 6 of the 7 R1 trap
    classes recurring) and B went 8 → 8.
15. **Where the learning is visible is the per-round curve, and it is one bit.**
    After the T2 rule was approved (turn 2), C's R3 jobs made **zero** T2
    mistakes — the only such harness jobs in EV-007b or EV-007c. In the final
    block the rule was still in `General rules` and Q11 was wrong in both jobs
    anyway. **A rule present in `STATE.md` is not a rule applied** (design
    residuals H5/H6; one shared decision per class). B never solved a T2 class in
    8 jobs.
16. **T1 never moved for anyone, and the loop never saw it.** All 5 erratum-file
    classes are mistakes in 16/16 scored harness jobs and 2/2 bare jobs, in
    EV-007c as in EV-007b; no lesson, candidate or rule ever mentioned errata. The
    loop promotes what the agent writes down, and the agent wrote down the layout
    of the corpus and the supersession bit, not the errata.
17. **EV-007c's attribution rule is met — the contrast is attributable to "review,
    then promote".** Six promotions and two approved rules preceded the final
    block. That is the difference between EV-007c and EV-007b: the sealed rule
    allows the contrast to be read, and it reads as a fail of the line.
18. **The product mechanism that ended EV-007b is gone on v0.25.0.** 3 reviews, 0
    fail-closes, 9 blocks reviewed, 1 rejected as fabricated (turn 1). The
    review's citation check and the Stop hook's flush format now fit
    ([#274](https://github.com/caty-ai/caty-agent-harness/issues/274) /
    [#275](https://github.com/caty-ai/caty-agent-harness/pull/275)).
19. **What EV-007c promoted is instrument-specific.** "Answers concentrate in
    middle-range files per step chunk" is a Verified fact about `p3trap-M-i1`;
    re-presenting the same corpus in every job (as the sealed series does) opens a
    **memorization channel** that the sealed design accepts and this page does not
    hide. The supersession rule is the one promotion that is a general statement.
20. **EV-007c's cap: 93.0 %, held.** No overshoot, no retired directories, no
    empty runs, no usage-limit wait, no resume. Posture: `d4-verify ok` ×4; the
    sealed known limitation "SPARE = A-slot overlap" materialized in R1 (arm B ran
    on the A slot because its own slot read 5h 97 %).
21. **Limits carried into EV-007c from the design:** one bit per class, the H5
    positional-recency / H6 lifecycle-wins residuals, A17 (VOID matchable at
    merge), **no hold-out instance** (`p3trap-M-i2` still not built), n = 1 run,
    and a **single task model** (haiku — the Sonnet/Opus ladder is
    [#265](https://github.com/caty-ai/caty-agent-harness/issues/265)).

### Deviations and correction ledger

EV-007 carried seven ledgered deviations (D1–D7); 8 infra-failed run directories
are excluded from every denominator and counted separately:

| id | date | what | handling |
|---|---|---|---|
| D1 | 08-28 | Job-slot profiles carried the operator's user-global settings (39 hook entries, broken paths → Writes denied) and a ~117k-token injected baseline | profiles normalized; j1 rerun in all arms; first j1 ×3 excluded |
| D2 | 08-28 | Scorer crashed on a malformed answer file and killed a run the gate had already rejected | scorer rejection treated as a failed unscored attempt; A-j1 rerun |
| D3 | 08-28 | Runner wrote a before-snapshot into a directory the job reset; two snapshots lost | snapshots relocated; no denominator effect |
| D4 | 08-29 | The account-switcher share feature re-links slot profiles to the live user-global files on every launch, silently reverting D1 | restored from backup, D1 made durable by a normalization tool |
| D5 | 08-29 | Corpus copied only on first use → j4 ran against the previous job's corpus; both harness arms empty-ran | per-job corpus union merge; B/C j4 rerun; both first runs excluded |
| D6 | 08-29 | The C-j4 rerun empty-ran while its injected state still carried the failed run's "corpus broken" claim | rig-confounded: C-j4 excluded from all quantitative denominators, descriptive record kept |
| D7 | 08-31 | D5's union assumed disjoint file names; two corpus instances share all 60 names → j7 served stale content under new names | union now compares content; B/C j7 rerun (20/20 each); rerun attempt counts carry a stale-residue caveat |

EV-007b's recorded deviations, all pre-seal: the RUNPLAN stop rule (stop if no
posture reaches ≥2 true-misquotes per job) was **superseded by the calibration
ladder** rather than executed, recorded in #264 and confirmed by the owner on
2026-09-03 together with the instrument choice (candidate 1, stop on failure) — owner
decisions recorded in [#264](https://github.com/caty-ai/caty-agent-harness/issues/264#issuecomment-5530742823); the first
ladder round-2 launch aborted at 6–7 of 33 stages because every slot profile had
been re-linked to the user-global files (the D4 vector again) and was relaunched
after normalization; and the first XXXL launch was refused at enqueue because the
previous band's attempt budget leaked into the next level inside the ladder
runner (`plan-step count exceeds attempts_budget: value=66 attempts_budget=42`) —
fixed, **zero spend**. `attempts_budget=1`, the fallback instrument plan, turned
out not to be runnable at all: the task-runner rejects a budget below the
plan-step count.

**EV-007b's post-seal records (main run, 2026-09-04).** After the seal, EV-007b
followed EV-007's discipline: the sealed file is never edited, and every change
is a **superseding record** in its §7 correction ledger, taken on an owner
decision. Three were recorded — **A** (the intake drain predicate, replaced by a
steady-state rule), **B** (the budget cap, 45M → 75M), and **C** (the loop turn
gains an `archive-dayfile` step) — with the full statement of each, its basis and
its owner decision in the main-run subsection above. None of them touched the
pass/fail line, the mistake definition, the series or the outcome taxonomy. Two
further events are ledgered but are **not** corrections: the orchestrator stop at
12:04:17Z (R2 wave killed 90 s in; both jobs retired into `*.orchestrator-stop-1`
directories, leftovers relocated byte-exact, `STATE.md` byte-identical to the
pre-wave snapshot, no denominator affected) and the orchestrator hold at
15:21:15Z while the owner decided on correction C. The rig-seal re-check after
the corrections found exactly two changed files, `runner/run_round.sh` and
`runner/run_rounds.sh`, both listed with before/after hashes (112 of 114
unchanged).

**EV-007c has no post-seal record (main run, 2026-09-05).** Its sealed copy was
not edited and the §7 correction ledger of its pre-registration is **empty** — the
first main run of this family that needed no correction. EV-007b's three
corrections (A the intake drain predicate, B the cap, C the `archive-dayfile`
step) were folded into the EV-007c body *before* the seal and ran as sealed, so
the `rule=section7-correction-A` / `-C` tokens on EV-007c's intake and archive
receipts are those carried rule ids, not new records. The rig-seal re-check
(`shasum -c` over the sealed 116-file block) passed **116/116**, and the run
ledger carries no `section7-correction` and no `orchestrator-*` note.

### Cost

| lane | charge tokens |
|---|---|
| EV-007, scored run directories (all arms) | **116,782,940** — 97.3 % of the sealed 120M cap |
| EV-007, including the 8 infra-failed directories | 130,228,564 — 108.5 % of the cap |
| EV-007b pilots: P0.7 | 16,211,897 |
| EV-007b pilots: ladder round 1 | 28,233,033 |
| EV-007b pilots: ladder round 2 | 132,311,480 |
| EV-007b pilots: ladder round 2, aborted first XXL attempt (retained streams, added by hand) | 11,059,320 |
| EV-007b pilots: trap-instrument pilot | 3,880,315 |
| **EV-007b pre-run total, reported outside the cap** | **191,696,045 (≈191.7M)** |
| **EV-007b main run, inside the 75M cap (correction B)** | **77,917,875 — 103.9 % of the cap** |
| EV-007c pre-run spend (outside the cap) | 0 — no pilot; the wiring re-check started no task-model session (one GLM reviewer call) |
| **EV-007c main run, inside the 85M cap** | **79,070,996 — 93.0 % of the cap** |

The sealed EV-007 text caps "charge tokens total across all arms" and separately
says infra failures count in no metric denominator; it does not say whether they
count against the cap, so both readings are given. The cancelled after-block (9
jobs) would have exceeded the cap under either. Charge by ladder level is in the EV-007b table above (2-job totals; P0.7 rows per job);
the two overflow-band levels are the expensive ones
(≈21–24M per XXL job, ≈42–46M per XXXL job). EV-007b's own cap is a separate,
explicitly sealed number: the gate ran before every launch attempt and never let
one start at or over 75M, and the 3.9 % overshoot is the final block — the
round that was already in flight, exactly the bound the sealed text names.
EV-007c's own cap (85M, an owner decision at seal) was gated the same way — the
gate ran before every launch (×4) — and this time the run ended **under** the cap,
at 93.0 %, with no overshoot and nothing retired to double-count.

### Reproduce / audit

Issues: [#202](https://github.com/caty-ai/caty-agent-harness/issues/202) (EV-007
run narrative and correction ledger D1–D7),
[#264](https://github.com/caty-ai/caty-agent-harness/issues/264) (EV-007b: P0.7,
both ladder rounds, the trap instrument, the seal, the §7 correction ledger, the
main run and its rig facts, wiring re-check),
[#263](https://github.com/caty-ai/caty-agent-harness/issues/263) /
[#267](https://github.com/caty-ai/caty-agent-harness/pull/267) (the recurrence-unit
change, released as v0.24.0),
[#264](https://github.com/caty-ai/caty-agent-harness/issues/264) again for
EV-007c (the seal, the run and its result comment),
[#274](https://github.com/caty-ai/caty-agent-harness/issues/274) /
[#275](https://github.com/caty-ai/caty-agent-harness/pull/275) (the citation-check
fix, released as v0.25.0),
[#265](https://github.com/caty-ai/caty-agent-harness/issues/265) (the Sonnet/Opus
ladder, not part of any of the three runs).

Pins: EV-007 sealed on `v0.21.1` (`74b9fbc9…`); EV-007b's pilots after 2026-09-02
19:43 UTC, and its sealed main run, on `v0.24.0` (`90a602f`, checked by tag and
SHA before every launch). The loop-layer diff between those two pins is
**not** zero, which is why the wiring re-check was redone rather than carried.
EV-007c is sealed on `v0.25.0` (`23ab781`, likewise checked by tag and SHA at both
preflights), and its wiring re-check was redone again on that pin.

Records in the private experiments tree, cited as pointers:
`PREREGISTRATION-MAIN-SEALED-20260827.md` (sealed 2026-08-27) ·
`REPORT-MAIN.md` (every figure reproduced by `tmp/report-aggregate.py`) ·
`PREREGISTRATION-P0.md` + `REPORT-P0.md` (the wiring proof) ·
`PREREGISTRATION-B-SEALED-2026-09-04.md` (sealed 2026-09-04T11:36Z, sha256
`fff51f7d…be8811`) with the §7 correction ledger (records A / B / C) in
`PREREGISTRATION-B.md` · `REPORT-B.md`, the EV-007b main-run report — every
figure in the subsection above is reproduced by `tmp/report-aggregate-b.py` ·
`EV007B-TRAP-DESIGN.md` v0.2 + `PANEL-RECORD-TRAP.md` (the instrument design and
its review panels) · `ev006/corpora/trap/SEAL-MANIFEST.txt` (the sealed trap
corpus) · `EV007B-DESIGN-NOTE.md`, `EV007B-RUNPLAN.md` ·
`results-main/` and `results-b/` (per-job score / gate / ledger and attempt
streams, per-round receipts, run ledger) · `results-p07/`, `results-calib/`
(pilots; ladder figures recomputed by `tools/calib_report.py`) ·
`results-b/wiring/recheck-v0.24.0.md` (the v0.24.0 wiring re-check, with every
receipt quoted verbatim).

EV-007c's records, in the same tree: `PREREGISTRATION-C-SEALED-2026-09-05.md`
(sealed 2026-09-05, sha256 `931601d8…7fed31`; its §7 correction ledger holds **no
records**) · `REPORT-C.md`, the EV-007c main-run report — every figure in the
EV-007c subsection above is reproduced by `tmp/report-aggregate-c.py`, with the
cap view from `tools/charge_sum.py --results results-c --cap 85000000` ·
`results-c/` (per-job score / gate / ledger and attempt streams, per-round
receipts `results-c/round-{1,2,3}/`, snapshots, and the run ledger
`results-c/run-ledger.log`) · `results-c/wiring/recheck-v0.25.0.md` and
`results-c/wiring/hook-demo-20260905T162128Z/` (the pre-run wiring re-check and
the Stop-hook demonstration) · the arm workspaces `ws-c-A`, `ws-c-B`, `ws-c-C`,
left untouched after the run.

### Future work

None of this is scheduled, and no dates are promised. Two of the three problems
this section opened with are closed: the instrument exists and is sealed
(`p3trap-M-i1` still produces repeat mistakes on `v0.25.0` — its 5 erratum-file
classes are a mistake in all 16 scored harness jobs and both bare jobs of
EV-007c), and **the review step now cites the raw layer it is given**, which is
what #274 landed and what EV-007c ran on. What is open is the instrument's
resolution and the channel the loop cannot see.

- **A hold-out instance before any confirmatory claim.** `p3trap-M-i2` — the same
  trap construction with renamed vocabulary — was named as a limitation at both
  seals and **has still not been built**. n = 1 run, one bit per class, and no
  hold-out: nothing here should be turned into a confirmatory result without it.
- **A per-class multi-item instrument.** One bit per class cannot separate "the
  rule is present" from "the rule is applied": in EV-007c the T2 rule was live in
  `General rules` through the final block and Q11 was wrong in both final jobs
  anyway. Distinguishing those two states is the next instrument question, and
  this instrument cannot do it.
- **The flush/lesson side, not the review.** T1 (the erratum-file classes) never
  moved for any arm in either main run, and no lesson, candidate or rule ever
  mentioned errata — the agent never wrote the bit down, so the loop never had it
  to review. That is a question for what gets written into the raw layer, not for
  what the review does with it.
- **The Sonnet/Opus ladder**
  ([#265](https://github.com/caty-ai/caty-agent-harness/issues/265)) now has a
  working instrument to start from, rather than the 19–20/20 corpora that stopped
  the first search, and EV-007c's single task model (haiku) is a carried limit it
  would answer.

The rig built for EV-007b — count-axis rounds with a resumable ledger, the
two-seat reviewer chain, the flush quarantine tool, the corpus resolver, the
trap generator and validator — is on disk and usable by any successor run.
