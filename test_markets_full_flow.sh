#!/bin/bash
set -e

# Helpers
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_status() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }

NETWORK="local"
VAULT_ID=$(dfx canister id vault --network $NETWORK)
MARKETTRADE_ID=$(dfx canister id markettrade --network $NETWORK)

# ==============================================================================
# 1. SETUP
# ==============================================================================
print_info "Setting up..."

# Identities
dfx identity use default
RESOLVER=$(dfx identity get-principal)
print_info "Resolver: $RESOLVER"

dfx identity new trader_winner --storage-mode=plaintext 2>/dev/null || true
TRADER_WINNER=$(dfx identity get-principal --identity trader_winner)
print_info "Winner: $TRADER_WINNER"

dfx identity new trader_loser --storage-mode=plaintext 2>/dev/null || true
TRADER_LOSER=$(dfx identity get-principal --identity trader_loser)
print_info "Loser: $TRADER_LOSER"

# Top up Factory
print_info "Topping up factory..."
dfx canister deposit-cycles 3000000000000 marketfactory --network $NETWORK

# Fund Traders (ckBTC)
print_info "Funding traders..."
dfx identity use testuser
FUND_AMT=100000000 # 100M sats
dfx canister call ckbtc_ledger icrc1_transfer "(record { to=record{owner=principal\"$TRADER_WINNER\";subaccount=null}; amount=$FUND_AMT })" --network $NETWORK >/dev/null
dfx canister call ckbtc_ledger icrc1_transfer "(record { to=record{owner=principal\"$TRADER_LOSER\";subaccount=null}; amount=$FUND_AMT })" --network $NETWORK >/dev/null

# Approve Vault (for buying)
dfx identity use trader_winner
dfx canister call ckbtc_ledger icrc2_approve "(record { amount=1000000000; spender=record{owner=principal\"$VAULT_ID\";subaccount=null} })" --network $NETWORK >/dev/null

dfx identity use trader_loser
dfx canister call ckbtc_ledger icrc2_approve "(record { amount=1000000000; spender=record{owner=principal\"$VAULT_ID\";subaccount=null} })" --network $NETWORK >/dev/null


# Common Timings (Fast)
NOW=$(date +%s)
CLOSE=$(( ($NOW + 10) * 1000000000 ))
EXP=$(( ($NOW + 20) * 1000000000 ))

# ==============================================================================
# 2. BINARY MARKET
# ==============================================================================
echo ""
echo "----------------------------------------------------------------"
echo "TESTING BINARY MARKET"
echo "----------------------------------------------------------------"

dfx identity use default
RES=$(dfx canister call marketfactory createBinaryMarket "(record { 
    title=\"Binary Test\"; 
    description=\"Desc\"; 
    category=variant{Crypto}; 
    image=variant{ImageUrl=\"\"}; 
    tags=vec{}; 
    bettingCloseTime=$CLOSE; 
    expirationTime=$EXP; 
    resolutionLink=\"\"; 
    resolutionDescription=\"\" 
})" --network $NETWORK 2>&1)
MARKET_ID=$(echo "$RES" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
print_status "Created Binary Market #$MARKET_ID"

# Trade
# Winner buys YES
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Binary=variant{YES}}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_winner >/dev/null
# Loser buys NO
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Binary=variant{NO}}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_loser >/dev/null
print_status "Trades placed"

# Wait
print_info "Waiting for expiry..."
sleep 22

# Resolve (YES)
dfx identity use default
dfx canister call markettrade resolveMarket "($MARKET_ID:nat, variant{Binary=variant{Yes}})" --network $NETWORK >/dev/null
print_status "Resolved to YES"

# Approve Burn & Claim
MARKET_INFO=$(dfx canister call markettrade getMarket "($MARKET_ID:nat)" --network $NETWORK)
LEDGER=$(echo "$MARKET_INFO" | grep 'ledger =' | head -1 | cut -d'"' -f2)

# Claim
print_info "Claiming..."
CLAIM_RES=$(dfx canister call markettrade claimWinnings "($MARKET_ID:nat)" --network $NETWORK --identity trader_winner)
if echo "$CLAIM_RES" | grep -q "totalPayout"; then
    print_status "Winner Claimed: $(echo "$CLAIM_RES" | grep -o 'totalPayout = [0-9]*')"
else
    print_error "Claim failed: $CLAIM_RES"
fi

# ==============================================================================
# 3. MULTIPLE CHOICE MARKET
# ==============================================================================
echo ""
echo "----------------------------------------------------------------"
echo "TESTING MULTIPLE CHOICE MARKET"
echo "----------------------------------------------------------------"

NOW=$(date +%s)
CLOSE=$(( ($NOW + 10) * 1000000000 ))
EXP=$(( ($NOW + 20) * 1000000000 ))

