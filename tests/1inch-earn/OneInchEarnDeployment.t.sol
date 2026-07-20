// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '../../src/contracts/interfaces/IPoolConfigurator.sol';
import {IAToken} from '../../src/contracts/interfaces/IAToken.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {AaveProtocolDataProvider} from '../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {DataTypes} from '../../src/contracts/protocol/libraries/types/DataTypes.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';

/**
 * @title OneInchEarnDeploymentTest
 * @notice Verifies the 1inch Earn launch book is applied exactly: 1x branding, per-reserve
 * risk parameters, the collateral-only (red-row) policy for 1INCH, the ETH-correlated eMode,
 * and market-level settings. Runs fully locally against mocks.
 */
contract OneInchEarnDeploymentTest is OneInchEarnTestBase {
  IPool internal pool;
  AaveProtocolDataProvider internal dp;

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    dp = AaveProtocolDataProvider(report.protocolDataProvider);
  }

  function test_allReservesListed() public view {
    address[] memory reserves = pool.getReservesList();
    assertEq(reserves.length, 7, 'should list exactly 7 reserves');
  }

  function test_oneInchIsCollateralOnly() public view {
    // The red row: supplied as collateral, never borrowable, never flashloanable.
    (, uint256 ltv, uint256 lt, uint256 bonus, , bool collateral, bool borrowing, , , ) = dp
      .getReserveConfigurationData(tokens.oneInch);

    assertEq(ltv, 55_00, '1INCH ltv');
    assertEq(lt, 65_00, '1INCH liquidation threshold');
    assertEq(bonus, 110_00, '1INCH liquidation bonus');
    assertTrue(collateral, '1INCH must be usable as collateral');
    assertFalse(borrowing, '1INCH borrowing must be disabled');
    assertFalse(dp.getFlashLoanEnabled(tokens.oneInch), '1INCH flashloans must be disabled');

    (uint256 borrowCap, uint256 supplyCap) = dp.getReserveCaps(tokens.oneInch);
    assertEq(supplyCap, 2_500_000, '1INCH supply cap (tokens)');
    assertEq(borrowCap, 0, '1INCH borrow cap');
  }

  function test_blueChipsAreTwoSided() public view {
    _assertBorrowable(tokens.weth);
    _assertBorrowable(tokens.wstEth);
    _assertBorrowable(tokens.wbtc);
    _assertBorrowable(tokens.cbBtc);
    _assertBorrowable(tokens.usdc);
    _assertBorrowable(tokens.usdt);
  }

  function test_oneXBranding() public view {
    _assertBranding(tokens.weth, 'WETH');
    _assertBranding(tokens.oneInch, '1INCH');
    _assertBranding(tokens.usdc, 'USDC');
  }

  function test_launchBookParametersMatchConfig() public view {
    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);
    for (uint256 i = 0; i < listings.length; i++) {
      OneInchEarnConfig.AssetListing memory l = listings[i];
      (, uint256 ltv, uint256 lt, uint256 bonus, uint256 reserveFactor, , bool borrowing, , , ) = dp
        .getReserveConfigurationData(l.asset);
      assertEq(ltv, l.ltv, string.concat(l.assetSymbol, ' ltv'));
      assertEq(lt, l.liqThreshold, string.concat(l.assetSymbol, ' lt'));
      assertEq(bonus, l.liquidationBonus, string.concat(l.assetSymbol, ' bonus'));
      assertEq(reserveFactor, l.reserveFactor, string.concat(l.assetSymbol, ' reserveFactor'));
      assertEq(borrowing, l.enabledToBorrow, string.concat(l.assetSymbol, ' borrowing'));
      assertEq(
        dp.getLiquidationProtocolFee(l.asset),
        l.liqProtocolFee,
        string.concat(l.assetSymbol, ' liqProtocolFee')
      );
      (uint256 borrowCap, uint256 supplyCap) = dp.getReserveCaps(l.asset);
      assertEq(supplyCap, l.supplyCap, string.concat(l.assetSymbol, ' supplyCap'));
      assertEq(borrowCap, l.borrowCap, string.concat(l.assetSymbol, ' borrowCap'));
    }
  }

  function test_ethCorrelatedEMode() public view {
    OneInchEarnConfig.EModeConfig memory e = OneInchEarnConfig.ethCorrelatedEMode();
    DataTypes.CollateralConfig memory cfg = pool.getEModeCategoryCollateralConfig(e.categoryId);

    assertEq(cfg.ltv, e.ltv, 'emode ltv');
    assertEq(cfg.liquidationThreshold, e.liqThreshold, 'emode lt (93%)');
    assertEq(cfg.liquidationBonus, e.liquidationBonus, 'emode bonus');
    assertEq(pool.getEModeCategoryLabel(e.categoryId), e.label, 'emode label');

    uint128 collateralBitmap = pool.getEModeCategoryCollateralBitmap(e.categoryId);
    uint128 borrowableBitmap = pool.getEModeCategoryBorrowableBitmap(e.categoryId);

    uint256 wethId = pool.getReserveData(tokens.weth).id;
    uint256 wstEthId = pool.getReserveData(tokens.wstEth).id;
    uint256 usdcId = pool.getReserveData(tokens.usdc).id;

    assertTrue(_isBitSet(collateralBitmap, wethId), 'WETH must be eMode collateral');
    assertTrue(_isBitSet(collateralBitmap, wstEthId), 'wstETH must be eMode collateral');
    assertTrue(_isBitSet(borrowableBitmap, wethId), 'WETH must be eMode borrowable');
    assertFalse(_isBitSet(borrowableBitmap, wstEthId), 'wstETH must NOT be eMode borrowable');
    assertFalse(_isBitSet(collateralBitmap, usdcId), 'USDC must NOT be eMode collateral');
  }

  function test_marketLevelSettings() public view {
    assertEq(
      pool.FLASHLOAN_PREMIUM_TOTAL(),
      OneInchEarnConfig.FLASH_LOAN_PREMIUM_TOTAL,
      'flash premium'
    );
    // aTokens accrue interest to the market treasury (Collector).
    address aToken = pool.getReserveAToken(tokens.weth);
    assertEq(IAToken(aToken).RESERVE_TREASURY_ADDRESS(), report.treasury, 'treasury wiring');
  }

  function test_payloadRenouncedPoolAdmin() public view {
    assertFalse(
      ACLManager(report.aclManager).isPoolAdmin(address(listingPayload)),
      'listing payload must renounce POOL_ADMIN'
    );
    assertTrue(listingPayload.executed(), 'payload executed');
  }

  function test_listingCannotBeReplayed() public {
    vm.expectRevert(); // AlreadyExecuted (and also no longer POOL_ADMIN)
    listingPayload.execute();
  }

  // --------------------------------- helpers -----------------------------------

  function _assertBorrowable(address asset) internal view {
    (, , , , , bool collateral, bool borrowing, , , ) = dp.getReserveConfigurationData(asset);
    assertTrue(collateral, 'blue chip collateral');
    assertTrue(borrowing, 'blue chip borrowing');
  }

  function _assertBranding(address asset, string memory symbol) internal view {
    address aToken = pool.getReserveAToken(asset);
    address vToken = pool.getReserveVariableDebtToken(asset);

    assertEq(
      IERC20Metadata(aToken).symbol(),
      string.concat('1x', symbol),
      'aToken symbol must be 1x-branded'
    );
    assertEq(IERC20Metadata(aToken).name(), string.concat('1inch Earn ', symbol), 'aToken name');
    assertEq(IERC20Metadata(vToken).symbol(), string.concat('1xDebt', symbol), 'debt token symbol');
  }
}
