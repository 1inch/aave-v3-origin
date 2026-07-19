import { describe, it, expect } from 'vitest';
import { simulateLiquidation } from '../liquidation';
import type { LiquidationInput } from '../liquidation';

const base: LiquidationInput = {
  collateral: 6000,
  debt: 5000,
  ltPct: 80,
  bonusPct: 5,
  protocolFeePct: 10,
  debtToCover: 2000,
};

describe('close factor (LiquidationLogic v3.3 rules)', () => {
  it('rejects liquidation when HF >= 1', () => {
    const r = simulateLiquidation({ ...base, collateral: 8000, debt: 6000 });
    // HF = 8000*0.8/6000 = 1.066…
    expect(r.liquidatable).toBe(false);
  });

  it('applies the 50% position-wide close factor for large, mildly unhealthy positions', () => {
    // HF = 6000*0.8/5000 = 0.96 (> 0.95), both sides >= $2,000
    const r = simulateLiquidation(base);
    expect(r.liquidatable).toBe(true);
    expect(r.fullCloseFactor).toBe(false);
    expect(r.maxLiquidatableDebt).toBe(2500);
  });

  it('allows 100% when HF <= CLOSE_FACTOR_HF_THRESHOLD (0.95)', () => {
    // HF = 5200*0.83/5000 = 0.8632
    const r = simulateLiquidation({ ...base, collateral: 5200, debt: 5000, ltPct: 83 });
    expect(r.fullCloseFactor).toBe(true);
    expect(r.maxLiquidatableDebt).toBe(5000);
  });

  it('allows 100% for small positions (< $2,000 threshold), even with HF > 0.95', () => {
    // HF = 1900*0.77/1500 = 0.9753 > 0.95, but collateral < $2,000
    const r = simulateLiquidation({ ...base, collateral: 1900, debt: 1500, ltPct: 77 });
    expect(r.liquidatable).toBe(true);
    expect(r.fullCloseFactor).toBe(true);
    expect(r.maxLiquidatableDebt).toBe(1500);
  });

  it('clamps debtToCover to the maximum liquidatable amount', () => {
    const r = simulateLiquidation({ ...base, debtToCover: 99999 });
    expect(r.actualDebtLiquidated).toBe(2500);
  });
});

describe('bonus & protocol fee split', () => {
  it('seizes debt × (1 + bonus) and fees the bonus portion', () => {
    // HF = 4000*0.45/2000 = 0.9 -> full close factor
    const r = simulateLiquidation({
      collateral: 4000,
      debt: 2000,
      ltPct: 45,
      bonusPct: 5,
      protocolFeePct: 10,
      debtToCover: 1000,
    });
    expect(r.actualDebtLiquidated).toBeCloseTo(1000, 10);
    expect(r.collateralSeized).toBeCloseTo(1050, 10);
    expect(r.bonusPortion).toBeCloseTo(50, 10);
    expect(r.protocolFee).toBeCloseTo(5, 10);
    expect(r.toLiquidator).toBeCloseTo(1045, 10);
    expect(r.liquidatorProfit).toBeCloseTo(45, 10);
    expect(r.dustViolation).toBe(false); // leftovers: 1000 debt / 2950 collateral
  });

  it('caps the seizure at the available collateral and back-computes the debt', () => {
    // HF = 5200*0.83/5000 = 0.8632, full CF; covering all debt wants 5250 > 5200
    const r = simulateLiquidation({
      collateral: 5200,
      debt: 5000,
      ltPct: 83,
      bonusPct: 5,
      protocolFeePct: 10,
      debtToCover: 5000,
    });
    expect(r.collateralSeized).toBeCloseTo(5200, 10);
    expect(r.actualDebtLiquidated).toBeCloseTo(5200 / 1.05, 6);
    expect(r.leftoverCollateral).toBeCloseTo(0, 10);
  });
});

describe('dust rule (MustNotLeaveDust, MIN_LEFTOVER_BASE = $1,000)', () => {
  it('flags leftovers strictly between 0 and $1,000 on either side', () => {
    // full CF (HF 0.8632); cover 4500 -> leftover debt 500, leftover collateral 475
    const r = simulateLiquidation({
      collateral: 5200,
      debt: 5000,
      ltPct: 83,
      bonusPct: 5,
      protocolFeePct: 10,
      debtToCover: 4500,
    });
    expect(r.leftoverDebt).toBeCloseTo(500, 10);
    expect(r.leftoverCollateral).toBeCloseTo(475, 10);
    expect(r.dustViolation).toBe(true);
  });

  it('accepts leftovers >= $1,000 on both sides', () => {
    const r = simulateLiquidation(base); // covers 2000 -> leftovers 3000 debt / 3900 collateral
    expect(r.dustViolation).toBe(false);
  });

  it('accepts full liquidation of one side (zero leftover)', () => {
    const r = simulateLiquidation({
      collateral: 5200,
      debt: 5000,
      ltPct: 83,
      bonusPct: 5,
      protocolFeePct: 10,
      debtToCover: 5000,
    });
    expect(r.dustViolation).toBe(false);
  });
});

describe('bad debt detection', () => {
  it('creates a deficit when collateral is consumed but debt remains', () => {
    const r = simulateLiquidation({
      collateral: 5200,
      debt: 5000,
      ltPct: 83,
      bonusPct: 5,
      protocolFeePct: 10,
      debtToCover: 5000,
    });
    // seizure capped at 5200 -> repaid ~4952 -> ~48 debt left with zero collateral
    expect(r.createsBadDebt).toBe(true);
    expect(r.leftoverDebt).toBeGreaterThan(0);
  });

  it('does not flag bad debt when collateral remains', () => {
    expect(simulateLiquidation(base).createsBadDebt).toBe(false);
  });
});
