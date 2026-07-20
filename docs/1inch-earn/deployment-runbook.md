# 1inch Earn — Aave v3.7 Deployment & Configuration Runbook

1inch Earn is a sovereign Aave v3.7 money market on Ethereum mainnet, operated by the 1inch
DAO. This runbook is the ordered operational procedure for deploying and configuring it from
this repository. Everything here is code in `src/deployments/projects/1inch-earn/`,
`scripts/1inch-earn/` and `tests/1inch-earn/`; the audited Aave v3.7 core is untouched.

> Nothing in this repo waives the Aave v3.7 BUSL-1.1 license. Production mainnet use requires
> the Aave DAO agreement (or waiting for the 6 Mar 2027 MIT change date). See `LICENSE`.

## 0. What gets deployed

| Component                      | Source                                            | Notes                                                                                                                                                    |
| ------------------------------ | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full Aave v3.7 market          | `AaveV3BatchOrchestration` (unchanged)            | provider + registry, Pool/Configurator, ACL, oracle, Collector + dustBin, incentives, data providers, config engine, static aToken factory, WETH gateway |
| Launch book (7 reserves)       | `OneInchEarnConfig` + `OneInchEarnListingPayload` | 1x-branded aTokens; 1INCH collateral-only; ETH eMode                                                                                                     |
| Liquidator KYC gate (optional) | `KycNFT` + `OneInchPoolInstance`                  | permissioned liquidations; reversible                                                                                                                    |
| Governance handover            | `OneInchEarnHandover`                             | all roles/ownership → DAO, guardian, risk provider                                                                                                       |
| AQUA listing (phase 2)         | `AquaListingPayload`                              | post-TGE, gated                                                                                                                                          |

Single source of truth for all risk parameters and mainnet addresses:
[`OneInchEarnConfig.sol`](../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol).

### Launch book (approved 19 Jul 2026)

| Reserve        | LTV / LT                  | Liq. bonus | Borrowable             | Supply cap (tokens)    | eMode                         |
| -------------- | ------------------------- | ---------- | ---------------------- | ---------------------- | ----------------------------- |
| 1INCH          | 55% / 65%                 | 10%        | never (flashloans off) | 2,500,000 (→5,000,000) | –                             |
| WETH           | 80% / 83%                 | 5%         | yes                    | 3,000                  | ETH (collateral + borrowable) |
| wstETH         | 80% / 83%                 | 6%         | yes                    | 2,500                  | ETH (collateral)              |
| WBTC           | 73% / 78%                 | 6.5%       | yes                    | 100                    | –                             |
| cbBTC          | 73% / 78%                 | 6.5%       | yes                    | 100                    | –                             |
| USDC           | 75% / 78%                 | 4.5%       | yes (primary)          | 10,000,000             | –                             |
| USDT           | 75% / 78%                 | 4.5%       | yes (primary)          | 10,000,000             | –                             |
| AQUA (phase 2) | 30% / 38.5% → 50% / 62.5% | 12.5%      | never                  | $0.5M-equiv            | –                             |

Caps are in WHOLE TOKENS (the protocol multiplies by `10**decimals`), converted from the USD
anchors at the reference prices documented in `OneInchEarnConfig`. The risk provider MUST
re-validate every cap and rate against live prices immediately before launch.

## 1. Pre-flight gates (do not deploy until all are true)

- [ ] Aave DAO license agreement signed (or MIT change date reached).
- [ ] 1IP ratified: operator budget, $5M treasury seed, $2–3M protocol-owned 1INCH/USDC liquidity.
- [ ] Risk provider (Chaos Labs / Gauntlet-class) engaged; final caps/rates/LTs signed off.
- [ ] Independent config + code audit of this `1inch-earn/` package booked.
- [ ] DAO executor, guardian multisig, and risk-provider addresses finalized.
- [ ] wstETH price adapter reviewed (default: Aave mainline adapter; override via `WSTETH_USD_FEED`).
- [ ] Deploy the KYC NFT owner (Business Portal minting wallet / ops multisig) if using gated liquidations.

## 2. Environment

Use a DEDICATED deployment checkout. Do NOT run `make test` in it after `deploy-libs`: the
test harness (`TestnetProcedures`) deletes `FOUNDRY_LIBRARIES` from `.env` and forces a
recompile, which would unlink the libraries you just deployed.

```
export PATH="$HOME/.foundry/bin:$PATH"
# .env
RPC_MAINNET=<your mainnet RPC>
ETHERSCAN_API_KEY_MAINNET=<key>          # contract verification
MNEMONIC_INDEX=<ledger account index>
LEDGER_SENDER=<ledger address>
```

`git submodule update --init --recursive && npm install` if not already set up.

## 3. Dress rehearsal (run every time before mainnet)

