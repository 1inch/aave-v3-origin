#!/usr/bin/env bash
#
# 1inch Earn — Anvil integration test.
#
# Exercises the REAL deployment SCRIPTS (Deploy -> List -> Seed -> InstallGate -> Handover)
# end-to-end against a mainnet-forked Anvil node — the one path the Foundry unit/fork tests do
# NOT cover (they call the payloads/libraries directly). Uses a funded Anvil key instead of a
# Ledger, and asserts on-chain state via `cast`.
#
# Requirements: foundry (anvil, cast, forge), jq, and a mainnet RPC in RPC_MAINNET
# (defaults to a public node). Run: make test-1inch-earn-anvil   (or bash this script).
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
unset FOUNDRY_LIBRARIES || true # let forge auto-deploy the logic libraries on the fork

RPC="${RPC_MAINNET:-https://ethereum-rpc.publicnode.com}"
PORT="${ANVIL_PORT:-8545}"
URL="http://127.0.0.1:${PORT}"
# Anvil default account #0 (well-known test key).
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
SENDER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
DAO=0x0000000000000000000000000000000000000600
GUARDIAN=0x0000000000000000000000000000000000000601
RISK=0x0000000000000000000000000000000000000602

WETH=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
ONEINCH=0x111111111117dC0aa78b770fA6A738034120C302
USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
USDT=0xdAC17F958D2ee523a2206206994597C13D831ec7
WBTC=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
WSTETH=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
MAXU=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff # type(uint256).max
# Explicit gas limit for pool actions. This makes `cast send` SKIP gas estimation — the
# estimation eth_call runs against the fork RPC and is what transiently reverts on a cold read
# from a multiplexed public endpoint; the real tx then executes against anvil's own (consistent)
# post-fork state. This is the key to deterministic runs on flaky RPCs. ~6M >> any Aave action.
GL=6000000

cd "$(git rev-parse --show-toplevel)"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"; pass "$3"; }
# Big-integer comparisons — token/debt/collateral amounts (~1e19) overflow bash's 64-bit ints.
bn_ge() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>=int(sys.argv[2]) else 1)" "$1" "$2"; }
bn_gt() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>int(sys.argv[2]) else 1)" "$1" "$2"; }
bn_lt() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1])<int(sys.argv[2]) else 1)" "$1" "$2"; }
bn_eq() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1])==int(sys.argv[2]) else 1)" "$1" "$2"; }
# a >= b - 3 : aToken balances round DOWN by a wei or two vs the supplied amount.
bn_ge_tol() { python3 -c "import sys;sys.exit(0 if int(sys.argv[1])>=int(sys.argv[2])-3 else 1)" "$1" "$2"; }

# Public, load-balanced RPCs occasionally serve cold/stale fork storage on first touch (a
# status-1 tx whose effect reads back as 0). These idempotent wrappers verify the on-chain
# EFFECT with read-retries and only (re)send when the target state is not yet satisfied, so the
# multi-asset stages are robust on flaky endpoints without risking double-actions. A dedicated
# (non-multiplexed) RPC removes the flakiness entirely.
dtoken() { cast call "$POOL" 'getReserveVariableDebtToken(address)(address)' "$1" --rpc-url "$URL"; }
atoken() { cast call "$POOL" 'getReserveAToken(address)(address)' "$1" --rpc-url "$URL"; }
bal() { cast call "$1" 'balanceOf(address)(uint256)' "$2" --rpc-url "$URL" | awk '{print $1}'; }
# scaledBalanceOf is raw local state (no `* index`), so it is IMMUNE to the cold reserve-index
# read that can make balanceOf() transiently return 0 for a status-1 tx on a multiplexed RPC.
# Progression gates use this; human-facing amount checks use bal()/getUserAccountData.
sbal() { cast call "$1" 'scaledBalanceOf(address)(uint256)' "$2" --rpc-url "$URL" | awk '{print $1}'; }
# tokdebt_base: the account's total debt in base currency (0 only if truly no debt).
debt_base() { cast call "$POOL" 'getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)' "$1" --rpc-url "$URL" | sed -n '2p' | awk '{print $1}'; }

# retry <attempts> <sleep_s> <cmd...>: run until it exits 0 (used to reach a target on-chain state).
retry() {
  local n="$1" s="$2"; shift 2
  local i
  for i in $(seq 1 "$n"); do "$@" && return 0; sleep "$s"; done
  return 1
}

# send_once_then_poll <effect_check_cmd...> -- separated by "--" from the send: retries the SEND
# only while it fails (revert / gas-estimate error), and once a send returns success polls the
# EFFECT check. Never re-sends after a successful send, so additive actions (supply/borrow)
# cannot double when a status-1 tx's effect reads back cold on a flaky RPC.
# usage: _send_then_poll "<check-fn-and-args>" cast send ...
_send_then_poll() {
  local check="$1"; shift
  local k j
  for k in 1 2 3 4; do
    if "$@" >/tmp/anvil-act.log 2>&1; then
      # Poll the effect. Between polls, mine an empty block: this forces anvil to advance and
      # re-serve state, which reconciles the transient cold reads seen on multiplexed public RPCs.
      for j in $(seq 1 12); do
        eval "$check" && return 0
        cast rpc evm_mine --rpc-url "$URL" >/dev/null 2>&1 || true
        sleep 1
      done
      return 1 # sent OK but effect never materialized (do NOT re-send / double)
    fi
    sleep 1
  done
  return 1
}

