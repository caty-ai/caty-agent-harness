# Contributing

Thanks for your interest in improving Caty Agent Harness.

## Ground rules

- **Issue first.** Open a GitHub issue before starting non-trivial work. State *why* the change is needed, *what "done" looks like* (checkable conditions), and *which files you expect to touch*. One-line fixes such as typos are exempt.
- **Stay inside the documented seams.** Integrations must go through the documented plugin seams (`scripts/tr-enqueue`, pinned templates, read-only artifact consumption) and must not bypass runtime-specific installer or verifier requirements. See [docs/plugin-convention.md](docs/plugin-convention.md).
- **Honest completion.** A change is done when its stated done-conditions pass with evidence, not when it looks done. Pull requests should list which conditions passed and how they were checked.

## Prerequisites

The tests are plain shell suites, but a few tools must be present:

- **bash 3.2+** — the macOS default is fine; everything targets it (see Code style)
- **make** — the test and lint entry points are Makefile targets
- **git 2.34+** — the updater suite exercises SSH signature verification, which older git cannot do
- **ssh-keygen with `-Y` support** (OpenSSH 8.2+, the floor git documents for SSH signing) — the updater suite generates and verifies ed25519 signing keys; without it those cases cannot run
- **python3** — several suites shell out to it for fixtures and checks (any recent 3.x)
- standard Unix tools (grep, sed, awk, mktemp) as shipped on macOS or Linux

## Running the tests

From the repository root:

```sh
make test
make lint
```

`make test` runs every shell suite under `tests/` and reports all failing suites after the run; `make lint` syntax-checks every tracked shell script and rejects Bash 4.2+ Unicode escapes in ANSI-C quoted strings. All suites must pass before a pull request is reviewed. If your change alters installer, pause, task-runner, or adapter behavior, add or extend a test that pins the new contract.

WSL2 contributors run the same `make test` and `make lint`, with the same support conditions as the README: if you are validating install or hook behavior, your AI tool (Claude Code / Codex CLI) must run inside the same WSL2 distro, the repo must live on the Linux filesystem (`/home/...`, not `/mnt/c/...`) for correctness rather than speed, `git 2.34+` is required, the user must be non-root, and wrapper-type files must not be group/world-writable (for example `chmod 0755`). The post-merge `ci-matrix` job carries the closest automated approximation in the `ubuntu-wsl2-profile` cell (`umask 002`, non-root container); the pull-request gate is still `test-lint`, so a regression that appears only under `umask 002` will surface on `main`'s matrix run, not in the PR gate.

## Pull requests

- Keep one pull request per issue, and keep branches short-lived.
- List the files you changed and confirm they match what the issue predicted; explain any difference.
- Documentation changes follow the same flow. English (`README.md`, `docs/*.md`) is canonical; please keep the Japanese, Chinese, and Thai translations aligned when you change user-facing text, or note in the PR that translations need a follow-up.

## Code style

- `install.sh` and `scripts/` target **bash 3.2+** (macOS default); avoid bash 4+ features.
- Prefer plain files, atomic writes, and explicit receipts over background state — that is the design principle of the whole project.
