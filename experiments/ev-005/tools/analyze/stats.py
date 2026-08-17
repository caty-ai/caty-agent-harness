"""Pre-registered EV-005 statistical machinery."""

from __future__ import annotations

from collections import Counter
from fractions import Fraction
import importlib.util
import itertools
import math
from pathlib import Path
from statistics import NormalDist
from typing import Iterable


def load_sealed_tail_prob(pack: Path):
    path = pack / "tools" / "mdd-sim.py"
    spec = importlib.util.spec_from_file_location("ev005_sealed_mdd_sim", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import sealed tail_prob from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.tail_prob


def sign(value: float | Fraction) -> str:
    if value > 0:
        return "positive"
    if value < 0:
        return "negative"
    return "zero"


def exact_contrast(d_units: list[int], tail_prob) -> dict[str, object]:
    counts = tuple(sum(abs(value) == magnitude for value in d_units) for magnitude in (1, 2, 3))
    total = sum(d_units)
    p_value = tail_prob(counts, abs(total))
    estimate = total / (3 * len(d_units)) if d_units else 0.0
    return {
        "n_tasks": len(d_units),
        "difference_units": d_units,
        "m_counts": {"abs_1": counts[0], "abs_2": counts[1], "abs_3": counts[2]},
        "T_units": abs(total),
        "estimate": estimate,
        "sign": sign(estimate),
        "p_value": p_value,
    }


def generic_signflip_contrast(differences: list[Fraction]) -> dict[str, object]:
    """Exact grouped sign-flip result for sensitivity differences off the 1/3 grid."""
    if not differences:
        return {"n_tasks": 0, "estimate": None, "sign": "unavailable", "p_value": None}
    p_value = _centered_signflip_p(differences, Fraction(0))
    estimate = sum(differences, Fraction(0)) / len(differences)
    return {
        "n_tasks": len(differences),
        "estimate": float(estimate),
        "sign": sign(estimate),
        "p_value": float(p_value),
    }


def _centered_signflip_p(differences: list[Fraction], delta: Fraction) -> Fraction:
    centered_counts = Counter(value - delta for value in differences)
    groups = sorted(centered_counts.items(), key=lambda item: item[0])
    observed = abs(sum((value - delta for value in differences), Fraction(0)))
    hits = 0
    total = 0
    ranges = [range(count + 1) for _, count in groups]
    for selected in itertools.product(*ranges):
        statistic = Fraction(0)
        weight = 1
        for (value, count), positive_count in zip(groups, selected):
            statistic += (2 * positive_count - count) * value
            weight *= math.comb(count, positive_count)
        total += weight
        # Fraction comparison is exact and therefore stronger than the sealed
        # 1e-12 floating tolerance requested for statistic comparisons.
        if abs(statistic) >= observed:
            hits += weight
    return Fraction(hits, total)


def permutation_ci(d_units: list[int]) -> dict[str, object]:
    """Invert exact grouped sign flips on the sealed 1/300 grid.

    The grid includes both endpoints and the returned interval is the closure
    of grid points with exact p > 0.05.  In the common degenerate all-equal
    case with at least six tasks, only the point estimate is accepted and the
    interval collapses to that point.  For very small degenerate samples the
    discrete test can accept the full grid; this is intentional exact-test
    edge behavior, not a floating-point special case.
    """
    if not d_units:
        raise ValueError("permutation CI needs at least one paired task")
    if any(type(value) is not int or value < -3 or value > 3 for value in d_units):
        raise ValueError("permutation CI differences must be integer 1/3-units in [-3, 3]")

    # Precompute the exact grouped sign configurations once.  For a grid point
    # delta = step/300 and task difference d = unit/3, multiplying the signed
    # statistic by 300 gives
    #   100 * sum(sign_i * unit_i) - step * sum(sign_i).
    # Group multiplicities contribute exactly product(comb(n_v, k_v)).
    groups = sorted(Counter(d_units).items())
    configurations: Counter[tuple[int, int]] = Counter()
    ranges = [range(count + 1) for _, count in groups]
    for selected in itertools.product(*ranges):
        signed_units = 0
        signed_count = 0
        weight = 1
        for (unit, count), positive_count in zip(groups, selected):
            coefficient = 2 * positive_count - count
            signed_units += coefficient * unit
            signed_count += coefficient
            weight *= math.comb(count, positive_count)
        configurations[(signed_units, signed_count)] += weight

    total_weight = 1 << len(d_units)
    observed_units = sum(d_units)
    accepted: list[int] = []
    for step in range(-300, 301):
        observed = abs(100 * observed_units - step * len(d_units))
        hits = sum(
            weight for (signed_units, signed_count), weight in configurations.items()
            if abs(100 * signed_units - step * signed_count) >= observed
        )
        if 20 * hits > total_weight:
            accepted.append(step)
    if not accepted:
        return {"lower": None, "upper": None, "grid_step": 1 / 300, "accepted_points": 0}
    return {
        "lower": min(accepted) / 300,
        "upper": max(accepted) / 300,
        "grid_step": 1 / 300,
        "accepted_points": len(accepted),
    }


def _tango_score(theta: float, n: int, b: int, c: int) -> float:
    """Tango (1998) efficient score, oriented as (b-c)/n."""
    a = 2.0 * n
    coef_b = -b - c + (2 * n - b + c) * theta
    coef_c = -c * theta * (1.0 - theta)
    discriminant = max(0.0, coef_b * coef_b - 4.0 * a * coef_c)
    p21 = (math.sqrt(discriminant) - coef_b) / (2.0 * a)
    variance_term = n * (2.0 * p21 + theta * (1.0 - theta))
    numerator = b - c - n * theta
    if variance_term <= 0.0:
        return math.copysign(math.inf, numerator) if numerator else 0.0
    return numerator / math.sqrt(variance_term)


def tango_score_interval(n: int, b: int, c: int, confidence: float = 0.95) -> tuple[float, float]:
    """Tango (1998) score CI for a paired marginal-proportion difference.

    ``b`` counts pairs (first=1, second=0), ``c`` counts (first=0,
    second=1), so the point estimate is ``(b-c)/n``.  Limits solve the
    efficient-score equations by deterministic bisection.  This formulation
    remains defined when either or both discordant cells are zero.
    """
    if n <= 0 or min(b, c) < 0 or b + c > n:
        raise ValueError("invalid paired 2x2 counts")
    z = NormalDist().inv_cdf(0.5 + confidence / 2.0)
    estimate = (b - c) / n

    def root(left: float, right: float, target: float) -> float:
        for _ in range(100):
            middle = (left + right) / 2.0
            value = _tango_score(middle, n, b, c)
            if value > target:
                left = middle
            else:
                right = middle
        return (left + right) / 2.0

    lower_edge = -1.0 + 1e-14
    upper_edge = 1.0 - 1e-14
    lower = -1.0 if _tango_score(lower_edge, n, b, c) < z else root(lower_edge, estimate, z)
    # For the upper equation, -score decreases from positive at the upper
    # boundary to zero at the estimate; reverse the score sign for bisection.
    def upper_root(left: float, right: float) -> float:
        for _ in range(100):
            middle = (left + right) / 2.0
            value = -_tango_score(middle, n, b, c)
            if value < z:
                left = middle
            else:
                right = middle
        return (left + right) / 2.0

    upper = 1.0 if -_tango_score(upper_edge, n, b, c) < z else upper_root(estimate, upper_edge)
    return lower, upper


def paired_binary_counts(pairs: Iterable[tuple[bool, bool]]) -> tuple[int, int, int]:
    pairs = list(pairs)
    b = sum(first and not second for first, second in pairs)
    c = sum(second and not first for first, second in pairs)
    return len(pairs), b, c


def five_number(values: Iterable[float | int | None]) -> dict[str, float | int | None]:
    raw = list(values)
    clean = sorted(float(value) for value in raw if isinstance(value, (int, float)) and not isinstance(value, bool))
    result: dict[str, float | int | None] = {"null_count": len(raw) - len(clean)}
    if not clean:
        result.update({"min": None, "q1": None, "median": None, "q3": None, "max": None})
        return result

    def quantile(probability: float) -> float:
        position = probability * (len(clean) - 1)
        low = math.floor(position)
        high = math.ceil(position)
        if low == high:
            return clean[low]
        fraction = position - low
        return clean[low] * (1.0 - fraction) + clean[high] * fraction

    result.update({
        "min": clean[0], "q1": quantile(0.25), "median": quantile(0.5),
        "q3": quantile(0.75), "max": clean[-1],
    })
    return result
