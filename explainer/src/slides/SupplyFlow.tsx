import { StepFlow } from "../components/StepFlow";
import type { FlowActor, FlowStep } from "../components/StepFlow";

const ACTORS: FlowActor[] = [
  { id: "user", label: "User" },
  { id: "pool", label: "Pool", sub: "SupplyLogic" },
  { id: "reserve", label: "ReserveLogic" },
  { id: "validation", label: "ValidationLogic" },
  { id: "atoken", label: "aWETH", sub: "AToken" },
  { id: "erc20", label: "WETH", sub: "ERC-20" },
];

const STEPS: FlowStep[] = [
  {
    from: "user",
    to: "pool",
    label: "supply(WETH, 10, user, 0)",
    kind: "call",
    title: "User calls supply()",
    desc: "Anyone can supply on behalf of any address. The Pool routes into SupplyLogic.executeSupply via a linked-library delegatecall.",
  },
  {
    from: "pool",
    to: "reserve",
    label: "updateState()",
    kind: "call",
    title: "Refresh the reserve",
    desc: "Cumulates liquidityIndex and variableBorrowIndex since lastUpdateTimestamp and accrues the reserve-factor share of new debt interest to the treasury. Runs at most once per block.",
  },
  {
    from: "pool",
    to: "validation",
    label: "validateSupply()",
    kind: "check",
    title: "Checks",
    desc: "Reserve must be active, not paused, not frozen; the resulting total supply (in scaled terms since v3.5) must stay under the supply cap; supplying to the aToken address itself is blocked.",
  },
  {
    from: "pool",
    to: "reserve",
    label: "updateInterestRatesAndVirtualBalance(+10)",
    kind: "call",
    title: "Reprice the reserve",
    desc: "The new liquidity lowers utilization, so borrow & supply rates drop. The inflow is added to virtualUnderlyingBalance — the v3.1 defense that makes donations irrelevant to protocol accounting.",
  },
  {
    from: "user",
    to: "erc20",
    label: "safeTransferFrom(user → aWETH, 10)",
    kind: "transfer",
    title: "Pull the underlying",
    desc: "The 10 WETH move from the user into the aToken contract, which custodies all of the reserve’s liquidity.",
  },
  {
    from: "pool",
    to: "atoken",
    label: "mint(scaled = ⌊10 / index⌋)",
    kind: "mint",
    title: "Mint the receipt",
    desc: "The user receives scaled aTokens: amount ÷ liquidityIndex, rounded down (v3.5). From here their balance grows automatically as the index climbs.",
  },
  {
    from: "pool",
    to: "pool",
    label: "setUsingAsCollateral(true)",
    kind: "event",
    title: "First supply enables collateral",
    desc: "If this is the user’s first balance of the asset and the asset has an LTV, it is automatically flagged as collateral in the user bitmap (still true for supply/deposit — v3.6 only removed auto-enabling on transfers and liquidations). Emits ReserveUsedAsCollateralEnabled + Supply.",
  },
];

export function SupplyFlow() {
  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        <span className="grad">Supply</span>: 10 WETH enters the pool
      </h2>
      <p className="slide-subtitle">
        Every state-changing action follows the same skeleton:{" "}
        <em>update state → validate → reprice → move tokens</em>. Step through
        what happens inside one <code>supply()</code> call.
      </p>

      <StepFlow actors={ACTORS} steps={STEPS} />

      <div className="cols c3" style={{ marginTop: 16 }}>
        <div className="card">
          <h3>withdraw() is the mirror image</h3>
          <p>
            Burn scaled aTokens (<strong>rounded up</strong>, v3.5), send
            underlying back, inflow becomes outflow. If the asset was
            collateral, a health-factor check guards the withdrawal.
          </p>
        </div>
        <div className="card">
          <h3>Collateral flag hygiene</h3>
          <p>
            Since v3.5 the flag is reliably cleared when a withdrawal or
            aToken-repay empties the balance — closing edge cases where "ghost
            collateral" flags lingered.
          </p>
        </div>
        <div className="card">
          <h3>LTV0 ordering rule</h3>
          <p>
            If any of the user's enabled collateral has <strong>LTV = 0</strong>
            , that collateral must be withdrawn first — withdrawing healthy
            collateral around it reverts (<code>validateHFAndLtvzero</code>).
            v3.7's isolated eModes reuse exactly this rule.
          </p>
        </div>
      </div>
    </div>
  );
}
