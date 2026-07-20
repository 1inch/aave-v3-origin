// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from '../OneInchEarnTestBase.sol';
import {IPool} from '../../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../../src/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TestnetERC20} from '../../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {Errors} from '../../../src/contracts/protocol/libraries/helpers/Errors.sol';
import {MockSimpleFlashLoanReceiverWithoutMint} from '../../../src/contracts/mocks/flashloan/MockSimpleFlashLoanReceiverWithoutMint.sol';
import {KycNFT} from '../../../src/deployments/projects/1inch-earn/KycNFT.sol';
import {OneInchPoolInstance} from '../../../src/deployments/projects/1inch-earn/OneInchPoolInstance.sol';

/// @dev Minimal relay that holds a KYC NFT and liquidates on behalf of a non-KYC beneficiary,
/// forwarding the seized collateral. Demonstrates that the gate is per-CALLER.
contract KycLiquidationRelay {
  function liquidate(
    IPool pool,
    address collateral,
    address debt,
    address borrower,
    uint256 amount,
    address beneficiary
  ) external {
    IERC20(debt).approve(address(pool), type(uint256).max);
    pool.liquidationCall(collateral, debt, borrower, amount, false);
    IERC20(collateral).transfer(beneficiary, IERC20(collateral).balanceOf(address(this)));
  }
}

/**
 * @title OneInchEarnLiquidationSecurityTest
 * @notice Adversarial tests for NFT-gated liquidations: an unauthorized liquidator cannot snipe
 * the liquidation bonus; the gate is correctly scoped to `liquidationCall` ONLY (repay, flashloan
 * and Umbrella deficit elimination stay permissionless); healthy positions and self-liquidations
 * are rejected; and the gate cannot be opened by a non-admin. Also documents that gating is
 * per-caller (a KYC holder can relay for a non-KYC beneficiary).
 */
