// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {Errors} from '../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {IWrappedTokenGatewayV3} from '../../src/contracts/helpers/interfaces/IWrappedTokenGatewayV3.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title OneInchEarnScenariosTest
 * @notice End-to-end user-journey scenarios on the (ungated) 1inch Earn market: eMode leverage
 * loops (ETH + stablecoin), liquidation variants, the v3.3 bad-debt deficit + Umbrella cover flow,
 * and the WrappedTokenGateway native-ETH path.
 */
contract OneInchEarnScenariosTest is OneInchEarnTestBase {
  IPool internal pool;

  address internal user = makeAddr('user');
  address internal user2 = makeAddr('user2');
  address internal whale = makeAddr('scenarioWhale');
  address internal liquidator = makeAddr('liquidator');
  address internal umbrella = makeAddr('umbrella');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
  }

  function test_ethEModeLeverageLoop() public {
    _supplyFrom(whale, tokens.weth, 200 ether); // WETH liquidity

    // 20 wstETH ~ $78k. Base wstETH LTV 80% => ~18.9 WETH cap; ETH eMode 90% => ~21.3 WETH cap.
    _mintSupply(user, tokens.wstEth, 20e18);
    vm.prank(user);
    pool.setUserEMode(OneInchEarnConfig.ETH_CORRELATED_EMODE_ID);
    assertEq(pool.getUserEMode(user), OneInchEarnConfig.ETH_CORRELATED_EMODE_ID, 'in ETH eMode');

    // 20 WETH ($66k) exceeds the 80% base cap but is within the 90% eMode cap.
    vm.prank(user);
    pool.borrow(tokens.weth, 20 ether, 2, 0, user);
    (, , , , , uint256 hf) = pool.getUserAccountData(user);
    assertGt(hf, 1e18, 'eMode borrower healthy');

    // Counterfactual: same collateral, NO eMode -> the same borrow exceeds base LTV and reverts.
    _mintSupply(user2, tokens.wstEth, 20e18);
    vm.prank(user2);
    vm.expectRevert(); // CollateralCannotCoverNewBorrow
    pool.borrow(tokens.weth, 20 ether, 2, 0, user2);
  }

  function test_stablecoinEModeBoostedBorrow() public {
    _supplyFrom(whale, tokens.usdt, 1_000_000e6);

    // 100k USDC collateral. Base USDC LTV 75% => 75k cap; stable eMode 90% => 90k cap.
    _mintSupply(user, tokens.usdc, 100_000e6);
    vm.prank(user);
    pool.setUserEMode(OneInchEarnConfig.STABLECOIN_EMODE_ID);

    vm.prank(user);
    pool.borrow(tokens.usdt, 85_000e6, 2, 0, user); // > 75% base, < 90% eMode
    (, , , , , uint256 hf) = pool.getUserAccountData(user);
    assertGt(hf, 1e18, 'stable eMode borrower healthy');
  }

  function test_liquidationReceiveAToken() public {
    _openLiquidatablePosition();

    address aWbtc = pool.getReserveAToken(tokens.wbtc);
    _mint(tokens.usdc, liquidator, 100_000e6);
    vm.startPrank(liquidator);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, user, type(uint256).max, true); // receive aTokens
    vm.stopPrank();

    assertGt(IERC20(aWbtc).balanceOf(liquidator), 0, 'liquidator received aWBTC');
  }

  function test_revert_selfLiquidation() public {
    _openLiquidatablePosition();
    _mint(tokens.usdc, user, 100_000e6);
    vm.startPrank(user);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    vm.expectRevert(Errors.SelfLiquidation.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, user, type(uint256).max, false);
    vm.stopPrank();
  }

  function test_deficitCreationAndUmbrellaElimination() public {
    // Borrower: 1 WBTC ($100k) collateral, borrows 70k USDC.
    _supplyFrom(whale, tokens.usdc, 1_000_000e6);
    _mintSupply(user, tokens.wbtc, 1e8);
    vm.prank(user);
    pool.borrow(tokens.usdc, 70_000e6, 2, 0, user);

    // WBTC collapses to $3k: even a full liquidation cannot cover the $70k debt.
    vm.mockCall(feeds.wbtc, abi.encodeWithSignature('latestAnswer()'), abi.encode(int256(3_000e8)));

    _mint(tokens.usdc, liquidator, 1_000_000e6);
    vm.startPrank(liquidator);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, user, type(uint256).max, false);
    vm.stopPrank();

    uint256 deficit = pool.getReserveDeficit(tokens.usdc);
    assertGt(deficit, 0, 'bad debt recorded as reserve deficit');

    // Wire Umbrella (owner = marketOwner = deployer) and cover the deficit.
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setAddress('UMBRELLA', umbrella);

    _mintSupply(umbrella, tokens.usdc, 200_000e6); // Umbrella holds aUSDC to burn
    vm.prank(umbrella);
    pool.eliminateReserveDeficit(tokens.usdc, deficit);

    assertEq(pool.getReserveDeficit(tokens.usdc), 0, 'deficit eliminated by Umbrella');
  }

  function test_wrappedTokenGatewayNativeEth() public {
    IWrappedTokenGatewayV3 gateway = IWrappedTokenGatewayV3(payable(report.wrappedTokenGateway));
    address aWeth = pool.getReserveAToken(tokens.weth);

    vm.deal(user, 10 ether);
    vm.prank(user);
    gateway.depositETH{value: 5 ether}(address(pool), user, 0);
    assertApproxEqAbs(IERC20(aWeth).balanceOf(user), 5 ether, 2, 'native ETH deposit minted aWETH');

    // Withdraw back to native ETH (approve the gateway to pull aWETH).
    vm.startPrank(user);
    IERC20(aWeth).approve(address(gateway), type(uint256).max);
    uint256 ethBefore = user.balance;
    gateway.withdrawETH(address(pool), 2 ether, user);
    vm.stopPrank();
    assertApproxEqAbs(user.balance - ethBefore, 2 ether, 2, 'withdrew native ETH');
  }

  // --------------------------------- helpers -----------------------------------

  function _openLiquidatablePosition() internal {
    _supplyFrom(whale, tokens.usdc, 1_000_000e6);
    _mintSupply(user, tokens.wbtc, 1e8); // $100k
    vm.prank(user);
    pool.borrow(tokens.usdc, 70_000e6, 2, 0, user);
    // WBTC -20% -> HF < 1 (78% LT * 80k = 62.4k < 70k debt).
    vm.mockCall(feeds.wbtc, abi.encodeWithSignature('latestAnswer()'), abi.encode(int256(80_000e8)));
    (, , , , , uint256 hf) = pool.getUserAccountData(user);
    assertLt(hf, 1e18, 'position liquidatable');
  }

  function _supplyFrom(address who, address token, uint256 amount) internal {
    if (token == tokens.weth) {
      deal(tokens.weth, who, amount);
    } else {
      _mint(token, who, amount);
    }
    vm.startPrank(who);
    IERC20(token).approve(address(pool), type(uint256).max);
    pool.supply(token, amount, who, 0);
    vm.stopPrank();
  }

  function _mintSupply(address who, address token, uint256 amount) internal {
    _supplyFrom(who, token, amount);
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
