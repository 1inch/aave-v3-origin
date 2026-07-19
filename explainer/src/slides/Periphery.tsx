import { SrcRef } from "../components/SrcRef";
import { CodeBlock } from "../components/CodeBlock";

export function Periphery() {
  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        <span className="grad">Periphery</span> &amp; special reserves
      </h2>
      <p className="slide-subtitle">
        A small set of satellite contracts rounds out the developer surface: an
        ERC-4626 wrapper for composability, a native-ETH gateway, the incentives
        engine, the treasury path — and one reserve that breaks the "users
        supply liquidity" rule: GHO.
      </p>

      <div className="cols c2">
        <div>
          <div className="card tone-teal">
            <h3>Stata tokens — ERC-4626 over aTokens</h3>
            <p>
              <code>StataTokenV2</code> ("static aToken") wraps a rebasing
              aToken into a standard vault:{" "}
              <strong>share balances stay fixed</strong> while the exchange rate
              grows with the liquidity index — the interface most DeFi protocols
              integrate against.
            </p>
            <ul className="tight">
              <li>
                Deployed permissionlessly per asset via the{" "}
                <code>StataTokenFactory</code>
              </li>
              <li>
                Forwards liquidity-mining rewards to holders (rewards must be
                registered via refreshRewardTokens())
              </li>
              <li>
                Doubles as Umbrella's coverage asset: staked "waTokens"{" "}
                <em>are</em> stata tokens
              </li>
              <li>
                Upgradeable by governance; 4626 rounding always favors the vault
              </li>
            </ul>
          </div>
          <div className="card" style={{ marginTop: 14 }}>
            <h3>WrappedTokenGatewayV3 — native ETH in one call</h3>
            <p>
              The Pool only knows WETH. The gateway wraps/unwraps around it:{" "}
              <code>depositETH</code>, <code>withdrawETH</code> (pulls aWETH via
              approval), <code>borrowETH</code> (needs credit delegation on the
              WETH debt token) and <code>repayETH</code> — so wallets never
              handle WETH directly.
            </p>
          </div>
          <div className="card" style={{ marginTop: 14 }}>
            <h3>RewardsController — the incentives engine</h3>
            <p>
              Every scaled mint/burn/transfer calls{" "}
              <code>handleAction(user, totalSupply, userBalance)</code> on the
              rewards controller (an immutable on the tokens since v3.4).
              Multiple simultaneous reward tokens per asset, per-second emission
              rates, pluggable transfer strategies (pull-from-treasury, staked
              AAVE) and <code>claimRewards</code> / <code>claimAllRewards</code>{" "}
              for users.
            </p>
          </div>
        </div>

        <div>
          <div className="card tone-pink">
            <h3>GHO — the minted reserve (since v3.4)</h3>
            <p>
              GHO is Aave's native stablecoin: it is not supplied by users, it
              is <strong>minted into the pool</strong> by the{" "}
              <code>GHODirectMinter</code> facilitator and supplied as aGHO.
              Since the v3.4 alignment it behaves like every other reserve —
              same aToken/vToken implementations, virtual accounting,
              flash-loanable — with three configuration quirks:
            </p>
            <ul className="tight">
              <li>
                <strong>Supply cap 1</strong>: users cannot supply GHO (only the
                facilitator does)
              </li>
              <li>
                <strong>Reserve factor 100%</strong>: all borrow interest goes
                to the treasury
              </li>
              <li>
                <strong>Static rate</strong>: utilization does not move the
                borrow rate; governance sets it directly
              </li>
            </ul>
            <p>
              The pre-v3.4 custom aGHO/vGHO (discount model, repayment hooks) is
              fully retired — one less special case in every flow.
            </p>
          </div>
          <div className="card" style={{ marginTop: 14 }}>
            <h3>The treasury path</h3>
            <CodeBlock
              code={`borrow interest accrues
  └─ reserveFactor % → reserve.accruedToTreasury   (scaled, on updateState)
       └─ mintToTreasury() → aTokens minted to the Collector
            ├─ flash-loan premiums (100% since v3.4)
            ├─ liquidation protocol fees (ceil-rounded since v3.7)
            └─ DustBin: listing-time dust, segregated from income (v3.4)`}
            />
            <p style={{ fontSize: 13, color: "var(--text-dim)" }}>
              The Collector is a governance-controlled proxy; periodic
              "collector migration" payloads sweep accrued fees into DAO
              budgets.
            </p>
          </div>
        </div>
      </div>
      <SrcRef
        paths={[
          "src/contracts/extensions/stata-token/README.md",
          "src/contracts/helpers/WrappedTokenGatewayV3.sol",
          "src/contracts/rewards/RewardsController.sol",
          "src/contracts/treasury/Collector.sol",
        ]}
      />
    </div>
  );
}
