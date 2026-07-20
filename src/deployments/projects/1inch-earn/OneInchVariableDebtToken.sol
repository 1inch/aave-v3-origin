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
  error CallerNotDebtOwner();
  error ReceiverHealthFactorTooLow();

  event CreditApproval(address indexed receiver, address indexed spender, uint256 amount);
  event TransferableSet(bool transferable);
  event DebtReceiverGateSet(address indexed gate);
  event ReceiverMinHealthFactorSet(uint256 minHealthFactor);
  event DebtTransferred(
    address indexed asset,
    address indexed from,
    address indexed to,
    uint256 amount
  );

  uint256 public constant ONE_INCH_DEBT_TOKEN_REVISION = 6;

  bytes32 public constant CREDIT_WITH_SIG_TYPEHASH =
    keccak256('CreditWithSig(address spender,uint256 value,uint256 nonce,uint256 deadline)');

  /// @dev receiver => spender => amount of debt `spender` may move onto `receiver`.
  mapping(address => mapping(address => uint256)) internal _creditAllowances;
  /// @dev separate nonce space from credit delegation's `_nonces`.
  mapping(address => uint256) internal _creditNonces;

  bool internal _transferable;
  IERC20 internal _debtReceiverGate;
  /// @dev Extra safety margin required of the receiver AFTER assuming debt. 0 = disabled
  /// (the base `validateHFAndLtv` >= 1e18 check still applies). e.g. 1.1e18 for a 10% buffer.
  uint256 internal _receiverMinHealthFactor;

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

  /// @notice Sets the minimum health factor the receiver must retain AFTER assuming debt.
  /// @dev 0 disables the extra buffer (base >= 1e18 check still applies). Set e.g. 1.1e18
  /// so a receiver can never be left immediately liquidatable by a debt handoff.
  function setReceiverMinHealthFactor(uint256 minHealthFactor) external onlyPoolAdmin {
    _receiverMinHealthFactor = minHealthFactor;
    emit ReceiverMinHealthFactorSet(minHealthFactor);
  }

  function transferable() external view returns (bool) {
    return _transferable;
  }

  function debtReceiverGate() external view returns (IERC20) {
    return _debtReceiverGate;
  }

  function receiverMinHealthFactor() external view returns (uint256) {
    return _receiverMinHealthFactor;
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
  /// Pass `type(uint256).max` to move the caller's entire debt.
  function transfer(address to, uint256 amount) external override returns (bool) {
    _debtTransfer(_msgSender(), to, amount);
    return true;
  }

  /// @notice Moves `from`'s debt to `to`. `from` MUST be the caller — debt can only be moved by
  /// its owner. Third-party/settlement-driven moves go through the P2P debt-swap adapter with an
  /// explicit maker authorization, not this path.
  function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
    if (from != _msgSender()) revert CallerNotDebtOwner();
    _debtTransfer(from, to, amount);
    return true;
  }

  function _debtTransfer(address from, address to, uint256 amount) internal {
    if (!_transferable) revert TransfersDisabled();
    if (from == to) revert SelfTransferNotAllowed();

    IERC20 gate = _debtReceiverGate;
    if (address(gate) != address(0) && gate.balanceOf(to) == 0) revert ReceiverNotAllowed();

    uint256 index = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);

    // Resolve the effective underlying amount + scaled amount, supporting the full-balance
    // sentinel so a debtor can always fully exit (a nominal `balanceOf` amount could otherwise
    // round the scaled amount above the held balance and revert).
    uint256 fromScaled = _userState[from].balance;
    uint256 scaledAmount;
    uint256 transferAmount;
    if (amount == type(uint256).max) {
      scaledAmount = fromScaled;
      transferAmount = scaledAmount.getVTokenBalance(index);
    } else {
      transferAmount = amount;
      scaledAmount = amount.getVTokenMintScaledAmount(index);
    }
    if (transferAmount == 0 || scaledAmount == 0) revert InvalidAmount();

    // Consume the receiver's credit granted to the debtor (`from`), by the underlying amount.
    uint256 currentCredit = _creditAllowances[to][from];
    if (currentCredit < transferAmount) revert InsufficientCredit();
    if (currentCredit != type(uint256).max) {
      _creditAllowances[to][from] = currentCredit - transferAmount;
    }

    _moveScaledDebt(from, to, transferAmount, scaledAmount, index);

    IOneInchEarnPool(address(POOL)).finalizeDebtTransfer(_underlyingAsset, from, to);

    // Optional extra receiver margin on top of the pool's >= 1e18 health-factor check.
    uint256 minHf = _receiverMinHealthFactor;
    if (minHf != 0) {
      (, , , , , uint256 healthFactor) = POOL.getUserAccountData(to);
      if (healthFactor < minHf) revert ReceiverHealthFactorTooLow();
    }

    emit DebtTransferred(_underlyingAsset, from, to, transferAmount);
  }

  /// @dev Moves scaled debt between accounts, mirroring `AToken._transfer` interest accounting:
  /// each user's stored index (`_userState[...].additionalData`) is refreshed and accrued
  /// interest is emitted before the move, so later mint/burn attribute interest correctly.
  /// Finally emits the ERC20 `Transfer(from, to, amount)` for the moved debt so balance
  /// indexers/subgraphs stay correct (neither `super._transfer` nor the accrual events cover it).
  function _moveScaledDebt(
    address from,
    address to,
    uint256 amount,
    uint256 scaledAmount,
    uint256 index
  ) internal {
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

    emit Transfer(from, to, amount);
  }
}