# ensure_borrow <asset> <rawAmt> <who> <pk>: borrow rawAmt once (retrying only on send failure).
# Progression gate is scaledBalanceOf > 0 (index-immune); the caller checks exact amounts later.
ensure_borrow() {
  local asset="$1" amt="$2" who="$3" pk="$4" v
  v=$(dtoken "$asset")
  bn_gt "$(sbal "$v" "$who")" 0 && return 0
  _send_then_poll "bn_gt \"\$(sbal $v $who)\" 0" \
    cast send "$POOL" 'borrow(address,uint256,uint256,uint16,address)' "$asset" "$amt" 2 0 "$who" \
    --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" && return 0
  echo "  [ensure_borrow failed] asset=$asset who=$who scaled=$(sbal "$v" "$who") last error:" >&2
  tail -3 /tmp/anvil-act.log >&2
  return 1
}

# ensure_supply <token> <rawAmt> <who> <pk>: deal + approve + supply rawAmt once (idempotent:
# deal SETS an absolute balance, and the supply is retried only on send failure).
ensure_supply() {
  local token="$1" amt="$2" who="$3" pk="$4" a
  a=$(atoken "$token")
  bn_ge_tol "$(bal "$a" "$who")" "$amt" && return 0
  deal_erc20 "$token" "$who" "$amt"
  cast send "$token" 'approve(address,uint256)' "$POOL" "$MAXU" --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" >/dev/null 2>&1 || true
  _send_then_poll "bn_ge_tol \"\$(bal $a $who)\" $amt" \
    cast send "$POOL" 'supply(address,uint256,address,uint16)' "$token" "$amt" "$who" 0 \
    --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" && return 0
  echo "  [ensure_supply failed] token=$token who=$who aBal=$(bal "$a" "$who") last error:" >&2
  tail -3 /tmp/anvil-act.log >&2
  return 1
}

# ensure_debt_cleared <asset> <who> <pk>: repay max until scaled debt == 0 (caller pre-funds interest).
ensure_debt_cleared() {
  local asset="$1" who="$2" pk="$3" v
  v=$(dtoken "$asset")
  bn_eq "$(sbal "$v" "$who")" 0 && return 0
  _send_then_poll "bn_eq \"\$(sbal $v $who)\" 0" \
    cast send "$POOL" 'repay(address,uint256,uint256,address)' "$asset" "$MAXU" 2 "$who" \
    --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" && return 0
  echo "  [ensure_debt_cleared failed] asset=$asset who=$who scaled=$(sbal "$v" "$who")" >&2
  tail -3 /tmp/anvil-act.log >&2; return 1
}

# ensure_supply_weth <rawAmt> <who> <pk>: wrap REAL ETH (keeps WETH9 ETH-backed for later
# unwraps) + approve + supply, gated on scaled aWETH registration (index-immune).
ensure_supply_weth() {
  local amt="$1" who="$2" pk="$3" a
  a=$(atoken "$WETH")
  bn_gt "$(sbal "$a" "$who")" 0 && return 0
  cast send "$WETH" 'deposit()' --value "$amt" --rpc-url "$URL" --private-key "$pk" >/dev/null 2>&1 || true
  cast send "$WETH" 'approve(address,uint256)' "$POOL" "$MAXU" --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" >/dev/null 2>&1 || true
  _send_then_poll "bn_gt \"\$(sbal $a $who)\" 0" \
    cast send "$POOL" 'supply(address,uint256,address,uint16)' "$WETH" "$amt" "$who" 0 \
    --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" && return 0
  echo "  [ensure_supply_weth failed] who=$who scaledA=$(sbal "$a" "$who")" >&2
  tail -3 /tmp/anvil-act.log >&2; return 1
}

# ensure_withdrawn <token> <who> <pk>: withdraw max until scaled aToken(who) == 0.
ensure_withdrawn() {
  local token="$1" who="$2" pk="$3" a
  a=$(atoken "$token")
  bn_eq "$(sbal "$a" "$who")" 0 && return 0
  _send_then_poll "bn_eq \"\$(sbal $a $who)\" 0" \
    cast send "$POOL" 'withdraw(address,uint256,address)' "$token" "$MAXU" "$who" \
    --gas-limit "$GL" --rpc-url "$URL" --private-key "$pk" && return 0
  echo "  [ensure_withdrawn failed] token=$token who=$who scaled=$(sbal "$a" "$who")" >&2
  tail -3 /tmp/anvil-act.log >&2; return 1
}

# deal_erc20 <token> <holder> <rawAmount>: fund any ERC20 balance on the fork WITHOUT a whale,
# the cast equivalent of forge's `deal`. Auto-detects the `balanceOf` mapping slot by probing
# candidate base slots 0..30 (works for proxied/packed layouts like USDC slot 9, USDT slot 2,
# WBTC/wstETH slot 0), writing via anvil_setStorageAt and restoring on a miss. totalSupply is
# left unadjusted (no test here asserts it).
deal_erc20() {
  local token="$1" holder="$2" amount="$3" slot mapslot orig val bal
  val=$(cast to-uint256 "$amount")
  for slot in $(seq 0 30); do
    mapslot=$(cast index address "$holder" "$slot")
    orig=$(cast storage "$token" "$mapslot" --rpc-url "$URL")
    cast rpc anvil_setStorageAt "$token" "$mapslot" "$val" --rpc-url "$URL" >/dev/null
    bal=$(cast call "$token" "balanceOf(address)(uint256)" "$holder" --rpc-url "$URL" | awk '{print $1}')
    if bn_eq "$bal" "$amount"; then return 0; fi
    cast rpc anvil_setStorageAt "$token" "$mapslot" "$orig" --rpc-url "$URL" >/dev/null
  done
  fail "deal_erc20: could not locate balance slot for $token"
}


