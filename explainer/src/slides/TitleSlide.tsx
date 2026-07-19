export function TitleSlide() {
  return (
    <div>
      <div style={{ textAlign: "center", padding: "4vh 0 2vh" }}>
        <span className="slide-kicker">
          An interactive walkthrough for developers
        </span>
        <h1 className="big-number" style={{ margin: "6px 0 4px" }}>
          How{" "}
          <span
            style={{
              background: "var(--accent-grad)",
              WebkitBackgroundClip: "text",
              backgroundClip: "text",
              color: "transparent",
            }}
          >
            Aave v3.7
          </span>{" "}
          works
        </h1>
        <p
          className="slide-subtitle"
          style={{ margin: "10px auto 18px", textAlign: "center" }}
        >
          From the first <code>supply()</code> to the wei-level rounding of a
          liquidation — the architecture, the math and every feature shipped
          between v3.0 and v3.7, visualized. Built from the{" "}
          <code>aave-v3-origin</code> codebase itself.
        </p>
        <div className="pill-row" style={{ justifyContent: "center" }}>
          <span className="pill teal">Solidity 0.8.27</span>
          <span className="pill teal">POOL_REVISION 11</span>
          <span className="pill pink">Isolated eModes</span>
          <span className="pill pink">Deterministic liquidation rounding</span>
          <span className="pill">BUSL-1.1 · BGD Labs for the Aave DAO</span>
        </div>
      </div>

      <div className="cols c4" style={{ marginTop: 24 }}>
        <div className="card tone-teal">
          <h3>01 · Foundations</h3>
          <p>
            What Aave is, the contract map, aTokens &amp; debt tokens, interest
            indexes and the rate model that prices every borrow.
          </p>
        </div>
        <div className="card">
          <h3>02 · Core flows</h3>
          <p>
            Step-through sequence diagrams of supply, borrow and liquidation, an
            interactive health-factor and liquidation calculator, and how bad
            debt becomes a tracked deficit.
          </p>
        </div>
        <div className="card tone-pink">
          <h3>03 · eModes &amp; v3.7</h3>
          <p>
            Liquid eModes, the new <code>isolated</code> flag, and everything
            v3.7 removed: isolation mode, siloed borrowing, the L2 sentinel and{" "}
            <code>dropReserve</code>.
          </p>
        </div>
        <div className="card">
          <h3>04 · Ecosystem</h3>
          <p>
            Flash loans, multicall &amp; position managers, governance roles,
            the security model, and the full v3.0 → v3.7 version timeline.
          </p>
        </div>
      </div>

      <p className="note" style={{ marginTop: 26 }}>
        Navigate with <strong>→</strong> / <strong>←</strong>, press{" "}
        <strong>T</strong> for the table of contents. Every diagram with a{" "}
        <em>Next step</em> button can be stepped through; every chart with
        sliders is live.
      </p>
    </div>
  );
}
