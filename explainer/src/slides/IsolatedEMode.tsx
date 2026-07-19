import { useState } from "react";
import { Toggle, Stat } from "../components/Controls";
import { CodeBlock } from "../components/CodeBlock";

type Asset = {
  sym: string;
  value: number;
  inBitmap: boolean;
  baseLtv: number;
  emodeLtv: number;
};

const ASSETS: Asset[] = [
  { sym: "WETH", value: 10000, inBitmap: true, baseLtv: 80.5, emodeLtv: 93 },
  { sym: "wstETH", value: 4000, inBitmap: true, baseLtv: 78.5, emodeLtv: 93 },
  { sym: "LINK", value: 5000, inBitmap: false, baseLtv: 66, emodeLtv: 66 },
];

function effectiveLtv(
  a: Asset,
  inEMode: boolean,
  isolated: boolean
): { ltv: number; reason: string; branch: 1 | 2 | 3 } {
  if (inEMode && a.inBitmap) {
    return {
      ltv: a.emodeLtv,
      reason: `in collateralBitmap → eMode LTV ${a.emodeLtv}%`,
      branch: 1,
    };
  }
  if (inEMode && isolated && !a.inBitmap) {
    return { ltv: 0, reason: "outside bitmap + isolated → LTV 0", branch: 2 };
  }
  return { ltv: a.baseLtv, reason: `base LTV ${a.baseLtv}%`, branch: 3 };
}

