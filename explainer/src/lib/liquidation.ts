/**
 * Liquidation close-factor / bonus / dust math for a simplified single-collateral,
 * single-debt position priced in base currency (USD).
 *
 * Mirrors the v3.3+ rules in src/contracts/protocol/libraries/logic/LiquidationLogic.sol:
 *   DEFAULT_LIQUIDATION_CLOSE_FACTOR = 50%
 *   CLOSE_FACTOR_HF_THRESHOLD        = 0.95e18
 *   MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD = 2000e8  ($2,000)
 *   MIN_LEFTOVER_BASE                = threshold / 2 ($1,000)
 *
 * Documented simplifications (kept deliberately — this is a teaching model):
 * float math instead of ray/wad, one collateral + one debt reserve, no eMode
 * LT/bonus override, prices fixed at 1.
 */

export const CLOSE_FACTOR_HF_THRESHOLD = 0.95;
export const MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD = 2000;
export const MIN_LEFTOVER_BASE = MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD / 2;
export const DEFAULT_LIQUIDATION_CLOSE_FACTOR = 0.5;

export type LiquidationInput = {
  /** borrower's collateral on this reserve, in $ */
  collateral: number;
  /** borrower's debt on this reserve (= total debt in this model), in $ */
  debt: number;
  /** liquidation threshold in % */
  ltPct: number;
  /** liquidation bonus in % (e.g. 5 = liquidator receives 105%) */
  bonusPct: number;
  /** protocol fee in % of the bonus portion */
  protocolFeePct: number;
  /** liquidator-chosen debtToCover, in $ */
  debtToCover: number;
};

export type LiquidationResult = {
  healthFactor: number;
  liquidatable: boolean;
  /** true when the 100% close factor applies */
  fullCloseFactor: boolean;
  maxLiquidatableDebt: number;
  actualDebtLiquidated: number;
  collateralSeized: number;
  bonusPortion: number;
  protocolFee: number;
  toLiquidator: number;
  liquidatorProfit: number;
  leftoverDebt: number;
  leftoverCollateral: number;
  /** MustNotLeaveDust() would revert */
  dustViolation: boolean;
  /** position ends with debt but zero collateral -> deficit is created */
  createsBadDebt: boolean;
};

export function simulateLiquidation(input: LiquidationInput): LiquidationResult {
  const { collateral, debt, ltPct, bonusPct, protocolFeePct, debtToCover } = input;
  const hf = debt === 0 ? Infinity : (collateral * (ltPct / 100)) / debt;
  const liquidatable = hf < 1;

  // Close factor (v3.3): 100% when HF <= 0.95 or either side of this reserve < $2,000
  const smallPosition =
    collateral < MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD || debt < MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD;
  const fullCloseFactor = hf <= CLOSE_FACTOR_HF_THRESHOLD || smallPosition;
  const maxLiquidatableDebt = fullCloseFactor ? debt : debt * DEFAULT_LIQUIDATION_CLOSE_FACTOR;

  const requested = Math.min(debtToCover, maxLiquidatableDebt);
  let actualDebtLiquidated = requested;
  let collateralSeized = actualDebtLiquidated * (1 + bonusPct / 100);
  if (collateralSeized > collateral) {
    collateralSeized = collateral;
    actualDebtLiquidated = collateral / (1 + bonusPct / 100);
  }

  const basePortion = collateralSeized / (1 + bonusPct / 100);
  const bonusPortion = collateralSeized - basePortion;
  const protocolFee = (bonusPortion * protocolFeePct) / 100;
  const toLiquidator = collateralSeized - protocolFee;

  const leftoverDebt = debt - actualDebtLiquidated;
  const leftoverCollateral = collateral - collateralSeized;

  // Dust rule: both sides must end at zero or >= MIN_LEFTOVER_BASE.
  // 0.5 tolerance stands in for wei-level rounding of the on-chain check.
  const dustViolation =
    liquidatable &&
    leftoverDebt > 0.5 &&
    leftoverCollateral > 0.5 &&
    (leftoverDebt < MIN_LEFTOVER_BASE || leftoverCollateral < MIN_LEFTOVER_BASE);

  const createsBadDebt = liquidatable && !dustViolation && leftoverCollateral <= 0.5 && leftoverDebt > 0.5;

  return {
    healthFactor: hf,
    liquidatable,
    fullCloseFactor,
    maxLiquidatableDebt,
    actualDebtLiquidated,
    collateralSeized,
    bonusPortion,
    protocolFee,
    toLiquidator,
    liquidatorProfit: toLiquidator - actualDebtLiquidated,
    leftoverDebt,
    leftoverCollateral,
    dustViolation,
    createsBadDebt,
  };
}
