import { useState } from "react";

type Node = {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
  label: string;
  sub?: string;
  color: string;
  desc: string;
  detail: string;
};

const NODES: Node[] = [
  {
    id: "provider",
    x: 355,
    y: 10,
    w: 250,
    h: 52,
    label: "PoolAddressesProvider",
    sub: "registry + proxy admin",
    color: "#8a63c8",
    desc: "The address book and upgrade hub of one market.",
    detail:
      "Immutable anchor of a market: getPool(), getPoolConfigurator(), getPriceOracle(), getACLManager(), getUmbrella(). Owned by governance — setPoolImpl() / setPoolConfiguratorImpl() perform proxy upgrades. Since v3.7 the price-oracle-sentinel entry is no longer read.",
  },
  {
    id: "acl",
    x: 30,
    y: 10,
    w: 200,
    h: 52,
    label: "ACLManager",
    sub: "roles",
    color: "#8a63c8",
    desc: "Role-based access control for every admin action.",
    detail:
      "OpenZeppelin AccessControl with protocol roles: POOL_ADMIN, EMERGENCY_ADMIN, RISK_ADMIN, FLASH_BORROWER, BRIDGE, ASSET_LISTING_ADMIN. The PoolConfigurator consults it on every admin call.",
  },
  {
    id: "oracle",
    x: 730,
    y: 10,
    w: 200,
    h: 52,
    label: "AaveOracle",
    sub: "Chainlink aggregators",
    color: "#6ea8fe",
    desc: "One price feed per asset, USD base with 8 decimals.",
    detail:
      "getAssetPrice(asset) proxies to Chainlink aggregators (with a governance-set fallback oracle). All risk math — health factor, liquidation amounts, caps in base currency — consumes these prices. In v3.7 the L2 sequencer-uptime sentinel that used to gate borrows/liquidations was removed entirely.",
  },
  {
    id: "pool",
    x: 355,
    y: 132,
    w: 250,
    h: 64,
    label: "Pool (proxy)",
    sub: "user entry point · rev 11",
    color: "#2ebac6",
    desc: "The single user-facing contract: supply, borrow, repay, withdraw, liquidate, flash loan.",
    detail:
      "An upgradeable proxy (InitializableImmutableAdminUpgradeabilityProxy) whose implementation (PoolInstance, POOL_REVISION = 11 in v3.7) delegates the heavy lifting to externally-linked logic libraries. Holds all storage: reserves, user config bitmaps, eMode categories. Also exposes Multicall and position-manager approvals since v3.4.",
  },
  {
    id: "configurator",
    x: 680,
    y: 132,
    w: 250,
    h: 64,
    label: "PoolConfigurator (proxy)",
    sub: "admin entry point · rev 8",
    color: "#b6509e",
    desc: "Governance-facing: listings, risk params, caps, freezing, eModes.",
    detail:
      "All configuration goes through here, guarded by ACLManager roles: initReserves(), configureReserveAsCollateral(), setReserveFreeze()/Pause(), supply & borrow caps, eMode category management (incl. the new setEModeCategoryIsolated in v3.7). ConfiguratorLogic is inlined since v3.7 (no longer a separately deployed library).",
  },
  {
    id: "irs",
    x: 30,
    y: 132,
    w: 250,
    h: 64,
    label: "InterestRateStrategy",
    sub: "DefaultReserveInterestRateStrategyV2",
    color: "#f6c453",
    desc: "One stateful contract computes rates for every reserve.",
    detail:
      "Since v3.1 a single stateful strategy holds per-asset rate params (optimal usage, base rate, slope1, slope2) in storage; since v3.4 its address is an immutable on the Pool implementation (RESERVE_INTEREST_RATE_STRATEGY) — one less SLOAD per touched reserve. Rates are recalculated on every reserve interaction.",
  },
  {
    id: "atoken",
    x: 130,
    y: 268,
    w: 210,
    h: 56,
    label: "aToken (per reserve)",
    sub: "interest-bearing receipt",
    color: "#3fd69a",
    desc: "ERC-20 receipt that grows with the liquidity index; holds the underlying.",
    detail:
      "aWETH, aUSDC… hold the actual underlying balances and mint/burn on supply/withdraw. balanceOf = scaledBalance × liquidityIndex (floor-rounded since v3.5). Treasury and RewardsController are immutables since v3.4. Supports EIP-2612 permit and renounceAllowance (v3.6).",
  },
  {
    id: "vtoken",
    x: 375,
    y: 268,
    w: 210,
    h: 56,
    label: "VariableDebtToken",
    sub: "non-transferable debt",
    color: "#f0647c",
    desc: "Tokenized debt: mints on borrow, burns on repay. Not transferable.",
    detail:
      "balanceOf = scaledBalance × variableBorrowIndex (ceil-rounded since v3.5), so debt compounds automatically. Supports credit delegation: approveDelegation() lets another address borrow against your collateral, plus renounceDelegation since v3.6.",
  },
  {
    id: "treasury",
    x: 620,
    y: 268,
    w: 150,
    h: 56,
    label: "Collector",
    sub: "DAO treasury",
    color: "#9aa5c4",
    desc: "Receives the reserve-factor share of interest and all fees.",
    detail:
      "The reserve factor slice of borrow interest is accrued as aTokens to the Collector (accruedToTreasury, minted on mintToTreasury). Flash-loan premiums go 100% to the treasury since v3.4. A small DustBin contract (v3.4) holds the dust deposited at listing time.",
  },
  {
    id: "rewards",
    x: 795,
    y: 268,
    w: 150,
    h: 56,
    label: "RewardsController",
    sub: "incentives",
    color: "#9aa5c4",
    desc: "Optional liquidity-mining rewards on aToken/debt balances.",
    detail:
      "Hooked from every scaled-balance mutation (handleAction). Distributes configured reward tokens pro-rata to suppliers/borrowers. Immutable on the token implementations since v3.4.",
  },
  {
    id: "helpers",
    x: 30,
    y: 360,
    w: 900,
    h: 46,
    label:
      "Read-only helpers: AaveProtocolDataProvider · UiPoolDataProviderV3 · LiquidationDataProvider · WrappedTokenGatewayV3 · stata tokens (ERC-4626)",
    color: "#66719a",
    desc: "Periphery for UIs and integrators — no protocol state of their own.",
    detail:
      "Aggregated views over reserves, user positions, eModes and liquidation amounts, plus the ETH gateway (wrap/unwrap native ETH) and static-rate ERC-4626 wrappers. In v3.7 they keep returning legacy fields (debt ceilings, siloed flags) as hard-coded defaults for backwards compatibility.",
  },
];

