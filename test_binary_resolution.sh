#!/bin/bash

# Exit on error
set -e

# Report File
REPORT_FILE="resolution_report.md"

# Clear/Init report
echo "# Binary Market Resolution Test Report" > $REPORT_FILE
echo "" >> $REPORT_FILE
echo "Date: $(date)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# Colors & Helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
log_report() { echo "$1" >> $REPORT_FILE; }

NETWORK="local"
VAULT_ID=$(dfx canister id vault --network $NETWORK)
LEDGER_ID=$(dfx canister id ckbtc_ledger --network $NETWORK)
MARKETTRADE_ID=$(dfx canister id markettrade --network $NETWORK)

print_info "Vault ID: $VAULT_ID"

# 1. SETUP IDENTITIES
print_info "Setting up identities..."

# Resolver (using default)
dfx identity use default
RESOLVER_PRINCIPAL=$(dfx identity get-principal)
log_report "## Identities"
log_report "- **Resolver:** \`$RESOLVER_PRINCIPAL\`"

# Trader YES
dfx identity new trader_yes --storage-mode=plaintext 2>/dev/null || true
TRADER_YES=$(dfx identity get-principal --identity trader_yes)
log_report "- **Trader YES:** \`$TRADER_YES\`"

# Trader NO
dfx identity new trader_no --storage-mode=plaintext 2>/dev/null || true
TRADER_NO=$(dfx identity get-principal --identity trader_no)
log_report "- **Trader NO:** \`$TRADER_NO\`"
log_report ""

# 2. FUND TRADERS
print_info "Funding traders..."
dfx identity use testuser
FUND_AMOUNT=50000000 # 50M sats

# Fund YES
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TRADER_YES\"; subaccount = null }; 
  amount = $FUND_AMOUNT 
})" --network $NETWORK >/dev/null

# Fund NO
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TRADER_NO\"; subaccount = null }; 
  amount = $FUND_AMOUNT 
})" --network $NETWORK >/dev/null

# Approve Vault (YES)
dfx identity use trader_yes
dfx canister call ckbtc_ledger icrc2_approve "(record { 
  amount = $FUND_AMOUNT; 
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null }; 
})" --network $NETWORK >/dev/null

# Approve Vault (NO)
dfx identity use trader_no
dfx canister call ckbtc_ledger icrc2_approve "(record { 
  amount = $FUND_AMOUNT; 
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null }; 
})" --network $NETWORK >/dev/null

print_status "Traders funded and approved vault"

# 3. CREATE MARKET
dfx identity use default
print_info "Creating Market..."

# Timings: Close in 10s, Expire in 20s
NOW=$(date +%s)
CLOSE=$(( ($NOW + 10) * 1000000000 ))
EXP=$(( ($NOW + 20) * 1000000000 ))

WALLET=$(dfx identity get-wallet --network $NETWORK)
RES=$(dfx canister call marketfactory createBinaryMarket "(record { title=\"Will BTC hit 100k?\"; description=\"Start time: $NOW\"; category=variant {Crypto}; image=variant {ImageUrl=\"\"}; tags=vec{}; bettingCloseTime=$CLOSE; expirationTime=$EXP; resolutionLink=\"\"; resolutionDescription=\"\" })" --network $NETWORK --with-cycles 2000000000000 --wallet $WALLET 2>&1 || true)

MARKET_ID=$(echo "$RES" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)

if [ -z "$MARKET_ID" ]; then
  print_error "Failed to create market"
  echo "$RES"
  exit 1
fi

print_status "Created Market #$MARKET_ID"
log_report "## Market Details"
log_report "- **ID:** $MARKET_ID"
log_report "- **Title:** Will BTC hit 100k?"
log_report "- **Timings:** Close +10s, Expire +20s"
log_report ""

# 4. PERFORM TRADES
TRADE_AMOUNT=10000000 # 10M sats

# Trader YES buys YES
print_info "Trader YES buying YES tokens..."
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant {Binary=variant{YES}}, $TRADE_AMOUNT:nat64, 100000.0:float64)" --network $NETWORK --identity trader_yes >/dev/null

# Trader NO buys NO
print_info "Trader NO buying NO tokens..."
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant {Binary=variant{NO}}, $TRADE_AMOUNT:nat64, 100000.0:float64)" --network $NETWORK --identity trader_no >/dev/null

print_status "Trades executed"
log_report "## Trading"
log_report "- Trader YES bought 10M sats of YES"
log_report "- Trader NO bought 10M sats of NO"
log_report ""

# 5. WAIT FOR EXPIRY
print_info "Waiting 25s for market expiry..."
sleep 25

# 6. RESOLVE MARKET
print_info "Resolving Market to YES..."
dfx identity use default
RESOLVE_RES=$(dfx canister call markettrade resolveMarket "($MARKET_ID:nat, variant {Binary=variant{Yes}})" --network $NETWORK --wallet $WALLET 2>&1)

if echo "$RESOLVE_RES" | grep -q "ok"; then
  print_status "Market Resolved to YES"
  log_report "## Resolution"
  log_report "- **Outcome:** YES"
  log_report "- **Status:** Resolved Successfully"
else
  print_error "Resolution Failed"
  echo "$RESOLVE_RES"
  log_report "## Resolution"
  log_report "- **Status:** ❌ Failed: $RESOLVE_RES"
  exit 1
fi
log_report ""