contract OneInchEarnLiquidationSecurityTest is OneInchEarnTestBase {
  IPool internal pool;
  KycNFT internal kyc;

  address internal kycOwner = makeAddr('kycOwner');
  address internal whale = makeAddr('whale');
  address internal borrower = makeAddr('borrower');
  address internal attacker = makeAddr('attacker');
  address internal umbrella = makeAddr('umbrella');

  function setUp() public {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);
    kyc = new KycNFT('1inch Earn Liquidator KYC', '1EARN-KYC', '1', kycOwner);
    _installGatedPool(IERC20(address(kyc)));

    // USDC liquidity + a borrower one price-move away from liquidation.
    _mint(tokens.usdc, whale, 2_000_000e6);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 2_000_000e6, whale, 0);
    vm.stopPrank();

    _supplyCollateral(borrower, tokens.wbtc, 1e8); // $100k
    vm.prank(borrower);
    pool.borrow(tokens.usdc, 70_000e6, 2, 0, borrower);
  }

  // ------------------- gate blocks unauthorized bonus-sniping -------------------

  function test_finding_none_nonKycCannotSnipeLiquidationBonus() public {
    _crashWbtc(80_000e8); // HF < 1
    _fund(attacker, tokens.usdc, 70_000e6);
    vm.prank(attacker);
    vm.expectRevert(OneInchPoolInstance.OnlyKycLiquidators.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
  }

  // ------------------- gate scope: repay / flashloan / deficit are NOT gated -------------------

  function test_gateDoesNotBlockRepay() public {
    // A non-KYC third party repaying the borrower's debt is always allowed (helps solvency).
    _fund(attacker, tokens.usdc, 70_000e6);
    vm.startPrank(attacker);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.repay(tokens.usdc, 10_000e6, 2, borrower);
    vm.stopPrank();
    assertLt(
      IERC20(pool.getReserveVariableDebtToken(tokens.usdc)).balanceOf(borrower),
      70_000e6,
      'repay by non-KYC succeeded'
    );
  }

  function test_gateDoesNotBlockFlashLoan() public {
    MockSimpleFlashLoanReceiverWithoutMint receiver = new MockSimpleFlashLoanReceiverWithoutMint(
      IPoolAddressesProvider(report.poolAddressesProvider)
    );
    uint256 amount = 100_000e6;
    uint256 premium = (amount * 5) / 10_000; // 0.05% total premium
    _mint(tokens.usdc, address(receiver), premium); // pre-fund the premium
    vm.prank(attacker); // a non-KYC EOA initiates
    pool.flashLoanSimple(address(receiver), tokens.usdc, amount, '', 0);
    // Reaching here (no OnlyKycLiquidators revert) proves flashloans are ungated.
    assertGt(
      IERC20(tokens.usdc).balanceOf(pool.getReserveAToken(tokens.usdc)),
      0,
      'flashloan settled'
    );
  }

  function test_gateDoesNotBlockDeficitElimination() public {
    // Force bad debt, then a NON-KYC Umbrella eliminates the deficit — must not be gated.
    _crashWbtc(3_000e8);
    _fund(attacker, tokens.usdc, 200_000e6);
    // Bootstrap the deficit via a KYC'd liquidation (full seize leaves residual debt as deficit).
    vm.prank(kycOwner);
    kyc.mint(attacker, 1);
    vm.startPrank(attacker);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
    vm.stopPrank();
    uint256 deficit = pool.getReserveDeficit(tokens.usdc);
    assertGt(deficit, 0, 'deficit created');

    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setAddress('UMBRELLA', umbrella);
    _supplyCollateral(umbrella, tokens.usdc, 300_000e6); // umbrella holds aUSDC, holds no KYC NFT
    vm.prank(umbrella);
    pool.eliminateReserveDeficit(tokens.usdc, deficit);
    assertEq(pool.getReserveDeficit(tokens.usdc), 0, 'non-KYC Umbrella cleared deficit');
  }

  // ------------------- no free bonus: healthy / self liquidation rejected -------------------

  function test_cannotLiquidateHealthyPosition() public {
    vm.prank(kycOwner);
    kyc.mint(attacker, 2);
    _fund(attacker, tokens.usdc, 70_000e6);
    vm.startPrank(attacker);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    vm.expectRevert(Errors.HealthFactorNotBelowThreshold.selector); // borrower still healthy
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
    vm.stopPrank();
  }

  function test_selfLiquidationBannedEvenForKycHolder() public {
    _crashWbtc(80_000e8);
    vm.prank(kycOwner);
    kyc.mint(borrower, 3); // borrower is KYC'd
    _fund(borrower, tokens.usdc, 70_000e6);
    vm.startPrank(borrower);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    vm.expectRevert(Errors.SelfLiquidation.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
    vm.stopPrank();
  }

  // ------------------- gate cannot be opened by a non-admin -------------------

  function test_strangerCannotDisableGateToSnipe() public {
    OneInchPoolInstance gatedPool = OneInchPoolInstance(report.poolProxy);
    vm.prank(attacker);
    vm.expectRevert(OneInchPoolInstance.CallerNotPoolOrEmergencyAdmin.selector);
    gatedPool.setLiquidatorGate(IERC20(address(0)));
  }

  // ------------------- documented: gating is per-caller (KYC holder can relay) -------------------

  function test_finding_kycHolderCanRelayLiquidationToNonKycBeneficiary() public {
    _crashWbtc(80_000e8);
    KycLiquidationRelay relay = new KycLiquidationRelay();
    vm.prank(kycOwner);
    kyc.mint(address(relay), 4); // the RELAY holds the KYC NFT
    _mint(tokens.usdc, address(relay), 70_000e6);

    relay.liquidate(pool, tokens.wbtc, tokens.usdc, borrower, type(uint256).max, attacker);

    // The non-KYC beneficiary ends up with the seized collateral — gating is per-caller, so a
    // KYC holder can service others. This is by design (documented), not a bypass of the gate.
    assertGt(
      IERC20(tokens.wbtc).balanceOf(attacker),
      0,
      'non-KYC beneficiary received seized WBTC'
    );
  }

  // --------------------------------- helpers -----------------------------------

  function _installGatedPool(IERC20 gate) internal {
    OneInchPoolInstance gatedPool = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      gate
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(gatedPool));
  }

  function _crashWbtc(int256 price) internal {
    vm.mockCall(feeds.wbtc, abi.encodeWithSignature('latestAnswer()'), abi.encode(price));
  }

  function _supplyCollateral(address user, address token, uint256 amount) internal {
    _mint(token, user, amount);
    vm.startPrank(user);
    IERC20(token).approve(address(pool), type(uint256).max);
    pool.supply(token, amount, user, 0);
    vm.stopPrank();
  }

  function _fund(address to, address token, uint256 amount) internal {
    _mint(token, to, amount);
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
