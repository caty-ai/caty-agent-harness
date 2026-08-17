"""Machine-readable and counter-evidence-first EV-005 result reports."""

from __future__ import annotations

from collections import Counter, defaultdict
from fractions import Fraction
import json
import math
from pathlib import Path
import subprocess
from typing import Any, Callable

from coding import CodedRun
from draws import crosscheck_draw, gaming_audit_draw
from load import ARMS, LoadedData
from stats import (
    exact_contrast, five_number, generic_signflip_contrast, paired_binary_counts,
    permutation_ci, sign, tango_score_interval,
)


DECISION_RULE = (
    "H-primary is confirmed iff the §4 primary test rejects at α = 0.05 two-sided in W's "
    "favor; anything else is reported as not confirmed. No other test can confirm H-primary."
)
REGISTERED_SEATS = ("seat-01", "seat-02", "seat-04", "seat-05", "seat-06")


def _task_successes(
    coded: list[CodedRun], removed: set[str],
) -> tuple[dict[str, dict[str, int]], dict[str, dict[str, int]]]:
    matrix: dict[str, dict[str, int]] = defaultdict(lambda: {arm: 0 for arm in ARMS})
    denominators: dict[str, dict[str, int]] = defaultdict(lambda: {arm: 0 for arm in ARMS})
    for run in coded:
        if run.record.task_id in removed:
            continue
        denominators[run.record.task_id][run.record.arm] += 1
        if run.verified:
            matrix[run.record.task_id][run.record.arm] += 1
    return dict(matrix), dict(denominators)


def _contrast(
    matrix: dict[str, dict[str, Fraction]], left: str, right: str,
    tail_prob: Callable[..., float],
) -> dict[str, Any]:
    differences = [matrix[task][left] - matrix[task][right] for task in sorted(matrix)]
    scaled = [difference * 3 for difference in differences]
    if all(value.denominator == 1 for value in scaled):
        units = [int(value) for value in scaled]
        result = exact_contrast(units, tail_prob)
        result["ci_95"] = (
            permutation_ci(units) if units else
            {"lower": None, "upper": None, "grid_step": 1 / 300, "accepted_points": 0}
        )
    else:
        result = generic_signflip_contrast(differences)
        result.update({
            "difference_units": None,
            "m_counts": None,
            "T_units": None,
            "ci_95": {
                "lower": None, "upper": None, "grid_step": None,
                "accepted_points": None,
                "reason": "reduced stopped-block denominators are off the sealed 1/3 CI grid",
            },
        })
    result["left"] = left
    result["right"] = right
    return result


def _per_protocol(coded: list[CodedRun], removed: set[str]) -> dict[str, Any]:
    grouped: dict[tuple[str, str], list[CodedRun]] = defaultdict(list)
    for run in coded:
        if run.record.task_id not in removed and run.outcome != "contaminated":
            grouped[(run.record.task_id, run.record.arm)].append(run)
    differences: list[Fraction] = []
    dropped: list[str] = []
    for task in sorted({run.record.task_id for run in coded} - removed):
        w = grouped[(task, "W")]
        bp = grouped[(task, "B+")]
        if not w or not bp:
            dropped.append(task)
            continue
        differences.append(
            Fraction(sum(run.verified for run in w), len(w))
            - Fraction(sum(run.verified for run in bp), len(bp))
        )
    result = generic_signflip_contrast(differences)
    result["tasks_without_both_arms_after_drop"] = dropped
    return result


def _subset_result(runs: list[CodedRun], selector: Callable[[CodedRun], bool]) -> dict[str, Any]:
    paired: dict[tuple[str, int], dict[str, bool]] = defaultdict(dict)
    for run in runs:
        if selector(run):
            paired[(run.record.task_id, int(run.record.ledger["replicate"]))][run.record.arm] = run.verified
    by_task: dict[str, list[int]] = defaultdict(list)
    for (task_id, _), arms in sorted(paired.items()):
        if "W" in arms and "B+" in arms:
            by_task[task_id].append(int(arms["W"]) - int(arms["B+"]))
    task_differences = [sum(values) / len(values) for _, values in sorted(by_task.items())]
    block_count = sum(len(values) for values in by_task.values())
    estimate = sum(task_differences) / len(task_differences) if task_differences else None
    return {
        "blocks": block_count, "tasks": len(task_differences), "estimate": estimate,
        "sign": sign(estimate) if estimate is not None else "unavailable",
    }


