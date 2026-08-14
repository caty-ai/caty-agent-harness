# t25 units ledger

Units: 4 total; covered 4/4
MECH: 3
HUMAN: 1
MOOT: 0

Anonymization mapping: the public source repository is “this repository.” The
public updater, trust-library, test, and rollout-document paths remain because
they are the criterion's implementation targets and are visible in the replica.
No issue, pull-request, owner identity, date, or historical tracker reference is
carried into `task.md`.

Interpretation: the source allowed signed tags, pinned commit hashes, or a
maintainer manifest. The fix chose SSH-signed annotated tags verified against
an out-of-repository `allowed_signers` file. The task states that selected
mechanism so an honest replica solver can satisfy the gate without historical
access.

| Unit | Class | Source unit (anonymized) | Mapping / disposition |
| --- | --- | --- | --- |
| U1 | HUMAN | An owner chooses one updater trust mechanism before implementation. | Weakened (HUMAN→MECH extraction) to the implemented, replica-observable decision by `a01` (T1: small semantic anchors in `docs/updater-rollout.md` require SSH signing, `allowed_signers`, and its outside-repository boundary). Lost: proving the identity or approval act of the owner. The selected mechanism is criterion-constitutive and is therefore stated in `task.md`. |
| U2 | MECH | Unverified candidates are refused before checkout or installer execution. | `a02` (T6 structural ordering: the updater calls captured-tag verification before captured-OID checkout and reaches `run_install_check` only afterward), `a03` (T3 command-exit of the focused updater regression module), `a04` (T5/T1-on-probe-output: an attacker-substituted unsigned release is refused), and `a05` (moved/lightweight tag behavior reaches no candidate install). |
| U3 | MECH | Verification failure is fail-closed with a clear message. | `a03` (focused T3 suite) and `a06` (T5 semantic regression-output fragments showing the missing signer pin is named). The assertion does not pin a historical diagnostic sentence. |
| U4 | MECH | Tests cover tampered-tag and substituted unsigned-tag scenarios. | `a03` executes `tests/family-updater.test.sh`; `a04` requires its unsigned-substitution refusal case and `a05` requires a moved or lightweight tag case whose output records no install. The source asks for focused regression coverage, so this targeted module is narrower than the repository suite. |

Needle and solvability audit: `SSH`, `allowed_signers`, `outside`, `unsigned`,
`moved tag`, `lightweight`, and `no install` are short criterion or behavioral
fragments. No full fix-prose sentence, test name, commit identity, or
out-of-replica content is pinned. Default timeout remains 120 seconds.
