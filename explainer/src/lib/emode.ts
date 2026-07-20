/**
 * Effective-LTV resolution for a user inside an eMode category.
 * Mirrors ValidationLogic.getUserReserveLtv (v3.7).
 * Source: src/contracts/protocol/libraries/logic/ValidationLogic.sol
 */

export type EModeAsset = {
  /** asset is flagged in the category's collateralBitmap */
  inCollateralBitmap: boolean;
  /** asset is flagged in the category's ltvzeroBitmap */
  inLtvzeroBitmap?: boolean;
  /** base (non-eMode) LTV in % */
  baseLtv: number;
  /** category LTV in % */
  emodeLtv: number;
};

export type LtvResolution = {
  ltv: number;
  /** which branch of getUserReserveLtv applied (1: bitmap, 2: isolated -> 0, 3: base) */
  branch: 1 | 2 | 3;
  reason: string;
};

export function getUserReserveLtv(
  asset: EModeAsset,
  userInEMode: boolean,
  categoryIsolated: boolean,
): LtvResolution {
  if (userInEMode && asset.inCollateralBitmap) {
    if (asset.inLtvzeroBitmap) {
      return { ltv: 0, branch: 1, reason: 'in collateralBitmap but flagged ltvzero → LTV 0' };
    }
    return { ltv: asset.emodeLtv, branch: 1, reason: `in collateralBitmap → eMode LTV ${asset.emodeLtv}%` };
  }
  if (userInEMode && categoryIsolated) {
    return { ltv: 0, branch: 2, reason: 'outside bitmap + isolated → LTV 0' };
  }
  return { ltv: asset.baseLtv, branch: 3, reason: `base LTV ${asset.baseLtv}%` };
}

/**
 * Entry validation for an isolated eMode: entry is blocked while the user has
 * collateral enabled on any asset that would resolve to LTV 0 under the target category
 * (the InvalidCollateralInEmode check in validateSetUserEMode).
 */
export function isEModeEntryBlocked(
  assets: { asset: EModeAsset; enabledAsCollateral: boolean }[],
  categoryIsolated: boolean,
): boolean {
  return assets.some(
    ({ asset, enabledAsCollateral }) =>
      enabledAsCollateral && getUserReserveLtv(asset, true, categoryIsolated).ltv === 0,
  );
}
