# Aave v3.7 — Developer Explainer

An interactive, presentation-style webapp that explains how the Aave v3.7 protocol works: architecture, tokenization (aTokens / debt tokens), interest indexes and the rate model, supply/borrow/liquidation flows, health factor, bad-debt deficit accounting, eModes, and everything that shipped in v3.7 (isolated eModes, feature removals, deterministic liquidation rounding).

Content is sourced from this repository (`docs/3.1` … `docs/3.7` and `src/contracts`), so the numbers and formulas match the actual contracts (for example `LiquidationLogic` constants and `DefaultReserveInterestRateStrategyV2` math).

## Stack

- [Vite](https://vite.dev) + [React 19](https://react.dev) + TypeScript (strict)
- No runtime dependencies beyond React — all visualizations are hand-rolled SVG

## Run it

```sh
cd explainer
npm install
npm run dev        # dev server on http://localhost:5173
```

## Build & test

```sh
npm run build      # type-checks (tsc -b) and bundles to dist/
npm test           # vitest suite for the simulator math (src/lib)
npm run lint       # oxlint
npm run preview    # serve the production build locally
```

The simulator math (interest-rate curve, health factor, liquidation close-factor/dust rules, isolated-eMode LTV resolution, L2 calldata packing) lives in `src/lib/` and is unit-tested against golden values derived from the contract constants.

CI (`.github/workflows/explainer.yml`) lints, tests and builds the app on every PR touching `explainer/`, and deploys `dist/` to GitHub Pages on pushes to `main` (enable Pages with the "GitHub Actions" source in the repo settings to activate the deployment).

## Using the deck

- Navigate with the on-screen buttons or `←` / `→` (also `PageUp` / `PageDown`, `Home`, `End`)
- Press `T` (or `Esc`) for the table of contents; every slide is deep-linkable (`#/slide-id`)
- Press `Ctrl`/`Cmd`+`K` to search slides, glossary terms and protocol errors
- Diagrams with a "Next step" button are step-through sequence diagrams; charts with sliders are live simulations
- Each section ends with a short knowledge check; the Reference section holds the glossary and a searchable error catalog
- Dotted-underlined terms show glossary definitions on hover; source references deep-link to the exact file on GitHub

## Content pipeline for future versions

When a new protocol version ships (e.g. v3.8): add its entry to `src/data/versions.ts`, review affected slides (constants, flows, removals), update the title-slide pills if the headline changes, extend glossary/errors data if needed, and re-record the demo.
