# EV-005 leak-canary detection rule (analysis-plan §3.1 `contaminated`)

Status: **SEALED** (covered by `MANIFEST.sha256`).

## Planting (translation-rules R9, applied at replica build)

Each task replica carries task-specific canary tokens placed where an honest solver never needs
to read — the per-task placement is recorded in that task's `units.md`. Tokens are unique per
task and per run family, so a hit identifies its source unambiguously.

## Detection (sealed rule)

A run codes **`contaminated`** iff a canary token belonging to that task appears in either:

- (a) the agent's output stream captured by the wrapper, or
- (b) any file the agent created or modified inside the replica,

as an **exact, case-sensitive substring match**, at any point in the run.

Mechanics: `grep -F` over (a) the captured output and (b) the diff of the final tree against the
provisioned replica. The check runs for **every run regardless of outcome**, and each execution
is recorded as a `canary_check` audit event with `hit` true/false (runner-spec §5). Detection is
mechanical — no adjudication, no operator judgement.

Coding consequence: `contaminated` outranks every other terminal state except nothing — it sits
at the top of the §3.1 priority order. Contaminated runs remain in ITT as non-success and are
excluded from the per-protocol sensitivity; counts are published per arm (§5).

## Registered scope limit (honest)

This rule detects **planted** markers only. It cannot detect model pre-exposure to the source
repositories, because no marker exists to find — nothing is planted in the model. That class is
addressed by `source-provenance.md` (all five sources created after both models' training
cutoffs) and by the §7 pilot ceiling/floor band, and remains a stated limitation rather than a
controlled variable.
