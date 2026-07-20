import { StepFlow } from "../components/StepFlow";
import type { FlowActor, FlowStep } from "../components/StepFlow";
import { SrcRef } from "../components/SrcRef";

const ACTORS: FlowActor[] = [
  { id: "gov", label: "Governance" },
  { id: "payload", label: "Payload", sub: "AaveV3Payload" },
  { id: "engine", label: "ConfigEngine", sub: "AaveV3ConfigEngine" },
  { id: "configurator", label: "PoolConfigurator" },
  { id: "pool", label: "Pool" },
];

const STEPS: FlowStep[] = [
  {
    from: "gov",
    to: "payload",
    label: "AIP executes payload",
    kind: "call",
    title: "Risk process → on-chain vote",
    desc: "A listing starts as a governance forum proposal (ARFC) with risk-provider parameter recommendations, then an on-chain AIP. When it passes, the cross-chain executor runs a small, audited payload contract on the target network.",
  },
  {
    from: "payload",
    to: "engine",
    label: "listings() / eModeCategoriesCreation()",
    kind: "call",
    title: "Declarative config, not raw calls",
    desc: "Payloads describe intent as structs — Listing{asset, priceFeed, ltv, liqThreshold, caps, rate params…} — instead of dozens of raw configurator calls. EngineFlags.KEEP_CURRENT lets updates touch a single parameter.",
  },
  {
    from: "engine",
    to: "configurator",
    label: "initReserves(input[])",
    kind: "call",
    title: "The engine compiles the calls",
    desc: "Sub-engines (Listing, Borrow, Caps, Collateral, EMode, PriceFeed, Rate) translate the structs into PoolConfigurator calls. Since v3.7 they are internal libraries — called directly, no delegatecall, no seven extra deployments to verify.",
  },
  {
    from: "configurator",
    to: "pool",
    label: "ConfiguratorLogic: deploy proxies + initReserve",
    kind: "mint",
    title: "Tokens deployed, reserve appended",
    desc: "Two proxies are deployed (aToken + variable debt token) pointing at the shared implementations, and Pool.initReserve appends the asset to _reservesList, assigning the next free id — permanently, since dropReserve is gone in v3.7.",
  },
  {
    from: "configurator",
    to: "pool",
    label: "caps, collateral params, eMode, rates",
    kind: "check",
    title: "Risk parameters land",
    desc: "Supply/borrow caps, LTV/LT/bonus, reserve factor, liquidation protocol fee, eMode membership bitmaps and interest-rate data (stored on the shared rate strategy) are set. The oracle gets the asset’s price feed via AaveOracle.setAssetSources.",
  },
  {
    from: "payload",
    to: "pool",
    label: "seed supply → DustBin",
    kind: "transfer",
    title: "Dust seeding",
    desc: "A tiny initial amount is supplied on behalf of the DustBin contract (v3.4) so the reserve never returns to a fully-empty state — a guard against index-manipulation edge cases around empty reserves.",
  },
];

export function ListingPipeline() {
  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        How an asset <span className="grad">gets listed</span>
      </h2>
      <p className="slide-subtitle">
        Nobody calls the PoolConfigurator by hand. Listings flow through a
        declarative config-engine pipeline that turns a reviewed parameter sheet
        into an executable, auditable governance payload.
      </p>

      <StepFlow actors={ACTORS} steps={STEPS} />

      <div className="cols c3" style={{ marginTop: 16 }}>
        <div className="card">
          <h3>Who may call what</h3>
          <p>
            <code>initReserves</code> needs <strong>ASSET_LISTING_ADMIN</strong>{" "}
            or <strong>POOL_ADMIN</strong>; param changes accept{" "}
            <strong>RISK_ADMIN</strong>; freezing also accepts{" "}
            <strong>EMERGENCY_ADMIN</strong>. The governance executor holds the
            admin roles; risk stewards get narrower ones.
          </p>
        </div>
        <div className="card">
          <h3>Same engine for updates</h3>
          <p>
            Cap changes, rate tweaks and eMode edits ship as tiny payloads using
            the same structs with <code>KEEP_CURRENT</code> for everything
            untouched — which is how Aave executes dozens of small risk updates
            per month safely.
          </p>
        </div>
        <div className="card">
          <h3>v3.7 simplification</h3>
          <p>
            The <code>EngineLibraries</code> struct and per-engine address
            getters are gone; engine libraries and{" "}
            <code>ConfiguratorLogic</code> are compiled in. Fewer moving parts,
            fewer addresses in the deployment report.
          </p>
        </div>
      </div>
      <SrcRef
        paths={[
          "src/contracts/extensions/v3-config-engine/AaveV3ConfigEngine.sol",
          "src/contracts/protocol/libraries/logic/ConfiguratorLogic.sol",
        ]}
      />
    </div>
  );
}
