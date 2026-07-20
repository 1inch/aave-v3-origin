// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from '../OneInchEarnTestBase.sol';
import {IPool} from '../../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICreditDelegationToken} from '../../../src/contracts/interfaces/ICreditDelegationToken.sol';
import {TestnetERC20} from '../../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {MockAggregator} from '../../../src/contracts/mocks/oracle/CLAggregators/MockAggregator.sol';
import {Errors} from '../../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {ACLManager} from '../../../src/contracts/protocol/configuration/ACLManager.sol';
import {AaveProtocolDataProvider} from '../../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {AquaListingPayload} from '../../../src/deployments/projects/1inch-earn/AquaListingPayload.sol';

/**
 * @title OneInchEarnRedRowInvariantsSecurityTest
 * @notice Attacks the collateral-only ("red row") invariant: an adversary must NEVER be able to
 * create 1INCH or AQUA debt through any route — direct borrow, delegated borrow, single- or
 * multi-asset flashloan — while the assets remain usable as collateral. Creating red-row debt
 * would let an attacker short the governance token via the protocol or grief the treasury.
 */
contract OneInchEarnRedRowInvariantsSecurityTest is OneInchEarnTestBase {
  IPool internal pool;
  AaveProtocolDataProvider internal dp;

  address internal whale = makeAddr('whale');
  address internal attacker = makeAddr('attacker');
  address internal aqua;

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    dp = AaveProtocolDataProvider(report.protocolDataProvider);

    // List AQUA (phase 2) so both red-row assets are exercised by the same invariants.
    aqua = address(new TestnetERC20('Aqua', 'AQUA', 18, deployer));
    AquaListingPayload payload = new AquaListingPayload(
      report,
      aqua,
      address(new MockAggregator(1e8)),
      500_000
    );
    vm.prank(deployer);
    ACLManager(report.aclManager).addPoolAdmin(address(payload));
    payload.execute();

    // Deep liquidity for a real borrow attempt to draw against.
    _mint(tokens.usdc, whale, 2_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 2_000_000e6, whale, 0);
    vm.stopPrank();
  }

  // ------------------------------- 1INCH -------------------------------

  function test_cannotBorrow1inch() public {
    _supplyCollateral(attacker, tokens.wbtc, 2e8); // ample collateral
    // Someone even supplies 1INCH liquidity so illiquidity isn't the blocker.
    _supplyCollateral(whale, tokens.oneInch, 1_000_000e18);
    vm.prank(attacker);
    vm.expectRevert(Errors.BorrowingNotEnabled.selector);
    pool.borrow(tokens.oneInch, 1e18, 2, 0, attacker);
  }

  function test_cannotBorrow1inchViaDelegation() public {
    _supplyCollateral(attacker, tokens.wbtc, 2e8);
    _supplyCollateral(whale, tokens.oneInch, 1_000_000e18);
    // attacker delegates 1INCH borrow power to a puppet; puppet borrows on behalf -> still blocked.
    address vToken = pool.getReserveVariableDebtToken(tokens.oneInch);
    vm.prank(attacker);
    ICreditDelegationToken(vToken).approveDelegation(address(this), 1e18);
    vm.expectRevert(Errors.BorrowingNotEnabled.selector);
    pool.borrow(tokens.oneInch, 1e18, 2, 0, attacker);
  }

  function test_cannotFlashLoan1inchSimple() public {
    _supplyCollateral(whale, tokens.oneInch, 1_000_000e18);
    vm.prank(attacker);
    vm.expectRevert(Errors.FlashloanDisabled.selector);
    pool.flashLoanSimple(address(this), tokens.oneInch, 1e18, '', 0);
  }

  function test_cannotFlashLoan1inchMultiAsset() public {
    _supplyCollateral(whale, tokens.oneInch, 1_000_000e18);
    address[] memory assets = new address[](1);
    assets[0] = tokens.oneInch;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1e18;
    uint256[] memory modes = new uint256[](1); // mode 0
    vm.prank(attacker);
    vm.expectRevert(Errors.FlashloanDisabled.selector);
    pool.flashLoan(address(this), assets, amounts, modes, attacker, '', 0);
  }

  function test_1inchStillWorksAsCollateral() public {
    // The invariant is "no debt", NOT "unusable": 1INCH must still back a stable borrow.
    _supplyCollateral(attacker, tokens.oneInch, 1_000_000e18); // $400k at $0.40
    vm.prank(attacker);
    pool.borrow(tokens.usdc, 50_000e6, 2, 0, attacker); // well within 1INCH's ~40% LTV
    (, , , , , uint256 hf) = pool.getUserAccountData(attacker);
    assertGt(hf, 1e18, '1INCH-collateralized borrow is healthy');
  }

  // ------------------------------- AQUA -------------------------------

  function test_cannotBorrowAqua() public {
    _supplyCollateral(attacker, tokens.wbtc, 2e8);
    _supplyCollateral(whale, aqua, 400_000e18);
    vm.prank(attacker);
    vm.expectRevert(Errors.BorrowingNotEnabled.selector);
    pool.borrow(aqua, 1e18, 2, 0, attacker);
  }

  function test_cannotFlashLoanAqua() public {
    _supplyCollateral(whale, aqua, 400_000e18);
    vm.prank(attacker);
    vm.expectRevert(Errors.FlashloanDisabled.selector);
    pool.flashLoanSimple(address(this), aqua, 1e18, '', 0);
  }

  // ------------------------------- config invariant -------------------------------

  function test_redRowConfigForbidsBorrowAndFlashloan() public view {
    address[2] memory redRows = [tokens.oneInch, aqua];
    for (uint256 i = 0; i < redRows.length; i++) {
      (, uint256 ltv, uint256 lt, , , bool usable, bool borrowing, , , ) = dp
        .getReserveConfigurationData(redRows[i]);
      assertFalse(borrowing, 'red row: borrowing disabled');
      assertFalse(dp.getFlashLoanEnabled(redRows[i]), 'red row: flashloans disabled');
      assertTrue(usable, 'red row: usable as collateral');
      assertGt(ltv, 0, 'red row: positive LTV');
      assertGt(lt, ltv, 'red row: liq threshold above LTV');
      (uint256 borrowCap, ) = dp.getReserveCaps(redRows[i]);
      assertEq(borrowCap, 0, 'red row: zero borrow cap');
    }
  }

  // --------------------------------- helpers -----------------------------------

  function _supplyCollateral(address user, address token, uint256 amount) internal {
    _mint(token, user, amount);
    vm.startPrank(user);
    IERC20(token).approve(address(pool), type(uint256).max);
    pool.supply(token, amount, user, 0);
    vm.stopPrank();
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
