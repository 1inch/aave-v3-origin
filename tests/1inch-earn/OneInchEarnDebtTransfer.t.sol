// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../src/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IPoolConfigurator} from '../../src/contracts/interfaces/IPoolConfigurator.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {KycNFT} from '../../src/deployments/projects/1inch-earn/KycNFT.sol';
import {OneInchPoolInstance} from '../../src/deployments/projects/1inch-earn/OneInchPoolInstance.sol';
import {OneInchVariableDebtToken} from '../../src/deployments/projects/1inch-earn/OneInchVariableDebtToken.sol';
import {OneInchDebtTransferValidation} from '../../src/deployments/projects/1inch-earn/OneInchDebtTransferValidation.sol';

/**
 * @title OneInchEarnDebtTransferTest
 * @notice Exercises the transferable debt token end-to-end on a local mock market:
 * the credit (receiver opt-in) consent model, the receiver health check via
 * finalizeDebtTransfer, the transferable/KYC guards, eMode borrowability, and the
 * documented limitation that a naive two-leg debt swap reverts on the intermediate
 * double-debt state.
 */
contract OneInchEarnDebtTransferTest is OneInchEarnTestBase {
  IPool internal pool;
  OneInchVariableDebtToken internal usdcDebt;

  address internal borrower;
  address internal receiver;
  address internal whale;

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    _installOneInchPool(); // needed for finalizeDebtTransfer

    borrower = makeAddr('borrower');
    receiver = makeAddr('receiver');
    whale = makeAddr('whale');

    usdcDebt = OneInchVariableDebtToken(pool.getReserveVariableDebtToken(tokens.usdc));

    // USDC + USDT liquidity so positions can borrow either.
    _mint(tokens.usdc, whale, 2_000_000e6);
    _mint(tokens.usdt, whale, 2_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    IERC20(tokens.usdt).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 2_000_000e6, whale, 0);
    pool.supply(tokens.usdt, 2_000_000e6, whale, 0);
    vm.stopPrank();

    // Borrower: 1 WBTC ($100k) collateral, borrows 50k USDC (healthy).
    _supply(borrower, tokens.wbtc, 1e8);
    vm.prank(borrower);
    pool.borrow(tokens.usdc, 50_000e6, 2, 0, borrower);

    // Enable transfers for USDC debt (bootstrap pool admin = deployer).
    vm.prank(deployer);
    usdcDebt.setTransferable(true);
  }

  function test_happyPath_creditThenTransfer() public {
    // Receiver has spare collateral and opts in by crediting the borrower.
    _supply(receiver, tokens.wbtc, 2e8); // $200k
    uint256 amount = 40_000e6;

    vm.prank(receiver);
    usdcDebt.credit(borrower, amount);

    uint256 borrowerBefore = usdcDebt.balanceOf(borrower);
    uint256 receiverBefore = usdcDebt.balanceOf(receiver);
    assertEq(receiverBefore, 0, 'receiver starts debt-free');

    vm.prank(borrower);
    usdcDebt.transfer(receiver, amount);

    assertApproxEqAbs(
      usdcDebt.balanceOf(borrower),
      borrowerBefore - amount,
      2,
      'borrower debt down'
    );
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), amount, 2, 'receiver debt up');

    // Receiver is now a borrower and stays solvent; borrower still solvent.
    (, , , , , uint256 receiverHf) = pool.getUserAccountData(receiver);
    assertGt(receiverHf, 1e18, 'receiver healthy');
  }

  function test_emitsTransferEvent() public {
    // The debt move must emit ERC20 Transfer(from, to, amount) so balance indexers stay correct.
    _supply(receiver, tokens.wbtc, 2e8);
    uint256 amount = 30_000e6;
    vm.prank(receiver);
    usdcDebt.credit(borrower, amount);

    vm.expectEmit(true, true, false, true, address(usdcDebt));
    emit IERC20.Transfer(borrower, receiver, amount);

    vm.prank(borrower);
    usdcDebt.transfer(receiver, amount);
  }

  function test_revert_withoutCredit() public {
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.InsufficientCredit.selector);
    usdcDebt.transfer(receiver, 10_000e6);
  }

  function test_revert_whenTransfersDisabled() public {
    // USDT debt token keeps transfers OFF (only USDC was enabled in setUp).
    OneInchVariableDebtToken usdtDebt = OneInchVariableDebtToken(
      pool.getReserveVariableDebtToken(tokens.usdt)
    );
    vm.prank(receiver);
    usdtDebt.credit(borrower, 10_000e6);
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.TransfersDisabled.selector);
    usdtDebt.transfer(receiver, 10_000e6);
  }

  function test_revert_selfTransfer() public {
    vm.prank(borrower);
    usdcDebt.credit(borrower, 10_000e6);
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.SelfTransferNotAllowed.selector);
    usdcDebt.transfer(borrower, 10_000e6);
  }

  function test_revert_receiverWouldBeUnhealthy() public {
    // Receiver has thin collateral: cannot absorb 40k of debt.
    _supply(receiver, tokens.wbtc, 1e6); // ~$1k collateral
    uint256 amount = 40_000e6;
    vm.prank(receiver);
    usdcDebt.credit(borrower, amount);
    vm.prank(borrower);
    vm.expectRevert(); // HealthFactorLowerThanLiquidationThreshold
    usdcDebt.transfer(receiver, amount);
  }

  function test_kycGatedReceiver() public {
    KycNFT kyc = new KycNFT('Debt KYC', 'DKYC', '1', deployer);
    vm.prank(deployer);
    usdcDebt.setDebtReceiverGate(IERC20(address(kyc)));

    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 10_000e6);

    // Receiver has no KYC token yet.
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.ReceiverNotAllowed.selector);
    usdcDebt.transfer(receiver, 10_000e6);

    // Mint KYC to receiver -> allowed.
    vm.prank(deployer);
    kyc.mint(receiver, 1);
    vm.prank(borrower);
    usdcDebt.transfer(receiver, 10_000e6);
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), 10_000e6, 2, 'kyc receiver assumed debt');
  }

  function test_revert_eModeDebtNotBorrowable() public {
    // Receiver enters the ETH-correlated eMode (only WETH borrowable there), backed by WETH,
    // then tries to receive USDC debt -> rejected.
    _supplyWeth(receiver, 60 ether);
    uint8 emodeId = listingPayloadEModeId(); // hoist: avoid the prank being consumed by this call
    vm.prank(receiver);
    pool.setUserEMode(emodeId);

    vm.prank(receiver);
    usdcDebt.credit(borrower, 10_000e6);
    vm.prank(borrower);
    vm.expectRevert(OneInchDebtTransferValidation.DebtNotBorrowableInEMode.selector);
    usdcDebt.transfer(receiver, 10_000e6);
  }

  function test_creditWithSig() public {
    uint256 receiverPk = 0xA11CE;
    address sigReceiver = vm.addr(receiverPk);
    _supply(sigReceiver, tokens.wbtc, 2e8);

    uint256 amount = 10_000e6;
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 structHash = keccak256(
      abi.encode(
        usdcDebt.CREDIT_WITH_SIG_TYPEHASH(),
        borrower,
        amount,
        usdcDebt.creditNonces(sigReceiver),
        deadline
      )
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', usdcDebt.DOMAIN_SEPARATOR(), structHash)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(receiverPk, digest);

    usdcDebt.creditWithSig(sigReceiver, borrower, amount, deadline, v, r, s);
    assertEq(usdcDebt.creditAllowance(sigReceiver, borrower), amount, 'sig credit set');

    vm.prank(borrower);
    usdcDebt.transfer(sigReceiver, amount);
    assertApproxEqAbs(usdcDebt.balanceOf(sigReceiver), amount, 2, 'sig receiver assumed debt');
  }

  function test_naiveTwoLegSwapReverts() public {
    // Documents the limitation: a debt-for-debt swap cannot settle as two raw transfers,
    // because the first leg's receiver transiently holds BOTH debts and fails the HF check.
    OneInchVariableDebtToken usdtDebt = OneInchVariableDebtToken(
      pool.getReserveVariableDebtToken(tokens.usdt)
    );
    vm.prank(deployer);
    usdtDebt.setTransferable(true);

    // Counterparty B: $100k collateral, borrows 70k USDT (near its 75% LTV).
    address partyB = makeAddr('partyB');
    _supply(partyB, tokens.wbtc, 1e8);
    vm.prank(partyB);
    pool.borrow(tokens.usdt, 70_000e6, 2, 0, partyB);

    // Leg 1: borrower pushes its 50k USDC debt onto B. B now would owe USDT+USDC -> unhealthy.
    vm.prank(partyB);
    usdcDebt.credit(borrower, 40_000e6);
    vm.prank(borrower);
    vm.expectRevert(); // receiver HF check fails on the intermediate double-debt state
    usdcDebt.transfer(partyB, 40_000e6);
  }

  function test_interestAccrualAndScaledSupplyConservation() public {
    _supply(receiver, tokens.wbtc, 2e8);

    // Let interest accrue on the borrower's existing debt.
    vm.warp(block.timestamp + 30 days);

    uint256 scaledSupplyBefore = usdcDebt.scaledTotalSupply();
    uint256 totalUnderlyingBefore = usdcDebt.balanceOf(borrower) + usdcDebt.balanceOf(receiver);

    uint256 amount = 20_000e6;
    vm.prank(receiver);
    usdcDebt.credit(borrower, amount);
    vm.prank(borrower);
    usdcDebt.transfer(receiver, amount);

    // A transfer moves scaled debt between users; it never changes total scaled supply.
    assertEq(usdcDebt.scaledTotalSupply(), scaledSupplyBefore, 'scaled supply conserved');
    // Underlying debt is conserved across the move (within ceil-rounding dust).
    assertApproxEqAbs(
      usdcDebt.balanceOf(borrower) + usdcDebt.balanceOf(receiver),
      totalUnderlyingBefore,
      3,
      'underlying debt conserved'
    );

    // Both positions keep accruing interest afterwards.
    uint256 borrowerAfter = usdcDebt.balanceOf(borrower);
    uint256 receiverAfter = usdcDebt.balanceOf(receiver);
    vm.warp(block.timestamp + 30 days);
    assertGt(usdcDebt.balanceOf(borrower), borrowerAfter, 'borrower keeps accruing');
    assertGt(usdcDebt.balanceOf(receiver), receiverAfter, 'receiver accrues on assumed debt');
  }

  function test_fullBalanceExitWithMaxSentinel() public {
    _supply(receiver, tokens.wbtc, 3e8);
    vm.warp(block.timestamp + 10 days); // ensure a non-unit index so rounding matters

    uint256 fullDebt = usdcDebt.balanceOf(borrower);
    vm.prank(receiver);
    usdcDebt.credit(borrower, type(uint256).max);

    vm.prank(borrower);
    usdcDebt.transfer(receiver, type(uint256).max);

    assertEq(usdcDebt.balanceOf(borrower), 0, 'borrower fully exited');
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), fullDebt, 3, 'receiver holds the whole debt');
  }

  function test_infiniteCreditNotDecremented() public {
    _supply(receiver, tokens.wbtc, 3e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, type(uint256).max);

    vm.prank(borrower);
    usdcDebt.transfer(receiver, 10_000e6);
    assertEq(
      usdcDebt.creditAllowance(receiver, borrower),
      type(uint256).max,
      'infinite credit persists'
    );
  }

  function test_transferFromByOwner() public {
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 15_000e6);
    vm.prank(borrower);
    usdcDebt.transferFrom(borrower, receiver, 15_000e6);
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), 15_000e6, 2, 'owner transferFrom works');
  }

  function test_revert_transferFromByNonOwner() public {
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 15_000e6);
    address stranger = makeAddr('stranger');
    vm.prank(stranger);
    vm.expectRevert(OneInchVariableDebtToken.CallerNotDebtOwner.selector);
    usdcDebt.transferFrom(borrower, receiver, 15_000e6);
  }

  function test_receiverMinHealthFactorBuffer() public {
    _supply(receiver, tokens.wbtc, 2e8); // $200k
    uint256 amount = 40_000e6;
    vm.prank(receiver);
    usdcDebt.credit(borrower, amount);

    // Require a very high buffer the receiver cannot meet -> revert.
    vm.prank(deployer);
    usdcDebt.setReceiverMinHealthFactor(50e18);
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.ReceiverHealthFactorTooLow.selector);
    usdcDebt.transfer(receiver, amount);

    // Lower the buffer below the receiver's post-transfer HF -> succeeds.
    vm.prank(deployer);
    usdcDebt.setReceiverMinHealthFactor(2e18);
    vm.prank(borrower);
    usdcDebt.transfer(receiver, amount);
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), amount, 2, 'transfer within buffer');
  }

  function test_revert_pausedReserve() public {
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 10_000e6);
    vm.prank(deployer);
    IPoolConfigurator(report.poolConfiguratorProxy).setReservePause(tokens.usdc, true);
    vm.prank(borrower);
    vm.expectRevert(OneInchDebtTransferValidation.ReservePaused.selector);
    usdcDebt.transfer(receiver, 10_000e6);
  }

  function test_revert_frozenReserve() public {
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 10_000e6);
    vm.prank(deployer);
    IPoolConfigurator(report.poolConfiguratorProxy).setReserveFreeze(tokens.usdc, true);
    vm.prank(borrower);
    vm.expectRevert(OneInchDebtTransferValidation.ReserveFrozen.selector);
    usdcDebt.transfer(receiver, 10_000e6);
  }

  function test_revert_borrowingDisabledReserve() public {
    // Governance disables borrowing on USDC while the borrower already holds debt: the debt
    // becomes non-transferable to a receiver (borrow-side check), same rule that keeps the
    // red-row 1INCH/AQUA debt (which can never exist) unassumable.
    _supply(receiver, tokens.wbtc, 2e8);
    vm.prank(receiver);
    usdcDebt.credit(borrower, 10_000e6);
    vm.prank(deployer);
    IPoolConfigurator(report.poolConfiguratorProxy).setReserveBorrowing(tokens.usdc, false);
    vm.prank(borrower);
    vm.expectRevert(OneInchDebtTransferValidation.BorrowingNotEnabled.selector);
    usdcDebt.transfer(receiver, 10_000e6);
  }

  // --------------------------------- helpers -----------------------------------

  function listingPayloadEModeId() internal view returns (uint8) {
    return listingPayload.EMODE_CATEGORY_ID();
  }

  function _installOneInchPool() internal {
    OneInchPoolInstance impl = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      IERC20(address(0))
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(impl));
  }

  function _supply(address user, address token, uint256 amount) internal {
    _mint(token, user, amount);
    vm.startPrank(user);
    IERC20(token).approve(address(pool), type(uint256).max);
    pool.supply(token, amount, user, 0);
    vm.stopPrank();
  }

  function _supplyWeth(address user, uint256 amount) internal {
    deal(tokens.weth, user, amount);
    vm.startPrank(user);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, amount, user, 0);
    vm.stopPrank();
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}

