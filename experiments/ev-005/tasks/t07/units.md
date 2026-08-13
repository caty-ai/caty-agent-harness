# t07 faithfulness record

Units: 25 total; covered 25/25
MECH: 21
HUMAN: 0
MOOT: 4

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | MECH | `DESIGN.md` title uses the public product name. | `a01` and `a02` (T1 content-presence + T4 content-absence in `DESIGN.md`) |
| U2 | MECH | `DESIGN-task-runner.md` companion note uses the public product name. | `a03` and `a04` (T1 + T4 in `DESIGN-task-runner.md`) |
| U3 | MECH | `DESIGN-task-runner.md` loop description uses the public product name. | `a05` and `a06` (T1 + T4 in `DESIGN-task-runner.md`) |
| U4 | MECH | `DESIGN-task-runner.md` verification-promotion sentence uses the public product name. | `a07` and `a08` (T1 + T4 in `DESIGN-task-runner.md`) |
| U5 | MECH | `SYNTHESIS.md` title uses the public product name. | `a09` and `a10` (T1 + T4 in `SYNTHESIS.md`) |
| U6 | MECH | `SYNTHESIS.md` namespace note uses the public product name. | `a11` and `a12` (T1 + T4 in `SYNTHESIS.md`) |
| U7 | MECH | `SYNTHESIS-task-runner.md` verification-promotion sentence uses the public product name. | `a13` and `a14` (T1 + T4 in `SYNTHESIS-task-runner.md`) |
| U8 | MECH | `SYNTHESIS-task-runner.md` verify retry wording uses the public product name. | `a15` and `a16` (T1 + T4 in `SYNTHESIS-task-runner.md`) |
| U9 | MECH | `docs/governance-rules.md` rewrites the historical-source prose line as a neutral pre-publication private-tracker reference. | `a17` and `a18` (T1 + T4 in `docs/governance-rules.md`) |
| U10 | MECH | `docs/governance-rules.md` rewrites the synthesis-scope table row with the public product name. | `a19` and `a20` (T1 + T4 in `docs/governance-rules.md`) |
| U11 | MECH | `docs/governance-rules.md` rewrites the `v1.0 source` table row as a neutral pre-publication private-tracker reference. | `a21` and `a22` (T1 + T4 in `docs/governance-rules.md`) |
| U12 | MECH | `docs/governance-rules.md` rewrites the `Amendment issue` table row as a neutral pre-publication private-tracker reference. | `a23` and `a24` (T1 + T4 in `docs/governance-rules.md`) |
| U13 | MECH | `docs/updater-rollout.md` rewrites the source-of-truth line as a neutral pre-publication private-tracker reference. | `a25` and `a26` (T1 + T4 in `docs/updater-rollout.md`) |
| U14 | MECH | `docs/updater-rollout.md` rewrites the path-correction note as a neutral pre-publication private-tracker reference. | `a27` and `a28` (T1 + T4 in `docs/updater-rollout.md`) |
| U15 | MECH | `scripts/lib-wrapper-conformance.sh` uses the public temporary-stage prefix. | `a29` and `a30` (T1 + T4 in `scripts/lib-wrapper-conformance.sh`). Author revision r1 (applies to U15–U18): task.md now names the four target prefixes — they are criterion-constitutive (the source Done when names them verbatim; the exact tokens are not derivable from the pre-fix tree, only the naming stem is). Anonymization-sweep exemption recorded here. |
| U16 | MECH | `scripts/attest-wrapper` uses the public attest scratch-directory prefix. | `a31` and `a32` (T1 + T4 in `scripts/attest-wrapper`) |
| U17 | MECH | `scripts/attest-wrapper` uses the public attest stdout prefix. | `a33` and `a34` (T1 + T4 in `scripts/attest-wrapper`) |
| U18 | MECH | `scripts/attest-wrapper` uses the public attest stderr prefix. | `a35` and `a36` (T1 + T4 in `scripts/attest-wrapper`) |
| U19 | MECH | No case-insensitive `fable` occurrence remains outside lines that contain a frozen compatibility identifier or a nominative model mention. | `a37` (T4 content-absence over tracked files, with an inline allowlist for the three frozen marker strings, the frozen wrapper schema including its `/v0` fixture, `FABLE_*` contract variables, and the nominative model-name forms present in the source tree; the validator-injected `.ev005-donecheck.sh` is excluded because it is gate scaffolding rather than repository source). The assertion permits allowed occurrences to be removed and therefore does not require an exact repository-wide occurrence set. |
| U20 | MECH | The full repository test suite is green on the branch-equivalent tree. | `a38` (T3 command-exit: `make test`; task timeout raised to `1800 s` because the required fix-tree suite exceeded `120 s`, `300 s`, and `600 s` in history-zero replicas during admission.) |
| U21 | MECH | Repository lint is green on the branch-equivalent tree. | `a39` (T3 command-exit: `make lint`; task timeout raised to `1800 s` because validation pairs the required suite with lint and the fix-tree suite alone exceeded `120 s`, `300 s`, and `600 s` admission budgets.) |
| U22 | MOOT | The full repository test suite is green on the merged-mainline tree. | Dropped (MOOT: the offline replica has no live merged-mainline destination). |
| U23 | MOOT | Repository lint is green on the merged-mainline tree. | Dropped (MOOT: the offline replica has no live merged-mainline destination). |
| U24 | MOOT | A new tag is published after merge for this cleanup. | Dropped (MOOT: post-merge tag publication does not exist inside the offline replica). |
| U25 | MOOT | A release is published after merge for this cleanup. | Dropped (MOOT: post-merge release publication does not exist inside the offline replica). |
