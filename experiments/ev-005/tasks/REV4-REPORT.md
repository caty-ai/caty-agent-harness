# EV-005 acceptance-driven revision report REV4

## t12 r4-1 exemption

`t12` is revised under a narrow r4-1 exemption for `a12`/`a13` only. The full
source-required suite keeps caller `HOME` because that upstream suite couples
to passwd-home resolution after clearing the process environment. The sealed
experiment runner already provides a per-run private `HOME`, so the forgone
donecheck-layer `HOME` replacement is still satisfied at the runner layer.
`TMPDIR` remains suite-specific. Probes `a01`-`a11` are unchanged and still run
under invocation-specific fresh `HOME`/`TMPDIR`.

## Ruling rationale

REV3 proved the isolation backfill itself created the false-negative on the fix
leg: `test_recall.RecallTests.test_search_adapters_guard_leading_dash_query`
reads passwd-home after env clearing, while the expectation path was expanded
against the injected suite `HOME`. That coupling belongs to the source suite,
not to the acceptance target. The correct r4-1 disposition is therefore a
targeted exemption for the full-suite leg instead of weakening any earlier
probe.

## Diff summary

- `t12/donecheck.sh`: removed the suite-only `HOME="$suite_root/home"` override
  and the unused `suite_root/home` directory creation for `a12`/`a13`; kept
  `TMPDIR="$suite_root/tmp"`, `PYTHONDONTWRITEBYTECODE=1`, mktemp/cleanup, and
  the existing `a13` grep unchanged.
- `t12/units.md`: updated `U12`, the pair note, and the timeout/footer note to
  record the r4-1 exemption precisely and remove stale fresh-`HOME` suite
  wording.

## Validation status

Authoritative REV4 validation now completes with `VERDICT t12 PASS`. The fresh
post-edit log at `../tools/validate-logs/t12.log` records pre FAIL×5 / fix
PASS×5, with all completed runs showing pre exit=1×5 and fix exit=0×5. The
completed suite durations were 22–24 seconds. This confirms the exemption
resolves the false negative without changing `a01`-`a11`.

## Retroactivity scope

No other task is affected. Under r4-1 retroactivity, only `t12`'s source
criterion requires the full FMA suite whose upstream passwd-home coupling makes
this exemption necessary.
