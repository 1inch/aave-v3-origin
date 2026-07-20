// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../src/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TestnetERC20} from '../../src/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import {KycNFT} from '../../src/deployments/projects/1inch-earn/KycNFT.sol';
import {OneInchPoolInstance} from '../../src/deployments/projects/1inch-earn/OneInchPoolInstance.sol';
import {OneInchEarnLiquidatorGate} from '../../src/deployments/projects/1inch-earn/OneInchEarnLiquidatorGate.sol';

/**
 * @title OneInchEarnLiquidationGateTest
 * @notice End-to-end verification of the NFT-gated (permissioned) liquidations feature:
 * a non-KYC liquidator is rejected, a KYC-NFT holder liquidates successfully (and keeps
 * the NFT), owner revocation re-locks access, and a zero-address gate is fully
 * permissionless. Uses a real underwater position and the audited liquidation engine.
 */
contract OneInchEarnLiquidationGateTest is OneInchEarnTestBase {
  IPool internal pool;
  KycNFT internal kyc;
  address internal kycOwner;

  address internal borrower;
  address internal whale;
  address internal liquidator;

  uint256 internal constant WBTC_SUPPLY = 1e8; // 1 WBTC ($100k at setup price)
  uint256 internal constant USDC_LIQUIDITY = 1_000_000e6;
  uint256 internal constant USDC_BORROW = 70_000e6;

  function setUp() public {
    kycOwner = makeAddr('kycOwner');
    borrower = makeAddr('borrower');
    whale = makeAddr('whale');
    liquidator = makeAddr('liquidator');
  }

  function test_nonKycLiquidatorReverts() public {
    _freshMarket(true);
    _fundLiquidator();
    vm.prank(liquidator);
    vm.expectRevert(OneInchPoolInstance.OnlyKycLiquidators.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
  }

  function test_kycHolderCanLiquidateAndKeepsNft() public {
    _freshMarket(true);
    _fundLiquidator();

    uint256 tokenId = 1;
    vm.prank(kycOwner);
    kyc.mint(liquidator, tokenId);
    assertEq(kyc.balanceOf(liquidator), 1, 'liquidator KYC minted');

    uint256 collateralBefore = IERC20(pool.getReserveAToken(tokens.wbtc)).balanceOf(borrower);

    vm.prank(liquidator);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);

    // Liquidation actually happened: borrower's collateral shrank and liquidator got WBTC.
    uint256 collateralAfter = IERC20(pool.getReserveAToken(tokens.wbtc)).balanceOf(borrower);
    assertLt(collateralAfter, collateralBefore, 'collateral seized');
    assertGt(IERC20(tokens.wbtc).balanceOf(liquidator), 0, 'liquidator received WBTC');

    // The gate NFT is only read, never transferred.
    assertEq(kyc.balanceOf(liquidator), 1, 'liquidator still holds the KYC NFT');
  }

  function test_ownerBurnRevokesAccess() public {
    _freshMarket(true);
    _fundLiquidator();

    uint256 tokenId = 7;
    vm.prank(kycOwner);
    kyc.mint(liquidator, tokenId);

    // Emergency revoke-all: owner can burn any token.
    vm.prank(kycOwner);
    kyc.burn(tokenId);
    assertEq(kyc.balanceOf(liquidator), 0, 'KYC revoked');

    vm.prank(liquidator);
    vm.expectRevert(OneInchPoolInstance.OnlyKycLiquidators.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
  }

  function test_zeroAddressGateIsPermissionless() public {
    // Gate disabled at install: liquidations are fully permissionless.
    _freshMarket(false);
    _fundLiquidator();

    assertTrue(
      OneInchPoolInstance(report.poolProxy).isAuthorizedLiquidator(liquidator),
      'any address authorized when gate disabled'
    );

    vm.prank(liquidator);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
    assertGt(IERC20(tokens.wbtc).balanceOf(liquidator), 0, 'permissionless liquidation succeeded');
  }

  function test_isAuthorizedLiquidatorView() public {
    _freshMarket(true);
    assertFalse(
      OneInchPoolInstance(report.poolProxy).isAuthorizedLiquidator(liquidator),
      'no NFT -> not authorized'
    );
    vm.prank(kycOwner);
    kyc.mint(liquidator, 3);
    assertTrue(
      OneInchPoolInstance(report.poolProxy).isAuthorizedLiquidator(liquidator),
      'NFT holder -> authorized'
    );
  }

  function test_gateSeededOnInstall() public {
    _freshMarket(true);
    assertEq(
      address(OneInchPoolInstance(report.poolProxy).liquidatorGate()),
      address(kyc),
      'gate seeded from immutable on install'
    );
  }

  function test_emergencyOpenViaSetter() public {
    // The emergency path: open liquidations instantly WITHOUT a pool upgrade.
    _freshMarket(true);
    _fundLiquidator();

    // Non-holder is blocked while the gate is active.
    vm.prank(liquidator);
    vm.expectRevert(OneInchPoolInstance.OnlyKycLiquidators.selector);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);

    // Guardian (EMERGENCY_ADMIN) opens the gate in one tx.
    vm.prank(deployer); // deployer is emergencyAdmin during bootstrap
    OneInchPoolInstance(report.poolProxy).setLiquidatorGate(IERC20(address(0)));

    // Now anyone can liquidate.
    vm.prank(liquidator);
    pool.liquidationCall(tokens.wbtc, tokens.usdc, borrower, type(uint256).max, false);
    assertGt(IERC20(tokens.wbtc).balanceOf(liquidator), 0, 'permissionless after open');
  }

  function test_gateRotation() public {
    _freshMarket(true);

    // Rotate to a fresh KYC contract; old holders lose access, new holders gain it.
    KycNFT kyc2 = new KycNFT('KYC2', 'KYC2', '1', kycOwner);
    vm.prank(deployer); // POOL_ADMIN during bootstrap
    OneInchPoolInstance(report.poolProxy).setLiquidatorGate(IERC20(address(kyc2)));

    assertEq(address(OneInchPoolInstance(report.poolProxy).liquidatorGate()), address(kyc2));

    vm.prank(kycOwner);
    kyc.mint(liquidator, 9); // old gate token
    assertFalse(
      OneInchPoolInstance(report.poolProxy).isAuthorizedLiquidator(liquidator),
      'old gate token no longer authorizes'
    );
  }

  function test_setLiquidatorGateOnlyAdmin() public {
    _freshMarket(true);
    address stranger = makeAddr('stranger');
    vm.prank(stranger);
    vm.expectRevert(OneInchPoolInstance.CallerNotPoolOrEmergencyAdmin.selector);
    OneInchPoolInstance(report.poolProxy).setLiquidatorGate(IERC20(address(0)));
  }

  // --------------------------------- helpers -----------------------------------

  /// @dev Deploys a fresh market, lists the launch book, installs the gated pool once
  /// (gated with a KYC NFT, or with the gate disabled), and opens an underwater position.
  function _freshMarket(bool gated) internal {
    _deployMarketAndList();
    pool = IPool(report.poolProxy);

    kyc = new KycNFT('1inch Earn Liquidator KYC', '1EARN-KYC', '1', kycOwner);

    _installGatedPool(gated ? IERC20(address(kyc)) : IERC20(address(0)));
    _openUnderwaterPosition();
  }

  function _installGatedPool(IERC20 gate) internal {
    OneInchPoolInstance gatedPool = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      gate
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(gatedPool));
  }

  function _openUnderwaterPosition() internal {
    // Whale supplies USDC liquidity so the borrower can draw a loan.
    _mint(tokens.usdc, whale, USDC_LIQUIDITY);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, USDC_LIQUIDITY, whale, 0);
    vm.stopPrank();

    // Borrower supplies WBTC collateral and borrows USDC near the LTV limit.
    _mint(tokens.wbtc, borrower, WBTC_SUPPLY);
    vm.startPrank(borrower);
    IERC20(tokens.wbtc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.wbtc, WBTC_SUPPLY, borrower, 0);
    pool.borrow(tokens.usdc, USDC_BORROW, 2, 0, borrower);
    vm.stopPrank();

    // WBTC price craters from $100k to $80k: HF = 80k * 0.78 / 70k = 0.89 < 1.
    vm.mockCall(
      feeds.wbtc,
      abi.encodeWithSignature('latestAnswer()'),
      abi.encode(int256(80_000e8))
    );

    (, , , , , uint256 hf) = pool.getUserAccountData(borrower);
    assertLt(hf, 1e18, 'borrower must be underwater');
  }

  function _fundLiquidator() internal {
    _mint(tokens.usdc, liquidator, USDC_BORROW);
    vm.prank(liquidator);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
  }

  function _mint(address token, address to, uint256 amount) internal {
    vm.prank(deployer);
    TestnetERC20(token).mint(to, amount);
  }
}
