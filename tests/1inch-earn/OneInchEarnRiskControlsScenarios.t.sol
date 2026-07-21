// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '../../src/contracts/interfaces/IPoolConfigurator.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {Errors} from '../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnRiskControlsScenariosTest
 * @notice Exercises the risk-control surface end to end: supply/borrow cap enforcement, guardian
 * freeze/pause blocking pool actions, eMode liquidation, and eMode exit safety. These paths were
 * previously only asserted at config level, never triggered at runtime.
 */
contract OneInchEarnRiskControlsScenariosTest is OneInchEarnTestBase {
  IPool internal pool;
  IPoolConfigurator internal configurator;

  address internal whale = makeAddr('whale');
  address internal user = makeAddr('user');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    configurator = IPoolConfigurator(report.poolConfiguratorProxy);

    _mint(tokens.usdc, whale, 5_000_000e6);
    deal(tokens.weth, whale, 5_000 ether);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 3_000_000e6, whale, 0);
    pool.supply(tokens.weth, 2_000 ether, whale, 0);
    vm.stopPrank();
  }

  // --------------------------------- caps ---------------------------------

  function test_supplyCapEnforced() public {
    // WBTC supply cap is 100 (whole tokens). Supplying 101 must revert.
    _mint(tokens.wbtc, user, 101e8);
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    vm.expectRevert(Errors.SupplyCapExceeded.selector);
    pool.supply(tokens.wbtc, 101e8, user, 0);
    vm.stopPrank();
  }

  function test_borrowCapEnforced() public {
    // Tighten the USDC borrow cap to 1000, then a 1001 borrow must revert.
    vm.prank(deployer);
    configurator.setBorrowCap(tokens.usdc, 1_000);

    _mint(tokens.wbtc, user, 5e8); // ample collateral
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 5e8, user, 0);
    vm.expectRevert(Errors.BorrowCapExceeded.selector);
    pool.borrow(tokens.usdc, 1_001e6, 2, 0, user);
    vm.stopPrank();
  }

  // --------------------------------- freeze / pause ---------------------------------

  function test_freezeBlocksSupplyAndBorrowButAllowsRepayWithdraw() public {
    _mint(tokens.wbtc, user, 1e8);
    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    pool.borrow(tokens.usdc, 20_000e6, 2, 0, user);
    vm.stopPrank();

    vm.prank(deployer);
    configurator.setReserveFreeze(tokens.wbtc, true);

    // New supply blocked...
    _mint(tokens.wbtc, user, 1e8);
    vm.startPrank(user);
    vm.expectRevert(Errors.ReserveFrozen.selector);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    // ...but withdrawing existing collateral still works (winding down is always allowed).
    pool.withdraw(tokens.wbtc, 0.1e8, user);
    vm.stopPrank();

    // Borrowing a frozen reserve is also blocked.
    vm.prank(deployer);
    configurator.setReserveFreeze(tokens.usdc, true);
    vm.prank(user);
    vm.expectRevert(Errors.ReserveFrozen.selector);
    pool.borrow(tokens.usdc, 1e6, 2, 0, user);
  }

  function test_pauseBlocksAllActions() public {
    _mint(tokens.wbtc, user, 1e8);
    vm.prank(deployer);
    configurator.setReservePause(tokens.wbtc, true, 0);

    vm.startPrank(user);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    vm.expectRevert(Errors.ReservePaused.selector);
    pool.supply(tokens.wbtc, 1e8, user, 0);
    vm.stopPrank();
  }

  // --------------------------------- eMode liquidation + exit ---------------------------------

  function test_emodeLiquidation() public {
    // Borrower supplies wstETH, enters ETH eMode, borrows WETH near the eMode LTV.
    _mint(tokens.wstEth, user, 20e18); // ~$78k
    vm.startPrank(user);
    IERC20(tokens.wstEth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wstEth, 20e18, user, 0);
    pool.setUserEMode(OneInchEarnConfig.ETH_CORRELATED_EMODE_ID);
    pool.borrow(tokens.weth, 20 ether, 2, 0, user); // ~$66k, allowed at 90% eMode LTV
    vm.stopPrank();

    // wstETH de-pegs down ~15% -> HF < 1 (LT 93% in eMode).
    vm.mockCall(
      feeds.wstEth,
      abi.encodeWithSignature('latestAnswer()'),
      abi.encode(int256(3_300e8))
    );
    (, , , , , uint256 hf) = pool.getUserAccountData(user);
    assertLt(hf, 1e18, 'eMode position underwater');

    address liquidator = makeAddr('liquidator');
    deal(tokens.weth, liquidator, 50 ether);
    uint256 collBefore = IERC20(pool.getReserveAToken(tokens.wstEth)).balanceOf(user);
    vm.startPrank(liquidator);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.liquidationCall(tokens.wstEth, tokens.weth, user, type(uint256).max, false);
    vm.stopPrank();

    assertLt(
      IERC20(pool.getReserveAToken(tokens.wstEth)).balanceOf(user),
      collBefore,
      'eMode collateral seized in liquidation'
    );
    assertGt(IERC20(tokens.wstEth).balanceOf(liquidator), 0, 'liquidator received wstETH + bonus');
  }

  function test_exitEModeRevertsWhenItWouldUndercollateralize() public {
    // A position that only stays healthy thanks to the eMode LTV boost cannot leave eMode.
    _mint(tokens.wstEth, user, 20e18);
    vm.startPrank(user);
    IERC20(tokens.wstEth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wstEth, 20e18, user, 0);
    pool.setUserEMode(OneInchEarnConfig.ETH_CORRELATED_EMODE_ID);
    pool.borrow(tokens.weth, 20 ether, 2, 0, user); // > base 80% LTV, only OK under eMode

    vm.expectRevert(Errors.HealthFactorLowerThanLiquidationThreshold.selector);
    pool.setUserEMode(0); // exit eMode -> base LTV can't cover -> revert
    vm.stopPrank();
  }

  function test_exitEModeSucceedsWhenSafe() public {
    _mint(tokens.wstEth, user, 20e18);
    vm.startPrank(user);
    IERC20(tokens.wstEth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wstEth, 20e18, user, 0);
    pool.setUserEMode(OneInchEarnConfig.ETH_CORRELATED_EMODE_ID);
    pool.borrow(tokens.weth, 5 ether, 2, 0, user); // small, safe under base LTV too
    pool.setUserEMode(0); // exit is fine
    vm.stopPrank();
    assertEq(pool.getUserEMode(user), 0, 'exited eMode');
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
