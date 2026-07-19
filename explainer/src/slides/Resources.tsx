export function Resources() {
  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        Now <span className="grad">read the code</span>
      </h2>
      <p className="slide-subtitle">
        Everything in this deck maps directly onto <code>aave-v3-origin</code>.
        A suggested reading order, and where each concept lives.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>Suggested code-reading path</h3>
          <ul className="tight">
            <li>
              <strong>1.</strong>{" "}
              <code>src/contracts/protocol/libraries/types/DataTypes.sol</code>{" "}
              — every struct: ReserveData, EModeCategory, user config bitmaps.
            </li>
            <li>
              <strong>2.</strong> <code>protocol/pool/Pool.sol</code> +{" "}
              <code>PoolStorage.sol</code> — the router and its storage.
            </li>
            <li>
              <strong>3.</strong> <code>libraries/logic/SupplyLogic.sol</code> →{" "}
              <code>BorrowLogic.sol</code> — the happy paths, with{" "}
              <code>ReserveLogic</code> (indexes) and{" "}
              <code>ValidationLogic</code> alongside.
            </li>
            <li>
              <strong>4.</strong> <code>libraries/logic/GenericLogic.sol</code>{" "}
              — calculateUserAccountData, the health factor engine.
            </li>
            <li>
              <strong>5.</strong>{" "}
              <code>libraries/logic/LiquidationLogic.sol</code> — close factors,
              dust rules, bad-debt cleanup, v3.7 rounding.
            </li>
            <li>
              <strong>6.</strong> <code>protocol/tokenization/</code> +{" "}
              <code>libraries/math/TokenMath.sol</code> — scaled balances and
              rounding directions.
            </li>
            <li>
              <strong>7.</strong>{" "}
              <code>misc/DefaultReserveInterestRateStrategyV2.sol</code> — the
              rate curve you played with earlier.
            </li>
          </ul>
        </div>

        <div>
          <div className="card">
            <h3>In this repository</h3>
            <ul className="tight">
              <li>
                <code>docs/3.1 … 3.7</code> — per-release feature docs (this
                deck's primary source)
              </li>
              <li>
                <code>docs/Aave_V3_Technical_Paper.pdf</code> — the original
                whitepaper
              </li>
              <li>
                <code>src/contracts/instances/</code> — the exact deployed
                implementation contracts (PoolInstance rev 11)
              </li>
              <li>
                <code>tests/</code> — Foundry suites (<code>make test</code>),
                invariant harnesses for Echidna/Medusa
              </li>
              <li>
                <code>audits/</code> — every audit v3.0 → v3.7 ·{" "}
                <code>certora/</code> — formal verification specs
              </li>
            </ul>
          </div>
          <div className="card link-grid" style={{ marginTop: 14 }}>
            <h3>External</h3>
            <ul className="tight">
              <li>
                <a
                  href="https://github.com/aave-dao/aave-v3-origin"
                  target="_blank"
                  rel="noreferrer"
                >
                  github.com/aave-dao/aave-v3-origin
                </a>{" "}
                — this codebase
              </li>
              <li>
                <a
                  href="https://aave.com/docs"
                  target="_blank"
                  rel="noreferrer"
                >
                  aave.com/docs
                </a>{" "}
                — developer documentation
              </li>
              <li>
                <a
                  href="https://governance.aave.com"
                  target="_blank"
                  rel="noreferrer"
                >
                  governance.aave.com
                </a>{" "}
                — ARFCs &amp; AIPs (v3.7: "[ARFC] BGD. Aave v3.7")
              </li>
              <li>
                <a
                  href="https://github.com/bgd-labs/aave-address-book"
                  target="_blank"
                  rel="noreferrer"
                >
                  bgd-labs/aave-address-book
                </a>{" "}
                — deployed addresses per network
              </li>
            </ul>
          </div>
          <div className="note" style={{ marginTop: 14 }}>
            <strong>The 20-second recap:</strong> scaled balances × growing
            indexes; a kinked rate curve prices liquidity; LTV opens positions,
            LT + health factor close them; liquidators and the deficit machinery
            keep the pool solvent; eModes concentrate leverage safely — and v3.7
            made all of it smaller, stricter and easier to reason about.
          </div>
          <div className="note pink" style={{ marginTop: 10 }}>
            Keep going: the{" "}
            <a href="#/glossary" style={{ color: "var(--aave-teal)" }}>
              glossary
            </a>{" "}
            and the searchable{" "}
            <a href="#/errors" style={{ color: "var(--aave-teal)" }}>
              error catalog
            </a>{" "}
            in the Reference section are built for day-to-day integration work.
          </div>
        </div>
      </div>
    </div>
  );
}
