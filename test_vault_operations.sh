#!/bin/bash

# Exit on error
set -e

# Report File
REPORT_FILE="vault_operations_report.md"

# Clear report
echo "# Vault Operations Verification Report" > $REPORT_FILE
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

print_info "Vault ID: $VAULT_ID"
print_info "Ledger ID: $LEDGER_ID"

log_report "## Setup"
log_report "- **Vault Canister:** \`$VAULT_ID\`"
log_report "- **Ledger Canister:** \`$LEDGER_ID\`"
log_report ""

# Setup Trader
print_info "Setting up 'trader_vault'..."
dfx identity new trader_vault --storage-mode=plaintext 2>/dev/null || true
TRADER_PRINCIPAL=$(dfx identity get-principal --identity trader_vault) # Get principal without switching yet

# Fund Trader
dfx identity use testuser
dfx canister call ckbtc_ledger icrc1_transfer "(record {
  to = record { owner = principal \"$TRADER_PRINCIPAL\"; subaccount = null };
  amount = 200_000_000
})" --network $NETWORK >/dev/null

# Approve Vault
dfx identity use trader_vault
dfx canister call ckbtc_ledger icrc2_approve "(record {
  amount = 200_000_000;
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null };
})" --network $NETWORK >/dev/null

log_report "## Trader Setup"
log_report "- **Trader Principal:** \`$TRADER_PRINCIPAL\`"
log_report "- **Initial Funding:** 200,000,000 sats"
log_report ""

# Switch back to default for creation
dfx identity use default

# Create Market
print_info "Creating Market..."
CLOSE=$(( ($(date +%s) + 3600) * 1000000000 ))
EXP=$(( ($(date +%s) + 7200) * 1000000000 ))

RES=$(dfx canister call marketfactory createBinaryMarket "(record {
  title=\"Vault Test\"; description=\"Testing Balances\"; category=variant {Crypto}; image=variant {ImageUrl=\"\"}; tags=vec{}; bettingCloseTime=$CLOSE; expirationTime=$EXP; resolutionLink=\"\"; resolutionDescription=\"\"
})" --network $NETWORK --with-cycles 2000000000000 2>&1)

MARKET_ID=$(echo "$RES" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)

if [ -z "$MARKET_ID" ]; then
  print_error "Failed to create market. Response:"
  echo "$RES"
  exit 1
fi

print_status "Created Market #$MARKET_ID"

# Construct Subaccount VEC
# Market ID to 4 bytes
B0=$(( ($MARKET_ID >> 24) & 0xFF ))
B1=$(( ($MARKET_ID >> 16) & 0xFF ))
B2=$(( ($MARKET_ID >> 8) & 0xFF ))
B3=$(( $MARKET_ID & 0xFF ))

# 28 zeros then 4 bytes (vec {0;0;...;B0;B1;B2;B3})
# Construct string "vec { 0; 0; ... }" - 28 times
ZEROS=""
for i in {1..28}; do ZEROS="${ZEROS}0; "; done
SUBCLIENT_VEC="vec { $ZEROS$B0; $B1; $B2; $B3 }"

print_info "Subaccount Vec for Market #$MARKET_ID: $SUBCLIENT_VEC"

# CHECK INITIAL BALANCE
print_info "Checking Initial Vault Balance..."
BAL_RES=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record {
  owner = principal \"$VAULT_ID\";
  subaccount = opt $SUBCLIENT_VEC
})" --network $NETWORK)

BAL_INIT=$(echo "$BAL_RES" | grep -o '[0-9_]*' | tr -d '_')
print_info "Initial Balance: $BAL_INIT"

log_report "## Pre-Trade Checks"
log_report "- **Market ID:** $MARKET_ID"
log_report "- **Vault Subaccount:** Derived from Market ID"
log_report "- **Initial Vault Balance:** $BAL_INIT sats"
log_report ""

# BUY TOKENS
AMOUNT=50000000 # 50M
print_info "Buying 50M sats..."
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant {Binary=variant{YES}}, $AMOUNT:nat64, 100000.0:float64)" --network $NETWORK --identity trader_vault >/dev/null

# CHECK FINAL BALANCE
print_info "Checking Final Vault Balance..."
BAL_RES_FINAL=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record {
  owner = principal \"$VAULT_ID\";
  subaccount = opt $SUBCLIENT_VEC
})" --network $NETWORK)

BAL_FINAL=$(echo "$BAL_RES_FINAL" | grep -o '[0-9_]*' | tr -d '_')
print_info "Final Balance: $BAL_FINAL"

# Verify
EXPECTED=$(( $BAL_INIT + $AMOUNT ))

log_report "## Post-Trade Checks"
log_report "- **Trade Action:** Buy 50,000,000 sats (YES Tokens)"
log_report "- **Expected Vault Balance:** $EXPECTED sats"
log_report "- **Actual Vault Balance:** $BAL_FINAL sats"

if [ "$BAL_FINAL" -eq "$EXPECTED" ]; then
  print_status "Balance verified!"
  log_report "- **Status:** ✅ VERIFIED"
else
  print_error "Balance Mismatch!"
  log_report "- **Status:** ❌ FAILED (Mismatch)"
fi

# Reset
dfx identity use default

echo ""
print_status "Report generated: $REPORT_FILE"
cat $REPORT_FILE
