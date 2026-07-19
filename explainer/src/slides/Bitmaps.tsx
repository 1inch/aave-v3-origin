import { useState } from "react";
import { Toggle } from "../components/Controls";
import { SrcRef } from "../components/SrcRef";

type Field = {
  name: string;
  from: number;
  to: number;
  deprecated?: boolean;
  desc: string;
};

const CONFIG_FIELDS: Field[] = [
  {
    name: "LTV",
    from: 0,
    to: 15,
    desc: "Loan-to-value in bps (e.g. 8050 = 80.5%). Zeroed on freeze since v3.1 (previous value parked in _pendingLtv).",
  },
  {
    name: "Liquidation threshold",
    from: 16,
    to: 31,
    desc: "LT in bps. Drives the health factor.",
  },
  {
    name: "Liquidation bonus",
    from: 32,
    to: 47,
    desc: "Encoded as 100% + bonus: 10500 = 5% bonus for liquidators.",
  },
  {
    name: "Decimals",
    from: 48,
    to: 55,
    desc: "Cached ERC-20 decimals. Listings require ≥ 6 since v3.1.",
  },
  {
    name: "Active",
    from: 56,
    to: 56,
    desc: "Reserve is initialized and usable.",
  },
  {
    name: "Frozen",
    from: 57,
    to: 57,
    desc: "No new supplies or borrows; existing positions unaffected.",
  },
  {
    name: "Borrowing enabled",
    from: 58,
    to: 58,
    desc: "Whether the asset can be borrowed at all (outside eMode rules).",
  },
  {
    name: "Stable borrowing",
    from: 59,
    to: 59,
    deprecated: true,
    desc: "DEPRECATED v3.2 — stable rate removed protocol-wide.",
  },
  {
    name: "Paused",
    from: 60,
    to: 60,
    desc: "Everything blocked, including repay and liquidations.",
  },
  {
    name: "Borrowable in isolation",
    from: 61,
    to: 61,
    deprecated: true,
    desc: "DEPRECATED v3.7 — isolation mode removed.",
  },
  {
    name: "Siloed borrowing",
    from: 62,
    to: 62,
    deprecated: true,
    desc: "DEPRECATED v3.7 — siloed borrowing removed.",
  },
  {
    name: "Flashloan enabled",
    from: 63,
    to: 63,
    desc: "Per-reserve flash-loan switch.",
  },
  {
    name: "Reserve factor",
    from: 64,
    to: 79,
    desc: "Treasury share of borrow interest, in bps.",
  },
  {
    name: "Borrow cap",
    from: 80,
    to: 115,
    desc: "In whole tokens; 0 = no cap.",
  },
  {
    name: "Supply cap",
    from: 116,
    to: 151,
    desc: "In whole tokens; 0 = no cap. Checked in scaled terms since v3.5.",
  },
  {
    name: "Liquidation protocol fee",
    from: 152,
    to: 167,
    desc: "Treasury share of the liquidation bonus, in bps. Rounded up since v3.7.",
  },
  {
    name: "eMode category",
    from: 168,
    to: 175,
    deprecated: true,
    desc: "DEPRECATED v3.2 — liquid eModes replaced the 1:1 asset↔category link with bitmaps.",
  },
  {
    name: "Unbacked mint cap",
    from: 176,
    to: 211,
    deprecated: true,
    desc: "DEPRECATED v3.4 — portals/unbacked feature removed.",
  },
  {
    name: "Debt ceiling",
    from: 212,
    to: 251,
    deprecated: true,
    desc: "DEPRECATED v3.7 — isolation-mode debt ceilings removed; bits must stay untouched.",
  },
  {
    name: "Virtual accounting",
    from: 252,
    to: 252,
    deprecated: true,
    desc: "DEPRECATED v3.4 — virtual accounting is always on; flag kept for integrators that decode it.",
  },
  {
    name: "Unused",
    from: 253,
    to: 255,
    deprecated: true,
    desc: "Free bits for future features.",
  },
];

