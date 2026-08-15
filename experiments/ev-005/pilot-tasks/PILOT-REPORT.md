# EV-005 pilot-task authoring report

Status: **5 of 5 tasks admitted.** Every task has pre FAIL×5, fix PASS×5,
a confirmed negative-validity probe, and a constant-true declaration from the
official pre leg. The pilot remains outside the 30-task analysis set and uses
the same translation rules and admission machinery.

## Task inventory and admission evidence

| Task | Source | Pre-fix → fix | Size | Donecheck timeout | Validity verdict and log | Negative probe | Constant-true assertions |
| --- | --- | --- | --- | ---: | --- | --- | ---: |
| p01 | `caty-ai/caty-agent-harness#56` | `7c1b7158d4dae0d2fbaf87b55222d6201d55062e` → `70843945b1cd5bbb36f5281a8e8e0da98c4d00e3` | size-XL; 16 files, +1258/−412 | 1800 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p01.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p01.log) | 1 (`a13`) |
| p02 | `caty-ai/caty-agent-harness#27` | `948d1a9e93f0c1fb7ad9c989f27e516bb5e0b129` → `18e897513e06e9f2e93e08920f0cdd8314472c70` | size-XL; 25 files, +1826/−299 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p02.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p02.log) | 0 |
| p03 | `caty-ai/caty-agent-harness#61` | `ec846cdae1f5af4ddebac12449b120aa0e383402` → `441607653dc1e59a1baac3f2bf9fbffaca0535c4` | 7 files, +452/−107 | 180 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p03.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p03.log) | 2 (`a07`, `a08`) |
| p04 | `caty-ai/caty-agent-harness#68` | `70843945b1cd5bbb36f5281a8e8e0da98c4d00e3` → `e07eac1dad578b5bc22b238a65c5c61d31f957b0` | 3 files, +340/−6 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p04.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p04.log) | 0 |
| p05 | `caty-ai/context-kit#4` | `92fc39c86422ddfe3654e4f4f38e6f6ff1fd0b39` → `5c8b54af9386125695d0e87ab14c5d2c0fdf5973` | 6 files, +805/−0 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p05.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p05.log) | 0 |

All validity and negative-probe logs postdate their corresponding donechecks,
and none contains a `DIRTY-TREE` finding. The p01 `a13` constant-true check is
the full-suite invariance guard. The p03 `a07` and `a08` constant-true checks
guard the unchanged `verify-job` and `wrapper-conformance` integrations. Every
delta-bearing assertion fails on all five pre runs; no task has an unexplained
constant-true assertion.

The p01 pre runs exited 1 in 549, 554, 561, 553, and 556 seconds. Its fix runs
exited 0 in 653, 640, 653, 655, and 633 seconds. The official log ends with
`VERDICT p01 PASS`.

## Candidate search trail for p03–p05

The search applied the I-3 method to all five registered source repositories:
search issue-referencing commit subjects, use `git log -S` to locate the first
and last relevant content states, inspect the candidate diff and criterion,
then require the R11 pre/fix gate as the mechanical backstop. The selected issue
numbers do not occur in `eligibility-ledger.md`: harness issues 61 and 68 are
outside its harness pool, and context-kit issue 4 is distinct from its sole
ledger candidate, issue 1.

### Repository survey and disposition

| Repository surveyed | Search result and disposition |
| --- | --- |
| `caty-ai/caty-agent-harness` | **Selected #61 as p03 (medium, strong)**: the merge parent/fix pair isolates the position-free verdict parser, has a preserved implementation brief, and supplies focused CLI/example tests plus unchanged-integration guards. **Selected #68 as p04 (medium, strong)**: the merge parent/fix pair isolates configurable verifier API-base behavior, with offline opener-stub coverage and a bounded focused suite. |
| `caty-ai/family-os` | **Skipped #39** because its documentation/PR provenance left the exact landed pair ambiguous. **Skipped #52** because it was small and did not serve the requested medium difficulty band. |
| `caty-ai/family-memory-architecture` | **Skipped #19** because its 15-file, +1654-line delta is XL rather than medium; p01 and p02 already supply the pilot's intentional XL heavy tail. |
| `caty-ai/context-kit` | **Selected #4 as p05 (medium+, strong)**: the direct parent and issue-referencing commit form a clean pair, the behavior is exercised by a dedicated local regression suite, and the task adds hook/input-validation diversity. **Skipped #7 and #9** because their landed changes were large rather than medium. |
| `caty-ai/self-growth-loop` | **Skipped #3** because it was small and therefore did not satisfy the preferred medium difficulty contribution. |

