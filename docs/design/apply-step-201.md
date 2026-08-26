# Apply step — reviewed candidates → durable-tier writeback (#201)

Status: DRAFT for L1-9 upstream review (design freeze happens on #201 after adjudication)
Author: Alpha (orchestrator). Implementation writer will be Codex (Sol), per lane plan.
Refs: #148 (candidate generation, merged v0.18.0), #144 (promotion layer gap), #149
(monthly stocktake boundary), #170 (durable-tier caps), #182 (atomic_write_file guard,
adjacent), DESIGN.md §3.3–§3.4, EV-007 (#202) clarify decisions C1–C5.

## 1. Purpose and scope

`raw-review.sh` produces host-verified promotion candidates
(`loop/promotions/candidates-<runid>.md`, theme recurrence recomputed by the host,
`promote: yes` only at union-k ≥ 2). Nothing consumes them (#144). The apply step is
the missing consumer: it turns accepted candidates into durable-tier entries.

In scope: consumption contract, approval flow, writeback to the three durable targets,
idempotency/dedup, caps interplay, receipts, rollback of apply's own promotions.

Out of scope (fixed boundaries):
- **#149 (monthly stocktake)** owns consolidation, demotion proposals, compaction, and
  any edit to entries apply did not create. Apply is strictly additive plus targeted
  rollback of its own promotions.
- **#182** (unguarded `cp` inside `atomic_write_file`) is adjacent, not solved here;
  apply reuses the existing guarded path and inherits its fix when #182 lands.
- Raw-review prompt/grammar changes (none needed — see §8 decision D2).

## 2. Actor model and concurrency

Apply is a **host-run deterministic script** (`scripts/apply-promotions.sh`), part of
the trusted single-writer family (DESIGN §3.4 R6). No model call anywhere in apply.

Lock protocol (never holds both locks at once; three phases):

1. **Snapshot** — take `loop/promotions/.lock` (same helper as raw-review): read the
   candidate file set and `apply.log`; copy candidates to a temp dir; release.
2. **Writeback** — take the state lock (`take_state_lock`, `loop/.distill-state.lock`):
   dedup against current `STATE.md`, append accepted entries, run
   `fold_declared_state_caps` (existing #170 enforcement), rewrite via
   `atomic_write_file` only; release.
3. **Receipt** — retake `loop/promotions/.lock`: append receipt lines to
   `loop/promotions/apply.log`; release.

Crash-safety: idempotency (§5) never depends on receipts alone, so a crash between
phase 2 and 3 cannot double-promote.

## 3. Consumption contract

Input: every `loop/promotions/candidates-<runid>.md` not yet fully resolved in
`apply.log` (per-theme resolution, not per-file, so a partially approved file is
revisited). Blocks are parsed with the field grammar raw-review emits: `## theme-…`,
`theme:`, `class:` ∈ {capability-fact, rule, skill}, `promote:` ∈ {yes, not-yet},
`supersedes:` (optional), `weeks:`/`union-k:`, `members:`, `member-hash:`, `evidence:`.

**Candidates are untrusted data** (DESIGN §3.4: citation validation proves source
authenticity, not benign intent). Mechanical hygiene gates, applied before any theme is
eligible (fail → `skipped reason=hygiene`, never partial-fix):

- theme text: single line, non-empty, ≤ 240 bytes, no control characters
- must not start with `#`, `-`, or whitespace (apply constructs the bullet itself)
- must not contain `<!--`, `invalidated-by:`, or the field-name tokens of the STATE
  entry grammar (marker/provenance spoofing)
- block must parse completely; unknown `class` or malformed `union-k` → skip
- `promote: not-yet` → `skipped reason=k-below-2` (recorded, may pass later)
- a theme listed in another theme's `supersedes:` chain in the same batch → the
  superseded one is `skipped reason=superseded`

Per-run volume guard: at most `APPLY_MAX_PER_SECTION` (default 20) promotions per
durable section per run. Anything beyond is `skipped reason=volume-guard` and remains
pending. Rationale: a single poisoned or runaway candidates file must not be able to
flush an entire durable section through cap eviction in one run.

## 4. Approval flow and targets

Owner decisions already fixed (2026-08-26/27): approver = Alpha; capability-class
facts may auto-promote.

| class | target | approval |
|---|---|---|
| capability-fact | `## Verified facts` | **auto** when `promote: yes` (host-recomputed k ≥ 2) and hygiene passes |
| rule | `## General rules` | requires explicit approval: `--approve theme-<runid>-NNN` (repeatable) or `--approve-file <manifest>`; unapproved → `skipped reason=awaiting-approval`, stays pending |
| skill | `skills/_staging/<slug>/SKILL.md` draft stub only | no approval consumed; see below |

- Approval identity is recorded per receipt (`approver=alpha`). The approval manifest
  is an input, not a store — the durable record of "who approved what, when" is the
  receipt line.
- **skill class**: a candidate carries a theme + cited member quotes, not a reusable
  procedure, so apply cannot author a skill. It materializes a draft stub in
  `skills/_staging/` (never loaded at CONSULT) with the draft schema fields
  (`name, description, trigger: TODO, status: draft, source: theme-id + members`).
  Promotion `_staging → skills/` stays on the existing R12 path (human/agent authored,
  verifier-gated) and is not part of apply. If the stub directory already exists,
  `skipped reason=stub-exists`.

Entry format written (matches the `templates/STATE.md` comment grammar):

```
- 2026-08-27 <theme text> (source: theme-<runid>-NNN; reviewer: <model>; weeks: <list>; k=<union-k>)
```

The `source: theme-…` stamp is the idempotency and rollback anchor.

## 5. Idempotency and dedup

Primary guard (source of truth): under the state lock, a theme is already applied if
its `theme-<runid>-NNN` stamp appears in the target section of current `STATE.md`.
Secondary guard: `apply.log` contains a `decision=promoted` line for the theme-id
(covers the case where the promoted line was later evicted by caps — eviction must not
resurrect a promotion). Tertiary (content-level) dedup: exact-line match of the
normalized theme text against the target section (catches a re-reviewed theme that
returns under a new theme-id), recorded as `skipped reason=duplicate-content`.

`supersedes:` handling — when the superseded theme was itself applied earlier, apply
(a) promotes the new line and (b) rewrites the old line **in place** appending
` invalidated-by: theme-<new>` (permitted by the STATE entry grammar), both inside one
phase-2 lock hold and one atomic rewrite. No line is ever deleted by apply.

Residual accepted risk: crash after phase 2 but before phase 3, followed by cap
eviction of the new line before the next run, loses both guards for that theme. The
archive eviction markers (`<!-- caps eviction … -->` + weekly archive) keep the event
reconstructable; judged acceptable and documented.

## 6. Caps interplay (#170)

Apply never bypasses caps: every write goes through the same
`fold_declared_state_caps` + `atomic_write_file` path the fold already uses, inside the
same lock hold as the append. Caps are never raised by apply; evictions archive
normally. The volume guard (§3) bounds how much eviction pressure one run can create.
Consolidation of a full section is #149's job, not apply's.

## 7. Receipts and rollback

`loop/promotions/apply.log` — append-only, one key=value line per theme per run
(same style as `runs.log`):

```
ts=<UTC> applyid=<runid-of-apply-run> theme=<theme-id> class=<class> decision=promoted|skipped|rolled-back reason=<token> approver=<id|-> target=<section|staging-path> line_sha=<sha256 of written line|->
```

Every run also appends one summary line (`decision=run-summary`,
counts promoted/skipped by reason) so "0 consumed" stays operator-visible.

Rollback (`apply-promotions.sh --rollback <theme-id> --reason <ref>`): under the state
lock, locate the promoted line by its `source:` stamp, append
` invalidated-by: <ref>` in place, add a dated `## Open failures` entry naming what the
review missed (DESIGN §3.3 rollback contract), atomic rewrite, then receipt
`decision=rolled-back`. Rollback of a `_staging` stub = delete the stub directory
(drafts are explicitly non-durable) + receipt. Apply can roll back **only lines
carrying an apply `source:` stamp**; everything else is #149 territory.

## 8. Decisions folded in from the EV-007 pilots

- **D1 — rule-text quality gate placement**: the semantic gate ("derived from a real
  observed miss, behavior-level wording, no baked-in point-in-time values") lives in
  the **review stage** (raw-review's model prompt already owns semantic judgment;
  EV-007 arm C additionally distills from real misses by protocol). Apply, being
  deterministic, enforces only the mechanical subset (§3 hygiene + length). Rationale:
  a host script cannot judge wording quality without a model call, and apply must stay
  model-free (§2). Pilot P0.6 evidence: miss-derived rules cost less downstream
  (2.68M→2.01M tokens/job) while speculative rules doubled churn — this is a prompt/
  protocol concern, not an apply-code concern.
- **D2 — no new conf keys**: apply ships with constants + env overrides
  (`APPLY_MAX_PER_SECTION`); no `loop/review.conf` additions, so no collision with the
  #196 conf-template lane (resolves the UNKNOWN in the #201 file prediction: no
  serialization needed).
- **D3 — non-interactive default**: a bare `apply-promotions.sh` run auto-applies
  eligible capability-facts and reports pending rules; approvals are explicit flags.
  This is what EV-007 arm C invokes inside the loop.

## 9. Test plan (implementation gate, per Done when)

- Fixture coverage: accept/skip for every `reason` token above; supersedes in-place
  annotation; volume guard; hygiene rejections (control chars, marker spoofing,
  oversize); idempotent re-run (byte-identical STATE.md); crash-window replay
  (phase 2 done, phase 3 missing → no double promotion); rollback round-trip.
- At least one replay against a real `candidates-<runid>.md` from the 34-day corpus.
- All STATE.md mutations asserted to go through `take_state_lock` +
  `atomic_write_file` (no raw `cp`/append in apply — #201 Done when).

## 10. Files to touch (implementation phase, to re-declare at WIP update)

- `scripts/apply-promotions.sh` (new)
- `tests/apply-promotions/…` (new fixtures + replay test)
- `docs/engineering.md` / `docs/reference.md` (short promotion-consumer section;
  README claim fix stays in #146)
- read-only reuse: `scripts/lib-state-fold.sh` helpers (no edits planned; if a helper
  needs a signature change it will be declared before writing)