const COLORS = [
  "#2ebac6",
  "#3fd69a",
  "#f6c453",
  "#6ea8fe",
  "#e08fcb",
  "#b6509e",
  "#8a63c8",
];

function colorOf(i: number, dep?: boolean) {
  return dep ? "rgba(255,255,255,0.14)" : COLORS[i % COLORS.length];
}

function ConfigBitBar({
  sel,
  onSel,
}: {
  sel: number;
  onSel: (i: number) => void;
}) {
  const W = 940;
  const rowBits = 128;
  const bw = W / rowBits;
  return (
    <svg
      viewBox={`0 0 ${W} 96`}
      role="img"
      aria-label="ReserveConfigurationMap bit layout"
    >
      {CONFIG_FIELDS.map((f, i) => {
        const segs: { row: number; from: number; to: number }[] = [];
        for (let row = 0; row < 2; row++) {
          const lo = Math.max(f.from, row * rowBits);
          const hi = Math.min(f.to, row * rowBits + rowBits - 1);
          if (lo <= hi)
            segs.push({
              row,
              from: lo - row * rowBits,
              to: hi - row * rowBits,
            });
        }
        return segs.map((s) => (
          <rect
            key={`${i}-${s.row}`}
            className="bitbar-seg"
            x={s.from * bw}
            y={s.row * 50}
            width={(s.to - s.from + 1) * bw - 1}
            height={26}
            rx={3}
            fill={colorOf(i, f.deprecated)}
            stroke={sel === i ? "#fff" : "transparent"}
            strokeWidth={1.6}
            opacity={f.deprecated ? 0.6 : 0.9}
            onClick={() => onSel(i)}
          />
        ));
      })}
      <text x={0} y={40} fontSize="9.5" fill="#66719a" fontFamily="var(--mono)">
        bit 0
      </text>
      <text
        x={W}
        y={40}
        fontSize="9.5"
        fill="#66719a"
        fontFamily="var(--mono)"
        textAnchor="end"
      >
        bit 127
      </text>
      <text x={0} y={90} fontSize="9.5" fill="#66719a" fontFamily="var(--mono)">
        bit 128
      </text>
      <text
        x={W}
        y={90}
        fontSize="9.5"
        fill="#66719a"
        fontFamily="var(--mono)"
        textAnchor="end"
      >
        bit 255
      </text>
    </svg>
  );
}

const USER_RESERVES = ["WETH", "wstETH", "USDC", "LINK"];

