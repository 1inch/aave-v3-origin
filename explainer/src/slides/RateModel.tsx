import { useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { SrcRef } from "../components/SrcRef";
import {
  borrowRate as calcBorrowRate,
  supplyRate as calcSupplyRate,
} from "../lib/interestRate";

const CW = 640;
const CH = 300;
const PAD = { l: 52, r: 16, t: 14, b: 32 };

export function RateModel() {
  const [uopt, setUopt] = useState(90);
  const [base, setBase] = useState(0);
  const [slope1, setSlope1] = useState(6);
  const [slope2, setSlope2] = useState(75);
  const [rf, setRf] = useState(15);
  const [u, setU] = useState(72);

  // Mirrors DefaultReserveInterestRateStrategyV2.calculateInterestRates
  // (float model shared with the vitest suite: src/lib/interestRate.ts)
  const params = { optimalUsageRatio: uopt, baseRate: base, slope1, slope2 };
  const borrowRate = (util: number) => calcBorrowRate(util, params);
  const supplyRate = (util: number) => calcSupplyRate(util, params, rf);

  const maxY = Math.max(borrowRate(100), 1) * 1.08;
  const x = (util: number) => PAD.l + (util / 100) * (CW - PAD.l - PAD.r);
  const y = (rate: number) => CH - PAD.b - (rate / maxY) * (CH - PAD.t - PAD.b);

  const path = (fn: (util: number) => number) => {
    const pts: string[] = [];
    for (let i = 0; i <= 200; i++) {
      const util = i / 2;
      pts.push(`${x(util).toFixed(1)},${y(fn(util)).toFixed(1)}`);
    }
    return pts.join(" ");
  };

  const curBorrow = borrowRate(u);
  const curSupply = supplyRate(u);

  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        Rates come from a <span className="grad">kinked utilization curve</span>
      </h2>
      <p className="slide-subtitle">
        <code>utilization = totalDebt / (virtualBalance + totalDebt)</code>.
        Below the <strong>optimal usage ratio</strong> the borrow rate climbs
        gently (slope 1); above it, a steep slope 2 kicks in to defend the
        pool's exit liquidity. Suppliers receive the borrow rate times
        utilization, minus the reserve factor. One stateful strategy contract
        prices every reserve — drag the sliders to explore it.
      </p>

      <div
        className="cols"
        style={{ gridTemplateColumns: "minmax(0, 3fr) minmax(280px, 2fr)" }}
      >
        <div className="diagram-wrap">
          <svg
            viewBox={`0 0 ${CW} ${CH}`}
            role="img"
            aria-label="interest rate curve"
          >
            {[0, 0.25, 0.5, 0.75, 1].map((f) => {
              const v = f * maxY;
              return (
                <g key={f}>
                  <line
                    x1={PAD.l}
                    y1={y(v)}
                    x2={CW - PAD.r}
                    y2={y(v)}
                    stroke="rgba(255,255,255,0.07)"
                  />
                  <text
                    x={PAD.l - 7}
                    y={y(v) + 3.5}
                    textAnchor="end"
                    fontSize="10"
                    fill="#66719a"
                    fontFamily="var(--mono)"
                  >
                    {v.toFixed(0)}%
                  </text>
                </g>
              );
            })}
            {[0, 20, 40, 60, 80, 100].map((util) => (
              <text
                key={util}
                x={x(util)}
                y={CH - 12}
                textAnchor="middle"
                fontSize="10"
                fill="#66719a"
                fontFamily="var(--mono)"
              >
                {util}%
              </text>
            ))}
            <text
              x={CW / 2}
              y={CH - 1}
              textAnchor="middle"
              fontSize="9.5"
              fill="#66719a"
            >
              UTILIZATION
            </text>

            {/* optimal marker */}
            <line
              x1={x(uopt)}
              y1={PAD.t}
              x2={x(uopt)}
              y2={CH - PAD.b}
              stroke="#8a63c8"
              strokeDasharray="4 4"
              strokeWidth="1.4"
            />
            <text
              x={x(uopt)}
              y={PAD.t + 10}
              textAnchor="middle"
              fontSize="10"
              fill="#b39ddb"
              fontFamily="var(--mono)"
            >
              optimal {uopt}%
            </text>

            <polyline
              points={path(borrowRate)}
              fill="none"
              stroke="#e08fcb"
              strokeWidth="2.6"
            />
            <polyline
              points={path(supplyRate)}
              fill="none"
              stroke="#2ebac6"
              strokeWidth="2.6"
            />

            {/* current utilization */}
            <line
              x1={x(u)}
              y1={PAD.t}
              x2={x(u)}
              y2={CH - PAD.b}
              stroke="rgba(255,255,255,0.35)"
              strokeWidth="1"
            />
            <circle
              cx={x(u)}
              cy={y(curBorrow)}
              r="5"
              fill="#e08fcb"
              stroke="#0b1020"
              strokeWidth="1.5"
            />
            <circle
              cx={x(u)}
              cy={y(curSupply)}
              r="5"
              fill="#2ebac6"
              stroke="#0b1020"
              strokeWidth="1.5"
            />

            <g fontFamily="var(--mono)" fontSize="11">
              <text x={x(2)} y={PAD.t + 12} fill="#e08fcb">
                ● borrow rate
              </text>
              <text x={x(2)} y={PAD.t + 28} fill="#2ebac6">
                ● supply rate
              </text>
            </g>
          </svg>
          <div className="control-panel" style={{ padding: "10px 8px 4px" }}>
            <Slider
              label="Current utilization"
              value={u}
              min={0}
              max={100}
              onChange={setU}
              format={(v) => `${v}%`}
            />
          </div>
        </div>

        <div>
          <div className="card">
            <h3>Rate parameters (per asset, set by governance)</h3>
            <div className="control-panel" style={{ marginTop: 8 }}>
              <Slider
                label="Optimal usage"
                value={uopt}
                min={45}
                max={99}
                onChange={setUopt}
                format={(v) => `${v}%`}
              />
              <Slider
                label="Base rate"
                value={base}
                min={0}
                max={10}
                step={0.25}
                onChange={setBase}
                format={(v) => `${v}%`}
              />
              <Slider
                label="Slope 1"
                value={slope1}
                min={0}
                max={20}
                step={0.5}
                onChange={setSlope1}
                format={(v) => `${v}%`}
              />
              <Slider
                label="Slope 2"
                value={slope2}
                min={0}
                max={300}
                step={5}
                onChange={setSlope2}
                format={(v) => `${v}%`}
              />
              <Slider
                label="Reserve factor"
                value={rf}
                min={0}
                max={50}
                step={1}
                onChange={setRf}
                format={(v) => `${v}%`}
              />
            </div>
            <div className="stat-grid">
              <Stat k="Borrow APR" v={`${curBorrow.toFixed(2)}%`} tone="warn" />
              <Stat k="Supply APR" v={`${curSupply.toFixed(2)}%`} tone="teal" />
              <Stat
                k="To treasury"
                v={`${((curBorrow * u * rf) / 100 / 100).toFixed(2)}%`}
              />
            </div>
          </div>
          <div className="formula">
            u ≤ u<sub>opt</sub>: <span className="fr">rate</span>{" "}
            <span className="fo">=</span> base <span className="fo">+</span>{" "}
            slope1 <span className="fo">·</span> u<span className="fo">/</span>u
            <sub>opt</sub>
          </div>
          <div className="formula">
            u &gt; u<sub>opt</sub>: <span className="fr">rate</span>{" "}
            <span className="fo">=</span> base <span className="fo">+</span>{" "}
            slope1 <span className="fo">+</span> slope2{" "}
            <span className="fo">·</span> (u−u<sub>opt</sub>)
            <span className="fo">/</span>(1−u<sub>opt</sub>)
          </div>
          <div className="note">
            Since v3.1 the strategy is <strong>stateful</strong>: params live in
            a mapping on one shared contract (updated via governance without
            redeploying). Since v3.4 its address is an{" "}
            <strong>immutable</strong> on the Pool. Rates are capped: base +
            slope1 + slope2 ≤ <code>MAX_BORROW_RATE</code> (1000%).
          </div>
          <SrcRef
            paths={[
              "src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol",
            ]}
          />
        </div>
      </div>
    </div>
  );
}