dfx identity use default
RES=$(dfx canister call marketfactory createMultipleChoiceMarket "(record { 
    title=\"MC Test\"; 
    description=\"Desc\"; 
    category=variant{Crypto}; 
    image=variant{ImageUrl=\"\"}; 
    tags=vec{}; 
    outcomes=vec{\"A\";\"B\";\"C\"}; 
    bettingCloseTime=$CLOSE; 
    expirationTime=$EXP; 
    resolutionLink=\"\"; 
    resolutionDescription=\"\" 
})" --network $NETWORK 2>&1)
MARKET_ID=$(echo "$RES" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
print_status "Created MC Market #$MARKET_ID"

# Trade
# Winner buys A
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Outcome=\"A\"}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_winner >/dev/null
# Loser buys B
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Outcome=\"B\"}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_loser >/dev/null
print_status "Trades placed"

# Wait
print_info "Waiting for expiry..."
sleep 22

# Resolve (A)
dfx identity use default
dfx canister call markettrade resolveMarket "($MARKET_ID:nat, variant{MultipleChoice=\"A\"})" --network $NETWORK >/dev/null
print_status "Resolved to A"

# Approve Burn & Claim
MARKET_INFO=$(dfx canister call markettrade getMarket "($MARKET_ID:nat)" --network $NETWORK)
LEDGER=$(echo "$MARKET_INFO" | grep 'ledger =' | head -1 | cut -d'"' -f2)



print_info "Claiming..."
CLAIM_RES=$(dfx canister call markettrade claimWinnings "($MARKET_ID:nat)" --network $NETWORK --identity trader_winner)
if echo "$CLAIM_RES" | grep -q "totalPayout"; then
    print_status "Winner Claimed: $(echo "$CLAIM_RES" | grep -o 'totalPayout = [0-9]*')"
else
    print_error "Claim failed: $CLAIM_RES"
fi

# ==============================================================================
# 4. COMPOUND MARKET
# ==============================================================================
echo ""
echo "----------------------------------------------------------------"
echo "TESTING COMPOUND MARKET"
echo "----------------------------------------------------------------"

NOW=$(date +%s)
CLOSE=$(( ($NOW + 10) * 1000000000 ))
EXP=$(( ($NOW + 20) * 1000000000 ))

dfx identity use default
RES=$(dfx canister call marketfactory createCompoundMarket "(record { 
    title=\"Compound Test\"; 
    description=\"Desc\"; 
    category=variant{Crypto}; 
    image=variant{ImageUrl=\"\"}; 
    tags=vec{}; 
    subjects=vec{\"Sub1\";\"Sub2\"}; 
    bettingCloseTime=$CLOSE; 
    expirationTime=$EXP; 
    resolutionLink=\"\"; 
    resolutionDescription=\"\" 
})" --network $NETWORK 2>&1)
MARKET_ID=$(echo "$RES" | grep -o 'ok = [0-9]*' | cut -d' ' -f3)
print_status "Created Compound Market #$MARKET_ID"

# Trade
# Winner buys Sub1-YES
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Subject=record{\"Sub1\";variant{YES}}}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_winner >/dev/null
# Loser buys Sub1-NO
dfx canister call markettrade buyTokens "($MARKET_ID:nat, variant{Subject=record{\"Sub1\";variant{NO}}}, 10000000:nat64, 100000.0:float64)" --network $NETWORK --identity trader_loser >/dev/null
print_status "Trades placed"

# Wait
print_info "Waiting for expiry..."
sleep 22

# Resolve (Sub1=YES, Sub2=YES)
dfx identity use default
# Note resolving ALL subjects is required? Or can we resolve partially?
# The type is `[(Text, BinaryOutcome)]`. Usually implies all.
dfx canister call markettrade resolveMarket "($MARKET_ID:nat, variant{Compound=vec{ record{\"Sub1\";variant{Yes}}; record{\"Sub2\";variant{Yes}} }})" --network $NETWORK >/dev/null
print_status "Resolved"

# Approve Burn & Claim
MARKET_INFO=$(dfx canister call markettrade getMarket "($MARKET_ID:nat)" --network $NETWORK)
LEDGER=$(echo "$MARKET_INFO" | grep 'ledger =' | head -1 | cut -d'"' -f2)



print_info "Claiming..."
CLAIM_RES=$(dfx canister call markettrade claimWinnings "($MARKET_ID:nat)" --network $NETWORK --identity trader_winner)
if echo "$CLAIM_RES" | grep -q "totalPayout"; then
    print_status "Winner Claimed: $(echo "$CLAIM_RES" | grep -o 'totalPayout = [0-9]*')"
else
    print_error "Claim failed: $CLAIM_RES"
fi

echo ""
print_status "All tests complete!"
