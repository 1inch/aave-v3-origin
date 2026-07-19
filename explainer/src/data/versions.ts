export type Version = {
  ver: string;
  when: string;
  headline: string;
  major?: boolean;
  items: string[];
};

/**
 * Source of truth: docs/3.x/Aave-v3.x-features.md + README.md audit index.
 * To onboard a future release (e.g. v3.8): add its entry here, review the
 * affected slides, and update the title-slide pills if the headline changes.
 */
export const VERSIONS: Version[] = [
  {
    ver: 'v3.0',
    when: 'Mar 2022',
    headline: 'The v3 foundation: eModes, isolation mode, caps, gas rework',
    major: true,
    items: [
      'Portal-ready architecture, efficiency mode (eMode) v1, isolation mode with debt ceilings, siloed borrowing',
      'Supply & borrow caps, granular roles via ACLManager, L2Pool with calldata compression',
      'Patch releases v3.0.1 (Dec 2022) and v3.0.2 (Apr 2023)',
    ],
  },
  {
    ver: 'v3.1',
    when: 'Apr 2024',
    headline: 'Virtual accounting & the stateful rate strategy',
    items: [
      'virtualUnderlyingBalance tracks every in/outflow — donations can no longer skew utilization (defense-in-depth)',
      'One stateful DefaultReserveInterestRateStrategyV2 for all assets; rate caps (≤1000%)',
      'Liquidation grace period after unpause (≤4h); freeze sets LTV 0 atomically; min 6 decimals for listings; emergency admin can freeze',
    ],
  },
  {
    ver: 'v3.2',
    when: 'Sep 2024',
    headline: 'Stable rate removed · liquid eModes',
    major: true,
    items: [
      'All stable-rate logic deleted — variable is the only mode',
      'Liquid eModes: per-category collateralBitmap + borrowableBitmap, any asset in any number of categories, eMode oracle removed',
    ],
  },
  {
    ver: 'v3.3',
    when: 'Jan 2025',
    headline: 'Bad-debt deficit & the close-factor redesign',
    items: [
      'Zero-collateral positions get remaining debt burned into a tracked reserve.deficit; eliminateReserveDeficit for Umbrella',
      'Close factor position-wide; 100% close factor for positions < $2,000; MustNotLeaveDust forbids leftovers < $1,000',
      'Read-optimized config bitmasks; getReserveAToken/getReserveVariableDebtToken getters',
    ],
  },
  {
    ver: 'v3.4',
    when: 'Jun 2025',
    headline: 'GHO alignment, multicall, position managers',
    items: [
      'GHO became a normal reserve (virtual accounting everywhere); custom aGHO/vGHO retired',
      'Multicall on the Pool; position-manager approvals; self-liquidation forbidden',
      'Immutables: rate strategy, treasury, rewards controller; custom error types (solc 0.8.27); "unbacked"/portals removed; flash-loan fees 100% to treasury; DustBin',
    ],
  },
  {
    ver: 'v3.5',
    when: 'Jul 2025',
    headline: 'Deterministic token rounding & scaled accounting',
    items: [
      'Every mint/burn/balance rounds in the protocol’s favor (aToken: floor/ceil/floor · vToken: ceil/floor/ceil); TokenMath library',
      'Operations pass scaled amounts end-to-end, removing repeated lossy conversions; HF valuations pessimistic (collateral down, debt up)',
      'Borrow HF check moved after state changes; collateral flags reliably cleared; exact allowance consumption',
    ],
  },
  {
    ver: 'v3.6',
    when: 'Nov 2025',
    headline: 'eMode decoupling · auto-collateral cleanup',
    items: [
      'eMode fully decoupled from base config + per-category ltvzeroBitmap: collateral-only-in-eMode, borrowable-only-in-eMode',
      'Auto-enable-as-collateral removed on aToken transfers and liquidations (supply still auto-enables)',
      'renounceAllowance / renounceDelegation; OZ-aligned event behavior; freeze cascades ltvzero into affected eModes',
    ],
  },
  {
    ver: 'v3.7',
    when: 'Mar 2026',
    headline: 'Isolated eModes · big cleanup · liquidation rounding',
    major: true,
    items: [
      'bool isolated on eMode categories: outside-bitmap collateral contributes zero LTV — automatic risk isolation',
      'Removed: isolation mode & siloed borrowing, PriceOracleSentinel/SequencerOracle, dropReserve (reserves list append-only)',
      'Deterministic floor/ceil rounding in liquidations; scaled-balance-based bad-debt detection; ConfiguratorLogic & config-engine libraries inlined',
      'Pool revision 11, PoolConfigurator revision 8',
    ],
  },
];
