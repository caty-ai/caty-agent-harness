# Family updater rollout

The updater accepts a release only after verifying the exact tag object and
proving that its captured commit is an ancestor of the configured release
branch. Per-repository SSH signing keys are the cryptographic boundary.
Release-branch reachability closes tag-object-only cross-repository replay; the
signer-file directive below prevents one trust file from being wired to the
wrong repository. The directive does not cryptographically bind a key or tag to
a repository.

Stable-ring soak is rollout pacing only. A signer can backdate
`GIT_COMMITTER_DATE`, so tag age is never proof of authenticity.

## First installation: mechanical bootstrap gate

Do not execute the clone's cron wrapper or recurring updater before bootstrap.
The owner must deliver two values out of band:

1. an absolute path to an SSH `allowed_signers` file, normally
   `$HOME/.claude/state/updater-allowed-signers`; and
2. the exact initial release name, such as `v1.3.0`.

The signer file must be non-empty, readable, outside the clone, and contain
exactly one repository directive followed by the pinned keys:

```text
# updater-repo: github.com/example/caty-agent-harness
release@example.invalid ssh-ed25519 AAAA...
```

The identity must equal the normalized effective fetch endpoint. Never copy the
file from the repository, auto-create it, or fall back to Git configuration.
The updater snapshots the validated file into private 0600 transient state;
directive parsing and every `verify-tag` call consume those same bytes.

Run an out-of-band copy of bootstrap, or compare its bytes with a trusted copy
before execution. The trusted directory must contain `updater-bootstrap` and
its sibling `lib-updater-verify.sh`:

```sh
CATY_UPDATER_RELEASE_BRANCH=main /trusted/updater-bootstrap \
  --repo-dir "$HOME/claude-workspace/caty-agent-harness" \
  --allowed-signers "$HOME/.claude/state/updater-allowed-signers" \
  --initial-tag v1.3.0 \
  --cron-wrapper-dest "$HOME/.local/bin/caty-family-updater-cron"
```

Bootstrap is online-only. It captures and validates the origin endpoint,
fetches all branches with tags suppressed and pruning enabled, then verifies
exactly the owner-named tag; it never selects a newer tag. It captures the tag
object and commit OIDs once, verifies the tag with the signer snapshot, binds
the `tag` header exactly to the owner-named ref, proves the commit is on the
release branch, checks out and asserts the captured commit, records the floor,
and only then installs the cron wrapper. Rebound and tag-only foreign releases
are refused. Offline and air-gapped bootstrap is unsupported.

Example recurring configuration:

```cron
12 * * * * REPO_DIR="$HOME/claude-workspace/caty-agent-harness" WORKSPACE="$HOME/claude-workspace" AGENT="claude-code" RING="stable" SOAK_HOURS="24" FMA_SCRIPTS_DIR="$HOME/claude-workspace/family-memory-architecture/scripts" CATY_UPDATER_ALLOWED_SIGNERS="$HOME/.claude/state/updater-allowed-signers" CATY_UPDATER_RELEASE_BRANCH="main" "$HOME/.local/bin/caty-family-updater-cron" >>"$HOME/claude-workspace/updater-cron.log" 2>&1
```

Use `RING=canary SOAK_HOURS=0` only for the assigned canary. Give every
clone a read-only deploy credential; the updater never pushes.

## Repository identity and transports

Accepted host forms are `[user@]host:org/repo[.git]`,
`ssh://[user@]host[:22]/org/repo[.git]`, and
`https://host[:443]/org/repo[.git]`. Full URL userinfo is removed before
comparison, and the entire host-form identity is lowercased. Only default
explicit ports are accepted. Trailing slashes and one trailing `.git` suffix
are removed repeatedly until stable.

Absolute filesystem paths, `file:///absolute/path`, and
`file://localhost/absolute/path` are accepted for tests and local development;
their identity is the resolved physical path. Production must use a host-form
endpoint.

