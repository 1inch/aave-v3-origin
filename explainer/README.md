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

## Build

```sh
npm run build      # type-checks (tsc -b) and bundles to dist/
npm run preview    # serve the production build locally
```

## Using the deck

- Navigate with the on-screen buttons or `←` / `→` (also `PageUp` / `PageDown`, `Home`, `End`)
- Press `T` for the table of contents; every slide is deep-linkable (`#/slide-id`)
- Diagrams with a "Next step" button are step-through sequence diagrams; charts with sliders are live simulations
