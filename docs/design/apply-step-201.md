# Apply step — reviewed candidates → durable-tier writeback (#201)

Status: FROZEN 2026-08-27, superseding record v3.1 (L1-8): errata + classifications
forced by the 3-seat implementation review of f9dc955 (Opus 5 / GLM 5.3 / Kimi K3 —
§3.4 full token classification incl. supersedes-not-owned=terminal; §2.1 phase-3
receipt truthfulness; §2.2a temp-dir wording; §4 stub-replay canonical clarification;
§7 transitions-only stated exceptions; §9 second-run invariant + test seams). No
architectural change; upstream panel notified (Grok delta). Original freeze:
(L1-9 upstream review: 3-seat GO — see #201 adjudication records) (v1 reviewed
2026-08-27 by Kimi K3 / Grok 4.6 / GLM 5.3, all NO-GO;
v2 landed all round-1 flip conditions — delta verdicts Kimi GO / Grok GO / GLM NO-GO on
one remaining supersedes cell; v3 lands that cell plus all round-2 non-blocking
observations — adjudication records on #201)
Author: Alpha (orchestrator). Implementation writer will be Codex (Sol), per lane plan.
Refs: #148 (candidate generation, merged v0.18.0), #144 (promotion layer gap), #149
(monthly stocktake boundary), #170 (durable-tier caps), #182 (atomic_write_file guard,
adjacent), DESIGN.md §3.3–§3.4, EV-007 (#202) clarify decisions C1–C5.

## 1. Purpose and scope

`raw-review.sh` produces host-verified promotion candidates
(`loop/promotions/candidates-<runid>.md`, theme recurrence recomputed by the host).
Nothing consumes them (#144). The apply step is the missing consumer: it turns accepted
candidates into durable-tier entries.

In scope: consumption contract, approval flow, writeback to the three durable targets,
idempotency/dedup, caps interplay, receipts, rollback of apply's own promotions.

Apply performs exactly **three classes of STATE.md mutation**, all gated on apply's own
`source:` stamp — nothing else is ever touched:

1. append a new bullet whose `source:` is the promoted theme-id;
2. in-place append of ` invalidated-by: theme-<new>` on a line whose `source:` is the
   superseded theme-id (apply-created lines only — see §5 supersedes table);
3. `--rollback` of an apply-stamped line, plus one dated `## Open failures` bullet.

Out of scope (fixed boundaries):
- **#149 (monthly stocktake)** owns consolidation, demotion proposals, compaction, and
  any edit to lines that do not carry an apply `source:` stamp.
- **#182** (unguarded `cp` inside `atomic_write_file`) is adjacent, not solved here;
  apply reuses the existing guarded helper unchanged and inherits its fix when #182
  lands.
- Raw-review prompt/grammar changes (none needed — §8 D1).

## 2. Actor model, locks, and the publish recipe

Apply is a **host-run deterministic script** (`scripts/apply-promotions.sh`), part of
the trusted single-writer family (DESIGN §3.4 R6). No model call anywhere in apply.
Host-script seams, same as its siblings: `--workspace <dir>` argument resolved via
`caty_pause_canonical_workspace`; refuse to run unless pause state is `enabled`
(receipt `reason=skipped-paused`, exit 0); `umask 077`; exit map per
`docs/cli-conventions.md` (usage error = 2, operational failure = 1, success = 0).

### 2.1 Locks

- **Apply-exclusive lock** `loop/promotions/.apply.lock` (new; mkdir-style, pid file,
  stale threshold 1800 s, 3 bounded attempts) held for the **whole run**. Exactly one
  apply may be in any phase — this removes multi-process volume multiplication and
  concurrent stub creation by construction. Not shared with raw-review's `.lock`, so
  no interaction with the nightly review job.
- **Promotions lock** `loop/promotions/.lock` (same constants as raw-review's inline
  `take_review_lock`: 3 attempts / 1800 s stale / distinct pid label
  `apply-promotions`; the lock constants remain pinned here and duplicated) — held only
  for candidate-set snapshot and receipt appends.
- **State lock** via `take_state_lock "$workspace" apply-promotions <attempts> <sleep>`
  with **bounded attempts** (default 30 × 1 s, mirroring flush-intake; never
  `max_attempts=0`) — held only for the STATE.md publish.

Acquisition order is fixed: apply.lock → then promotions lock or state lock, **never
promotions and state simultaneously**. Current peers hold only one lock each
(flush-intake: state; raw-review: promotions), so no cycle exists.

Lock-acquisition failure in phase 1 or 2 = **abort before any STATE.md byte is
written**, exit non-zero. Phase-3 promotions-lock failure is the one case where STATE
and the index are already durably published: receipts are then the only loss, the
dangling `run-start` is the operator signal, and the index prevents replay — exit
non-zero so the caller knows receipts are incomplete. In that phase-3 case the
per-theme receipt lines and a summary with the **real** promoted/skipped counts are
O_APPENDed directly (raw-review.sh's existing lock-busy receipt precedent) — the
ledger must never assert fewer promotions than actually landed (v3.1, from the
implementation review: a hardcoded `promoted=0` summary both falsified the ledger and
suppressed the dangling-`run-start` crash signal). For phase-1 lock-busy, append
`decision=run-summary reason=lock-busy` if the promotions lock permits, else O_APPEND
it. Intake's lock-busy `exit 0` is explicitly **not** copied. Mid-run operational
aborts after `run-start` (rollback target invalid, torn index, caps-read-failed)
likewise leave a reasoned `run-summary` — a diagnosed refusal must not masquerade as
a crash (v3.1).

### 2.2 Run phases

1. **Run-start receipt** — under the promotions lock: append
   `decision=run-start applyid=<id> inputs=<n>` to `apply.log`, snapshot the candidate
   file set and `apply.log` + `apply-index.tsv` to a private temp dir; release.
   (A crashed run is thereafter mechanically detectable: `run-start` without a matching
   `run-summary`.)
2. **Writeback** — under the state lock:
   a. copy live `STATE.md` to a private temp file (0600, inside a private 0700
      mktemp directory on the same filesystem as STATE.md — same-filesystem is an
      `atomic_write_file` rename requirement, so "the workspace temp area" means a
      private temp dir under the workspace, created after the pause check and lock
      acquisition; v3.1 wording erratum);
   b. perform all mutations (appends, `invalidated-by:` annotations) **on the temp**;
   c. enforce caps by **refusal, not eviction** (§6): a section whose post-append line
      count would exceed its cap takes no further appends this run
      (`skipped reason=section-full`). Section identity and line counting use the same
      rules as the fold (`lib-state-fold.sh`): heading = prefix match on
      `## Verified facts` / `## General rules` at line start, count = every
      non-preamble section line. Duplicate or missing VF/GR headings → **abort the
      run** (`caps-read-failed`), zero STATE bytes — the fold's own heading validation
      is lost when the fold is not called, so apply re-implements it fail-closed;
   d. one single `atomic_write_file <temp> STATE.md`. `fold_declared_state_caps` is
      **never called by apply** and is never pointed at live STATE.md (its no-eviction
      path is a no-op that would leave a live append unguarded — v1 CRITICAL);
   e. in the same lock hold, rewrite `loop/promotions/apply-index.tsv` (§5, the
      anti-resurrection index) via `atomic_write_file`.
3. **Receipts** — retake the promotions lock: append per-theme receipt lines and the
   `run-summary` line to `apply.log`; release.

Crash-safety: the index and STATE.md are published in the same lock hold, so no crash
window can separate the durable effect from its anti-resurrection record (v1 accepted a
residual here; v2 closes it). A crash between phase 2 and 3 loses only operator-log
lines, which the next run detects via the dangling `run-start`.

## 3. Consumption contract

### 3.1 Input enumeration

Input files are exactly those matching the **anchored** pattern
`^candidates-[0-9]{8}T[0-9]{6}Z-[0-9]+\.md$` in `loop/promotions/` (the runid grammar
raw-review emits: `date -u +%Y%m%dT%H%M%SZ`-`$$`). This excludes
`candidates-*.rejects.md` by construction — reject files contain **unvalidated
model-raw blocks** whose citations failed, and consuming them is the cheapest
poisoning path (v1 MAJOR). Files must be regular non-symlink files; anything else is
`skipped reason=input-untrusted`. A fixture places a poisoned `.rejects.md` beside real
candidates and asserts zero consumption.

A file is revisited until every theme in it is in a **terminal** state (§3.4).

### 3.2 Block grammar

Full emitted grammar (all fields raw-review writes — v1 omitted three):
`## theme-<runid>-NNN`, `theme:`, `class:` ∈ {capability-fact, rule, skill},
`reviewer:`, `run-weeks:`, `run-k:`, `promote:` ∈ {yes, not-yet}, `supersedes:`
(optional), `weeks:`, `union-k:`, `members:` (list), `member-hash:` (list),
`evidence:` (block). A block that fails to parse completely, or contains unknown
required-field values, is `skipped reason=parse` — never partial-fix.

### 3.3 Hygiene: allowlist encoding of every interpolated field

**Candidates are untrusted data** (DESIGN §3.4). Every field that apply interpolates
into STATE.md, `apply-index.tsv`, receipts, or a filesystem path gets an allowlist
rule; violation → `skipped reason=hygiene` for the whole theme:

| Field | Rule |
|---|---|
| theme-id | must match `^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$` **and** its runid must equal the runid token of the candidates filename it came from (cross-file spoof block) |
| theme text | single line, non-empty, ≤ 240 bytes, no control characters, must not start with `#`, `-`, or whitespace, and must not contain any of the literal tokens: `source:`, `reviewer:`, `weeks:`, `k=`, `approver:`, `invalidated-by:`, `confirmations:`, `dedup_key:`, `mech_check:`, `<!--`, `-->` |
| reviewer | `^[A-Za-z0-9._+-]+$` |
| run-k / weeks / union-k | `run-k:` must be an ASCII non-negative integer no greater than the number of members; `weeks:` must match the ISO-week list grammar raw-review validates (`^[0-9]{4}-W[0-9]{2}(,[0-9]{4}-W[0-9]{2})*$`). With `recurrence_unit=sessions`, the bounded host-emitted `run-k:` is effective; with `recurrence_unit=weeks`, apply independently recounts distinct `weeks:` exactly as before. The file's `union-k:` integer and `promote:` field are advisory and never open the gate. |
| class | closed enum; NOTE: the class value is **model-chosen** upstream — see §4 residual |
| members / evidence | must be non-empty (raw-review guarantees this at generation; apply re-checks because the file is untrusted at consumption time) |
| skill slug | derived **only from the validated theme-id** (never from theme text): `theme-<runid>-NNN` → slug `<runid>-NNN` (charset `[A-Za-z0-9-]`, fixed length); stub path is `skills/_staging/<slug>/` and the resolved path must stay inside `skills/_staging/` (no symlink traversal); creation uses exclusive `mkdir` |
| `--reason` / approval manifest entries | same allowlist as reviewer plus `:#/-` — they are interpolated into `invalidated-by:` and Open failures lines |

Stub frontmatter values (description = theme text, source = theme-id + member list) are
written with a conservative encoder (single-quoted YAML with `'` doubled, or JSON
string encoding) — never raw interpolation into YAML. `status: draft` and `trigger:`
are host constants, not candidate fields.

Apply reads `recurrence_unit`, `promote_min_k`, and `promote_min_weeks` from
`loop/review.conf` with the same defaults and decimal/enum validation as raw-review.
Malformed values fail closed before candidate consumption, leave `STATE.md` unchanged,
exit 2, and append a `reason=config` run summary to `apply.log`.

### 3.4 Per-theme resolution states

**Every §7 reason token has exactly one classification here** (v3.1 erratum — the
3-seat implementation review demonstrated that an unclassified token, guessed as
persistable, bricked the index validator; the vocabulary the index accepts and the
vocabulary `record_result` can write MUST be one single table in the script, and the
index writer refuses out-of-vocabulary decisions at write time):

Terminal (never revisited): `promoted` (incl. `reason=stub-replay`), `rolled-back`,
`duplicate-content`, `hygiene`, `parse`, `superseded` (assigned the moment its
superseder promotes — same batch or cross-run, §5), `k-below-2` and
`weeks-below-min` (terminal because
recurrence emits a **new** theme-id in a later run; a frozen id's k never changes —
§9 has a fixture asserting the re-emitted id, not the frozen one, is what gets
reconsidered), `stub-exists` (foreign/non-canonical stub dirs only — see §4),
**`supersedes-not-owned`** (the non-owned target line belongs to
#149's jurisdiction; a re-review of the theme mints a new id, so the frozen id never
becomes promotable).

Revisit (pending): `awaiting-approval`, `section-full`, `volume-guard`,
`supersedes-ambiguous` (re-resolves only if a later batch changes the facts; never
promotes silently).

Run-level or receipt-only, never a per-theme index decision: `input-untrusted`
(per-file), `caps-read-failed`, `lock-busy`, `skipped-paused`, `config`, `rollback-refused`
(operational rollback refusal), `stub-dirty` (rollback-operation outcome),
`unknown-approval`, `already-applied`,
`already-rolled-back` (the latter three are guard outcomes about an id whose index
row keeps its original decision — persisting them would rewrite history; v3.2 nit
from the delta review: listing them as Terminal invited a future edit to persist
them, which would reintroduce the vocabulary-mismatch CRITICAL). These never produce
index rows. The index-decision table and the summary/receipt reason-token table are
distinct; only the former is accepted by the index grammar, so `rollback-refused`
MUST NOT enter the index-decision table or an index row.

`supersedes-unresolved` is a **receipt annotation only** (`note=supersedes-unresolved`
on the promoted superseder's receipt line) — no theme ever holds it as a decision
state (v2 let two readings diverge here; this closes it).

Resolution is computed from `apply-index.tsv` (primary) with `apply.log` as the
operator view; `apply.log` missing → treated as empty (the index is authoritative);
`apply-index.tsv` torn or grammar-invalid → **abort the run**, promote nothing
(harness-owned file, strict parse posture, fail-closed).

### 3.5 Volume guard

At most `APPLY_MAX_PER_SECTION` (default 20) promotions per durable section per run,
and at most `APPLY_MAX_AUTO` (default 10) of those via the auto path (§4). Excess is
`skipped reason=volume-guard`, pending. With §6 no-eviction promotion and the
apply-exclusive lock, a pending tail can no longer flush a section — it can only fill
the remaining headroom, so the guard now bounds churn rate, not blast radius.

## 4. Approval flow and targets

Owner decisions (2026-08-26/27): approver = Alpha; capability-class facts **may**
auto-promote. v2 realizes "may" as an explicit flag rather than a bare default
(3-seat convergent finding: `class:` is model-authored, so a bare-run auto default
routes the approval gate through a value the reviewed model chose):

- **Default run: nothing is written to STATE.md.** The run reports pending themes
  (receipt + stdout) and materializes skill stubs only.
- `--auto-capability-facts`: promotes hygiene-passing capability-facts whose effective
  recurrence meets `promote_min_k` and whose recounted ISO-week spread meets
  `promote_min_weeks`
  into `## Verified facts` without per-theme approval. This is the flag EV-007 arm C
  passes inside the loop. Auto-promoted lines carry `approver=auto` in the receipt and
  `approver: auto` in the provenance trailer — the entry-format block below is the
  **single canonical trailer grammar**; #149 stocktake and rollback sweeps grep the
  literal `approver: auto`. Bounded by `APPLY_MAX_AUTO`.
- `--approve theme-<id>` (repeatable) / `--approve-file <manifest>`: promotes the named
  themes (`rule` → `## General rules`, `capability-fact` → `## Verified facts`).
  Manifest grammar: UTF-8 text, one theme-id per line, `#` comments, blank lines
  ignored, must be a regular non-symlink file; unknown or non-pending ids →
  `skipped reason=unknown-approval` (never fail-open into promotion).
  **Approval never overrides hygiene, the configured recurrence/week gates, or caps** —
  an approved theme failing those is skipped with the stronger reason.
- Approver identity: `approver=alpha` is a receipt label (workspace-local host tool;
  whoever can run the script can approve — recorded, not authenticated).

| class | target | path |
|---|---|---|
| capability-fact | `## Verified facts` | `--auto-capability-facts` or explicit approval |
| rule | `## General rules` | explicit approval only |
| skill | `skills/_staging/<slug>/SKILL.md` draft stub | materialized on any run; never touches STATE.md; promotion `_staging → skills/` stays on the existing R12 verifier-gated path, outside apply |

Skill stubs: frontmatter carries a host-written `source: theme-<id>` line; the
existence guard is the directory **and** that frontmatter stamp. Crash-replay after
`mkdir` (with or without `SKILL.md` yet written, **including a fully-written
byte-canonical stub whose index/receipt write was lost** — the canonical check is the
existing byte-identity helper) → complete the stub if needed and receipt
`decision=promoted reason=stub-replay` (not `stub-exists`), so replay converges and
the stub stays rollbackable. `stub-exists` is reserved for foreign or non-canonical
directories at the slug path (v3.1 clarification — the implementation review found a
post-write crash window that mislabeled apply's own stub).
Stub creation does not count against `APPLY_MAX_PER_SECTION` (stubs are never
CONSULT-loaded).

Entry format written (matches the `templates/STATE.md` comment grammar):

```
- 2026-08-27 <theme text> (source: theme-<runid>-NNN; reviewer: <reviewer>; weeks: <recounted list>; k=<effective>; unit=<sessions|weeks>; approver: <alpha|auto>)
```

The `source:` stamp is the idempotency and rollback anchor; its regex (anchored to the
trailer position, `\(source: theme-[0-9TZ-]+-[0-9]{3};` …) must match **exactly one**
line for rollback/annotation — zero or multiple matches abort that operation
(fail-closed; a theme text can no longer fake a second stamp because `source:` is a
banned token in theme text, §3.3). The reader also accepts the pre-#263 trailer without
`unit=` so existing apply-stamped entries remain deduplicatable and rollbackable.

## 5. Idempotency and dedup

**Anti-resurrection source of truth = `loop/promotions/apply-index.tsv`** — one row per
theme-id ever decided: `theme_id  class  decision  applyid  line_sha  ts`. Written via
`atomic_write_file` in the same state-lock hold as the STATE.md publish (§2.2), so no
crash can separate them. Apply is its only writer. Rollback updates the row
(`decision=rolled-back`) in the same hold as the STATE edit. Cap-eviction of a
promoted line by *other* actors (intake's fold), apply.log loss, or workspace restore
from a STATE-only backup can no longer resurrect a promotion (v1 MAJOR, closed).

Guard order, pinned (first hit wins):

1. hygiene (§3.3) → `hygiene`
2. theme-id present in apply-index (any terminal decision, including `rolled-back`) →
   `already-applied` (its own reason token; fixtures cover it)
3. theme-id stamp present in the target section of current STATE.md (anchored trailer
   match) → `already-applied` (index self-heals: row is re-added if missing)
4. content dedup: normalized theme text equals the normalized theme text of any
   existing line in the target section. Normalization is **apply-defined**: strip
   leading `- YYYY-MM-DD `, strip the trailing ` (source: …)` trailer by the anchored
   trailer regex (the existing `normalize_state_candidate` strips only the short
   legacy trailer and is NOT reused for this), collapse whitespace, case-preserve →
   `duplicate-content`. Legacy lines with differently-shaped stamps will not
   dedup-match a re-entered identical theme — conservative by intent (misses some
   dupes, never false-positives; #149 owns legacy consolidation)
5. supersedes resolution (table below)
6. configured-unit effective k → `k-below-2` (before the approval gate, so an
   under-threshold theme terminates instead of lingering as `awaiting-approval` forever)
7. independent distinct-week recount → `weeks-below-min`
8. approval / auto gate (§4) → `awaiting-approval`
9. caps headroom (§6) → `section-full`
10. volume guard → `volume-guard`
11. promote

Supersedes table (v1 left every non-happy path to the implementer):

| Case | Behavior |
|---|---|
| superseded theme applied earlier, line present with apply stamp | promote new line + in-place ` invalidated-by: theme-<new>` on the old line, same phase-2 hold; annotation is idempotent (skip if already present, never double-append) |
| superseded theme in apply-index as `promoted`/`rolled-back` but line evicted/absent from STATE | promote new line, receipt carries `note=supersedes-unresolved` (old line legitimately gone; nothing to annotate) |
| superseded theme in apply-index with a **pending** decision (e.g. `awaiting-approval`), no STATE line | superseder promotes (subject to its own guards) **and** the target's index row is updated to `superseded` (terminal) in the same state-lock hold — a later `--approve` of the target is then `skipped reason=unknown-approval` (non-pending). Closes the round-2 ordering inversion: a stale pending theme can never promote after its successor |
| supersedes target present in STATE **without** an apply stamp | promote nothing for this theme: `skipped reason=supersedes-not-owned` (#149 territory; apply must not edit non-apply lines) |
| supersedes target unknown everywhere (not in index, not in STATE, not in batch) | promote the new line, receipt carries `note=supersedes-unresolved` |
| same batch: superseded + superseder both present | superseded theme is skipped `reason=superseded` **only if the superseder is promoted in this run**; if the superseder is skipped (hygiene/approval/…), the superseded theme is evaluated on its own merits this run |
| cycles, or two superseders naming one victim, or chain ambiguity | promote **neither** side: `skipped reason=supersedes-ambiguous` (upstream raw-review collapses multi-matches last-match-wins — noted for #148 follow-up; apply cannot reconstruct the chain, so it stops) |

## 6. Caps interplay (#170)

**Apply is never the cause of an eviction.** It enforces caps by refusal: if appending
would push a section past its cap (`STATE_FOLD_VERIFIED_CAP_DEFAULT`=120 /
`STATE_FOLD_RULES_CAP_DEFAULT`=80, read from lib-state-fold constants), the append is
`skipped reason=section-full` and stays pending; #149 owns shrinking full sections.
Consequences, stated: live STATE.md is never over-cap even transiently; apply never
calls `fold_declared_state_caps`; untrusted input can no longer choose which trusted
lines leave (v1's per-run eviction bound is superseded by this strictly stronger
invariant); the cap numbers are never raised by apply. `caps-read-failed` fires when
the cap constants cannot be sourced/parsed from `lib-state-fold.sh` or the §2.2c
heading validation fails — in both cases the run aborts with zero STATE bytes.

Rollback's `## Open failures` append is not covered by the VF/GR fold; the failures
cap (100) is enforced by the intake path on the next intake. Bounded by promotion
count, documented as accepted.

## 7. Receipts and rollback

`loop/promotions/apply.log` — append-only operator ledger (the index, §5, is the
resolution authority). Lines:

- `decision=run-start applyid=<id> inputs=<n>` (phase 1)
- per-theme **transitions only** (a theme that stays `awaiting-approval` across 300
  nightly runs produces one line, not 300; the run-summary carries still-pending
  counts). Stated exceptions (v3.1, each is deliberate operator feedback): a
  persistent `input-untrusted` file re-receipts every run (nagging is intended); the
  malformed content of an invalid/unparseable theme-id re-receipts every run because
  it has no stable index key and the operator must remove the garbage (adding another
  durable seen-set is outside this step and, if needed, belongs to #149); the
  guard-3 index self-heal emits one forced receipt when it re-adds a lost row (an
  index mutation must never be silent); a stale `--approve` of a non-pending id
  re-receipts `unknown-approval` per invocation (the operator passed the flag, the
  operator gets the answer): `ts=<UTC> applyid=<id> theme=<theme-id> class=<class> decision=promoted|skipped|rolled-back reason=<token> note=<supersedes-unresolved|-> k=<effective-k|-> unit=<sessions|weeks|-> approver=<alpha|auto|-> target=<section|staging-path> line_sha=<sha256 of written line|->`
- `decision=run-summary` with counts promoted/skipped-by-reason/pending, always
  appended on every completed run (0-consumed stays operator-visible; a `run-start`
  with no `run-summary` marks a crashed run).

For a malformed block with a valid theme-id, an existing terminal index row suppresses
another per-theme receipt and index upsert. The run-summary still counts the block under
its original `hygiene` or `parse` token; the existing index is the only seen-set.

Reason-token set is closed: `hygiene parse rollback-refused input-untrusted already-applied
duplicate-content superseded supersedes-not-owned
supersedes-ambiguous awaiting-approval unknown-approval k-below-2 weeks-below-min section-full
volume-guard stub-exists stub-replay stub-dirty caps-read-failed lock-busy
skipped-paused already-rolled-back config` — §9 requires a fixture per token.

Rollback (`apply-promotions.sh --rollback <theme-id> --reason <ref>`):

- Runs under the same `.apply.lock` as a promotion run (whole-operation exclusive), so
  an apply run's phase-2 index rewrite can never clobber a concurrent rollback's row
  update.
- STATE line: locate by anchored stamp (exactly one match or abort), append
  ` invalidated-by: <ref>` in place, add a dated `## Open failures` entry naming what
  the review missed (DESIGN §3.3), single atomic rewrite + index update in the same
  hold, receipt `decision=rolled-back`. `rolled-back` is terminal: the theme-id can
  never be re-promoted (index row wins even after later `--approve`); re-rollback →
  `skipped reason=already-rolled-back`. `--reason` passes §3.3 hygiene.
- `_staging` stub: delete **only if** the frontmatter `source:` matches the theme-id
  **and** the directory content is byte-identical to what apply would generate
  (no human edits since creation); otherwise `skipped reason=stub-dirty` and a human
  or #149 cleans up. No `--force` in v1 of the script.
- Rollback touches only apply-stamped artifacts; everything else is #149.

## 8. Decisions folded in from the EV-007 pilots (reworded after v1 review)

- **D1 — quality-gate placement**: apply stays model-free; the mechanical subset
  (§3.3) is enforced at apply. The review-stage model prompt encourages
  miss-derived, behavior-level rule wording (pilot P0.6: miss-derived rules cost
  2.68M→2.01M tokens/job; speculative rules doubled churn) — but **a prompt is a
  pre-filter, not a gate**. The binding quality gate for rules is the explicit
  approval flag; for auto-promoted capability-facts the binding gates are mechanical
  only (hygiene + configured-unit recurrence and calendar-spread gates), and §11
  records that residual honestly.
- **D2 — shared review configuration**: apply consumes the three raw-review recurrence
  keys from `loop/review.conf`; apply-only caps and lock controls remain constants plus
  env overrides (`APPLY_MAX_PER_SECTION`, `APPLY_MAX_AUTO`, lock attempt counts).
- **D3 — invocation modes**: bare run = report + stubs only (writes nothing durable);
  EV-007 arm C invokes `--auto-capability-facts`; Alpha's approval sessions pass
  `--approve`/`--approve-file`. Arm C's loop cadence should size its timeout for the
  worst-case stale-lock wait (up to 1800 s if a prior holder crashed).

## 9. Test plan (implementation gate, per Done when)

- One fixture per reason token (closed set, §7), including: poisoned `.rejects.md`
  beside real candidates (zero consumption); reviewer/weeks/theme-id injection;
  cross-file theme-id spoof (runid mismatch); slug traversal attempt via crafted
  theme-id; YAML breakout attempt in stub description; control chars / banned tokens /
  oversize in theme text; inflated or non-decimal `run-k`; sessions and weeks unit
  gates; independent `promote_min_weeks`; lying `promote: yes` below threshold;
  `--approve` attempting to override hygiene and recurrence (must fail); unknown-approval manifest entries;
  approval manifest as symlink (refused).
- Idempotency: byte-identical STATE.md on immediate re-run; `already-applied` via
  index, via stamp, and via content dedup separately; index survives simulated cap
  eviction by an intake fold (no resurrection); rolled-back theme cannot be
  re-promoted even with `--approve`.
- Crash windows: kill after phase 2 (STATE + index written, no receipts) → next run
  detects dangling `run-start`, re-run converges with no double promotion; kill after
  stub `mkdir` → `stub-replay`; torn `apply-index.tsv` → run aborts, zero STATE bytes.
- Caps: section at cap-1 accepts exactly one line; over-cap appends never visible in
  live STATE at any point (assert no intermediate write); volume guard across two
  sequential runs of the same file; auto sub-cap.
- Supersedes: every row of the §5 table, including cycle and not-owned; annotation
  idempotency (no double `invalidated-by:`); **cross-run pending target**: pending
  target + cross-run superseder promotion + later `--approve` of the target → must
  skip (`unknown-approval`), never promote.
- k-below-2 lifecycle: frozen theme-id stays terminal; a later run re-emitting the
  recurred theme under a new id is what gets reconsidered.
- Duplicate or missing VF/GR headings in STATE.md → run aborts (`caps-read-failed`),
  zero STATE bytes.
- Locks: lock-busy on each of the three locks → zero STATE bytes + correct receipt/
  exit; paused workspace → `skipped-paused`.
- At least one replay against a real `candidates-<runid>.md` from the 34-day corpus
  (plus the fixture suite above — the corpus alone does not exercise the guard
  paths).
- Assert all STATE.md mutations go through `take_state_lock` + `atomic_write_file`
  (no unguarded cp/append anywhere in apply).
- **Second-run invariant (v3.1, from the implementation review's CRITICAL)**: after
  EVERY reason-token fixture, re-run apply and assert the run exits with its expected
  code and `apply-index.tsv` still parses — no token may ever write a row the
  validator rejects. Plus a static assertion that the decision vocabulary
  `record_result` can persist is a subset of the validator's accepted set (single
  table, §3.4).
- Crash-window test seams: the script may ship env-gated self-kill hooks
  (`APPLY_TEST_CRASH_AFTER_STUB_MKDIR`, `APPLY_TEST_CRASH_AFTER_PHASE2`, and a
  between-STATE-and-index variant) — declared here as the documented test seam
  (v3.1; they only SIGKILL the process, never write) and listed in
  `docs/reference.md` alongside the other `APPLY_*` variables.
- Phase-3 lock-busy truthfulness: a run that published STATE must never record a
  summary asserting fewer promotions than landed — fixture races the promotions lock
  after phase 2 and asserts ledger/STATE agreement (v3.1, from the implementation
  review).

## 10. Files touched by the original #201 implementation phase

- `scripts/apply-promotions.sh` (new; contains its own promotions-lock helper with
  pinned constants and its own durable-section append/annotate awk; sourced reuse of
  `take_state_lock` / `release_state_lock` / `atomic_write_file` / cap constants only)
- `loop/promotions/apply-index.tsv`, `loop/promotions/apply.log`,
  `loop/promotions/.apply.lock` (new runtime artifacts, created on first run)
- `tests/apply-promotions/…` (new fixtures + replay test)
- `docs/engineering.md` / `docs/reference.md` (short promotion-consumer section;
  README claim fix stays in #146)

## 11. Threat model — named failure modes → mitigations → residuals

| # | Failure mode | Mitigations (§) | Residual after v2 |
|---|---|---|---|
| 1 | Durable-tier poisoning / section flush | anchored input enum excl. rejects (3.1); allowlist encoding of every interpolated field + banned-token list + theme-id↔filename binding (3.3); no-eviction promotion — untrusted input cannot evict trusted lines (6); slug from validated id only + exclusive mkdir (3.3); stubs never CONSULT-loaded (4) | a well-cited, hygiene-passing but *maliciously worded* capability-fact meeting the configured recurrence unit and thresholds still auto-promotes under `--auto-capability-facts`: `class:` and theme wording are model-chosen, and recurrence + citation authenticity ≠ benign intent. Bounded by `APPLY_MAX_AUTO`, the `approver: auto` provenance marker (sweepable), rollback, and #149. Accepted by owner decision; EV-007 measures the real-world rate. |
| 2 | Broken idempotency / resurrection | apply-index written atomically in the same lock hold as STATE (5); guard order pinned (5); `rolled-back` terminal (7); stub frontmatter stamp + `stub-replay` (4) | index + STATE + log all lost simultaneously (full workspace loss) — unrecoverable by design anywhere; content dedup blocks a *new* theme-id with identical normalized wording even when legitimate (operators reword or use #149) |
| 3 | Fail-open | closed reason-token set with terminal/revisit split (3.4); torn index aborts (3.4); approval cannot override gates (4); ambiguous supersedes stops (5); lock failure aborts before write (2.1) | none known at design level; §9 pins each with a fixture |
| 4 | Lock/crash windows | apply-exclusive lock (2.1); fixed acquisition order, never promotions+state together (2.1); single atomic publish + same-hold index (2.2); run-start/run-summary crash detection (7) | #182's `cp` window inside `atomic_write_file` (inherited, adjacent); stale-lock steal at 1800 s against a live-but-slow holder (existing `take_state_lock` property, unchanged) |
