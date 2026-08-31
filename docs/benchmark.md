# Benchmark — sealed, pre-registered, machine-scored

[English](benchmark.md) | [日本語](benchmark.ja.md) ｜ back to the [front page](../README.md)

This page carries the full numbers behind the README claim — including the
places where the harness did **not** win. One benchmark lane exists per model;
new lanes are added as they are measured (tracking:
[#129](https://github.com/caty-ai/caty-agent-harness/issues/129)).

## The four experiment families — how to read this page

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
   arm P2-WIN deliberately left out: 8 sealed hold-out runs, reported in
   [#235](https://github.com/caty-ai/caty-agent-harness/issues/235); the full
   section lands on this page via its own reviewed lane
   ([#254](https://github.com/caty-ai/caty-agent-harness/issues/254)).

Everything here is sealed and pre-registered before any run, machine-scored,
and reported with its limitations attached — including the places where the
harness did not win.

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

| Model | Completion, bare vs harness (correct_resolved) | Efficiency, bare÷harness median charge |
|---|---|---|
| claude-haiku-4.5 (main run) | 13% vs 43% (M/L pooled, task_resolved) | tokens −59% |
| claude-sonnet-5 | 28/30 vs 28/30 — dead even | S 0.52× · M 0.63× · **L 2.40×** |
| claude-opus-5 | 30/30 vs 30/30 — full ceiling, zero false completions | M 1.17× · **L 1.46×** |

Read before quoting:

- The completion rescue is **haiku-band-only** — strong models complete these
  jobs bare. What they gain instead is **same-accuracy token savings emerging
  at the L band** (a ratio above 1.0 = harness cheaper; sonnet's S/M cells sit
  below 1.0 — the harness costs extra where the job fits comfortably).
- On the primary `task_resolved` metric, sonnet's harness arm shows −27pt —
  entirely p2 read-coverage-style violations (the known selective-reading
  artifact; the pre-registered secondary endpoint `correct_resolved` corrects
  it, and the near-miss ledger for P1 is empty). Both metrics are reported.
- The pilot's n=1 ratios (opus L ≈2×) converged to **1.46×** at n=15 — a live
  demonstration of why single-pair ratios are unreliable (see also the
  [EV-008 n=3 addendum](#ev-008-n3)).
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

The hero's `Tokens vs bare` converts the ratio to a reduction as
`1 − median(sentinel/bare)`, with the minus sign showing lower token charge:
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

- The single-run medians (sonnet 0.801, opus 0.923) sat well inside these
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
