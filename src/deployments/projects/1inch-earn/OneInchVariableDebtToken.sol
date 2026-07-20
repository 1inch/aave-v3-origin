// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {VariableDebtTokenInstance} from '../../../contracts/instances/VariableDebtTokenInstance.sol';
import {IPool} from '../../../contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ECDSA} from 'openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {Errors} from '../../../contracts/protocol/libraries/helpers/Errors.sol';
import {TokenMath} from '../../../contracts/protocol/libraries/helpers/TokenMath.sol';
import {IOneInchEarnPool} from './IOneInchEarnPool.sol';

/**
 * @title OneInchVariableDebtToken
 * @author 1inch
 * @notice Variable debt token for the 1inch Earn market that supports TRANSFERABLE debt,
 * porting the design proven in 1inch/money-market-protocol (`Debtoken.sol`).
 *
 * Consent model (inverted approval — the RECEIVER opts in):
 * - `approve`/`allowance` stay disabled (a debtor must not be able to hand debt to an
 *   unwilling address). Instead the debt receiver calls `credit(spender, amount)` (or signs
 *   `creditWithSig`) to authorize `spender` to move up to `amount` of debt ONTO them.
 * - `transfer(to, amount)` and `transferFrom(from, to, amount)` both consume the receiver's
 *   credit to `msg.sender`, so the receiver always consents.
 *
 * Safety:
 * - Only the debt is moved; the receiver backs it with their OWN collateral. The pool's
 *   `finalizeDebtTransfer` runs the borrow-side reserve/eMode checks, flips the borrowing
 *   flags, and health-checks the RECEIVER (the sender only improves).
 * - `transferable` is false by default and set per-reserve by POOL_ADMIN (post-audit).
 *   An optional `debtReceiverGate` (e.g. a `KycNFT`) can restrict who may assume debt.
 *
 * @dev Subclass only — the audited `VariableDebtToken`/`VariableDebtTokenInstance` are
 * untouched. Deployed as a fresh per-market implementation, so the appended storage
 * (`_creditAllowances`, `_creditNonces`, `_transferable`, `_debtReceiverGate`) is layout-safe.
 */
