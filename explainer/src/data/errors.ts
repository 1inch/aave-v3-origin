export type ErrorCategory =
  | 'access control'
  | 'user validation'
  | 'liquidation'
  | 'configuration'
  | 'token'
  | 'flash loan'
  | 'eMode';

export type ProtocolError = {
  name: string;
  meaning: string;
  category: ErrorCategory;
  note?: string;
};

// Transcribed from src/contracts/protocol/libraries/helpers/Errors.sol (v3.7)
export const ERRORS: ProtocolError[] = [
  {
    name: 'CallerNotPoolAdmin',
    meaning: 'Caller lacks the POOL_ADMIN role.',
    category: 'access control',
  },
  {
    name: 'CallerNotPoolOrEmergencyAdmin',
    meaning: 'Caller is neither pool nor emergency admin.',
    category: 'access control',
  },
  {
    name: 'CallerNotRiskOrPoolAdmin',
    meaning: 'Caller is neither risk nor pool admin.',
    category: 'access control',
  },
  {
    name: 'CallerNotRiskOrPoolOrEmergencyAdmin',
    meaning:
      'Caller is not risk, pool or emergency admin (e.g. setReserveFreeze, setEModeCategoryIsolated).',
    category: 'access control',
  },
  {
    name: 'CallerNotAssetListingOrPoolAdmin',
    meaning: 'Caller may not list assets.',
    category: 'access control',
  },
  {
    name: 'CallerNotPoolConfigurator',
    meaning: 'Pool method reserved for the PoolConfigurator proxy.',
    category: 'access control',
  },
  {
    name: 'CallerNotAToken',
    meaning: 'Method callable only by a registered aToken (finalizeTransfer).',
    category: 'access control',
  },
  {
    name: 'CallerMustBePool',
    meaning: 'Token mint/burn entry points are Pool-only.',
    category: 'access control',
  },
  {
    name: 'CallerNotUmbrella',
    meaning: 'eliminateReserveDeficit is restricted to the registered Umbrella.',
    category: 'access control',
    note: 'v3.3+',
  },
  {
    name: 'CallerNotPositionManager',
    meaning: 'Caller was not approved via approvePositionManager for the on-behalf-of user.',
    category: 'access control',
    note: 'v3.4+',
  },
  {
    name: 'SelfLiquidation',
    meaning: 'Borrower tried to liquidate their own position.',
    category: 'liquidation',
    note: 'forbidden since v3.4',
  },
  {
    name: 'HealthFactorNotBelowThreshold',
    meaning: 'Liquidation attempted on a healthy account (HF ≥ 1).',
    category: 'liquidation',
  },
  {
    name: 'CollateralCannotBeLiquidated',
    meaning: 'Targeted collateral is not enabled as collateral by the borrower.',
    category: 'liquidation',
  },
  {
    name: 'SpecifiedCurrencyNotBorrowedByUser',
    meaning: 'Targeted debt asset is not borrowed by the borrower.',
    category: 'liquidation',
  },
  {
    name: 'MustNotLeaveDust',
    meaning: 'Liquidation would leave 0 < leftover < $1,000 of debt or collateral on the reserve.',
    category: 'liquidation',
    note: 'rule v3.3, typed error v3.7',
  },
  {
    name: 'LiquidationGraceSentinelCheckFailed',
    meaning: 'Reserve is inside its post-unpause liquidation grace period (≤ 4h).',
    category: 'liquidation',
    note: 'v3.1+',
  },
  {
    name: 'ReserveInactive',
    meaning: 'Reserve not initialized or deactivated.',
    category: 'user validation',
  },
  {
    name: 'ReserveFrozen',
    meaning: 'New supplies/borrows blocked while frozen.',
    category: 'user validation',
  },
  {
    name: 'ReservePaused',
    meaning: 'All actions blocked while paused.',
    category: 'user validation',
  },
  {
    name: 'BorrowingNotEnabled',
    meaning: 'Asset is not flagged borrowable.',
    category: 'user validation',
  },
  {name: 'InvalidAmount', meaning: 'Amount must be greater than 0.', category: 'user validation'},
  {
    name: 'NotEnoughAvailableUserBalance',
    meaning: 'Withdraw exceeds the user balance.',
    category: 'user validation',
  },
  {
    name: 'InvalidInterestRateModeSelected',
    meaning: 'Rate mode must be 2 (variable) — stable was removed in v3.2.',
    category: 'user validation',
  },
  {
    name: 'HealthFactorLowerThanLiquidationThreshold',
    meaning: 'Action would push the account below HF 1 (borrow, withdraw, transfer, eMode switch).',
    category: 'user validation',
  },
  {
    name: 'CollateralCannotCoverNewBorrow',
    meaning: 'Aggregate LTV headroom too small for the requested borrow.',
    category: 'user validation',
  },
  {
    name: 'UserHasAssetWithZeroLtv',
    meaning: 'Action blocked while LTV-0 collateral is enabled (must be withdrawn first).',
    category: 'user validation',
    note: 'renamed in v3.7 (was UserInIsolationModeOrLtvZero)',
  },
  {
    name: 'LtvValidationFailed',
    meaning: 'Aggregate LTV check failed (e.g. borrowing with zero effective LTV).',
    category: 'user validation',
  },
  {
    name: 'NoDebtOfSelectedType',
    meaning: 'Repay called without matching outstanding variable debt.',
    category: 'user validation',
  },
  {
    name: 'NoExplicitAmountToRepayOnBehalf',
    meaning: 'uint256.max repay is not allowed on behalf of someone else.',
    category: 'user validation',
  },
  {
    name: 'UnderlyingBalanceZero',
    meaning: 'Collateral toggle on an asset with zero balance.',
    category: 'user validation',
  },
  {
    name: 'BorrowCapExceeded',
    meaning: 'Total debt would exceed the borrow cap.',
    category: 'user validation',
  },
  {
    name: 'SupplyCapExceeded',
    meaning: 'Total supply would exceed the supply cap.',
    category: 'user validation',
  },
  {
    name: 'WithdrawToAToken',
    meaning: 'Withdrawing to the aToken address is blocked.',
    category: 'user validation',
    note: 'v3.1 defense',
  },
  {
    name: 'SupplyToAToken',
    meaning: 'Supplying on behalf of the aToken address is blocked.',
    category: 'user validation',
    note: 'v3.1 defense',
  },
  {
    name: 'AssetNotListed',
    meaning: 'Asset has no reserve in this pool.',
    category: 'user validation',
  },
  {
    name: 'UserCannotHaveDebt',
    meaning: 'Caller must hold no debt (Umbrella coverage path).',
    category: 'user validation',
    note: 'v3.3+',
  },
  {
    name: 'ReserveNotInDeficit',
    meaning: 'eliminateReserveDeficit on a reserve with zero deficit.',
    category: 'user validation',
    note: 'v3.3+',
  },
  {
    name: 'InvalidFlashloanExecutorReturn',
    meaning: 'executeOperation returned false.',
    category: 'flash loan',
  },
  {
    name: 'InconsistentFlashloanParams',
    meaning: 'assets / amounts / modes arrays have different lengths.',
    category: 'flash loan',
  },
  {
    name: 'FlashloanDisabled',
    meaning: 'Flash-loaning is disabled for this asset.',
    category: 'flash loan',
  },
  {name: 'FlashloanPremiumInvalid', meaning: 'Premium above 100%.', category: 'flash loan'},
  {
    name: 'NotBorrowableInEMode',
    meaning: 'Asset not flagged borrowable in the user’s eMode category.',
    category: 'eMode',
    note: 'v3.2+',
  },
  {
    name: 'InvalidCollateralInEmode(address,uint256)',
    meaning:
      'Entering an eMode while holding enabled collateral that would have zero LTV there (isolated eModes).',
    category: 'eMode',
    note: 'v3.6/v3.7',
  },
  {
    name: 'InvalidDebtInEmode(address,uint256)',
    meaning: 'Entering an eMode while borrowing an asset not borrowable in it.',
    category: 'eMode',
    note: 'v3.6+',
  },
  {
    name: 'MustBeEmodeCollateral(address,uint256)',
    meaning: 'ltvzero flag requires the asset to be an eMode collateral first.',
    category: 'eMode',
    note: 'v3.6+',
  },
  {
    name: 'EModeCategoryReserved',
    meaning: 'Category 0 is reserved for "no eMode".',
    category: 'eMode',
  },
  {
    name: 'InconsistentEModeCategory',
    meaning: 'Invalid category id for this configuration call.',
    category: 'eMode',
  },
  {
    name: 'InvalidEmodeCategoryParams',
    meaning: 'eMode LTV/LT/bonus parameters fail sanity checks.',
    category: 'eMode',
  },
  {name: 'InvalidMintAmount', meaning: 'Scaled mint amount computed as zero.', category: 'token'},
  {name: 'InvalidBurnAmount', meaning: 'Scaled burn amount computed as zero.', category: 'token'},
  {
    name: 'InvalidExpiration',
    meaning: 'permit / delegationWithSig deadline passed.',
    category: 'token',
  },
  {
    name: 'InvalidSignature',
    meaning: 'permit / delegationWithSig signature check failed.',
    category: 'token',
  },
  {
    name: 'OperationNotSupported',
    meaning: 'Called an intentionally unsupported token operation (e.g. transferring debt tokens).',
    category: 'token',
  },
  {name: 'ReserveAlreadyAdded', meaning: 'Asset already has a reserve.', category: 'configuration'},
  {
    name: 'ReserveAlreadyInitialized',
    meaning: 'Reserve init called twice.',
    category: 'configuration',
  },
  {
    name: 'NoMoreReservesAllowed',
    meaning: 'Reserves list is full (128 ids).',
    category: 'configuration',
  },
  {
    name: 'ReserveLiquidityNotZero',
    meaning: 'Config change requires zero liquidity.',
    category: 'configuration',
  },
  {
    name: 'ReserveDebtNotZero',
    meaning: 'Config change requires zero debt.',
    category: 'configuration',
  },
  {
    name: 'InvalidReserveParams',
    meaning: 'Reserve risk parameters fail sanity checks.',
    category: 'configuration',
  },
  {
    name: 'InvalidLtv / InvalidLiquidationThreshold / InvalidLiquidationBonus',
    meaning: 'Collateral parameters out of range or inconsistent (LTV ≤ LT, bonus > 100%…).',
    category: 'configuration',
  },
  {
    name: 'InvalidDecimals',
    meaning: 'Listing requires ≥ 6 decimals (v3.1).',
    category: 'configuration',
  },
  {
    name: 'InvalidReserveFactor / InvalidBorrowCap / InvalidSupplyCap / InvalidLiquidationProtocolFee',
    meaning: 'Value exceeds its allowed maximum.',
    category: 'configuration',
  },
  {
    name: 'InvalidOptimalUsageRatio / InvalidMaxRate / Slope2MustBeGteSlope1',
    meaning: 'Interest-rate parameter sanity checks (max total rate 1000%).',
    category: 'configuration',
    note: 'v3.1+',
  },
  {
    name: 'InvalidGracePeriod',
    meaning: 'Liquidation grace period above the 4h maximum.',
    category: 'configuration',
    note: 'v3.1+',
  },
  {
    name: 'InvalidFreezeState / InvalidLtvzeroState',
    meaning: 'Setting a freeze/ltvzero flag to its current value.',
    category: 'configuration',
    note: 'v3.6+',
  },
  {
    name: 'InvalidReserveIndex',
    meaning: 'Reserve index out of bitmap range.',
    category: 'configuration',
  },
  {
    name: 'ZeroAddressNotValid / NotContract / InconsistentParamsLength',
    meaning: 'Generic input sanity checks.',
    category: 'configuration',
  },
  {
    name: 'AclAdminCannotBeZero',
    meaning: 'ACL admin must be set on the addresses provider.',
    category: 'configuration',
  },
  {
    name: 'AddressesProviderNotRegistered / InvalidAddressesProviderId / AddressesProviderAlreadyAdded / InvalidAddressesProvider',
    meaning: 'PoolAddressesProviderRegistry bookkeeping errors.',
    category: 'configuration',
  },
  {
    name: 'PoolAddressesDoNotMatch',
    meaning: 'Token implementation initialized against the wrong pool.',
    category: 'configuration',
  },
  {
    name: 'UnderlyingCannotBeRescued',
    meaning: 'rescueTokens cannot touch the aToken’s own underlying.',
    category: 'configuration',
  },
];

export const REMOVED_IN_V37 = [
  'DebtCeilingExceeded',
  'InvalidDebtCeiling',
  'DebtCeilingNotZero',
  'AssetNotBorrowableInIsolation',
  'SiloedBorrowingViolation',
  'PriceOracleSentinelCheckFailed',
  'UnderlyingClaimableRightsNotZero',
  'VariableDebtSupplyNotZero',
];
