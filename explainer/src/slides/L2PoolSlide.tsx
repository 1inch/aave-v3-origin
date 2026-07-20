import { useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { CodeBlock } from "../components/CodeBlock";
import { SrcRef } from "../components/SrcRef";
import {
  encodeSupplyArgs,
  toBytes32Hex,
  SUPPLY_HEX_SEGMENTS,
} from "../lib/calldata";

const ASSETS = [
  "WETH",
  "wstETH",
  "USDC",
  "USDT",
  "GHO",
  "LINK",
  "WBTC",
  "AAVE",
];

const SEG_COLORS: Record<string, string> = {
  unused: "#66719a",
  referralCode: "#f6c453",
  amount: "#2ebac6",
  assetId: "#e08fcb",
};

export function L2PoolSlide() {
  const [assetId, setAssetId] = useState(2);
  const [amount, setAmount] = useState(2500);
  const [referral, setReferral] = useState(0);

  const word = encodeSupplyArgs({
    assetId,
    amount: BigInt(amount) * 10n ** 6n, // USDC-style 6 decimals for readability
    referralCode: referral,
  });
  const hex = toBytes32Hex(word).slice(2);

  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        <span className="grad">L2Pool</span>: one word of calldata
      </h2>
      <p className="slide-subtitle">
        On rollups, calldata bytes are the dominant cost. <code>L2Pool</code>{" "}
        (used on Arbitrum, Optimism, Scroll…) overloads each action with a
        packed <code>bytes32</code> version: the asset becomes its 16-bit
        reserve id — possible precisely because the reserves list is stable (and
        append-only since v3.7).
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            Pack a supply() yourself{" "}
            <span className="pill teal">interactive</span>
          </h3>
          <div className="control-panel" style={{ marginTop: 8 }}>
            <Slider
              label="Asset (reserve id)"
              value={assetId}
              min={0}
              max={7}
              onChange={setAssetId}
              format={(v) => `${v} · ${ASSETS[v]}`}
            />
            <Slider
              label="Amount (USDC)"
              value={amount}
              min={0}
              max={100000}
              step={100}
              onChange={setAmount}
              format={(v) => v.toLocaleString("en-US")}
            />
            <Slider
              label="Referral code"
              value={referral}
              min={0}
              max={500}
              onChange={setReferral}
              format={(v) => String(v)}
            />
          </div>
          <div
            className="formula"
            style={{
              whiteSpace: "normal",
              wordBreak: "break-all",
              lineHeight: 1.8,
            }}
          >
            0x
            {SUPPLY_HEX_SEGMENTS.map((seg) => (
              <span
                key={seg.name}
                style={{ color: SEG_COLORS[seg.name] }}
                title={seg.name}
              >
                {hex.slice(seg.from, seg.to)}
              </span>
            ))}
          </div>
          <div className="pill-row" style={{ marginTop: 4 }}>
            <span className="pill" style={{ color: SEG_COLORS.unused }}>
              bits 160-255 unused / permit
            </span>
            <span className="pill warn">
              bits 144-159 referral = {referral}
            </span>
            <span className="pill teal">bits 16-143 amount (uint128)</span>
            <span className="pill pink">bits 0-15 assetId = {assetId}</span>
          </div>
          <div className="stat-grid">
            <Stat k="Standard supply() calldata" v="132 bytes" />
            <Stat k="L2Pool supply(bytes32)" v="36 bytes" tone="good" />
            <Stat k="Saved" v="~73%" tone="teal" />
          </div>
        </div>

        <div>
          <CodeBlock
            title="src/contracts/protocol/libraries/logic/CalldataLogic.sol"
            code={`function decodeSupplyParams(
  mapping(uint256 => address) storage reservesList,
  bytes32 args
) internal view returns (address, uint256, uint16) {
  uint16 assetId;
  uint256 amount;
  uint16 referralCode;

  assembly {
    assetId := and(args, 0xFFFF)
    amount := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    referralCode := and(shr(144, args), 0xFFFF)
  }
  return (reservesList[assetId], amount, referralCode);
}`}
          />
          <ul className="tight">
            <li>
              <strong>Same Pool underneath:</strong> each compact entry point
              decodes and calls the standard function with{" "}
              <code>_msgSender()</code> — no separate logic to audit.
            </li>
            <li>
              <strong>Sentinel for "max":</strong> a <code>uint128.max</code>{" "}
              amount decodes to <code>uint256.max</code>, so "withdraw
              everything" / "repay everything" still fit in the packed word.
            </li>
            <li>
              <strong>Two words when needed:</strong> permit variants append{" "}
              <code>deadline</code> and <code>v</code> into the unused high bits
              and pass <code>r</code>, <code>s</code> as separate arguments;{" "}
              <code>liquidationCall</code> packs both asset ids, the borrower
              and <code>debtToCover</code> into two words.
            </li>
          </ul>
        </div>
      </div>
      <SrcRef
        paths={[
          "src/contracts/protocol/pool/L2Pool.sol",
          "src/contracts/protocol/libraries/logic/CalldataLogic.sol",
        ]}
      />
    </div>
  );
}
