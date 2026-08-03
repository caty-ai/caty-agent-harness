# BRIEF.tmpl.md — canonical delegation brief (3-layer)

<!-- Fill every slot. If a slot is genuinely N/A, write "none" — do not delete it.
     Before writing, CONSULT skills/ for a delegation-<worker> skill and apply it.
     Calibrate prescription to the worker model's tier: strong models (Fable-class)
     get constraints and goals, not step-by-step scripts — over-prescription degrades
     their output (official Fable 5 guidance). Weak/local models need explicit
     enumeration of what to produce (field-verified: Claire's distiller 0→10 bullets
     after enumeration). -->


## 実装仕様 Goal
- **Deliverables**: exact files/outputs, with paths.
- **SoT to read first**: the spec/docs the worker must read before acting.
- **Context**: repo, branch, runtime facts the worker cannot discover cheaply.
- **Scope-out**: files/areas the worker must NOT touch (explicit list).
- **Sandbox constraints**: known worker limitations (see delegation-<worker> skill),
  e.g. "FILES ONLY — no git commands; the caller commits".
- **Budget**: hard time budget + fallback ("if X has not finished in N minutes,
  kill it and do Y / report") — never allow open-ended waiting. Never end a reply
  on a promise ("I'll wait", "I'll now do X") — do the work or report blocked.

## 実装チェック Self-verification
- Audit every claim in your report against a tool result from this run; report only
  evidenced work, and mark anything unverified as unverified.
- Executable checks with expected results (commands, exit codes, output to paste).
- At least one end-to-end dry-run where applicable, run twice if idempotency matters.
- "Confirm you did NOT do <scope-out item>" for the riskiest exclusions.

## レビュー基準 Reviewer criteria
- Report format (raw markdown, no preamble) and required evidence
  (diff stat, run transcripts, deviations WITH reasons).
- Who verifies and who commits (default: caller reviews independently and commits;
  worker never merges or pushes).
- What the reviewer will re-run independently — tell the worker so it leaves the
  environment reproducible.

<!-- DISTILL hook: if this delegation failed or needed rework, update (or stage) the
     delegation-<worker> skill with what you would put in the next brief. -->