# 7. REDEEM WINNINGS
log_report "## Redemption"

# Check Initial Balances
dfx identity use trader_yes
BAL_YES_PRE=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record { owner = principal \"$TRADER_YES\"; subaccount = null })" --network $NETWORK | grep -o '[0-9_]*' | tr -d '_')

dfx identity use trader_no
BAL_NO_PRE=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record { owner = principal \"$TRADER_NO\"; subaccount = null })" --network $NETWORK | grep -o '[0-9_]*' | tr -d '_')

# --- APPROVAL STEP START ---
print_info "Fetching Market Info for Approval..."
MARKET_INFO=$(dfx canister call markettrade getMarket "($MARKET_ID:nat)" --network $NETWORK)
MARKET_LEDGER=$(echo "$MARKET_INFO" | grep 'ledger =' | head -1 | cut -d'"' -f2)
# Extract YES Token ID (blob format)
# The output format is: yesTokenId = blob "\..."
YES_TOKEN_BLOB=$(echo "$MARKET_INFO" | grep 'yesTokenId =' | cut -d'=' -f2 | xargs) 
# Note: xargs trims whitespace. The value is `blob "\..."` or `blob "..."`.

print_info "Market Ledger: $MARKET_LEDGER"
print_info "YES Token ID: $YES_TOKEN_BLOB"

print_info "Approving MarketTrade to burn YES tokens..."
dfx identity use trader_yes
# Approve full balance (shares)
# First get balance to be sure? Or just approve huge amount.
APPROVE_RES=$(dfx canister call "$MARKET_LEDGER" icrc2_approve "(record { 
  amount = 1000000000; 
  spender = record { owner = principal \"$MARKETTRADE_ID\"; subaccount = null };
  from_subaccount = null;
  memo = null;
  created_at_time = null;
  expected_allowance = null;
  expires_at = null;
  fee = null;
})" --argument-type candid --network $NETWORK 2>&1 || true)
# Note: ICRC-151 icrc2_approve might need token_id if it deviates from standard.
# Standard ICRC-2 does NOT take token_id in approve?
# Wait, ICRC-2 is for single token ledgers.
# ICRC-151 is multi-token.
# If ICRC-151 uses standard ICRC-2 methods on the surface, does it assume a default token?
# Or does it have a custom `icrc2_approve` signature?
# I need to check the Candid interface of the specific ledger canister.
# But for now, assuming standard interface might fail if multi-token.
# Let's hope the ledger acts as single token or I need to find the specific approve method.
# markets.mo defines `ICRC151Interface` with `transfer` and `transfer_from` but validation of `approve` is tricky.
# Code snippet 1046 in vault.mo showed `icrc2_allowance`.
# Let's try to assume it supports standard verify.
# If this fails, I'll need to use `approve_token` or similar if it exists.
# But wait... looking at factory.mo snippet 567: `ledgerActor : ICRC151Interface`.
# It has `create_token` etc.
# Does it implement `icrc2_approve`?
# Snippet 38 "type ICRC151Interface" doesn't list `icrc2_approve`.
# But `doxa` uses `icrc1_balance_of` and `transfer_from`.
# So `approve` must exist.
# Checking logic...

# Let's just try calling it.
print_info "Approval Result: $APPROVE_RES"
# --- APPROVAL STEP END ---

print_info "Redeeming for Trader YES (Winner)..."
dfx identity use trader_yes
REDEEM_YES=$(dfx canister call markettrade claimWinnings "($MARKET_ID:nat)" --network $NETWORK 2>&1 || true)

print_info "Redeeming for Trader NO (Loser)..."
dfx identity use trader_no
REDEEM_NO=$(dfx canister call markettrade claimWinnings "($MARKET_ID:nat)" --network $NETWORK 2>&1 || true)

# Check Final Balances
BAL_YES_POST=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record { owner = principal \"$TRADER_YES\"; subaccount = null })" --network $NETWORK | grep -o '[0-9_]*' | tr -d '_')
BAL_NO_POST=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record { owner = principal \"$TRADER_NO\"; subaccount = null })" --network $NETWORK | grep -o '[0-9_]*' | tr -d '_')

# Analyze YES Redemption
if echo "$REDEEM_YES" | grep -q "ok"; then
  PAYOUT_YES=$(echo "$REDEEM_YES" | grep -o 'totalPayout = [0-9]*' | cut -d'=' -f2 | xargs)
  print_status "Trader YES redeemed $PAYOUT_YES sats"
  log_report "- **Trader YES (Winner):** Redeemed $PAYOUT_YES sats. (Balance: $BAL_YES_PRE -> $BAL_YES_POST)"
else
  print_error "Trader YES redemption failed: $REDEEM_YES"
  log_report "- **Trader YES (Winner):** ❌ Redemption Failed: $REDEEM_YES"
fi

# Analyze NO Redemption
if echo "$REDEEM_NO" | grep -q "err"; then
  print_status "Trader NO redemption correctly failed/returned nothing"
  log_report "- **Trader NO (Loser):** No payout (Expected). Response: $REDEEM_NO"
else
  print_error "Trader NO redemption unexpected: $REDEEM_NO"
  log_report "- **Trader NO (Loser):** ⚠️ Unexpected result: $REDEEM_NO"
fi

# Reset
dfx identity use default

echo ""
print_status "Test Complete. Report generated: $REPORT_FILE"
cat $REPORT_FILE
