// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDefaultInterestRateStrategyV2} from '../../../contracts/interfaces/IDefaultInterestRateStrategyV2.sol';

/**
 * @title OneInchEarnConfig
 * @author 1inch
 * @notice Single source of truth for the "1inch Earn" Aave v3.7 instance on Ethereum mainnet.
 * @dev Encodes the launch book approved on 19 Jul 2026 (C-level briefing):
 * - 1INCH (and later AQUA): collateral-only, borrowing disabled at listing, forever, by policy.
 * - Blue chips two-sided: WETH, wstETH, WBTC, cbBTC, USDC, USDT.
 * - ETH-correlated eMode (WETH/wstETH) at 93% liquidation threshold.
 *
 * IMPORTANT conventions (misconfiguration is the #1 fork killer — read carefully):
 * - All percentage values use bps in the PoolConfigurator format: 80_00 = 80.00%.
 * - `liquidationBonus` uses the configurator format where 110_00 means a 10% bonus
 *   (the protocol requires the value to be above 100_00).
 * - Supply/borrow caps are denominated in WHOLE TOKENS of the underlying, not USD
 *   (the protocol compares against cap * 10 ** decimals). USD anchors from the launch
 *   book are converted at the reference prices documented below and MUST be re-checked
 *   by the risk provider right before launch and re-tuned as prices move.
 * - Interest rate params use bps as defined by `IDefaultInterestRateStrategyV2.InterestRateData`.
 */
