# Aave v3.7 Explainer — Plan v2

Status: **v2 largely executed** (28 slides). v1 shipped the 20-slide interactive baseline; this
document reviews it, records the research behind the review, and defines the improved roadmap.

## 0. Execution status

- **Done — Phase 2:** C0 (accuracy corrections), C1 (bitmaps & storage-layout slide), C2 (GitHub
  source deep-links via `SrcRef`), C3 (glossary slide + `Term` hover tooltips), C4 (searchable
  error catalog), C5 (L2Pool calldata slide with live `bytes32` packing), C6 (Umbrella deep-dive on
  the bad-debt slide), C7 (listing-pipeline slide).
- **Done — Phase 3:** U1 (focus management on slide change, `aria-live` step notes,
  `prefers-reduced-motion`), U2 (knowledge checks after Foundations / Core flows / eModes & v3.7),
  U3 (Esc toggles the contents grid), U4 (Ctrl/Cmd+K search palette over slides, glossary and
  errors).
- **Done — Phase 4:** E1 (CI workflow `.github/workflows/explainer.yml`: oxlint + vitest + build,
  path-filtered), E2 (41 vitest cases over `src/lib`: rate curve, health factor, close-factor/dust
  rules, isolated-eMode LTV resolution, calldata packing — simulators now consume these shared
  modules), E3 (GitHub Pages deploy job on main; requires Pages enabled in repo settings),
  E4 (version content extracted to `src/data/versions.ts` + documented update checklist).
- **Done — follow-up review round:** C8 + C9 ("Periphery & special reserves" slide: stata
  tokens/ERC-4626, WrappedTokenGatewayV3, RewardsController, treasury path, GHO minted-reserve
  card), U5 (print view via `/?print`, linked from the Contents overlay — renders all slides
  sequentially with page breaks; kept in the dark theme with `print-color-adjust: exact` instead
  of a black-on-white restyle, since the SVG palette is dark-theme-native), U6 (touch swipe
  navigation on the slide stage; SVG pan was dropped as unnecessary — diagrams fit the viewport).
  Plus review fixes: hash-link navigation now animates in the correct direction, per-slide
  `document.title`, StepFlow Play restarts from the end, invalid rate configs surface the
  on-chain `Slope2MustBeGteSlope1` error, glossary tooltips clamp to the viewport, quiz review
  link for the virtual-accounting question points at the supply flow, TOC overlay is a labelled
  dialog.
- **Remaining:** none from the v2 roadmap.

---

## 1. Goal & audience

A presentation-style webapp that gives any developer an accurate, visual mental model of how Aave
v3.7 works — deep enough to read `src/contracts` afterwards without getting lost, faithful enough
that every constant, formula and rule shown matches the code in this repository.

Primary audience: protocol/integration engineers and auditors new to Aave. Secondary: anyone
technical evaluating v3.7 changes.

## 2. What v1 ships (baseline)

| #   | Slide                        | Interactive element                                                   |
| --- | ---------------------------- | --------------------------------------------------------------------- |
| 1   | Title & agenda               | —                                                                     |
| 2   | What is Aave?                | actor-flow SVG                                                        |
| 3   | Contract architecture        | clickable contract map + info panel                                   |
| 4   | Pool & logic libraries       | — (table + code)                                                      |
| 5   | Tokenization (aToken/vToken) | index slider → live balances                                          |
| 6   | Indexes & interest accrual   | animated linear-vs-compound chart                                     |
| 7   | Interest rate model          | full curve simulator (mirrors `DefaultReserveInterestRateStrategyV2`) |
| 8   | Supply & withdraw            | step-through sequence diagram (7 steps)                               |
| 9   | Borrow & repay               | step-through sequence diagram (7 steps)                               |
| 10  | Health factor                | HF gauge + LTV/LT position bar simulator                              |
| 11  | Liquidation flow             | step-through sequence diagram (10 steps)                              |
| 12  | Liquidation math             | close-factor/bonus/dust calculator + v3.7 rounding table              |
| 13  | Bad debt & deficit           | — (cards + code)                                                      |
| 14  | eModes                       | category switcher + bitmap rows + LTV/LT bars                         |
| 15  | Isolated eMode (v3.7)        | scenario sandbox reproducing `getUserReserveLtv`                      |
| 16  | v3.7 removals                | — (cards)                                                             |
| 17  | Flash loans & UX             | step-through sequence diagram (5 steps)                               |
| 18  | Governance & security        | — (roles table + cards)                                               |
| 19  | Version timeline v3.0→v3.7   | expandable entries                                                    |
| 20  | Resources / reading path     | —                                                                     |

