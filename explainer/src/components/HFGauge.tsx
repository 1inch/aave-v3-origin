const MIN_HF = 0.5;
const MAX_HF = 2.5;
const START_ANGLE = -110;
const END_ANGLE = 110;

function polar(cx: number, cy: number, r: number, angleDeg: number) {
  const rad = ((angleDeg - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function arcPath(cx: number, cy: number, r: number, a0: number, a1: number) {
  const p0 = polar(cx, cy, r, a0);
  const p1 = polar(cx, cy, r, a1);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M ${p0.x.toFixed(2)} ${p0.y.toFixed(
    2
  )} A ${r} ${r} 0 ${large} 1 ${p1.x.toFixed(2)} ${p1.y.toFixed(2)}`;
}

function hfToAngle(hf: number) {
  const clamped = Math.min(MAX_HF, Math.max(MIN_HF, hf));
  const t = (clamped - MIN_HF) / (MAX_HF - MIN_HF);
  return START_ANGLE + t * (END_ANGLE - START_ANGLE);
}

const ZONES: { from: number; to: number; color: string }[] = [
  { from: MIN_HF, to: 1.0, color: "#f0647c" },
  { from: 1.0, to: 1.1, color: "#f6934d" },
  { from: 1.1, to: 1.5, color: "#f6c453" },
  { from: 1.5, to: MAX_HF, color: "#3fd69a" },
];

export function HFGauge({ hf }: { hf: number }) {
  const cx = 110;
  const cy = 104;
  const r = 84;
  const angle = hfToAngle(hf);
  const needleTip = polar(cx, cy, r - 14, angle);
  const infinite = !Number.isFinite(hf);
  const display = infinite ? "∞" : hf >= 100 ? ">100" : hf.toFixed(2);
  const color = infinite
    ? "#3fd69a"
    : hf < 1
    ? "#f0647c"
    : hf < 1.1
    ? "#f6934d"
    : hf < 1.5
    ? "#f6c453"
    : "#3fd69a";
  return (
    <div className="gauge-wrap">
      <svg
        width="220"
        height="140"
        viewBox="0 0 220 140"
        role="img"
        aria-label={`Health factor ${display}`}
      >
        {ZONES.map((z) => (
          <path
            key={z.from}
            d={arcPath(cx, cy, r, hfToAngle(z.from), hfToAngle(z.to))}
            stroke={z.color}
            strokeWidth="12"
            fill="none"
            strokeLinecap="butt"
            opacity="0.85"
          />
        ))}
        {/* HF = 1 marker */}
        {(() => {
          const a = hfToAngle(1);
          const p0 = polar(cx, cy, r + 10, a);
          const p1 = polar(cx, cy, r - 10, a);
          return (
            <line
              x1={p0.x}
              y1={p0.y}
              x2={p1.x}
              y2={p1.y}
              stroke="#fff"
              strokeWidth="2"
            />
          );
        })()}
        <text
          x={polar(cx, cy, r + 22, hfToAngle(1)).x}
          y={polar(cx, cy, r + 22, hfToAngle(1)).y}
          fill="#9aa5c4"
          fontSize="10"
          textAnchor="middle"
        >
          1.0
        </text>
        <line
          x1={cx}
          y1={cy}
          x2={needleTip.x}
          y2={needleTip.y}
          stroke="#e9edf8"
          strokeWidth="3"
          strokeLinecap="round"
          style={{ transition: "all 0.2s ease" }}
        />
        <circle cx={cx} cy={cy} r="5" fill="#e9edf8" />
        <text
          x={cx}
          y={cy + 26}
          textAnchor="middle"
          fontSize="22"
          fontWeight="700"
          fill={color}
          fontFamily="var(--mono)"
        >
          {display}
        </text>
        <text
          x={cx}
          y={cy + 27 + 14}
          textAnchor="middle"
          fontSize="10"
          fill="#9aa5c4"
        >
          HEALTH FACTOR
        </text>
      </svg>
    </div>
  );
}
