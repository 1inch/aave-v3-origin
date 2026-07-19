import { describe, it, expect } from 'vitest';
import { borrowRate, supplyRate } from '../interestRate';
import type { RateParams } from '../interestRate';

const P: RateParams = { optimalUsageRatio: 90, baseRate: 0, slope1: 6, slope2: 75 };

describe('borrowRate (DefaultReserveInterestRateStrategyV2 model)', () => {
  it('returns the base rate at zero utilization', () => {
    expect(borrowRate(0, P)).toBe(0);
    expect(borrowRate(0, { ...P, baseRate: 2 })).toBe(2);
  });

  it('scales linearly with slope1 below the kink', () => {
    expect(borrowRate(45, P)).toBeCloseTo(3, 10); // half of optimal -> half of slope1
    expect(borrowRate(90, P)).toBeCloseTo(6, 10);
  });

  it('is continuous at the optimal usage ratio (the kink)', () => {
    const just = borrowRate(P.optimalUsageRatio, P);
    const above = borrowRate(P.optimalUsageRatio + 1e-9, P);
    expect(above).toBeCloseTo(just, 6);
  });

  it('reaches base + slope1 + slope2 at 100% utilization', () => {
    expect(borrowRate(100, P)).toBeCloseTo(81, 10);
    expect(borrowRate(100, { ...P, baseRate: 1 })).toBeCloseTo(82, 10);
  });

  it('prices the excess ratio with slope2 above the kink', () => {
    // halfway between kink (90) and 100 -> excess 0.5 -> slope1 + slope2/2
    expect(borrowRate(95, P)).toBeCloseTo(6 + 37.5, 10);
  });

  it('is monotonically non-decreasing in utilization', () => {
    let prev = -Infinity;
    for (let u = 0; u <= 100; u += 0.5) {
      const r = borrowRate(u, P);
      expect(r).toBeGreaterThanOrEqual(prev);
      prev = r;
    }
  });
});

describe('supplyRate', () => {
  it('is borrowRate × utilization × (1 − reserveFactor)', () => {
    const u = 80;
    expect(supplyRate(u, P, 15)).toBeCloseTo((borrowRate(u, P) * 0.8 * 0.85), 10);
  });

  it('is zero at zero utilization and reduced by the reserve factor', () => {
    expect(supplyRate(0, P, 15)).toBe(0);
    expect(supplyRate(90, P, 0)).toBeGreaterThan(supplyRate(90, P, 50));
  });

  it('never exceeds the borrow rate', () => {
    for (let u = 0; u <= 100; u += 5) {
      expect(supplyRate(u, P, 10)).toBeLessThanOrEqual(borrowRate(u, P) + 1e-12);
    }
  });
});
