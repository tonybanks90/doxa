#!/bin/bash

WASM_FILE="wasm/icrc151.wasm"
CANISTER="marketfactory"

echo "📦 Preparing WASM file..."

if [ ! -f "$WASM_FILE" ]; then
    echo "❌ Error: WASM file not found at $WASM_FILE"
    exit 1
fi

# Get file size
FILE_SIZE=$(wc -c < "$WASM_FILE")
echo "📏 WASM file size: $FILE_SIZE bytes"

# Convert to hex without newlines
echo "🔄 Converting WASM to hex..."
HEX_DATA=$(xxd -p "$WASM_FILE" | tr -d '\n')

# Create a temporary file with the call
echo "📝 Creating upload command..."
cat > /tmp/upload_wasm.sh << EOF
dfx canister call $CANISTER uploadIcrc151Wasm "(blob \"$HEX_DATA\")"
EOF

echo "⬆️  Uploading WASM..."
bash /tmp/upload_wasm.sh

# Clean up
rm /tmp/upload_wasm.sh

echo "✅ Upload complete!"
echo "Verifying..."
dfx canister call $CANISTER hasIcrc151Wasm