IPv6 hosts, `git://`, non-default ports, relative paths, nested group paths such
as `host/group/subgroup/repo`, query or fragment suffixes, multi-valued origin
URLs, and `file://` URLs with a non-local host are refused. `insteadOf` rewrites are evaluated as the effective fetch endpoint;
mirror layouts that normalize to a different or four-component identity are
unsupported. Failure reasons never include the raw URL.

The effective origin URL is captured once during signer validation. Branch
fetches, `ls-remote`, candidate-tag fetches, and bootstrap fetches all consume
that captured endpoint, never the mutable remote name. Ref updates still target
`refs/remotes/origin/*` through explicit refspecs.

## Release ritual and reachability

Every release tag must point to a commit already on the configured release
branch (`CATY_UPDATER_RELEASE_BRANCH`, default `main`). The value must pass
`git check-ref-format --branch`. Protect that branch, and push it before or with
the tag. Pointing the variable at an unprotected branch restores the ordinary
branch-write bypass for that deployment.

Spell the branch name with exact case. The syntax check accepts `MaIn`, and ref
lookup goes through the filesystem, so a case-drifted value can resolve to the
intended branch on a case-insensitive macOS clone while refusing on Linux hosts
and in the git-2.34 container cell.

A `push --follow-tags` can land between the updater's branch fetch and tag
listing. The resulting one-tick refusal is expected and self-heals on the next
tick. Branches are fetched with `--no-tags --prune`; a deleted release branch
cannot keep vouching after the next fetch.

The existing production releases `v0.1.0` through `v0.3.0` are already on their
release branch; this was checked read-only before rollout.

Tags are enumerated with `git ls-remote --refs --tags`, compared by direct ref
OID, and only absent names are fetched in one `git fetch --atomic --no-tags`
call. A moved name is never forced over the local ref. `--atomic` guarantees
atomic ref updates, not object-download rollback; unreachable objects are
ordinary `git gc` housekeeping and confer no trust.

## Persistent state and retry behavior

Each physical clone path has an independent monotonic pin:

```text
$HOME/.claude/state/updater-pin/<repo-name>-<path-hash>.json
```

The pin stores the highest successfully installed version and full commit OID.
An existing machine without a pin takes a version name only from the most recent
machine-written `ok` ledger entry and accepts it only when the tag still points
at pre-fetch `HEAD`. Without consistent evidence the updater fails closed and
names `scripts/updater-bootstrap`. A `--dry-run` computes the floor in memory
but writes no pin, dedupe, or ledger state and sends no reports.

Moved names, report dedupe, and exact install-failure identities use:

```text
$HOME/.claude/state/updater-ineligible/<repo-name>-<path-hash>.log
```

A moved name remains excluded. Cryptographic, reachability, and floor failures
are retryable; each name produces one deduplicated verification-failure report
until it passes, at which point a clear record is appended. Reachability failure
is never classified as `moved-tag` or `install-failure`. A high foreign tag does
not abort candidate selection, so a legitimate lower sibling can install in the
same tick. An install check failure excludes only the exact tag/commit pair.

Non-semver names are skipped locally without reports or state. Duplicate strict
semver names and malformed remote records stop and report once. A failed install
rolls back to the exact pre-update OID, asserts it, and only then runs the
rollback install check.

## Signing keys and rotation

Every update target must be a strict-semver annotated tag signed by a pinned SSH
key. Lightweight and unsigned releases are rollback identities only. Each
repository must have a disjoint signing key and signer file. Sharing a key
destroys cryptographic separation; the repository directive only detects file
reuse and is not a substitute for key separation.

A moved tag name is permanently excluded on that host. Publish the correction
under a higher version; never force the old name.

Rotate keys with overlap:

1. add the new public key while retaining the old and preserving exactly one
   `# updater-repo: <identity>` directive;
2. verify adoption on every updater host;
3. sign a release with the new key and verify fleet acceptance; then
4. retire the old key from every host.

## Migration preflight and recovery

Before enabling this release:

