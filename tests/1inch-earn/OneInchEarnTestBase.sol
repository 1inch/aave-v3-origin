// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {BatchTestProcedures} from '../utils/BatchTestProcedures.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';
import {WETH9} from '../../src/contracts/dependencies/weth/WETH9.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {MockAggregator} from '../../src/contracts/mocks/oracle/CLAggregators/MockAggregator.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';
import {OneInchEarnListingPayload} from '../../src/deployments/projects/1inch-earn/OneInchEarnListingPayload.sol';

/**
 * @title OneInchEarnTestBase
 * @notice Local (non-fork) harness that deploys the 1inch Earn market against mock tokens
 * and mock Chainlink aggregators, then lists the launch book with the real risk parameters
 * from `OneInchEarnConfig`. Mock underlyings stand in for the mainnet addresses; every
 * LTV / cap / rate / eMode value is the production one.
 */
abstract contract OneInchEarnTestBase is BatchTestProcedures {
  address internal deployer;

  MarketReport internal report;
  OneInchEarnConfig.TokenAddresses internal tokens;
  OneInchEarnConfig.FeedAddresses internal feeds;
  OneInchEarnConfig.AssetListing[] internal launchListings;
  OneInchEarnListingPayload internal listingPayload;

  function _deployMarketAndList() internal {
    deployer = makeAddr('oneInchEarnDeployer');
    Roles memory roles = Roles(deployer, deployer, deployer);
    DeployFlags memory flags;
    MarketReport memory empty;

    // Mock underlyings with mainnet-accurate decimals.
    address weth = address(new WETH9());
    tokens = OneInchEarnConfig.TokenAddresses({
      oneInch: address(new TestnetERC20('1inch', '1INCH', 18, deployer)),
      weth: weth,
      wstEth: address(new TestnetERC20('Wrapped stETH', 'wstETH', 18, deployer)),
      wbtc: address(new TestnetERC20('Wrapped BTC', 'WBTC', 8, deployer)),
      cbBtc: address(new TestnetERC20('Coinbase BTC', 'cbBTC', 8, deployer)),
      usdc: address(new TestnetERC20('USD Coin', 'USDC', 6, deployer)),
      usdt: address(new TestnetERC20('Tether USD', 'USDT', 6, deployer))
    });

    // Mock feeds (8 decimals) at representative launch prices.
    feeds = OneInchEarnConfig.FeedAddresses({
      oneInch: address(new MockAggregator(0.40e8)),
      weth: address(new MockAggregator(3300e8)),
      wstEth: address(new MockAggregator(3900e8)),
      wbtc: address(new MockAggregator(100_000e8)),
      cbBtc: address(new MockAggregator(100_000e8)),
      usdc: address(new MockAggregator(1e8)),
      usdt: address(new MockAggregator(1e8))
    });

    MarketConfig memory config = MarketConfig({
      networkBaseTokenPriceInUsdProxyAggregator: feeds.weth,
      marketReferenceCurrencyPriceInUsdProxyAggregator: feeds.weth,
      marketId: OneInchEarnConfig.MARKET_ID,
      oracleDecimals: OneInchEarnConfig.ORACLE_DECIMALS,
      providerId: OneInchEarnConfig.PROVIDER_ID,
      salt: bytes32(0),
      wrappedNativeToken: weth,
      flashLoanPremium: OneInchEarnConfig.FLASH_LOAN_PREMIUM_TOTAL,
      incentivesProxy: address(0),
      treasury: address(0)
    });

    report = deployAaveV3Testnet(deployer, roles, config, flags, empty);

    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);
    for (uint256 i = 0; i < listings.length; i++) {
      launchListings.push(listings[i]);
    }

    listingPayload = new OneInchEarnListingPayload(
      report,
      listings,
      OneInchEarnConfig.ethCorrelatedEMode()
    );

    vm.prank(deployer);
    ACLManager(report.aclManager).addPoolAdmin(address(listingPayload));

    listingPayload.execute();
  }

  function _isBitSet(uint128 bitmap, uint256 id) internal pure returns (bool) {
    return (bitmap >> id) & 1 == 1;
  }
}
