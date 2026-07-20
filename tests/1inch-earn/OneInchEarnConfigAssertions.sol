// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IAaveOracle} from '../../src/contracts/interfaces/IAaveOracle.sol';
import {AaveProtocolDataProvider} from '../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {DataTypes} from '../../src/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnConfigAssertions
 * @author 1inch
 * @notice Deployment-agnostic assertions that a live 1inch Earn market matches
 * `OneInchEarnConfig` exactly — the automated defense against the #1 fork failure mode
 * (misconfiguration). Reused by the local mock verification test and the mainnet-fork test,
 * and mirrors the checks a post-deploy verification run should make against the address report.
 */
abstract contract OneInchEarnConfigAssertions is Test {
  function _assertReserveMatchesConfig(
    IPool pool,
    AaveProtocolDataProvider dp,
    IAaveOracle oracle,
    OneInchEarnConfig.AssetListing memory l
  ) internal view {
    (
      ,
      uint256 ltv,
      uint256 lt,
      uint256 bonus,
      uint256 reserveFactor,
      bool collateral,
      bool borrowing,
      ,
      bool active,

    ) = dp.getReserveConfigurationData(l.asset);

    assertTrue(active, string.concat(l.assetSymbol, ': active'));
    assertEq(ltv, l.ltv, string.concat(l.assetSymbol, ': ltv'));
    assertEq(lt, l.liqThreshold, string.concat(l.assetSymbol, ': liqThreshold'));
    assertEq(bonus, l.liquidationBonus, string.concat(l.assetSymbol, ': liquidationBonus'));
    assertEq(reserveFactor, l.reserveFactor, string.concat(l.assetSymbol, ': reserveFactor'));
    assertEq(borrowing, l.enabledToBorrow, string.concat(l.assetSymbol, ': borrowing'));
    assertTrue(collateral, string.concat(l.assetSymbol, ': collateral (LT>0)'));

    assertEq(
      dp.getLiquidationProtocolFee(l.asset),
      l.liqProtocolFee,
      string.concat(l.assetSymbol, ': liqProtocolFee')
    );
    assertEq(
      dp.getFlashLoanEnabled(l.asset),
      l.flashloanable,
      string.concat(l.assetSymbol, ': flashloanable')
    );

    (uint256 borrowCap, uint256 supplyCap) = dp.getReserveCaps(l.asset);
    assertEq(supplyCap, l.supplyCap, string.concat(l.assetSymbol, ': supplyCap'));
    assertEq(borrowCap, l.borrowCap, string.concat(l.assetSymbol, ': borrowCap'));

    assertEq(
      oracle.getSourceOfAsset(l.asset),
      l.priceFeed,
      string.concat(l.assetSymbol, ': oracle source')
    );

    // 1x branding.
    address aToken = pool.getReserveAToken(l.asset);
    address vToken = pool.getReserveVariableDebtToken(l.asset);
    assertEq(
      IERC20Metadata(aToken).symbol(),
      string.concat('1x', l.assetSymbol),
      string.concat(l.assetSymbol, ': aToken 1x symbol')
    );
    assertEq(
      IERC20Metadata(vToken).symbol(),
      string.concat('1xd', l.assetSymbol),
      string.concat(l.assetSymbol, ': debt 1xd symbol')
    );
  }

  /// @notice Asserts the red-row policy: never borrowable, never flashloanable, but collateral.
  function _assertRedRow(AaveProtocolDataProvider dp, address asset, string memory sym) internal view {
    (, , , , , bool collateral, bool borrowing, , , ) = dp.getReserveConfigurationData(asset);
    assertTrue(collateral, string.concat(sym, ': red-row must be collateral'));
    assertFalse(borrowing, string.concat(sym, ': red-row must not borrow'));
    assertFalse(dp.getFlashLoanEnabled(asset), string.concat(sym, ': red-row no flashloan'));
    (uint256 borrowCap, ) = dp.getReserveCaps(asset);
    assertEq(borrowCap, 0, string.concat(sym, ': red-row borrow cap 0'));
  }

  function _assertEModeMatchesConfig(
    IPool pool,
    OneInchEarnConfig.EModeConfig memory e,
    address[] memory expectedCollateral,
    address[] memory expectedBorrowable
  ) internal view {
    DataTypes.CollateralConfig memory cfg = pool.getEModeCategoryCollateralConfig(e.categoryId);
    assertEq(cfg.ltv, e.ltv, 'emode ltv');
    assertEq(cfg.liquidationThreshold, e.liqThreshold, 'emode lt');
    assertEq(cfg.liquidationBonus, e.liquidationBonus, 'emode bonus');
    assertEq(pool.getEModeCategoryLabel(e.categoryId), e.label, 'emode label');
    assertEq(pool.getIsEModeCategoryIsolated(e.categoryId), e.isolated, 'emode isolated flag');

    uint128 collateralBitmap = pool.getEModeCategoryCollateralBitmap(e.categoryId);
    uint128 borrowableBitmap = pool.getEModeCategoryBorrowableBitmap(e.categoryId);
    for (uint256 i = 0; i < expectedCollateral.length; i++) {
      uint256 id = pool.getReserveData(expectedCollateral[i]).id;
      assertTrue((collateralBitmap >> id) & 1 == 1, 'emode collateral member');
    }
    for (uint256 i = 0; i < expectedBorrowable.length; i++) {
      uint256 id = pool.getReserveData(expectedBorrowable[i]).id;
      assertTrue((borrowableBitmap >> id) & 1 == 1, 'emode borrowable member');
    }
  }
}
