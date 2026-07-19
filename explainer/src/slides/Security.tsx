import { SrcRef } from "../components/SrcRef";

const ROLES: { role: string; holder: string; can: string }[] = [
  {
    role: "POOL_ADMIN",
    holder: "governance executor",
    can: "everything: listings, params, upgrades, rescueTokens",
  },
  {
    role: "RISK_ADMIN",
    holder: "risk steward / council",
    can: "caps, rate params, eMode config, collateral params",
  },
  {
    role: "EMERGENCY_ADMIN",
    holder: "guardian multisig",
    can: "pause/unpause, freeze, set eMode isolation (v3.7)",
  },
  {
    role: "ASSET_LISTING_ADMIN",
    holder: "listing steward",
    can: "initReserves for new assets",
  },
  {
    role: "FLASH_BORROWER",
    holder: "whitelisted contracts",
    can: "premium-free flash loans",
  },
  {
    role: "BRIDGE",
    holder: "nobody on current markets",
    can: "role still defined in ACLManager, but the unbacked/portals flow it gated was removed in v3.4 — vestigial",
  },
];

export function Security() {
  return (
    <div>
      <span className="slide-kicker">Ecosystem</span>
      <h2 className="slide-title">
        Governance, risk levers &amp;{" "}
        <span className="grad">defense in depth</span>
      </h2>
      <p className="slide-subtitle">
        Every privileged action flows through the ACLManager's roles, and years
        of upgrades have layered accounting defenses under the business logic.
      </p>

      <div className="cols c2">
        <div>
          <div className="card">
            <h3>Who can do what (ACLManager)</h3>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Role</th>
                  <th>Typically held by</th>
                  <th>Powers</th>
                </tr>
              </thead>
              <tbody>
                {ROLES.map((r) => (
                  <tr key={r.role}>
                    <td>
                      <code>{r.role}</code>
                    </td>
                    <td>{r.holder}</td>
                    <td>{r.can}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="card" style={{ marginTop: 14 }}>
            <h3>Risk levers per reserve</h3>
            <ul className="tight">
              <li>
                <strong>Supply / borrow caps</strong> — hard exposure limits,
                checked in scaled terms since v3.5.
              </li>
              <li>
                <strong>Freeze</strong> — stops new supply/borrows; since v3.1
                atomically sets LTV 0 (restored on unfreeze), since v3.6 also
                flags ltvzero in affected eModes.
              </li>
              <li>
                <strong>Pause</strong> — stops everything; unpausing can set a{" "}
                <strong>liquidation grace period</strong> (≤ 4h) so users can
                top up before liquidators strike.
              </li>
              <li>
                <strong>
                  Reserve factor, liquidation bonus &amp; protocol fee
                </strong>{" "}
                — the economic dials.
              </li>
            </ul>
          </div>
        </div>

        <div>
          <div className="card tone-teal">
            <h3>Accounting defenses (accumulated v3.1 → v3.7)</h3>
            <ul className="tight">
              <li>
                <strong>Virtual accounting (v3.1):</strong> utilization and
                available liquidity come from an internal counter, not{" "}
                <code>balanceOf</code> — donations to the aToken can't distort
                rates or enable inflation attacks.
              </li>
              <li>
                <strong>Borrow ≤ aToken supply (v3.1):</strong> soft cap against
                exotic mint-loop vectors.
              </li>
              <li>
                <strong>Minimum 6 decimals (v3.1)</strong> for any listed asset
                — low-decimal tokens are precision landmines.
              </li>
              <li>
                <strong>Protocol-favoring rounding everywhere (v3.5):</strong>{" "}
                supply floors, debt ceils, HF valuations pessimistic.
              </li>
              <li>
                <strong>Deterministic liquidation rounding (v3.7):</strong> no
                half-up rounding left for liquidators to game.
              </li>
              <li>
                <strong>Bricked implementation initializers (v3.4)</strong> and
                revision-gated proxy upgrades.
              </li>
            </ul>
          </div>
          <div className="card" style={{ marginTop: 14 }}>
            <h3>Process around v3.7</h3>
            <p>
              Reviewed by <strong>Certora</strong> (incl. formal-verification
              rule adaptation), <strong>MixBytes</strong>,{" "}
              <strong>Pashov Audit Group</strong>, <strong>Enigma Dark</strong>,
              plus supervised AI reviews (Sherlock AI, Savant). Deployed via
              two-phase governance rollout (smaller networks first, then
              Ethereum Core/Prime and the large L2s), with an upgrade payload
              that zeroed legacy configs before switching implementations. The
              repo ships Foundry unit/fuzz suites, Echidna/Medusa invariant
              harnesses and Certora specs under <code>tests/</code> and{" "}
              <code>certora/</code>.
            </p>
          </div>
          <SrcRef
            paths={[
              "src/contracts/protocol/configuration/ACLManager.sol",
              "audits",
              "tests/invariants",
            ]}
          />
        </div>
      </div>
    </div>
  );
}
