import { describe, it, expect } from 'vitest';
import {
  healthFactor,
  borrowCapacity,
  borrowHeadroom,
  priceDropToLiquidation,
} from '../healthFactor';

describe('healthFactor', () => {
  it('is Infinity with no debt', () => {
    expect(healthFactor(10000, 83, 0)).toBe(Infinity);
  });

  it('equals collateral × LT / debt', () => {
    expect(healthFactor(10000, 83, 6000)).toBeCloseTo(1.3833, 3);
    expect(healthFactor(10000, 80, 8000)).toBeCloseTo(1, 10);
  });

  it('drops below 1 when debt exceeds LT-weighted collateral', () => {
    expect(healthFactor(10000, 80, 8001)).toBeLessThan(1);
  });
});

describe('borrow capacity & headroom', () => {
  it('caps borrows at collateral × LTV', () => {
    expect(borrowCapacity(10000, 80)).toBe(8000);
  });

  it('headroom is capacity minus debt, floored at zero', () => {
    expect(borrowHeadroom(10000, 80, 6000)).toBe(2000);
    expect(borrowHeadroom(10000, 80, 9000)).toBe(0);
  });
});

describe('priceDropToLiquidation', () => {
  it('is 100% with no debt', () => {
    expect(priceDropToLiquidation(10000, 83, 0)).toBe(100);
  });

  it('is 0 when already liquidatable', () => {
    expect(priceDropToLiquidation(10000, 80, 9000)).toBe(0);
  });

  it('matches the HF=1 boundary', () => {
    // HF = 1.25 -> collateral can fall 20% before HF hits 1
    expect(priceDropToLiquidation(10000, 80, 6400)).toBeCloseTo(20, 10);
  });
});
