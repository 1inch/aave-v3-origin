// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {PoolInstance} from '../../../contracts/instances/PoolInstance.sol';
import {IPoolAddressesProvider} from '../../../contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../../contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

/**
 * @title OneInchPoolInstance
 * @author 1inch
 * @notice Pool instance of the 1inch Earn market with NFT-gated (permissioned) liquidations.
 * @dev Thin subclass of the audited v3.7 `PoolInstance` — no core file is modified. The gate
 * follows the 1inch house pattern (swap-vm `_onlyTakerTokenBalanceNonZero`, FeeTaker access
 * token): a plain `balanceOf(caller) > 0` read through the IERC20 interface, which is
 * selector-compatible with ERC-721, so a `KycNFT` works natively. The NFT is only read,
 * never transferred.
 *
 * Safety properties:
 * - `LIQUIDATOR_GATE == address(0)` disables the gate entirely (fully permissionless
 *   liquidations, byte-for-byte `PoolInstance` behavior).
 * - The gate is an immutable, NOT storage: the Pool storage layout stays untouched for
 *   future v3.x upgrades.
 * - Enabling/disabling/changing the gate = deploying a new instance and calling
 *   `PoolAddressesProvider.setPoolImpl` (a 1inch DAO governance action, reversible anytime).
 *   Each newly installed instance must return a strictly higher `getRevision()`.
 * - No other Pool path is affected: `eliminateReserveDeficit` (Umbrella), position managers,
 *   flashloans and transfers behave exactly as in v3.7.
 */
contract OneInchPoolInstance is PoolInstance {
  /// @dev Thrown when a non KYC'd address attempts to liquidate while the gate is active.
  error OnlyKycLiquidators();

  /// @dev Must be strictly greater than the revision of the implementation it replaces
  /// (vanilla v3.7 `PoolInstance` is 11). Adopting a future upstream Pool revision N
  /// requires re-basing this contract on it with revision > N.
  uint256 public constant ONE_INCH_POOL_REVISION = 12;

  /// @notice KYC NFT (or any ERC20/ERC721 exposing `balanceOf`) gating `liquidationCall`.
  /// @dev address(0) = gate disabled (permissionless liquidations).
  IERC20 public immutable LIQUIDATOR_GATE;

  constructor(
    IPoolAddressesProvider provider,
    IReserveInterestRateStrategy interestRateStrategy_,
    IERC20 liquidatorGate
  ) PoolInstance(provider, interestRateStrategy_) {
    LIQUIDATOR_GATE = liquidatorGate;
  }

  function getRevision() internal pure virtual override returns (uint256) {
    return ONE_INCH_POOL_REVISION;
  }

  /**
   * @notice Returns true when `liquidator` is allowed to call `liquidationCall`.
   * @dev Helper for liquidation bots and UIs.
   */
  function isAuthorizedLiquidator(address liquidator) public view returns (bool) {
    return address(LIQUIDATOR_GATE) == address(0) || LIQUIDATOR_GATE.balanceOf(liquidator) > 0;
  }

  /**
   * @notice NFT-gated liquidation call; see {IPool-liquidationCall} for the base semantics.
   * @dev Reverts with {OnlyKycLiquidators} when the gate is active and the caller
   * (`_msgSender()`, ERC2771-aware like the rest of the Pool) holds no gate token.
   */
  function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address borrower,
    uint256 debtToCover,
    bool receiveAToken
  ) public virtual override {
    if (!isAuthorizedLiquidator(_msgSender())) revert OnlyKycLiquidators();
    super.liquidationCall(collateralAsset, debtAsset, borrower, debtToCover, receiveAToken);
  }
}