library OneInchEarnConfig {
  // ----------------------------- Market constants ------------------------------

  string internal constant MARKET_ID = '1inch Earn Ethereum Market';

  /// @dev Fresh registry owned by the 1inch DAO; 1 = the main (and only) market.
  uint256 internal constant PROVIDER_ID = 1;

  /// @dev USD-denominated market: 8 decimals base currency unit, like Aave mainline.
  uint8 internal constant ORACLE_DECIMALS = 8;

  /// @dev Total flashloan premium, in bps of the PercentageMath scale: 5 = 0.05%.
  uint128 internal constant FLASH_LOAN_PREMIUM_TOTAL = 0.0005e4;

  /// @dev CREATE2 salt used for the Collector (treasury) and dustBin deployment.
  bytes32 internal constant COLLECTOR_SALT = keccak256('1INCH_EARN_COLLECTOR_V1');

  // ------------------------------- 1x branding ---------------------------------

  string internal constant ATOKEN_NAME_PREFIX = '1inch Earn ';
  string internal constant ATOKEN_SYMBOL_PREFIX = '1x';
  string internal constant VDEBT_NAME_PREFIX = '1inch Earn Variable Debt ';
  string internal constant VDEBT_SYMBOL_PREFIX = '1xDebt';

  // ------------------------------ Liquidator gate ------------------------------

  string internal constant KYC_NFT_NAME = '1inch Earn Liquidator KYC';
  string internal constant KYC_NFT_SYMBOL = '1EARN-KYC';
  string internal constant KYC_NFT_VERSION = '1';

  // ----------------------------------- eMode -----------------------------------

  uint8 internal constant ETH_CORRELATED_EMODE_ID = 1;

  // ----------------------- Mainnet underlying addresses ------------------------

  address internal constant ONEINCH = 0x111111111117dC0aa78b770fA6A738034120C302;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
  address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
  address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  // -------------------------- Mainnet Chainlink feeds --------------------------
  // All feeds MUST answer in 8 decimals (asserted by the fork dress rehearsal) and
  // MUST pass the independent oracle review before launch.

  /// @dev Chainlink ETH/USD.
  address internal constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

  /// @dev Chainlink 1INCH/USD.
  address internal constant ONEINCH_USD_FEED = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;

  /// @dev Chainlink BTC/USD. VERIFY: Aave mainline prices WBTC through a composed
  /// WBTC/BTC * BTC/USD adapter to capture bridge de-peg risk; the risk provider must
  /// decide whether to deploy the composed adapter before launch.
  address internal constant WBTC_USD_FEED = 0xF4030086522a5beea4988f8ca5b36dBc97BCe88C;

  /// @dev Chainlink cbBTC/USD. VERIFY on-chain before launch (fork test sanity-checks it).
  address internal constant CBBTC_USD_FEED = 0x2665701293fCbEB223D11A08D826563EDcCE423A;

  /// @dev Chainlink USDC/USD.
  address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

  /// @dev Chainlink USDT/USD.
  address internal constant USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

  // NOTE: wstETH has NO direct constant on purpose. A CAPO-style correlated-asset
  // price adapter (wstETH -> stETH exchange rate composed with a USD feed, upside
  // capped) must be deployed and reviewed before launch, then passed explicitly to
  // `mainnetFeeds(address wstEthUsdFeed)`.

  // ---------------------------------- Types ------------------------------------

  struct AssetListing {
    address asset;
    string assetSymbol;
    address priceFeed;
    // Collateral side (configurator format; liquidationBonus 110_00 = 10% bonus).
    uint256 ltv;
    uint256 liqThreshold;
    uint256 liquidationBonus;
    uint256 liqProtocolFee;
    // Borrow side.
    bool enabledToBorrow;
    bool flashloanable;
    uint256 reserveFactor;
    // Caps in whole tokens of the underlying.
    uint256 supplyCap;
    uint256 borrowCap;
    // ETH-correlated eMode membership.
    bool eModeCollateral;
    bool eModeBorrowable;
    // Interest rate strategy params (bps).
    IDefaultInterestRateStrategyV2.InterestRateData rates;
  }

  struct EModeConfig {
    uint8 categoryId;
    uint16 ltv;
    uint16 liqThreshold;
    // Configurator format: 101_00 = 1% bonus.
    uint16 liquidationBonus;
    string label;
    // false = standard liquid eMode. Setting true (isolated eMode, v3.7) would zero
    // the LTV of any collateral outside the category for users inside the eMode.
    // Decision: launch non-isolated to keep pro cross-margin flexibility; the DAO can
    // flip it later via `setEModeCategoryIsolated` without liquidating existing users.
    bool isolated;
  }

  struct TokenAddresses {
    address oneInch;
    address weth;
    address wstEth;
    address wbtc;
    address cbBtc;
    address usdc;
    address usdt;
  }

  struct FeedAddresses {
    address oneInch;
    address weth;
    address wstEth;
    address wbtc;
    address cbBtc;
    address usdc;
    address usdt;
  }

  // ------------------------------ Config builders -------------------------------

  function mainnetTokens() internal pure returns (TokenAddresses memory) {
    return
      TokenAddresses({
        oneInch: ONEINCH,
        weth: WETH,
        wstEth: WSTETH,
        wbtc: WBTC,
        cbBtc: CBBTC,
        usdc: USDC,
        usdt: USDT
      });
  }

  /// @param wstEthUsdFeed The reviewed CAPO-style wstETH/USD adapter (see note above).
  function mainnetFeeds(address wstEthUsdFeed) internal pure returns (FeedAddresses memory) {
    require(wstEthUsdFeed != address(0), 'WSTETH_FEED_REQUIRED');
    return
      FeedAddresses({
        oneInch: ONEINCH_USD_FEED,
        weth: ETH_USD_FEED,
        wstEth: wstEthUsdFeed,
        wbtc: WBTC_USD_FEED,
        cbBtc: CBBTC_USD_FEED,
        usdc: USDC_USD_FEED,
        usdt: USDT_USD_FEED
      });
  }

  function ethCorrelatedEMode() internal pure returns (EModeConfig memory) {
    return
      EModeConfig({
        categoryId: ETH_CORRELATED_EMODE_ID,
        ltv: 90_00,
        liqThreshold: 93_00, // launch book: "ETH eMode 93%"
        liquidationBonus: 101_00, // 1% bonus; 93_00 * 101_00 = 93.93% <= 100% (protocol invariant)
        label: 'ETH correlated',
        isolated: false
      });
  }

  /**
   * @notice The phase-1 launch book: 7 reserves.
   * @dev Cap conversion anchors (documented assumptions, retune before launch):
   * - 1INCH  $1.0M  at $0.40  => 2,500,000 1INCH (staged ratchet to 5,000,000 = $2M)
   * - WETH   $10M   at $3,300 => 3,000 WETH
   * - wstETH $10M   at $4,000 => 2,500 wstETH
   * - WBTC   $10M   at $100k  => 100 WBTC (same for cbBTC)
   * - USDC/USDT $10M => 10,000,000 tokens
   */
  function listings(
    TokenAddresses memory tokens,
    FeedAddresses memory feeds
  ) internal pure returns (AssetListing[] memory result) {
    result = new AssetListing[](7);

    // --- 1INCH: THE RED ROW. Collateral-only, borrowing disabled at listing, forever,
    // by policy. No flashloans: supplied 1INCH must not be rentable, even intra-tx.
    result[0] = AssetListing({
      asset: tokens.oneInch,
      assetSymbol: '1INCH',
      priceFeed: feeds.oneInch,
      ltv: 55_00,
      liqThreshold: 65_00,
      liquidationBonus: 110_00, // 65_00 * 110_00 = 71.5% <= 100%; 25pt bad-debt margin vs LT
      liqProtocolFee: 10_00,
      enabledToBorrow: false,
      flashloanable: false,
      reserveFactor: 20_00,
      supplyCap: 2_500_000,
      borrowCap: 0,
      eModeCollateral: false,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 45_00, // mandatory even for non-borrowable reserves
        baseVariableBorrowRate: 0,
        variableRateSlope1: 7_00,
        variableRateSlope2: 300_00
      })
    });

    // --- WETH: two-sided blue chip; ETH-correlated eMode collateral + borrowable.
    result[1] = AssetListing({
      asset: tokens.weth,
      assetSymbol: 'WETH',
      priceFeed: feeds.weth,
      ltv: 80_00,
      liqThreshold: 83_00,
      liquidationBonus: 105_00,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 15_00,
      supplyCap: 3_000,
      borrowCap: 2_400,
      eModeCollateral: true,
      eModeBorrowable: true,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 90_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 2_70,
        variableRateSlope2: 80_00
      })
    });

    // --- wstETH: collateral-heavy LST; eMode collateral, small borrow side.
    result[2] = AssetListing({
      asset: tokens.wstEth,
      assetSymbol: 'wstETH',
      priceFeed: feeds.wstEth,
      ltv: 80_00,
      liqThreshold: 83_00,
      liquidationBonus: 106_00,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 15_00,
      supplyCap: 2_500,
      borrowCap: 250,
      eModeCollateral: true,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 25,
        variableRateSlope1: 4_50,
        variableRateSlope2: 80_00
      })
    });

    // --- WBTC.
    result[3] = AssetListing({
      asset: tokens.wbtc,
      assetSymbol: 'WBTC',
      priceFeed: feeds.wbtc,
      ltv: 73_00,
      liqThreshold: 78_00,
      liquidationBonus: 106_50,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 20_00,
      supplyCap: 100,
      borrowCap: 40,
      eModeCollateral: false,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 4_00,
        variableRateSlope2: 300_00
      })
    });

    // --- cbBTC.
    result[4] = AssetListing({
      asset: tokens.cbBtc,
      assetSymbol: 'cbBTC',
      priceFeed: feeds.cbBtc,
      ltv: 73_00,
      liqThreshold: 78_00,
      liquidationBonus: 106_50,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 20_00,
      supplyCap: 100,
      borrowCap: 40,
      eModeCollateral: false,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 45_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 4_00,
        variableRateSlope2: 300_00
      })
    });

    // --- USDC: primary borrow engine.
    result[5] = AssetListing({
      asset: tokens.usdc,
      assetSymbol: 'USDC',
      priceFeed: feeds.usdc,
      ltv: 75_00,
      liqThreshold: 78_00,
      liquidationBonus: 104_50,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 10_00,
      supplyCap: 10_000_000,
      borrowCap: 9_000_000,
      eModeCollateral: false,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 90_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 5_50,
        variableRateSlope2: 60_00
      })
    });

    // --- USDT: primary borrow engine.
    result[6] = AssetListing({
      asset: tokens.usdt,
      assetSymbol: 'USDT',
      priceFeed: feeds.usdt,
      ltv: 75_00,
      liqThreshold: 78_00,
      liquidationBonus: 104_50,
      liqProtocolFee: 10_00,
      enabledToBorrow: true,
      flashloanable: true,
      reserveFactor: 10_00,
      supplyCap: 10_000_000,
      borrowCap: 9_000_000,
      eModeCollateral: false,
      eModeBorrowable: false,
      rates: IDefaultInterestRateStrategyV2.InterestRateData({
        optimalUsageRatio: 90_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 5_50,
        variableRateSlope2: 60_00
      })
    });
  }

  /**
   * @notice The phase-2 AQUA listing (post-TGE, gated: live Chainlink-quality feed,
   * 30 days of trading, proven 2% depth). Same red-row policy as 1INCH.
   * @dev Published quarterly ratchet: LTV/LT start at 30% / 38.5% and may step toward
   * 50% / 62.5% via `configureReserveAsCollateral` (governance) as history accrues.
   * Cap anchor: $0.5M converted at the TGE reference price by the risk provider.
   */
  function aquaListing(
    address aqua,
    address aquaUsdFeed,
    uint256 supplyCapTokens
  ) internal pure returns (AssetListing memory) {
    return
      AssetListing({
        asset: aqua,
        assetSymbol: 'AQUA',
        priceFeed: aquaUsdFeed,
        ltv: 30_00,
        liqThreshold: 38_50,
        liquidationBonus: 112_50, // 38_50 * 112_50 = 43.31% <= 100%
        liqProtocolFee: 10_00,
        enabledToBorrow: false, // THE RED ROW: never borrowable
        flashloanable: false,
        reserveFactor: 20_00,
        supplyCap: supplyCapTokens,
        borrowCap: 0,
        eModeCollateral: false,
        eModeBorrowable: false,
        rates: IDefaultInterestRateStrategyV2.InterestRateData({
          optimalUsageRatio: 45_00,
          baseVariableBorrowRate: 0,
          variableRateSlope1: 7_00,
          variableRateSlope2: 300_00
        })
      });
  }
}
