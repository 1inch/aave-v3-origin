import { SrcRef } from "../components/SrcRef";

export function V37Changes() {
  return (
    <div>
      <span className="slide-kicker">eModes &amp; v3.7</span>
      <h2 className="slide-title">
        v3.7 is mostly <span className="grad">subtraction</span>
      </h2>
      <p className="slide-subtitle">
        Beyond isolated eModes, v3.7 is a deliberate simplification release:
        four legacy mechanisms were deleted outright — roughly 600 lines less
        core code, a smaller attack surface, and gas savings on the hottest
        paths.
      </p>

      <div className="cols c2">
        <div className="card tone-bad">
          <h3>
            Isolation mode &amp; siloed borrowing{" "}
            <span className="pill bad">removed</span>
          </h3>
          <p>
            <strong>Was:</strong> per-asset debt ceilings restricting users to
            one "isolated" collateral (v3.0), and assets that forbade borrowing
            anything else alongside them.
          </p>
          <p>
            <strong>Why gone:</strong> barely used (siloed borrowing: never in
            production) and fully superseded by v3.6 eModes —
            borrowable/collateral bitmaps + per-category ltvzero give the same
            control with less state.
            <code> IsolationModeLogic</code> deleted; debt-ceiling bits in the
            reserve config are dead; liquidations no longer update isolation
            counters.
          </p>
          <p>
            <strong>Gas:</strong> borrow −1.2–2.3k, repay −3.2–7.2k, first
            supply −5.5k, <code>getReserveData</code> −2.1k.
          </p>
        </div>

        <div className="card tone-bad">
          <h3>
            PriceOracleSentinel &amp; SequencerOracle{" "}
            <span className="pill bad">removed</span>
          </h3>
          <p>
            <strong>Was:</strong> an L2 circuit breaker that froze borrows and
            liquidations while the sequencer-uptime feed reported downtime (+
            grace period), with a carve-out that still allowed liquidations
            below HF 0.95.
          </p>
          <p>
            <strong>Why gone:</strong> uptime detection proved ad-hoc and
            unreliable per network; false positives blocked liquidations exactly
            when the protocol needed them most. Both contracts, their
            interfaces, the <code>PriceOracleSentinelCheckFailed</code> error
            and the 0.95 constant are deleted — one less external call on every
            borrow and liquidation.
          </p>
        </div>

        <div className="card tone-bad">
          <h3>
            dropReserve() <span className="pill bad">removed</span>
          </h3>
          <p>
            <strong>Was:</strong> governance could delist a reserve whose
            supply, debt and treasury accruals were all exactly zero —
            conditions never met on a live market.
          </p>
          <p>
            <strong>Why gone:</strong> dropping frees a reserve id for reuse,
            and ids are hardcoded into eMode bitmaps, user-config bitmaps,
            subgraphs and integrations — silent breakage waiting to happen. The
            reserves list is now explicitly <strong>append-only</strong>.
          </p>
        </div>

        <div className="card tone-teal">
          <h3>
            Inlined libraries <span className="pill teal">simplified</span>
          </h3>
          <p>
            <code>ConfiguratorLogic</code> and all seven config-engine
            sub-libraries (Listing, Borrow, Caps, Collateral, EMode, PriceFeed,
            Rate) became <strong>internal</strong> — called directly instead of
            via <code>delegatecall</code> to separately deployed contracts.
            Fewer deployments, fewer addresses to verify, simpler orchestration.
          </p>
          <p>
            Error hygiene: <code>UserInIsolationModeOrLtvZero</code> →{" "}
            <code>UserHasAssetWithZeroLtv</code>; new{" "}
            <code>MustNotLeaveDust</code>; eight isolation/sentinel-era errors
            deleted.
          </p>
        </div>
      </div>

      <div className="note" style={{ marginTop: 16 }}>
        <strong>Compatibility:</strong> nothing breaks for integrators — data
        providers still expose the removed fields as hardcoded defaults (
        <code>getDebtCeiling() = 0</code>,{" "}
        <code>getSiloedBorrowing() = false</code>), storage bits are marked
        deprecated rather than reused, and the v3.7 upgrade payload cleaned up
        live configs before switching implementations (Pool rev 10 → 11,
        Configurator rev 7 → 8).
      </div>
      <SrcRef
        paths={[
          "docs/3.7/Aave-v3.7-changelog.md",
          "docs/3.7/mode-removal.md",
          "docs/3.7/sentinel-removal.md",
          "docs/3.7/drop-reserve-removal.md",
        ]}
      />
    </div>
  );
}
