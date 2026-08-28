# AGENTS.md — Caty Agent Harness
<!-- repo-state:begin (generated; do not edit) -->
<p align="center"><sub>generation: <code>5185597</code> (2026-08-27T18:49:55Z) · verify: <a href="https://api.github.com/repos/caty-ai/caty-agent-harness/commits/main">API HEAD</a> · <a href="./status.json">status.json</a></sub></p>
<!-- repo-state:end -->

Caty Agent Harness adds a file-based work discipline — a handover notebook, completion checks with evidence, and honest-stop rules — to the workspace an AI agent operates in. It is plain shell and plain files, installed into someone else's workspace.

**Are you here to install it?** Then this is the wrong page — read [docs/agent-guide.md](docs/agent-guide.md) instead. This file is for agents **contributing to this repository**.

This file is a **map**, not an encyclopedia. It routes; the documents it points at are authoritative. Where this file and a linked document disagree, the linked document wins — and the disagreement is a bug in this file.

---

## 0. First 30 seconds

| You need | Where |
| --- | --- |
| What this project is, for humans | [README.md](README.md) |
| What is actually enforced, and where | [docs/engineering.md](docs/engineering.md) |
| The contribution contract you are bound by | [CONTRIBUTING.md](CONTRIBUTING.md) |
| How to verify your change | Section 2 below |
| Found a vulnerability? | [SECURITY.md](SECURITY.md) — report privately, **do not** open a public issue with sensitive details |
| What happened before | GitHub issues and closed PRs — this repository keeps no separate progress file |

---

## 1. The map

| You want to know | Read |
| --- | --- |
| Design intent and the reasoning behind it | [docs/design/DESIGN.md](docs/design/DESIGN.md), [docs/design/SYNTHESIS.md](docs/design/SYNTHESIS.md) |
| Task runner design | [docs/design/DESIGN-task-runner.md](docs/design/DESIGN-task-runner.md) |
| Rules binding the claude-code, hermes, and openclaw adapters | [adapters/CONTRACT.md](adapters/CONTRACT.md) — normative for those three |
| How plugins may integrate | [docs/plugin-convention.md](docs/plugin-convention.md) |
| Exact command flags and contract details | [docs/reference.md](docs/reference.md) |
| CLI output prefixes and exit codes | [docs/cli-conventions.md](docs/cli-conventions.md) |
| Benchmark method and results | [docs/benchmark.md](docs/benchmark.md) |
| Family adoption governance (R1–R14) | [docs/governance-rules.md](docs/governance-rules.md) — maintainer context: how this family adopts external tools. Not the contribution workflow. **Editing that file is not an ordinary docs change**: its own amendment procedure requires cross-model review, and a Sho gate for its gated sections. |

<!-- claim: contract-scope claude-code hermes openclaw -->

Directories:

- `adapters/` — one directory per runtime: claude-code, codex, hermes, kimi, openclaw. `CONTRACT.md` is normative for claude-code, hermes, and openclaw; the codex and kimi adapters are bootstrap plus Stop hooks and are not bound by it.
- `scripts/` — the shell entry points that do the real work.
- `templates/` — files the installer drops into a user's workspace (`STATE.md`, briefs, rubrics).
- `skills/` — holds one repository-side reference template, `_staging/SKILL.tmpl.md`. Not a library this repository ships, and not copied into workspaces: `scripts/loop-init` creates an empty `skills/_staging/` there.
- `tests/` — one `*.test.sh` suite per concern.
- `install.sh` — the installer. Targets bash 3.2+.

---

## 2. Verification (nothing counts as done without this)

```sh
make test    # runs every tests/*.test.sh suite, reports all failing suites
make lint    # syntax-checks every tracked shell script, rejects bash 4.2+ ANSI-C Unicode escapes
```

<!-- claim: make-target test -->
<!-- claim: make-target lint -->

- Expected: `Suite Summary: <n> PASS, 0 FAIL`. `make lint` refuses a vacuous green — zero files checked is a failure.
- Prerequisites are listed in [CONTRIBUTING.md](CONTRIBUTING.md) — bash 3.2+, `make`, git 2.34+, `ssh-keygen -Y` (OpenSSH 8.2+), python3, and standard Unix tools.
- If you edit the Makefile `test` recipe, resync `.github/ci/make-test-recipe.pin` in the same change. That pin is checked after merge, not on your PR, so skipping it turns `main` red.

CI, accurately:

