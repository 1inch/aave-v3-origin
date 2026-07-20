// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IPool} from '../../../contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../../contracts/interfaces/IPoolAddressesProvider.sol';
import {IFlashLoanReceiver} from '../../../contracts/misc/flashloan/interfaces/IFlashLoanReceiver.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title OneInchEarnDebtSwapAdapter
 * @author 1inch
 * @notice Peer-to-peer debt swap for the 1inch Earn market: atomically swaps a maker's debt in
 * asset X for debt in asset Y with a taker who wants the opposite, WITHOUT routing through a DEX
 * (the two opposite demands net directly). Each party's new debt is backed by their OWN collateral;
 * both must consent via credit delegation to this adapter.
 *
 * This is the correct settlement path for a debt-for-debt swap (the raw two-transfer path on the
 * transferable debt token reverts on the intermediate double-debt state). It never holds a position
 * and can hold no user funds beyond the in-flight flashloan.
 *
 * Flow (one transaction, no double-debt at any point):
 *  1. Flash-borrow makerDebtAmount of X and takerDebtAmount of Y (mode 0 = repaid in full).
 *  2. Repay the maker's X debt and the taker's Y debt (both now shed).
 *  3. Borrow Y on behalf of the maker and X on behalf of the taker (their credit delegations).
 *  4. Repay the flashloans; the flashloan premium is pulled from `premiumPayer`.
 *
 * Economics: the maker sheds `makerDebtAmount` of X and takes on `takerDebtAmount` of Y; the taker
 * does the mirror. The rebate the maker gets ("receive less debt") is exactly the extra debt the
 * taker assumes (makerDebtAmount vs takerDebtAmount in value) — a fully internal P2P spread. The
 * only external cost is the flashloan premium, covered by `premiumPayer`.
 *
 * @dev Pre-reqs the integrating UI/settlement must arrange before calling `swapDebt`:
 *  - maker: `approveDelegation(adapter, >= takerDebtAmount)` on Y's variable debt token.
 *  - taker: `approveDelegation(adapter, >= makerDebtAmount)` on X's variable debt token.
 *  - premiumPayer: approve this adapter to pull the flashloan premium in X and Y.
 * The pool's borrow validation health-checks each borrower, so an unhealthy resulting position
 * for either party reverts the whole swap.
 */
contract OneInchEarnDebtSwapAdapter is IFlashLoanReceiver {
  using SafeERC20 for IERC20;

  error CallerNotPool();
  error InitiatorNotAdapter();
  error UnexpectedFlashAssets();

  uint256 internal constant VARIABLE_RATE_MODE = 2;

  IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
  IPool public immutable override POOL;

  struct DebtSwapParams {
    address maker;
    address taker;
    address makerDebtAsset; // X: the maker sheds this, the taker assumes it
    uint256 makerDebtAmount; // amount of X
    address takerDebtAsset; // Y: the taker sheds this, the maker assumes it
    uint256 takerDebtAmount; // amount of Y
    address premiumPayer; // funds the flashloan premium (must approve this adapter for X and Y)
  }

  constructor(IPool pool) {
    POOL = pool;
    ADDRESSES_PROVIDER = pool.ADDRESSES_PROVIDER();
  }

  /// @notice Executes the P2P debt swap. Anyone may call (e.g. an Aqua settlement contract);
  /// the swap only succeeds if both parties delegated credit and both end solvent.
  function swapDebt(DebtSwapParams calldata p) external {
    address[] memory assets = new address[](2);
    assets[0] = p.makerDebtAsset;
    assets[1] = p.takerDebtAsset;

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = p.makerDebtAmount;
    amounts[1] = p.takerDebtAmount;

    uint256[] memory modes = new uint256[](2); // both 0 => flashloan repaid in full

    POOL.flashLoan(address(this), assets, amounts, modes, address(this), abi.encode(p), 0);
  }

  /// @inheritdoc IFlashLoanReceiver
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    require(msg.sender == address(POOL), CallerNotPool());
    require(initiator == address(this), InitiatorNotAdapter());

    DebtSwapParams memory p = abi.decode(params, (DebtSwapParams));
    require(
      assets[0] == p.makerDebtAsset && assets[1] == p.takerDebtAsset,
      UnexpectedFlashAssets()
    );

    // 1. Shed both parties' current debts using the flashed liquidity. Doing both repays before
    // any new borrow guarantees neither account ever holds both debts at once.
    IERC20(p.makerDebtAsset).forceApprove(address(POOL), amounts[0]);
    POOL.repay(p.makerDebtAsset, amounts[0], VARIABLE_RATE_MODE, p.maker);

    IERC20(p.takerDebtAsset).forceApprove(address(POOL), amounts[1]);
    POOL.repay(p.takerDebtAsset, amounts[1], VARIABLE_RATE_MODE, p.taker);

    // 2. Open the swapped debts on behalf of each party (requires their credit delegation).
    // Each borrow health-checks the borrower against their own collateral.
    POOL.borrow(p.takerDebtAsset, amounts[1], VARIABLE_RATE_MODE, 0, p.maker);
    POOL.borrow(p.makerDebtAsset, amounts[0], VARIABLE_RATE_MODE, 0, p.taker);

    // 3. Cover the flashloan premiums from the payer and approve the pool to pull repayment.
    if (premiums[0] > 0) {
      IERC20(p.makerDebtAsset).safeTransferFrom(p.premiumPayer, address(this), premiums[0]);
    }
    if (premiums[1] > 0) {
      IERC20(p.takerDebtAsset).safeTransferFrom(p.premiumPayer, address(this), premiums[1]);
    }
    IERC20(p.makerDebtAsset).forceApprove(address(POOL), amounts[0] + premiums[0]);
    IERC20(p.takerDebtAsset).forceApprove(address(POOL), amounts[1] + premiums[1]);

    return true;
  }
}