1. Compare the public-key material in every family repository's signer files
   pairwise. For each pair, extract key type and base64 material, then require an
   empty intersection. Any shared key blocks rollout until one repository is
   rotated:

   ```sh
   awk '!/^#/ && NF >= 3 {print $2, $3}' "$repo_a_signers" | LC_ALL=C sort -u >"$secure_tmp/repo-a.keys"
   awk '!/^#/ && NF >= 3 {print $2, $3}' "$repo_b_signers" | LC_ALL=C sort -u >"$secure_tmp/repo-b.keys"
   comm -12 "$secure_tmp/repo-a.keys" "$secure_tmp/repo-b.keys" >"$secure_tmp/shared.keys"
   test ! -s "$secure_tmp/shared.keys"
   ```

2. On every host, verify the current pin/floor tag and `HEAD`, fetch the release
   branch, and prove the pinned commit is reachable:

   ```sh
   git -C "$repo" fetch --no-tags origin \
     "+refs/heads/$CATY_UPDATER_RELEASE_BRANCH:refs/remotes/origin/$CATY_UPDATER_RELEASE_BRANCH"
   git -C "$repo" -c gpg.format=ssh \
     -c gpg.ssh.allowedSignersFile="$signers" verify-tag "$pinned_tag"
   git -C "$repo" merge-base --is-ancestor "$pinned_commit" \
     "refs/remotes/origin/$CATY_UPDATER_RELEASE_BRANCH"
   test "$(git -C "$repo" rev-parse HEAD)" = "$pinned_commit"
   ```

3. Refuse production rollout if the effective origin is a filesystem path or
   `file://` URL. Production transports must use a supported host form:

   ```sh
   effective_origin=$(git -C "$repo" remote get-url origin)
   case "$effective_origin" in
     /*|file://*) printf 'production origin must use a host form\n' >&2; exit 1 ;;
   esac
   ```

The upgraded updater refuses until the directive exists and releases are
branch-backed, so migrate signer files before enabling it. If a host's pin or
floor is foreign or suspect, quarantine it; never lower or hand-edit the floor.
Under incident procedure, remove the affected clone and its per-clone updater
state, create a clean clone, and run trusted bootstrap with an owner-confirmed
release name. Publish the repair release before cloning: bootstrap fetches
branches with tags suppressed, so the owner-named tag must already be present
in the clean clone. Name an annotated, signed tag; `v0.1.0` is lightweight and
verification refuses it.

```sh
mkdir -p "$quarantine"
mv "$repo" "$quarantine/suspect-clone"
mv "$pin_path" "$quarantine/suspect-pin.json"
test ! -e "$ineligible_path" || mv "$ineligible_path" "$quarantine/suspect-ineligible.log"
git clone "$trusted_origin" "$clean_clone"
/trusted/updater-bootstrap \
  --repo-dir "$clean_clone" \
  --allowed-signers "$signers" \
  --initial-tag "$owner_confirmed_tag" \
  --cron-wrapper-dest "$HOME/.local/bin/caty-family-updater-cron"
```

Shallow clones, no-branch or release-only origins, offline bootstrap,
unprotected release branches, and unsupported endpoint forms are not valid
deployments.

## Residual risks

A fresh clone has no prior direct OID and cannot detect a tag name moved before
the clone existed. Owner-named bootstrap removes automatic selection; signature
verification prevents substituted content; exact header binding prevents a
genuine tag object being rebound under a new version; release reachability
prevents tag-object-only replay.

If an attacker controls both the remote and the owner channel supplying the
initial name, the owner can still be induced to name an older genuine release.
Protect the out-of-band channel.

An attacker with ordinary write authority to both the configured release branch
and tags can place a foreign signed commit on that branch before tagging it; a
full remote compromise can do the same. Reachability does not defend against
either case. Branch protection, disjoint keys, and the migration preflight are
required.

## Operational checks

- Git 2.34 or newer with SSH signature verification is mandatory.
- Relative, missing, empty, unreadable, repository-local, unbound, multiply
  bound, CRLF-tainted, and mismatched signer files stop the run.
- `family-updater: repository binding verified: <identity>` is emitted once per
  successfully bound run.
- Successful installs and failures append to
  `~/.claude/state/installed-versions.log`; no-op current runs do not.
