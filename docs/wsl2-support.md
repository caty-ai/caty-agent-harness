# WSL2 support note

This note records the measured scope behind Caty Agent Harness's WSL2 claim. It is intentionally narrower than "Windows support": native Windows remains unsupported, while WSL2 (Ubuntu on Windows) is a separate verified-with-conditions tier.

For the full decision lane, issue history, and wording discussion, see [issue #158](https://github.com/caty-ai/caty-agent-harness/issues/158).

## Summary

- **Native Windows**: not supported. The measured blockers are filesystem and locking semantics that break harness assumptions.
- **WSL2 (Ubuntu on Windows)**: supported with conditions, verified on one dated machine on 2026-08-23, but not CI-tested.
- **Closest CI approximation**: `ubuntu-wsl2-profile` in `ci-matrix` (`umask 002`, non-root container). That is useful evidence, but it is still not the same thing as a real WSL2 run.

## Measured record

### 2026-08-22 baseline measurements

- Native Windows: **5/30 suites passed**
- WSL2 before correcting ambient conditions: **24/30 suites passed**
- WSL2 after correcting ambient conditions but before issue #157: **29/30 suites passed**

The one remaining failure at that point was the real harness bug fixed by [issue #157](https://github.com/caty-ai/caty-agent-harness/issues/157), not a WSL2-only environment artifact.

### 2026-08-23 post-fix measurements

- WSL2 with the `umask 022` profile, after #157: **30/30 suites passed**
- WSL2 after D1', under raw `umask 0002`: **30/30 suites passed**

The dated machine was `win11-test-vm`, a Windows 11 Enterprise Evaluation VM on the family server. The verified WSL2 environment used Ubuntu, a non-root user, `git 2.50`, and a repository checkout on the Linux filesystem.

## Windows native walls

These three measured walls are why native Windows is still marked unsupported:

1. `chmod` silently becomes `644`, so wrapper and trust-mode checks cannot rely on the requested executable mode.
2. `ln -s` becomes a copy rather than a real symlink in the tested path, so harness symlink assumptions do not hold.
3. There is no `flock`, so the locking contract used by the harness is missing.

Any one of those would be a serious caveat. Together they are enough to keep native Windows out of the supported set.

## Conditions for the WSL2 tier

The WSL2 claim is real only under these conditions:

1. **Your AI tool must run inside the same WSL2 distro.**
   A Windows-side agent can install successfully while the harness hooks simply never fire. This is the easiest failure to miss, so it is the first condition everywhere the claim is made.
2. **The repository must live on the Linux filesystem.**
   Use a path like `/home/...`, not `/mnt/c/...`. This is a correctness requirement, not just a performance tip: the harness relies on Linux filesystem semantics for mode checks, symlinks, and related trust decisions.
3. **Use `git 2.34+`.**
   Older Git versions miss the SSH-signing floor used by the updater suites.
4. **Run as a non-root user.**
   Root can make permission-sensitive tests pass for the wrong reason, hiding the behavior the harness is trying to verify.
5. **Wrapper-type files must not be group/world-writable.**
   Use modes like `0755`. Under `umask 002`, a bare `chmod +x` can leave wrappers at `0775`, and the harness correctly refuses those files. That refusal is intentional fail-closed behavior, not a bug.

## Scheduling on Linux/WSL2

The adapter scheduling docs were written macOS-first (LaunchAgent). The launchd rationale — macOS crontab sessions cannot reach the user Keychain, so `claude -p` exits with `Not logged in` under cron — is macOS-specific. On Linux and WSL2 the claude CLI discovers its credentials under `$HOME` on disk, so cron is a valid scheduler for the same tick wrappers. Two working options:

### Option A: cron

The WSL2-specific trap: **cron does not autostart** in a stock WSL2 distro. Either

- enable systemd — put `[boot]`/`systemd=true` in `/etc/wsl.conf` inside the distro, then run `wsl --shutdown` from Windows and reopen; cron and systemd timers then start on distro boot — or
- without systemd, start it per boot with `sudo service cron start` (manually, or via a `[boot]` `command=service cron start` line in `/etc/wsl.conf`).

Either way, remember that a WSL2 distro only runs while Windows keeps it alive; a tick schedule assumes the distro is up at tick time.

A crontab entry for the harness cron wrapper looks like:

```crontab
CATY_WRAPPER_EXTRA_PATH=/home/<user>/.local/bin:/home/<user>/.npm-global/bin
TARGET=/absolute/path/to/caty-agent-harness/adapters/claude-code/flush-intake.sh
CATY_HARNESS_ROOT=/absolute/path/to/caty-agent-harness
0 */8 * * * /bin/bash /absolute/path/to/workspace/scripts/cron-wrapper.sh /absolute/path/to/workspace
```

### Wrapper PATH: `CATY_WRAPPER_EXTRA_PATH`

Both wrapper templates (`templates/cron-wrapper.tmpl.sh`, `templates/updater-cron.tmpl.sh`) pin `PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`. On Linux/WSL2 the `claude`/`codex` CLIs are almost always under a user-local prefix — `~/.nvm/versions/node/<version>/bin`, `~/.npm-global/bin`, or `~/.local/bin` — none of which is on that list, so a tick can fail to find the CLI even though interactive shells work. Set `CATY_WRAPPER_EXTRA_PATH` in the crontab (or unit) environment to a colon-separated list of absolute directories. The wrapper validates each entry (absolute, non-empty; anything else is a fail-closed infra error, exit 3) and appends the list **after** the pinned baseline, so user directories can never shadow system tools. Find the real directory with `dirname "$(command -v claude)"` in an interactive shell; note that nvm paths are version-specific and move on `nvm install`, so prefer a stable prefix such as `~/.npm-global/bin` or `~/.local/bin` where you can.

This variable is for the two wrapper templates only. The Hermes verifier provider intentionally keeps its own fixed `PATH=/usr/bin:/bin` and does not honor it; see `adapters/hermes/INSTALL.md` for that contract.

### Option B: systemd user timer

With `systemd=true` enabled, a user unit + timer pair fills the LaunchAgent role:

```ini
# ~/.config/systemd/user/caty-intake.service
[Unit]
Description=Caty harness flush intake tick

[Service]
Type=oneshot
Environment=TARGET=/absolute/path/to/caty-agent-harness/adapters/claude-code/flush-intake.sh
Environment=CATY_HARNESS_ROOT=/absolute/path/to/caty-agent-harness
Environment=CATY_WRAPPER_EXTRA_PATH=/home/<user>/.local/bin
ExecStart=/bin/bash /absolute/path/to/workspace/scripts/cron-wrapper.sh /absolute/path/to/workspace
```

```ini
# ~/.config/systemd/user/caty-intake.timer
[Unit]
Description=Caty harness flush intake cadence

[Timer]
OnUnitActiveSec=8h
OnBootSec=5min
Persistent=true

[Install]
WantedBy=timers.target
```

Enable with `systemctl --user enable --now caty-intake.timer`, and run `loginctl enable-linger <user>` so the user manager keeps running without an open session — on WSL2, sessions close often.

## Known caveats

- **mawk (`--check` freshness warning) — tracked as [issue #84](https://github.com/caty-ai/caty-agent-harness/issues/84).** Ubuntu's default `awk` is mawk, which does not support the ERE interval regex used by the `install.sh` freshness check, producing a spurious `cannot prove fresh` warning. Until #84 closes, treat that specific warning as unproven-not-stale under mawk, or install `gawk`.
- **perl is a runtime prerequisite for task-runner.** Stock Ubuntu ships it; minimal WSL2/container images may not. See the prerequisites list in [CONTRIBUTING.md](../CONTRIBUTING.md) for the fail-closed behavior when it is absent.
- **Locale coverage differs from CI in human runs.** `tests/pause-contract.test.sh` hard-asserts its `en_US.UTF-8` locale-path case only on Darwin and skips it elsewhere, so a human WSL2 `make test` silently loses that coverage unless the locale exists. CI restores it with `locale-gen`; for parity run `sudo locale-gen en_US.UTF-8` once in the distro.

## Why the `umask` axis matters

The first fail-open lesson came from [issue #157](https://github.com/caty-ai/caty-agent-harness/issues/157) and commit `a58062a`, not from `umask`. Before that fix, mode detection assumed BSD-first `stat` handling; on GNU userlands it could yield invalid or empty mode data. WSL2 exposed that as the one remaining real suite failure after the ambient setup was corrected. At the same time, the existing CI GNU cells stayed green because the arithmetic path did not turn that bad mode data into a failing check, so those green cells were effectively fail-open. `#157` changed mode detection to GNU-first and validates a pure octal mode string before doing arithmetic, so invalid or empty data now fails closed instead of slipping through.

The later `umask` lesson is separate. The 2026-08-22 run also showed that a WSL2 result could look "almost supported" while still depending on ambient `umask` behavior. That is why D1' made trust fixtures `umask`-independent and why D2' added the `ubuntu-wsl2-profile` CI cell. The pre-D1' measurement under raw `umask 0002` was **6 failing suites / 50 FAIL lines** (issue #158 実測ゲート, 2026-08-23), which D1' took to zero. If the suite had only passed under `umask 022`, it would still have been too easy to document WSL2 as supported while missing a real-world `umask 002` refusal path. After D1', the raw `umask 0002` run passed 30/30, which is the evidence behind the current wording.

## Scope and honesty

- This is a **dated, one-machine verification record**, not a broad claim about every Windows laptop or every WSL2 distro.
- WSL2 is therefore marked **🟡 supported with conditions**, not **✅ CI-tested**.
- Native Windows remains **❌ not supported** until those measured walls are removed or a new support path is proven.
