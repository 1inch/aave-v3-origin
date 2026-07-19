import { useEffect, useId, useMemo, useState } from "react";

export type FlowActor = { id: string; label: string; sub?: string };

export type FlowKind =
  | "call"
  | "return"
  | "transfer"
  | "mint"
  | "burn"
  | "check"
  | "event";

export type FlowStep = {
  from: string;
  to: string;
  label: string;
  title: string;
  desc: string;
  kind?: FlowKind;
};

const KIND_COLOR: Record<FlowKind, string> = {
  call: "#2ebac6",
  return: "#8a93b4",
  transfer: "#f6c453",
  mint: "#3fd69a",
  burn: "#f0647c",
  check: "#6ea8fe",
  event: "#c792ea",
};

const KIND_LABEL: Record<FlowKind, string> = {
  call: "call",
  return: "return",
  transfer: "token transfer",
  mint: "mint",
  burn: "burn",
  check: "validation",
  event: "event",
};

const W = 960;
const ACTOR_H = 40;
const ROW_H = 46;
const TOP = 56;

export function StepFlow({
  actors,
  steps,
  legend = true,
}: {
  actors: FlowActor[];
  steps: FlowStep[];
  legend?: boolean;
}) {
  const uid = useId().replace(/[^a-zA-Z0-9]/g, "");
  const [current, setCurrent] = useState(0);
  const [playing, setPlaying] = useState(false);

  const xOf = useMemo(() => {
    const map = new Map<string, number>();
    const span = W / actors.length;
    actors.forEach((a, i) => map.set(a.id, span * i + span / 2));
    return map;
  }, [actors]);

  useEffect(() => {
    if (!playing) return;
    if (current >= steps.length - 1) {
      setPlaying(false);
      return;
    }
    const t = setTimeout(
      () => setCurrent((c) => Math.min(c + 1, steps.length - 1)),
      1500
    );
    return () => clearTimeout(t);
  }, [playing, current, steps.length]);

  const height = TOP + steps.length * ROW_H + 16;
  const kindsUsed = useMemo(() => {
    const set = new Set<FlowKind>();
    steps.forEach((s) => set.add(s.kind ?? "call"));
    return [...set];
  }, [steps]);
  const cur = steps[current];

  return (
    <div className="stepflow">
      <div className="stepflow-controls">
        <button
          className="icon-btn"
          onClick={() => {
            setCurrent(0);
            setPlaying(false);
          }}
        >
          ↺ Reset
        </button>
        <button
          className="icon-btn"
          disabled={current === 0}
          onClick={() => {
            setCurrent((c) => Math.max(0, c - 1));
            setPlaying(false);
          }}
        >
          ← Prev
        </button>
        <button
          className="icon-btn primary"
          disabled={current >= steps.length - 1}
          onClick={() => {
            setCurrent((c) => Math.min(steps.length - 1, c + 1));
            setPlaying(false);
          }}
        >
          Next step →
        </button>
        <button className="icon-btn" onClick={() => setPlaying((p) => !p)}>
          {playing ? "⏸ Pause" : "▶ Play"}
        </button>
        <span className="stepflow-progress">
          step {current + 1} / {steps.length}
        </span>
        {legend && (
          <span
            style={{
              display: "flex",
              gap: 10,
              flexWrap: "wrap",
              marginLeft: "auto",
            }}
          >
            {kindsUsed.map((k) => (
              <span
                key={k}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 5,
                  fontSize: 11.5,
                  color: "var(--text-dim)",
                }}
              >
                <span
                  style={{
                    width: 14,
                    height: 3,
                    background: KIND_COLOR[k],
                    borderRadius: 2,
                    display: "inline-block",
                  }}
                />
                {KIND_LABEL[k]}
              </span>
            ))}
          </span>
        )}
      </div>
      <svg
        viewBox={`0 0 ${W} ${height}`}
        role="img"
        aria-label="sequence diagram"
      >
        <defs>
          {kindsUsed.map((k) => (
            <marker
              key={k}
              id={`arr-${uid}-${k}`}
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto-start-reverse"
            >
              <path d="M 0 0 L 10 5 L 0 10 z" fill={KIND_COLOR[k]} />
            </marker>
          ))}
        </defs>
        {actors.map((a) => {
          const x = xOf.get(a.id)!;
          const bw = Math.min(150, W / actors.length - 14);
          return (
            <g key={a.id}>
              <line
                x1={x}
                y1={ACTOR_H}
                x2={x}
                y2={height - 8}
                stroke="rgba(255,255,255,0.12)"
                strokeDasharray="4 5"
              />
              <rect
                x={x - bw / 2}
                y={4}
                width={bw}
                height={ACTOR_H - 6}
                rx={9}
                fill="#101832"
                stroke="rgba(255,255,255,0.18)"
              />
              <text
                x={x}
                y={a.sub ? 19 : 25}
                textAnchor="middle"
                fill="#e9edf8"
                fontSize="12.5"
                fontWeight={700}
              >
                {a.label}
              </text>
              {a.sub && (
                <text
                  x={x}
                  y={31}
                  textAnchor="middle"
                  fill="#9aa5c4"
                  fontSize="9.5"
                  fontFamily="var(--mono)"
                >
                  {a.sub}
                </text>
              )}
            </g>
          );
        })}
        {steps.map((s, i) => {
          const kind = s.kind ?? "call";
          const color = KIND_COLOR[kind];
          const y = TOP + i * ROW_H + ROW_H / 2;
          const x1 = xOf.get(s.from)!;
          const x2 = xOf.get(s.to)!;
          const isCurrent = i === current;
          const opacity = i < current ? 0.55 : isCurrent ? 1 : 0.14;
          const selfCall = s.from === s.to;
          const labelFill = isCurrent ? "#e9edf8" : "#9aa5c4";
          return (
            <g
              key={i}
              opacity={opacity}
              style={{ transition: "opacity 0.25s" }}
            >
              {selfCall ? (
                <>
                  <path
                    d={`M ${x1} ${y - 9} C ${x1 + 56} ${y - 9}, ${x1 + 56} ${
                      y + 9
                    }, ${x1 + 7} ${y + 9}`}
                    fill="none"
                    stroke={color}
                    strokeWidth={isCurrent ? 2.4 : 1.5}
                    markerEnd={`url(#arr-${uid}-${kind})`}
                  />
                  <text
                    x={x1 + 64}
                    y={y + 4}
                    fontSize="11"
                    fontFamily="var(--mono)"
                    fill={labelFill}
                  >
                    {s.label}
                  </text>
                </>
              ) : (
                <>
                  <line
                    x1={x1}
                    y1={y}
                    x2={x2 > x1 ? x2 - 4 : x2 + 4}
                    y2={y}
                    stroke={color}
                    strokeWidth={isCurrent ? 2.4 : 1.5}
                    strokeDasharray={kind === "return" ? "5 4" : undefined}
                    markerEnd={`url(#arr-${uid}-${kind})`}
                  />
                  <text
                    x={(x1 + x2) / 2}
                    y={y - 7}
                    textAnchor="middle"
                    fontSize="11"
                    fontFamily="var(--mono)"
                    fill={labelFill}
                  >
                    {s.label}
                  </text>
                </>
              )}
              <circle
                cx={18}
                cy={y}
                r={9}
                fill={isCurrent ? color : "transparent"}
                stroke={color}
                strokeWidth="1"
              />
              <text
                x={18}
                y={y + 3.5}
                textAnchor="middle"
                fontSize="10"
                fontWeight={700}
                fill={isCurrent ? "#0b1020" : color}
              >
                {i + 1}
              </text>
            </g>
          );
        })}
      </svg>
      <div className="stepflow-note">
        <div className="t">
          {current + 1}. {cur.title}
        </div>
        <div className="d">{cur.desc}</div>
      </div>
    </div>
  );
}
