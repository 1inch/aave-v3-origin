// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DeployAaveV3MarketBatchedBase} from '../misc/DeployAaveV3MarketBatchedBase.sol';
import {OneInchEarnMarketInput} from '../../src/deployments/inputs/OneInchEarnMarketInput.sol';

/**
 * @title Deploy1inchEarnMarket
 * @author 1inch
 * @notice Step 1 of the 1inch Earn rollout: deploys the full Aave v3.7 market
 * (addresses provider + registry, Pool/Configurator, ACL, oracle, treasury + dustBin,
 * incentives, data providers, config engine, static aToken factory, WETH gateway) in a
 * single broadcast and writes the address report under /reports.
 *
 * PRECONDITION: the 5 logic libraries must be pre-deployed and linked (make deploy-libs
 * chain=mainnet). See docs/1inch-earn/deployment-runbook.md.
 *
 * Usage (mainnet, Ledger):
 *   forge script scripts/1inch-earn/Deploy1inchEarnMarket.sol:Deploy1inchEarnMarket \
 *     --rpc-url mainnet --ledger --sender <LEDGER_SENDER> --broadcast --verify --slow
 */
contract Deploy1inchEarnMarket is DeployAaveV3MarketBatchedBase, OneInchEarnMarketInput {}
