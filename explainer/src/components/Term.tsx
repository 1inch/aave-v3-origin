import type { ReactNode } from "react";
import { findGlossary } from "../data/glossary";

/**
 * Inline glossary term with a hover/focus tooltip.
 * `t` must match an entry in src/data/glossary.ts; children default to the term text.
 */
export function Term({ t, children }: { t: string; children?: ReactNode }) {
  const entry = findGlossary(t);
  if (!entry) return <>{children ?? t}</>;
  return (
    <span className="term" tabIndex={0}>
      {children ?? t}
      <span className="term-tip" role="tooltip">
        <span className="tt" style={{ display: "block" }}>
          {entry.term}
        </span>
        {entry.def}
      </span>
    </span>
  );
}
