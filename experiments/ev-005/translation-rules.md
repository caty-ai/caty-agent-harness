# EV-005 translation rules — Done when → donecheck

- Normative design: caty-ai/caty-agent-harness#63 (v2.1, frozen 2026-08-13)
- Purpose: make the conversion from an issue's completion criterion ("Done when") to a mechanical gate (`donecheck.sh`) **rule-derived rather than authored ad hoc**, so that (a) the bundle is internally consistent, (b) a third party can audit any task by re-deriving its donecheck from these rules, and (c) authoring bias cannot leak asymmetrically into one arm — all arms share the identical task file set (design §2).
- Scope: applies to every task in the bundle, re-enacted and synthetic alike. For synthetic tasks the author first writes a Done when in issue style, then applies these same rules.

## 1. Decomposition

R1. Split the Done when into **check units**: one unit per independently falsifiable claim. A bullet may yield several units; prose yields units at sentence/clause level.

R2. Classify each unit:

| class | meaning | fate |
|---|---|---|
| MECH | decidable by a deterministic local procedure (file content, command exit, diff shape, behavior probe) | becomes one or more donecheck assertions |
| HUMAN | requires human/owner judgement, approval, live external interaction, or aesthetics | see R3 |
| MOOT | meaningless in the anonymized replica (e.g. "PR merged", "label created", process/CI-platform steps) | dropped, recorded |

R3. HUMAN units: if a *behavioral core* can be extracted (e.g. "docs explain X" → "doc file contains a section whose body mentions X's required elements"), extract it and record the weakening in the task's ledger row. If not, the unit is dropped and recorded. **A task whose MECH share is zero is not admissible.** A task where the dropped units gut the criterion (author judgement, reviewed at acceptance) is likewise rejected.

R4. Faithfulness bounds: the donecheck must test **no more and no less** than the surviving MECH units — no scope creep (assertions with no source unit are forbidden), no silent weakening (every non-covered unit must appear in the drop/weaken record). The per-task record lists `unit → assertion(s)` or `unit → dropped/weakened(reason)`.

## 2. Assertion catalog

Every assertion instantiates one of these forms (extend only by amendment):