def _material_change_firings(
    full_estimate: float,
    seat_results: dict[str, dict[str, Any]],
    rotation_results: dict[str, dict[str, Any]],
) -> list[str]:
    """Return registered ≥10-block subsets with a strictly opposite sign."""
    output = []
    for prefix, results in (("seat", seat_results), ("rotation", rotation_results)):
        for name, value in sorted(results.items()):
            estimate = value["estimate"]
            if value["blocks"] >= 10 and estimate is not None and estimate * full_estimate < 0:
                output.append(f"{prefix}:{name}")
    return output


def _h2(coded: list[CodedRun], removed: set[str]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for arm in ARMS:
        arm_runs = [r for r in coded if r.record.arm == arm and r.record.task_id not in removed and r.record.declarations]
        strata: dict[str, list[CodedRun]] = {"agent_check_before": [], "no_agent_check_before": []}
        for run in arm_runs:
            first_seq = run.record.declarations[0].get("seq")
            before = any(
                e.get("event") == "donecheck_invocation" and e.get("invoker") == "agent"
                and type(e.get("seq")) is int and e["seq"] < first_seq
                for e in run.record.events
            )
            strata["agent_check_before" if before else "no_agent_check_before"].append(run)

        def summarize(items: list[CodedRun]) -> dict[str, Any]:
            adjudicated = [r for r in items if r.first is not None]
            failures = sum(not r.first.passed for r in adjudicated if r.first is not None)
            return {
                "declarations": len(items), "adjudicated": len(adjudicated),
                "adjudication_impossible": len(items) - len(adjudicated),
                "first_snapshot_failures": failures,
                "failure_proportion": failures / len(adjudicated) if adjudicated else None,
            }
        output[arm] = summarize(arm_runs)
        output[arm]["strata"] = {name: summarize(items) for name, items in strata.items()}
    return output


def _h3(data: LoadedData, coded: list[CodedRun], removed: set[str]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    attempts: Counter[tuple[str, str, int]] = Counter()
    for row in data.ledger_rows:
        key = (str(row.get("task_id")), str(row.get("arm")), int(row.get("replicate", 0)))
        attempts[key] += 1
    for arm in ARMS:
        values = [
            attempts[(run.record.task_id, arm, int(run.record.ledger["replicate"]))]
            for run in coded if run.record.arm == arm and run.record.task_id not in removed
        ]
        operator = sum(
            e.get("event") == "operator_intervention"
            for run in coded if run.record.arm == arm and run.record.task_id not in removed
            for e in run.record.events
        )
        output[arm] = {
            "attempts_per_run": five_number(values),
            "attempts_mean": sum(values) / len(values) if values else None,
            "operator_interventions": operator,
        }
    return output


def _infrastructure(coded: list[CodedRun], removed: set[str]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for arm in ARMS:
        runs = [r for r in coded if r.record.arm == arm and r.record.task_id not in removed]
        waits = [r.record.trailer.get("provider_wait_s") for r in runs]
        output[arm] = {
            "provider_wait_s": five_number(waits),
            "gate_wallclock_timeout_fraction": five_number([]),
            "wallclock_timeout_fraction_by_invoker": {
                invoker: five_number([]) for invoker in ("agent", "gate", "pipeline")
            },
        }
    return output


def _caps(
    data: LoadedData, coded: list[CodedRun], removed: set[str], *, mode: str,
) -> dict[str, Any]:
    voids = {
        arm: sum(item.get("arm") == arm for item in data.voided_attempts)
        for arm in ARMS
    }
    void_attempts: dict[str, set[int]] = defaultdict(set)
    for item in data.voided_attempts:
        void_attempts[str(item.get("block_id"))].add(int(item.get("attempt", 0)))
    all_blocks = {str(row.get("block_id")) for row in data.ledger_rows}
    voided_blocks = {block for block, attempts in void_attempts.items() if attempts}
    stopped_blocks = set(data.stopped_blocks)
    operator_rates = {}
    retention_failure_rates = {}
    for arm in ARMS:
        arm_runs = [r for r in coded if r.record.arm == arm and r.record.task_id not in removed]
        operator_rates[arm] = (
            sum(r.outcome == "operator_abort" for r in arm_runs) / len(arm_runs) if arm_runs else 0.0
        )
        retention_failure_rates[arm] = (
            sum(
                r.record.retention_failure is not None
                and _adjudication_provenance(r) == "in-run-audit"
                for r in arm_runs
            ) / len(arm_runs) if arm_runs else 0.0
        )
    retention_failure_cap_note = None
    retention_failures_over_10pct_any_arm = any(
        rate > 0.10 for rate in retention_failure_rates.values()
    )
    if mode != "docker":
        retention_failures_over_10pct_any_arm = False
        retention_failure_cap_note = (
            "Not evaluated: adjudication mode 'non-registered-dry-run' uses in-run adjudication by "
            "mode, so the retention-failure cap is not registered here."
        )
    flags = {
        "check_bug_removals_over_3": len(removed) > 3,
        "operator_abort_over_10pct_any_arm": any(rate > 0.10 for rate in operator_rates.values()),
        "retention_failures_over_10pct_any_arm": retention_failures_over_10pct_any_arm,
        "double_voided_blocks_present": bool(stopped_blocks),
        "voided_blocks_over_10pct": bool(all_blocks) and len(voided_blocks) / len(all_blocks) > 0.10,
    }
    return {
        "compromised_flags": flags, "compromised": any(flags.values()),
        "voids_per_arm": voids, "voided_attempts_per_arm": voids,
        "total_blocks": len(all_blocks),
        "voided_blocks": sorted(voided_blocks),
        "double_voided_blocks": sorted(stopped_blocks),
        "stopped_blocks": [
            {"block_id": block, "void_reasons": data.stopped_blocks[block]}
            for block in sorted(data.stopped_blocks)
        ],
        "operator_abort_rates": operator_rates,
        "retention_failure_rates": retention_failure_rates,
        "retention_failure_cap_note": retention_failure_cap_note,
    }


def _adjudication_provenance(run: CodedRun) -> str:
    if run.terminal is not None:
        return run.terminal.provenance
    if run.record.declarations:
        return "unavailable"
    return "not-applicable"


def build_report(
    *, data: LoadedData, coded: list[CodedRun], pack: Path, out_root: Path,
    series: str, mode: str, image: str, image_id: str | None,
    removed_tasks: set[str], tail_prob: Callable[..., float],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any] | None]:
    included = [r for r in coded if r.record.task_id not in removed_tasks]
    successes, denominators = _task_successes(coded, removed_tasks)
    for task in sorted(data.tasks):
        if task not in removed_tasks:
            successes.setdefault(task, {arm: 0 for arm in ARMS})
            denominators.setdefault(task, {arm: 0 for arm in ARMS})
    for task, arm_denominators in sorted(denominators.items()):
        if len(set(arm_denominators.values())) != 1:
            raise RuntimeError(
                f"ARM_SYMMETRY_DENOMINATOR_MISMATCH: task {task} has {arm_denominators}"
            )
    matrix: dict[str, dict[str, Fraction]] = {}
    for task in sorted(successes):
        denominator = denominators[task][ARMS[0]]
        if denominator:
            matrix[task] = {
                arm: Fraction(successes[task][arm], denominator) for arm in ARMS
            }
    primary = _contrast(matrix, "W", "B+", tail_prob)
    registered_adjudication = mode == "docker"
    confirmed = (
        primary["p_value"] is not None
        and primary["p_value"] <= 0.05
        and primary["estimate"] > 0
        and series == "main"
        and mode == "docker"
    )
    primary["confirmatory"] = series == "main" and registered_adjudication
    primary["confirmed"] = confirmed
    primary["decision_rule"] = DECISION_RULE if primary["confirmatory"] else None
    if series != "main":
        primary["decision_sentence"] = "Descriptive crossover contrast; no α decision is made."
    elif not registered_adjudication:
        primary["decision_sentence"] = (
            "Not evaluated: adjudication mode 'non-registered-dry-run' is not the registered "
            "procedure (analysis-plan §3.1, runner-spec §4)."
        )
    else:
        primary["decision_sentence"] = (
            "H-primary is confirmed." if confirmed else "H-primary is not confirmed."
        )
    secondary = {
        "W_vs_B": _contrast(matrix, "W", "B", tail_prob),
        "Bplus_vs_B": _contrast(matrix, "B+", "B", tail_prob),
    }
    pairs = defaultdict(dict)
    for run in included:
        pairs[(run.record.task_id, int(run.record.ledger["replicate"]))][run.record.arm] = run.verified
    incomplete_pairs = {
        key: sorted(arms) for key, arms in pairs.items() if set(arms) != set(ARMS)
    }
    if incomplete_pairs:
        raise RuntimeError(f"ARM_SYMMETRY_PAIRING_MISMATCH: {incomplete_pairs}")
    wb_pairs = [(arms["W"], arms["B+"]) for _, arms in sorted(pairs.items())]
    if not wb_pairs:
        raise ValueError("TANGO_EMPTY_PAIR_SET: no paired W/B+ scoring runs remain")
    n_pairs, discordant_w, discordant_bp = paired_binary_counts(wb_pairs)
    tango = tango_score_interval(n_pairs, discordant_w, discordant_bp)

    outcome_counts = {
        arm: dict(sorted(Counter(r.outcome for r in included if r.record.arm == arm).items()))
        for arm in ARMS
    }
    candidates = [
        {"run_id": r.record.run_id, "task_id": r.record.task_id, "reasons": r.candidate_reasons}
        for r in coded if r.candidate_reasons
    ]
    disagreements = {
        "pipeline": [r.record.run_id for r in coded if r.pipeline_disagreement],
        "w_gate": [r.record.run_id for r in coded if r.w_gate_disagreement],
    }

    sensitivity: dict[str, Any] = {"per_protocol": _per_protocol(coded, removed_tasks)}
    sensitivity["per_protocol"]["direction_matches_itt"] = (
        sensitivity["per_protocol"]["sign"] == primary["sign"]
    )
    long_drop = {"t01", "t07", "t30"}
    if series == "main":
        long_matrix = {task: arms for task, arms in matrix.items() if task not in long_drop}
        sensitivity["drop_t01_t07_t30"] = _contrast(long_matrix, "W", "B+", tail_prob)
    else:
        sensitivity["drop_t01_t07_t30"] = {"applicable": False, "reason": "registered for main series only"}
    repos = sorted({str(task.meta["source_repo"]) for task in data.tasks.values() if task.task_id not in removed_tasks})
    sensitivity["leave_one_repo_out"] = {}
    for repo in repos:
        subset = {
            task: arms for task, arms in matrix.items()
            if str(data.tasks[task].meta["source_repo"]) != repo
        }
        sensitivity["leave_one_repo_out"][repo] = _contrast(subset, "W", "B+", tail_prob)
    any_matrix = {
        task: {arm: Fraction(int(successes[task][arm] > 0), 1) for arm in ARMS}
        for task in matrix
    }
    all_matrix = {
        task: {
            arm: Fraction(int(successes[task][arm] == denominators[task][arm]), 1)
            for arm in ARMS
        }
        for task in matrix
    }
    sensitivity["aggregation"] = {
        "any_pass": _contrast(any_matrix, "W", "B+", tail_prob),
        "all_pass": _contrast(all_matrix, "W", "B+", tail_prob),
    }
    observed_seats = {str(r.record.ledger["seat"]) for r in included}
    seats = list(REGISTERED_SEATS) + sorted(observed_seats - set(REGISTERED_SEATS))
    seat_results = {
        seat: _subset_result(included, lambda r, seat=seat: str(r.record.ledger["seat"]) == seat)
        for seat in seats
    }
    rotations = {
        str(rotation): _subset_result(
            included, lambda r, rotation=rotation: int(r.record.ledger["rank"]) % 3 == rotation
        ) for rotation in range(3)
    }
    firings = _material_change_firings(primary["estimate"], seat_results, rotations)
    infra = _infrastructure(included, removed_tasks)
    # Fill task timeout values without trusting a ledger convenience field.
    for arm in ARMS:
        by_invoker: dict[str, list[float | None]] = {
            invoker: [] for invoker in ("agent", "gate", "pipeline")
        }
        for run in included:
            if run.record.arm != arm:
                continue
            timeout = float(data.tasks[run.record.task_id].meta["timeout_s"])
            for event in run.record.events:
                if event.get("event") == "gate_resource_sample":
                    wallclock = event.get("wallclock_s")
                    invoker = event.get("invoker")
                    if invoker not in by_invoker:
                        continue
                    by_invoker[str(invoker)].append(
                        float(wallclock) / timeout
                        if isinstance(wallclock, (int, float)) and not isinstance(wallclock, bool)
                        else None
                    )
        infra[arm]["wallclock_timeout_fraction_by_invoker"] = {
            invoker: five_number(values) for invoker, values in by_invoker.items()
        }
        infra[arm]["gate_wallclock_timeout_fraction"] = five_number(by_invoker["gate"])
    sensitivity["execution_infrastructure"] = {
        "per_seat": seat_results, "per_slot_rotation_class": rotations,
        "material_change_firings": sorted(firings), "distributions": infra,
    }

    task_matrix = {
        task: {
            arm: (
                successes[task][arm] / denominators[task][arm]
                if denominators[task][arm] else None
            )
            for arm in ARMS
        }
        for task in sorted(successes)
    }
    caps = _caps(data, coded, removed_tasks, mode=mode)
    experiment_status = "compromised" if caps["compromised"] else "not_compromised"
    retention_failures = {
        arm: [
            {
                "run_id": run.record.run_id,
                "task_id": run.record.task_id,
                **(run.record.retention_failure or {}),
            }
            for run in sorted(included, key=lambda item: item.record.run_id)
            if run.record.arm == arm and run.record.retention_failure is not None
        ]
        for arm in ARMS
    }
    counters = {
        arm: {
            "declaration_excess": sum(
                e.get("event") == "declaration_excess" for r in included if r.record.arm == arm for e in r.record.events
            ),
            "gate_execution_untrusted": sum(
                e.get("event") == "gate_execution_untrusted" for r in included if r.record.arm == arm for e in r.record.events
            ),
            "agent_donecheck_invocations": sum(
                e.get("event") == "donecheck_invocation" and e.get("invoker") == "agent"
                for r in included if r.record.arm == arm for e in r.record.events
            ),
        } for arm in ARMS
    }
    attempt_structure: dict[str, Any] = {}
    by_block: dict[str, list[dict[str, Any]]] = defaultdict(list)
    scoring_run_ids = {run.run_id for run in data.runs}
    for row in data.ledger_rows:
        by_block[str(row.get("block_id"))].append(row)
    for block, rows in sorted(by_block.items()):
        attempt_structure[block] = {
            "attempts": sorted({int(row.get("attempt", 0)) for row in rows}),
            "non_scoring_run_ids": sorted(
                str(row.get("run_id")) for row in rows
                if str(row.get("run_id")) not in scoring_run_ids
            ),
            "scoring_run_ids": sorted(
                str(row.get("run_id")) for row in rows
                if str(row.get("run_id")) in scoring_run_ids
            ),
            "stopped": block in data.stopped_blocks,
            "void_reasons": data.stopped_blocks.get(block, []),
        }
    gaming = gaming_audit_draw(included)
    crosscheck = crosscheck_draw([record.run_id for record in data.runs]) if series == "main" else None
    try:
        pack_sha = subprocess.run(
            ["git", "-C", str(pack), "rev-parse", "HEAD"], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError(f"cannot resolve pack git SHA: {exc}") from exc
    report = {
        "schema_version": 1,
        "series": series,
        "registered_adjudication": registered_adjudication,
        "experiment_status": experiment_status,
        "series_scope": (
            "confirmatory main series" if series == "main"
            else "descriptive only, no α, no pooling with the main series"
        ),
        "provenance": {
            "pack_git_sha": pack_sha, "out_root": out_root.name,
            "adjudication_mode": mode, "image_tag": image,
            "image_id": image_id,
            "image_id_verified_in_this_run": mode == "docker",
        },
        "counter_evidence": {
            "experiment_status": experiment_status,
            "w_below_bplus": primary["estimate"] < 0,
            "gaming_audit_status": "sample drawn; human audit findings are external to this pipeline",
            "disagreements": disagreements,
            "material_change_firings": sorted(firings),
            "retention_failures": retention_failures,
        },
        "outcome_counts": outcome_counts,
        "outcome_rows": [
            {
                "run_id": run.record.run_id,
                "task_id": run.record.task_id,
                "arm": run.record.arm,
                "replicate": run.record.ledger["replicate"],
                "outcome": run.outcome,
                "adjudication_provenance": _adjudication_provenance(run),
                "terminal_adjudication_available": run.terminal is not None,
                "check_bug_candidate": bool(run.candidate_reasons),
                "excluded_by_check_bug_removal": run.record.task_id in removed_tasks,
            }
            for run in sorted(coded, key=lambda item: item.record.run_id)
        ],
        "task_arm_proportions": task_matrix,
        "task_arm_denominators": {
            task: denominators[task] for task in sorted(denominators)
        },
        "primary": primary,
        "secondary_descriptive": secondary,
        "tango_run_level_w_vs_bplus": {
            "pairs": n_pairs, "discordant_w_only": discordant_w,
            "discordant_bplus_only": discordant_bp, "estimate": (discordant_w - discordant_bp) / n_pairs,
            "ci_95": {"lower": tango[0], "upper": tango[1]},
        },
        "h2_first_declaration": _h2(coded, removed_tasks),
        "h3": _h3(data, coded, removed_tasks),
        "sensitivity": sensitivity,
        "caps": caps,
        "retention_failures": retention_failures,
        "evidence_counters": counters,
        "block_reexecution_structure": attempt_structure,
        "check_bug_candidates": candidates,
        "check_bug_removals": sorted(removed_tasks),
        "disagreements": disagreements,
        "draws": {"gaming_audit": gaming, "crosscheck": crosscheck},
        "direction_replication": {
            "crossover_sign": primary["sign"] if series == "crossover" else None,
            "main_sign": primary["sign"] if series == "main" else None,
            "statement": (
                "Main-series sign is reported here; compare the separately emitted crossover sign without pooling."
                if series == "main" else
                "Crossover sign is descriptive; compare it with the separately emitted main-series sign without pooling."
            ),
        },
    }
    return report, gaming, crosscheck


def _fmt(value: Any) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.6g}"
    return str(value)


def markdown_report(report: dict[str, Any]) -> str:
    title_suffix = " NON-REGISTERED DRY RUN" if not report["registered_adjudication"] else ""
    lines = [
        f"# EV-005 {report['series']} analysis{title_suffix}",
        "",
        f"**Scope:** {report['series_scope']}. **Adjudication mode:** `{report['provenance']['adjudication_mode']}`.",
        "",
        "## Counter-evidence first",
        "",
        f"- Experiment status: **{report['experiment_status']}**.",
        f"- Retention failures by arm: `{json.dumps(report['retention_failures'], sort_keys=True)}`.",
        f"- W < B+ descriptively: `{report['counter_evidence']['w_below_bplus']}`.",
        f"- Gaming audit: {report['counter_evidence']['gaming_audit_status']}.",
        f"- Pipeline disagreements: `{report['disagreements']['pipeline']}`.",
        f"- W gate disagreements: `{report['disagreements']['w_gate']}`.",
        f"- Material-change predicate firings: `{report['counter_evidence']['material_change_firings']}`.",
        "",
        "## Outcome counts",
        "",
        "| arm | outcomes |",
        "| --- | --- |",
    ]
    for arm in ARMS:
        lines.append(f"| {arm} | `{json.dumps(report['outcome_counts'][arm], sort_keys=True)}` |")
    lines += ["", "## Task × arm verified-pass proportion", "", "| task | W | B+ | B |", "| --- | ---: | ---: | ---: |"]
    for task, arms in report["task_arm_proportions"].items():
        denominators = report["task_arm_denominators"][task]
        lines.append(
            f"| {task} | {_fmt(arms['W'])} (n={denominators['W']}) | "
            f"{_fmt(arms['B+'])} (n={denominators['B+']}) | "
            f"{_fmt(arms['B'])} (n={denominators['B']}) |"
        )
    primary = report["primary"]
    lines += [
        "", ("## Primary W vs B+" if report["series"] == "main" else "## W vs B+ descriptive contrast"), "",
        f"T = `{primary['T_units']}` 1/3-units; m = `{primary['m_counts']}`; p = `{_fmt(primary['p_value'])}`; "
        f"estimate = `{_fmt(primary['estimate'])}`; permutation CI = `{primary['ci_95']}`.",
        "",
    ]
    if report["series"] == "main":
        if primary["decision_rule"] is not None:
            lines += [primary["decision_rule"], ""]
        lines += [f"**{primary['decision_sentence']}**"]
        if report["experiment_status"] == "compromised":
            lines += [
                "",
                "Per §5 the experiment is reported as compromised; no unqualified primary claim is made.",
            ]
    else:
        lines += [f"**{primary['decision_sentence']}**"]
    lines += [
        "", "## Secondary contrasts (descriptive)", "",
        f"- W vs B: `{report['secondary_descriptive']['W_vs_B']}`",
        f"- B+ vs B: `{report['secondary_descriptive']['Bplus_vs_B']}`",
        "", "## Tango paired run-level interval", "",
        f"`{report['tango_run_level_w_vs_bplus']}`",
        "", "## H-2 first-declaration indicator", "",
        "| arm | stratum | declarations | adjudicated | impossible | failures | failure proportion |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for arm in ARMS:
        overall = report["h2_first_declaration"][arm]
        lines.append(
            f"| {arm} | overall | {overall['declarations']} | {overall['adjudicated']} | "
            f"{overall['adjudication_impossible']} | {overall['first_snapshot_failures']} | "
            f"{_fmt(overall['failure_proportion'])} |"
        )
        for name, values in overall["strata"].items():
            lines.append(
                f"| {arm} | {name} | {values['declarations']} | {values['adjudicated']} | "
                f"{values['adjudication_impossible']} | {values['first_snapshot_failures']} | "
                f"{_fmt(values['failure_proportion'])} |"
            )
    lines += [
        "", "## H-3", "",
        "| arm | attempts mean | attempts distribution | operator interventions |",
        "| --- | ---: | --- | ---: |",
    ]
    for arm in ARMS:
        values = report["h3"][arm]
        lines.append(
            f"| {arm} | {_fmt(values['attempts_mean'])} | "
            f"`{json.dumps(values['attempts_per_run'], sort_keys=True)}` | "
            f"{values['operator_interventions']} |"
        )
    sensitivity = report["sensitivity"]
    lines += [
        "", "## Sensitivity analyses", "",
        "| analysis | n | estimate | sign | p (descriptive where applicable) |",
        "| --- | ---: | ---: | --- | ---: |",
        f"| per-protocol | {sensitivity['per_protocol']['n_tasks']} | "
        f"{_fmt(sensitivity['per_protocol']['estimate'])} | {sensitivity['per_protocol']['sign']} | "
        f"{_fmt(sensitivity['per_protocol']['p_value'])} |",
    ]
    long_drop = sensitivity["drop_t01_t07_t30"]
    if long_drop.get("applicable", True):
        lines.append(
            f"| drop t01/t07/t30 | {long_drop['n_tasks']} | {_fmt(long_drop['estimate'])} | "
            f"{long_drop['sign']} | {_fmt(long_drop['p_value'])} |"
        )
    for repo, values in sensitivity["leave_one_repo_out"].items():
        lines.append(
            f"| leave out {repo} | {values['n_tasks']} | {_fmt(values['estimate'])} | "
            f"{values['sign']} | {_fmt(values['p_value'])} |"
        )
    for name, values in sensitivity["aggregation"].items():
        lines.append(
            f"| {name} | {values['n_tasks']} | {_fmt(values['estimate'])} | "
            f"{values['sign']} | {_fmt(values['p_value'])} |"
        )
    lines += [
        "", "### Execution-infrastructure subsets", "",
        "| factor | subset | blocks | estimate | sign |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    execution = sensitivity["execution_infrastructure"]
    for factor, key in (("seat", "per_seat"), ("rotation", "per_slot_rotation_class")):
        for name, values in execution[key].items():
            lines.append(
                f"| {factor} | {name} | {values['blocks']} | {_fmt(values['estimate'])} | {values['sign']} |"
            )
    lines += [
        "", f"Material-change firings: `{execution['material_change_firings']}`.",
        "", "Per-arm provider-wait and gate-duration distributions:", "",
        "| arm | provider_wait_s | gate wallclock / timeout_s |",
        "| --- | --- | --- |",
    ]
    for arm in ARMS:
        distributions = execution["distributions"][arm]
        gate_value = (
            f"`{json.dumps(distributions['gate_wallclock_timeout_fraction'], sort_keys=True)}`"
            if arm == "W" else "n/a (no gate in this arm)"
        )
        lines.append(
            f"| {arm} | `{json.dumps(distributions['provider_wait_s'], sort_keys=True)}` | "
            f"{gate_value} |"
        )
    lines += [
        "", "All donecheck resource samples, separated by invoker:", "",
        "| arm | invoker | wallclock / timeout_s |",
        "| --- | --- | --- |",
    ]
    for arm in ARMS:
        by_invoker = execution["distributions"][arm]["wallclock_timeout_fraction_by_invoker"]
        for invoker in ("agent", "gate", "pipeline"):
            lines.append(
                f"| {arm} | {invoker} | `{json.dumps(by_invoker[invoker], sort_keys=True)}` |"
            )
    lines += [
        "", "## Caps, voids, excess declarations, and untrusted executions", "",
        "| compromised flag | fired |",
        "| --- | --- |",
    ]
    for name, fired in report["caps"]["compromised_flags"].items():
        lines.append(f"| {name} | {fired} |")
    if report["caps"]["retention_failure_cap_note"] is not None:
        lines += ["", report["caps"]["retention_failure_cap_note"]]
    lines += [
        "", f"Voids, abort rates, and retention-failure rates: `{json.dumps(report['caps'], sort_keys=True)}`",
        "", "| arm | void rows | operator abort rate | retention failure rate | declaration excess | gate untrusted | agent donecheck invocations |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for arm in ARMS:
        counters = report["evidence_counters"][arm]
        lines.append(
            f"| {arm} | {report['caps']['voids_per_arm'][arm]} | "
            f"{_fmt(report['caps']['operator_abort_rates'][arm])} | "
            f"{_fmt(report['caps']['retention_failure_rates'][arm])} | "
            f"{counters['declaration_excess']} | {counters['gate_execution_untrusted']} | "
            f"{counters['agent_donecheck_invocations']} |"
        )
    lines += [
        "", "### Stopped blocks", "",
        "| block | void reasons |",
        "| --- | --- |",
    ]
    for stopped in report["caps"]["stopped_blocks"]:
        lines.append(
            f"| {stopped['block_id']} | `{json.dumps(stopped['void_reasons'], sort_keys=True)}` |"
        )
    if not report["caps"]["stopped_blocks"]:
        lines.append("| — | none |")
    lines += [
        "", "### Retention failures", "",
        "| arm | run | task | stage | error |",
        "| --- | --- | --- | --- | --- |",
    ]
    for arm in ARMS:
        for failure in report["retention_failures"][arm]:
            lines.append(
                f"| {arm} | {failure['run_id']} | {failure['task_id']} | "
                f"{failure['stage']} | `{failure['error']}` |"
            )
    if not any(report["retention_failures"].values()):
        lines.append("| — | — | — | — | none |")
    lines += [
        "", "## Check-bug candidates and disagreements", "",
        "| run | task | reasons |",
        "| --- | --- | --- |",
    ]
    for candidate in report["check_bug_candidates"]:
        lines.append(
            f"| {candidate['run_id']} | {candidate['task_id']} | "
            f"`{json.dumps(candidate['reasons'], sort_keys=True)}` |"
        )
    if not report["check_bug_candidates"]:
        lines.append("| — | — | none |")
    lines += [
        "", f"Disagreements: `{json.dumps(report['disagreements'], sort_keys=True)}`",
        "", "## Block re-execution structure", "",
        "| block | attempts | scoring runs | non-scoring runs |",
        "| --- | --- | ---: | ---: |",
    ]
    for block, values in report["block_reexecution_structure"].items():
        lines.append(
            f"| {block} | `{values['attempts']}` | {len(values['scoring_run_ids'])} | "
            f"{len(values['non_scoring_run_ids'])} |"
        )
    lines += ["", "## Sealed draws", ""]
    for arm in ARMS:
        draw = report["draws"]["gaming_audit"][arm]
        lines.append(
            f"- {arm}: seed `{draw['seed']}`, sample `{[row['run_id'] for row in draw['runs']]}`."
        )
    if report["draws"]["crosscheck"] is not None:
        crosscheck = report["draws"]["crosscheck"]
        lines.append(
            f"- Host cross-check: seed `{crosscheck['seed']}`, sample `{crosscheck['run_ids']}`."
        )
    lines += [
        "", "## Direction replication", "",
        report["direction_replication"]["statement"],
        "",
    ]
    return "\n".join(lines)


def write_reports(report_dir: Path, report: dict[str, Any]) -> None:
    (report_dir / "analysis-report.json").write_text(
        json.dumps(report, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    (report_dir / "analysis-report.md").write_text(markdown_report(report), encoding="utf-8")
