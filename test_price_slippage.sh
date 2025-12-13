#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛡️ Price Slippage Test - MaxPrice Protection${NC}"
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
# CREATE MARKET
# ============================================
print_info "Creating Binary Market for Slippage Test..."

BINARY_RESULT=$(dfx canister call marketfactory createBinaryMarket "(
  record {
    title = \"Slippage Test Market\";
    description = \"Testing max price protection.\";
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
dfx identity new trader_slippage --storage-mode=plaintext 2>/dev/null || true
dfx identity use trader_slippage
TRADER_PRINCIPAL=$(dfx identity get-principal)

# Fund trader
dfx identity use testuser
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TRADER_PRINCIPAL\"; subaccount = null }; 
  amount = 1_000_000_000 
})" --network $NETWORK >/dev/null

dfx identity use trader_slippage
dfx canister call ckbtc_ledger icrc2_approve "(record { 
  amount = 1_000_000_000;
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null };
})" --network $NETWORK --identity trader_slippage >/dev/null

# ============================================
# SLIPPAGE TEST
# ============================================
echo ""
echo "Testing Slippage Protection"
echo "--------------------------------------------------------"

check_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($BINARY_ID:nat, variant { Binary = variant { YES } })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

P0=$(check_price)
echo "Initial Price: $P0 sats"

# TEST 1: SUCCESSFUL TRADE (High Max Price)
print_info "Test 1: Buy 10M sats with MaxPrice=100000 (Should Succeed)..."
RES1=$(dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)
if echo "$RES1" | grep -q "tokensReceived"; then
  print_status "Trade 1 Passed (Accepted)"
else
  print_error "Trade 1 Failed unexpectedly: $RES1"
fi

P1=$(check_price)
echo "New Price: $P1 sats"

# TEST 2: FAILED TRADE (Too Low Max Price)
# Try to buy with Limit = Current Price - 1 sat (Impossible if buying increases price)
# Actually, try Limit = P1 (Buying will push it > P1)
LIMIT_PRICE=$P1
print_info "Test 2: Buy 10M sats with MaxPrice=$LIMIT_PRICE (Should Fail due to slippage)..."
RES2=$(dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 10_000_000:nat64, $LIMIT_PRICE:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)

if echo "$RES2" | grep -q "Price slippage too high"; then
  print_status "Trade 2 Passed (Correctly Rejected: 'Price slippage too high')"
else
  if echo "$RES2" | grep -q "tokensReceived"; then
    print_error "Trade 2 FAILED: Transaction was accepted but should have been rejected!"
  else
    print_warning "Trade 2 Result unexpected: $RES2"
  fi
fi

# ============================================
# CREATE MULTIPLE CHOICE MARKET (SLIPPAGE)
# ============================================
print_info "Creating Multiple Choice Market for Slippage..."

MC_RESULT=$(dfx canister call marketfactory createMultipleChoiceMarket "(
  record {
    title = \"Slippage Test MC\";
    description = \"Testing MC slippage.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"\" };
    tags = vec {};
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"\";
    resolutionDescription = \"\";
    outcomes = vec { \"Alpha\"; \"Beta\"; \"Gamma\" };
  }
)" --network $NETWORK 2>&1)

if echo "$MC_RESULT" | grep -q "ok"; then
  MC_ID=$(echo "$MC_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "MC Market #$MC_ID created"
else
  print_error "MC Creation failed: $MC_RESULT"
  exit 1
fi

check_mc_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($MC_ID:nat, variant { Outcome = \"Alpha\" })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

MC_P0=$(check_mc_price)
echo "MC Initial Price: $MC_P0 sats"

# MC TEST 1: SUCCESSFUL TRADE
print_info "MC Test 1: Buy 10M sats Alpha with MaxPrice=100000 (Should Succeed)..."
MC_RES1=$(dfx canister call markettrade buyTokens "($MC_ID:nat, variant { Outcome = \"Alpha\" }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)
if echo "$MC_RES1" | grep -q "tokensReceived"; then
  print_status "MC Trade 1 Passed"
else
  print_error "MC Trade 1 Failed: $MC_RES1"
fi

MC_P1=$(check_mc_price)
echo "MC New Price: $MC_P1 sats"

# MC TEST 2: FAILED TRADE
MC_LIMIT=$MC_P1
print_info "MC Test 2: Buy 10M sats Alpha with MaxPrice=$MC_LIMIT (Should Fail)..."
MC_RES2=$(dfx canister call markettrade buyTokens "($MC_ID:nat, variant { Outcome = \"Alpha\" }, 10_000_000:nat64, $MC_LIMIT:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)

if echo "$MC_RES2" | grep -q "Price slippage too high"; then
  print_status "MC Trade 2 Passed (Correctly Rejected)"
else
  print_error "MC Trade 2 Failed (Was not rejected): $MC_RES2"
fi


# ============================================
# CREATE COMPOUND MARKET (SLIPPAGE)
# ============================================
print_info "Creating Compound Market for Slippage..."

CMP_RESULT=$(dfx canister call marketfactory createCompoundMarket "(
  record {
    title = \"Slippage Test Compound\";
    description = \"Testing Compound slippage.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"\" };
    tags = vec {};
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"\";
    resolutionDescription = \"\";
    subjects = vec { \"SubjectX\"; \"SubjectY\" };
  }
)" --network $NETWORK 2>&1)

if echo "$CMP_RESULT" | grep -q "ok"; then
  CMP_ID=$(echo "$CMP_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Compound Market #$CMP_ID created"
else
  print_error "Compound Creation failed: $CMP_RESULT"
  exit 1
fi

check_cmp_price() {
  local price_res=$(dfx canister call markettrade getMarketPrice "($CMP_ID:nat, variant { Subject = record { \"SubjectX\"; variant { YES } } })" --network $NETWORK 2>&1)
  echo "$price_res" | grep -o 'ok = [0-9.]*' | cut -d' ' -f3
}

CMP_P0=$(check_cmp_price)
echo "Compound Initial Price: $CMP_P0 sats"

# COMPOUND TEST 1: SUCCESSFUL TRADE
print_info "Compound Test 1: Buy 10M sats SubjectX YES with MaxPrice=100000 (Should Succeed)..."
CMP_RES1=$(dfx canister call markettrade buyTokens "($CMP_ID:nat, variant { Subject = record { \"SubjectX\"; variant { YES } } }, 10_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)
if echo "$CMP_RES1" | grep -q "tokensReceived"; then
  print_status "Compound Trade 1 Passed"
else
  print_error "Compound Trade 1 Failed: $CMP_RES1"
fi

CMP_P1=$(check_cmp_price)
echo "Compound New Price: $CMP_P1 sats"

# COMPOUND TEST 2: FAILED TRADE
CMP_LIMIT=$CMP_P1
print_info "Compound Test 2: Buy 10M sats SubjectX YES with MaxPrice=$CMP_LIMIT (Should Fail)..."
CMP_RES2=$(dfx canister call markettrade buyTokens "($CMP_ID:nat, variant { Subject = record { \"SubjectX\"; variant { YES } } }, 10_000_000:nat64, $CMP_LIMIT:float64)" --network $NETWORK --identity trader_slippage 2>&1 || true)

if echo "$CMP_RES2" | grep -q "Price slippage too high"; then
  print_status "Compound Trade 2 Passed (Correctly Rejected)"
else
  print_error "Compound Trade 2 Failed (Was not rejected): $CMP_RES2"
fi

# Reset
dfx identity use default
