// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICreditDelegationToken} from '../../src/contracts/interfaces/ICreditDelegationToken.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {OneInchEarnDebtSwapAdapter} from '../../src/deployments/projects/1inch-earn/OneInchEarnDebtSwapAdapter.sol';

/**
 * @title OneInchEarnDebtSwapTest
 * @notice Verifies the P2P debt-swap adapter: a maker owing USDT and a taker owing USDC swap
 * their debt denominations atomically (no DEX), each backed by their own collateral, with both
 * consenting via credit delegation. This is the settlement path for the Aqua debt-for-debt swap
 * that a naive two-transfer cannot do.
 */
contract OneInchEarnDebtSwapTest is OneInchEarnTestBase {
  IPool internal pool;
  OneInchEarnDebtSwapAdapter internal adapter;

  address internal maker;
  address internal taker;
  address internal whale;

  uint256 internal constant DEBT = 50_000e6;

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    adapter = new OneInchEarnDebtSwapAdapter(pool);

    maker = makeAddr('maker');
    taker = makeAddr('taker');
    whale = makeAddr('whale');

    // Liquidity for both stables (+ keep a buffer with the whale to fund premiums).
    _mint(tokens.usdc, whale, 2_000_000e6);
    _mint(tokens.usdt, whale, 2_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    IERC20(tokens.usdt).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 1_000_000e6, whale, 0);
    pool.supply(tokens.usdt, 1_000_000e6, whale, 0);
    // Whale funds the flashloan premium.
    IERC20(tokens.usdc).approve(address(adapter), type(uint256).max);
    IERC20(tokens.usdt).approve(address(adapter), type(uint256).max);
    vm.stopPrank();

    // Maker owes USDT; Taker owes USDC. Each has WBTC collateral.
    _supply(maker, tokens.wbtc, 1e8);
    vm.prank(maker);
    pool.borrow(tokens.usdt, DEBT, 2, 0, maker);

    _supply(taker, tokens.wbtc, 1e8);
    vm.prank(taker);
    pool.borrow(tokens.usdc, DEBT, 2, 0, taker);

    // Consent: maker will assume USDC (delegates on USDC debt), taker will assume USDT.
    // NB: resolve the debt-token addresses BEFORE pranking (a getter call would consume the prank).
    ICreditDelegationToken usdcDebt = ICreditDelegationToken(
      pool.getReserveVariableDebtToken(tokens.usdc)
    );
    ICreditDelegationToken usdtDebt = ICreditDelegationToken(
      pool.getReserveVariableDebtToken(tokens.usdt)
    );
    vm.prank(maker);
    usdcDebt.approveDelegation(address(adapter), DEBT);
    vm.prank(taker);
    usdtDebt.approveDelegation(address(adapter), DEBT);
  }

  function test_p2pDebtSwap() public {
    // The caller (whale) pays the flashloan premium and has approved the adapter.
    vm.prank(whale);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: DEBT,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: DEBT
      })
    );

    // Maker: shed USDT, now owes USDC.
    assertApproxEqAbs(_debt(tokens.usdt, maker), 0, 2, 'maker USDT debt cleared');
    assertApproxEqAbs(_debt(tokens.usdc, maker), DEBT, 2, 'maker now owes USDC');
    // Taker: shed USDC, now owes USDT.
    assertApproxEqAbs(_debt(tokens.usdc, taker), 0, 2, 'taker USDC debt cleared');
    assertApproxEqAbs(_debt(tokens.usdt, taker), DEBT, 2, 'taker now owes USDT');

    // Both remain solvent, and the adapter holds no dust.
    (, , , , , uint256 makerHf) = pool.getUserAccountData(maker);
    (, , , , , uint256 takerHf) = pool.getUserAccountData(taker);
    assertGt(makerHf, 1e18, 'maker solvent');
    assertGt(takerHf, 1e18, 'taker solvent');
    assertEq(IERC20(tokens.usdc).balanceOf(address(adapter)), 0, 'no USDC dust in adapter');
    assertEq(IERC20(tokens.usdt).balanceOf(address(adapter)), 0, 'no USDT dust in adapter');
  }

  function test_partialDebtSwap() public {
    // Swapping only half the books is fine: each repay burns exactly the flashed amount.
    uint256 half = DEBT / 2;
    vm.prank(whale);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: half,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: half
      })
    );
    assertApproxEqAbs(_debt(tokens.usdt, maker), DEBT - half, 2, 'maker keeps residual USDT debt');
    assertApproxEqAbs(_debt(tokens.usdc, maker), half, 2, 'maker assumed half USDC');
    assertApproxEqAbs(_debt(tokens.usdc, taker), DEBT - half, 2, 'taker keeps residual USDC debt');
    assertApproxEqAbs(_debt(tokens.usdt, taker), half, 2, 'taker assumed half USDT');
  }

  function test_premiumPaidByCallerOnly() public {
    // Turn on a non-zero flashloan premium so the pull-from-caller path executes.
    address configurator = report.poolConfiguratorProxy;
    vm.prank(deployer);
    (bool ok, ) = configurator.call(
      abi.encodeWithSignature('updateFlashloanPremium(uint128)', uint128(9)) // 0.09%
    );
    assertTrue(ok, 'set premium');

    uint256 whaleUsdcBefore = IERC20(tokens.usdc).balanceOf(whale);
    uint256 whaleUsdtBefore = IERC20(tokens.usdt).balanceOf(whale);
    uint256 makerUsdtBefore = IERC20(tokens.usdt).balanceOf(maker);
    uint256 takerUsdcBefore = IERC20(tokens.usdc).balanceOf(taker);

    vm.prank(whale);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: DEBT,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: DEBT
      })
    );

    uint256 premium = (DEBT * 9) / 10_000;
    assertEq(
      whaleUsdtBefore - IERC20(tokens.usdt).balanceOf(whale),
      premium,
      'caller paid the USDT premium'
    );
    assertEq(
      whaleUsdcBefore - IERC20(tokens.usdc).balanceOf(whale),
      premium,
      'caller paid the USDC premium'
    );
    // The swapped parties' wallets are untouched (debt moved, no token pulls from them).
    assertEq(IERC20(tokens.usdt).balanceOf(maker), makerUsdtBefore, 'maker wallet untouched');
    assertEq(IERC20(tokens.usdc).balanceOf(taker), takerUsdcBefore, 'taker wallet untouched');
  }

  function test_revert_withoutMakerDelegation() public {
    // Revoke the maker's delegation -> the borrow-on-behalf leg reverts, unwinding the swap.
    ICreditDelegationToken usdcDebt = ICreditDelegationToken(
      pool.getReserveVariableDebtToken(tokens.usdc)
    );
    vm.prank(maker);
    usdcDebt.approveDelegation(address(adapter), 0);
    vm.prank(whale);
    vm.expectRevert();
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: DEBT,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: DEBT
      })
    );
  }

  function test_revert_withoutTakerDelegation() public {
    ICreditDelegationToken usdtDebt = ICreditDelegationToken(
      pool.getReserveVariableDebtToken(tokens.usdt)
    );
    vm.prank(taker);
    usdtDebt.approveDelegation(address(adapter), 0);
    vm.prank(whale);
    vm.expectRevert();
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: DEBT,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: DEBT
      })
    );
  }

  function test_revert_swapExceedingActualDebt() public {
    // Asking to swap more than the maker actually owes: repay burns less than the flashed
    // amount -> DebtBelowSwapAmount guard unwinds the whole swap (no over-borrow, no stuck funds).
    vm.prank(whale);
    vm.expectRevert(OneInchEarnDebtSwapAdapter.DebtBelowSwapAmount.selector);
    adapter.swapDebt(
      OneInchEarnDebtSwapAdapter.DebtSwapParams({
        maker: maker,
        taker: taker,
        makerDebtAsset: tokens.usdt,
        makerDebtAmount: DEBT * 2,
        takerDebtAsset: tokens.usdc,
        takerDebtAmount: DEBT
      })
    );
  }

  function test_revert_executeOperationNotPool() public {
    // Direct invocation of the flashloan callback must be rejected.
    address[] memory assets = new address[](2);
    uint256[] memory amounts = new uint256[](2);
    uint256[] memory premiums = new uint256[](2);
    vm.expectRevert(OneInchEarnDebtSwapAdapter.CallerNotPool.selector);
    adapter.executeOperation(assets, amounts, premiums, address(adapter), '');
  }

  function test_revert_flashloanInitiatorNotAdapter() public {
    // A third party flash-borrowing INTO the adapter (initiator != adapter) must be rejected,
    // otherwise an attacker could trigger swaps with forged params.
    address[] memory assets = new address[](1);
    assets[0] = tokens.usdc;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1_000e6;
    uint256[] memory modes = new uint256[](1);

    OneInchEarnDebtSwapAdapter.DebtSwapParams memory p = OneInchEarnDebtSwapAdapter.DebtSwapParams({
      maker: maker,
      taker: taker,
      makerDebtAsset: tokens.usdt,
      makerDebtAmount: DEBT,
      takerDebtAsset: tokens.usdc,
      takerDebtAmount: DEBT
    });

    vm.prank(whale);
    vm.expectRevert(); // bubbled InitiatorNotAdapter inside the flashloan
    pool.flashLoan(address(adapter), assets, amounts, modes, whale, abi.encode(p, whale), 0);
  }

  function _debt(address asset, address user) internal view returns (uint256) {
    return IERC20(pool.getReserveVariableDebtToken(asset)).balanceOf(user);
  }

  function _supply(address user, address token, uint256 amount) internal {
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