- **On every pull request**: `test-lint.yml`, `gitleaks.yml`, `history-check.yml`, `review-labels.yml`, `pr-size.yml`.
<!-- claim: workflow-on test-lint.yml pull_request -->
<!-- claim: workflow-on gitleaks.yml pull_request -->
<!-- claim: workflow-on history-check.yml pull_request -->
<!-- claim: workflow-on review-labels.yml pull_request -->
<!-- claim: workflow-on pr-size.yml pull_request -->
- **Required before merge to `main`**: `test-lint / test`, `test-lint / lint`, `test-lint / test-macos`, `test-lint / test-macos-skip`, `gitleaks / gitleaks`, `history-check / history-check`, `risk-review-gate / risk-review-gate`. The check names are validated against workflow sources on every PR run and against live branch protection wherever the API is readable (maintainer machines); CI cannot read branch protection.
<!-- claim: required-check test-lint / test -->
<!-- claim: required-check test-lint / lint -->
<!-- claim: required-check test-lint / test-macos -->
<!-- claim: required-check test-lint / test-macos-skip -->
<!-- claim: required-check gitleaks / gitleaks -->
<!-- claim: required-check history-check / history-check -->
<!-- claim: required-check risk-review-gate / risk-review-gate -->
- **After merge, not a PR gate**: `ci-matrix.yml` runs on pushes to `main`, on a weekly schedule, and on manual dispatch. It is a portability detection net. Do not wait for it on a PR — a pull request event does not start it.
<!-- claim: workflow-on ci-matrix.yml push schedule workflow_dispatch -->
<!-- claim: workflow-not-on ci-matrix.yml pull_request -->

"It looks right" is not evidence. The output of those commands is.

---

## 3. Boundaries

MUST:

- Target **bash 3.2+** in `install.sh` and `scripts/` (reason: the macOS default ships 3.2, and this tool installs onto other people's machines).
- Add or extend a test when you change installer, pause, task-runner, or adapter behavior (reason: [CONTRIBUTING.md](CONTRIBUTING.md) — the contract is only real if a test pins it).
- Keep English canonical. When you change user-facing text, update the matching translation — the sibling `docs/*.ja.md` for a docs change, `README.ja.md` / `.zh.md` / `.th.md` for a README change — or state in the PR that translations are a follow-up.
- Prefer plain files, atomic writes, and explicit receipts over background state (reason: this is the design principle of the whole project — see [docs/engineering.md](docs/engineering.md)).

MUST NOT:

- Bypass the documented plugin seams (`scripts/tr-enqueue`, pinned templates, read-only artifact consumption) — see [docs/plugin-convention.md](docs/plugin-convention.md).
- Weaken or contradict [adapters/CONTRACT.md](adapters/CONTRACT.md) from an adapter-specific guide, for the adapters it binds.
- Use bash 4+ features (reason: same as the bash 3.2+ rule — it fails on macOS users).
- Put sensitive vulnerability details in a public issue — see [SECURITY.md](SECURITY.md).

---

## 4. How to work here

This is [CONTRIBUTING.md](CONTRIBUTING.md) restated. If you need the reasoning, read it there.

1. **Issue first** for non-trivial work: *why* the change is needed, what *"done" looks like* as checkable conditions, and *which files you expect to touch*. One-line fixes such as typos are exempt. Vulnerabilities go through [SECURITY.md](SECURITY.md) instead.
2. **One pull request per issue**, and keep branches short-lived.
3. **List the files you changed**, confirm they match what the issue predicted, and explain any difference. A difference is allowed; an unexplained difference is not.
4. **Show your evidence.** State which done-conditions passed and how you checked them.

Changes land through pull requests: the required checks above only run on a PR, so a direct push to `main` is invisible to the required checks listed in section 2.

The maintainers additionally run the lane discipline in the [Family Dev Handbook](https://github.com/caty-ai/family-dev-handbook) — WIP declarations, worktrees, parallel-work rules. That is maintainer process, not a requirement placed on outside contributors, and `CONTRIBUTING.md` remains the contract for this repository.

---

## 5. Definition of done

- [ ] Every "done when" condition on the issue passes, with evidence
- [ ] `make test` and `make lint` are green locally
- [ ] The required checks listed in section 2 are green
- [ ] No undeclared skipped tests — the anti-SKIP gates reject `SKIP` lines unless the exact full line content is declared in `.github/ci/declared-skips.pin` (one occurrence per declared line)
- [ ] Nothing left that only *looks* done — `CONTRIBUTING.md` calls this honest completion, and a TODO placeholder or a stub standing in for the stated behavior fails it
- [ ] Reviewed by someone other than the author — a maintainer norm; GitHub does not enforce it here

---

## 6. Maintaining this file

- Prefer a link over a copied fact. Machine-readable claim markers let CI validate selected duplicated mechanics; unmarked facts can still drift silently.
- Keep it between 50 and 200 lines. When it grows, move content into `docs/` and leave a link.
- Change it in the same PR that changes the behavior it describes. A stale map is worse than no map.
