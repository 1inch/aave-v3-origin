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

cd "$(git rev-parse --show-toplevel)"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"; pass "$3"; }

echo "== starting anvil (fork of mainnet) =="
anvil --fork-url "$RPC" --port "$PORT" --auto-impersonate --silent &
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
cast send "$GATEWAY" "depositETH(address,address,uint16)" "$POOL" "$SENDER" 0 --value 1ether --rpc-url "$URL" --private-key "$PK" >/dev/null
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
cast send "$VWETH" 'setTransferable(bool)' true --from "$DAO" --unlocked --rpc-url "$URL" >/dev/null \
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

for who_pk in "$BORROWER_PK" "$RECEIVER_PK"; do
  cast send "$WETH" "deposit()" --value 10ether --rpc-url "$URL" --private-key "$who_pk" >/dev/null
  cast send "$WETH" "approve(address,uint256)" "$POOL" "$(cast max-uint)" --rpc-url "$URL" --private-key "$who_pk" >/dev/null
  FROM=$(cast wallet address --private-key "$who_pk")
  cast send "$POOL" "supply(address,uint256,address,uint16)" "$WETH" 10ether "$FROM" 0 --rpc-url "$URL" --private-key "$who_pk" >/dev/null
done
cast send "$POOL" "borrow(address,uint256,uint256,uint16,address)" "$WETH" 3ether 2 0 "$BORROWER" --rpc-url "$URL" --private-key "$BORROWER_PK" >/dev/null
pass "borrower supplied 10 WETH and borrowed 3 WETH"

# Receiver consents to take on 2 WETH of debt, borrower pushes it over.
cast send "$VWETH" "credit(address,uint256)" "$BORROWER" 2ether --rpc-url "$URL" --private-key "$RECEIVER_PK" >/dev/null
cast send "$VWETH" "transfer(address,uint256)" "$RECEIVER" 2ether --rpc-url "$URL" --private-key "$BORROWER_PK" >/dev/null

RCV_DEBT=$(cast call "$VWETH" "balanceOf(address)(uint256)" "$RECEIVER" --rpc-url "$URL" | awk '{print $1}')
BRW_DEBT=$(cast call "$VWETH" "balanceOf(address)(uint256)" "$BORROWER" --rpc-url "$URL" | awk '{print $1}')
[ "$RCV_DEBT" -ge 2000000000000000000 ] 2>/dev/null || fail "receiver debt after handoff ($RCV_DEBT)"
pass "receiver now owes ~2 WETH (1xdWETH=$RCV_DEBT)"
[ "$BRW_DEBT" -lt 1100000000000000000 ] 2>/dev/null || fail "borrower residual debt after handoff ($BRW_DEBT)"
pass "borrower residual debt ~1 WETH (1xdWETH=$BRW_DEBT)"

# Both parties must be healthy after the handoff (HF is field 6 of getUserAccountData).
for acct in "$BORROWER" "$RECEIVER"; do
  HF=$(cast call "$POOL" "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" "$acct" --rpc-url "$URL" | sed -n '6p' | awk '{print $1}')
  [ "$HF" -gt 1000000000000000000 ] 2>/dev/null || fail "unhealthy account $acct (hf=$HF)"
done
pass "both parties healthy after debt handoff"

echo ""
echo "== ALL ANVIL INTEGRATION CHECKS PASSED =="
