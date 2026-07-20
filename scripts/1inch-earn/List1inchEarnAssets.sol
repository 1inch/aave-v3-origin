// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import {OneInchEarnReportReader} from './utils/OneInchEarnReportReader.sol';
import {MarketReport} from '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';
import {OneInchEarnListingPayload} from '../../src/deployments/projects/1inch-earn/OneInchEarnListingPayload.sol';

/**
 * @title List1inchEarnAssets
 * @author 1inch
 * @notice Step 2: lists the launch book (1x-branded) on the freshly deployed market and
 * creates the ETH-correlated eMode. Run by the bootstrap deployer (still POOL_ADMIN).
 *
 * Optional env `WSTETH_USD_FEED` overrides the wstETH price adapter (defaults to the Aave
 * mainline adapter).
 *
 * Usage (mainnet, Ledger):
 *   REPORT_PATH=reports/<ts>-market-deployment.json \
 *   forge script scripts/1inch-earn/List1inchEarnAssets.sol:List1inchEarnAssets \
 *     --rpc-url mainnet --ledger --sender <LEDGER_SENDER> --broadcast --slow
 */
contract List1inchEarnAssets is OneInchEarnReportReader {
  function run() external {
    MarketReport memory report = _readReport();

    OneInchEarnConfig.TokenAddresses memory tokens = OneInchEarnConfig.mainnetTokens();
    OneInchEarnConfig.FeedAddresses memory feeds = OneInchEarnConfig.mainnetFeeds(
      vm.envOr('WSTETH_USD_FEED', OneInchEarnConfig.WSTETH_USD_FEED)
    );
    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);

    vm.startBroadcast();

    OneInchEarnListingPayload payload = new OneInchEarnListingPayload(
      report,
      listings,
      OneInchEarnConfig.ethCorrelatedEMode()
    );

    // Grant, execute (self-renounces POOL_ADMIN inside execute()).
    ACLManager(report.aclManager).addPoolAdmin(address(payload));
    payload.execute();

    vm.stopBroadcast();

    console.log('1inch Earn listing payload executed:', address(payload));
  }
}
