# Task t09

## Goal

Make the generated-artifact permission check portable to directories that
inherit a different group, while retaining strict owner-and-group enforcement
for deployments that explicitly pin an artifact owner.

## Done when

- [ ] U1. With no pinned owner configured, the permission check accepts a
  generated artifact whose uid is the current user's and whose mode is `0600`,
  even when its gid differs from the process group.
- [ ] U2. When `FMA_EXPECT_OWNER` pins an owner and group, a uid mismatch still
  fails the permission check.
- [ ] U3. When `FMA_EXPECT_OWNER` pins an owner and group, a gid mismatch still
  fails the permission check.
- [ ] U4. Repository tests cover both the default inherited-group acceptance
  path and the pinned-owner group-mismatch rejection path.

## Allowed tools

| Tool | Allowed | Notes |
| --- | --- | --- |
| `bash` and standard local Unix tools | Yes | Read files, run local checks, and edit files in this repository |
| `git` (read-only) | Yes | Inspect tracked content, diffs, and status; no commits, pushes, fetches, or resets |
| Standard file editing | Yes | Change repository files directly |
| Network, `gh`, or web access | No | Not available for this task |

## Budget

- Attempt budget: `45 minutes wall-clock per run / at most 5 completion declarations per run`
- Donecheck timeout: `120 s` per `donecheck.sh` invocation — a verification-time
  bound on the machine gate, separate from and not part of the attempt budget.
- A machine gate `donecheck.sh` ships with this task; it is readable and executable.
