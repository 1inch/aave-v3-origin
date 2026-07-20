// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketReport} from '../../interfaces/IMarketReportTypes.sol';
import {IPoolConfigurator, ConfiguratorInputTypes} from '../../../contracts/interfaces/IPoolConfigurator.sol';
import {IAaveOracle} from '../../../contracts/interfaces/IAaveOracle.sol';
import {ACLManager} from '../../../contracts/protocol/configuration/ACLManager.sol';
import {OneInchEarnConfig} from './OneInchEarnConfig.sol';

/**
 * @title OneInchEarnListingBase
 * @author 1inch
 * @notice Base payload listing reserves on the 1inch Earn market with "1x" branding.
 * @dev The stock Aave config engine hardcodes the 'Aave ' / 'a' / 'variableDebt' token
 * prefixes inside `ListingEngine`, so this payload calls `PoolConfigurator.initReserves`
 * directly with 1inch Earn names (aToken `1xWETH`, debt token `1xDebtWETH`, ...). All
 * audited v3.7 core files stay byte-identical; the deployed config engine remains usable
 * by governance for every name-agnostic update (caps, collateral, borrow, rates, eModes).
 *
 * Lifecycle: deploy -> `ACLManager.addPoolAdmin(payload)` -> `execute()` (single use) ->
 * the payload renounces POOL_ADMIN in the same transaction.
 */
abstract contract OneInchEarnListingBase {
  error AlreadyExecuted();
  error NoListings();

  IPoolConfigurator public immutable CONFIGURATOR;
  IAaveOracle public immutable ORACLE;
  ACLManager public immutable ACL_MANAGER;
  address public immutable ATOKEN_IMPL;
  address public immutable VDEBT_IMPL;

  bool public executed;

  OneInchEarnConfig.AssetListing[] internal _listings;

  constructor(MarketReport memory report, OneInchEarnConfig.AssetListing[] memory listings_) {
    if (listings_.length == 0) revert NoListings();

    CONFIGURATOR = IPoolConfigurator(report.poolConfiguratorProxy);
    ORACLE = IAaveOracle(report.aaveOracle);
    ACL_MANAGER = ACLManager(report.aclManager);
    ATOKEN_IMPL = report.aToken;
    VDEBT_IMPL = report.variableDebtToken;

    for (uint256 i = 0; i < listings_.length; i++) {
      _listings.push(listings_[i]);
    }
  }

  function getListings() external view returns (OneInchEarnConfig.AssetListing[] memory) {
    return _listings;
  }

  /// @notice Lists all configured reserves, then renounces POOL_ADMIN.
  function execute() external {
    if (executed) revert AlreadyExecuted();
    executed = true;

    _setPriceFeeds();
    _initReserves();
    _configureReserves();
    _postListing();

    ACL_MANAGER.renounceRole(ACL_MANAGER.POOL_ADMIN_ROLE(), address(this));
  }

  /// @dev Hook for extra configuration (e.g. eModes) executed while still POOL_ADMIN.
  function _postListing() internal virtual {}

  function _setPriceFeeds() internal {
    uint256 length = _listings.length;
    address[] memory assets = new address[](length);
    address[] memory sources = new address[](length);
    for (uint256 i = 0; i < length; i++) {
      assets[i] = _listings[i].asset;
      sources[i] = _listings[i].priceFeed;
    }
    ORACLE.setAssetSources(assets, sources);
  }

  function _initReserves() internal {
    uint256 length = _listings.length;
    ConfiguratorInputTypes.InitReserveInput[]
      memory inputs = new ConfiguratorInputTypes.InitReserveInput[](length);

    for (uint256 i = 0; i < length; i++) {
      OneInchEarnConfig.AssetListing memory listing = _listings[i];
      inputs[i] = ConfiguratorInputTypes.InitReserveInput({
        aTokenImpl: ATOKEN_IMPL,
        variableDebtTokenImpl: VDEBT_IMPL,
        underlyingAsset: listing.asset,
        aTokenName: aTokenName(listing.assetSymbol),
        aTokenSymbol: aTokenSymbol(listing.assetSymbol),
        variableDebtTokenName: vTokenName(listing.assetSymbol),
        variableDebtTokenSymbol: vTokenSymbol(listing.assetSymbol),
        params: bytes(''),
        interestRateData: abi.encode(listing.rates)
      });
    }

    CONFIGURATOR.initReserves(inputs);
  }

  function _configureReserves() internal {
    uint256 length = _listings.length;
    for (uint256 i = 0; i < length; i++) {
      OneInchEarnConfig.AssetListing memory listing = _listings[i];

      CONFIGURATOR.configureReserveAsCollateral(
        listing.asset,
        listing.ltv,
        listing.liqThreshold,
        listing.liquidationBonus
      );

      // Both flags set explicitly: the red-row policy (borrowing/flashloans disabled for
      // 1INCH and AQUA) must be visible on-chain as an explicit configuration event.
      CONFIGURATOR.setReserveBorrowing(listing.asset, listing.enabledToBorrow);
      CONFIGURATOR.setReserveFlashLoaning(listing.asset, listing.flashloanable);

      CONFIGURATOR.setReserveFactor(listing.asset, listing.reserveFactor);
      CONFIGURATOR.setSupplyCap(listing.asset, listing.supplyCap);
      if (listing.borrowCap != 0) {
        CONFIGURATOR.setBorrowCap(listing.asset, listing.borrowCap);
      }
      CONFIGURATOR.setLiquidationProtocolFee(listing.asset, listing.liqProtocolFee);
    }
  }

  // ------------------------------- 1x branding ---------------------------------

  function aTokenName(string memory assetSymbol) public pure returns (string memory) {
    return string.concat(OneInchEarnConfig.ATOKEN_NAME_PREFIX, assetSymbol);
  }

  function aTokenSymbol(string memory assetSymbol) public pure returns (string memory) {
    return string.concat(OneInchEarnConfig.ATOKEN_SYMBOL_PREFIX, assetSymbol);
  }

  function vTokenName(string memory assetSymbol) public pure returns (string memory) {
    return string.concat(OneInchEarnConfig.VDEBT_NAME_PREFIX, assetSymbol);
  }

  function vTokenSymbol(string memory assetSymbol) public pure returns (string memory) {
    return string.concat(OneInchEarnConfig.VDEBT_SYMBOL_PREFIX, assetSymbol);
  }
}
