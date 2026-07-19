function ActorDiagram() {
  return (
    <div className="diagram-wrap">
      <svg
        viewBox="0 0 960 330"
        role="img"
        aria-label="Actors interacting with the Aave pool"
      >
        <defs>
          <marker
            id="wa-arr"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#2ebac6" />
          </marker>
          <marker
            id="wa-arr-pink"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#b6509e" />
          </marker>
          <marker
            id="wa-arr-warn"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#f6c453" />
          </marker>
          <linearGradient id="wa-pool" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="rgba(182,80,158,0.25)" />
            <stop offset="1" stopColor="rgba(46,186,198,0.25)" />
          </linearGradient>
        </defs>

        {/* pool */}
        <rect
          x="370"
          y="95"
          width="220"
          height="140"
          rx="16"
          fill="url(#wa-pool)"
          stroke="rgba(255,255,255,0.25)"
        />
        <text
          x="480"
          y="130"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="17"
          fontWeight="800"
        >
          The Pool
        </text>
        <text
          x="480"
          y="152"
          textAnchor="middle"
          fill="#9aa5c4"
          fontSize="11.5"
        >
          one shared liquidity pool
        </text>
        <text
          x="480"
          y="168"
          textAnchor="middle"
          fill="#9aa5c4"
          fontSize="11.5"
        >
          per market (per network)
        </text>
        <text
          x="480"
          y="196"
          textAnchor="middle"
          fill="#2ebac6"
          fontSize="11"
          fontFamily="var(--mono)"
        >
          supply · withdraw · borrow · repay
        </text>
        <text
          x="480"
          y="212"
          textAnchor="middle"
          fill="#2ebac6"
          fontSize="11"
          fontFamily="var(--mono)"
        >
          liquidationCall · flashLoan
        </text>

        {/* suppliers */}
        <rect
          x="30"
          y="40"
          width="200"
          height="78"
          rx="12"
          fill="#101832"
          stroke="rgba(46,186,198,0.5)"
        />
        <text
          x="130"
          y="66"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="14"
          fontWeight="700"
        >
          Suppliers
        </text>
        <text x="130" y="86" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          deposit assets, earn yield,
        </text>
        <text x="130" y="100" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          receive aTokens 1:1
        </text>
        <line
          x1="230"
          y1="66"
          x2="368"
          y2="112"
          stroke="#2ebac6"
          strokeWidth="1.8"
          markerEnd="url(#wa-arr)"
        />
        <text
          x="290"
          y="72"
          fill="#2ebac6"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          supply(USDC)
        </text>
        <line
          x1="368"
          y1="132"
          x2="230"
          y2="96"
          stroke="#3fd69a"
          strokeWidth="1.4"
          strokeDasharray="5 4"
          markerEnd="url(#wa-arr)"
        />
        <text
          x="255"
          y="123"
          fill="#3fd69a"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          aUSDC + interest
        </text>

        {/* borrowers */}
        <rect
          x="30"
          y="200"
          width="200"
          height="78"
          rx="12"
          fill="#101832"
          stroke="rgba(182,80,158,0.55)"
        />
        <text
          x="130"
          y="226"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="14"
          fontWeight="700"
        >
          Borrowers
        </text>
        <text x="130" y="246" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          post collateral, take
        </text>
        <text x="130" y="260" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          overcollateralized loans
        </text>
        <line
          x1="230"
          y1="222"
          x2="368"
          y2="188"
          stroke="#b6509e"
          strokeWidth="1.8"
          markerEnd="url(#wa-arr-pink)"
        />
        <text
          x="252"
          y="196"
          fill="#e08fcb"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          collateral in
        </text>
        <line
          x1="368"
          y1="212"
          x2="230"
          y2="252"
          stroke="#b6509e"
          strokeWidth="1.4"
          strokeDasharray="5 4"
          markerEnd="url(#wa-arr-pink)"
        />
        <text
          x="262"
          y="248"
          fill="#e08fcb"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          borrow(WETH)
        </text>

        {/* liquidators */}
        <rect
          x="730"
          y="40"
          width="200"
          height="78"
          rx="12"
          fill="#101832"
          stroke="rgba(246,196,83,0.5)"
        />
        <text
          x="830"
          y="66"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="14"
          fontWeight="700"
        >
          Liquidators
        </text>
        <text x="830" y="86" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          repay unhealthy debt, seize
        </text>
        <text x="830" y="100" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          collateral + bonus
        </text>
        <line
          x1="730"
          y1="80"
          x2="592"
          y2="122"
          stroke="#f6c453"
          strokeWidth="1.8"
          markerEnd="url(#wa-arr-warn)"
        />
        <text
          x="612"
          y="86"
          fill="#f6c453"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          liquidationCall()
        </text>

        {/* treasury */}
        <rect
          x="730"
          y="200"
          width="200"
          height="78"
          rx="12"
          fill="#101832"
          stroke="rgba(255,255,255,0.2)"
        />
        <text
          x="830"
          y="226"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="14"
          fontWeight="700"
        >
          DAO Treasury
        </text>
        <text x="830" y="246" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          reserve factor · flash-loan fees
        </text>
        <text x="830" y="260" textAnchor="middle" fill="#9aa5c4" fontSize="11">
          liquidation protocol fee
        </text>
        <line
          x1="592"
          y1="212"
          x2="728"
          y2="240"
          stroke="#8a93b4"
          strokeWidth="1.5"
          strokeDasharray="5 4"
          markerEnd="url(#wa-arr)"
        />
        <text
          x="618"
          y="242"
          fill="#8a93b4"
          fontSize="10.5"
          fontFamily="var(--mono)"
        >
          share of interest
        </text>

        {/* oracle */}
        <rect
          x="410"
          y="272"
          width="140"
          height="42"
          rx="10"
          fill="#101832"
          stroke="rgba(110,168,254,0.5)"
        />
        <text
          x="480"
          y="290"
          textAnchor="middle"
          fill="#e9edf8"
          fontSize="12"
          fontWeight="700"
        >
          Price Oracle
        </text>
        <text x="480" y="304" textAnchor="middle" fill="#9aa5c4" fontSize="10">
          Chainlink, USD base
        </text>
        <line
          x1="480"
          y1="270"
          x2="480"
          y2="238"
          stroke="#6ea8fe"
          strokeWidth="1.5"
          markerEnd="url(#wa-arr)"
        />
      </svg>
    </div>
  );
}

