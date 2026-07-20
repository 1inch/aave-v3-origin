// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {PoolInstance} from '../../../contracts/instances/PoolInstance.sol';
import {IPoolAddressesProvider} from '../../../contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../../contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IACLManager} from '../../../contracts/interfaces/IACLManager.sol';
import {Errors} from '../../../contracts/protocol/libraries/helpers/Errors.sol';
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
 * Storage & upgrade safety:
 * - The gate address lives in an ERC-7201 namespaced slot, NOT in sequential Pool storage,
 *   so it can never collide with the audited Pool layout or any future upstream v3.x
 *   storage additions.
 * - It is seeded from a constructor immutable during `initialize` (run when the impl is
 *   installed via `setPoolImpl`), so there is no permissionless gap between install and
 *   configuration.
 *
 * Governance control (matches the briefing's "guardian veto on everything" posture):
 * - `setLiquidatorGate` is callable by POOL_ADMIN or EMERGENCY_ADMIN, so the DAO can rotate
 *   the KYC contract, and the guardian can OPEN liquidations instantly in a crisis
 *   (`gate = address(0)`) — a single transaction, no pool upgrade required.
 * - `gate == address(0)` disables the gate entirely (fully permissionless liquidations).
 *
 * Scope: only `liquidationCall` is gated. `eliminateReserveDeficit` (Umbrella), position
 * managers, flashloans and transfers behave exactly as in v3.7.
 */
contract OneInchPoolInstance is PoolInstance {
  /// @dev Thrown when a non KYC'd address attempts to liquidate while the gate is active.
  error OnlyKycLiquidators();
  /// @dev Thrown when a non-admin attempts to change the liquidator gate.
  error CallerNotPoolOrEmergencyAdmin();

  event LiquidatorGateUpdated(address indexed oldGate, address indexed newGate);

  /// @dev Must be strictly greater than the revision of the implementation it replaces
  /// (vanilla v3.7 `PoolInstance` is 11). Adopting a future upstream Pool revision N
  /// requires re-basing this contract on it with revision > N.
  uint256 public constant ONE_INCH_POOL_REVISION = 12;

  /// @dev ERC-7201 namespaced storage location:
  /// keccak256(abi.encode(uint256(keccak256("oneinch.earn.storage.LiquidatorGate")) - 1)) & ~0xff
  bytes32 private constant LIQUIDATOR_GATE_STORAGE =
    0x6691a854ab1934d27ab045857bb2da759a05bbccc283bf0e0d4cad63ea80a700;

  /// @notice Initial gate seeded into storage on install. address(0) = start permissionless.
  IERC20 internal immutable INITIAL_LIQUIDATOR_GATE;

  /// @custom:storage-location erc7201:oneinch.earn.storage.LiquidatorGate
  struct LiquidatorGateStorage {
    IERC20 gate;
  }

  constructor(
    IPoolAddressesProvider provider,
    IReserveInterestRateStrategy interestRateStrategy_,
    IERC20 initialGate
  ) PoolInstance(provider, interestRateStrategy_) {
    INITIAL_LIQUIDATOR_GATE = initialGate;
  }

  /**
   * @inheritdoc PoolInstance
   * @dev Seeds the gate from the constructor immutable into namespaced storage the first
   * time this implementation is installed on the proxy.
   */
  function initialize(IPoolAddressesProvider provider) external override initializer {
    require(provider == ADDRESSES_PROVIDER, Errors.InvalidAddressesProvider());
    _getGateStorage().gate = INITIAL_LIQUIDATOR_GATE;
  }

  function getRevision() internal pure virtual override returns (uint256) {
    return ONE_INCH_POOL_REVISION;
  }

  /// @notice The ERC20/ERC721 whose balance gates `liquidationCall`. address(0) = disabled.
  function liquidatorGate() public view returns (IERC20) {
    return _getGateStorage().gate;
  }

  /**
   * @notice Sets (or clears) the liquidator gate token. Callable by POOL_ADMIN or
   * EMERGENCY_ADMIN. Set to address(0) to make liquidations permissionless again.
   */
  function setLiquidatorGate(IERC20 gate) external {
    IACLManager acl = IACLManager(ADDRESSES_PROVIDER.getACLManager());
    if (!acl.isPoolAdmin(_msgSender()) && !acl.isEmergencyAdmin(_msgSender())) {
      revert CallerNotPoolOrEmergencyAdmin();
    }
    LiquidatorGateStorage storage $ = _getGateStorage();
    emit LiquidatorGateUpdated(address($.gate), address(gate));
    $.gate = gate;
  }

  /**
   * @notice Returns true when `liquidator` is allowed to call `liquidationCall`.
   * @dev Helper for liquidation bots and UIs.
   */
  function isAuthorizedLiquidator(address liquidator) public view returns (bool) {
    IERC20 gate = _getGateStorage().gate;
    return address(gate) == address(0) || gate.balanceOf(liquidator) > 0;
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

  function _getGateStorage() private pure returns (LiquidatorGateStorage storage $) {
    assembly {
      $.slot := LIQUIDATOR_GATE_STORAGE
    }
  }
}
