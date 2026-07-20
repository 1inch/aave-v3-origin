// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {AaveV3BatchOrchestration} from '../../src/deployments/projects/aave-v3-batched/AaveV3BatchOrchestration.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IReserveInterestRateStrategy} from '../../src/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IAaveOracle} from '../../src/contracts/interfaces/IAaveOracle.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';
import {AaveProtocolDataProvider} from '../../src/contracts/helpers/AaveProtocolDataProvider.sol';
import {IOwnableLike} from '../../src/deployments/projects/1inch-earn/OneInchEarnHandover.sol';

import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';
import {OneInchEarnListingPayload} from '../../src/deployments/projects/1inch-earn/OneInchEarnListingPayload.sol';
import {OneInchEarnHandover} from '../../src/deployments/projects/1inch-earn/OneInchEarnHandover.sol';
import {OneInchPoolInstance} from '../../src/deployments/projects/1inch-earn/OneInchPoolInstance.sol';
import {OneInchVariableDebtToken} from '../../src/deployments/projects/1inch-earn/OneInchVariableDebtToken.sol';
import {KycNFT} from '../../src/deployments/projects/1inch-earn/KycNFT.sol';

interface IAggregatorLike {
  function latestAnswer() external view returns (int256);

  function decimals() external view returns (uint8);
}

/**
 * @title OneInchEarnMainnetForkTest
 * @notice Full dress rehearsal of the 1inch Earn rollout against a mainnet fork: deploy
 * the market, list the real launch book (real tokens + real Aave-mainline price adapters),
 * run a supply/borrow/repay + aToken-transfer smoke, exercise NFT-gated liquidation on a
 * real underwater position, then hand over every role to the DAO and audit that the
 * deployer keeps nothing.
 *
 * Skipped automatically unless `RPC_MAINNET` (or `RPC_MAINNET_FORK`) is set, so the
 * default `make test` run needs no network.
 */
