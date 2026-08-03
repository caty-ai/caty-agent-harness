# Contributing

Thanks for your interest in improving Caty Agent Harness.

## Ground rules

- **Issue first.** Open a GitHub issue before starting non-trivial work. State *why* the change is needed, *what "done" looks like* (checkable conditions), and *which files you expect to touch*. One-line fixes such as typos are exempt.
- **Stay inside the documented seams.** Integrations must go through the documented plugin seams (`scripts/tr-enqueue`, pinned templates, read-only artifact consumption) and must not bypass runtime-specific installer or verifier requirements. See [docs/plugin-convention.md](docs/plugin-convention.md).
- **Honest completion.** A change is done when its stated done-conditions pass with evidence, not when it looks done. Pull requests should list which conditions passed and how they were checked.

## Running the tests

From the repository root, run every shell suite:

```sh
set -e
for test_file in tests/*.test.sh; do
  bash "$test_file"
done
```

All suites must pass before a pull request is reviewed. If your change alters installer, pause, task-runner, or adapter behavior, add or extend a test that pins the new contract.

## Pull requests

- Keep one pull request per issue, and keep branches short-lived.
- List the files you changed and confirm they match what the issue predicted; explain any difference.
- Documentation changes follow the same flow. English (`README.md`, `docs/*.md`) is canonical; please keep the Japanese, Chinese, and Thai translations aligned when you change user-facing text, or note in the PR that translations need a follow-up.

## Code style

- `install.sh` and `scripts/` target **bash 3.2+** (macOS default); avoid bash 4+ features.
- Prefer plain files, atomic writes, and explicit receipts over background state — that is the design principle of the whole project.
