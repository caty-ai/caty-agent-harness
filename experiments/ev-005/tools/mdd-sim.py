#!/usr/bin/env python3
"""EV-005 MDD simulation for the k=3 paired-proportion design (analysis-plan r2 §4).

Sealed with the manifest; stdlib-only (no third-party dependencies) so the sealed
environment can re-run it byte-identically. Seed below is the sealed seed.

Design simulated
----------------
n = 30 tasks, k = 3 runs per task x arm cell. Task-level outcome per arm =
verified_pass proportion over k runs. Primary test = exact paired permutation
(sign-flip) test on task-level proportion differences d_i = pW_i - pB+_i,
statistic T = mean(d_i), two-sided alpha = 0.05.

Operationalization note (pins §4's wording for the simulation): under the sharp
null, arm labels within a task are exchangeable and runs are independent fresh
replicas conditional on the task, so independent per-task sign flips are exact
regardless of between-task (repo) correlation; repo structure enters the design
as the block covariate carried by §6-3 (leave-one-repo-out). With k = 3 each
d_i lives on the 1/3 grid in [-1, 1], so the full 2^30 flip distribution of
sum(s_i * d_i) is computed EXACTLY by integer convolution (no Monte Carlo in
the test itself; the seed governs data generation only).

Data-generating scenarios (all pre-registered here)
---------------------------------------------------
Baseline B+ per-task true success probabilities p_i ~ Beta(mu*c, (1-mu)*c)
  mu in {0.20, 0.35, 0.50, 0.65, 0.80}   (baseline mean)
  c  in {2, 6}                            (heterogeneity: 2 = high, 6 = moderate)
Treatment: W per-task probability = min(p_i + delta, 1.0), homogeneous additive
  delta in {0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35}
  (delta = 0.00 rows validate type-I control; ceiling clipping is reported as
  the realized mean shift E[min(p+delta,1) - p], so near-ceiling rows are honest.)
nsim = 2000 simulated experiments per scenario point.
MDD(mu, c) = smallest delta with power >= 0.80.
"""

import random
from fractions import Fraction

SEED = 20260815
N_TASKS = 30
K = 3
ALPHA = 0.05
NSIM = 2000
MUS = [0.20, 0.35, 0.50, 0.65, 0.80]
CONCS = [2.0, 6.0]
DELTAS = [0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35]
POWER_TARGET = 0.80

_dist_cache = {}


def tail_prob(counts, t_obs_units):
    """Exact P(|T| >= |t_obs|) under independent sign flips.

    counts = (m1, m2, m3): number of tasks with |d_i| = v/3 for v = 1, 2, 3
    (zero-difference tasks contribute nothing). t_obs_units = |sum d_i| in 1/3
    units (integer). Returns a float in (0, 1].
    """
    if t_obs_units == 0:
        return 1.0
    key = counts
    dist = _dist_cache.get(key)
    if dist is None:
        # dist maps sum (in 1/3 units) -> number of sign assignments (integer).
        dist = {0: 1}
        for value, m in zip((1, 2, 3), counts):
            for _ in range(m):
                nxt = {}
                for s, w in dist.items():
                    for sv in (s + value, s - value):
                        nxt[sv] = nxt.get(sv, 0) + w
                dist = nxt
        _dist_cache[key] = dist
    total = sum(dist.values())
    hits = sum(w for s, w in dist.items() if abs(s) >= t_obs_units)
    return float(Fraction(hits, total))


def simulate_point(rng, mu, conc, delta):
    """Return (power_or_alpha, realized_mean_shift) at one scenario point."""
    a, b = mu * conc, (1.0 - mu) * conc
    rejections = 0
    shift_accum = 0.0
    for _ in range(NSIM):
        m = [0, 0, 0]  # counts of |d| = 1/3, 2/3, 3/3
        t_units = 0
        shift = 0.0
        for _ in range(N_TASKS):
            p = rng.betavariate(a, b)
            pw = min(p + delta, 1.0)
            shift += pw - p
            xb = sum(1 for _ in range(K) if rng.random() < p)
            xw = sum(1 for _ in range(K) if rng.random() < pw)
            d = xw - xb  # in 1/3 units, integer in [-3, 3]
            if d != 0:
                m[abs(d) - 1] += 1
                t_units += d
        if tail_prob(tuple(m), abs(t_units)) <= ALPHA:
            rejections += 1
        shift_accum += shift / N_TASKS
    return rejections / NSIM, shift_accum / NSIM


def main():
    rng = random.Random(SEED)
    print("| baseline mean (B+) | heterogeneity c | delta | realized mean shift | power |")
    print("| --- | --- | --- | --- | --- |")
    mdd = {}
    for mu in MUS:
        for conc in CONCS:
            for delta in DELTAS:
                power, shift = simulate_point(rng, mu, conc, delta)
                row_power = f"{power:.3f}" + (" (type-I)" if delta == 0.0 else "")
                print(f"| {mu:.2f} | {conc:g} | {delta:.2f} | {shift:+.3f} | {row_power} |")
                if delta > 0.0 and (mu, conc) not in mdd and power >= POWER_TARGET:
                    mdd[(mu, conc)] = delta
    print()
    print("| baseline mean (B+) | heterogeneity c | MDD (power >= 0.80) |")
    print("| --- | --- | --- |")
    for mu in MUS:
        for conc in CONCS:
            v = mdd.get((mu, conc))
            print(f"| {mu:.2f} | {conc:g} | {('%.2f' % v) if v else '> 0.35'} |")
    print()
    print(f"(seed = {SEED}; nsim = {NSIM}; n = {N_TASKS}; k = {K}; alpha = {ALPHA} two-sided; "
          "test = exact sign-flip permutation via integer convolution)")


if __name__ == "__main__":
    main()
