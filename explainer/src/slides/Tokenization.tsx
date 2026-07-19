import { useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { CodeBlock } from "../components/CodeBlock";
import { SrcRef } from "../components/SrcRef";
import { Term } from "../components/Term";

export function Tokenization() {
  const [index, setIndex] = useState(1.08);
  const scaledSupply = 100;
  const scaledDebt = 40;
  const balance = scaledSupply * index;
  const debt = scaledDebt * index;

  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        Positions are tokens:{" "}
        <span className="grad">aTokens &amp; debt tokens</span>
      </h2>
      <p className="slide-subtitle">
        Aave never stores your balance directly. It stores a{" "}
        <Term t="scaled balance">
          <strong>scaled balance</strong>
        </Term>{" "}
        — your share of the pool — and multiplies it by an ever-growing{" "}
        <Term t="index">
          <strong>index</strong>
        </Term>{" "}
        whenever anyone asks. That single trick makes interest accrue to every
        holder continuously, with zero per-user storage writes.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            Drag the index forward in time{" "}
            <span className="pill teal">interactive</span>
          </h3>
          <div className="control-panel" style={{ marginTop: 10 }}>
            <Slider
              label="Reserve index"
              value={index}
              min={1}
              max={1.5}
              step={0.005}
              onChange={setIndex}
              format={(v) => `${v.toFixed(3)} RAY`}
            />
          </div>
          <div className="stat-grid">
            <Stat k="scaledBalance (aWETH)" v={scaledSupply.toFixed(2)} />
            <Stat k="balanceOf → supplier" v={balance.toFixed(2)} tone="good" />
            <Stat k="scaledBalance (vDAI)" v={scaledDebt.toFixed(2)} />
            <Stat k="balanceOf → debt" v={debt.toFixed(2)} tone="bad" />
          </div>
          <div className="formula" style={{ marginTop: 14 }}>
            <span className="fv">balanceOf(user)</span>{" "}
            <span className="fo">=</span>{" "}
            <span className="fv">scaledBalance(user)</span>{" "}
            <span className="fo">×</span> <span className="fr">index(t)</span>
          </div>
          <p className="note">
            The scaled amounts never change while you hold — only the index
            moves. Supply 100 at index 1.00 and you hold{" "}
            <code>100 / 1.00 = 100</code> scaled units; at index{" "}
            {index.toFixed(3)} they are worth{" "}
            <strong>{balance.toFixed(2)}</strong>.
          </p>
        </div>

        <div>
          <div className="cols c2">
            <div className="card tone-good">
              <h3>aToken</h3>
              <ul className="tight">
                <li>
                  <strong>Transferable ERC-20</strong> receipt (aWETH, aUSDC…),
                  holds the underlying liquidity
                </li>
                <li>
                  Grows with the <strong>liquidityIndex</strong>
                </li>
                <li>
                  v3.5 rounding: mint <strong>floor</strong>, burn{" "}
                  <strong>ceil</strong>, balanceOf <strong>floor</strong> —
                  never in the user's favor
                </li>
                <li>EIP-2612 permit, renounceAllowance (v3.6)</li>
              </ul>
            </div>
            <div className="card tone-bad">
              <h3>VariableDebtToken</h3>
              <ul className="tight">
                <li>
                  <strong>Non-transferable</strong> — debt can't be sent away
                </li>
                <li>
                  Grows with the <strong>variableBorrowIndex</strong>
                </li>
                <li>
                  v3.5 rounding: mint <strong>ceil</strong>, burn{" "}
                  <strong>floor</strong>, balanceOf <strong>ceil</strong> — debt
                  is never understated
                </li>
                <li>
                  Credit delegation: approveDelegation() lets others borrow
                  against your collateral
                </li>
              </ul>
            </div>
          </div>
          <CodeBlock
            title="src/contracts/protocol/tokenization (concept)"
            code={`// v3.5+: callers pass both amount and scaledAmount — computed once
// via TokenMath, avoiding repeated lossy conversions.
function balanceOf(address user) public view returns (uint256) {
  // aToken: getATokenBalance -> rayMulFloor
  // vToken: getVTokenBalance -> rayMulCeil
  return TokenMath.getATokenBalance(
    super.balanceOf(user),                          // scaled
    POOL.getReserveNormalizedIncome(_underlyingAsset) // live index
  );
}`}
          />
          <SrcRef
            paths={[
              "src/contracts/protocol/tokenization/AToken.sol",
              "src/contracts/protocol/tokenization/VariableDebtToken.sol",
              "src/contracts/protocol/libraries/math/TokenMath.sol",
            ]}
          />
        </div>
      </div>
    </div>
  );
}