export function Bitmaps() {
  const [sel, setSel] = useState(0);
  const [borrowing, setBorrowing] = useState([false, false, true, false]);
  const [collateral, setCollateral] = useState([true, true, false, false]);
  const field = CONFIG_FIELDS[sel];

  const userBits = USER_RESERVES.flatMap((_, i) => [
    borrowing[i],
    collateral[i],
  ]);
  const userValue = userBits.reduce(
    (acc, b, i) => (b ? acc | (1n << BigInt(i)) : acc),
    0n
  );

  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        Everything is a <span className="grad">bitmap</span>
      </h2>
      <p className="slide-subtitle">
        Aave's hottest data fits in single storage slots. One 256-bit word
        configures a whole reserve; two bits per reserve describe a user's
        entire portfolio shape; and upgrades never migrate storage — retired
        fields are struck through and their slots reused.{" "}
        <strong>Click a segment</strong> to inspect it.
      </p>

      <div className="cols c2">
        <div>
          <div className="card">
            <h3>
              ReserveConfigurationMap — one word per reserve{" "}
              <span className="pill teal">interactive</span>
            </h3>
            <ConfigBitBar sel={sel} onSel={setSel} />
            <div
              className="arch-panel"
              style={{ marginTop: 10, minHeight: 86 }}
            >
              <div
                className="t"
                style={{
                  textDecoration: field.deprecated ? "line-through" : undefined,
                }}
              >
                {field.name}{" "}
                <span className="pill" style={{ marginLeft: 6 }}>
                  bit
                  {field.from === field.to
                    ? ` ${field.from}`
                    : `s ${field.from}–${field.to}`}
                </span>{" "}
                {field.deprecated && (
                  <span className="pill bad">deprecated</span>
                )}
              </div>
              <div className="d">{field.desc}</div>
            </div>
            <p className="note" style={{ marginTop: 10 }}>
              v3.3 flipped all masks to be <strong>read-optimized</strong> (
              <code>data &amp; LTV_MASK</code> instead of{" "}
              <code>data &amp; ~LTV_MASK</code>) — reads outnumber writes by
              orders of magnitude. Deprecated ranges are never reused, which is
              what keeps proxy upgrades storage-safe.
            </p>
          </div>
        </div>

        <div>
          <div className="card">
            <h3>
              UserConfigurationMap — 2 bits per reserve{" "}
              <span className="pill teal">interactive</span>
            </h3>
            <p>
              Bit <code>2·id</code>: borrowing · bit <code>2·id + 1</code>: used
              as collateral. Toggle a sample portfolio:
            </p>
            {USER_RESERVES.map((r, i) => (
              <div className="asset-row" key={r}>
                <span className="sym">{r}</span>
                <span className="pill">id {i}</span>
                <span className="spacer" />
                <Toggle
                  label="borrowing"
                  on={borrowing[i]}
                  onChange={(v) =>
                    setBorrowing((b) => b.map((x, j) => (j === i ? v : x)))
                  }
                  pink
                />
                <Toggle
                  label="collateral"
                  on={collateral[i]}
                  onChange={(v) =>
                    setCollateral((c) => c.map((x, j) => (j === i ? v : x)))
                  }
                />
              </div>
            ))}
            <div className="bitmap-row" style={{ marginTop: 8 }}>
              <span className="bitmap-label">bits (id 3 … id 0)</span>
              {[...userBits].reverse().map((b, i) => {
                const isCollateralBit = i % 2 === 0;
                return (
                  <span
                    key={i}
                    className={`bit ${b ? "on" : ""} ${
                      b && !isCollateralBit ? "pink" : ""
                    }`}
                  >
                    {b ? 1 : 0}
                  </span>
                );
              })}
              <span className="pill teal" style={{ marginLeft: 8 }}>
                data = 0x{userValue.toString(16)}
              </span>
            </div>
            <p
              style={{ fontSize: 12.5, color: "var(--text-dim)", marginTop: 8 }}
            >
              <code>BORROWING_MASK = 0x5555…</code> (odd pattern) and{" "}
              <code>COLLATERAL_MASK = 0xAAAA…</code> answer "is the user
              borrowing / collateralizing <em>anything</em>?" in one AND — and{" "}
              <code>calculateUserAccountData</code> only visits reserves whose
              pair is non-zero.
            </p>
          </div>

          <div className="card" style={{ marginTop: 14 }}>
            <h3>ReserveData: slots are recycled, never shifted</h3>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Slot content today</th>
                  <th>What lived there before</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <code>deficit</code> (v3.3 bad debt)
                  </td>
                  <td>currentStableBorrowRate (retired v3.2)</td>
                </tr>
                <tr>
                  <td>
                    <code>virtualUnderlyingBalance</code>
                  </td>
                  <td>
                    unbacked (retired v3.4; the old virtual-balance slot is now
                    padding)
                  </td>
                </tr>
                <tr>
                  <td>
                    <code>__deprecatedIsolationModeTotalDebt</code>
                  </td>
                  <td>
                    isolationModeTotalDebt (retired v3.7; getter returns 0)
                  </td>
                </tr>
                <tr>
                  <td>
                    <code>bool isolated</code> in EModeCategory
                  </td>
                  <td>
                    10 free padding bytes of slot 0 (v3.7 — zero-init = false
                    for existing categories)
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      <SrcRef
        paths={[
          "src/contracts/protocol/libraries/types/DataTypes.sol",
          "src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol",
          "src/contracts/protocol/libraries/configuration/UserConfiguration.sol",
        ]}
      />
    </div>
  );
}
