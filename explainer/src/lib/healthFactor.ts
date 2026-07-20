/**
 * Health factor & borrowing power math.
 * Source: src/contracts/protocol/libraries/logic/GenericLogic.sol (calculateUserAccountData)
 */

/** HF = collateral × LT / debt. Infinity when there is no debt. */
export function healthFactor(collateral: number, ltPct: number, debt: number): number {
  if (debt === 0) return Infinity;
  return (collateral * (ltPct / 100)) / debt;
}

/** Maximum total debt the position can carry, from the aggregate LTV. */
export function borrowCapacity(collateral: number, ltvPct: number): number {
  return (collateral * ltvPct) / 100;
}

/** Additional borrowable amount (never negative). */
export function borrowHeadroom(collateral: number, ltvPct: number, debt: number): number {
  return Math.max(0, borrowCapacity(collateral, ltvPct) - debt);
}

/**
 * How far (in %) the collateral value can fall before HF hits 1.
 * Returns 0 when already liquidatable, 100 with no debt.
 */
export function priceDropToLiquidation(collateral: number, ltPct: number, debt: number): number {
  if (debt === 0) return 100;
  return Math.max(0, (1 - debt / (collateral * (ltPct / 100))) * 100);
}
