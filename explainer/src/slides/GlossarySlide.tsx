import { GLOSSARY } from "../data/glossary";

export function GlossarySlide() {
  return (
    <div>
      <span className="slide-kicker">Reference</span>
      <h2 className="slide-title">
        <span className="grad">Glossary</span>
      </h2>
      <p className="slide-subtitle">
        Every term this deck (and the codebase) leans on. Dotted-underlined
        words throughout the slides show these definitions on hover.
      </p>
      <div className="glossary-grid">
        {GLOSSARY.map((g) => (
          <div className="glossary-item" key={g.term}>
            <div className="g-term">{g.term}</div>
            <div className="g-def">{g.def}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
