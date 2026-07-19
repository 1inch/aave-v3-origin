import { CodeBlock } from "../components/CodeBlock";

export function BadDebt() {
  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        Bad debt becomes a <span className="grad">tracked deficit</span>
      </h2>
      <p className="slide-subtitle">
        A crash can leave an account with debt but no collateral — debt nobody
        will ever repay, silently accruing interest against suppliers. Since
        v3.3 the protocol recognizes that moment, burns the debt, and books it
        as an explicit per-reserve <code>deficit</code> that governance can
        cover.
      </p>

      <div className="cols c3">
        <div className="card tone-bad">
          <h3>1 · Detect</h3>
          <p>
            At the end of every <code>liquidationCall</code>: if the borrower
            has <strong>zero collateral left</strong> (across all reserves) but
            debt remaining, the position is bad debt.
          </p>
          <p>
            <strong>v3.7 refinement:</strong> "zero collateral" is now decided
            by <em>scaled-balance consumption</em> — using the same{" "}
            <code>rayDivCeil</code> rounding as the actual burn/transfer —
            instead of comparing base-currency values. A few wei of leftover
            that price to $0 can no longer strand un-burnable debt.
          </p>
        </div>
        <div className="card tone-warn">
          <h3>2 · Burn &amp; book</h3>
          <p>
            The remaining <code>vToken</code> balance is burned immediately and
            the amount is added to <code>reserve.deficit</code> (stored in the
            retired stable-borrow-rate slot). Interest stops compounding on debt
            that will never be repaid.
          </p>
          <p>
            Suppliers' aTokens are unaffected at this point — the loss is{" "}
            <em>socialized only in accounting</em>, made visible via{" "}
            <code>getReserveDeficit()</code>.
          </p>
        </div>
        <div className="card tone-good">
          <h3>3 · Eliminate</h3>
          <p>
            The <strong>Umbrella</strong> entity (registered on the
            PoolAddressesProvider — Aave's staking-based safety module) calls{" "}
            <code>eliminateReserveDeficit(asset, amount)</code>, burning its own
            aTokens to write the deficit down.
          </p>
          <p>
            Since v3.5 it returns the amount actually covered, capped at the
            outstanding deficit.
          </p>
        </div>
      </div>

      <div className="cols c2" style={{ marginTop: 16 }}>
        <CodeBlock
          title="src/contracts/protocol/libraries/logic/LiquidationLogic.sol (concept)"
          code={`// after seizing collateral & repaying debt:
bool hasNoCollateralLeft = vars.totalCollateralInBaseCurrency ==
  vars.collateralToLiquidateInBaseCurrency; // v3.7: via scaled consumption

if (hasNoCollateralLeft && borrowerConfig.isBorrowingAny()) {
  _burnBadDebt(reservesData, reservesList, borrowerConfig, borrower);
  // -> for every borrowed reserve: burn vTokens, add to reserve.deficit
}

// later, permissioned (only Umbrella):
function eliminateReserveDeficit(address asset, uint256 amount)
  external returns (uint256 coveredAmount);`}
        />
        <div>
          <div className="card">
            <h3>Why not just leave it?</h3>
            <ul className="tight">
              <li>
                <strong>Phantom interest:</strong> unrecoverable debt kept
                accruing, inflating the borrow index and overstating protocol
                income.
              </li>
              <li>
                <strong>Utilization distortion:</strong> dead debt propped up
                utilization and thus rates for everyone else. Since v3.3,{" "}
                <code>deficit + unbacked</code> is passed to the rate strategy
                instead.
              </li>
              <li>
                <strong>Clean risk signal:</strong> a queryable deficit gives
                the DAO an exact number to cover with safety-module funds —
                instead of an invisible hole.
              </li>
            </ul>
          </div>
          <div className="note pink" style={{ marginTop: 12 }}>
            The dust rules from the previous slide exist for this feature:
            liquidators must fully clear a position (or leave ≥ $1,000 on both
            sides) so the bad-debt check can actually fire — leaving $0.50 of
            collateral would otherwise dodge the cleanup.
          </div>
          <div className="src-ref">
            docs/3.3/Aave-v3.3-features.md · docs/3.7/liquidation-rounding.md
          </div>
        </div>
      </div>
    </div>
  );
}
