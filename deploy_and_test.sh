#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Doxa Prediction Markets - Full Deployment and Test${NC}"
echo "========================================================"

# Configuration
NETWORK="local"
IDENTITY="default"

print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# ============================================
# STEP 1: Deploy Core Canisters
# ============================================
print_info "Deploying core canisters..."

dfx deploy marketfactory --network $NETWORK
dfx deploy vault --network $NETWORK
dfx deploy markettrade --network $NETWORK

print_status "Core canisters deployed"

# Get canister IDs
FACTORY_ID=$(dfx canister id marketfactory --network $NETWORK)
VAULT_ID=$(dfx canister id vault --network $NETWORK)
MARKETS_ID=$(dfx canister id markettrade --network $NETWORK)

echo "    MarketFactory: $FACTORY_ID"
echo "    Vault:         $VAULT_ID"
echo "    MarkeTrade:    $MARKETS_ID"

# ============================================
# STEP 2: Upload ICRC-151 WASM using Python script
# ============================================
print_info "Uploading ICRC-151 WASM to MarketFactory..."

python3 upload-wasm.py ./wasm/icrc151.wasm marketfactory

print_status "ICRC-151 WASM uploaded"

# ============================================
# STEP 3: Set up ALL inter-canister connections
# ============================================
print_info "Setting up inter-canister connections..."

# 1. Set Markets canister in Factory
print_info "Setting Markets canister in Factory..."
dfx canister call marketfactory setMarketsCanister "(principal \"$MARKETS_ID\")" --network $NETWORK

# 2. Set TokenFactory in MarkeTrade
print_info "Setting TokenFactory in MarkeTrade..."
dfx canister call markettrade setTokenFactory "(principal \"$FACTORY_ID\")" --network $NETWORK

# 3. Set Vault in MarkeTrade
print_info "Setting Vault in MarkeTrade..."
dfx canister call markettrade setVaultCanister "(principal \"$VAULT_ID\")" --network $NETWORK

# 4. Initialize Vault with Markets canister (use a dummy ledger for now if no ckBTC)
print_info "Initializing Vault with Markets canister..."
# We'll use a placeholder for ckBTC ledger - the vault initialize takes markets + ledger
CKBTC_LEDGER="ryjl3-tyaaa-aaaaa-aaaba-cai"  # Standard ckBTC ledger principal
dfx canister call vault initialize "(principal \"$MARKETS_ID\", principal \"$CKBTC_LEDGER\")" --network $NETWORK || true

print_status "Inter-canister connections established"

# ============================================
# STEP 4: Create Binary Market (from test_market_creation.sh)
# ============================================
print_info "Testing market creation (from test_market_creation.sh)..."

# Calculate timestamps (nanoseconds) - exactly as in test_market_creation.sh
NOW=$(date +%s)
CLOSE_TIME=$(( ($NOW + 3600) * 1000000000 ))
EXPIRATION_TIME=$(( ($NOW + 7200) * 1000000000 ))

echo "Close Time: $CLOSE_TIME"
echo "Expiration Time: $EXPIRATION_TIME"

echo ""
echo -e "${BLUE}------------------------------------------------${NC}"
echo -e "${BLUE}Creating Binary Market${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"

dfx canister call marketfactory createBinaryMarket "(
  record {
    title = \"Will Bitcoin hit \$100k by 2025?\";
    description = \"Prediction market for Bitcoin price.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"https://cryptologos.cc/logos/bitcoin-btc-logo.png\" };
    tags = vec { variant { Crypto }; variant { Technology } };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://coingecko.com\";
    resolutionDescription = \"Price on CoinGecko at expiration.\";
  }
)"

print_status "Binary Market created"

# ============================================
# STEP 5: Get Market Info
# ============================================
echo ""
echo -e "${BLUE}------------------------------------------------${NC}"
echo -e "${BLUE}Getting Market Info${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"

print_info "Getting market details from MarkeTrade..."
dfx canister call markettrade getMarket "(1:nat)" --network $NETWORK || \
  print_warning "getMarket failed"

print_info "Getting market prices..."
dfx canister call markettrade getMarketPrice "(1:nat, variant { Binary = variant { YES } })" --network $NETWORK || \
  print_warning "getMarketPrice failed"

# ============================================
# STEP 6: Test Buy Tokens
# ============================================
echo ""
echo -e "${BLUE}------------------------------------------------${NC}"
echo -e "${BLUE}Testing Token Purchase${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"

CALLER_PRINCIPAL=$(dfx identity get-principal)
print_info "Caller principal: $CALLER_PRINCIPAL"

print_info "Attempting to buy YES tokens..."
dfx canister call markettrade buyTokens "(1:nat, variant { Binary = variant { YES } }, 1000:nat64, 0.5:float64)" \
  --network $NETWORK || print_warning "buyTokens failed"

# ============================================
# Summary
# ============================================
echo ""
echo "========================================================"
print_status "Deployment and Test Complete! 🚀"
echo "========================================================"
echo ""
echo "Deployed Canisters:"
echo "  - MarketFactory: $FACTORY_ID"
echo "  - Vault:         $VAULT_ID"
echo "  - MarkeTrade:    $MARKETS_ID"
echo ""