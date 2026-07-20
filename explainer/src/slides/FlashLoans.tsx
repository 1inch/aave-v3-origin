import { StepFlow } from "../components/StepFlow";
import type { FlowActor, FlowStep } from "../components/StepFlow";
import { SrcRef } from "../components/SrcRef";

const ACTORS: FlowActor[] = [
  { id: "receiver", label: "Receiver", sub: "IFlashLoanReceiver" },
  { id: "pool", label: "Pool", sub: "FlashLoanLogic" },
  { id: "atoken", label: "aUSDC" },
  { id: "treasury", label: "Treasury" },
];

const STEPS: FlowStep[] = [
  {
    from: "receiver",
    to: "pool",
    label: "flashLoanSimple(receiver, USDC, 1M, params)",
    kind: "call",
    title: "Request the loan",
    desc: "No collateral required — the entire loan lives and dies inside one transaction. flashLoan() additionally supports multiple assets and debt modes.",
  },
  {
    from: "atoken",
    to: "receiver",
    label: "transferUnderlyingTo(1M)",
    kind: "transfer",
    title: "Optimistic transfer",
    desc: "The Pool sends the full amount before any repayment guarantee — the EVM’s atomicity is the collateral.",
  },
  {
    from: "pool",
    to: "receiver",
    label: "executeOperation(...)",
    kind: "call",
    title: "Your code runs",
    desc: "The receiver contract does whatever it wants — arbitrage, collateral swaps, self-liquidation protection — and must end holding amount + premium, with the Pool approved to pull it.",
  },
  {
    from: "pool",
    to: "atoken",
    label: "pull 1M + premium",
    kind: "transfer",
    title: "Repayment enforced",
    desc: "safeTransferFrom pulls principal + fee back into the aToken. If the pull fails, the whole transaction reverts as if the loan never happened. Virtual balance is restored + premium.",
  },
  {
    from: "pool",
    to: "treasury",
    label: "premium → accruedToTreasury",
    kind: "mint",
    title: "Fee to the DAO",
    desc: "The premium (FLASHLOAN_PREMIUM_TOTAL) is governance-set per market via updateFlashloanPremium — 0.05% on current production markets. Since v3.4 it accrues 100% to the treasury (FLASHLOAN_PREMIUM_TO_PROTOCOL is hardcoded). Approved FLASH_BORROWER role addresses pay zero premium.",
  },
];

export function FlashLoans() {
  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        <span className="grad">Flash loans</span> &amp; the UX toolbox
      </h2>
      <p className="slide-subtitle">
        Uncollateralized loans that exist for exactly one transaction — the
        primitive behind liquidation bots, collateral swaps and debt migrations.
        Plus the quality-of-life features that landed on the way to v3.7.
      </p>

      <StepFlow actors={ACTORS} steps={STEPS} />

      <div className="cols c4" style={{ marginTop: 16 }}>
        <div className="card">
          <h3>Open as debt instead</h3>
          <p>
            <code>flashLoan()</code> with <code>interestRateMode = 2</code>{" "}
            skips repayment and converts the loan into a regular variable borrow
            against <code>onBehalfOf</code>'s collateral (requires credit
            delegation). Mode 0 = must repay.
          </p>
        </div>
        <div className="card">
          <h3>Multicall (v3.4)</h3>
          <p>
            The Pool implements OpenZeppelin <code>Multicall</code>: supply +
            enable eMode + borrow in one transaction. GHO can be flash-loaned
            like any asset since its v3.4 alignment.
          </p>
        </div>
        <div className="card">
          <h3>Position managers (v3.4)</h3>
          <p>
            <code>approvePositionManager(manager, true)</code> lets a contract
            call <code>setUserUseReserveAsCollateralOnBehalfOf</code> and{" "}
            <code>setUserEModeOnBehalfOf</code> — the explicit successor to
            "magic" auto-collateral behaviors removed in v3.6.
          </p>
        </div>
        <div className="card">
          <h3>Allowance hygiene (v3.5/3.6)</h3>
          <p>
            Exact allowance consumption on transfers (v3.5), plus{" "}
            <code>renounceAllowance</code> / <code>renounceDelegation</code>{" "}
            (v3.6) so integrations can burn leftover approvals of rebasing
            aTokens.
          </p>
        </div>
      </div>
      <SrcRef
        paths={[
          "src/contracts/protocol/libraries/logic/FlashLoanLogic.sol",
          "src/contracts/misc/flashloan",
        ]}
      />
    </div>
  );
}
