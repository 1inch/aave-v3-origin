/**
 * Mirrors DefaultReserveInterestRateStrategyV2.calculateInterestRates in float math.
 * All rates and ratios are expressed in percent (0-100 scale).
 * Source: src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol
 */
export type RateParams = {
  /** optimal usage ratio in % (kink point) */
  optimalUsageRatio: number;
  /** base variable borrow rate in % */
  baseRate: number;
  /** slope below the kink in % */
  slope1: number;
  /** slope above the kink in % */
  slope2: number;
};

/** Variable borrow rate in % for a given utilization in %. */
export function borrowRate(utilization: number, p: RateParams): number {
  if (utilization <= 0) return p.baseRate;
  if (utilization <= p.optimalUsageRatio) {
    return p.baseRate + (p.slope1 * utilization) / p.optimalUsageRatio;
  }
  const excess = (utilization - p.optimalUsageRatio) / (100 - p.optimalUsageRatio);
  return p.baseRate + p.slope1 + p.slope2 * excess;
}

/**
 * Supply (liquidity) rate in %: borrowRate × supplyUsage × (1 − reserveFactor).
 * With no unbacked/deficit, supply usage equals borrow usage.
 */
export function supplyRate(utilization: number, p: RateParams, reserveFactorPct: number): number {
  return (borrowRate(utilization, p) * utilization * (1 - reserveFactorPct / 100)) / 100;
}
