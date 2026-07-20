// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {PercentageMath} from '../../src/contracts/protocol/libraries/math/PercentageMath.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnConfigInvariantsTest
 * @notice Pure (no-deploy) safety checks on the launch book itself: every reserve and eMode row
 * in `OneInchEarnConfig` must satisfy the Aave v3.7 protocol math BEFORE it is ever deployed, so
 * a future config edit that would revert `PoolConfigurator` (or, worse, list an unsafe reserve)
 * is caught at unit-test time. Complements `OneInchEarnConfigVerification` (which checks the
 * deployed state equals config); this checks config is internally valid.
 */
contract OneInchEarnConfigInvariantsTest is Test {
  using PercentageMath for uint256;

  function _tokens() internal pure returns (OneInchEarnConfig.TokenAddresses memory) {
    return OneInchEarnConfig.mainnetTokens();
  }

  function _feeds() internal pure returns (OneInchEarnConfig.FeedAddresses memory) {
    return OneInchEarnConfig.mainnetFeeds();
  }

  function test_everyListingSatisfiesProtocolMath() public pure {
    OneInchEarnConfig.AssetListing[] memory ls = OneInchEarnConfig.listings(_tokens(), _feeds());
    assertEq(ls.length, 7, 'expected 7 launch reserves');
    for (uint256 i = 0; i < ls.length; i++) {
      _assertCollateralMath(
        ls[i].assetSymbol,
        ls[i].ltv,
        ls[i].liqThreshold,
        ls[i].liquidationBonus
      );
      // Reserve factor and liquidation protocol fee must be valid percentages (< 100%).
      assertLt(ls[i].reserveFactor, 100_00, string.concat(ls[i].assetSymbol, ': reserveFactor<100%'));
      assertLt(ls[i].liqProtocolFee, 100_00, string.concat(ls[i].assetSymbol, ': liqProtocolFee<100%'));
      // All launch reserves are collateral with a positive supply cap.
      assertGt(ls[i].liqThreshold, 0, string.concat(ls[i].assetSymbol, ': is collateral'));
      assertGt(ls[i].supplyCap, 0, string.concat(ls[i].assetSymbol, ': supply cap set'));
      // Interest-rate optimal usage must sit in the strategy's valid band (1%..99%).
      assertGe(ls[i].rates.optimalUsageRatio, 1_00, string.concat(ls[i].assetSymbol, ': optimal>=1%'));
      assertLe(ls[i].rates.optimalUsageRatio, 99_00, string.concat(ls[i].assetSymbol, ': optimal<=99%'));
      // A borrowable reserve needs a borrow cap; a non-borrowable one must not be flashloanable
      // (the red-row policy) and carries no borrow cap.
      if (!ls[i].enabledToBorrow) {
        assertFalse(ls[i].flashloanable, string.concat(ls[i].assetSymbol, ': non-borrowable=>no flashloan'));
        assertEq(ls[i].borrowCap, 0, string.concat(ls[i].assetSymbol, ': non-borrowable=>borrowCap 0'));
      }
    }
  }

  function test_redRowIsCollateralOnly() public pure {
    OneInchEarnConfig.AssetListing[] memory ls = OneInchEarnConfig.listings(_tokens(), _feeds());
    // result[0] is 1INCH by construction.
    OneInchEarnConfig.AssetListing memory oneInch = ls[0];
    assertEq(oneInch.asset, OneInchEarnConfig.ONEINCH, 'row0 is 1INCH');
    assertFalse(oneInch.enabledToBorrow, '1INCH never borrowable');
    assertFalse(oneInch.flashloanable, '1INCH never flashloanable');
    assertGt(oneInch.liqThreshold, 0, '1INCH is collateral');
  }

  function test_aquaListingIsCollateralOnly() public pure {
    OneInchEarnConfig.AssetListing memory aqua = OneInchEarnConfig.aquaListing(
      address(0xA),
      address(0xB),
      500_000
    );
    assertFalse(aqua.enabledToBorrow, 'AQUA never borrowable');
    assertFalse(aqua.flashloanable, 'AQUA never flashloanable');
    _assertCollateralMath('AQUA', aqua.ltv, aqua.liqThreshold, aqua.liquidationBonus);
  }

  function test_everyEModeSatisfiesProtocolMath() public pure {
    OneInchEarnConfig.EModeConfig[] memory es = OneInchEarnConfig.launchEModes();
    assertGt(es.length, 0, 'has eModes');
    for (uint256 i = 0; i < es.length; i++) {
      assertGt(es[i].categoryId, 0, 'eMode id != 0');
      _assertCollateralMath(es[i].label, es[i].ltv, es[i].liqThreshold, es[i].liquidationBonus);
    }
  }

  /// @dev The exact checks `PoolConfigurator.configureReserveAsCollateral` / `setEModeCategory`
  /// enforce: ltv <= liqThreshold, liquidationBonus > 100%, and liqThreshold * liquidationBonus
  /// <= 100% (else a liquidation would instantly undercollateralize the position).
  function _assertCollateralMath(
    string memory label,
    uint256 ltv,
    uint256 liqThreshold,
    uint256 liquidationBonus
  ) internal pure {
    assertLe(ltv, liqThreshold, string.concat(label, ': ltv<=liqThreshold'));
    assertGt(liquidationBonus, 100_00, string.concat(label, ': liquidationBonus>100%'));
    assertLe(
      liqThreshold.percentMul(liquidationBonus),
      PercentageMath.PERCENTAGE_FACTOR,
      string.concat(label, ': liqThreshold*liquidationBonus<=100%')
    );
  }
}