Engineering baseline: Vite 8 + React 19 + TS strict, zero runtime deps beyond React, hand-rolled
SVG, hash deep-links, keyboard nav, TOC overlay. `tsc -b`, `vite build`, `oxlint` and root
`npm run lint` all green. Manually GUI-tested end-to-end (recorded walkthrough in PR #4).

## 3. Review findings

### 3.1 Content gaps (found by diffing v1 against the codebase and aave.com docs topics)

- **Bitmaps & storage layout are the protocol's core data structures and v1 barely shows them.**
  `ReserveConfigurationMap` is a documented 256-bit field map (LTV bits 0–15 … flash-loan bit 63 …
  supply cap bits 116–151, with v3.7-deprecated ranges 59/61/62/168–175/176–211/212–251/252);
  `UserConfiguration` packs 2 bits per reserve (borrowing/collateral masks `0x55…`/`0xAA…`);
  `ReserveData` reuses retired slots across upgrades (deficit lives in the old stable-borrow-rate
  slot, `virtualUnderlyingBalance` moved into the old `unbacked` position). This is the best
  "how upgrades stay storage-safe" story in the repo and it deserves a dedicated interactive slide.
- **L2Pool & calldata compression is absent.** `L2Pool` packs `supply/borrow/repay/...` args into
  one/two `bytes32` via `CalldataLogic` (asset referenced by its 16-bit reserve id) — a distinctive
  Aave design for rollups, easy to visualize with a byte-layout widget.
- **Umbrella is under-explained.** v1 mentions `eliminateReserveDeficit`, but research (aave.com
  docs + LlamaRisk governance analysis) gives concrete mechanics worth a half-slide: users stake
  waTokens (wrapped aTokens, `StataTokenV2`) / GHO into `StakeToken`s; a DAO-funded _deficit
  offset_ absorbs first losses; beyond it, `Umbrella` (fetched by the Pool via
  `ADDRESSES_PROVIDER.getAddress('UMBRELLA')`) slashes stakes and burns aTokens to cover the
  recorded deficit — no governance vote needed.
- **Periphery is name-dropped only.** Stata tokens (ERC-4626 `StataTokenV2`, also Umbrella's
  coverage asset), `WrappedTokenGatewayV3`, `RewardsController` mechanics (`handleAction` hooks),
  and the treasury/`Collector`/`DustBin` path each get one sentence today.
- **The listing pipeline is missing.** How an asset actually goes live: risk process → payload
  using `AaveV3ConfigEngine` (whose sub-engines were inlined in v3.7) → `PoolConfigurator.initReserves`
  → token proxies deployed. Integrators ask this constantly.
- **No error catalog.** v3.4 moved to typed custom errors; a searchable table (error → thrown
  where → what it means for the caller) is a high-value debugging aid that nothing else offers.
- **GHO post-v3.4 behavior** (minted-not-supplied reserve, supply cap 1, 100% reserve factor,
  flash-loanable) only appears inside the timeline entry.

### 3.2 Accuracy corrections to fold in (small, found in self-review)

- Architecture panel: the AddressesProvider exposes generic `getAddress(bytes32)`; Umbrella is
  `getAddress('UMBRELLA')` — don't imply a dedicated `getUmbrella()` getter.
- Security slide BRIDGE row: the **role still exists** in `ACLManager`; it's the unbacked/portals
  flow that was removed in v3.4 — phrase as "vestigial since v3.4".
- Flash-loan slide: state that the total premium is governance-set per market via
  `updateFlashloanPremium` (verify current production bps when implementing) rather than leaving
  the value unstated.
- Liquidation-math simulator: document on-slide its simplifications (single collateral/debt pair,
  base-currency units, no eMode LT override, float math instead of ray/wad).

### 3.3 UX / pedagogy gaps

- No way to **verify understanding** (no knowledge checks) and no **glossary** — first-time
  readers meet RAY, bps, base currency, scaled balance, close factor with no hover help.
- `src-ref` footers are **plain text**; they should deep-link to the exact file on GitHub.
- No **overview/grid mode**, no **search/command palette** — 20 slides is at the edge of what TOC
  alone navigates comfortably (benchmark: reveal.js overview mode, docs sites' Ctrl+K).
- No **print/PDF export** path for offline reading.
- Accessibility debt: focus is not moved on slide change, step-flow notes aren't `aria-live`,
  animations ignore `prefers-reduced-motion`, contrast unaudited.
- Mobile: usable but step-flow SVGs get small; no touch swipe navigation.

### 3.4 Engineering gaps

- **No automated tests** for the simulator math (IR curve, close factor, dust rule, isolated-eMode
  LTV resolution) — currently guarded only by manual testing.
- **CI ignores the explainer**: `.github/workflows/test.yml` runs foundry lint/tests only; a broken
  explainer build would merge silently.
- **No deployment**: the app only runs locally despite `base: './'` already supporting static
  hosting (GitHub Pages).
- **No content pipeline** for future protocol versions (v3.8+ will need timeline/slide updates;
  version data is currently inline in `Timeline.tsx`).

## 4. Research inputs

- Repo: `docs/3.1`–`docs/3.7` release docs; `DataTypes.sol` (config bit map),
  `UserConfiguration.sol` (2-bit masks), `L2Pool.sol`/`CalldataLogic.sol`,
  `extensions/stata-token/README.md`, `Pool.sol` (UMBRELLA constant, flash-loan premium storage),
  `LiquidationLogic.sol` constants, `.github/workflows/*`, `foundry.toml` (solc 0.8.27).
- External: aave.com/docs topic inventory (v3 operations, flash loans, Umbrella, stata, AaveKit,
  changelog — confirms which topics integrators expect); aave.com Umbrella docs + LlamaRisk
  "Umbrella Coverage Principles and Slashing Logic" (deficit offset, slashing, 20-day cooldown);
  governance ARFC "[BGD] Aave v3.7" + AIP 473/489 (two-phase rollout, audit set); reveal.js
  feature set as the presentation-UX benchmark (overview mode, PDF export, fragments).

## 5. Updated roadmap

### Phase 2 — content depth & correctness (highest value)

| ID  | Item                                                              | Priority | Acceptance criteria                                                                                                                                                                                                                        |
| --- | ----------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| C0  | Apply §3.2 accuracy corrections                                   | P0       | wording fixed on architecture/security/flash-loan slides; simulator assumptions noted on-slide                                                                                                                                             |
| C1  | New slide "Bitmaps & storage layout" after Pool & libraries       | P0       | interactive 256-bit `ReserveConfigurationMap` inspector (hover a field → meaning, deprecated bits struck through); user-config 2-bit pair visual; `ReserveData` slot-reuse diagram (deficit / virtual balance)                             |
| C2  | Source deep-links                                                 | P0       | every `src-ref` renders as link(s) to `github.com/aave-dao/aave-v3-origin/blob/main/...`                                                                                                                                                   |
| C3  | Glossary + hover tooltips                                         | P0       | ≥ 15 terms (RAY, WAD, bps, base currency, scaled balance, index, utilization, LTV, LT, close factor, eMode, reserve, deficit, virtual balance, grace period); dotted-underline tooltips usable on every slide; glossary reachable from TOC |
| C4  | Errors catalog slide/panel                                        | P1       | searchable table of the custom errors in `Errors.sol` with trigger context; includes v3.7 renames/removals                                                                                                                                 |
| C5  | New slide "L2Pool & calldata compression"                         | P1       | bytes32 layout widget: toggle asset id/amount/referral fields and see the packed word update                                                                                                                                               |
| C6  | Umbrella upgrade of Bad-debt slide (or new half-slide)            | P1       | deficit offset → slash → Collector flow diagram; StakeToken/waToken mention; cooldown noted                                                                                                                                                |
| C7  | New slide "Listing pipeline & config engine"                      | P1       | payload → config engine (inlined v3.7) → PoolConfigurator → proxies sequence; who holds which role                                                                                                                                         |
| C8  | Periphery expansion: stata (ERC-4626), gateway, rewards mechanics | P2       | one structured slide replacing the current helpers footnote                                                                                                                                                                                |
| C9  | GHO card in Tokenization or Timeline detail                       | P2       | post-v3.4 behavior accurately described                                                                                                                                                                                                    |

### Phase 3 — UX & pedagogy

| ID  | Item                     | Priority | Acceptance criteria                                                                                                                                        |
| --- | ------------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| U1  | Accessibility pass       | P0       | focus moved to slide heading on change; step notes `aria-live=polite`; `prefers-reduced-motion` honored by all animations; keyboard-only run-through clean |
| U2  | Knowledge checks         | P1       | 3–4 question quiz slide at the end of each section, instant feedback with link back to the relevant slide                                                  |
| U3  | Overview grid mode       | P1       | Esc (or footer button) shows all slides as thumbnails/cards, click to jump                                                                                 |
| U4  | Search / command palette | P1       | Ctrl+K fuzzy search over slide titles + glossary terms                                                                                                     |
| U5  | Print/PDF stylesheet     | P2       | `?print` renders all slides sequentially, charts at default state, black-on-white                                                                          |
| U6  | Mobile & touch           | P2       | swipe navigation; step-flow SVGs pan/scroll on narrow screens                                                                                              |
| U7  | Presenter mode           | non-goal | cut — this is a self-serve explainer, not a talk                                                                                                           |

### Phase 4 — engineering & distribution

| ID  | Item                        | Priority | Acceptance criteria                                                                                                                                                                                                                                           |
| --- | --------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| E1  | CI job for the explainer    | P0       | new job in `.github/workflows/test.yml` (or dedicated workflow) running `npm ci && npx oxlint && npm run build` in `explainer/`, path-filtered to `explainer/**`                                                                                              |
| E2  | Simulator math unit tests   | P1       | vitest suite: IR curve (kink continuity, RF effect), close-factor matrix ($2,000/$0.95 boundaries), dust rule (revert band), isolated-eMode LTV resolution (3 branches), HF edge cases (zero debt → ∞); golden values hand-checked against contract constants |
| E3  | GitHub Pages deployment     | P1       | workflow publishing `explainer/dist` on main; README links the live URL                                                                                                                                                                                       |
| E4  | Data-driven version content | P2       | timeline + "what's new" data extracted to `src/data/versions.ts`; documented 5-step checklist for onboarding a future v3.8 (add docs, extend data file, add/adjust slides, update pills, re-record demo)                                                      |

### Suggested sequencing

1. C0 + C2 (hours, immediate accuracy/authority win) → 2. C1 + C3 (the two biggest teaching gaps)
   → 3. E1 (cheap, protects everything after) → 4. C4–C7 + U1 → 5. U2–U4, E2, E3 → 6. P2 leftovers.

## 6. Non-goals

- Live chain data / wallet connection — simulators stay deterministic and offline.
- Covering Aave v4 (hub-and-spoke) beyond a one-line "what's next" pointer — different codebase.
- i18n, analytics, backend of any kind.

## 7. Definition of done (per phase)

- All existing quality gates stay green: `tsc -b`, `vite build`, `oxlint`, root `npm run lint`.
- Any new interactive widget gets a manual GUI test pass; math widgets additionally get vitest
  coverage (from E2 onward).
- Every technical claim on a new/edited slide carries a source link (C2 style) to the exact file.
- Demo video re-recorded when slide count or headline interactions change.