echo "== starting anvil (fork of mainnet) =="
# Pin behind HEAD for reproducibility. Load-balanced public RPCs (the default) serve slightly
# different heads per request, so forking too close to the tip can land ahead of some backends'
# state and yield spurious empty-storage reads (observed as InsufficientDebt/gas-estimate
# reverts). ~100 blocks back sits safely inside every backend's recent-state window. Override
# with FORK_BLOCK=<n> for a fully fixed pin.
FORK_FLAG=""
if [ -n "${FORK_BLOCK:-}" ]; then
  FORK_FLAG="--fork-block-number ${FORK_BLOCK}"
  echo "  pinning fork to fixed block ${FORK_BLOCK}"
else
  LATEST=$(cast block-number --rpc-url "$RPC" 2>/dev/null || true)
  if [ -n "$LATEST" ] && [ "$LATEST" -gt 64 ] 2>/dev/null; then
    # ~32 blocks back: recent enough to stay inside a public full node's non-archive state
    # window (deeper pins hit "archive requires a token" on some endpoints), but far enough that
    # every load-balancer backend already has the block. NOTE: multiplexed public RPCs can still
    # occasionally serve cold fork storage; the multi-asset stages below retry to absorb that.
    # A dedicated (single-node) RPC via RPC_MAINNET removes the nondeterminism entirely.
    FORK_FLAG="--fork-block-number $((LATEST - 32))"
    echo "  pinning fork to block $((LATEST - 32)) (head $LATEST)"
  fi
fi
anvil --fork-url "$RPC" $FORK_FLAG --port "$PORT" --auto-impersonate --silent &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for i in $(seq 1 40); do
  if cast block-number --rpc-url "$URL" >/dev/null 2>&1; then break; fi
  sleep 1
  [ "$i" = "40" ] && fail "anvil did not start"
done
echo "  anvil up at block $(cast block-number --rpc-url "$URL")"

SCRIPT_FLAGS="--rpc-url $URL --private-key $PK --broadcast --slow --skip-simulation"

