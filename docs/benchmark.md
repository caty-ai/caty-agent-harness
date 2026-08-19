# Benchmark — sealed, pre-registered, machine-scored

[🇯🇵 日本語版](benchmark.ja.md)

This page carries the full numbers behind the README claim — including the
places where the harness did **not** win. One benchmark lane exists per model;
new lanes are added as they are measured (tracking:
[#129](https://github.com/caty-ai/caty-agent-harness/issues/129)).

---

## What was measured

The failure this product exists for: an AI that says **"done!" without having
done the work**. We measured it on context-overflow workloads — jobs whose
reading volume (75K–300K tokens) cannot fit one context window.

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
answers fed back, M size only). Equal token caps per size for every arm.
Order: hypotheses and analysis pre-registered → corpora, graders and runners
hash-sealed (`SEAL-MANIFEST`, 185 files) → then the runs. Scoring is machines
only; near-miss adjudication was done arm-blind (54 candidates, 3 accepted —
one per arm).

### Primary result — verified completion on M/L (context-overflow) sizes

| | bare | harness |
|---|---|---|
| Verified completion, M/L pooled (n=30/arm) | 4/30 (13%, CI 5–30%) | **13/30 (43%, CI 27–61%)** |

Effect **+30 pt**, stratified exact test **p = 0.0079**. Naive-retry control:
2/15 (13%) at comparable cost to bare — retrying alone does not close the gap.

Per genre (M/L pooled): research 4/10 → 7/10 · code questions 0/10 → **6/10** ·
CSV **0/10 → 0/10** (see limitations).

### Completion hallucination — the headline number

| per completion claim | bare | harness |
|---|---|---|
| claimed "done" without having read the corpus (measured coverage) | 247/263 (**94%**) | 2/41 (**5%**) |

The two failure shapes are qualitatively different: bare's failed claims are
overwhelmingly *unread* claims; when the harness misses, it has read
everything and some answers are wrong — and when it cannot progress it stops
honestly (DLQ/no-progress) instead of declaring success.

We split hallucination three ways and **only the completion kind collapsed**:

| hallucination kind | bare | harness |
|---|---|---|
| completion (claimed done, work not done) | 94% of claims | 5% of claims |
| wrong answers (per-item error, M/L) | 22–31% | 24–38% |
| unsupported quotes (quote doesn't back the answer, M/L totals) | 138 | 166 |

The harness does not make the model smarter per answer — it makes the *claim
of completion* honest and the delivery verified.

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
  infra procedure (final data contains zero infra-terminated runs).

## Reproduce / audit

Design (5-seat cross-model review), pre-registration, seal manifest, raw
writeback and the adjudication log live in
[harness#100](https://github.com/caty-ai/caty-agent-harness/issues/100)
(final results comment). Raw per-run artifacts (transcripts, gates, scores,
ledgers) are retained offline and available on request — they are too large to
vendor into this repository.
