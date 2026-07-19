import { useEffect, useMemo, useRef, useState } from "react";
import { Slider, Stat } from "../components/Controls";
import { CodeBlock } from "../components/CodeBlock";

const T_MAX = 5; // years
const CW = 620;
const CH = 260;
const PAD = { l: 46, r: 14, t: 12, b: 28 };

export function Indexes() {
  const [apr, setApr] = useState(12);
  const [t, setT] = useState(2.2);
  const [playing, setPlaying] = useState(false);
  const raf = useRef<number | null>(null);

  useEffect(() => {
    if (!playing) return;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = (now - last) / 1000;
      last = now;
      setT((prev) => {
        const next = prev + dt * 0.55;
        if (next >= T_MAX) {
          setPlaying(false);
          return T_MAX;
        }
        return next;
      });
      raf.current = requestAnimationFrame(tick);
    };
    raf.current = requestAnimationFrame(tick);
    return () => {
      if (raf.current !== null) cancelAnimationFrame(raf.current);
    };
  }, [playing]);

  const r = apr / 100;
  const linear = (tt: number) => 1 + r * tt;
  const compound = (tt: number) => Math.exp(r * tt);

  const yMax = useMemo(() => Math.exp(r * T_MAX) * 1.04, [r]);
  const x = (tt: number) => PAD.l + (tt / T_MAX) * (CW - PAD.l - PAD.r);
  const y = (v: number) =>
    CH - PAD.b - ((v - 1) / (yMax - 1)) * (CH - PAD.t - PAD.b);

  const pathOf = (fn: (tt: number) => number, upTo: number) => {
    const pts: string[] = [];
    const steps = 120;
    for (let i = 0; i <= steps; i++) {
      const tt = (upTo * i) / steps;
      pts.push(`${x(tt).toFixed(1)},${y(fn(tt)).toFixed(1)}`);
    }
    return pts.join(" ");
  };

  const liqIdx = linear(t);
  const borIdx = compound(t);

  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        Two indexes drive <span className="grad">all interest</span>
      </h2>
      <p className="slide-subtitle">
        Each reserve keeps a <code>liquidityIndex</code> (what suppliers earn)
        and a <code>variableBorrowIndex</code> (what borrowers owe), both in
        27-decimal <strong>ray</strong> precision. They only advance when
        someone touches the reserve — <code>updateState()</code> cumulates the
        interest since <code>lastUpdateTimestamp</code>.
      </p>

      <div className="cols c2">
        <div className="card">
          <h3>
            Watch the indexes diverge{" "}
            <span className="pill teal">interactive</span>
          </h3>
          <div className="stepflow-controls" style={{ marginTop: 6 }}>
            <button
              className="icon-btn primary"
              onClick={() => setPlaying((p) => !p)}
            >
              {playing ? "⏸ Pause" : "▶ Play"}
            </button>
            <button
              className="icon-btn"
              onClick={() => {
                setPlaying(false);
                setT(0);
              }}
            >
              ↺ Reset
            </button>
            <span className="stepflow-progress">t = {t.toFixed(2)} years</span>
          </div>
          <svg
            viewBox={`0 0 ${CW} ${CH}`}
            style={{ width: "100%", height: "auto" }}
            role="img"
            aria-label="index growth chart"
          >
            {[0, 0.25, 0.5, 0.75, 1].map((f) => {
              const v = 1 + f * (yMax - 1);
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
                    x={PAD.l - 6}
                    y={y(v) + 3.5}
                    textAnchor="end"
                    fontSize="10"
                    fill="#66719a"
                    fontFamily="var(--mono)"
                  >
                    {v.toFixed(2)}
                  </text>
                </g>
              );
            })}
            {[0, 1, 2, 3, 4, 5].map((yr) => (
              <text
                key={yr}
                x={x(yr)}
                y={CH - 10}
                textAnchor="middle"
                fontSize="10"
                fill="#66719a"
                fontFamily="var(--mono)"
              >
                {yr}y
              </text>
            ))}
            <polyline
              points={pathOf(compound, T_MAX)}
              fill="none"
              stroke="rgba(240,100,124,0.25)"
              strokeWidth="1.5"
            />
            <polyline
              points={pathOf(linear, T_MAX)}
              fill="none"
              stroke="rgba(63,214,154,0.25)"
              strokeWidth="1.5"
            />
            <polyline
              points={pathOf(compound, t)}
              fill="none"
              stroke="#f0647c"
              strokeWidth="2.4"
            />
            <polyline
              points={pathOf(linear, t)}
              fill="none"
              stroke="#3fd69a"
              strokeWidth="2.4"
            />
            <circle cx={x(t)} cy={y(borIdx)} r="4" fill="#f0647c" />
            <circle cx={x(t)} cy={y(liqIdx)} r="4" fill="#3fd69a" />
            <text
              x={x(t) - 8}
              y={y(borIdx) - 8}
              textAnchor="end"
              fontSize="11"
              fill="#f0647c"
              fontFamily="var(--mono)"
            >
              borrow {borIdx.toFixed(4)}
            </text>
            <text
              x={x(t) - 8}
              y={y(liqIdx) + 16}
              textAnchor="end"
              fontSize="11"
              fill="#3fd69a"
              fontFamily="var(--mono)"
            >
              liquidity {liqIdx.toFixed(4)}
            </text>
          </svg>
          <div className="control-panel">
            <Slider
              label="Rate (both sides)"
              value={apr}
              min={1}
              max={50}
              step={1}
              onChange={setApr}
              format={(v) => `${v}% APR`}
            />
          </div>
          <div className="stat-grid">
            <Stat
              k="100 supplied is now"
              v={(100 * liqIdx).toFixed(2)}
              tone="good"
            />
            <Stat
              k="100 borrowed is now"
              v={(100 * borIdx).toFixed(2)}
              tone="bad"
            />
          </div>
        </div>

        <div>
          <div className="card">
            <h3>Linear for suppliers, compounded for borrowers</h3>
            <div className="formula">
              <span className="fv">liquidityIndex</span>{" "}
              <span className="fo">×=</span> <span className="fc">1</span>{" "}
              <span className="fo">+</span>{" "}
              <span className="fr">liquidityRate</span>{" "}
              <span className="fo">·</span> Δt
              <span className="fo">/</span>
              <span className="fc">1y</span>
            </div>
            <div className="formula">
              <span className="fv">borrowIndex</span>{" "}
              <span className="fo">×=</span> (<span className="fc">1</span>{" "}
              <span className="fo">+</span>{" "}
              <span className="fr">borrowRate</span>
              <span className="fo">/</span>
              <span className="fc">1y</span>
              <span className="fo">)^</span>Δt<span className="fo">·s</span>
            </div>
            <p>
              Borrow interest compounds <strong>per second</strong>{" "}
              (approximated on-chain with a 3-term binomial expansion in{" "}
              <code>MathUtils.calculateCompoundedInterest</code>); supply
              interest cumulates linearly between updates. The spread that opens
              up between the curves is exactly what funds the reserve factor and
              keeps the pool solvent — debt always grows at least as fast as
              claims.
            </p>
          </div>
          <CodeBlock
            title="src/contracts/protocol/libraries/logic/ReserveLogic.sol (concept)"
            code={`function updateState(DataTypes.ReserveData storage reserve, ...) internal {
  if (reserve.lastUpdateTimestamp == block.timestamp) return; // once per block

  _updateIndexes(reserve, cache);   // cumulate both indexes since last update
  _accrueToTreasury(reserve, cache); // reserveFactor % of new debt -> treasury
  reserve.lastUpdateTimestamp = uint40(block.timestamp);
}`}
          />
          <div className="note">
            <strong>Ray = 1e27.</strong> Indexes start at 1 ray on listing.{" "}
            <code>getReserveNormalizedIncome()</code> /{" "}
            <code>...NormalizedVariableDebt()</code> extrapolate them to{" "}
            <em>now</em> for view calls, so balances are always current even if
            the reserve was last touched days ago.
          </div>
        </div>
      </div>
    </div>
  );
}
