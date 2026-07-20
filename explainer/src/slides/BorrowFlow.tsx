import { StepFlow } from "../components/StepFlow";
import type { FlowActor, FlowStep } from "../components/StepFlow";

const ACTORS: FlowActor[] = [
  { id: "user", label: "User" },
  { id: "pool", label: "Pool", sub: "BorrowLogic" },
  { id: "validation", label: "ValidationLogic" },
  { id: "vtoken", label: "vUSDC", sub: "VariableDebtToken" },
  { id: "atoken", label: "aUSDC", sub: "AToken" },
  { id: "generic", label: "GenericLogic" },
];

const STEPS: FlowStep[] = [
  {
    from: "user",
    to: "pool",
    label: "borrow(USDC, 5000, 2, 0, user)",
    kind: "call",
    title: "User calls borrow()",
    desc: "interestRateMode must be 2 (variable) — stable was removed in v3.2. With credit delegation, a delegatee can borrow onBehalfOf the collateral owner after approveDelegation().",
  },
  {
    from: "pool",
    to: "pool",
    label: "updateState()",
    kind: "call",
    title: "Refresh indexes first",
    desc: "Same as supply: indexes and treasury accrual are brought up to the current block before anything is measured.",
  },
  {
    from: "pool",
    to: "validation",
    label: "validateBorrow()",
    kind: "check",
    title: "Reserve-level checks",
    desc: "Active, not paused, not frozen, borrowing enabled, borrow cap not exceeded, amount ≤ aToken total supply (v3.1 inflation defense), and the asset must be flagged borrowable in the user’s current eMode. v3.7 removed the sequencer-sentinel gate and all siloed-borrowing checks.",
  },
  {
    from: "pool",
    to: "vtoken",
    label: "mint(scaled = ⌈5000 / borrowIndex⌉)",
    kind: "mint",
    title: "Record the debt",
    desc: "Scaled debt is minted rounded up (v3.5) — the protocol never understates what you owe. The user config bitmap flags the asset as borrowed.",
  },
  {
    from: "pool",
    to: "generic",
    label: "validateHFAndLtv()",
    kind: "check",
    title: "Health check after the state change",
    desc: "calculateUserAccountData walks the user’s bitmap: collateral valued with floor rounding, debt with ceil (v3.5). Requires health factor ≥ 1 and total debt within the collateral’s aggregate LTV. Since v3.5 this runs after minting — one computation, no duplicate edge cases.",
  },
  {
    from: "pool",
    to: "pool",
    label: "updateInterestRates(−5000)",
    kind: "call",
    title: "Reprice with the outflow",
    desc: "Utilization jumps, so the borrow rate for every borrower of this reserve ticks up. virtualUnderlyingBalance decreases by the borrowed amount.",
  },
  {
    from: "atoken",
    to: "user",
    label: "transferUnderlyingTo(user, 5000)",
    kind: "transfer",
    title: "Funds leave the pool",
    desc: "The aToken pays out 5000 USDC to the borrower. Emits Borrow(reserve, user, onBehalfOf, amount, rate, referral).",
  },
];

export function BorrowFlow() {
  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        <span className="grad">Borrow</span>: overcollateralized credit
      </h2>
      <p className="slide-subtitle">
        Borrowing mints a debt token against your collateral. The protocol
        checks the reserve, mints the debt, then verifies your whole account is
        still healthy — in that order since v3.5.
      </p>

      <StepFlow actors={ACTORS} steps={STEPS} />

      <div className="cols c3" style={{ marginTop: 16 }}>
        <div className="card">
          <h3>repay()</h3>
          <p>
            Burns scaled debt <strong>rounded down</strong> (v3.5) after pulling
            the underlying. <code>type(uint256).max</code> repays everything.
            Repay emits <code>Repay</code> and lowers utilization → rates fall.
          </p>
        </div>
        <div className="card">
          <h3>repayWithATokens()</h3>
          <p>
            Burns your aTokens of the same asset to settle debt without an
            ERC-20 transfer. Since v3.5 it is only allowed if the account is{" "}
            <strong>healthy after</strong> the operation — no self-inflicted
            liquidations.
          </p>
        </div>
        <div className="card">
          <h3>Credit delegation</h3>
          <p>
            <code>approveDelegation(delegatee, amount)</code> on the debt token
            lets contracts or friends draw debt against your collateral — the
            base primitive for the ETH gateway and many integrations.
          </p>
        </div>
      </div>
    </div>
  );
}
