import { CodeBlock } from "../components/CodeBlock";
import { SrcRef } from "../components/SrcRef";

const LIBS: { name: string; kind: "external" | "internal"; desc: string }[] = [
  {
    name: "SupplyLogic",
    kind: "external",
    desc: "executeSupply / executeWithdraw, aToken transfer finalization, collateral flag management, setUserEMode (moved here in v3.6).",
  },
  {
    name: "BorrowLogic",
    kind: "external",
    desc: "executeBorrow / executeRepay incl. repayWithATokens. Since v3.5 the health-factor check runs after state changes.",
  },
  {
    name: "LiquidationLogic",
    kind: "external",
    desc: "executeLiquidationCall, close-factor rules, bonus & protocol fee, bad-debt cleanup, executeEliminateDeficit. Deterministic rounding since v3.7.",
  },
  {
    name: "FlashLoanLogic",
    kind: "external",
    desc: "flashLoan / flashLoanSimple: optimistic transfer, callback, repayment + premium (or conversion into a borrow position).",
  },
  {
    name: "PoolLogic",
    kind: "external",
    desc: "Reserve initialization, mintToTreasury, rescueTokens, index/rate syncing. executeDropReserve was removed in v3.7.",
  },
  {
    name: "ConfiguratorLogic",
    kind: "internal",
    desc: "Reserve listing + token proxy deployment for the PoolConfigurator. Inlined (internal) since v3.7 — no separate deployment, no delegatecall.",
  },
  {
    name: "ValidationLogic",
    kind: "internal",
    desc: "Every require() that guards an action: caps, freezes, pauses, HF & LTV checks, eMode rules, getUserReserveLtv (the v3.7 isolated-eMode hook).",
  },
  {
    name: "ReserveLogic",
    kind: "internal",
    desc: "The reserve state machine: updateState() (index growth + treasury accrual) and updateInterestRatesAndVirtualBalance().",
  },
  {
    name: "GenericLogic",
    kind: "internal",
    desc: "calculateUserAccountData: iterates user bitmap, prices collateral (floor) and debt (ceil) in base currency, returns HF, LTV, LT.",
  },
  {
    name: "EModeConfiguration / ReserveConfiguration / UserConfiguration",
    kind: "internal",
    desc: "Bitmap codecs: 256-bit reserve config, 2-bits-per-reserve user bitmap, 128-bit eMode collateral/borrowable/ltvzero masks.",
  },
];

export function PoolLibraries() {
  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        One Pool, <span className="grad">ten libraries</span>
      </h2>
      <p className="slide-subtitle">
        The <code>Pool</code> contract itself is mostly a router: each entry
        point delegates into a logic library. External libraries are deployed
        once and linked into the bytecode (a <code>delegatecall</code> per
        action); internal ones are inlined at compile time. This is how the
        protocol stays below the 24 KB contract-size limit.
      </p>

      <div className="cols c2">
        <div>
          <CodeBlock
            title="src/contracts/protocol/pool/Pool.sol (abridged)"
            code={`function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
  public virtual override
{
  SupplyLogic.executeSupply(
    _reserves, _reservesList, _usersConfig[onBehalfOf],
    DataTypes.ExecuteSupplyParams({
      asset: asset,
      amount: amount,
      onBehalfOf: onBehalfOf,
      referralCode: referralCode
    })
  );
}

// storage lives on the proxy (PoolStorage):
mapping(address => DataTypes.ReserveData) internal _reserves;
mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
mapping(uint256 => address) internal _reservesList;   // append-only since v3.7
mapping(uint8 => DataTypes.EModeCategory) internal _eModeCategories;`}
          />
          <div className="note">
            <strong>Why libraries?</strong> Deploying the logic once and{" "}
            <code>delegatecall</code>-ing keeps the Pool implementation small
            and lets audits focus per-concern. The proxy holds all storage, so
            upgrading the implementation (rev 10 → 11 for v3.7) never migrates
            state — new fields reuse deprecated slots or padding.
          </div>
        </div>

        <div>
          <table className="tbl">
            <thead>
              <tr>
                <th>Library</th>
                <th>Linkage</th>
                <th>Responsibility</th>
              </tr>
            </thead>
            <tbody>
              {LIBS.map((l) => (
                <tr key={l.name}>
                  <td>
                    <code>{l.name}</code>
                  </td>
                  <td>
                    <span
                      className={`pill ${l.kind === "external" ? "teal" : ""}`}
                    >
                      {l.kind}
                    </span>
                  </td>
                  <td>{l.desc}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <SrcRef
            paths={[
              "src/contracts/protocol/libraries/logic",
              "src/contracts/protocol/libraries/configuration",
            ]}
          />
        </div>
      </div>
    </div>
  );
}
