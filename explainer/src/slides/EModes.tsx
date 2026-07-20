import { useState } from "react";
import { BitRow } from "../components/Controls";
import { SrcRef } from "../components/SrcRef";
import { Term } from "../components/Term";

const RESERVES = [
  "WETH",
  "wstETH",
  "weETH",
  "USDC",
  "USDT",
  "GHO",
  "LINK",
  "WBTC",
];

type Category = {
  id: number;
  label: string;
  ltv: number;
  lt: number;
  bonus: number;
  collateral: boolean[];
  borrowable: boolean[];
  ltvzero: boolean[];
  blurb: string;
};

const CATEGORIES: Category[] = [
  {
    id: 1,
    label: "ETH correlated",
    ltv: 93,
    lt: 95,
    bonus: 1,
    collateral: [true, true, true, false, false, false, false, false],
    borrowable: [true, false, false, false, false, false, false, false],
    ltvzero: [false, false, true, false, false, false, false, false],
    blurb:
      "LST leverage: wstETH/weETH collateral borrows WETH at 93% LTV. weETH is flagged ltvzero here — it still counts for the health factor but cannot back new borrows in this category.",
  },
  {
    id: 2,
    label: "Stablecoins",
    ltv: 90,
    lt: 92.5,
    bonus: 1.5,
    collateral: [false, false, false, true, true, false, false, false],
    borrowable: [false, false, false, true, true, true, false, false],
    ltvzero: [false, false, false, false, false, false, false, false],
    blurb:
      "USDC/USDT collateral can borrow stables (incl. GHO) at 90% LTV — parameters that would be reckless cross-asset are safe between tightly correlated ones.",
  },
];

export function EModes() {
  const [cat, setCat] = useState(0);
  const c = CATEGORIES[cat];
  const baseLtv = 80.5;
  const baseLt = 83;

  return (
    <div>
      <span className="slide-kicker">eModes &amp; v3.7</span>
      <h2 className="slide-title">
        <span className="grad">Efficiency modes</span>: higher leverage for
        correlated assets
      </h2>
      <p className="slide-subtitle">
        An <Term t="eMode">eMode</Term> category is a named bundle of{" "}
        <strong>
          <Term t="LTV">LTV</Term> /{" "}
          <Term t="liquidation threshold">liquidation threshold</Term> /{" "}
          <Term t="liquidation bonus">bonus</Term>
        </strong>{" "}
        plus three 128-bit bitmaps over the reserves list. A user opts in with{" "}
        <code>setUserEMode(id)</code>; category 0 means "no eMode". Since v3.2's{" "}
        <em>liquid eModes</em>, any asset can belong to any number of
        categories.
      </p>

      <div className="cols c2">
        <div className="card">
          <div className="seg" style={{ marginBottom: 14 }}>
            {CATEGORIES.map((cc, i) => (
              <button
                key={cc.id}
                className={i === cat ? "active" : ""}
                onClick={() => setCat(i)}
              >
                eMode {cc.id} · {cc.label}
              </button>
            ))}
          </div>
          <div className="bitmap-row" style={{ marginBottom: 2 }}>
            <span className="bitmap-label">reserve id →</span>
            {RESERVES.map((r, i) => (
              <span
                key={r}
                className="bit"
                style={{ borderStyle: "dashed" }}
                title={`id ${i}`}
              >
                {r.slice(0, 2)}
              </span>
            ))}
          </div>
          <BitRow
            label="collateralBitmap"
            bits={c.collateral}
            names={RESERVES}
          />
          <BitRow
            label="borrowableBitmap"
            bits={c.borrowable}
            names={RESERVES}
            tone="pink"
          />
          <BitRow
            label="ltvzeroBitmap (v3.6)"
            bits={c.ltvzero}
            names={RESERVES}
            tone="warn"
          />
          <p style={{ fontSize: 13, color: "var(--text-dim)", marginTop: 10 }}>
            {c.blurb}
          </p>
          <SrcRef
            paths={[
              "src/contracts/protocol/libraries/types/DataTypes.sol",
              "src/contracts/protocol/libraries/configuration/EModeConfiguration.sol",
            ]}
            note="EModeCategory struct · isReserveEnabledOnBitmap()"
          />
        </div>

        <div>
          <div className="card">
            <h3>What the user gets in eMode {c.id}</h3>
            {[
              { name: "LTV", base: baseLtv, emode: c.ltv },
              { name: "Liq. threshold", base: baseLt, emode: c.lt },
            ].map((row) => (
              <div key={row.name} style={{ margin: "10px 0" }}>
                <div
                  style={{
                    fontSize: 12,
                    color: "var(--text-dim)",
                    marginBottom: 4,
                  }}
                >
                  {row.name}: base {row.base}% → eMode{" "}
                  <strong style={{ color: "var(--aave-teal)" }}>
                    {row.emode}%
                  </strong>
                </div>
                <div
                  style={{
                    position: "relative",
                    height: 16,
                    borderRadius: 6,
                    background: "rgba(255,255,255,0.07)",
                    overflow: "hidden",
                  }}
                >
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      width: `${row.emode}%`,
                      background: "rgba(46,186,198,0.45)",
                    }}
                  />
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      width: `${row.base}%`,
                      background: "rgba(182,80,158,0.65)",
                    }}
                  />
                </div>
              </div>
            ))}
            <div className="pill-row" style={{ margin: "12px 0 0" }}>
              <span className="pill pink">
                base bonus 5% → eMode {c.bonus}%
              </span>
              <span className="pill teal">applies only to bitmap assets</span>
            </div>
          </div>

          <div className="card" style={{ marginTop: 14 }}>
            <h3>The rules (v3.6 baseline)</h3>
            <ul className="tight">
              <li>
                Entering/switching requires: <strong>HF ≥ 1 after</strong> the
                switch and every borrowed asset{" "}
                <strong>borrowable in the new category</strong>.
              </li>
              <li>
                Collateral <em>outside</em> the bitmap still counts — at its{" "}
                <strong>base</strong> LTV/LT. (This is the loophole v3.7's{" "}
                <code>isolated</code> flag closes — next slide.)
              </li>
              <li>
                Since v3.6, eMode config is fully <strong>decoupled</strong>{" "}
                from the base reserve config: an asset can be collateral or
                borrowable <em>only</em> inside an eMode, and{" "}
                <code>ltvzeroBitmap</code> applies LTV0 rules per category.
              </li>
              <li>
                Liquidations of bitmap collateral use the eMode's LT and bonus.
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
