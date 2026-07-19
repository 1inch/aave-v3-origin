import { useEffect, useMemo, useRef, useState } from "react";
import { paletteMatches } from "../lib/paletteIndex";
import type { PaletteEntry } from "../lib/paletteIndex";

export function SearchPalette({
  entries,
  onNavigate,
  onClose,
}: {
  entries: PaletteEntry[];
  onNavigate: (slideId: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [sel, setSel] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const results = useMemo(() => {
    const q = query.trim();
    if (q === "") return entries.filter((e) => e.kind === "slide");
    return entries.filter((e) => paletteMatches(e, q)).slice(0, 12);
  }, [entries, query]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    setSel(0);
  }, [query]);

  const go = (entry: PaletteEntry) => {
    onNavigate(entry.targetSlideId);
    onClose();
  };

  return (
    <div
      className="palette-overlay"
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        className="palette"
        role="dialog"
        aria-label="Search slides, glossary and errors"
      >
        <input
          ref={inputRef}
          type="text"
          placeholder="Search slides, glossary terms, errors…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown") {
              e.preventDefault();
              setSel((s) => Math.min(results.length - 1, s + 1));
            } else if (e.key === "ArrowUp") {
              e.preventDefault();
              setSel((s) => Math.max(0, s - 1));
            } else if (e.key === "Enter" && results[sel]) {
              go(results[sel]);
            } else if (e.key === "Escape") {
              onClose();
            }
          }}
        />
        <div className="palette-results">
          {results.map((r, i) => (
            <button
              key={`${r.kind}-${r.label}`}
              className={`palette-item ${i === sel ? "sel" : ""}`}
              onMouseEnter={() => setSel(i)}
              onClick={() => go(r)}
            >
              <span className="kind">{r.kind}</span>
              <span>{r.label}</span>
              <span className="sub">{r.sub}</span>
            </button>
          ))}
          {results.length === 0 && (
            <div className="palette-empty">Nothing matches "{query}"</div>
          )}
        </div>
      </div>
    </div>
  );
}