### Pair provenance tier

- **p01/p02:** the ledger's surveyed-pair tier: previously recorded,
  GitHub-API-verified merge/fix and parent linkage. They are the two verified
  `size-risk` rows excluded from the analysis set and intentionally reused for
  the pilot's heavy tail.
- **p03/p04:** I-3 local-archaeology tier: issue-referencing merge/side-branch
  subjects, recovered local implementation briefs, and content inspection of
  the parent/fix deltas. Their R11 logs are the mechanical pair backstop.
- **p05:** I-3 local-archaeology tier: the issue-referencing linear commit is
  directly preceded by the selected pre tree; content inspection and R11
  validation confirm the complete hook feature lands at the fix SHA.

This is the same two-tier limitation language used by the ledger: local
issue-subject/content provenance is weaker than API linkage on its own, so it is
published rather than silently treated as equivalent; completed R11 validity
is the mechanical backstop.

## Failure and retry history

- **p02:** an initial documentation assertion pinned an over-tight
  `deadman-probe` needle. The needle was removed/calibrated to the actual intake
  and marker contract, then validity and the negative probe completed green.
- **p03:** a 120-second validation attempt timed out under machine contention.
  The task was not weakened; the whole-script timeout was raised from 120 to
  180 seconds and recorded in metadata/task/units. The final five fix runs took
  92–98 seconds and passed.
- **p05:** `a08` was strengthened before admission to execute the focused
  regression suite together with shell syntax, Python AST, and JSON parsing,
  rather than accepting only surface structure. The strengthened gate passed
  five fix runs and its negative probe still failed as intended.
- **p01:** full-suite execution is the intended heavy-tail measurement and has
  not been diluted. Earlier suite-parallelization experiments were used to
  find a stable execution shape; the official validation used the final stable
  six-way shared execution. It completed pre FAIL×5 and fix PASS×5, and the
  route-a token-stub probe confirmed its six-assertion expected-FAIL set in
  629 seconds; the edited tree returned nonzero with all thirteen assertions
  failing.

## Model routing and review availability

| Role | Requested model / effort | Actual model / effort | Result |
| --- | --- | --- | --- |
| Draft task executors | `gpt-5.4` / high | `gpt-5.4` / high | Parallel bounded drafts for p01–p05 |
| Final integration and this report | `gpt-5.6-sol` / high | `gpt-5.6-sol` / high | Cross-task editorial integration, structural checks, and evidence synthesis |

External review seats were unavailable in this authoring window: Opus was not
logged in, while Kimi and GLM returned connection errors. No external verdict
is counted or implied. Alpha remains author of record.

## Final authoring status

The batch is **five-task complete**. All five task directories satisfy the
recorded validity, negative-probe, footer, isolation, and constant-true
requirements. The two XL tasks remain intact rather than weakening their gates
for runtime, and p03–p05 contribute the requested outside-ledger medium-band
archaeology pairs.

## Correction record — commit scope of `25c9be8` (author, 2026-08-16)

The r5 commit was staged with a directory-scoped `git add` while this pilot batch was still
being written, so `25c9be8` contains the in-flight pilot files (and one `.pyc`) beyond its
stated scope. No history was rewritten: the pilot batch is reviewed on its own merits here and
the build artifact is removed in this commit, with `__pycache__/` ignored under the pack. The
r5 substance itself is unaffected — its only non-pilot files were `arm-instructions.md` and
`analysis-plan.md`. Recorded so the lane ledger matches reality (L1-8).
