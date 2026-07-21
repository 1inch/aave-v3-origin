// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICreditDelegationToken} from '../../src/contracts/interfaces/ICreditDelegationToken.sol';
import {IWrappedTokenGatewayV3} from '../../src/contracts/helpers/interfaces/IWrappedTokenGatewayV3.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {WETH9} from '../../src/contracts/dependencies/weth/WETH9.sol';

/**
 * @title OneInchEarnLifecycleScenariosTest
 * @notice End-to-end user journeys that fill runtime gaps not covered elsewhere: full
 * supply/withdraw and borrow/repay/withdraw cycles, repayWithATokens, the WrappedTokenGateway
 * native-ETH borrow/repay legs, supplier interest accrual over time, and reserve-factor interest
 * routed to the Collector treasury.
 */
contract OneInchEarnLifecycleScenariosTest is OneInchEarnTestBase {
  IPool internal pool;
  IWrappedTokenGatewayV3 internal gateway;

  address internal whale = makeAddr('whale');
  address internal user = makeAddr('user');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    gateway = IWrappedTokenGatewayV3(payable(report.wrappedTokenGateway));

    // Deep USDC + WETH liquidity. Wrap real ETH (not `deal`) so the WETH9 contract holds the
    // ETH backing — required for the gateway's unwrap-on-borrow/withdraw path to succeed.
    _mint(tokens.usdc, whale, 5_000_000e6);
    vm.deal(whale, 2_000 ether);
    vm.startPrank(whale);
    WETH9(payable(tokens.weth)).deposit{value: 2_000 ether}();
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 3_000_000e6, whale, 0);
    pool.supply(tokens.weth, 2_000 ether, whale, 0);
    vm.stopPrank();
  }

  function test_supplyWithdrawFullCycle() public {
    _mint(tokens.wbtc, user, 5e8);
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 5e8, user, 0);
    assertEq(IERC20(pool.getReserveAToken(tokens.wbtc)).balanceOf(user), 5e8, 'aWBTC minted 1:1');

    // Withdraw everything (max sentinel) — the previously-untested exit path.
    uint256 withdrawn = pool.withdraw(tokens.wbtc, type(uint256).max, user);
    vm.stopPrank();
    assertEq(withdrawn, 5e8, 'withdrew full balance');
    assertEq(IERC20(pool.getReserveAToken(tokens.wbtc)).balanceOf(user), 0, 'aWBTC burned');
    assertEq(IERC20(tokens.wbtc).balanceOf(user), 5e8, 'underlying returned');
  }

  function test_borrowRepayWithdrawFullCycle() public {
    _mint(tokens.wbtc, user, 1e8); // $100k collateral
    _mint(tokens.usdc, user, 100e6); // dust to cover accrued interest at repay
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    pool.borrow(tokens.usdc, 40_000e6, 2, 0, user);
    assertEq(IERC20(tokens.usdc).balanceOf(user), 40_000e6 + 100e6, 'received borrow');

    // Repay in full (max sentinel), then the collateral becomes fully withdrawable.
    pool.repay(tokens.usdc, type(uint256).max, 2, user);
    assertEq(
      IERC20(pool.getReserveVariableDebtToken(tokens.usdc)).balanceOf(user),
      0,
      'debt cleared'
    );
    uint256 out = pool.withdraw(tokens.wbtc, type(uint256).max, user);
    vm.stopPrank();
    assertEq(out, 1e8, 'collateral fully withdrawn after repay');
  }

  function test_repayWithATokens() public {
    // User supplies WBTC collateral + USDC (aUSDC), borrows USDC, then repays with its aUSDC.
    _mint(tokens.wbtc, user, 1e8);
    _mint(tokens.usdc, user, 50_000e6);
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    pool.supply(tokens.usdc, 50_000e6, user, 0);
    pool.borrow(tokens.usdc, 30_000e6, 2, 0, user);

    uint256 debtBefore = IERC20(pool.getReserveVariableDebtToken(tokens.usdc)).balanceOf(user);
    pool.repayWithATokens(tokens.usdc, 20_000e6, 2);
    vm.stopPrank();

    uint256 debtAfter = IERC20(pool.getReserveVariableDebtToken(tokens.usdc)).balanceOf(user);
    assertApproxEqAbs(debtBefore - debtAfter, 20_000e6, 2, 'debt reduced by aToken repay');
  }

  function test_wrappedTokenGatewayBorrowAndRepayEth() public {
    // Collateral: WBTC. Borrow native ETH via the gateway (requires WETH debt delegation).
    _mint(tokens.wbtc, user, 1e8);
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    vm.stopPrank();

    address wethDebt = pool.getReserveVariableDebtToken(tokens.weth);
    vm.prank(user);
    ICreditDelegationToken(wethDebt).approveDelegation(address(gateway), 10 ether);

    uint256 ethBefore = user.balance;
    vm.prank(user);
    gateway.borrowETH(address(pool), 5 ether, 0);
    assertEq(user.balance - ethBefore, 5 ether, 'received native ETH from borrow');
    assertApproxEqAbs(IERC20(wethDebt).balanceOf(user), 5 ether, 2, 'WETH debt opened');

    // Repay the ETH debt via the gateway (payable).
    vm.deal(user, user.balance + 6 ether);
    vm.prank(user);
    gateway.repayETH{value: 5 ether}(address(pool), type(uint256).max, user);
    assertEq(IERC20(wethDebt).balanceOf(user), 0, 'ETH debt repaid via gateway');
  }

  function test_supplierInterestAccruesOverTime() public {
    // Utilisation drives the supply rate: user supplies USDC, a borrower draws it, time passes.
    _mint(tokens.usdc, user, 100_000e6);
    vm.startPrank(user);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 100_000e6, user, 0);
    vm.stopPrank();

    address borrower = makeAddr('borrower');
    _mint(tokens.wbtc, borrower, 5e8);
    vm.startPrank(borrower);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 5e8, borrower, 0);
    pool.borrow(tokens.usdc, 200_000e6, 2, 0, borrower); // high utilisation
    vm.stopPrank();

    uint256 aBefore = IERC20(pool.getReserveAToken(tokens.usdc)).balanceOf(user);
    vm.warp(block.timestamp + 365 days);
    uint256 aAfter = IERC20(pool.getReserveAToken(tokens.usdc)).balanceOf(user);
    assertGt(aAfter, aBefore, 'aUSDC supplier balance grew with interest');
  }

  function test_reserveFactorAccruesToTreasury() public {
    address borrower = makeAddr('borrower');
    _mint(tokens.wbtc, borrower, 5e8);
    vm.startPrank(borrower);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 5e8, borrower, 0);
    pool.borrow(tokens.usdc, 200_000e6, 2, 0, borrower);
    vm.stopPrank();

    vm.warp(block.timestamp + 365 days);
    // Poke the reserve so interest is booked, then mint the reserve-factor share to the treasury.
    vm.prank(borrower);
    pool.borrow(tokens.usdc, 1e6, 2, 0, borrower);
    address[] memory assets = new address[](1);
    assets[0] = tokens.usdc;
    pool.mintToTreasury(assets);

    uint256 treasuryBal = IERC20(pool.getReserveAToken(tokens.usdc)).balanceOf(report.treasury);
    assertGt(treasuryBal, 0, 'reserve-factor interest routed to Collector treasury');
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
