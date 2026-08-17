from __future__ import annotations

import itertools
import math
from pathlib import Path
from fractions import Fraction

import pytest

from stats import (
    exact_contrast, five_number, generic_signflip_contrast, load_sealed_tail_prob,
    permutation_ci, tango_score_interval,
)


PACK = Path(__file__).resolve().parents[3]


def brute_tail(values):
    observed = abs(sum(values))
    totals = [abs(sum(sign * value for sign, value in zip(signs, values)))
              for signs in itertools.product((-1, 1), repeat=len(values))]
    return sum(value >= observed for value in totals) / len(totals)


def test_sealed_tail_prob_import_and_hand_computed_case():
    tail_prob = load_sealed_tail_prob(PACK)
    values = [1, 2, -1]
    result = exact_contrast(values, tail_prob)
    # Kills a strict-tail (`>` rather than registered inclusive `>=`) implementation,
    # which returns 0.25 instead of the exact two-sided 0.75 for this vector.
    assert result["p_value"] == pytest.approx(0.75, abs=1e-12)
    assert result["p_value"] == brute_tail(values)
    assert result["estimate"] == pytest.approx(2 / 9, abs=1e-12)


def brute_ci(values):
    accepted = []
    for step in range(-300, 301):
        delta = Fraction(step, 300)
        centered = [Fraction(value, 3) - delta for value in values]
        observed = abs(sum(centered))
        totals = [abs(sum(sign * value for sign, value in zip(signs, centered)))
                  for signs in itertools.product((-1, 1), repeat=len(values))]
        hits = sum(value >= observed for value in totals)
        if Fraction(hits, len(totals)) > Fraction(1, 20):
            accepted.append(delta)
    return float(min(accepted)), float(max(accepted))


def test_permutation_ci_matches_brute_force_and_contains_estimate():
    values = [3, 2, -1, 1, 0, 2]
    result = permutation_ci(values)
    # Kills an off-by-one grid scan that omits either sealed endpoint: the upper
    # endpoint is exactly 1.0 while the lower endpoint is exactly -100/300.
    assert result["lower"] == pytest.approx(-1 / 3, abs=1e-12)
    assert result["upper"] == pytest.approx(1.0, abs=1e-12)
    assert (result["lower"], result["upper"]) == pytest.approx(brute_ci(values))
    estimate = sum(values) / (3 * len(values))
    assert result["lower"] <= estimate <= result["upper"]


def test_permutation_ci_degenerate_case_collapses_to_point():
    result = permutation_ci([1] * 6)
    assert result["lower"] == pytest.approx(1 / 3)
    assert result["upper"] == pytest.approx(1 / 3)


def test_tango_published_asymmetric_golden_value():
    # Newcombe's published TANGO spreadsheet example: n=50, b=12, c=2,
    # point estimate .20 and 95% Tango interval .0611 to .3447.
    # The high-precision pin kills both a Wald interval substitution and a b/c
    # direction swap; neither produces these asymmetric score roots.
    assert tango_score_interval(50, 12, 2) == pytest.approx(
        (0.06111240618634402, 0.3447087482821486), abs=1e-12,
    )


def test_tango_symmetric_case_is_symmetric():
    lower, upper = tango_score_interval(50, 10, 10)
    assert lower == pytest.approx(-upper, abs=1e-12)
    assert lower < 0 < upper


def test_tango_zero_discordant_closed_form():
    # Tango (1998) Appendix III boundary case b=c=0 gives symmetric limits
    # z^2/(n+z^2), directly hand-checkable from the score equation.
    lower, upper = tango_score_interval(30, 0, 0)
    z = 1.959963984540054
    expected = z * z / (30 + z * z)
    assert (lower, upper) == pytest.approx((-expected, expected), abs=1e-10)


def test_generic_signflip_value_pin_rejects_one_sided_tail():
    values = [Fraction(1, 2), Fraction(1, 3), Fraction(-1, 4), Fraction(1, 5)]
    result = generic_signflip_contrast(values)
    # Kills a plausible one-sided sensitivity test (0.1875): the registered
    # absolute two-sided sign-flip tail is 6/16 = 0.375.
    assert result["estimate"] == pytest.approx(47 / 240, abs=1e-12)
    assert result["p_value"] == pytest.approx(0.375, abs=1e-12)


def test_five_number_uses_linear_interpolated_quartiles():
    result = five_number([0, 10, 20, 100, None])
    # Kills Tukey hinges (q1=5, q3=60) and a null-as-zero implementation.
    assert result == {
        "null_count": 1,
        "min": 0.0,
        "q1": pytest.approx(7.5, abs=1e-12),
        "median": pytest.approx(15.0, abs=1e-12),
        "q3": pytest.approx(40.0, abs=1e-12),
        "max": 100.0,
    }
