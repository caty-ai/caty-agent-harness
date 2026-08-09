# Agent Guide — installing Caty Agent Harness

**You are (probably) an AI agent.** A human handed you this repository and asked you to set it up. This page is written for you: follow it top to bottom, then report back to your human in plain words. Humans reading along are welcome — the [front page](../README.md) has the friendly version, and the [engineering guide](engineering.md) has the deep one.

---

## What you are installing

Caty Agent Harness adds a file-based work discipline to the workspace you operate in: a handover notebook (`STATE.md`), completion checks with evidence, and honest-stop rules. It is **additive**: it creates missing files and appends one clearly-marked instruction block to your instruction file. It never replaces existing files, and nothing in this guide touches global configuration without your human's explicit approval.

Your write boundary for this installation:

- ✅ the clone directory, and the workspace directory the human designates
- ✅ appending the marked bootstrap block to the workspace's instruction file
- ⛔ global hooks/config/cron/launchd — only in step 5, only with the human's OK

---

## Step 0 — check the ground

Run these read-only checks and note the results for your final report:

```sh
git --version
bash --version          # 3.2+ is fine (macOS default works)
command -v python3      # needed for hooks and automated paths
```

If `python3` is missing, you can still complete steps 1–4; say so in your report and point the human at their platform's Python 3 install. This repository is public at <https://github.com/caty-ai/caty-agent-harness>, so no invitation is needed. If the repository URL is not reachable, stop and tell the human which error you saw.

<a id="step-1--identify-your-runtime"></a>

## Step 1 — identify your runtime

Pick the row that matches the tool **you** are running in right now:

| You are | `--bootstrap-runtime` | Instruction file to append to |
| --- | --- | --- |
| Claude Code | `claude-code` | `<workspace>/CLAUDE.md` |
| Codex CLI | `codex` | `<workspace>/AGENTS.md` |
| Kimi Code CLI | `kimi` | `<workspace>/AGENTS.md` |
| Hermes Agent | `hermes` | profile system-instructions file — follow [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) for the exact invocation |
| OpenClaw | `openclaw` | `<workspace>/AGENTS.md` — follow [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) for the exact invocation |

If you are none of these, stop and tell the human this tool is not yet supported (the list is exact; do not improvise).

## Step 2 — clone

Clone **next to**, not inside, the workspace (the clone keeps the scripts the harness runs from). If your current directory *is* the workspace, step out first:

```sh
cd ..    # only if you are currently inside the workspace
git clone https://github.com/caty-ai/caty-agent-harness.git
cd caty-agent-harness
```

## Step 3 — install into the workspace

`WORKSPACE` is the project folder the human wants you to work in — **use an absolute path** (the instruction-file append requires one):

```sh
WORKSPACE="/absolute/path/to/the/project"
./install.sh --workspace "$WORKSPACE" --bootstrap-runtime <your-runtime> --append-bootstrap "$WORKSPACE/<instruction-file>"
```

Fill `<your-runtime>` and `<instruction-file>` from the Step 1 table (Hermes and OpenClaw: use the exact invocation from your adapter document instead of this template). Missing folders and files are created; existing ones are never replaced. If the block is already present you'll see `skip: bootstrap already present` — that's fine, it's idempotent.

## Step 4 — health check

Always pass the workspace explicitly:

```sh
./install.sh --check --workspace "$WORKSPACE"
```

- Healthy required layout ends with: `ok: required layout and STATE.md headers present` (exit code 0).
- `learning path … FAIL` rows can appear while exit code stays 0: those are **optional automation paths not wired yet** (verifier, distiller cron, …). They are your step-5 to-do list, not an error.
- Exit code 1 means the required layout, `STATE.md` headers, or pause-control path safety is actually broken — read the message, fix, re-run.
- Exit code 2 means a usage error or a rejected unsafe path/object — re-check your flags and paths against Step 3.

## Step 5 — wire your runtime's automation (needs the human's OK)

The bootstrap block from Step 3 already makes you read `STATE.md` at task start. **End-of-session checkpoint reminders and deeper automation need per-runtime wiring that edits user-level config — ask your human before doing this**, then follow your adapter document:

| Runtime | What gets wired | Document |
| --- | --- | --- |
| Claude Code | `Stop` + `PreCompact` hooks (user settings) | [adapters/claude-code/INSTALL.md](../adapters/claude-code/INSTALL.md) |
| Codex CLI | `Stop` hook (`~/.codex/hooks.json`) | [adapters/codex/INSTALL.md](../adapters/codex/INSTALL.md) |
| Kimi Code CLI | `Stop` hook (`config.toml` `[[hooks]]`) | [adapters/kimi/INSTALL.md](../adapters/kimi/INSTALL.md) |
| Hermes Agent | verifier route, task-runner steps, cron/watchdog | [adapters/hermes/INSTALL.md](../adapters/hermes/INSTALL.md) |
| OpenClaw | nightly distillation + sentinel cron | [adapters/openclaw/INSTALL.md](../adapters/openclaw/INSTALL.md) |

If the human defers this, that's a valid state — the notebook and start-of-task discipline already work. Just say clearly in your report what is wired and what isn't.

## Step 6 — report back to your human

Use plain words, no jargon. A good report covers:

```text
Set up complete. Here's what that means:

- I now keep a handover notebook in <workspace> — if our session ends or resets,
  I can pick up where we left off instead of starting over.
- Health check: passed (core layout OK). [If FAIL rows: "Some optional automation
  (e.g. …) isn't wired yet — it needs a small settings change; want me to?"]
- What's wired / not wired: <from step 5>
- Nothing was replaced: I only added files and one marked block to <instruction file>.
- To pause everything in this workspace: one command, and all your notes and history stay.
  [If step 5 was wired: "The hook settings I added in step 5 stay until removed — I can
  take them out again on request."]

Want to try it? Give me a small task, then close this session and start a new one —
I'll remember where we were. Or ask me to run the bundled example at
templates/examples/img-pilot.task.md.
```

The bundled example you can run builds a self-contained SVG image card and a JSON delivery receipt using local tools only. From the harness repository root, set `STEP_PROVIDER` to your AI tool's step provider and run it end to end:

```sh
scripts/loop-init --workspace "$WORKSPACE"
scripts/tr-enqueue templates/examples/img-pilot.task.md "$WORKSPACE"
TR_SPAWN_STEP="$STEP_PROVIDER" scripts/task-runner.sh "$WORKSPACE"   # repeat until delivered
```

---

## Troubleshooting

| Symptom | Meaning | Do |
| --- | --- | --- |
| `append target must be an absolute path with an existing real parent: …` (exit 2) | The instruction-file path wasn't absolute, or the target/its parent is a symlink, or the parent folder doesn't exist | Re-run Step 3 with an absolute `$WORKSPACE` path |
| `skip: bootstrap already present` | The block is already installed (idempotency marker `# caty-agent-harness bootstrap v2`) | Nothing — this is success |
| `--check` exit 1 | Required layout or safety invariant broken | Read the message; usually re-running Step 3 repairs missing scaffold |
| Want to stop the harness | — | `./install.sh --disable --workspace "$WORKSPACE"` (reversible; `--enable` resumes; state is preserved) |

Deeper semantics (pause states, budgets, promotion rules): [reference.md](reference.md). Boundaries of what is mechanically enforced vs. instructed: [engineering.md](engineering.md).
