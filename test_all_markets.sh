#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎰 All Market Types - Creation and Trading Test${NC}"
echo "========================================================"
echo "Testing creation and trading for all market types:"
echo "  1. Binary Market (YES/NO)"
echo "  2. Multiple Choice Market (3+ outcomes)"
echo "  3. Compound Market (multiple subjects, each YES/NO)"
echo "========================================================"
echo ""

NETWORK="local"

print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Get canister IDs
FACTORY_ID=$(dfx canister id marketfactory --network $NETWORK)
MARKETS_ID=$(dfx canister id markettrade --network $NETWORK)
VAULT_ID=$(dfx canister id vault --network $NETWORK)

echo "Canisters:"
echo "  - Factory:    $FACTORY_ID"
echo "  - MarketTrade: $MARKETS_ID"
echo "  - Vault:      $VAULT_ID"
echo ""

# Calculate timestamps
NOW=$(date +%s)
CLOSE_TIME=$(( ($NOW + 3600) * 1000000000 ))
EXPIRATION_TIME=$(( ($NOW + 7200) * 1000000000 ))

# ============================================
# TOP UP FACTORY CYCLES
# ============================================
print_info "Topping up factory cycles for market creation..."
echo "  Each market needs ~0.85T cycles for ICRC-151 ledger"
echo "  Creating 3 markets = ~2.55T cycles needed"

# Top up 5T cycles to factory (enough for ~5 markets)
dfx canister deposit-cycles 5000000000000 marketfactory --network $NETWORK
print_status "Factory topped up with 5T cycles"
echo ""

# ============================================
# MARKET 1: Binary Market
# ============================================
echo -e "${MAGENTA}========================================================"
echo "MARKET 1: Binary Market (YES/NO)"
echo "========================================================${NC}"
echo ""

print_info "Creating Binary Market: 'Will ETH flip BTC by 2030?'"

BINARY_RESULT=$(dfx canister call marketfactory createBinaryMarket "(
  record {
    title = \"Will ETH flip BTC by 2030?\";
    description = \"Will Ethereum's market cap exceed Bitcoin's by end of 2030?\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"https://cryptologos.cc/logos/ethereum-eth-logo.png\" };
    tags = vec { variant { Crypto }; variant { Technology } };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://coingecko.com\";
    resolutionDescription = \"Market cap comparison on CoinGecko\";
  }
)" --network $NETWORK 2>&1)

