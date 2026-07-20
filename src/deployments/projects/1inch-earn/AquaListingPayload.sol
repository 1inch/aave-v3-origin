// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketReport} from '../../interfaces/IMarketReportTypes.sol';
import {OneInchEarnConfig} from './OneInchEarnConfig.sol';
import {OneInchEarnListingBase} from './OneInchEarnListingBase.sol';

/**
 * @title AquaListingPayload
 * @author 1inch
 * @notice Phase-2 payload: lists AQUA on the 1inch Earn market as collateral-only,
 * after the TGE launch gates are met.
 *
 * LAUNCH GATES (all must hold before governance executes this payload):
 * 1. A live, reviewed AQUA/USD price feed (Chainlink-quality; 8 decimals).
 * 2. >= 30 days of open trading history post-TGE.
 * 3. Proven, sustained 2% market depth per the risk provider's assessment.
 * 4. Supply cap converted from the $0.5M anchor at the TGE reference price.
 *
 * POLICY: AQUA follows the same red row as 1INCH — collateral side always, borrow side
 * never, flashloans disabled. Rented AQUA supply would let farmers game incentive
 * programs; there is nothing to rent here.
 *
 * RATCHET (published, quarterly, governance-executed via `configureReserveAsCollateral`
 * or the deployed config engine's `updateCollateralSide`):
 * - Listing:  LTV 30.00% / LT 38.50%
 * - Target:   LTV 50.00% / LT 62.50%
 * - Each step requires: 2% depth > $1M sustained, real volume evidence, and clean
 *   liquidation behavior observed at the current step.
 */
contract AquaListingPayload is OneInchEarnListingBase {
  constructor(
    MarketReport memory report,
    address aqua,
    address aquaUsdFeed,
    uint256 supplyCapTokens
  ) OneInchEarnListingBase(report, _buildListings(aqua, aquaUsdFeed, supplyCapTokens)) {}

  function _buildListings(
    address aqua,
    address aquaUsdFeed,
    uint256 supplyCapTokens
  ) internal pure returns (OneInchEarnConfig.AssetListing[] memory listings_) {
    listings_ = new OneInchEarnConfig.AssetListing[](1);
    listings_[0] = OneInchEarnConfig.aquaListing(aqua, aquaUsdFeed, supplyCapTokens);
  }
}
