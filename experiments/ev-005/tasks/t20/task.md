# Task t20

## Goal

Create an English evidence register that keeps product claims next to their
inspectable primary evidence, states uncertainty honestly, and fails closed
when evidence review becomes stale.

## Done when

- [ ] U1. `docs/evidence.md` exists.
- [ ] U2. Every claim records what maintainers `believe`.
- [ ] U3. Every claim records what was `built`.
- [ ] U4. Every claim records what `actually happened`.
- [ ] U5. Every claim records what maintainers `still don't know`.
- [ ] U6. Every claim has a unique, stable `claim-id`.
- [ ] U7. Every claim records delivery, visibility, and evidence state.
- [ ] U8. Every claim includes a primary-evidence link or explicitly identifies
  that the cited evidence is mechanism-only rather than a primary record.
- [ ] U9. Every claim records `observed-at`.
- [ ] U10. Every claim records `last-reviewed`.
- [ ] U11. Every claim records an `owner`.
- [ ] U12. Every claim records `counter-evidence`, using `none` when absent.
- [ ] U13. The initial register includes the discovery and repair of a silent
  failure.
- [ ] U14. The initial register includes a deliberately broken CI gate and its
  red/green recovery evidence.
- [ ] U15. The initial register includes an observed weekly reality-check run.
- [ ] U16. The initial register includes the governed self-growth sequence
  propose → trial → council → owner approval → adopt; if no public primary
  record exists yet, the entry must say so and remain unverified.
- [ ] U17. Before a link is accepted, a person checks its destination content,
  comments, and attachments against the denylist and records the review date;
  unverified links are excluded.
- [ ] U18. Evidence older than 90 days is treated as unknown until reverified.
- [ ] U19. The weekly workflow contains an evidence-freshness job that parses
  exact `last-reviewed` fields and fails for an age greater than 90 days.
- [ ] U20. The freshness failure is fail-closed: automation flags the stale
  claim and never edits the evidence register into a false current state.
- [ ] U21. Every evidence link is anonymously readable.
- [ ] U22. Every evidence link is safe for public disclosure.

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
