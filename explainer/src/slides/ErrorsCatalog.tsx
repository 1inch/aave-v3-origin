import { useMemo, useState } from "react";
import { ERRORS, REMOVED_IN_V37 } from "../data/errors";
import type { ErrorCategory } from "../data/errors";
import { SrcRef } from "../components/SrcRef";

const CATEGORIES: (ErrorCategory | "all")[] = [
  "all",
  "access control",
  "user validation",
  "liquidation",
  "eMode",
  "flash loan",
  "token",
  "configuration",
];

export function ErrorsCatalog() {
  const [query, setQuery] = useState("");
  const [cat, setCat] = useState<ErrorCategory | "all">("all");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return ERRORS.filter(
      (e) =>
        (cat === "all" || e.category === cat) &&
        (q === "" ||
          e.name.toLowerCase().includes(q) ||
          e.meaning.toLowerCase().includes(q) ||
          (e.note ?? "").toLowerCase().includes(q))
    );
  }, [query, cat]);

  return (
    <div>
      <span className="slide-kicker">Reference</span>
      <h2 className="slide-title">
        Error <span className="grad">catalog</span>
      </h2>
      <p className="slide-subtitle">
        Since v3.4 the protocol reverts with typed custom errors instead of
        numeric codes — explorers and traces show exactly what failed. Every
        error in <code>Errors.sol</code> (v3.7), searchable. If your integration
        reverts, start here.
      </p>

      <input
        className="errors-search"
        type="search"
        placeholder="Search errors… (e.g. dust, health factor, cap)"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      <div className="pill-row" style={{ marginTop: 0 }}>
        {CATEGORIES.map((c) => (
          <button
            key={c}
            className="icon-btn"
            style={
              cat === c
                ? {
                    background: "var(--accent-grad)",
                    border: "none",
                    color: "#fff",
                    fontWeight: 600,
                  }
                : undefined
            }
            onClick={() => setCat(c)}
          >
            {c}
          </button>
        ))}
      </div>

      <table className="tbl">
        <thead>
          <tr>
            <th style={{ width: "32%" }}>Error</th>
            <th>Meaning / thrown when</th>
            <th style={{ width: "17%" }}>Notes</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((e) => (
            <tr key={e.name}>
              <td>
                <code>{e.name}</code>
              </td>
              <td>{e.meaning}</td>
              <td>{e.note ?? ""}</td>
            </tr>
          ))}
          {filtered.length === 0 && (
            <tr>
              <td
                colSpan={3}
                style={{ textAlign: "center", color: "var(--text-faint)" }}
              >
                No errors match "{query}"
              </td>
            </tr>
          )}
        </tbody>
      </table>

      <div className="note pink" style={{ marginTop: 14 }}>
        <strong>Removed in v3.7</strong> (reverts you will never see again):{" "}
        {REMOVED_IN_V37.map((n, i) => (
          <span key={n}>
            {i > 0 && " · "}
            <code>{n}</code>
          </span>
        ))}
      </div>
      <SrcRef paths={["src/contracts/protocol/libraries/helpers/Errors.sol"]} />
    </div>
  );
}
