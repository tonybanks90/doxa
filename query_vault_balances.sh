#!/bin/bash

# Exit on error
set -e

# Report File
REPORT_FILE="vault_balances_report.md"

# Clear/Init report
echo "# Vault Balances Report" > $REPORT_FILE
echo "" >> $REPORT_FILE
echo "Date: $(date)" >> $REPORT_FILE
echo "" >> $REPORT_FILE
echo "| ID | Type | Status | Balance (sats) | Subaccount (Hex) | Title |" >> $REPORT_FILE
echo "|----|------|--------|----------------|------------------|-------|" >> $REPORT_FILE

# Colors & Helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_status() { echo -e "${GREEN}✅ $1${NC}"; }

NETWORK="local"
VAULT_ID=$(dfx canister id vault --network $NETWORK)
LEDGER_ID=$(dfx canister id ckbtc_ledger --network $NETWORK)
MARKETTRADE_ID=$(dfx canister id markettrade --network $NETWORK)

print_info "Vault ID: $VAULT_ID"
print_info "Ledger ID: $LEDGER_ID"

# Loop through potential market IDs (e.g., 1 to 40 based on recent creation history)
for MARKET_ID in {1..40}; do
  
  # Construct Subaccount VEC
  # Market ID to 4 bytes
  B0=$(( ($MARKET_ID >> 24) & 0xFF ))
  B1=$(( ($MARKET_ID >> 16) & 0xFF ))
  B2=$(( ($MARKET_ID >> 8) & 0xFF ))
  B3=$(( $MARKET_ID & 0xFF ))

  # Hex formatting for report
  SUB_HEX=$(printf "00000000000000000000000000000000000000000000000000000000%02x%02x%02x%02x" $B0 $B1 $B2 $B3)

  # 28 zeros then 4 bytes vector string for call
  ZEROS=""
  for i in {1..28}; do ZEROS="${ZEROS}0; "; done
  SUBCLIENT_VEC="vec { $ZEROS$B0; $B1; $B2; $B3 }"

  # CHECK BALANCE
  BAL_RES=$(dfx canister call ckbtc_ledger icrc1_balance_of "(record {
    owner = principal \"$VAULT_ID\";
    subaccount = opt $SUBCLIENT_VEC
  })" --network $NETWORK 2>/dev/null || echo "error")

  if [[ "$BAL_RES" == *"error"* ]]; then
    continue
  fi

  BAL_INIT=$(echo "$BAL_RES" | grep -o '[0-9_]*' | tr -d '_')

  # Parse Balance (default 0 if empty)
  if [ -z "$BAL_INIT" ]; then BAL_INIT=0; fi

  # If balance > 0, fetch market details to make the report useful
  if [ "$BAL_INIT" -gt "0" ]; then
    print_info "Found active balance for Market #$MARKET_ID: $BAL_INIT sats"
    
    # Get Market Details
    MARKET_RES=$(dfx canister call markettrade getMarket "($MARKET_ID:nat)" --network $NETWORK 2>&1)
    
    TITLE="Unknown"
    STATUS="Unknown"
    TYPE="Unknown"

    if echo "$MARKET_RES" | grep -q "ok"; then
      # Extract Title
      TITLE=$(echo "$MARKET_RES" | grep -o 'question = "[^"]*"' | cut -d'"' -f2)
      if [ -z "$TITLE" ]; then TITLE="Market #$MARKET_ID"; fi
      
      # Extract Type
      if echo "$MARKET_RES" | grep -q "marketType = variant { Binary }"; then TYPE="Binary"; fi
      if echo "$MARKET_RES" | grep -q "marketType = variant { MultipleChoice }"; then TYPE="MultipleChoice"; fi
      if echo "$MARKET_RES" | grep -q "marketType = variant { Compound }"; then TYPE="Compound"; fi
      
      # Check active status
      if echo "$MARKET_RES" | grep -q "active = true"; then
        STATUS="Active"
      else
        STATUS="Inactive"
      fi
    elif echo "$MARKET_RES" | grep -q "Market not found"; then
       STATUS="Not Found"
    fi

    echo "| $MARKET_ID | $TYPE | $STATUS | $BAL_INIT | \`$SUB_HEX\` | $TITLE |" >> $REPORT_FILE
  fi
done

print_status "Scan complete."
echo ""
echo "Summary:"
cat $REPORT_FILE
