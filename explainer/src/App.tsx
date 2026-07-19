import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ComponentType } from "react";
import { TitleSlide } from "./slides/TitleSlide";
import { WhatIsAave } from "./slides/WhatIsAave";
import { Architecture } from "./slides/Architecture";
import { PoolLibraries } from "./slides/PoolLibraries";
import { Tokenization } from "./slides/Tokenization";
import { Indexes } from "./slides/Indexes";
import { RateModel } from "./slides/RateModel";
import { SupplyFlow } from "./slides/SupplyFlow";
import { BorrowFlow } from "./slides/BorrowFlow";
import { HealthFactor } from "./slides/HealthFactor";
import { LiquidationFlow } from "./slides/LiquidationFlow";
import { LiquidationMath } from "./slides/LiquidationMath";
import { BadDebt } from "./slides/BadDebt";
import { EModes } from "./slides/EModes";
import { IsolatedEMode } from "./slides/IsolatedEMode";
import { V37Changes } from "./slides/V37Changes";
import { FlashLoans } from "./slides/FlashLoans";
import { Security } from "./slides/Security";
import { Timeline } from "./slides/Timeline";
import { Resources } from "./slides/Resources";

type SlideDef = { id: string; title: string; component: ComponentType };
type SectionDef = { title: string; slides: SlideDef[] };

const SECTIONS: SectionDef[] = [
  {
    title: "Foundations",
    slides: [
      {
        id: "intro",
        title: "Aave v3.7 — Developer Explainer",
        component: TitleSlide,
      },
      { id: "what-is-aave", title: "What is Aave?", component: WhatIsAave },
      {
        id: "architecture",
        title: "Contract architecture",
        component: Architecture,
      },
      {
        id: "pool-libraries",
        title: "The Pool & its logic libraries",
        component: PoolLibraries,
      },
      {
        id: "tokenization",
        title: "Tokenization: aTokens & debt tokens",
        component: Tokenization,
      },
      {
        id: "indexes",
        title: "Indexes & interest accrual",
        component: Indexes,
      },
      {
        id: "rate-model",
        title: "The interest rate model",
        component: RateModel,
      },
    ],
  },
  {
    title: "Core flows",
    slides: [
      { id: "supply-flow", title: "Supply & withdraw", component: SupplyFlow },
      { id: "borrow-flow", title: "Borrow & repay", component: BorrowFlow },
      {
        id: "health-factor",
        title: "Health factor & borrowing power",
        component: HealthFactor,
      },
      {
        id: "liquidation-flow",
        title: "Liquidations: the flow",
        component: LiquidationFlow,
      },
      {
        id: "liquidation-math",
        title: "Liquidations: the math",
        component: LiquidationMath,
      },
      { id: "bad-debt", title: "Bad debt & the deficit", component: BadDebt },
    ],
  },
  {
    title: "eModes & v3.7",
    slides: [
      { id: "emodes", title: "Efficiency modes (eModes)", component: EModes },
      {
        id: "isolated-emode",
        title: "Isolated eMode — new in v3.7",
        component: IsolatedEMode,
      },
      {
        id: "v37-changes",
        title: "v3.7 removals & simplification",
        component: V37Changes,
      },
    ],
  },
  {
    title: "Ecosystem",
    slides: [
      {
        id: "flash-loans",
        title: "Flash loans & UX features",
        component: FlashLoans,
      },
      {
        id: "security",
        title: "Governance, risk & security",
        component: Security,
      },
      {
        id: "timeline",
        title: "Version history: v3.0 → v3.7",
        component: Timeline,
      },
      {
        id: "resources",
        title: "Reading the code & resources",
        component: Resources,
      },
    ],
  },
];

const FLAT: (SlideDef & { section: string })[] = SECTIONS.flatMap((s) =>
  s.slides.map((sl) => ({ ...sl, section: s.title }))
);

function slideIndexFromHash(): number {
  const id = window.location.hash.replace(/^#\/?/, "");
  const i = FLAT.findIndex((s) => s.id === id);
  return i >= 0 ? i : 0;
}

export default function App() {
  const [index, setIndex] = useState(slideIndexFromHash);
  const [dir, setDir] = useState<"next" | "prev">("next");
  const [tocOpen, setTocOpen] = useState(false);
  const viewportRef = useRef<HTMLDivElement>(null);

  const goTo = useCallback((i: number) => {
    const clamped = Math.max(0, Math.min(FLAT.length - 1, i));
    setIndex((prev) => {
      if (clamped !== prev) setDir(clamped > prev ? "next" : "prev");
      return clamped;
    });
    setTocOpen(false);
  }, []);

  useEffect(() => {
    window.history.replaceState(null, "", `#/${FLAT[index].id}`);
    viewportRef.current?.scrollTo({ top: 0 });
  }, [index]);

  useEffect(() => {
    const onHash = () => setIndex(slideIndexFromHash());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
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
        setTocOpen(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index, goTo]);

  const slide = FLAT[index];
  const SlideComponent = slide.component;
  const progress = ((index + 1) / FLAT.length) * 100;
  const sectionOffsets = useMemo(() => {
    let off = 0;
    return SECTIONS.map((s) => {
      const o = off;
      off += s.slides.length;
      return o;
    });
  }, []);

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

      <main className="deck-stage">
        <div
          key={slide.id}
          ref={viewportRef}
          className={`slide-viewport ${
            dir === "next" ? "slide-enter-next" : "slide-enter-prev"
          }`}
        >
          <section className="slide">
            <SlideComponent />
          </section>
        </div>

        {tocOpen && (
          <div
            className="toc-overlay"
            onClick={(e) => e.target === e.currentTarget && setTocOpen(false)}
          >
            <h2 className="toc-title">Contents</h2>
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
      </main>

      <footer className="deck-footer">
        <span className="slide-counter">
          {String(index + 1).padStart(2, "0")} / {FLAT.length}
        </span>
        <div className="progress-track">
          <div className="progress-fill" style={{ width: `${progress}%` }} />
        </div>
        <span className="kbd-hint">
          <kbd>←</kbd> <kbd>→</kbd> navigate · <kbd>T</kbd> contents
        </span>
      </footer>
    </div>
  );
}