/**
 * @title OneInchEarnDebtTransferVanillaPoolTest
 * @notice Fail-closed guarantee: if `transferable` is enabled on a reserve while the market is
 * still running the vanilla `PoolInstance` (which lacks `finalizeDebtTransfer`), any debt
 * transfer reverts. Enabling transfers therefore requires the `OneInchPoolInstance` upgrade.
 */
contract OneInchEarnDebtTransferVanillaPoolTest is OneInchEarnTestBase {
  IPool internal pool;
  OneInchVariableDebtToken internal usdcDebt;
  address internal borrower;
  address internal receiver;

  function setUp() public {
    _deployMarketAndList(); // NOTE: deliberately does NOT install OneInchPoolInstance
    pool = IPool(report.poolProxy);
    borrower = makeAddr('borrower');
    receiver = makeAddr('receiver');
    usdcDebt = OneInchVariableDebtToken(pool.getReserveVariableDebtToken(tokens.usdc));

    address whale = makeAddr('whale');
    _mint(tokens.usdc, whale, 1_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 1_000_000e6, whale, 0);
    vm.stopPrank();

    _mint(tokens.wbtc, borrower, 1e8);
    vm.startPrank(borrower);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 1e8, borrower, 0);
    pool.borrow(tokens.usdc, 50_000e6, 2, 0, borrower);
    vm.stopPrank();

    vm.prank(deployer);
    usdcDebt.setTransferable(true);
  }

  function test_revert_transferOnVanillaPool() public {
    _mint(tokens.wbtc, receiver, 2e8);
    vm.startPrank(receiver);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 2e8, receiver, 0);
    usdcDebt.credit(borrower, 10_000e6);
    vm.stopPrank();

    // The pool has no `finalizeDebtTransfer` selector -> the token's callback reverts.
    vm.prank(borrower);
    vm.expectRevert();
    usdcDebt.transfer(receiver, 10_000e6);
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
