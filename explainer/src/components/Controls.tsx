export function Slider({
  label,
  value,
  min,
  max,
  step = 1,
  onChange,
  format,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (v: number) => void;
  format?: (v: number) => string;
}) {
  return (
    <div className="slider-row">
      <label>{label}</label>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
      <span className="val">{format ? format(value) : String(value)}</span>
    </div>
  );
}

export function Toggle({
  label,
  on,
  onChange,
  pink,
  disabled,
}: {
  label: string;
  on: boolean;
  onChange: (v: boolean) => void;
  pink?: boolean;
  disabled?: boolean;
}) {
  return (
    <div
      className="toggle-row"
      style={disabled ? { opacity: 0.45 } : undefined}
    >
      <button
        type="button"
        className={`switch ${pink ? "pink" : ""} ${on ? "on" : ""}`}
        onClick={() => !disabled && onChange(!on)}
        aria-pressed={on}
        aria-label={label}
      />
      <span>{label}</span>
    </div>
  );
}

export function Stat({
  k,
  v,
  tone,
}: {
  k: string;
  v: string;
  tone?: "good" | "bad" | "warn" | "teal";
}) {
  return (
    <div className="stat">
      <div className="k">{k}</div>
      <div className={`v ${tone ?? ""}`}>{v}</div>
    </div>
  );
}

export function BitRow({
  label,
  bits,
  names,
  tone,
}: {
  label: string;
  bits: boolean[];
  names: string[];
  tone?: "pink" | "warn";
}) {
  return (
    <div className="bitmap-row">
      <span className="bitmap-label">{label}</span>
      {bits.map((b, i) => (
        <span
          key={i}
          className={`bit ${b ? "on" : ""} ${b && tone ? tone : ""}`}
          title={names[i]}
        >
          {b ? 1 : 0}
        </span>
      ))}
    </div>
  );
}