if echo "$BINARY_RESULT" | grep -q "ok"; then
  BINARY_ID=$(echo "$BINARY_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Binary Market #$BINARY_ID created!"
else
  print_error "Binary Market creation failed: $BINARY_RESULT"
  BINARY_ID=""
fi

# ============================================
# MARKET 2: Multiple Choice Market
# ============================================
echo ""
echo -e "${CYAN}========================================================"
echo "MARKET 2: Multiple Choice Market"
echo "========================================================${NC}"
echo ""

print_info "Creating Multiple Choice Market: 'Which AI company will be most valuable in 2025?'"

MC_RESULT=$(dfx canister call marketfactory createMultipleChoiceMarket "(
  record {
    title = \"Which AI company will be most valuable in 2025?\";
    description = \"Which company will have the highest market cap at end of 2025?\";
    category = variant { AI };
    image = variant { ImageUrl = \"https://example.com/ai.png\" };
    tags = vec { variant { AI }; variant { Technology } };
    outcomes = vec { \"OpenAI\"; \"Anthropic\"; \"Google DeepMind\"; \"xAI\" };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://forbes.com\";
    resolutionDescription = \"Forbes company valuations\";
  }
)" --network $NETWORK 2>&1)

if echo "$MC_RESULT" | grep -q "ok"; then
  MC_ID=$(echo "$MC_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Multiple Choice Market #$MC_ID created!"
else
  print_error "Multiple Choice Market creation failed: $MC_RESULT"
  MC_ID=""
fi

# ============================================
# MARKET 3: Compound Market
# ============================================
echo ""
echo -e "${YELLOW}========================================================"
echo "MARKET 3: Compound Market (multiple subjects)"
echo "========================================================${NC}"
echo ""

print_info "Creating Compound Market: 'Super Bowl 2025 Predictions'"

COMPOUND_RESULT=$(dfx canister call marketfactory createCompoundMarket "(
  record {
    title = \"Super Bowl 2025 Predictions\";
    description = \"Multiple predictions about Super Bowl 2025\";
    category = variant { Sports };
    image = variant { ImageUrl = \"https://example.com/nfl.png\" };
    tags = vec { variant { Sports } };
    subjects = vec { \"ChiefsWin\"; \"Over50Points\"; \"MVPisQB\" };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://espn.com\";
    resolutionDescription = \"Official NFL results\";
  }
)" --network $NETWORK 2>&1)

if echo "$COMPOUND_RESULT" | grep -q "ok"; then
  COMPOUND_ID=$(echo "$COMPOUND_RESULT" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
  print_status "Compound Market #$COMPOUND_ID created!"
else
  print_error "Compound Market creation failed: $COMPOUND_RESULT"
  COMPOUND_ID=""
fi

# ============================================
# TRADING TESTS
# ============================================
echo ""
echo -e "${BLUE}========================================================"
echo "TRADING ON ALL MARKET TYPES"
echo "========================================================${NC}"
echo ""

# Setup clean trader identity (to avoid minter/approval issues)
print_info "Setting up trader identity..."
dfx identity new trader_final --storage-mode=plaintext || true
dfx identity use trader_final
TRADER_PRINCIPAL=$(dfx identity get-principal)
print_info "Trader Principal: $TRADER_PRINCIPAL"

# Fund trader from testuser (who has funds/is minter)
dfx identity use testuser
print_info "Funding trader..."
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TRADER_PRINCIPAL\"; subaccount = null }; 
  amount = 1_000_000_000 
})" --network $NETWORK

# Switch back to trader
dfx identity use trader_final

# Setup approval
print_info "Test user approving vault to spend ckBTC..."
dfx canister call ckbtc_ledger icrc2_approve "(record { 
  amount = 5_000_000_000;
  spender = record { owner = principal \"$VAULT_ID\"; subaccount = null };
})" --network $NETWORK --identity trader_final

# Binary Market Trades
if [ -n "$BINARY_ID" ]; then
  echo -e "${MAGENTA}Trading on Binary Market #$BINARY_ID${NC}"
  
  # Test 1: Buy YES tokens with 100M sats (1 ckBTC)
  print_info "Trade 1: Buying YES tokens with 100M sats (1 ckBTC)..."
  BUY_RESULT=$(dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { YES } }, 100_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_final 2>&1 || true)
  if echo "$BUY_RESULT" | grep -q "tokensReceived"; then
    SHARES=$(echo "$BUY_RESULT" | grep -o 'tokensReceived = [0-9.]*' | cut -d' ' -f3)
    print_status "Bought $SHARES YES shares"
  else
    print_warning "YES trade issue: $BUY_RESULT"
  fi
  
  print_info "Trade 3: Buying NO tokens with 75M sats..."
  BUY_RESULT=$(dfx canister call markettrade buyTokens "($BINARY_ID:nat, variant { Binary = variant { NO } }, 75_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_final 2>&1 || true)
  if echo "$BUY_RESULT" | grep -q "tokensReceived"; then
    SHARES=$(echo "$BUY_RESULT" | grep -o 'tokensReceived = [0-9.]*' | cut -d' ' -f3)
    print_status "Bought $SHARES NO shares"
  else
    print_warning "NO trade issue: $BUY_RESULT"
  fi
  echo ""
fi

# Multiple Choice Market Trades
if [ -n "$MC_ID" ]; then
  echo -e "${CYAN}Trading on Multiple Choice Market #$MC_ID${NC}"
  
  for OUTCOME in "OpenAI" "Anthropic" "Google_DeepMind" "xAI"; do
    print_info "Buying 5M sats of $OUTCOME tokens..."
    RESULT=$(dfx canister call markettrade buyTokens "($MC_ID:nat, variant { Outcome = \"$OUTCOME\" }, 5_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_final 2>&1 || true)
    if echo "$RESULT" | grep -q "tokensReceived"; then
      SHARES=$(echo "$RESULT" | grep -o 'tokensReceived = [0-9.]*' | cut -d' ' -f3)
      print_status "Bought $SHARES $OUTCOME shares"
    else
      print_warning "$OUTCOME trade issue"
    fi
  done
  echo ""
fi

# Compound Market Trades
if [ -n "$COMPOUND_ID" ]; then
  echo -e "${YELLOW}Trading on Compound Market #$COMPOUND_ID${NC}"
  
  for SUBJECT in "ChiefsWin" "Over50Points" "MVPisQB"; do
    print_info "Buying 5M sats of $SUBJECT YES tokens..."
    RESULT=$(dfx canister call markettrade buyTokens "($COMPOUND_ID:nat, variant { Subject = record { \"$SUBJECT\"; variant { YES } } }, 5_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_final 2>&1 || true)
    if echo "$RESULT" | grep -q "tokensReceived"; then
      SHARES=$(echo "$RESULT" | grep -o 'tokensReceived = [0-9.]*' | cut -d' ' -f3)
      print_status "Bought $SHARES $SUBJECT-YES shares"
    else
      print_warning "$SUBJECT YES trade issue"
    fi
    
    print_info "Buying 5M sats of $SUBJECT NO tokens..."
    RESULT=$(dfx canister call markettrade buyTokens "($COMPOUND_ID:nat, variant { Subject = record { \"$SUBJECT\"; variant { NO } } }, 5_000_000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_final 2>&1 || true)
    if echo "$RESULT" | grep -q "tokensReceived"; then
      SHARES=$(echo "$RESULT" | grep -o 'tokensReceived = [0-9.]*' | cut -d' ' -f3)
      print_status "Bought $SHARES $SUBJECT-NO shares"
    else
      print_warning "$SUBJECT NO trade issue"
    fi
  done
  echo ""
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo "========================================================"
echo -e "${BLUE}📊 MARKET SUMMARY${NC}"
echo "========================================================"
echo ""

# Get market info
for ((i=1; i<=3; i++)); do
  print_info "Market #$i state:"
  dfx canister call markettrade getMarket "($i:nat)" --network $NETWORK 2>&1 | head -20
  echo ""
done

# Switch back
dfx identity use default

echo "========================================================"
print_status "All Market Types Test Complete!"
echo "========================================================"
echo ""
echo "Created Markets:"
[ -n "$BINARY_ID" ] && echo "  - Binary Market #$BINARY_ID (YES/NO)"
[ -n "$MC_ID" ] && echo "  - Multiple Choice Market #$MC_ID (4 outcomes)"
[ -n "$COMPOUND_ID" ] && echo "  - Compound Market #$COMPOUND_ID (3 subjects)"
echo ""
