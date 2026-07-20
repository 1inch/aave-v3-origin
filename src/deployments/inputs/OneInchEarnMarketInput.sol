// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import './MarketInput.sol';
import {OneInchEarnConfig} from '../projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnMarketInput
 * @author 1inch
 * @notice Market input for the "1inch Earn" Aave v3.7 instance on Ethereum mainnet.
 * @dev Bootstrap-phase roles: the deployer holds marketOwner/poolAdmin/emergencyAdmin
 * until listing + seeding are complete and verified; then everything is moved to the
 * 1inch DAO executor, guardian and risk provider via the handover procedure
 * (see `src/deployments/projects/1inch-earn/OneInchEarnHandover.sol`).
 */
contract OneInchEarnMarketInput is MarketInput {
  function _getMarketInput(
    address deployer
  )
    internal
    pure
    override
    returns (
      Roles memory roles,
      MarketConfig memory config,
      DeployFlags memory flags,
      MarketReport memory deployedContracts
    )
  {
    roles.marketOwner = deployer;
    roles.poolAdmin = deployer;
    roles.emergencyAdmin = deployer;

    config.marketId = OneInchEarnConfig.MARKET_ID;
    config.providerId = OneInchEarnConfig.PROVIDER_ID;
    config.oracleDecimals = OneInchEarnConfig.ORACLE_DECIMALS;
    config.flashLoanPremium = OneInchEarnConfig.FLASH_LOAN_PREMIUM_TOTAL;
    config.salt = OneInchEarnConfig.COLLECTOR_SALT;

    // USD-based market on Ethereum: both UiPoolDataProvider aggregators point to
    // Chainlink ETH/USD, following the Aave v3 Ethereum mainline convention.
    config.networkBaseTokenPriceInUsdProxyAggregator = OneInchEarnConfig.ETH_USD_FEED;
    config.marketReferenceCurrencyPriceInUsdProxyAggregator = OneInchEarnConfig.ETH_USD_FEED;

    // Enables the WrappedTokenGateway (native ETH deposits/withdrawals).
    config.wrappedNativeToken = OneInchEarnConfig.WETH;

    // Ethereum mainnet: flags.l2 stays false (no L2Pool, no L2Encoder).

    return (roles, config, flags, deployedContracts);
  }
}
