export type GlossaryEntry = {term: string; def: string};

export const GLOSSARY: GlossaryEntry[] = [
  {
    term: 'ray',
    def: '27-decimal fixed-point unit (1e27). Indexes and rates are stored in ray; WadRayMath implements the arithmetic.',
  },
  {
    term: 'wad',
    def: '18-decimal fixed-point unit (1e18). The health factor is returned as a wad: 1e18 means exactly 1.0.',
  },
  {
    term: 'bps',
    def: 'Basis points, 1/100th of a percent. PercentageMath uses a 1e4 factor, so 10000 = 100%, 50 = 0.5%.',
  },
  {
    term: 'base currency',
    def: 'The unit the AaveOracle prices everything in — USD with 8 decimals on Aave v3 markets. All risk math (health factor, liquidation thresholds like the $2,000 close-factor bound) happens in base currency.',
  },
  {
    term: 'reserve',
    def: 'One listed asset: the underlying ERC-20 plus its aToken, variable debt token, configuration bitmap, interest-rate params and indexes. Identified by an id in the (append-only since v3.7) reserves list.',
  },
  {
    term: 'scaled balance',
    def: 'A user’s share of a reserve, stored on the token: amount ÷ index at interaction time. Actual balances are reconstructed as scaled × current index, which is how interest accrues without per-user writes.',
  },
  {
    term: 'index',
    def: 'Cumulative interest factor of a reserve, starting at 1 ray on listing. liquidityIndex grows with linear (simple) interest for suppliers; variableBorrowIndex compounds per second for borrowers.',
  },
  {
    term: 'utilization',
    def: 'totalDebt / (virtualUnderlyingBalance + totalDebt). The single input that drives the interest-rate curve.',
  },
  {
    term: 'LTV',
    def: 'Loan-to-value: the borrowing power a collateral grants when opening or increasing positions. Checked on borrow and withdraw; irrelevant for liquidations.',
  },
  {
    term: 'liquidation threshold',
    def: 'LT: the collateral weighting used in the health factor. Always ≥ LTV; crossing it (HF < 1) makes the position liquidatable.',
  },
  {
    term: 'liquidation bonus',
    def: 'The discount a liquidator receives on seized collateral, encoded as e.g. 10500 = 5% bonus. Part of the bonus can be skimmed as the liquidation protocol fee.',
  },
  {
    term: 'close factor',
    def: 'The share of a borrower’s total debt repayable in one liquidation: 50% by default (position-wide since v3.3), 100% when HF ≤ 0.95 or when the targeted reserve’s collateral or debt is below $2,000.',
  },
  {
    term: 'health factor',
    def: 'Σ(collateral_i × LT_i) / totalDebt, in base currency. Below 1.0 the account can be liquidated. Since v3.5 collateral is valued rounding down and debt rounding up.',
  },
  {
    term: 'reserve factor',
    def: 'The share of borrow interest routed to the DAO treasury (Collector), accrued as aTokens via accruedToTreasury.',
  },
  {
    term: 'virtual balance',
    def: 'virtualUnderlyingBalance (v3.1): internally tracked liquidity updated on every in/outflow. Rates and available-liquidity checks read it instead of ERC-20 balanceOf, making donations irrelevant.',
  },
  {
    term: 'deficit',
    def: 'Bad debt recognized per reserve (v3.3): when a liquidation leaves zero collateral but debt, the debt is burned and booked as reserve.deficit, coverable later via eliminateReserveDeficit.',
  },
  {
    term: 'Umbrella',
    def: 'Aave’s automated safety module. Users stake wrapped aTokens (waTokens / StataTokenV2) or GHO; when a reserve deficit exceeds the DAO-funded deficit offset, stakes are slashed and burned to cover it — no governance vote needed.',
  },
  {
    term: 'eMode',
    def: 'Efficiency mode: a category with boosted LTV/LT/bonus plus collateral, borrowable and ltvzero bitmaps over the reserves list. Users opt in via setUserEMode; category 0 = no eMode.',
  },
  {
    term: 'isolated eMode',
    def: 'v3.7 flag on an eMode category. When true, collateral outside the category’s collateralBitmap contributes zero LTV (it still counts for the health factor).',
  },
  {
    term: 'ltv0 rules',
    def: 'Assets with effective LTV 0 cannot back new borrows, cannot be newly enabled as collateral, and must be withdrawn before any other collateral.',
  },
  {
    term: 'aToken',
    def: 'Interest-bearing, transferable receipt token (aWETH, aUSDC…). Holds the reserve’s underlying liquidity; balance grows with the liquidityIndex.',
  },
  {
    term: 'variable debt token',
    def: 'Non-transferable token tracking a user’s debt; balance grows with the variableBorrowIndex. Supports credit delegation.',
  },
  {
    term: 'credit delegation',
    def: 'approveDelegation(delegatee, amount) on a debt token lets another address borrow against your collateral, up to the approved amount.',
  },
  {
    term: 'position manager',
    def: 'v3.4 role a user grants via approvePositionManager: the manager may toggle collateral flags and switch eModes on the user’s behalf.',
  },
  {
    term: 'grace period',
    def: 'Optional window (max 4h) set when unpausing a reserve during which liquidations stay blocked, giving users time to repay or top up (v3.1).',
  },
  {
    term: 'supply / borrow caps',
    def: 'Per-reserve hard limits on total supply and total debt, in whole tokens. Checked in scaled terms since v3.5.',
  },
];

export function findGlossary(term: string): GlossaryEntry | undefined {
  const t = term.toLowerCase();
  return GLOSSARY.find((g) => g.term.toLowerCase() === t);
}