- **T1 content-presence** — fixed-string or regex match in a named file (`grep -F`/`grep -E`), with count ≥ n where relevant.
- **T2 path-existence / path-absence** — file or directory exists / does not exist.
- **T3 command-exit** — a named command run at repo root exits 0 (e.g. the repo's own test suite, a self-check tool). Command and arguments are pinned in the task; PATH resolution is not relied on beyond the sealed environment.
- **T4 content-absence** — pattern count == 0 across a named file set (rename sweeps, "no occurrence remains"), with an explicit allowlist file when the source criterion has one.
- **T5 behavior probe** — run a bundled fixture through a repo script; assert exit code and/or output shape. Fixtures ship inside the task directory; the probe never mutates tracked files.
- **T6 structural** — mechanical shape checks: JSON/YAML parses, a table has row set R, generated block matches regenerator output (`--check` style idempotence).

Notes:
- T3 on a full test suite is allowed only when the source Done when itself invokes it; otherwise prefer the narrowest T3/T5 that covers the unit (keeps runtime bounded and failure attribution clean).
- **Needle calibration (r1, from batch-1 author review):** a T1/T4 needle pins the *unit*, not the historical fix's wording. Use the smallest distinctive fragment — paths, identifiers, numbers, or key phrases of a few words — never a full sentence of fix prose, unless the source Done when quotes exact wording. Rationale: the validity gate (§5) only proves fix-passes/pre-fails; it cannot prove that honest alternative solutions pass. Full-sentence pins collapse the task into transcription from the visible donecheck and reject correct paraphrases.
- **Criterion-constitutive identifiers (r1):** when the source Done when itself names a target (a URL, a rename target, an exact prefix) that is not derivable from the pre-fix tree, that identifier is spec, not provenance — it stays in task.md verbatim, with an anonymization-sweep exemption recorded in units.md. Deleting it makes the task unsolvable in-replica, which no arm can detect and the validity gate cannot catch.
- Every assertion emits one line `CHECK <id> PASS|FAIL <short reason>` on stdout; donecheck exits 0 iff all assertions pass (**fail-closed**: any error path, missing file, tool crash, or timeout is FAIL, never skip).

## 3. Determinism and sealing

R5. donecheck runs offline: no network, no `gh`, no web access (the run environment blocks these mechanically per design §4; donecheck must also not attempt them). Only the working tree, the task's bundled fixtures, and the standard toolchain (bash ≥ 3.2, git, coreutils, python3 where the repo suite needs it) may be touched.

R6. No wall-clock, randomness, or environment dependence: no `$RANDOM`, no date-based logic, `LC_ALL=C` pinned in the script header, fixed `--` argument hygiene, quoted expansions. A per-assertion timeout (default 120 s, per-task override recorded) is enforced by the runner; timeout = FAIL.

R7. donecheck reads the repo as-is; it never fixes, formats, or mutates the tree. Read-only enforcement is part of validity testing (a run must leave `git status --porcelain` unchanged).

## 4. Anonymization (task.md)

R8. task.md is rewritten from the issue body with: issue/PR numbers removed; repo and org names replaced by neutral stand-ins consistent across the bundle; person/agent names, dates, and internal tracker references removed; links stripped or replaced by in-bundle paths. The mapping is recorded per task and published with the ledger after runs complete (design §4: full-ledger publication; pre-run the mapping is part of the sealed manifest).

R9. The replica repo is a **history-zero copy**: the pre_fix tree is exported (`git archive` semantics) into a fresh `git init` with a single synthetic commit, so no commit messages, authors, or fix history can leak the answer. Leak markers (canary strings unique per task) are planted per design §3 `contaminated` handling.

R10. task.md carries, for every arm identically: the anonymized goal, the Done when (anonymized, unit-numbered), the allowed-tools table, the attempt/timeout budget, and — per the frozen visibility ruling (§2 note) — the visible, executable `donecheck.sh`. Arms differ **only** in the runner enforcing the gate (W) versus instructions (B+ self-verification wording / B minimal wording). The exact three instruction texts are frozen in the manifest.

## 5. Validity tests (admission gate)

R11. Each task must pass, before admission:
- pre_fix tree: `donecheck.sh` **FAIL × 5 consecutive runs**
- fix tree (anonymized the same way): `donecheck.sh` **PASS × 5 consecutive runs**
- both under the sealed environment; any flake → task revised or rejected (no third state).
- read-only check (R7) on every run.

R12. Runs are executed by `tools/validate-task.sh` (bundle tooling), which writes a machine log (task id, tree, run index, exit, duration) into the manifest inputs.

**Replica solvability (r2, from batch-1 non-author acceptance):** admission additionally requires that the surviving MECH criterion be **satisfiable from the replica tree and bundled fixtures alone** — an honest solver with no access to out-of-replica sources must be able to make the donecheck pass. Assertions that pin content not derivable in-replica (e.g. a full-blob hash of a file whose canonical source lives outside the replica, or content only reconstructible from the historical fix) are inadmissible even though they pass the R11 gate — the gate only runs the historical fix and cannot detect this class. Equality pins against a generator or canonical source are admissible only when that source ships in-replica (T6's regenerator premise). Found by the acceptance seat in batch 1 (t03 a01: blob-hash pin of an out-of-repo template copy).

**r3 (from batch-2 delta acceptance):**
1. *Disjunction preservation (R4 extension)*: when the source criterion states an explicit disjunction ("X or Y"), the donecheck must accept both branches, or the collapse to one branch must be recorded as a weakening in units.md. The R11 gate is structurally blind to this class — the historical fix always took one branch, so the gate always agrees.
2. *Derivability covers paths, not just content*: a pinned target path or filename must be derivable from the pre-fix tree, named by the criterion, or given in task.md; otherwise pin the discoverable pointer (e.g. the documented reference line) and resolve the target from it.
3. *Probe isolation*: T3/T5 probes must isolate mutable process environment (`HOME`, `TMPDIR` at minimum) so concurrent or dirty-workstation runs cannot flake them.
4. *Metadata–ledger binding*: a commit that changes a task's meta.json (SHAs, timeout) must re-verify that task's units.md narrative in the same commit (the I-2/N1 failure shape: corrected pair, stale ledger prose).
5. *Standard units.md footer*: every task ledger ends with the anonymization mapping, the longest needle with its derivability basis, and the timeout rationale (t11's footer is the template). Review findings anchor there instead of being re-derived per round.

**r4 (from batch-3 / round-3 acceptance, pre-sealing):**
1. *Retroactivity*: a commit that adopts a new rule must list the already-admitted tasks the rule applies to and either backfill them in the same revision cycle or record why each is exempt. (r3-3/r3-5 were initially applied only where their findings arose — P2/P3.)
2. *Discriminative power (r2 companion)*: when the replica ships a functional test for a criterion unit (e.g. a bundled test suite for a tool the unit requires), the donecheck must use it — or record why bare existence/structure checks suffice. Bare `[ -f ]` on a unit whose functional probe is sitting in-replica is under-testing (P1).
3. *Span-pair declaration*: when pre_fix is not the fix's first parent (a multi-commit span), units.md must state which assertions are expected to hold on BOTH legs (constant-true on pre), so pre-FAIL breadth is not misread across tasks (P10).
4. *Class labels follow the mapping*: a unit whose asserted core is fully mechanized is MECH (possibly weakened-MECH with the loss recorded), not HUMAN; HUMAN is reserved for units whose surviving assertion does not decide the claim (P4's inflation shape).

## 6. Authorship and acceptance

R13. Author of record for every task: Alpha. Codex (GPT-5.6 Sol) may draft under these rules; the author reviews every line before admission.

R14. Non-author acceptance (design §4): each task is inspected by the acceptance seat (Caty, once wired; fallback: another non-author family member) against this document — unit decomposition, class labels, faithfulness bounds, anonymization. 10–20% of tasks get a full **second-author independent re-derivation**; disagreement rate is reported in the results.

R15. Amendments to these rules after manifest sealing follow design §6 amendment procedure (public, versioned, pre-analysis).