```
# Full 1inch Earn suite: unit (config invariants, KycNFT, AQUA payload, handover),
# e2e scenarios (eMode loops, liquidations, deficit+Umbrella, gateway), debt
# transfer/swap, config verification — plus the mainnet-fork tests when RPC_MAINNET is set.
RPC_MAINNET=<rpc> make test-1inch-earn

# Anvil integration test: runs the REAL deploy scripts (deploy -> list -> seed -> gate ->
# handover) against a mainnet-forked anvil node with a test key, then simulates the
# post-handover DAO enabling debt transfers (impersonation) and a live borrow +
# consent-based debt-handoff journey via cast. This is the closest rehearsal to the
# actual mainnet procedure short of using the Ledger.
RPC_MAINNET=<rpc> make test-1inch-earn-anvil
```

All must be green. The fork suite skips automatically when `RPC_MAINNET` is unset; the anvil
harness defaults to a public node. Note: `OneInchDebtTransferLogic` (the externally-linked
library backing `OneInchPoolInstance.finalizeDebtTransfer`) is auto-deployed and linked by
`forge script` during the gate install broadcast — it is NOT part of `make deploy-libs`.

## 4. Deploy — step by step

### 4.1 Pre-deploy the logic libraries (once)

```
make deploy-libs chain=mainnet
```

CREATE2-deploys BorrowLogic, then FlashLoanLogic/LiquidationLogic/PoolLogic/SupplyLogic, and
appends their addresses to `.env` as `FOUNDRY_LIBRARIES`. Reuse the same checkout for the next
steps so the linkage persists.

### 4.2 Deploy the market

```
make deploy-1inch-earn chain=mainnet
```

Runs [`Deploy1inchEarnMarket`](../../scripts/1inch-earn/Deploy1inchEarnMarket.sol). Writes the
address report to `reports/<timestamp>-market-deployment.json`. Save this path:

```
export REPORT_PATH=reports/<timestamp>-market-deployment.json
```

Abort/rollback point: nothing is user-facing yet; no reserves are listed. A bad market can be
discarded by simply not listing on it.

### 4.3 List the launch book (1x branding + ETH eMode)

```
make list-1inch-earn chain=mainnet
```

Runs [`List1inchEarnAssets`](../../scripts/1inch-earn/List1inchEarnAssets.sol): deploys the
listing payload, grants it POOL_ADMIN, executes (sets oracle sources, `initReserves` with 1x
names, collateral/borrow/caps/liqProtocolFee, creates the ETH eMode), and self-renounces
POOL_ADMIN. Override the wstETH adapter with `WSTETH_USD_FEED=0x..` if a dedicated one was deployed.

Verify: 1INCH shows `borrowingEnabled=false` and `flashLoanEnabled=false`; aToken symbols are
`1x<SYMBOL>`; caps/LTs match the table above.

### 4.4 Seed dust (v3.6 collateral-flag pattern)

For each reserve, supply a tiny amount so the reserve is initialized and — for maker accounts —
so the collateral flag can be pre-enabled (the Aqua "dust + flag" pattern; incoming 1x tokens
count toward health only when the flag is already on). Route listing dust to the `dustBin`.

### 4.5 (Optional) Install NFT-gated liquidations

```
KYC_OWNER=<ops multisig> make install-1inch-earn-gate chain=mainnet
```

Runs [`Install1inchEarnLiquidatorGate`](../../scripts/1inch-earn/Install1inchEarnLiquidatorGate.sol):
deploys the `KycNFT` (owner mints/revokes via the Business Portal, same flow as the Aqua
resolver type) and installs `OneInchPoolInstance` via `setPoolImpl`. Reuse an existing gate
with `KYC_NFT=0x..`.

RECOMMENDED: launch permissionless (skip this step, or `DISABLE_GATE=true`) and enable the gate
later once enough liquidators are KYC'd — fewer liquidators means slower liquidations and more
v3.3 deficit landing on the treasury backstop.

### 4.6 Independent config audit gate

Freeze here. Have the independent reviewer confirm on-chain config against
`OneInchEarnConfig` before handover. This is the single most important gate — misconfiguration
is the top fork failure mode.

### 4.7 Governance handover

```
DAO_EXECUTOR=0x.. GUARDIAN=0x.. RISK_PROVIDER=0x.. make handover-1inch-earn chain=mainnet
```

Runs [`Handover1inchEarn`](../../scripts/1inch-earn/Handover1inchEarn.sol): moves provider +
registry ownership, ACL DEFAULT_ADMIN/POOL_ADMIN → DAO, EMERGENCY_ADMIN → guardian, RISK_ADMIN
→ risk provider, Collector roles → DAO, proxy admins (treasury/dustBin/static factory),
EmissionManager + WETH gateway ownership → DAO, and revokes every deployer permission.

Verify with the fork test's `test_fork_handoverRevokesDeployer` expectations against mainnet:
the deployer must hold nothing afterward.

### 4.8 Publish addresses

Commit the `reports/<timestamp>-market-deployment.json`, publish the market + 1x-token
addresses, and wire subgraph / SDK / risk dashboards / liquidation bots (all speak the Aave ABI).

## 5. Phase 2 — AQUA (post-TGE)

