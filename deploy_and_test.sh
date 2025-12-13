#!/bin/bash
# Deploy and Test Script - Full binary market resolution lifecycle

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

NETWORK="local"

# ===== STEP 1: Clean Start =====
print_info "Stopping dfx and starting clean..."
dfx stop 2>/dev/null || true
dfx start --clean --background
sleep 3
print_status "DFX started with clean state"

# ===== STEP 2: Deploy Backend Canisters =====
print_info "Deploying backend canisters..."

# Get default principal for minting account
dfx identity use default
DEFAULT_PRINCIPAL=$(dfx identity get-principal)

# Deploy ckBTC ledger with init args
print_info "Deploying ckbtc_ledger..."
dfx deploy ckbtc_ledger --argument "(variant { Init = record { 
  minting_account = record { owner = principal \"$DEFAULT_PRINCIPAL\"; subaccount = null }; 
  initial_balances = vec {}; 
  transfer_fee = 10; 
  token_name = \"ckBTC Test\"; 
  token_symbol = \"ckBTC\"; 
  metadata = vec {}; 
  feature_flags = opt record { icrc2 = true };
  archive_options = record { 
    num_blocks_to_archive = 1000; 
    trigger_threshold = 500; 
    controller_id = principal \"$DEFAULT_PRINCIPAL\"; 
    max_message_size_bytes = null; 
    cycles_for_archive_creation = null; 
    node_max_memory_size_bytes = null; 
    max_transactions_per_response = null 
  } 
} })" --network $NETWORK --yes

print_info "Deploying vault..."
dfx deploy vault --network $NETWORK --yes

print_info "Deploying markettrade..."
dfx deploy markettrade --network $NETWORK --yes

print_info "Deploying marketfactory..."
dfx deploy marketfactory --network $NETWORK --yes

print_status "All backend canisters deployed"

# ===== STEP 3: Configure Canisters =====
print_info "Configuring canister relationships..."

VAULT_ID=$(dfx canister id vault --network $NETWORK)
MARKETTRADE_ID=$(dfx canister id markettrade --network $NETWORK)
MARKETFACTORY_ID=$(dfx canister id marketfactory --network $NETWORK)
LEDGER_ID=$(dfx canister id ckbtc_ledger --network $NETWORK)

# Configure vault using initialize
dfx canister call vault initialize "(principal \"$MARKETTRADE_ID\", principal \"$LEDGER_ID\")" --network $NETWORK

# Configure markettrade
dfx canister call markettrade setTokenFactory "(principal \"$MARKETFACTORY_ID\")" --network $NETWORK
dfx canister call markettrade setVaultCanister "(principal \"$VAULT_ID\")" --network $NETWORK

# Configure marketfactory  
dfx canister call marketfactory setMarketsCanister "(principal \"$MARKETTRADE_ID\")" --network $NETWORK

print_status "Canisters configured"

# Upload ICRC-151 WASM to factory
print_info "Uploading ICRC-151 WASM to factory..."
python3 upload-wasm.py
if [ $? -ne 0 ]; then
  print_error "Failed to upload WASM"
  exit 1
fi
print_status "WASM uploaded"

# ===== STEP 4: Fund Wallet & Top Up Factory =====
print_info "Fabricating cycles for market creation..."
dfx ledger fabricate-cycles --canister $(dfx identity get-wallet) --amount 1000 --network $NETWORK
dfx canister call marketfactory acceptCycles --with-cycles 5000000000000 --wallet $(dfx identity get-wallet) --network $NETWORK

# ===== STEP 5: Create Test Identity =====
print_info "Setting up test identity..."
dfx identity new testuser --storage-mode=plaintext 2>/dev/null || true

# Mint ckBTC to testuser
dfx identity use default
TESTUSER=$(dfx identity get-principal --identity testuser)
dfx canister call ckbtc_ledger icrc1_transfer "(record { 
  to = record { owner = principal \"$TESTUSER\"; subaccount = null }; 
  amount = 1000000000000 
})" --network $NETWORK

print_status "Test environment ready"

# ===== STEP 6: Run Resolution Test =====
print_info "Running binary resolution test..."
./test_binary_resolution.sh

print_status "Deploy and test complete!"