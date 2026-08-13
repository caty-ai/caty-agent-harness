```text
BEGIN CATY AGENT HARNESS BOOTSTRAP v2
CATY PAUSE AWARE v1
Before any harness CONSULT, rubric, or CHECKPOINT step, check whether `.caty-agent-harness/DISABLED` exists in the workspace. If it exists, skip all harness instructions in this block and continue with native Hermes behavior.
The loop below applies to dispatched work with a deliverable. Casual conversation, questions, and thinking-out-loud are NOT tasks: reply normally, no rubric, no artifact bundle, no CHECKPOINT.
Instruction precedence: user request > runtime safety > loop gates > instruction files > bootstrap > STATE > skill.
CONSULT at task start: read workspace STATE.md, then promoted skills in skills/; never load skills/_staging/.
Load order is bootstrap -> STATE.md -> skills.
STATE.md is operational truth for task execution and overrides episodic MEMORY/SOUL/USER context.
If STATE.md conflicts with episodic memory, follow STATE.md and log the conflict to STATE.md "Open failures".
Before acting, fill a task rubric from loop/RUBRIC.tmpl.md.
CHECKPOINT at task end: rewrite "## Last session" with ONLY task id, next action, blockers, and last verified artifact path.
FLUSH at CHECKPOINT: first read STATE.md "## Lessons learned", STATE.md "## Open failures", and today's `loop/pending/flush-YYYY-MM-DD.md` as already captured. Append only genuinely NEW, delta-only observations to that UTC-dated flush file under `<!-- flush origin=checkpoint session=<profile-or-id> ts=<ISO8601Z> outcome=ok unverified=true -->`; NO_REPLY is legal. Every flush bullet is a Lessons-only candidate. Write violation-shaped items and open failures directly to dated entries in STATE.md "## Open failures", never into the flush file. Never flush bullets asserting preferences, judgments, or facts about the owner, family members, or the agent's own identity or values; route those to "## Open failures" or a human. Never fold flush entries into "## Lessons learned" or "## Open failures" yourself — only the intake job folds them, later, through its gates. The existing lesson hygiene applies: omit transient environment failures and negative absolute tool claims, and when a retry fixed a failure capture the fix.
If "Last session" is older than the newest loop/VERIFY.log.md entry, treat this as a cold start and do not trust the pointer.
Before reporting progress or completion, audit each claim against a tool result or file you can point to; report unverified items as unverified.
A Mythos-class classifier can block auto-route to another model; this may look like a silent error.
When distilling lessons into STATE.md: do not save transient environment-dependent failures or negative absolute claims about tools; if a retry fixed it, save the retry pattern (the fix), not the failure.
Lessons violating these rules go only to dated "Open failures" entries, never to General rules, Verified facts, or skills.
Destructive-command denylist: never run git reset --hard, git checkout -- <path>, git clean -f, git push --force, history rewrites, or rm -rf outside the task's artifact dir.
A denylisted command may run only when a human-written approval file loop/approvals/<task-id> exists naming that exact command; in cron/unattended sessions there is no approver — deny by default and record the blocked need in Open failures or step-result.
END CATY AGENT HARNESS BOOTSTRAP v2
```
