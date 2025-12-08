#!/bin/bash

# Upload ICRC-151 WASM to TokenFactory
WASM_FILE="./wasm/icrc151.wasm"

if [ ! -f "$WASM_FILE" ]; then
    echo "Error: WASM file not found at $WASM_FILE"
    echo "Please build ICRC-151 first and copy the WASM file"
    exit 1
fi

echo "Uploading ICRC-151 WASM to TokenFactory..."

# Convert WASM to hex and upload
dfx canister call marketfactory uploadIcrc151Wasm \
  "(blob \"$(cat $WASM_FILE | xxd -p | tr -d '\n')\")"

echo "✅ WASM uploaded successfully"