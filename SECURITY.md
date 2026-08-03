# Security Policy

Caty Agent Harness is a pure-shell/Python sidecar that writes plain files inside an agent workspace. It runs no daemon and opens no network ports, but it does append instruction blocks to agent instruction files and wire optional hooks and scheduled jobs. Security reports are welcome for:

- Leaked credentials, tokens, or personal information anywhere in the repository or its git history
- Ways to make the installer, `task-runner`, pause control, or updater write outside the managed workspace or escalate beyond documented behavior
- Ways to defeat the completion-evidence, verification, or pause contracts while appearing compliant
- Links in the documentation that point to malicious or compromised destinations

## Reporting a Vulnerability

Please report security issues privately via **GitHub's private vulnerability reporting** on this repository (Security → Report a vulnerability). If that is unavailable, open a GitHub issue *without sensitive details* and ask a maintainer to establish a private channel.

We aim to acknowledge reports within 7 days. Please do not disclose the issue publicly until it has been addressed.

## Supported Versions

Only the latest tagged release and the `main` branch are maintained.