export function IsolatedEMode() {
  const [isolated, setIsolated] = useState(true);
  const [inEMode, setInEMode] = useState(false);
  const [enabled, setEnabled] = useState<Record<string, boolean>>({
    WETH: true,
    wstETH: true,
    LINK: true,
  });
  const [feedback, setFeedback] = useState<string | null>(null);

  const entryBlocked =
    !inEMode && isolated && ASSETS.some((a) => enabled[a.sym] && !a.inBitmap);
  const blockingAsset = ASSETS.find((a) => enabled[a.sym] && !a.inBitmap)?.sym;

  const tryEnterEMode = () => {
    setFeedback(null);
    if (entryBlocked) {
      setFeedback(
        `setUserEMode(1) reverts: InvalidCollateralInEmode(${blockingAsset}, 1) — ${blockingAsset} is enabled as collateral but outside the eMode's collateralBitmap. Disable it first.`
      );
      return;
    }
    setInEMode(true);
  };

  const toggleCollateral = (a: Asset, next: boolean) => {
    setFeedback(null);
    if (next && inEMode && isolated && !a.inBitmap) {
      setFeedback(
        `setUserUseReserveAsCollateral(${a.sym}, true) does not enable — validateUseAsCollateral returns false because getUserReserveLtv(${a.sym}) == 0 inside the isolated eMode.`
      );
      return;
    }
    setEnabled((e) => ({ ...e, [a.sym]: next }));
  };

  const borrowPower = ASSETS.reduce((sum, a) => {
    if (!enabled[a.sym]) return sum;
    return sum + (a.value * effectiveLtv(a, inEMode, isolated).ltv) / 100;
  }, 0);

  return (
    <div>
      <span className="slide-kicker">eModes &amp; v3.7 · headline feature</span>
      <h2 className="slide-title">
        <span className="grad">Isolated eMode</span>: one flag closes the LTV
        loophole
      </h2>
      <p className="slide-subtitle">
        Before v3.7, a user in an "ETH-correlated" eMode could still borrow
        against <em>any other</em> collateral at its base LTV — defeating the
        category's risk isolation. Governance's workaround was hand-maintaining{" "}
        <code>ltvzeroBitmap</code> bits for every non-eMode asset on every
        listing. The new <code>bool isolated</code> automates it: outside-bitmap
        assets contribute <strong>zero LTV</strong>.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            Scenario sandbox <span className="pill pink">interactive</span>
          </h3>
          <div
            style={{
              display: "flex",
              gap: 18,
              flexWrap: "wrap",
              margin: "10px 0 14px",
            }}
          >
            <Toggle
              label="eMode 1 has isolated = true"
              on={isolated}
              onChange={(v) => {
                setIsolated(v);
                setFeedback(null);
              }}
              pink
            />
            {inEMode ? (
              <button
                className="icon-btn"
                onClick={() => {
                  setInEMode(false);
                  setFeedback(null);
                }}
              >
                ← Exit eMode 1
              </button>
            ) : (
              <button className="icon-btn primary" onClick={tryEnterEMode}>
                Enter eMode 1 (ETH correlated)
              </button>
            )}
          </div>

          {ASSETS.map((a) => {
            const eff = effectiveLtv(a, inEMode, isolated);
            const isOn = enabled[a.sym];
            return (
              <div className="asset-row" key={a.sym}>
                <span className="sym">{a.sym}</span>
                <span style={{ color: "var(--text-dim)" }}>
                  ${a.value.toLocaleString("en-US")}
                </span>
                <span className={`pill ${a.inBitmap ? "teal" : ""}`}>
                  {a.inBitmap ? "in bitmap" : "outside bitmap"}
                </span>
                <span className="spacer" />
                <span
                  className={`pill ${
                    !isOn
                      ? ""
                      : eff.ltv === 0
                      ? "bad"
                      : eff.ltv > a.baseLtv
                      ? "good"
                      : "warn"
                  }`}
                  title={eff.reason}
                >
                  {isOn ? `LTV ${eff.ltv}%` : "not collateral"}
                </span>
                <Toggle
                  label="collateral"
                  on={isOn}
                  onChange={(v) => toggleCollateral(a, v)}
                />
              </div>
            );
          })}

          <div className="stat-grid">
            <Stat
              k="Borrowing power"
              v={`$${Math.round(borrowPower).toLocaleString("en-US")}`}
              tone="teal"
            />
            <Stat k="User eMode" v={inEMode ? "1 (ETH corr.)" : "0 (none)"} />
            <Stat
              k="isolated flag"
              v={isolated ? "true" : "false"}
              tone={isolated ? "warn" : undefined}
            />
          </div>

          {feedback && (
            <p className="note warn" style={{ marginTop: 12 }}>
              {feedback}
            </p>
          )}
          {inEMode && isolated && enabled["LINK"] && (
            <p className="note pink" style={{ marginTop: 12 }}>
              Governance flipped <code>isolated</code> on a live eMode: LINK's
              LTV dropped to 0 <em>immediately</em>. The health factor is
              untouched (LT is unaffected), but no new borrows can lean on LINK
              — and LTV0 collateral must be withdrawn first. Exit the eMode to
              restore its base LTV.
            </p>
          )}
        </div>

        <div>
          <CodeBlock
            title="ValidationLogic.getUserReserveLtv() — the single-point change"
            code={`// 1. asset inside the eMode's collateralBitmap -> eMode LTV (or ltvzero)
if (categoryId != 0 && isReserveEnabledOnBitmap(collateralBitmap, id)) {
  return isReserveEnabledOnBitmap(ltvzeroBitmap, id)
    ? 0
    : eModeCategoryData.ltv;
}
// 2. NEW in v3.7: isolated eMode zeroes everything outside the bitmap
if (categoryId != 0 && eModeCategoryData.isolated) {
  return 0;
}
// 3. fallback: the asset's base LTV
return reserveData.configuration.getLtv();`}
          />
          <ul className="tight">
            <li>
              <strong>Single source of truth:</strong> because every LTV lookup
              funnels through this function, the flag automatically propagates
              to account data, borrow validation, withdrawals, collateral
              enabling and eMode entry.
            </li>
            <li>
              <strong>Entry blocked:</strong> you cannot enter an isolated eMode
              while non-bitmap collateral is enabled (
              <code>InvalidCollateralInEmode</code>).
            </li>
            <li>
              <strong>Enable blocked:</strong> inside one, enabling
              outside-bitmap collateral is a silent no-op.
            </li>
            <li>
              <strong>Storage-safe:</strong> <code>bool isolated</code> packs
              into a free byte of <code>EModeCategory</code> slot 0 — existing
              categories read <code>false</code>, no migration needed.
            </li>
            <li>
              <strong>Admin API:</strong>{" "}
              <code>setEModeCategory(..., isolated)</code> and a dedicated{" "}
              <code>setEModeCategoryIsolated(id, bool)</code> callable by risk,
              pool <em>or emergency</em> admins.
            </li>
          </ul>
          <div className="src-ref">
            docs/3.7/isolated-emode.md ·
            src/contracts/protocol/libraries/logic/ValidationLogic.sol
          </div>
        </div>
      </div>
    </div>
  );
}
