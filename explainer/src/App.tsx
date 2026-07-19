import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { SECTIONS, FLAT, slideIndexFromHash } from "./deck";
import { SearchPalette } from "./components/SearchPalette";
import { buildPaletteIndex } from "./lib/paletteIndex";

const PALETTE_INDEX = buildPaletteIndex(FLAT);
const SWIPE_MIN_X = 60;
const SWIPE_MAX_Y = 80;

function PrintDoc() {
  useEffect(() => {
    document.title = "Aave v3.7 Explainer — print view";
  }, []);
  return (
    <div className="print-doc">
      <div className="print-banner">
        Print view — every slide rendered sequentially at its default state. Use
        your browser's Print dialog to save as PDF.{" "}
        <a href="./#/intro">Back to the interactive deck →</a>
      </div>
      {FLAT.map((s, i) => {
        const Component = s.component;
        return (
          <article className="print-slide" key={s.id}>
            <div className="print-slide-meta">
              {String(i + 1).padStart(2, "0")} / {FLAT.length} · {s.section} ·{" "}
              {s.title}
            </div>
            <section className="slide">
              <Component />
            </section>
          </article>
        );
      })}
    </div>
  );
}

export default function App() {
  const isPrint = useMemo(
    () => new URLSearchParams(window.location.search).has("print"),
    []
  );
  const [index, setIndex] = useState(slideIndexFromHash);
  const [dir, setDir] = useState<"next" | "prev">("next");
  const [tocOpen, setTocOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const viewportRef = useRef<HTMLDivElement>(null);
  const touchStart = useRef<{ x: number; y: number } | null>(null);

  const goTo = useCallback((i: number) => {
    const clamped = Math.max(0, Math.min(FLAT.length - 1, i));
    setIndex((prev) => {
      if (clamped !== prev) setDir(clamped > prev ? "next" : "prev");
      return clamped;
    });
    setTocOpen(false);
  }, []);

  const goToId = useCallback(
    (id: string) => {
      const i = FLAT.findIndex((s) => s.id === id);
      if (i >= 0) goTo(i);
    },
    [goTo]
  );

  useEffect(() => {
    if (isPrint) return;
    window.history.replaceState(null, "", `#/${FLAT[index].id}`);
    document.title = `${FLAT[index].title} · Aave v3.7 Explainer`;
    viewportRef.current?.scrollTo({ top: 0 });
    // Move focus to the slide container so keyboard/screen-reader users land
    // on the new content after navigating.
    viewportRef.current?.focus({ preventScroll: true });
  }, [index, isPrint]);

  useEffect(() => {
    if (isPrint) return;
    // Route through goTo so the transition direction matches in-page hash
    // links too (e.g. the quiz "Review" links).
    const onHash = () => goTo(slideIndexFromHash());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, [goTo, isPrint]);

  useEffect(() => {
    if (isPrint) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((o) => !o);
        return;
      }
      if (paletteOpen) {
        if (e.key === "Escape") setPaletteOpen(false);
        return;
      }
      const target = e.target as HTMLElement;
      if (target.tagName === "INPUT" || target.tagName === "TEXTAREA") return;
      if (e.key === "ArrowRight" || e.key === "PageDown") {
        e.preventDefault();
        goTo(index + 1);
      } else if (e.key === "ArrowLeft" || e.key === "PageUp") {
        e.preventDefault();
        goTo(index - 1);
      } else if (e.key === "Home") {
        goTo(0);
      } else if (e.key === "End") {
        goTo(FLAT.length - 1);
      } else if (e.key === "t" || e.key === "T") {
        setTocOpen((o) => !o);
      } else if (e.key === "Escape") {
        setTocOpen((o) => !o);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index, goTo, paletteOpen, isPrint]);

  const sectionOffsets = useMemo(() => {
    let off = 0;
    return SECTIONS.map((s) => {
      const o = off;
      off += s.slides.length;
      return o;
    });
  }, []);

  if (isPrint) return <PrintDoc />;

  const slide = FLAT[index];
  const SlideComponent = slide.component;
  const progress = ((index + 1) / FLAT.length) * 100;

  const onTouchStart = (e: React.TouchEvent) => {
    const t = (e.target as HTMLElement).closest(
      "input, button, a, .toc-overlay, .palette-overlay"
    );
    touchStart.current = t
      ? null
      : { x: e.touches[0].clientX, y: e.touches[0].clientY };
  };

  const onTouchEnd = (e: React.TouchEvent) => {
    const start = touchStart.current;
    touchStart.current = null;
    if (!start || tocOpen || paletteOpen) return;
    const dx = e.changedTouches[0].clientX - start.x;
    const dy = e.changedTouches[0].clientY - start.y;
    if (Math.abs(dx) >= SWIPE_MIN_X && Math.abs(dy) <= SWIPE_MAX_Y) {
      goTo(index + (dx < 0 ? 1 : -1));
    }
  };

  return (
    <div className="deck">
      <header className="deck-header">
        <div className="brand">
          <img src="./favicon.svg" alt="" />
          <span>
            Aave <span className="v">v3.7</span> Explainer
          </span>
        </div>
        <div className="header-section">
          {slide.section} · {slide.title}
        </div>
        <div className="header-spacer" />
        <button
          className="icon-btn"
          onClick={() => setPaletteOpen(true)}
          aria-label="Search (Ctrl+K)"
        >
          ⌕ Search
        </button>
        <button className="icon-btn" onClick={() => setTocOpen((o) => !o)}>
          ☰ Contents
        </button>
        <button
          className="icon-btn"
          disabled={index === 0}
          onClick={() => goTo(index - 1)}
          aria-label="Previous slide"
        >
          ←
        </button>
        <button
          className="icon-btn primary"
          disabled={index === FLAT.length - 1}
          onClick={() => goTo(index + 1)}
          aria-label="Next slide"
        >
          Next →
        </button>
      </header>

      <main
        className="deck-stage"
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
      >
        <div
          key={slide.id}
          ref={viewportRef}
          tabIndex={-1}
          className={`slide-viewport ${
            dir === "next" ? "slide-enter-next" : "slide-enter-prev"
          }`}
        >
          <section className="slide" aria-label={slide.title}>
            <SlideComponent />
          </section>
        </div>

        {tocOpen && (
          <div
            className="toc-overlay"
            role="dialog"
            aria-modal="true"
            aria-label="Table of contents"
            onClick={(e) => e.target === e.currentTarget && setTocOpen(false)}
          >
            <div style={{ display: "flex", alignItems: "baseline", gap: 14 }}>
              <h2 className="toc-title">Contents</h2>
              <a
                className="toc-print-link"
                href="./?print"
                target="_blank"
                rel="noreferrer"
              >
                ⎙ Print / PDF view
              </a>
            </div>
            {SECTIONS.map((s, si) => (
              <div className="toc-section" key={s.title}>
                <h3>{s.title}</h3>
                <div className="toc-grid">
                  {s.slides.map((sl, j) => {
                    const flatIdx = sectionOffsets[si] + j;
                    return (
                      <button
                        key={sl.id}
                        className={`toc-item ${
                          flatIdx === index ? "active" : ""
                        }`}
                        onClick={() => goTo(flatIdx)}
                      >
                        <span className="toc-num">
                          {String(flatIdx + 1).padStart(2, "0")}
                        </span>
                        <span>{sl.title}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}

        {paletteOpen && (
          <SearchPalette
            entries={PALETTE_INDEX}
            onNavigate={goToId}
            onClose={() => setPaletteOpen(false)}
          />
        )}
      </main>

      <footer className="deck-footer">
        <span className="slide-counter">
          {String(index + 1).padStart(2, "0")} / {FLAT.length}
        </span>
        <div className="progress-track">
          <div className="progress-fill" style={{ width: `${progress}%` }} />
        </div>
        <span className="kbd-hint">
          <kbd>←</kbd> <kbd>→</kbd> navigate · <kbd>T</kbd> contents ·{" "}
          <kbd>Ctrl</kbd>+<kbd>K</kbd> search
        </span>
      </footer>
    </div>
  );
}
