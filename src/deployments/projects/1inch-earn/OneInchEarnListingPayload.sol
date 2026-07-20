// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketReport} from '../../interfaces/IMarketReportTypes.sol';
import {OneInchEarnConfig} from './OneInchEarnConfig.sol';
import {OneInchEarnListingBase} from './OneInchEarnListingBase.sol';

/**
 * @title OneInchEarnListingPayload
 * @author 1inch
 * @notice Phase-1 launch payload of the 1inch Earn market: lists the launch book
 * (1INCH collateral-only + WETH, wstETH, WBTC, cbBTC, USDC, USDT two-sided) with
 * 1x-branded tokens, and creates the ETH-correlated eMode.
 * @dev Launch policy encoded here:
 * - 1INCH is THE RED ROW: collateral side always, borrow side never. Borrowing and
 *   flashloans are explicitly disabled at listing; flipping either flag would require
 *   the 1inch DAO to publicly vote against its own policy (SafeSnap + timelock +
 *   guardian veto after handover).
 * - The ETH-correlated eMode (WETH + wstETH collateral, WETH borrowable) recreates the
 *   professional wstETH/WETH loop at 93% liquidation threshold.
 */
contract OneInchEarnListingPayload is OneInchEarnListingBase {
  uint8 public immutable EMODE_CATEGORY_ID;

  OneInchEarnConfig.EModeConfig internal _eMode;

  constructor(
    MarketReport memory report,
    OneInchEarnConfig.AssetListing[] memory listings_,
    OneInchEarnConfig.EModeConfig memory eMode_
  ) OneInchEarnListingBase(report, listings_) {
    _eMode = eMode_;
    EMODE_CATEGORY_ID = eMode_.categoryId;
  }

  function getEMode() external view returns (OneInchEarnConfig.EModeConfig memory) {
    return _eMode;
  }

  function _postListing() internal override {
    OneInchEarnConfig.EModeConfig memory eMode = _eMode;

    CONFIGURATOR.setEModeCategory(
      eMode.categoryId,
      eMode.ltv,
      eMode.liqThreshold,
      eMode.liquidationBonus,
      eMode.label,
      eMode.isolated
    );

    uint256 length = _listings.length;
    for (uint256 i = 0; i < length; i++) {
      OneInchEarnConfig.AssetListing memory listing = _listings[i];
      if (listing.eModeCollateral) {
        CONFIGURATOR.setAssetCollateralInEMode(listing.asset, eMode.categoryId, true);
      }
      if (listing.eModeBorrowable) {
        CONFIGURATOR.setAssetBorrowableInEMode(listing.asset, eMode.categoryId, true);
      }
    }
  }
}