contract OneInchVariableDebtToken is VariableDebtTokenInstance {
  using TokenMath for uint256;
  using SafeCast for uint256;

  error TransfersDisabled();
  error InsufficientCredit();
  error ReceiverNotAllowed();
  error SelfTransferNotAllowed();
  error InvalidAmount();
  error InsufficientDebt();

  event CreditApproval(address indexed receiver, address indexed spender, uint256 amount);
  event TransferableSet(bool transferable);
  event DebtReceiverGateSet(address indexed gate);

  uint256 public constant ONE_INCH_DEBT_TOKEN_REVISION = 6;

  bytes32 public constant CREDIT_WITH_SIG_TYPEHASH =
    keccak256('CreditWithSig(address spender,uint256 value,uint256 nonce,uint256 deadline)');

  /// @dev receiver => spender => amount of debt `spender` may move onto `receiver`.
  mapping(address => mapping(address => uint256)) internal _creditAllowances;
  /// @dev separate nonce space from credit delegation's `_nonces`.
  mapping(address => uint256) internal _creditNonces;

  bool internal _transferable;
  IERC20 internal _debtReceiverGate;

  constructor(
    IPool pool,
    address rewardsController
  ) VariableDebtTokenInstance(pool, rewardsController) {}

  function getRevision() internal pure virtual override returns (uint256) {
    return ONE_INCH_DEBT_TOKEN_REVISION;
  }

  // --------------------------------- governance --------------------------------

  /// @notice Enables/disables debt transfers for this reserve (default: disabled).
  function setTransferable(bool transferable_) external onlyPoolAdmin {
    _transferable = transferable_;
    emit TransferableSet(transferable_);
  }

  /// @notice Sets an optional gate token (e.g. KycNFT). address(0) = no receiver restriction.
  function setDebtReceiverGate(IERC20 gate) external onlyPoolAdmin {
    _debtReceiverGate = gate;
    emit DebtReceiverGateSet(address(gate));
  }

  function transferable() external view returns (bool) {
    return _transferable;
  }

  function debtReceiverGate() external view returns (IERC20) {
    return _debtReceiverGate;
  }

  // ---------------------------- consent (credit) -------------------------------

  /// @notice Receiver authorizes `spender` to move up to `amount` of debt onto the caller.
  function credit(address spender, uint256 amount) external returns (bool) {
    _creditAllowances[_msgSender()][spender] = amount;
    emit CreditApproval(_msgSender(), spender, amount);
    return true;
  }

  /// @notice Gasless variant: `receiver` signs the credit approval (e.g. inside an Aqua order).
  function creditWithSig(
    address receiver,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    require(receiver != address(0), Errors.ZeroAddressNotValid());
    require(block.timestamp <= deadline, Errors.InvalidExpiration());
    uint256 currentValidNonce = _creditNonces[receiver];
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        DOMAIN_SEPARATOR(),
        keccak256(abi.encode(CREDIT_WITH_SIG_TYPEHASH, spender, value, currentValidNonce, deadline))
      )
    );
    require(receiver == ECDSA.recover(digest, v, r, s), Errors.InvalidSignature());
    _creditNonces[receiver] = currentValidNonce + 1;
    _creditAllowances[receiver][spender] = value;
    emit CreditApproval(receiver, spender, value);
  }

  function creditAllowance(address receiver, address spender) external view returns (uint256) {
    return _creditAllowances[receiver][spender];
  }

  function creditNonces(address receiver) external view returns (uint256) {
    return _creditNonces[receiver];
  }

  // -------------------------------- transfers ----------------------------------

  /// @notice Moves the caller's own debt to `to`; requires `to` to have credited the caller.
  function transfer(address to, uint256 amount) external override returns (bool) {
    return _spendCreditAndTransfer(_msgSender(), _msgSender(), to, amount);
  }

  /// @notice Moves `from`'s debt to `to`; requires `to` to have credited the caller.
  function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
    return _spendCreditAndTransfer(_msgSender(), from, to, amount);
  }

  function _spendCreditAndTransfer(
    address spender,
    address from,
    address to,
    uint256 amount
  ) internal returns (bool) {
    uint256 currentCredit = _creditAllowances[to][spender];
    if (currentCredit < amount) revert InsufficientCredit();
    if (currentCredit != type(uint256).max) {
      _creditAllowances[to][spender] = currentCredit - amount;
    }
    _executeDebtTransfer(from, to, amount);
    return true;
  }

  function _executeDebtTransfer(address from, address to, uint256 amount) internal {
    if (!_transferable) revert TransfersDisabled();
    if (amount == 0) revert InvalidAmount();
    if (from == to) revert SelfTransferNotAllowed();

    IERC20 gate = _debtReceiverGate;
    if (address(gate) != address(0) && gate.balanceOf(to) == 0) revert ReceiverNotAllowed();

    uint256 index = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);
    uint256 scaledAmount = amount.getVTokenMintScaledAmount(index);

    _moveScaledDebt(from, to, scaledAmount, index);

    IOneInchEarnPool(address(POOL)).finalizeDebtTransfer(_underlyingAsset, from, to);
  }

  /// @dev Moves scaled debt between accounts, mirroring `AToken._transfer` interest accounting:
  /// each user's stored index (`_userState[...].additionalData`) is refreshed and accrued
  /// interest is emitted before the move, so later mint/burn attribute interest correctly.
  function _moveScaledDebt(address from, address to, uint256 scaledAmount, uint256 index) internal {
    uint256 fromScaled = _userState[from].balance;
    if (fromScaled < scaledAmount) revert InsufficientDebt();
    uint256 toScaled = _userState[to].balance;

    uint256 fromIncrease = fromScaled.getVTokenBalance(index) -
      fromScaled.getVTokenBalance(_userState[from].additionalData);
    uint256 toIncrease = toScaled.getVTokenBalance(index) -
      toScaled.getVTokenBalance(_userState[to].additionalData);

    _userState[from].additionalData = index.toUint128();
    _userState[to].additionalData = index.toUint128();

    super._transfer(from, to, scaledAmount.toUint120());

    if (fromIncrease > 0) {
      emit Transfer(address(0), from, fromIncrease);
      emit Mint(_msgSender(), from, fromIncrease, fromIncrease, index);
    }
    if (toIncrease > 0) {
      emit Transfer(address(0), to, toIncrease);
      emit Mint(_msgSender(), to, toIncrease, toIncrease, index);
    }
  }
}
