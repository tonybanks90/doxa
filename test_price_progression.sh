#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📈 Price Progression Test - Bonding Curve Visualization${NC}"
echo "========================================================"

NETWORK="local"

print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Get canister IDs
MARKETS_ID=$(dfx canister id markettrade --network $NETWORK)
VAULT_ID=$(dfx canister id vault --network $NETWORK)

# Calculate timestamps
NOW=$(date +%s)
CLOSE_TIME=$(( ($NOW + 3600) * 1000000000 ))
EXPIRATION_TIME=$(( ($NOW + 7200) * 1000000000 ))

# ============================================
# CREATE BINARY MARKET
# ============================================
print_info "Creating Binary Market for Price Test..."

BINARY_RESULT=$(dfx canister call marketfactory createBinaryMarket "(
  record {
    title = \"Price Test Binary\";
    description = \"Testing bonding curve progression.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"\" };
    tags = vec {};
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"\";
    resolutionDescription = \"\";
  }
)" --network $NETWORK 2>&1)

if echo "$BINARY_RESULT" | grep -q "ok"; then
  BINARY_ID=$(echo "$BINARY_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Binary Market #$BINARY_ID created"
else
  print_error "Creation failed: $BINARY_RESULT"
  exit 1
fi

# ============================================
# SETUP TRADER
# ============================================
print_info "Setting up trader..."
dfx identity new trader_progression --storage-mode=plaintext 2>/dev/null || true
dfx identity use trader_progression
TRADER_PRINCIPAL=$(dfx identity get-principal)

# Fund trader
dfx identity use testuser
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TRADER_PRINCIPAL\"; subaccount = null }; 
  amount = 1_000_000_000 
})" --network $NETWORK >/dev/null

dfx identity use trader_progression
dfx canister call ckbtc_ledger icrc2_approve "(record { 
  amount = 1_000_000_000;
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null };
})" --network $NETWORK --identity trader_progression >/dev/null

# ============================================
# PROGRESSION TEST
# ============================================
echo ""
echo "Testing Price Progression on Binary Market #$BINARY_ID (YES Token)"
echo "--------------------------------------------------------"

check_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($BINARY_ID:nat, variant { Binary = variant { YES } })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

# Initial Price
P0=$(check_price)
echo "Initial Price: $P0 sats"

# Buy 1: 10M sats
print_info "Buying 10M sats..."
dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
P1=$(check_price)
echo "Price after 10M sats: $P1 sats"

# Buy 2: 50M sats
print_info "Buying 50M sats..."
dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 50_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
P2=$(check_price)
echo "Price after +50M sats: $P2 sats"

# Buy 3: 100M sats
print_info "Buying 100M sats..."
dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 100_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
P3=$(check_price)
echo "Price after +100M sats: $P3 sats"

echo ""
echo "Progression Summary:"
echo "Start: $P0"
echo "Step 1: $P1"
echo "Step 2: $P2"
echo "Step 3: $P3"

if (( $(echo "$P1 > $P0" | bc -l) )) && (( $(echo "$P2 > $P1" | bc -l) )); then
  print_status "Price increased as expected! Bonding curve working."
else
  print_warning "Price did not increase as expected."
fi

# ============================================
# CREATE MULTIPLE CHOICE MARKET
# ============================================
print_info "Creating Multiple Choice Market..."

MC_RESULT=$(dfx canister call marketfactory createMultipleChoiceMarket "(
  record {
    title = \"Price Test MC\";
    description = \"Testing MC bonding curve.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"\" };
    tags = vec {};
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"\";
    resolutionDescription = \"\";
    outcomes = vec { \"OptionA\"; \"OptionB\"; \"OptionC\" };
  }
)" --network $NETWORK 2>&1)

if echo "$MC_RESULT" | grep -q "ok"; then
  MC_ID=$(echo "$MC_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "MC Market #$MC_ID created"
else
  print_error "MC Creation failed: $MC_RESULT"
  exit 1
fi

echo ""
echo "Testing Price Progression on MC Market #$MC_ID (OptionA)"
echo "--------------------------------------------------------"

check_mc_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($MC_ID:nat, variant { Outcome = \"OptionA\" })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

MC_P0=$(check_mc_price)
echo "Initial Price: $MC_P0 sats"

print_info "Buying 10M sats OptionA..."
dfx canister call markettrade buyTokens "($MC_ID:nat, variant { Outcome = \"OptionA\" }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
MC_P1=$(check_mc_price)
echo "Price after 10M sats: $MC_P1 sats"

print_info "Buying 50M sats OptionA..."
dfx canister call markettrade buyTokens "($MC_ID:nat, variant { Outcome = \"OptionA\" }, 50_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
MC_P2=$(check_mc_price)
echo "Price after +50M sats: $MC_P2 sats"

if (( $(echo "$MC_P1 > $MC_P0" | bc -l) )) && (( $(echo "$MC_P2 > $MC_P1" | bc -l) )); then
  print_status "MC Price increased correctly."
else
  print_warning "MC Price check failed."
fi


# ============================================
# CREATE COMPOUND MARKET
# ============================================
print_info "Creating Compound Market..."

CMP_RESULT=$(dfx canister call marketfactory createCompoundMarket "(
  record {
    title = \"Price Test Compound\";
    description = \"Testing Compound bonding curve.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"\" };
    tags = vec {};
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"\";
    resolutionDescription = \"\";
    subjects = vec { \"TopicA\"; \"TopicB\" };
  }
)" --network $NETWORK 2>&1)

if echo "$CMP_RESULT" | grep -q "ok"; then
  CMP_ID=$(echo "$CMP_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Compound Market #$CMP_ID created"
else
  print_error "Compound Creation failed: $CMP_RESULT"
  exit 1
fi

echo ""
echo "Testing Price Progression on Compound Market #$CMP_ID (TopicA YES)"
echo "--------------------------------------------------------"

check_cmp_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($CMP_ID:nat, variant { Subject = record { \"TopicA\"; variant { YES } } })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

CPM_P0=$(check_cmp_price)
echo "Initial Price: $CPM_P0 sats"

print_info "Buying 10M sats TopicA YES..."
dfx canister call markettrade buyTokens "($CMP_ID:nat, variant { Subject = record { \"TopicA\"; variant { YES } } }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
CPM_P1=$(check_cmp_price)
echo "Price after 10M sats: $CPM_P1 sats"

print_info "Buying 50M sats TopicA YES..."
dfx canister call markettrade buyTokens "($CMP_ID:nat, variant { Subject = record { \"TopicA\"; variant { YES } } }, 50_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_progression >/dev/null
CPM_P2=$(check_cmp_price)
echo "Price after +50M sats: $CPM_P2 sats"

if (( $(echo "$CPM_P1 > $CPM_P0" | bc -l) )) && (( $(echo "$CPM_P2 > $CPM_P1" | bc -l) )); then
  print_status "Compound Price increased correctly."
else
  print_warning "Compound Price check failed."
fi

# Reset
dfx identity use default
