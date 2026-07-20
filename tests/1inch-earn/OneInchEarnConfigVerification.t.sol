// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {OneInchEarnConfigAssertions} from './OneInchEarnConfigAssertions.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IAaveOracle} from '../../src/contracts/interfaces/IAaveOracle.sol';
import {AaveProtocolDataProvider} from '../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnConfigVerificationTest
 * @notice One automated gate asserting the deployed market matches OneInchEarnConfig exactly:
 * every reserve's risk params/caps/oracle/1x-naming, the red-row policy for 1INCH, and the
 * ETH eMode (params, membership, isolated flag). The runbook's pre-handover config-audit step
 * points here. Runs locally against mocks; the fork test reuses the same assertions on real assets.
 */
contract OneInchEarnConfigVerificationTest is OneInchEarnTestBase, OneInchEarnConfigAssertions {
  IPool internal pool;
  AaveProtocolDataProvider internal dp;

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    dp = AaveProtocolDataProvider(report.protocolDataProvider);
  }

  function test_everyReserveMatchesConfig() public view {
    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);
    IAaveOracle oracle = IAaveOracle(report.aaveOracle);
    assertEq(pool.getReservesList().length, listings.length, 'reserve count');
    for (uint256 i = 0; i < listings.length; i++) {
      _assertReserveMatchesConfig(pool, dp, oracle, listings[i]);
    }
  }

  function test_redRowPolicy() public view {
    _assertRedRow(dp, tokens.oneInch, '1INCH');
  }

  function test_ethEModeMatchesConfig() public view {
    address[] memory collateral = new address[](2);
    collateral[0] = tokens.weth;
    collateral[1] = tokens.wstEth;
    address[] memory borrowable = new address[](1);
    borrowable[0] = tokens.weth;
    _assertEModeMatchesConfig(pool, OneInchEarnConfig.ethCorrelatedEMode(), collateral, borrowable);
  }

  function test_stablecoinEModeMatchesConfig() public view {
    address[] memory members = new address[](2);
    members[0] = tokens.usdc;
    members[1] = tokens.usdt;
    // USDC/USDT are both collateral and borrowable in the stablecoin eMode.
    _assertEModeMatchesConfig(pool, OneInchEarnConfig.stablecoinEMode(), members, members);
  }
}
