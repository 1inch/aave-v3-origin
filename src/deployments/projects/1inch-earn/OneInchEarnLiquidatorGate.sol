// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '../../../contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../../contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {KycNFT} from './KycNFT.sol';
import {OneInchPoolInstance} from './OneInchPoolInstance.sol';
import {OneInchEarnConfig} from './OneInchEarnConfig.sol';

/**
 * @title OneInchEarnLiquidatorGate
 * @author 1inch
 * @notice Helper library to (a) deploy the liquidator KYC NFT and (b) install the
 * NFT-gated Pool implementation as a governance upgrade.
 * @dev Installing the gated pool is a one-time `PoolAddressesProvider.setPoolImpl` upgrade
 * (11 -> 12) that keeps every audited v3.7 deployment file byte-identical. AFTER install,
 * the gate token is mutable via `OneInchPoolInstance.setLiquidatorGate` (POOL_ADMIN or
 * EMERGENCY_ADMIN) — rotating the KYC contract or opening liquidations in an emergency
 * (`gate = address(0)`) is a single transaction, NOT another pool upgrade.
 *
 * The caller must own the `PoolAddressesProvider` (the deployer during bootstrap, the
 * 1inch DAO executor after handover). `setPoolImpl` re-runs the proxy initializer, which
 * re-validates the addresses provider and seeds the gate from the constructor immutable,
 * so live reserves and balances are unaffected.
 */
library OneInchEarnLiquidatorGate {
  /// @notice Deploys the liquidator KYC NFT owned by `owner` (Business Portal minting wallet / ops multisig).
  function deployGate(address owner) internal returns (KycNFT) {
    return
      new KycNFT(
        OneInchEarnConfig.KYC_NFT_NAME,
        OneInchEarnConfig.KYC_NFT_SYMBOL,
        OneInchEarnConfig.KYC_NFT_VERSION,
        owner
      );
  }

  /**
   * @notice Deploys `OneInchPoolInstance(gate)` and installs it as the pool implementation.
   * @param provider The market PoolAddressesProvider (caller must be its owner).
   * @param interestRateStrategy The market's default interest rate strategy
   *   (MarketReport.defaultInterestRateStrategy).
   * @param gate The KYC NFT gate; pass address(0) to install a permissionless gated pool
   *   (behaves like vanilla PoolInstance but with a higher revision).
   * @return newPoolImpl The freshly deployed, now-active pool implementation.
   */
  function installGatedPool(
    IPoolAddressesProvider provider,
    address interestRateStrategy,
    IERC20 gate
  ) internal returns (address newPoolImpl) {
    OneInchPoolInstance pool = new OneInchPoolInstance(
      provider,
      IReserveInterestRateStrategy(interestRateStrategy),
      gate
    );
    provider.setPoolImpl(address(pool));
    return address(pool);
  }
}
