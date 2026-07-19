import { StepFlow } from "../components/StepFlow";
import type { FlowActor, FlowStep } from "../components/StepFlow";

const ACTORS: FlowActor[] = [
  { id: "liq", label: "Liquidator" },
  { id: "pool", label: "Pool", sub: "LiquidationLogic" },
  { id: "validation", label: "ValidationLogic" },
  { id: "vtoken", label: "vUSDC", sub: "debt token" },
  { id: "atoken", label: "aWETH", sub: "collateral" },
  { id: "treasury", label: "Treasury" },
];

const STEPS: FlowStep[] = [
  {
    from: "liq",
    to: "pool",
    label: "liquidationCall(WETH, USDC, borrower, amt, false)",
    kind: "call",
    title: "Anyone can liquidate",
    desc: "Params: collateral asset to seize, debt asset to repay, the borrower, debtToCover, and whether to receive aTokens instead of underlying. Self-liquidation is forbidden since v3.4.",
  },
  {
    from: "pool",
    to: "pool",
    label: "updateState() ×2",
    kind: "call",
    title: "Refresh both reserves",
    desc: "Both the debt reserve and the collateral reserve get fresh indexes so every amount is measured at current values.",
  },
  {
    from: "pool",
    to: "validation",
    label: "HF < 1? grace period over?",
    kind: "check",
    title: "Eligibility",
    desc: "calculateUserAccountData must return HF < 1, both reserves active & not paused, collateral actually enabled by the borrower, and the post-unpause liquidation grace period (max 4h, v3.1) elapsed. v3.7 removed the sequencer-sentinel gate and its HF < 0.95 carve-out.",
  },
  {
    from: "pool",
    to: "pool",
    label: "close factor: 50% or 100%",
    kind: "check",
    title: "How much debt may be repaid",
    desc: "Default: up to 50% of the borrower’s total debt (position-wide since v3.3). Full 100% is allowed when HF ≤ 0.95, or when this reserve’s collateral or debt is worth less than $2,000 (MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD).",
  },
  {
    from: "pool",
    to: "pool",
    label: "collateral = debt·price·(1+bonus)",
    kind: "call",
    title: "Compute seized collateral",
    desc: "_calculateAvailableCollateralToLiquidate converts the repaid debt into collateral units and applies the liquidation bonus. Since v3.7 every rounding here is deterministic: floor for the seizure, ceil for the protocol fee — the liquidator absorbs the wei.",
  },
  {
    from: "pool",
    to: "validation",
    label: "MustNotLeaveDust",
    kind: "check",
    title: "No dust positions",
    desc: "v3.3 rule: after liquidation, debt and collateral on this reserve must each be zero or ≥ $1,000 (MIN_LEFTOVER_BASE). Prevents economically unliquidatable crumbs.",
  },
  {
    from: "pool",
    to: "vtoken",
    label: "burn(borrower, repaid)",
    kind: "burn",
    title: "Debt is settled",
    desc: "The liquidator transfers the debt asset in; the borrower’s scaled debt burns (floor, v3.5).",
  },
  {
    from: "pool",
    to: "atoken",
    label: "seize collateral + bonus",
    kind: "transfer",
    title: "Collateral changes hands",
    desc: "Underlying is sent out (or aTokens transferred if receiveAToken = true — no longer auto-enabled as the liquidator’s collateral since v3.6).",
  },
  {
    from: "pool",
    to: "treasury",
    label: "liquidationProtocolFee",
    kind: "transfer",
    title: "Protocol takes its cut",
    desc: "A configured percentage of the bonus goes to the treasury, rounded up since v3.7.",
  },
  {
    from: "pool",
    to: "vtoken",
    label: "if no collateral left: burn rest → deficit",
    kind: "event",
    title: "Bad-debt cleanup (v3.3)",
    desc: 'If the borrower ends with zero collateral but debt remaining, that debt is burned and booked as reserve deficit — stopping phantom interest accrual. v3.7 detects "zero collateral" via scaled-balance consumption, catching wei-level edge cases.',
  },
];

export function LiquidationFlow() {
  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        <span className="grad">Liquidation</span>: the protocol's immune system
      </h2>
      <p className="slide-subtitle">
        When a health factor dips below 1, any address can repay part of the
        debt and buy the borrower's collateral at a discount. Ten steps, three
        safety rules, and — since v3.7 — not a single wei of exploitable
        rounding.
      </p>

      <StepFlow actors={ACTORS} steps={STEPS} />

      <div className="pill-row" style={{ marginTop: 14 }}>
        <span className="pill teal">CLOSE_FACTOR_HF_THRESHOLD = 0.95</span>
        <span className="pill teal">
          MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD = $2,000
        </span>
        <span className="pill teal">MIN_LEFTOVER_BASE = $1,000</span>
        <span className="pill pink">
          DEFAULT_LIQUIDATION_CLOSE_FACTOR = 50%
        </span>
      </div>
      <div className="src-ref">
        src/contracts/protocol/libraries/logic/LiquidationLogic.sol
      </div>
    </div>
  );
}
