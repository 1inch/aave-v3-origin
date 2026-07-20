// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';
import {AaveProtocolDataProvider} from '../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {MockAggregator} from '../../src/contracts/mocks/oracle/CLAggregators/MockAggregator.sol';
import {AquaListingPayload} from '../../src/deployments/projects/1inch-earn/AquaListingPayload.sol';

/**
 * @title OneInchEarnAquaListingTest
 * @notice Phase-2 AQUA listing: lists AQUA collateral-only via AquaListingPayload and asserts the
 * red-row policy holds end to end — AQUA can be supplied as collateral and borrowed against, but
 * AQUA itself can never be borrowed.
 */
contract OneInchEarnAquaListingTest is OneInchEarnTestBase {
  IPool internal pool;
  AaveProtocolDataProvider internal dp;

  address internal aqua;
  address internal aquaFeed;
  uint256 internal constant AQUA_CAP = 500_000;

  address internal user = makeAddr('aquaUser');
  address internal whale = makeAddr('aquaWhale');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    dp = AaveProtocolDataProvider(report.protocolDataProvider);

    aqua = address(new TestnetERC20('Aqua', 'AQUA', 18, deployer));
    aquaFeed = address(new MockAggregator(1e8)); // $1 for the test

    AquaListingPayload payload = new AquaListingPayload(report, aqua, aquaFeed, AQUA_CAP);
    vm.prank(deployer);
    ACLManager(report.aclManager).addPoolAdmin(address(payload));
    payload.execute();
  }

  function test_aquaListedAsCollateralOnly() public view {
    (
      ,
      uint256 ltv,
      uint256 lt,
      uint256 bonus,
      ,
      bool collateral,
      bool borrowing,
      ,
      bool active,

    ) = dp.getReserveConfigurationData(aqua);
    assertTrue(active, 'AQUA active');
    assertTrue(collateral, 'AQUA collateral');
    assertFalse(borrowing, 'AQUA borrowing disabled');
    assertFalse(dp.getFlashLoanEnabled(aqua), 'AQUA flashloans disabled');
    assertEq(ltv, 30_00, 'AQUA ltv 30%');
    assertEq(lt, 38_50, 'AQUA lt 38.5%');
    assertEq(bonus, 112_50, 'AQUA bonus');

    (, uint256 supplyCap) = dp.getReserveCaps(aqua);
    assertEq(supplyCap, AQUA_CAP, 'AQUA supply cap');

    // 1x branding.
    assertEq(IERC20Metadata(pool.getReserveAToken(aqua)).symbol(), '1xAQUA', 'aToken 1xAQUA');
    assertEq(IERC20Metadata(pool.getReserveVariableDebtToken(aqua)).symbol(), '1xdAQUA', 'debt 1xdAQUA');
  }

  function test_aquaCannotBeBorrowed() public {
    // Provide AQUA liquidity so a borrow would otherwise be possible.
    _mint(aqua, whale, 100_000e18);
    vm.startPrank(whale);
    IERC20(aqua).approve(address(pool), type(uint256).max);
    pool.supply(aqua, 100_000e18, whale, 0);
    vm.stopPrank();

    // A user with WETH collateral still cannot borrow AQUA (borrowing disabled).
    _supplyWeth(user, 50 ether);
    vm.prank(user);
    vm.expectRevert(); // BorrowingNotEnabled
    pool.borrow(aqua, 1_000e18, 2, 0, user);
  }

  function test_aquaWorksAsCollateral() public {
    // USDC liquidity to borrow.
    _mint(tokens.usdc, whale, 1_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 1_000_000e6, whale, 0);
    vm.stopPrank();

    // User supplies AQUA ($100k) and borrows USDC against it within the 30% LTV.
    _mint(aqua, user, 100_000e18);
    vm.startPrank(user);
    IERC20(aqua).approve(address(pool), type(uint256).max);
    pool.supply(aqua, 100_000e18, user, 0);
    pool.borrow(tokens.usdc, 20_000e6, 2, 0, user); // 20% < 30% LTV
    vm.stopPrank();

    (, , , , , uint256 hf) = pool.getUserAccountData(user);
    assertGt(hf, 1e18, 'healthy AQUA-collateralized borrow');
    assertEq(IERC20(tokens.usdc).balanceOf(user), 20_000e6, 'borrowed USDC against AQUA');
  }

  function _supplyWeth(address who, uint256 amount) internal {
    deal(tokens.weth, who, amount);
    vm.startPrank(who);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, amount, who, 0);
    vm.stopPrank();
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