echo "== 1. deploy market =="
PRE_REPORT=$(ls -t reports/*-market-deployment.json 2>/dev/null | head -1 || true)
forge script scripts/1inch-earn/Deploy1inchEarnMarket.sol:Deploy1inchEarnMarket $SCRIPT_FLAGS >/tmp/anvil-deploy.log 2>&1 \
  || { tail -40 /tmp/anvil-deploy.log; fail "market deploy script"; }
REPORT=$(ls -t reports/*-market-deployment.json 2>/dev/null | head -1 || true)
# Guard against silently picking up a STALE report from an earlier run.
[ -n "$REPORT" ] && [ "$REPORT" != "$PRE_REPORT" ] || fail "deploy script wrote no fresh market report"
export REPORT_PATH="$REPORT"
POOL=$(jq -r .poolProxy "$REPORT")
DP=$(jq -r .protocolDataProvider "$REPORT")
ACL=$(jq -r .aclManager "$REPORT")
GATEWAY=$(jq -r .wrappedTokenGateway "$REPORT")
CONFIGURATOR=$(jq -r .poolConfiguratorProxy "$REPORT")
[ "$(cast code "$POOL" --rpc-url "$URL" | wc -c)" -gt 4 ] || fail "pool proxy has no code"
pass "market deployed (pool=$POOL)"

echo "== 2. list launch book =="
forge script scripts/1inch-earn/List1inchEarnAssets.sol:List1inchEarnAssets $SCRIPT_FLAGS >/tmp/anvil-list.log 2>&1 \
  || { tail -40 /tmp/anvil-list.log; fail "listing script"; }

# 1INCH must be collateral-only (borrowingEnabled == false); USDC must be borrowable.
ONEINCH_BORROW=$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$ONEINCH" --rpc-url "$URL" | sed -n '7p')
assert_eq "$ONEINCH_BORROW" "false" "1INCH borrowing disabled (red row)"
USDC_BORROW=$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$USDC" --rpc-url "$URL" | sed -n '7p')
assert_eq "$USDC_BORROW" "true" "USDC borrowing enabled"

# 1x branding on the aToken.
AWETH=$(cast call "$POOL" "getReserveAToken(address)(address)" "$WETH" --rpc-url "$URL")
ASYM=$(cast call "$AWETH" "symbol()(string)" --rpc-url "$URL" | tr -d '"')
assert_eq "$ASYM" "1xWETH" "aToken 1x branding"

# Listing payload renounced POOL_ADMIN; deployer still admin.
DEP_ADMIN=$(cast call "$ACL" "isPoolAdmin(address)(bool)" "$SENDER" --rpc-url "$URL")
assert_eq "$DEP_ADMIN" "true" "deployer is pool admin pre-handover"

# Warm anvil's fork cache: read each reserve's data + oracle price once so their config/index
# storage is cached locally BEFORE any borrow-time validation. On multiplexed public RPCs a
# cold in-tx fetch can transiently read 0 (surfacing as LtvValidationFailed/InsufficientDebt);
# a prior read pins a consistent value into anvil's own state.
AAVE_ORACLE=$(jq -r .aaveOracle "$REPORT")
for a in "$WETH" "$USDC" "$USDT" "$WBTC" "$WSTETH"; do
  cast call "$POOL" "getReserveData(address)" "$a" --rpc-url "$URL" >/dev/null 2>&1 || true
  cast call "$AAVE_ORACLE" "getAssetPrice(address)(uint256)" "$a" --rpc-url "$URL" >/dev/null 2>&1 || true
done
pass "warmed reserve/oracle fork cache for WETH/USDC/USDT/WBTC/wstETH"

echo "== 3. seed dust (wrap some ETH, then seed WETH into the dustBin) =="
cast send "$WETH" "deposit()" --value 0.01ether --rpc-url "$URL" --private-key "$PK" >/dev/null
forge script scripts/1inch-earn/Seed1inchEarn.sol:Seed1inchEarn $SCRIPT_FLAGS >/tmp/anvil-seed.log 2>&1 \
  || { tail -40 /tmp/anvil-seed.log; fail "seed script"; }
DUSTBIN=$(jq -r .dustBin "$REPORT")
DUST_AWETH=$(cast call "$AWETH" "balanceOf(address)(uint256)" "$DUSTBIN" --rpc-url "$URL" | awk '{print $1}')
[ "$DUST_AWETH" != "0" ] || fail "dustBin holds no aWETH after seed"
pass "seeded WETH locked in dustBin (aWETH=$DUST_AWETH)"

echo "== 4. install NFT liquidator gate =="
KYC_OWNER=$SENDER forge script scripts/1inch-earn/Install1inchEarnLiquidatorGate.sol:Install1inchEarnLiquidatorGate $SCRIPT_FLAGS >/tmp/anvil-gate.log 2>&1 \
  || { tail -40 /tmp/anvil-gate.log; fail "gate install script"; }
KYC=$(grep 'Deployed liquidator KYC NFT:' /tmp/anvil-gate.log | awk '{print $NF}')
GATE=$(cast call "$POOL" "liquidatorGate()(address)" --rpc-url "$URL")
assert_eq "$GATE" "$KYC" "liquidator gate points at the deployed KYC NFT"
assert_eq "$(cast call "$KYC" "owner()(address)" --rpc-url "$URL")" "$SENDER" "KYC NFT owned by KYC_OWNER"

echo "== 5. live tx: native ETH deposit via the WrappedTokenGateway =="
cast send "$GATEWAY" "depositETH(address,address,uint16)" "$POOL" "$SENDER" 0 --value 1ether --gas-limit "$GL" --rpc-url "$URL" --private-key "$PK" >/dev/null
SENDER_AWETH=$(cast call "$AWETH" "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$URL" | awk '{print $1}')
[ "$SENDER_AWETH" != "0" ] || fail "gateway deposit minted no aWETH"
pass "native ETH deposit minted aWETH ($SENDER_AWETH)"

echo "== 6. governance handover =="
DAO_EXECUTOR=$DAO GUARDIAN=$GUARDIAN RISK_PROVIDER=$RISK \
  forge script scripts/1inch-earn/Handover1inchEarn.sol:Handover1inchEarn $SCRIPT_FLAGS >/tmp/anvil-handover.log 2>&1 \
  || { tail -40 /tmp/anvil-handover.log; fail "handover script"; }
assert_eq "$(cast call "$ACL" "isPoolAdmin(address)(bool)" "$SENDER" --rpc-url "$URL")" "false" "deployer stripped of POOL_ADMIN"
assert_eq "$(cast call "$ACL" "isPoolAdmin(address)(bool)" "$DAO" --rpc-url "$URL")" "true" "DAO is POOL_ADMIN"
assert_eq "$(cast call "$ACL" "isEmergencyAdmin(address)(bool)" "$GUARDIAN" --rpc-url "$URL")" "true" "guardian is EMERGENCY_ADMIN"
assert_eq "$(cast call "$ACL" "isRiskAdmin(address)(bool)" "$RISK" --rpc-url "$URL")" "true" "risk provider is RISK_ADMIN"

echo "== 7. post-handover DAO op (impersonated): enable transferable WETH debt =="
# The listing already installs OneInchVariableDebtToken (revision 6) on every reserve, so no
# token upgrade is required — enabling transfers is a single POOL_ADMIN switch by the DAO.
VWETH=$(cast call "$POOL" "getReserveVariableDebtToken(address)(address)" "$WETH" --rpc-url "$URL")
assert_eq "$(cast call "$VWETH" 'ONE_INCH_DEBT_TOKEN_REVISION()(uint256)' --rpc-url "$URL")" "6" \
  "listing installed the OneInch debt token (revision 6)"
assert_eq "$(cast call "$VWETH" 'transferable()(bool)' --rpc-url "$URL")" "false" "debt transfers OFF by default"

cast rpc anvil_setBalance "$DAO" 0x8AC7230489E80000 --rpc-url "$URL" >/dev/null # gas for the DAO
cast send "$VWETH" 'setTransferable(bool)' true --from "$DAO" --unlocked --gas-limit "$GL" --rpc-url "$URL" >/dev/null \
  || fail "setTransferable by DAO"
assert_eq "$(cast call "$VWETH" 'transferable()(bool)' --rpc-url "$URL")" "true" "WETH debt transfers enabled by DAO"

# Fail-closed sanity: the stripped deployer can no longer flip the switch.
if cast send "$VWETH" 'setTransferable(bool)' false --rpc-url "$URL" --private-key "$PK" >/dev/null 2>&1; then
  fail "stripped deployer could still call setTransferable"
fi
pass "stripped deployer can no longer administer the debt token"

echo "== 8. live user journey: borrow + consent-based debt handoff (all via cast) =="
BORROWER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 # anvil account #1
BORROWER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
RECEIVER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC # anvil account #2
RECEIVER_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

ensure_supply_weth 10ether "$BORROWER" "$BORROWER_PK" || fail "stage8 borrower supply"
ensure_supply_weth 10ether "$RECEIVER" "$RECEIVER_PK" || fail "stage8 receiver supply"
ensure_borrow "$WETH" 3000000000000000000 "$BORROWER" "$BORROWER_PK" || fail "stage8 borrow"
pass "borrower supplied 10 WETH and borrowed 3 WETH"

# Receiver consents to take on 2 WETH of debt, borrower pushes it over. Gate on the receiver's
# scaled debt (index-immune) so the transfer is confirmed regardless of RPC index cold-reads.
cast send "$VWETH" "credit(address,uint256)" "$BORROWER" 2ether --gas-limit "$GL" --rpc-url "$URL" --private-key "$RECEIVER_PK" >/dev/null
_send_then_poll "bn_gt \"\$(sbal $VWETH $RECEIVER)\" 0" \
  cast send "$VWETH" "transfer(address,uint256)" "$RECEIVER" 2ether --gas-limit "$GL" --rpc-url "$URL" --private-key "$BORROWER_PK" \
  || fail "debt handoff transfer did not register"
RCV_DEBT=$(cast call "$VWETH" "balanceOf(address)(uint256)" "$RECEIVER" --rpc-url "$URL" | awk '{print $1}')
BRW_DEBT=$(cast call "$VWETH" "balanceOf(address)(uint256)" "$BORROWER" --rpc-url "$URL" | awk '{print $1}')
bn_ge "$RCV_DEBT" 2000000000000000000 || fail "receiver debt after handoff ($RCV_DEBT)"
pass "receiver now owes ~2 WETH (1xdWETH=$RCV_DEBT)"
bn_lt "$BRW_DEBT" 1100000000000000000 || fail "borrower residual debt after handoff ($BRW_DEBT)"
pass "borrower residual debt ~1 WETH (1xdWETH=$BRW_DEBT)"

# Both parties must be healthy after the handoff (HF is field 6 of getUserAccountData).
for acct in "$BORROWER" "$RECEIVER"; do
  HF=$(cast call "$POOL" "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" "$acct" --rpc-url "$URL" | sed -n '6p' | awk '{print $1}')
  bn_gt "$HF" 1000000000000000000 || fail "unhealthy account $acct (hf=$HF)"
done
pass "both parties healthy after debt handoff"

# ---------------------------------------------------------------------------------------------
# RUNTIME SCENARIOS on the live (handed-over) market. Admin actions use the impersonated DAO /
# guardian / risk roles installed by the handover (anvil started with --auto-impersonate). All
# scenarios are WETH-centric (wrappable from ETH) so they need no external token whales and are
# fully deterministic against any fork block.
# ---------------------------------------------------------------------------------------------
DAO_ADMIN="--from $DAO --unlocked"
GUARDIAN_ADMIN="--from $GUARDIAN --unlocked"
RISK_ADMIN_F="--from $RISK --unlocked"
cast rpc anvil_setBalance "$GUARDIAN" 0x8AC7230489E80000 --rpc-url "$URL" >/dev/null
cast rpc anvil_setBalance "$RISK" 0x8AC7230489E80000 --rpc-url "$URL" >/dev/null

# Anvil deterministic test accounts #3..#6.
U3=0x90F79bf6EB2c4f870365E785982E1f101E93b906
U3_PK=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
U4=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
U4_PK=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
U5=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
U5_PK=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
U6=0x976EA74026E726554dB657fA54763abd0C3a0aa9
U6_PK=0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e

echo "== 9. full supply / borrow / repay / withdraw cycle (WETH) =="
ensure_supply_weth 10ether "$U3" "$U3_PK" || fail "stage9 supply"
ensure_borrow "$WETH" 2000000000000000000 "$U3" "$U3_PK" || fail "stage9 borrow"
AWETH=$(cast call "$POOL" "getReserveAToken(address)(address)" "$WETH" --rpc-url "$URL")
cast send "$WETH" "deposit()" --value 1ether --rpc-url "$URL" --private-key "$U3_PK" >/dev/null # cover repay interest
ensure_debt_cleared "$WETH" "$U3" "$U3_PK" || fail "stage9 repay"
pass "debt fully repaid"
ensure_withdrawn "$WETH" "$U3" "$U3_PK" || fail "stage9 withdraw"
pass "collateral fully withdrawn (supply->borrow->repay->withdraw cycle)"

echo "== 10. WrappedTokenGateway native-ETH borrow + repay =="
ensure_supply_weth 10ether "$U4" "$U4_PK" || fail "stage10 supply"
cast send "$VWETH" "approveDelegation(address,uint256)" "$GATEWAY" 5ether --gas-limit "$GL" --rpc-url "$URL" --private-key "$U4_PK" >/dev/null
# Idempotent gateway borrow: only (re)send while the debt effect is not yet visible.
for _i in 1 2 3; do
  bn_ge "$(bal "$VWETH" "$U4")" 3000000000000000000 && break
  cast send "$GATEWAY" "borrowETH(address,uint256,uint16)" "$POOL" 3ether 0 --gas-limit "$GL" --rpc-url "$URL" --private-key "$U4_PK" >/dev/null 2>&1 || true
  sleep 1
done
U4_DEBT=$(bal "$VWETH" "$U4")
bn_ge "$U4_DEBT" 3000000000000000000 || fail "gateway borrowETH did not open WETH debt ($U4_DEBT)"
pass "borrowed 3 native ETH via gateway (debt=$U4_DEBT)"
cast send "$GATEWAY" "repayETH(address,uint256,address)" "$POOL" "$MAXU" "$U4" --value 4ether --gas-limit "$GL" --rpc-url "$URL" --private-key "$U4_PK" >/dev/null
assert_eq "$(cast call "$VWETH" "balanceOf(address)(uint256)" "$U4" --rpc-url "$URL" | awk '{print $1}')" "0" "gateway repayETH cleared the ETH debt"

# Capture WETH's original collateral params so admin-action stages can restore them (v3.7's
# freeze zeroes a reserve's LTV, and LT-lowering below mutates it).
WETH_LTV=$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$WETH" --rpc-url "$URL" | sed -n '2p' | awk '{print $1}')
WETH_LT=$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$WETH" --rpc-url "$URL" | sed -n '3p' | awk '{print $1}')
WETH_BONUS=$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$WETH" --rpc-url "$URL" | sed -n '4p' | awk '{print $1}')
restore_weth_collateral() {
  cast send "$CONFIGURATOR" "configureReserveAsCollateral(address,uint256,uint256,uint256)" \
    "$WETH" "$WETH_LTV" "$WETH_LT" "$WETH_BONUS" $RISK_ADMIN_F --gas-limit "$GL" --rpc-url "$URL" >/dev/null
}

echo "== 11. supply cap enforcement (risk admin) =="
ORIG_CAP=$(cast call "$DP" "getReserveCaps(address)(uint256,uint256)" "$WETH" --rpc-url "$URL" | sed -n '2p' | awk '{print $1}')
cast send "$CONFIGURATOR" "setSupplyCap(address,uint256)" "$WETH" 1 $RISK_ADMIN_F --gas-limit "$GL" --rpc-url "$URL" >/dev/null
cast send "$WETH" "deposit()" --value 2ether --rpc-url "$URL" --private-key "$U3_PK" >/dev/null
if cast send "$POOL" "supply(address,uint256,address,uint16)" "$WETH" 2ether "$U3" 0 --rpc-url "$URL" --private-key "$U3_PK" >/dev/null 2>&1; then
  fail "supply above cap should have reverted"
fi
pass "supply above cap reverted (SupplyCapExceeded)"
cast send "$CONFIGURATOR" "setSupplyCap(address,uint256)" "$WETH" "$ORIG_CAP" $RISK_ADMIN_F --gas-limit "$GL" --rpc-url "$URL" >/dev/null # restore
pass "supply cap restored to $ORIG_CAP"

echo "== 12. NFT-gated liquidation end-to-end (risk admin lowers LT to open a position) =="
# Borrower posts 10 WETH, borrows 7 WETH (70% base LTV).
ensure_supply_weth 10ether "$U5" "$U5_PK" || fail "stage12 supply"
ensure_borrow "$WETH" 7000000000000000000 "$U5" "$U5_PK" || fail "stage12 borrow"
# Risk admin drops WETH LT to 60% -> HF = 0.60*10/7 = 0.857 < 1 (ltv 59%, bonus 5%).
cast send "$CONFIGURATOR" "configureReserveAsCollateral(address,uint256,uint256,uint256)" "$WETH" 5900 6000 10500 $RISK_ADMIN_F --gas-limit "$GL" --rpc-url "$URL" >/dev/null
U5_HF=$(cast call "$POOL" "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" "$U5" --rpc-url "$URL" | sed -n '6p' | awk '{print $1}')
bn_lt "$U5_HF" 1000000000000000000 || fail "target not underwater (hf=$U5_HF)"
pass "position pushed underwater (hf=$U5_HF)"

# Liquidator (non-KYC) is blocked by the gate.
cast send "$WETH" "deposit()" --value 10ether --rpc-url "$URL" --private-key "$U6_PK" >/dev/null
cast send "$WETH" "approve(address,uint256)" "$POOL" "$MAXU" --rpc-url "$URL" --private-key "$U6_PK" >/dev/null
if cast send "$POOL" "liquidationCall(address,address,address,uint256,bool)" "$WETH" "$WETH" "$U5" "$MAXU" false --rpc-url "$URL" --private-key "$U6_PK" >/dev/null 2>&1; then
  fail "non-KYC liquidation should have reverted (gate)"
fi
pass "non-KYC liquidator blocked by the NFT gate"

# KYC owner (SENDER) mints the liquidator an NFT; liquidation now succeeds and seizes collateral.
cast send "$KYC" "mint(address,uint256)" "$U6" 100 --rpc-url "$URL" --private-key "$PK" >/dev/null
U5_COLL_BEFORE=$(cast call "$AWETH" "balanceOf(address)(uint256)" "$U5" --rpc-url "$URL" | awk '{print $1}')
cast send "$POOL" "liquidationCall(address,address,address,uint256,bool)" "$WETH" "$WETH" "$U5" "$MAXU" false --gas-limit "$GL" --rpc-url "$URL" --private-key "$U6_PK" >/tmp/anvil-liq.log 2>&1 \
  || { tail -3 /tmp/anvil-liq.log; fail "KYC liquidation reverted"; }
U5_COLL_AFTER=$(cast call "$AWETH" "balanceOf(address)(uint256)" "$U5" --rpc-url "$URL" | awk '{print $1}')
bn_lt "$U5_COLL_AFTER" "$U5_COLL_BEFORE" || fail "KYC liquidation seized no collateral (before=$U5_COLL_BEFORE after=$U5_COLL_AFTER)"
pass "KYC liquidator liquidated the position (collateral $U5_COLL_BEFORE -> $U5_COLL_AFTER)"
restore_weth_collateral # put WETH LTV/LT back
pass "WETH collateral params restored (ltv=$WETH_LTV lt=$WETH_LT)"

echo "== 13. guardian pause blocks all actions, then unpause =="
cast send "$CONFIGURATOR" "setReservePause(address,bool)" "$WETH" true $GUARDIAN_ADMIN --gas-limit "$GL" --rpc-url "$URL" >/dev/null
if cast send "$POOL" "supply(address,uint256,address,uint16)" "$WETH" 1ether "$U3" 0 --rpc-url "$URL" --private-key "$U3_PK" >/dev/null 2>&1; then
  fail "supply into paused reserve should have reverted"
fi
pass "supply into paused reserve reverted (ReservePaused)"
cast send "$CONFIGURATOR" "setReservePause(address,bool)" "$WETH" false $GUARDIAN_ADMIN --gas-limit "$GL" --rpc-url "$URL" >/dev/null
pass "guardian unpaused WETH"

echo "== 14. guardian freeze blocks new supply, then unfreeze (+ restore LTV) =="
cast send "$CONFIGURATOR" "setReserveFreeze(address,bool)" "$WETH" true $GUARDIAN_ADMIN --gas-limit "$GL" --rpc-url "$URL" >/dev/null
if cast send "$POOL" "supply(address,uint256,address,uint16)" "$WETH" 1ether "$U3" 0 --rpc-url "$URL" --private-key "$U3_PK" >/dev/null 2>&1; then
  fail "supply into frozen reserve should have reverted"
fi
pass "supply into frozen reserve reverted (ReserveFrozen)"
cast send "$CONFIGURATOR" "setReserveFreeze(address,bool)" "$WETH" false $GUARDIAN_ADMIN --gas-limit "$GL" --rpc-url "$URL" >/dev/null
# v3.7 zeroes a reserve's LTV on freeze; governance must re-set collateral params after unfreeze.
restore_weth_collateral
assert_eq "$(cast call "$DP" "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" "$WETH" --rpc-url "$URL" | sed -n '2p' | awk '{print $1}')" "$WETH_LTV" "WETH LTV restored after unfreeze"

# ---------------------------------------------------------------------------------------------
# MULTI-ASSET runtime scenarios with REAL mainnet tokens funded via `deal_erc20` (no whales).
# ---------------------------------------------------------------------------------------------
U7=0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
U7_PK=0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
U8=0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
U8_PK=0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
U9=0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
U9_PK=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6

# Deep USDC + USDT liquidity from a single funded LP (reuse account #3, clean after stage 9).
ensure_supply "$USDC" 2000000000000 "$U3" "$U3_PK" || fail "seed USDC liquidity" # 2,000,000 USDC
ensure_supply "$USDT" 2000000000000 "$U3" "$U3_PK" || fail "seed USDT liquidity" # 2,000,000 USDT
pass "seeded 2M USDC + 2M USDT liquidity via deal_erc20"

echo "== 15. cross-asset cycle: WBTC collateral -> borrow USDC -> repay -> withdraw (real tokens) =="
ensure_supply "$WBTC" 500000000 "$U7" "$U7_PK" || fail "stage15 WBTC supply" # 5 WBTC
ensure_borrow "$USDC" 40000000000 "$U7" "$U7_PK" || fail "stage15 USDC borrow"
# U7 started with 0 USDC, so the wallet balance is exactly the borrowed principal (index-immune).
bn_ge_tol "$(bal "$USDC" "$U7")" 40000000000 || fail "stage15 did not receive 40k USDC"
pass "borrowed 40k USDC against WBTC collateral"
deal_erc20 "$USDC" "$U7" 41000000000 # top up to cover accrued interest at repay
cast send "$USDC" "approve(address,uint256)" "$POOL" "$MAXU" --rpc-url "$URL" --private-key "$U7_PK" >/dev/null
ensure_debt_cleared "$USDC" "$U7" "$U7_PK" || fail "stage15 USDC repay"
pass "USDC debt fully repaid"
ensure_withdrawn "$WBTC" "$U7" "$U7_PK" || fail "stage15 WBTC withdraw"
pass "WBTC collateral fully withdrawn (cross-asset supply->borrow->repay->withdraw cycle)"

echo "== 16. stablecoin eMode boosted borrow (USDC collateral -> USDT) =="
ensure_supply "$USDC" 100000000000 "$U8" "$U8_PK" || fail "stage16 USDC supply" # 100k USDC
retry 5 1 bash -c "cast send '$POOL' 'setUserEMode(uint8)' 2 --gas-limit '$GL' --rpc-url '$URL' --private-key '$U8_PK' >/dev/null 2>&1; [ \"\$(cast call '$POOL' 'getUserEMode(address)(uint256)' '$U8' --rpc-url '$URL' | awk '{print \$1}')\" = 2 ]" \
  || fail "stage16 enter eMode"
pass "entered stablecoin eMode"
# 85k USDT is above the 75% base LTV but within the 90% stablecoin-eMode LTV.
ensure_borrow "$USDT" 85000000000 "$U8" "$U8_PK" || fail "stage16 USDT borrow"
# Warm the debt index into anvil's cache (mining reconciles multiplexed-RPC cold reads) so the
# HF and exit-eMode checks below evaluate against the real, non-zero debt.
for _i in $(seq 1 12); do bn_gt "$(debt_base "$U8")" 0 && break; cast rpc evm_mine --rpc-url "$URL" >/dev/null 2>&1 || true; sleep 1; done
bn_gt "$(debt_base "$U8")" 0 || fail "stage16 debt did not register"
U8_HF=$(cast call "$POOL" "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" "$U8" --rpc-url "$URL" | sed -n '6p' | awk '{print $1}')
bn_gt "$U8_HF" 1000000000000000000 || fail "stablecoin-eMode borrower unhealthy (hf=$U8_HF)"
pass "borrowed 85k USDT at boosted eMode LTV, healthy (hf=$U8_HF)"
# Exiting eMode would drop to the 75% base LTV and undercollateralize -> must revert.
if cast send "$POOL" "setUserEMode(uint8)" 0 --rpc-url "$URL" --private-key "$U8_PK" >/dev/null 2>&1; then
  fail "exiting eMode should have reverted (undercollateralized at base LTV)"
fi
pass "exit-eMode correctly blocked while it would undercollateralize"

echo "== 17. P2P debt swap via OneInchEarnDebtSwapAdapter (USDT <-> USDC, real tokens) =="
ADAPTER=$(forge create src/deployments/projects/1inch-earn/OneInchEarnDebtSwapAdapter.sol:OneInchEarnDebtSwapAdapter \
  --rpc-url "$URL" --private-key "$PK" --broadcast --json --constructor-args "$POOL" 2>/tmp/anvil-adapter.log | jq -r .deployedTo)
[ -n "$ADAPTER" ] && [ "$ADAPTER" != "null" ] || { tail -20 /tmp/anvil-adapter.log; fail "adapter deploy"; }
VUSDC=$(dtoken "$USDC")
VUSDT=$(dtoken "$USDT")
# Maker (U7) owes USDT; taker (U9) owes USDC. Each backed by 2 WBTC.
ensure_supply "$WBTC" 200000000 "$U7" "$U7_PK" || fail "stage17 maker WBTC supply"
ensure_borrow "$USDT" 50000000000 "$U7" "$U7_PK" || fail "stage17 maker USDT borrow"
ensure_supply "$WBTC" 200000000 "$U9" "$U9_PK" || fail "stage17 taker WBTC supply"
ensure_borrow "$USDC" 50000000000 "$U9" "$U9_PK" || fail "stage17 taker USDC borrow"
# Consent: maker will assume USDC, taker will assume USDT.
cast send "$VUSDC" "approveDelegation(address,uint256)" "$ADAPTER" 50000000000 --gas-limit "$GL" --rpc-url "$URL" --private-key "$U7_PK" >/dev/null
cast send "$VUSDT" "approveDelegation(address,uint256)" "$ADAPTER" 50000000000 --gas-limit "$GL" --rpc-url "$URL" --private-key "$U9_PK" >/dev/null
# Caller (maker U7) funds + approves the flashloan premium in both assets.
deal_erc20 "$USDC" "$U7" 200000000
deal_erc20 "$USDT" "$U7" 200000000
cast send "$USDC" "approve(address,uint256)" "$ADAPTER" "$MAXU" --gas-limit "$GL" --rpc-url "$URL" --private-key "$U7_PK" >/dev/null
cast send "$USDT" "approve(address,uint256)" "$ADAPTER" "$MAXU" --gas-limit "$GL" --rpc-url "$URL" --private-key "$U7_PK" >/dev/null
# Swap 49k of each 50k debt. The adapter requires each `repay` to return EXACTLY the flashed
# amount, so the swap amount must sit strictly below the (interest-grown) live debt; 49k leaves
# clear margin over the ~50000.00001 debt while still moving the bulk of the position. Gate the
# retry on the maker having ASSUMED USDC debt (scaled, index-immune).
SWAP=49000000000
retry 5 1 bash -c "cast send '$ADAPTER' 'swapDebt((address,address,address,uint256,address,uint256))' '($U7,$U9,$USDT,$SWAP,$USDC,$SWAP)' --gas-limit 20000000 --rpc-url '$URL' --private-key '$U7_PK' >/tmp/anvil-swap.log 2>&1; sb(){ cast call \$1 'scaledBalanceOf(address)(uint256)' \$2 --rpc-url '$URL' | awk '{print \$1}'; }; python3 -c \"import sys;sys.exit(0 if int(sys.argv[1])>0 else 1)\" \$(sb '$VUSDC' '$U7')" \
  || { tail -5 /tmp/anvil-swap.log; fail "P2P swapDebt did not settle"; }
# Both parties now hold the OPPOSITE asset's debt (index-immune scaled check).
bn_gt "$(sbal "$VUSDC" "$U7")" 0 || fail "maker did not assume USDC debt"
pass "maker assumed USDC debt (swapped from USDT)"
bn_gt "$(sbal "$VUSDT" "$U9")" 0 || fail "taker did not assume USDT debt"
pass "taker assumed USDT debt (atomic P2P swap settled on the live node)"

echo ""
echo "== ALL ANVIL INTEGRATION CHECKS PASSED =="