const EDGES: {
  from: [number, number];
  to: [number, number];
  color?: string;
  dash?: boolean;
}[] = [
  { from: [480, 62], to: [480, 130], color: "#8a63c8" },
  { from: [605, 40], to: [728, 40], color: "#8a63c8" },
  { from: [355, 40], to: [232, 40], color: "#8a63c8" },
  { from: [680, 164], to: [607, 164], color: "#b6509e" },
  { from: [282, 164], to: [353, 164], color: "#f6c453", dash: true },
  { from: [830, 62], to: [830, 130], color: "#6ea8fe", dash: true },
  { from: [420, 198], to: [280, 266], color: "#3fd69a" },
  { from: [480, 198], to: [480, 266], color: "#f0647c" },
  { from: [560, 198], to: [680, 266], color: "#9aa5c4", dash: true },
];

export function Architecture() {
  const [sel, setSel] = useState<string>("pool");
  const active = NODES.find((n) => n.id === sel)!;

  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        The <span className="grad">contract map</span> of one market
      </h2>
      <p className="slide-subtitle">
        Every Aave instance is the same small constellation of contracts. Two
        proxies face the world — the <code>Pool</code> for users and the{" "}
        <code>PoolConfigurator</code> for governance — and everything else
        supports them. <strong>Click any box</strong> to see what it does.
      </p>

      <div
        className="cols"
        style={{ gridTemplateColumns: "minmax(0, 2fr) minmax(260px, 1fr)" }}
      >
        <div className="diagram-wrap">
          <svg
            viewBox="0 0 960 420"
            role="img"
            aria-label="Aave contract architecture"
          >
            <defs>
              <marker
                id="arch-arr"
                viewBox="0 0 10 10"
                refX="9"
                refY="5"
                markerWidth="6.5"
                markerHeight="6.5"
                orient="auto-start-reverse"
              >
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#8a93b4" />
              </marker>
            </defs>
            {EDGES.map((e, i) => (
              <line
                key={i}
                x1={e.from[0]}
                y1={e.from[1]}
                x2={e.to[0]}
                y2={e.to[1]}
                stroke={e.color ?? "#8a93b4"}
                strokeOpacity="0.55"
                strokeWidth="1.6"
                strokeDasharray={e.dash ? "5 4" : undefined}
                markerEnd="url(#arch-arr)"
              />
            ))}
            {NODES.map((n) => {
              const isSel = n.id === sel;
              return (
                <g
                  key={n.id}
                  className="arch-node"
                  onClick={() => setSel(n.id)}
                >
                  <rect
                    x={n.x}
                    y={n.y}
                    width={n.w}
                    height={n.h}
                    rx={12}
                    fill={isSel ? "rgba(46,186,198,0.14)" : "#101832"}
                    stroke={isSel ? "#2ebac6" : n.color}
                    strokeOpacity={isSel ? 1 : 0.55}
                    strokeWidth={isSel ? 2 : 1.3}
                  />
                  <text
                    x={n.x + n.w / 2}
                    y={n.y + (n.sub ? n.h / 2 - 4 : n.h / 2 + 4)}
                    textAnchor="middle"
                    fill="#e9edf8"
                    fontSize={n.w > 700 ? 11.5 : 13}
                    fontWeight={700}
                  >
                    {n.label}
                  </text>
                  {n.sub && (
                    <text
                      x={n.x + n.w / 2}
                      y={n.y + n.h / 2 + 14}
                      textAnchor="middle"
                      fill={n.color}
                      fontSize="10.5"
                      fontFamily="var(--mono)"
                    >
                      {n.sub}
                    </text>
                  )}
                </g>
              );
            })}
          </svg>
        </div>

        <div>
          <div className="arch-panel">
            <div className="t" style={{ color: active.color }}>
              {active.label}
            </div>
            <div className="d" style={{ marginBottom: 8 }}>
              {active.desc}
            </div>
            <div className="d" style={{ fontSize: 12.5 }}>
              {active.detail}
            </div>
          </div>
          <div className="note" style={{ marginTop: 12 }}>
            <strong>Upgrade model:</strong> Pool, PoolConfigurator and both
            token implementations are upgradeable by governance via the
            AddressesProvider; each implementation carries a revision (
            <code>POOL_REVISION = 11</code> for v3.7) checked by{" "}
            <code>VersionedInitializable</code>.
          </div>
          <div className="src-ref">
            src/contracts/protocol/pool · src/contracts/protocol/configuration ·
            src/contracts/instances
          </div>
        </div>
      </div>
    </div>
  );
}