Gates (all required): live reviewed AQUA/USD feed, ≥30 days trading, proven 2% depth, cap
converted from $0.5M. Then execute [`AquaListingPayload`](../../src/deployments/projects/1inch-earn/AquaListingPayload.sol)
(collateral-only, borrowing off) via a governance action, granting it POOL_ADMIN for the single
listing tx. Ratchet LTV/LT 30%/38.5% → 50%/62.5% quarterly via `configureReserveAsCollateral`
or the config engine's `updateCollateralSide`, only on evidence.

## 6. Ongoing operations (post-handover, DAO-governed)

- Parameter tuning (caps, rates, LTs, eModes): risk provider via RISK_ADMIN; consider a bounded
  RiskSteward wrapper (caps-only, rate-limited) as a hardening follow-up.
- Emergency: guardian can `setReservePause` / `setPoolPause` (EMERGENCY_ADMIN).
- Bad debt: wire `provider.setAddress('UMBRELLA', ...)` + treasury cover policy (v3.3 deficit).
- Liquidator gate emergency: once the gated pool is installed, the gate token is mutable via
  `OneInchPoolInstance.setLiquidatorGate` (POOL_ADMIN or EMERGENCY_ADMIN). To OPEN liquidations
  instantly, the guardian calls `setLiquidatorGate(address(0))` — one tx, no pool upgrade. To
  rotate the KYC contract, set a new gate address. To lock out a single compromised liquidator,
  the KYC owner burns their token (emergency revoke-all is an owner script).
- Cap raises: staged, evidence-based (2% depth sustained, real volume, clean liquidations
  observed) — never by enthusiasm.

## 6b. Transferable debt tokens (off by default)

Every 1inch Earn reserve is listed with `OneInchVariableDebtToken` (a fork-layer subclass; the
audited core is untouched). Debt transfers are DISABLED at launch and require BOTH:

1. the NFT-gated pool (`OneInchPoolInstance`) installed via `setPoolImpl` — it carries the
   `finalizeDebtTransfer` hook the debt token calls; and
2. `OneInchVariableDebtToken.setTransferable(true)` for that specific reserve (POOL_ADMIN),
   done per-reserve only AFTER the independent audit.

Consent + safety model (ported from `1inch/money-market-protocol`):

- Inverted approval: `approve`/`permit` stay disabled. The debt RECEIVER opts in by calling
  `credit(spender, amount)` (or signing `creditWithSig`, e.g. inside an Aqua order). A debtor
  can never push debt onto an unwilling address, and `transferFrom` requires `from == msg.sender`
  (debt only moves by its owner; third-party/settlement moves use the adapter below).
- Full exit: pass `type(uint256).max` to move the caller's entire debt (avoids scaled-rounding dust).
- The receiver backs the assumed debt with THEIR OWN collateral; `finalizeDebtTransfer`
  health-checks the receiver (the sender only improves). Optional per-reserve KYC gate on the
  receiver via `setDebtReceiverGate` (reuses the `KycNFT`), and an optional extra receiver
  health-factor margin via `setReceiverMinHealthFactor` (0 = off; e.g. 1.1e18 for a 10% buffer).
- If `transferable` is enabled while the market still runs the vanilla pool (no
  `finalizeDebtTransfer`), transfers revert (fail-closed) — enabling transfers requires the
  `OneInchPoolInstance` upgrade first.

Use cases and the Aqua limitation:

- Single-direction handoff (someone assumes my debt) settles as one `transfer`/`transferFrom`
  on Aqua with a `creditWithSig` in the order — safe, and covered by
  `test_fork_singleDirectionDebtHandoff`.
- A two-leg debt-for-debt SWAP (`1xdUSDT` <-> `1xdUSDC`) does NOT settle as two raw transfers:
  whichever leg lands first leaves that receiver transiently holding both debts and fails the
  per-leg receiver HF check (proven by `test_naiveTwoLegSwapReverts`). Route debt SWAPS through
  the `OneInchEarnDebtSwapAdapter` (flashloan + repay/reborrow via two-sided credit delegation,
  no double-debt, no DEX) — see `OneInchEarnDebtSwap.t.sol`.
- To disable transfers again for a reserve: `setTransferable(false)` (POOL_ADMIN), one tx.

An automated config verifier (`OneInchEarnConfigVerification.t.sol`, reused on the mainnet fork)
asserts every reserve/eMode/oracle/1x-naming/red-row matches `OneInchEarnConfig` — the gate the
step 4.6 config audit should run.

## 7. Rollback summary

| After step   | To roll back                                                                            |
| ------------ | --------------------------------------------------------------------------------------- |
| 4.2 deploy   | Discard; don't list. No user funds.                                                     |
| 4.3 listing  | `setReservePause` / `setReserveFreeze` the affected reserve (POOL_ADMIN/guardian).      |
| 4.5 gate     | `setLiquidatorGate(address(0))` to open liquidations, or rotate the token — no upgrade. |
| debt xfer    | `setTransferable(false)` on the reserve's debt token — one tx, POOL_ADMIN.              |
| 4.7 handover | Irreversible without the DAO acting; do not run until 4.6 passes.                       |