export function WhatIsAave() {
  return (
    <div>
      <span className="slide-kicker">Foundations</span>
      <h2 className="slide-title">
        A non-custodial <span className="grad">liquidity protocol</span>
      </h2>
      <p className="slide-subtitle">
        Aave is a system of smart contracts where suppliers deposit assets into
        a shared pool and borrowers take overcollateralized loans against their
        own deposits. There are no order books and no counterparty matching —
        interest rates are set algorithmically from pool utilization, and
        unhealthy positions are closed by anyone willing to act as a liquidator.
      </p>

      <ActorDiagram />

      <div className="cols c4" style={{ marginTop: 18 }}>
        <div className="card">
          <h3>Overcollateralized</h3>
          <p>
            Every borrow must be backed by collateral worth more than the debt.
            The <strong>health factor</strong> measures that buffer; below 1.0
            the position becomes liquidatable.
          </p>
        </div>
        <div className="card">
          <h3>Variable rate only</h3>
          <p>
            Rates float with utilization, recomputed on every interaction.
            Stable-rate borrowing was fully removed in v3.2 after being
            deprecated protocol-wide.
          </p>
        </div>
        <div className="card">
          <h3>One market per instance</h3>
          <p>
            Each deployment (Ethereum Core, Prime, Arbitrum, Base…) is an
            isolated <strong>instance</strong> with its own Pool proxy, asset
            listings and risk parameters, all governed by the Aave DAO.
          </p>
        </div>
        <div className="card">
          <h3>Everything is a reserve</h3>
          <p>
            Each listed asset is a <strong>reserve</strong>: underlying ERC-20 +
            aToken + variable debt token + config bitmap + interest-rate params.
            The reserves list is append-only since v3.7.
          </p>
        </div>
      </div>
    </div>
  );
}