contract OneInchEarnMainnetForkTest is Test {
  address internal deployer = makeAddr('oneInchDeployer');
  address internal dao = makeAddr('oneInchDao');
  address internal guardian = makeAddr('oneInchGuardian');
  address internal riskProvider = makeAddr('oneInchRisk');
  address internal kycOwner = makeAddr('kycOwner');

  bool internal forked;
  MarketReport internal report;
  IPool internal pool;
  AaveProtocolDataProvider internal dp;
  OneInchEarnConfig.TokenAddresses internal tokens;
  OneInchEarnConfig.FeedAddresses internal feeds;

  function setUp() public {
    string memory rpc = vm.envOr('RPC_MAINNET', vm.envOr('RPC_MAINNET_FORK', string('')));
    if (bytes(rpc).length == 0) {
      return;
    }
    vm.createSelectFork(rpc);
    forked = true;

    tokens = OneInchEarnConfig.mainnetTokens();
    feeds = OneInchEarnConfig.mainnetFeeds();

    _deployMarket();
    _listLaunchBook();

    pool = IPool(report.poolProxy);
    dp = AaveProtocolDataProvider(report.protocolDataProvider);
  }

  function test_fork_launchBookListedWithRealFeeds() public {
    if (_skip()) return;

    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);
    IAaveOracle oracle = IAaveOracle(report.aaveOracle);

    for (uint256 i = 0; i < listings.length; i++) {
      OneInchEarnConfig.AssetListing memory l = listings[i];
      assertEq(oracle.getSourceOfAsset(l.asset), l.priceFeed, 'oracle source wired');
      assertGt(oracle.getAssetPrice(l.asset), 0, 'positive price');
      assertEq(IAggregatorLike(l.priceFeed).decimals(), 8, 'feed 8 decimals');

      // 1x branding on real tokens.
      address aToken = pool.getReserveAToken(l.asset);
      assertEq(IERC20Metadata(aToken).symbol(), string.concat('1x', l.assetSymbol), '1x symbol');
    }
  }

  function test_fork_oneInchCollateralOnly() public {
    if (_skip()) return;
    (, , , , , bool collateral, bool borrowing, , , ) = dp.getReserveConfigurationData(
      tokens.oneInch
    );
    assertTrue(collateral, '1INCH collateral enabled');
    assertFalse(borrowing, '1INCH borrowing disabled');
    assertFalse(dp.getFlashLoanEnabled(tokens.oneInch), '1INCH flashloans disabled');
  }

  function test_fork_supplyBorrowRepaySmoke() public {
    if (_skip()) return;

    address user = makeAddr('forkUser');
    uint256 wethAmount = 10 ether;
    deal(tokens.weth, user, wethAmount);

    // Provide USDC liquidity from a whale supplier.
    address whale = makeAddr('forkWhale');
    uint256 usdcLiquidity = 500_000e6;
    deal(tokens.usdc, whale, usdcLiquidity, true);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, usdcLiquidity, whale, 0);
    vm.stopPrank();

    vm.startPrank(user);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, wethAmount, user, 0);

    uint256 borrowAmount = 1_000e6;
    pool.borrow(tokens.usdc, borrowAmount, 2, 0, user);
    assertEq(IERC20(tokens.usdc).balanceOf(user), borrowAmount, 'USDC borrowed');

    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.repay(tokens.usdc, type(uint256).max, 2, user);
    vm.stopPrank();

    (, , uint256 availableBorrows, , , uint256 hf) = pool.getUserAccountData(user);
    assertGt(hf, 1e18, 'healthy after repay');
    assertGt(availableBorrows, 0, 'still has borrowing power');
  }

  function test_fork_aTokenTransferWithPreEnabledCollateralFlag() public {
    if (_skip()) return;

    // The Aqua "dust + flag" pattern: an incoming 1x token counts toward health only if
    // the receiver already has the reserve's collateral flag enabled (v3.6 semantics).
    address maker = makeAddr('aquaMaker');
    address taker = makeAddr('aquaTaker');

    deal(tokens.weth, maker, 5 ether);
    deal(tokens.weth, taker, 1); // dust to pre-enable the collateral flag

    address aWeth = pool.getReserveAToken(tokens.weth);

    vm.startPrank(taker);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, 1, taker, 0); // dust supply auto-enables collateral for taker
    vm.stopPrank();

    vm.startPrank(maker);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, 5 ether, maker, 0);
    uint256 sendAmount = 2 ether;
    IERC20(aWeth).transfer(taker, sendAmount);
    vm.stopPrank();

    // The transferred 1x token lands with the taker and counts as collateral (flag pre-enabled).
    (uint256 totalCollateralBase, , , , , uint256 hf) = pool.getUserAccountData(taker);
    assertGt(totalCollateralBase, 0, 'taker collateral includes received 1x token');
    assertEq(hf, type(uint256).max, 'no debt -> infinite HF');
    assertGt(IERC20(aWeth).balanceOf(taker), sendAmount - 10, 'taker received aWETH');
  }

  function test_fork_nftGatedLiquidation() public {
    if (_skip()) return;

    KycNFT kyc = new KycNFT('1inch Earn Liquidator KYC', '1EARN-KYC', '1', kycOwner);
    OneInchPoolInstance gatedPool = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      IERC20(address(kyc))
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(gatedPool));

    // Build an underwater WETH-collateral / USDC-debt position.
    address whale = makeAddr('liqWhale');
    address borrower = makeAddr('liqBorrower');
    address liquidator = makeAddr('liqLiquidator');

    deal(tokens.usdc, whale, 500_000e6, true);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 500_000e6, whale, 0);
    vm.stopPrank();

    deal(tokens.weth, borrower, 10 ether);
    vm.startPrank(borrower);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, 10 ether, borrower, 0);
    uint256 wethPrice = uint256(IAggregatorLike(feeds.weth).latestAnswer()); // 8 decimals USD
    // Borrow ~75% of collateral value in USDC (WETH LTV is 80%).
    uint256 borrowUsd = (10 * wethPrice * 75) / 100; // 8-decimals USD
    uint256 borrowUsdc = borrowUsd / 100; // 8 -> 6 decimals
    pool.borrow(tokens.usdc, borrowUsdc, 2, 0, borrower);
    vm.stopPrank();

    // Crash WETH price 40% to force HF < 1.
    vm.mockCall(
      feeds.weth,
      abi.encodeWithSignature('latestAnswer()'),
      abi.encode(int256((wethPrice * 60) / 100))
    );
    (, , , , , uint256 hf) = pool.getUserAccountData(borrower);
    assertLt(hf, 1e18, 'borrower underwater');

    // Fund liquidator with USDC.
    deal(tokens.usdc, liquidator, 500_000e6, true);
    vm.prank(liquidator);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);

    // Without the KYC NFT -> rejected.
    vm.prank(liquidator);
    vm.expectRevert(OneInchPoolInstance.OnlyKycLiquidators.selector);
    pool.liquidationCall(tokens.weth, tokens.usdc, borrower, type(uint256).max, false);

    // With the KYC NFT -> succeeds, and the NFT stays put.
    vm.prank(kycOwner);
    kyc.mint(liquidator, 1);
    uint256 wethBefore = IERC20(tokens.weth).balanceOf(liquidator);
    vm.prank(liquidator);
    pool.liquidationCall(tokens.weth, tokens.usdc, borrower, type(uint256).max, false);

    // receiveAToken=false -> liquidator is paid in underlying WETH collateral.
    assertGt(IERC20(tokens.weth).balanceOf(liquidator), wethBefore, 'seized WETH collateral');
    assertEq(kyc.balanceOf(liquidator), 1, 'liquidator keeps KYC NFT');
  }

  function test_fork_singleDirectionDebtHandoff() public {
    if (_skip()) return;

    // Install the gated pool (carries finalizeDebtTransfer) and enable USDC debt transfers.
    OneInchPoolInstance impl = new OneInchPoolInstance(
      IPoolAddressesProvider(report.poolAddressesProvider),
      IReserveInterestRateStrategy(report.defaultInterestRateStrategy),
      IERC20(address(0))
    );
    vm.prank(deployer);
    IPoolAddressesProvider(report.poolAddressesProvider).setPoolImpl(address(impl));

    OneInchVariableDebtToken usdcDebt = OneInchVariableDebtToken(
      pool.getReserveVariableDebtToken(tokens.usdc)
    );
    vm.prank(deployer);
    usdcDebt.setTransferable(true);

    // USDC liquidity.
    address whale = makeAddr('handoffWhale');
    deal(tokens.usdc, whale, 500_000e6, true);
    vm.startPrank(whale);
    IERC20(tokens.usdc).approve(address(pool), type(uint256).max);
    pool.supply(tokens.usdc, 500_000e6, whale, 0);
    vm.stopPrank();

    // Borrower: 10 WETH collateral, borrows 5k USDC.
    address borrower = makeAddr('handoffBorrower');
    deal(tokens.weth, borrower, 10 ether);
    vm.startPrank(borrower);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, 10 ether, borrower, 0);
    pool.borrow(tokens.usdc, 5_000e6, 2, 0, borrower);
    vm.stopPrank();

    // Receiver: 10 WETH collateral, opts in by crediting the borrower.
    address receiver = makeAddr('handoffReceiver');
    deal(tokens.weth, receiver, 10 ether);
    vm.startPrank(receiver);
    IERC20(tokens.weth).approve(address(pool), type(uint256).max);
    pool.supply(tokens.weth, 10 ether, receiver, 0);
    usdcDebt.credit(borrower, 5_000e6);
    vm.stopPrank();

    uint256 amount = 4_000e6;
    vm.prank(borrower);
    usdcDebt.transfer(receiver, amount);

    assertApproxEqAbs(usdcDebt.balanceOf(receiver), amount, 2, 'receiver assumed debt vs own collateral');
    (, , , , , uint256 receiverHf) = pool.getUserAccountData(receiver);
    (, , , , , uint256 borrowerHf) = pool.getUserAccountData(borrower);
    assertGt(receiverHf, 1e18, 'receiver solvent');
    assertGt(borrowerHf, 1e18, 'borrower solvent');
  }

  function test_fork_handoverRevokesDeployer() public {
    if (_skip()) return;

    OneInchEarnHandover.HandoverTargets memory targets = OneInchEarnHandover.HandoverTargets({
      daoExecutor: dao,
      guardian: guardian,
      riskProvider: riskProvider
    });

    vm.startPrank(deployer);
    OneInchEarnHandover.execute(report, targets, deployer);
    vm.stopPrank();

    ACLManager acl = ACLManager(report.aclManager);

    // New operators installed.
    assertTrue(acl.isPoolAdmin(dao), 'dao pool admin');
    assertTrue(acl.hasRole(bytes32(0), dao), 'dao default admin');
    assertTrue(acl.isEmergencyAdmin(guardian), 'guardian emergency admin');
    assertTrue(acl.isRiskAdmin(riskProvider), 'risk provider risk admin');

    // Deployer stripped of everything.
    assertFalse(acl.isPoolAdmin(deployer), 'deployer not pool admin');
    assertFalse(acl.isEmergencyAdmin(deployer), 'deployer not emergency admin');
    assertFalse(acl.hasRole(bytes32(0), deployer), 'deployer not default admin');

    // Ownership moved.
    assertEq(IOwnableLike(report.poolAddressesProvider).owner(), dao, 'provider owned by dao');
    assertEq(
      IOwnableLike(report.poolAddressesProviderRegistry).owner(),
      dao,
      'registry owned by dao'
    );
    assertEq(IOwnableLike(report.emissionManager).owner(), dao, 'emission manager owned by dao');
    assertEq(IOwnableLike(report.wrappedTokenGateway).owner(), dao, 'gateway owned by dao');
    assertEq(IPoolAddressesProvider(report.poolAddressesProvider).getACLAdmin(), dao, 'acl admin');

    // Transparent-proxy admins (upgrade rights) moved to the DAO.
    assertEq(_proxyAdminOwner(report.treasury), dao, 'treasury proxy admin -> dao');
    assertEq(_proxyAdminOwner(report.dustBin), dao, 'dustBin proxy admin -> dao');
    assertEq(
      _proxyAdminOwner(report.staticATokenFactoryProxy),
      dao,
      'static factory proxy admin -> dao'
    );
  }

  /// @dev Reads the ERC-1967 admin slot and returns its owner (the ProxyAdmin's owner).
  function _proxyAdminOwner(address proxy) internal view returns (address) {
    bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address proxyAdmin = address(uint160(uint256(vm.load(proxy, adminSlot))));
    return IOwnableLike(proxyAdmin).owner();
  }

  // --------------------------------- helpers -----------------------------------

  function _skip() internal returns (bool) {
    if (!forked) {
      vm.skip(true);
      return true;
    }
    return false;
  }

  function _deployMarket() internal {
    Roles memory roles = Roles(deployer, deployer, deployer);
    DeployFlags memory flags;
    MarketReport memory empty;

    MarketConfig memory config = MarketConfig({
      networkBaseTokenPriceInUsdProxyAggregator: OneInchEarnConfig.ETH_USD_FEED,
      marketReferenceCurrencyPriceInUsdProxyAggregator: OneInchEarnConfig.ETH_USD_FEED,
      marketId: OneInchEarnConfig.MARKET_ID,
      oracleDecimals: OneInchEarnConfig.ORACLE_DECIMALS,
      providerId: OneInchEarnConfig.PROVIDER_ID,
      salt: bytes32(0),
      wrappedNativeToken: tokens.weth,
      flashLoanPremium: OneInchEarnConfig.FLASH_LOAN_PREMIUM_TOTAL,
      incentivesProxy: address(0),
      treasury: address(0)
    });

    vm.startPrank(deployer);
    report = AaveV3BatchOrchestration.deployAaveV3(deployer, roles, config, flags, empty);
    vm.stopPrank();
  }

  function _listLaunchBook() internal {
    OneInchEarnConfig.AssetListing[] memory listings = OneInchEarnConfig.listings(tokens, feeds);
    OneInchEarnListingPayload payload = new OneInchEarnListingPayload(
      report,
      listings,
      OneInchEarnConfig.ethCorrelatedEMode()
    );

    vm.prank(deployer);
    ACLManager(report.aclManager).addPoolAdmin(address(payload));
    payload.execute();
  }
}
