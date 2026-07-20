// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from '../OneInchEarnTestBase.sol';
import {IPool} from '../../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../../src/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IScaledBalanceToken} from '../../../src/contracts/interfaces/IScaledBalanceToken.sol';
import {TestnetERC20} from '../../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {Errors} from '../../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {OneInchPoolInstance} from '../../../src/deployments/projects/1inch-earn/OneInchPoolInstance.sol';
import {OneInchVariableDebtToken} from '../../../src/deployments/projects/1inch-earn/OneInchVariableDebtToken.sol';

/**
 * @title OneInchEarnDebtTokenSecurityTest
 * @notice Adversarial tests for the transferable debt token: attempts to dump debt without
 * consent, extract value through rounding, destroy/duplicate debt, replay signatures across
 * reserves, and steal a third party's debt. Also documents the standing-`credit` bearer hazard.
 */
contract OneInchEarnDebtTokenSecurityTest is OneInchEarnTestBase {
  IPool internal pool;
  OneInchVariableDebtToken internal usdcDebt;
  OneInchVariableDebtToken internal usdtDebt;

  address internal whale = makeAddr('whale');
  address internal borrower = makeAddr('borrower');
  address internal receiver = makeAddr('receiver');
  address internal attacker = makeAddr('attacker');

  function setUp() public {
    _deployMarketAndList();
    _installOneInchPool(); // debt transfers require the gated pool's finalizeDebtTransfer hook
    pool = IPool(report.poolProxy);
    usdcDebt = OneInchVariableDebtToken(pool.getReserveVariableDebtToken(tokens.usdc));
    usdtDebt = OneInchVariableDebtToken(pool.getReserveVariableDebtToken(tokens.usdt));
    vm.startPrank(deployer);
    usdcDebt.setTransferable(true);
    usdtDebt.setTransferable(true);
    vm.stopPrank();

    _mint(tokens.usdc, whale, 5_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 3_000_000e6, whale, 0);
    vm.stopPrank();

    // Borrower with a 100k USDC debt; receiver over-collateralized so it can accept debt.
    _supplyCollateral(borrower, tokens.wbtc, 3e8);
    vm.prank(borrower);
    pool.borrow(tokens.usdc, 100_000e6, 2, 0, borrower);
    _supplyCollateral(receiver, tokens.wbtc, 5e8);
  }

  // ------------------------- cannot dump debt without consent -------------------------

  function test_cannotDumpDebtOnUnconsentingReceiver() public {
    // No credit granted -> borrower cannot offload debt onto the receiver.
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.InsufficientCredit.selector);
    usdcDebt.transfer(receiver, 50_000e6);
  }

  function test_cannotDumpViaTransferFromOnThirdParty() public {
    // Attacker can only move their OWN debt: transferFrom(from=borrower) by attacker reverts,
    // so nobody can shove a victim's debt around (or pull a third party's debt to themselves).
    vm.prank(receiver);
    usdcDebt.credit(attacker, 50_000e6);
    vm.prank(attacker);
    vm.expectRevert(OneInchVariableDebtToken.CallerNotDebtOwner.selector);
    usdcDebt.transferFrom(borrower, receiver, 50_000e6);
  }

  // --------------------------- value conservation / no rounding profit ---------------------------

  function test_transferConservesScaledAndUnderlyingDebt() public {
    vm.prank(receiver);
    usdcDebt.credit(borrower, 60_000e6);

    uint256 scaledTotalBefore = IScaledBalanceToken(address(usdcDebt)).scaledTotalSupply();
    uint256 sumBefore = usdcDebt.balanceOf(borrower) + usdcDebt.balanceOf(receiver);

    vm.prank(borrower);
    usdcDebt.transfer(receiver, 60_000e6);

    // Scaled supply is exactly conserved (a 1:1 scaled move); underlying conserved within rounding.
    assertEq(
      IScaledBalanceToken(address(usdcDebt)).scaledTotalSupply(),
      scaledTotalBefore,
      'scaled total supply conserved'
    );
    uint256 sumAfter = usdcDebt.balanceOf(borrower) + usdcDebt.balanceOf(receiver);
    assertApproxEqAbs(sumAfter, sumBefore, 2, 'underlying debt conserved (no free shedding)');
  }

  function test_repeatedDustTransfersCannotDestroyDebt() public {
    vm.prank(receiver);
    usdcDebt.credit(borrower, type(uint256).max);

    uint256 scaledTotalBefore = IScaledBalanceToken(address(usdcDebt)).scaledTotalSupply();
    for (uint256 i = 0; i < 25; i++) {
      vm.prank(borrower);
      usdcDebt.transfer(receiver, 1); // 1 wei each
    }
    // No scaled debt created or destroyed by dust churn -> no rounding profit.
    assertEq(
      IScaledBalanceToken(address(usdcDebt)).scaledTotalSupply(),
      scaledTotalBefore,
      'dust churn conserves scaled supply'
    );
  }

  // --------------------------- full-exit sentinel needs full credit ---------------------------

  function test_fullExitSentinelRequiresEnoughCredit() public {
    // type(uint256).max moves the WHOLE balance and must consume credit >= the full balance.
    vm.prank(receiver);
    usdcDebt.credit(borrower, 1_000e6); // far less than the ~100k balance
    vm.prank(borrower);
    vm.expectRevert(OneInchVariableDebtToken.InsufficientCredit.selector);
    usdcDebt.transfer(receiver, type(uint256).max);
  }

  // --------------------------- consent is a bearer hazard (documented) ---------------------------

  /// Standing `credit` is itself a bearer authorization: once the receiver credits a spender,
  /// that spender can push up to that amount ONTO the receiver at any later time. Receivers must
  /// scope credit to the intended, atomic hand-off (mirror of the adapter's delegation hazard).
  function test_finding_standingCreditCanBeConsumedLater() public {
    vm.prank(receiver);
    usdcDebt.credit(borrower, 50_000e6);
    // ... arbitrary time / blocks pass; the receiver forgot to revoke ...
    vm.warp(block.timestamp + 30 days);
    vm.prank(borrower);
    usdcDebt.transfer(receiver, 50_000e6); // still works
    assertApproxEqAbs(usdcDebt.balanceOf(receiver), 50_000e6, 2, 'stale credit still consumable');
  }

  // --------------------------- signatures: no cross-reserve replay ---------------------------

  function test_creditSigCannotReplayAcrossReserves() public {
    uint256 pk = 0xA11CE;
    address sigReceiver = vm.addr(pk);
    _supplyCollateral(sigReceiver, tokens.wbtc, 5e8);

    uint256 deadline = block.timestamp + 1 hours;
    // Sign against the USDC debt token's domain.
    bytes32 structHash = keccak256(
      abi.encode(
        usdcDebt.CREDIT_WITH_SIG_TYPEHASH(),
        borrower,
        uint256(10_000e6),
        usdcDebt.creditNonces(sigReceiver),
        deadline
      )
    );
    bytes32 digest = keccak256(
      abi.encodePacked('\x19\x01', usdcDebt.DOMAIN_SEPARATOR(), structHash)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

    // Replaying the USDC-domain signature on the USDT debt token must fail (distinct domain).
    vm.expectRevert(Errors.InvalidSignature.selector);
    usdtDebt.creditWithSig(sigReceiver, borrower, 10_000e6, deadline, v, r, s);

    // Sanity: it is valid on the USDC token it was signed for.
    usdcDebt.creditWithSig(sigReceiver, borrower, 10_000e6, deadline, v, r, s);
    assertEq(
      usdcDebt.creditAllowance(sigReceiver, borrower),
      10_000e6,
      'valid on intended reserve'
    );
  }

  // --------------------------- disabled ERC20 approve path stays disabled ---------------------------

  function test_plainApproveIsDisabled() public {
    // The debtor must never be able to grant a standard allowance to push debt.
    vm.prank(borrower);
    vm.expectRevert(Errors.OperationNotSupported.selector);
    usdcDebt.approve(attacker, type(uint256).max);
  }

  // --------------------------- helpers ---------------------------

  function _installOneInchPool() internal {
    OneInchPoolInstance impl = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      IERC20(address(0))
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(impl));
  }

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
