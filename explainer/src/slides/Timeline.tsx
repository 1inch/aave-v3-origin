import { useState } from "react";
import { VERSIONS } from "../data/versions";
import { SrcRef } from "../components/SrcRef";

export function Timeline() {
  const [open, setOpen] = useState<string>("v3.7");

  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        Four years of <span className="grad">continuous hardening</span>
      </h2>
      <p className="slide-subtitle">
        Each minor version is an in-place proxy upgrade proposed by BGD Labs and
        voted by the DAO — storage compatible, audited, and increasingly about
        deleting code rather than adding it. Click a version to expand.
      </p>

      <div className="timeline">
        {VERSIONS.map((v) => {
          const isOpen = open === v.ver;
          return (
            <div className={`tl-item ${v.major ? "major" : ""}`} key={v.ver}>
              <button
                className="tl-head"
                onClick={() => setOpen(isOpen ? "" : v.ver)}
                aria-expanded={isOpen}
              >
                <span className="ver">{v.ver}</span>
                <span className="when">{v.when}</span>
                <span className="what">{v.headline}</span>
                <span className={`chev ${isOpen ? "open" : ""}`}>▸</span>
              </button>
              {isOpen && (
                <div className="tl-body">
                  <ul className="tight">
                    {v.items.map((it, i) => (
                      <li key={i}>{it}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          );
        })}
      </div>
      <SrcRef
        paths={["docs", "README.md"]}
        note="per-version feature docs and audit index"
      />
    </div>
  );
}
