import { useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { SrcRef } from "../components/SrcRef";
import { Term } from "../components/Term";
import { simulateLiquidation } from "../lib/liquidation";

const fmt = (v: number) => `$${Math.round(v).toLocaleString("en-US")}`;

export function LiquidationMath() {
  const [collateral, setCollateral] = useState(5200);
  const [debt, setDebt] = useState(5000);
  const [lt, setLt] = useState(83);
  const [bonus, setBonus] = useState(5);
  const [feePct, setFeePct] = useState(10);
  const [cover, setCover] = useState(2500);

  // Shared with the vitest suite: src/lib/liquidation.ts
  const r = simulateLiquidation({
    collateral,
    debt,
    ltPct: lt,
    bonusPct: bonus,
    protocolFeePct: feePct,
    debtToCover: cover,
  });
  const hf = r.healthFactor;
  const liquidatable = r.liquidatable;
  const fullCloseFactor = r.fullCloseFactor;
  const maxLiquidatable = r.maxLiquidatableDebt;
  const actualDebt = r.actualDebtLiquidated;
  const seized = r.collateralSeized;
  const fee = r.protocolFee;
  const toLiquidator = r.toLiquidator;
  const leftoverDebt = r.leftoverDebt;
  const leftoverColl = r.leftoverCollateral;
  const dustViolation = r.dustViolation;
  const badDebt = r.createsBadDebt;
  const profit = r.liquidatorProfit;

  const barMax = Math.max(collateral, debt);
  const w = (v: number) => `${Math.max(0, (v / barMax) * 100)}%`;

  return (
    <div>
      <span className="slide-kicker">Core flows</span>
      <h2 className="slide-title">
        Liquidation <span className="grad">math, live</span>
      </h2>
      <p className="slide-subtitle">
        A single-reserve position, priced in USD like the contract prices
        everything in <Term t="base currency">base currency</Term>. Push the
        position underwater and watch the{" "}
        <Term t="close factor">close factor</Term>, bonus split and dust rules
        react. <em>Model simplifications:</em> one collateral + one debt
        reserve, prices fixed at 1, float math instead of ray/wad, no eMode
        LT/bonus override.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            The position <span className="pill teal">interactive</span>
          </h3>
          <div className="control-panel" style={{ marginTop: 8 }}>
            <Slider
              label="Collateral (WETH)"
              value={collateral}
              min={400}
              max={8000}
              step={50}
              onChange={setCollateral}
              format={fmt}
            />
            <Slider
              label="Debt (USDC)"
              value={debt}
              min={400}
              max={8000}
              step={50}
              onChange={setDebt}
              format={fmt}
            />
            <Slider
              label="Liquidation threshold"
              value={lt}
              min={60}
              max={95}
              onChange={setLt}
              format={(v) => `${v}%`}
            />
            <Slider
              label="Liquidation bonus"
              value={bonus}
              min={1}
              max={15}
              step={0.5}
              onChange={setBonus}
              format={(v) => `${v}%`}
            />
            <Slider
              label="Protocol fee (of bonus)"
              value={feePct}
              min={0}
              max={30}
              step={1}
              onChange={setFeePct}
              format={(v) => `${v}%`}
            />
            <Slider
              label="debtToCover"
              value={cover}
              min={0}
              max={8000}
              step={50}
              onChange={setCover}
              format={fmt}
            />
          </div>
          <div className="stat-grid">
            <Stat
              k="Health factor"
              v={hf.toFixed(3)}
              tone={hf < 1 ? "bad" : "good"}
            />
            <Stat
              k="Close factor"
              v={liquidatable ? (fullCloseFactor ? "100%" : "50%") : "—"}
              tone={fullCloseFactor ? "warn" : "teal"}
            />
            <Stat
              k="Max repayable"
              v={liquidatable ? fmt(maxLiquidatable) : "—"}
            />
          </div>
          {!liquidatable && (
            <p className="note warn" style={{ marginTop: 10 }}>
              HF ≥ 1 — <code>validateLiquidationCall</code> reverts with{" "}
              <code>HealthFactorNotBelowThreshold</code>. Raise the debt or
              lower the threshold.
            </p>
          )}
          {liquidatable && (
            <p className="note" style={{ marginTop: 10 }}>
              {fullCloseFactor
                ? hf <= 0.95
                  ? "HF ≤ 0.95 → the full position may be liquidated in one call."
                  : "Collateral or debt below $2,000 → small positions may always be fully closed (v3.3 anti-dust)."
                : "Healthy-ish HF and both sides ≥ $2,000 → at most 50% of the borrower’s total debt per call."}
            </p>
          )}
        </div>

        <div>
          <div className="card">
            <h3>Result of this liquidationCall</h3>
            {liquidatable ? (
              dustViolation ? (
                <p className="note warn" style={{ margin: "8px 0" }}>
                  <strong>Reverts: MustNotLeaveDust().</strong> Leftover debt{" "}
                  {fmt(leftoverDebt)} / collateral {fmt(leftoverColl)} —
                  anything strictly between $0 and $1,000 (MIN_LEFTOVER_BASE) on
                  either side is forbidden. Cover more debt, or less.
                </p>
              ) : (
                <>
                  <div
                    style={{
                      margin: "10px 0 4px",
                      fontSize: 12,
                      color: "var(--text-dim)",
                    }}
                  >
                    debt ({fmt(debt)}): repaid vs remaining
                  </div>
                  <div
                    style={{
                      display: "flex",
                      height: 18,
                      borderRadius: 6,
                      overflow: "hidden",
                      border: "1px solid var(--border-strong)",
                    }}
                  >
                    <div
                      style={{
                        width: w(actualDebt),
                        background: "rgba(110,168,254,0.75)",
                      }}
                      title="repaid"
                    />
                    <div
                      style={{
                        width: w(leftoverDebt),
                        background: "rgba(110,168,254,0.18)",
                      }}
                      title="remaining"
                    />
                  </div>
                  <div
                    style={{
                      margin: "12px 0 4px",
                      fontSize: 12,
                      color: "var(--text-dim)",
                    }}
                  >
                    collateral ({fmt(collateral)}): liquidator + fee vs
                    remaining
                  </div>
                  <div
                    style={{
                      display: "flex",
                      height: 18,
                      borderRadius: 6,
                      overflow: "hidden",
                      border: "1px solid var(--border-strong)",
                    }}
                  >
                    <div
                      style={{
                        width: w(toLiquidator),
                        background: "rgba(63,214,154,0.8)",
                      }}
                      title="to liquidator"
                    />
                    <div
                      style={{
                        width: w(fee),
                        background: "rgba(246,196,83,0.85)",
                      }}
                      title="protocol fee"
                    />
                    <div
                      style={{
                        width: w(leftoverColl),
                        background: "rgba(63,214,154,0.15)",
                      }}
                      title="remaining"
                    />
                  </div>
                  <div className="stat-grid">
                    <Stat k="Debt repaid" v={fmt(actualDebt)} tone="teal" />
                    <Stat k="Collateral seized" v={fmt(seized)} />
                    <Stat k="Liquidator profit" v={fmt(profit)} tone="good" />
                    <Stat
                      k="Protocol fee"
                      v={`$${fee.toFixed(2)}`}
                      tone="warn"
                    />
                  </div>
                  {badDebt && (
                    <p className="note pink" style={{ marginTop: 10 }}>
                      Collateral fully consumed with {fmt(leftoverDebt)} debt
                      remaining → the remainder is burned and booked as{" "}
                      <strong>reserve deficit</strong> (bad-debt cleanup, next
                      slide).
                    </p>
                  )}
                </>
              )
            ) : (
              <p>No liquidation possible while HF ≥ 1.</p>
            )}
          </div>

          <div className="card" style={{ marginTop: 14 }}>
            <h3>
              v3.7: deterministic rounding{" "}
              <span className="pill pink">new</span>
            </h3>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Computation</th>
                  <th>v3.6</th>
                  <th>v3.7</th>
                  <th>Favors</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <code>maxCollateralToLiquidate</code>
                  </td>
                  <td>half-up</td>
                  <td>
                    <strong>floor</strong>
                  </td>
                  <td>borrower (better post-liquidation HF)</td>
                </tr>
                <tr>
                  <td>
                    base portion for <code>bonusCollateral</code>
                  </td>
                  <td>half-up</td>
                  <td>
                    <strong>floor</strong>
                  </td>
                  <td>protocol fee</td>
                </tr>
                <tr>
                  <td>
                    <code>liquidationProtocolFee</code>
                  </td>
                  <td>half-up</td>
                  <td>
                    <strong>ceil</strong>
                  </td>
                  <td>protocol fee</td>
                </tr>
              </tbody>
            </table>
            <p>
              Half-up rounding let sophisticated liquidators pick{" "}
              <code>debtToCover</code> values that systematically landed every
              wei in their favor. v3.7 makes each direction explicit — the
              liquidator always absorbs the rounding loss.
            </p>
          </div>
          <SrcRef
            paths={[
              "src/contracts/protocol/libraries/logic/LiquidationLogic.sol",
              "docs/3.7/liquidation-rounding.md",
            ]}
          />
        </div>
      </div>
    </div>
  );
}
