# EV-005 pilot-task authoring report

Status: **4 of 5 tasks admitted; p01 official validation is IN PROGRESS.** This
is an honest intermediate report for the author to finalize after the current
p01 run and its negative probe complete. The pilot remains outside the 30-task
analysis set and uses the same translation rules and admission machinery.

## Task inventory and admission evidence

| Task | Source | Pre-fix → fix | Size | Donecheck timeout | Validity verdict and log | Negative probe | Constant-true assertions |
| --- | --- | --- | --- | ---: | --- | --- | ---: |
| p01 | `caty-ai/caty-agent-harness#56` | `7c1b7158d4dae0d2fbaf87b55222d6201d55062e` → `70843945b1cd5bbb36f5281a8e8e0da98c4d00e3` | size-XL; 16 files, +1258/−412 | 1800 s | **IN PROGRESS**. The current [p01 log](../tools/validate-logs/p01.log) postdates the donecheck but contains only the partial first pre run (`a01`–`a12` FAIL); it has no `RUN` line, fix leg, or verdict. No pass is claimed. | route a specified; execution pending | pending the completed pre leg |
| p02 | `caty-ai/caty-agent-harness#27` | `948d1a9e93f0c1fb7ad9c989f27e516bb5e0b129` → `18e897513e06e9f2e93e08920f0cdd8314472c70` | size-XL; 25 files, +1826/−299 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p02.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p02.log) | 0 |
| p03 | `caty-ai/caty-agent-harness#61` | `ec846cdae1f5af4ddebac12449b120aa0e383402` → `441607653dc1e59a1baac3f2bf9fbffaca0535c4` | 7 files, +452/−107 | 180 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p03.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p03.log) | 2 (`a07`, `a08`) |
| p04 | `caty-ai/caty-agent-harness#68` | `70843945b1cd5bbb36f5281a8e8e0da98c4d00e3` → `e07eac1dad578b5bc22b238a65c5c61d31f957b0` | 3 files, +340/−6 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p04.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p04.log) | 0 |
| p05 | `caty-ai/context-kit#4` | `92fc39c86422ddfe3654e4f4f38e6f6ff1fd0b39` → `5c8b54af9386125695d0e87ab14c5d2c0fdf5973` | 6 files, +805/−0 | 120 s | **PASS**: pre FAIL×5, fix PASS×5; [validity log](../tools/validate-logs/p05.log) | route a, `EXPECTED_FAIL_CONFIRMED`; [log](../tools/validate-logs/negprobe/p05.log) | 0 |

All completed validity and negative-probe logs postdate their corresponding
donechecks. The completed logs contain no `DIRTY-TREE` finding. The p03
constant-true checks are intentional invariance guards for the unchanged
`verify-job` and `wrapper-conformance` integrations; every delta-bearing p03
assertion fails on all five pre runs. No completed task has an unexplained
constant-true assertion.

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
| `caty-ai/caty-agent-harness` | **Selected #61 as p03**: the merge parent/fix pair isolates the position-free verdict parser, has a preserved implementation brief, and supplies focused CLI/example tests plus unchanged-integration guards. **Selected #68 as p04**: the merge parent/fix pair isolates configurable verifier API-base behavior, with offline opener-stub coverage and a bounded focused suite. These give parser and endpoint-configuration mechanisms rather than a third intake task. Release-binding work such as #54 was skipped because live release/tag and CI provenance would add external or platform-facing criteria to an offline replica. |
| `caty-ai/family-os` | Issue-reference and content searches were compared with the ledger pool. The bounded mechanical candidates found were already represented by the ledger's family-os issues; the remaining nearby work was HUMAN-dominant, approval-bearing, or epic-shaped. No outside-ledger pair offered a cleaner medium offline gate than the selected three. |
| `caty-ai/family-memory-architecture` | Later atomic-write, scheduler-state, storage, and rollout commits were inspected as alternates. They were skipped for this pilot because their complete landed behavior spans review/migration commits and operational shared-state boundaries, making pair attribution and a narrow 120-second replica gate less clean. The pilot did not need another broad state/operations task after the three stronger pairs were found. |
| `caty-ai/context-kit` | **Selected #4 as p05**: the direct parent and issue-referencing commit form a single clean pair, the behavior is exercised by a dedicated local regression suite, and the task adds hook/input-validation diversity. Issues #2 and #3 were smaller wrapper/persistence increments near the floor; #5–#7 overlap the broader context-kit#1 milestone already present in the analysis set. |
| `caty-ai/self-growth-loop` | Later issue-referencing history was surveyed, including test-clock and public-readiness work. It was retained as an alternate pool but skipped after three pairs were selected: much of the history is documentation/operations or multi-commit review work, while the mechanically attractive test-clock work would add test-maintenance behavior rather than the parser, endpoint, and hook diversity chosen here. |

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
  find a stable execution shape; the current official run uses the final
  stable six-way shared execution and is still in progress. The partial log is
  preserved as evidence, not absorbed as a pass or failure. Final admission
  requires pre FAIL×5, fix PASS×5, a completed route-a negative probe, and
  constant-true accounting.

## Model routing and review availability

| Role | Requested model / effort | Actual model / effort | Result |
| --- | --- | --- | --- |
| Draft task executors | `gpt-5.4` / high | `gpt-5.4` / high | Parallel bounded drafts for p01–p05 |
| Final integration and this report | `gpt-5.6-sol` / high | `gpt-5.6-sol` / high | Cross-task editorial integration, structural checks, and evidence synthesis |

External review seats were unavailable in this authoring window: Opus was not
logged in, while Kimi and GLM returned connection errors. No external verdict
is counted or implied. Alpha remains author of record and must finalize this
report after p01 evidence completes.

## Current handoff

The batch is **not yet five-task complete**. p02–p05 satisfy the recorded
validity, negative-probe, footer, isolation, and constant-true requirements.
p01 remains the sole open item; update its table row and the batch status only
from the finished official logs, without rewriting or concealing the current
in-progress evidence.
