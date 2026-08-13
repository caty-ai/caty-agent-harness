# Family updater rollout

The updater follows released tags only after verifying the exact tag object it
will use. SSH tag signatures are the security control. The stable-ring soak is
only rollout pacing: a signer can backdate `GIT_COMMITTER_DATE`, so tag age must
never be treated as proof of authenticity.

## First installation: mechanical bootstrap gate

Do not execute the clone's cron wrapper or recurring updater before bootstrap.
The owner must deliver two values out of band:

1. an SSH `allowed_signers` file, normally
   `$HOME/.claude/state/updater-allowed-signers`; and
2. the exact initial release name, such as `v1.3.0`.

The signer file must be non-empty, readable, and outside the clone. Never copy
it from the repository, auto-create it, or fall back to Git configuration. Run
an out-of-band copy of the bootstrap command (or compare its bytes with a trusted
copy before execution). The trusted directory must contain both
`updater-bootstrap` and its sibling `lib-updater-verify.sh`:

```sh
/trusted/updater-bootstrap \
  --repo-dir "$HOME/claude-workspace/caty-agent-harness" \
  --allowed-signers "$HOME/.claude/state/updater-allowed-signers" \
  --initial-tag v1.3.0 \
  --cron-wrapper-dest "$HOME/.local/bin/caty-family-updater-cron"
```

Bootstrap verifies exactly the owner-named tag; it does not select a newer tag.
It captures the tag-object and commit OIDs once, verifies the captured tag object
with the forced out-of-repo signer pin, binds the `tag` header exactly to the
owner-named ref, checks out the captured commit OID, asserts `HEAD`, records the
per-repository floor, and only then installs the cron wrapper. A rebound tag is
refused.

After bootstrap, configure the copied wrapper. Example:

```cron
12 * * * * REPO_DIR="$HOME/claude-workspace/caty-agent-harness" WORKSPACE="$HOME/claude-workspace" AGENT="claude-code" RING="stable" SOAK_HOURS="24" FMA_SCRIPTS_DIR="$HOME/claude-workspace/family-memory-architecture/scripts" CATY_UPDATER_ALLOWED_SIGNERS="$HOME/.claude/state/updater-allowed-signers" "$HOME/.local/bin/caty-family-updater-cron" >>"$HOME/claude-workspace/updater-cron.log" 2>&1
```

Use `RING=canary SOAK_HOURS=0` only for the assigned canary. Give every clone a
read-only deploy credential; the updater never pushes.

## Persistent state

Each physical clone path has an independent monotonic pin. The readable clone
basename is suffixed with a stable short hash of its resolved physical path, so
two clones named alike do not share state:

```text
$HOME/.claude/state/updater-pin/<repo-name>-<path-hash>.json
```

It records the highest successfully installed version and its full commit OID.
An existing machine without a pin takes the version name only from the most
recent `ok` entry for this repository in the machine-written
`$HOME/.claude/state/installed-versions.log`, and accepts it only when that name
still points at pre-fetch `HEAD`. The floor commit is always that recorded
pre-fetch OID. Without consistent ledger evidence the updater fails closed and
names `scripts/updater-bootstrap`. Unreadable or malformed pins also fail
closed. A `--dry-run` computes this floor in memory but writes no pin, dedupe or
ledger state and sends no heartbeat or hot-inbox report.

Moved names, report dedupe, and exact install-failure identities are recorded in
the append-only state log at:

```text
$HOME/.claude/state/updater-ineligible/<repo-name>-<path-hash>.log
```

A moved name remains excluded. A cryptographic or floor verification failure is
retried on later ticks so signer rotation or another out-of-band repair can
recover it; its report is deduplicated until that name passes verification.
Structurally valid remote records with non-semver tag names are skipped with a
local stdout note. They never become candidates and produce no report or
persistent record. Skipped names do not enter duplicate detection, so a repeated
non-semver record is skipped again. Duplicate strict-semver names and unparsable
remote records still stop the run and report once per offending name. An
`install.sh --check` failure excludes only the exact tag-name/commit-OID pair
after rollback, preventing hourly checkout and report churn.

## Release signing and key rotation

Every update target must be a strict semver annotated tag signed by a pinned SSH
key. Legacy lightweight or unsigned releases are rollback identities only and
can never be selected as update targets.

The gate binds a verified tag to its exact name and a pinned signing key; it
does **not** bind that tag to a repository. Each repository therefore must have
its own signing key and its own `allowed_signers` file. Sharing a key across
repositories lets a release signed for one repository pass the gate and be
installed by another repository.

A tag name rejected as moved is permanently excluded on that machine. Publish
the corrected release under a higher version; never re-push it under the same
name.

Rotate signing keys with overlap:

1. distribute the new public key in `allowed_signers` while retaining the old;
2. verify adoption on every updater host;
3. sign a release with the new key and verify fleet acceptance; then
4. retire the old key from every host.

Never switch the release signer before the overlap has been verified.

## Fetch behavior and atomicity

Branches are fetched with tags suppressed. Tags are enumerated with
`git ls-remote --refs --tags`, compared by direct ref OID, and only absent names
are fetched in one `git fetch --atomic --no-tags` call. A moved name is never
forced over the local ref. `--atomic` guarantees atomic **ref updates**: a failed
batch installs no new tag refs. It does not roll back downloaded objects;
unreachable objects are ordinary `git gc` housekeeping and confer no trust.

## Residual bootstrap risks

A fresh clone has no prior direct OID, so it cannot detect that an existing tag
name was moved before the clone was created. The owner-named bootstrap removes
automatic selection, while signature verification prevents substituted content
and exact header name binding prevents an old genuine tag object being rebound
under a new version name.

If an attacker controls both the remote and the owner channel that supplies the
initial tag name, the owner can still be induced to name an older genuine signed
release. That owner-channel compromise is out of scope for this mechanism and
must be addressed by protecting the out-of-band channel.

## Operational checks

- Git 2.34 or newer with SSH signature verification is mandatory.
- A missing, empty, unreadable, or repository-local `allowed_signers` file stops
  the run.
- Successful real updates and failures append to
  `~/.claude/state/installed-versions.log`; no-op current runs do not.
- A failed install check rolls back to the exact pre-update full commit OID,
  asserts that identity, and only then runs the rollback install check.
