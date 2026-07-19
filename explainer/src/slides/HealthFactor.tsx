import { useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { HFGauge } from "../components/HFGauge";

export function HealthFactor() {
  const [collateral, setCollateral] = useState(10000);
  const [lt, setLt] = useState(83);
  const [ltv, setLtv] = useState(80);
  const [debt, setDebt] = useState(6000);

  const effLtv = Math.min(ltv, lt);
  const hf = debt === 0 ? Infinity : (collateral * (lt / 100)) / debt;
  const borrowCap = (collateral * effLtv) / 100;
  const headroom = Math.max(0, borrowCap - debt);
  const liqDrop =
    debt === 0
      ? 100
      : Math.max(0, (1 - debt / (collateral * (lt / 100))) * 100);

  const barW = 560;
  const scale = (v: number) =>
    (v / Math.max(collateral, debt * 1.15, 1)) * barW;

  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        The <span className="grad">health factor</span>: one number rules the
        account
      </h2>
      <p className="slide-subtitle">
        Two thresholds bound every position: <strong>LTV</strong> caps what you
        can <em>open</em>, the higher <strong>liquidation threshold</strong>{" "}
        decides when you can be <em>closed</em>. The gap between them is your
        safety buffer.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            Position simulator <span className="pill teal">interactive</span>
          </h3>
          <div className="control-panel" style={{ marginTop: 8 }}>
            <Slider
              label="Collateral value"
              value={collateral}
              min={1000}
              max={30000}
              step={250}
              onChange={setCollateral}
              format={(v) => `$${v.toLocaleString("en-US")}`}
            />
            <Slider
              label="Liquidation threshold"
              value={lt}
              min={50}
              max={95}
              onChange={setLt}
              format={(v) => `${v}%`}
            />
            <Slider
              label="LTV (max borrow)"
              value={ltv}
              min={30}
              max={95}
              onChange={setLtv}
              format={(v) => `${Math.min(v, lt)}%`}
            />
            <Slider
              label="Debt"
              value={debt}
              min={0}
              max={25000}
              step={250}
              onChange={setDebt}
              format={(v) => `$${v.toLocaleString("en-US")}`}
            />
          </div>

          <svg
            viewBox="0 0 620 96"
            style={{ width: "100%", marginTop: 12 }}
            role="img"
            aria-label="position bar"
          >
            <rect
              x="20"
              y="18"
              width={barW}
              height="20"
              rx="6"
              fill="rgba(63,214,154,0.16)"
              stroke="rgba(63,214,154,0.5)"
            />
            <text
              x="24"
              y="13"
              fontSize="10"
              fill="#3fd69a"
              fontFamily="var(--mono)"
            >
              collateral ${collateral.toLocaleString("en-US")}
            </text>
            {/* LTV + LT markers */}
            <line
              x1={20 + scale((collateral * effLtv) / 100)}
              y1="12"
              x2={20 + scale((collateral * effLtv) / 100)}
              y2="44"
              stroke="#f6c453"
              strokeWidth="2"
            />
            <text
              x={20 + scale((collateral * effLtv) / 100)}
              y="56"
              fontSize="9.5"
              fill="#f6c453"
              textAnchor="middle"
              fontFamily="var(--mono)"
            >
              LTV {effLtv}%
            </text>
            <line
              x1={20 + scale((collateral * lt) / 100)}
              y1="12"
              x2={20 + scale((collateral * lt) / 100)}
              y2="44"
              stroke="#f0647c"
              strokeWidth="2"
            />
            <text
              x={20 + scale((collateral * lt) / 100)}
              y="68"
              fontSize="9.5"
              fill="#f0647c"
              textAnchor="middle"
              fontFamily="var(--mono)"
            >
              LT {lt}%
            </text>
            <rect
              x="20"
              y="72"
              width={Math.min(scale(debt), barW)}
              height="14"
              rx="5"
              fill={hf < 1 ? "rgba(240,100,124,0.75)" : "rgba(110,168,254,0.6)"}
            />
            <text
              x="24"
              y="94"
              fontSize="10"
              fill={hf < 1 ? "#f0647c" : "#6ea8fe"}
              fontFamily="var(--mono)"
            >
              debt ${debt.toLocaleString("en-US")}
            </text>
          </svg>
        </div>

        <div>
          <div className="cols c2">
            <div
              className="card"
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <HFGauge hf={hf} />
            </div>
            <div>
              <div className="formula" style={{ whiteSpace: "normal" }}>
                <span className="fr">HF</span> <span className="fo">=</span>{" "}
                Σ(collateral<sub>i</sub> <span className="fo">·</span> LT
                <sub>i</sub>) <span className="fo">/</span> totalDebt
              </div>
              <div className="stat-grid" style={{ marginTop: 8 }}>
                <Stat
                  k="Borrow headroom"
                  v={`$${Math.round(headroom).toLocaleString("en-US")}`}
                  tone={headroom > 0 ? "teal" : "bad"}
                />
                <Stat
                  k="Price drop to HF=1"
                  v={hf < 1 ? "liquidatable" : `${liqDrop.toFixed(1)}%`}
                  tone={hf < 1 ? "bad" : liqDrop < 10 ? "warn" : "good"}
                />
              </div>
            </div>
          </div>
          <ul className="tight" style={{ marginTop: 12 }}>
            <li>
              <strong>Opening / increasing risk</strong> (borrow, withdraw):
              checked against aggregate <em>LTV</em> — and blocked entirely
              while any enabled collateral has LTV 0.
            </li>
            <li>
              <strong>Liquidation</strong>: triggered purely by{" "}
              <em>HF &lt; 1</em>, i.e. debt crossing the LT-weighted collateral
              value.
            </li>
            <li>
              <strong>eModes</strong> substitute higher LTV/LT for the assets
              inside the category — that's the whole trick behind 93%-LTV
              ETH-correlated loops.
            </li>
            <li>
              <strong>v3.5 pessimistic rounding</strong>: collateral value
              rounds <em>down</em>, debt value rounds <em>up</em> (any non-zero
              debt is ≥ 1 wei of base currency) — dust can never hide from the
              health factor.
            </li>
          </ul>
          <div className="src-ref">
            src/contracts/protocol/libraries/logic/GenericLogic.sol ·
            calculateUserAccountData()
          </div>
        </div>
      </div>
    </div>
  );
}
