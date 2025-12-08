#!/bin/bash

# Exit on error
set -e

echo "Starting Doxa deployment..."

# Check if WASM exists
if [ ! -f "wasm/icrc151.wasm" ]; then
    echo "Error: wasm/icrc151.wasm not found!"
    echo "Please build icrc-151 and copy the WASM to wasm/icrc151.wasm"
    exit 1
fi

# Start dfx if not running
if ! dfx ping > /dev/null 2>&1; then
    echo "Starting dfx..."
    dfx start --background
else
    echo "dfx is already running."
fi

# Deploy canisters
echo "Deploying canisters..."
dfx deploy

# Upload WASM to marketfactory
echo "Uploading ICRC-151 WASM to marketfactory..."
# Using xxd and tr to convert binary to hex string for blob argument
# Note: The 'blob' type in candid expects a sequence of bytes. 
# The string representation for blob in dfx argument is usually quoted string with hex escapes or just a hex string if using some tools, 
# but dfx expects `blob "..."` where ... is the string with \xx escapes.
# Actually, a safer way for large files is often file argument if supported, but here we use the command substitution method.
# However, passing large blobs via command line can be tricky.
# Let's try the method from usecommands.md: "(blob \"$(cat wasm/icrc151.wasm | xxd -p | tr -d '\n')\")"
# But wait, `xxd -p` produces hex. `blob "..."` expects text. 
# `blob "\CA\FE\BA\BE"` format.
# `xxd -p` gives `cafebabe`.
# We need to convert `cafebabe` to `\ca\fe\ba\be`.
# Or use `file` argument if `dfx` supports it for blob? No, standard `dfx canister call` doesn't directly support file path for blob arg easily without tools.
# BUT, `usecommands.md` had: `"(blob \"$(cat wasm/icrc151.wasm | xxd -p | tr -d '\n')\")"`
# This looks like it treats the hex string as the blob content? No, that would be a text argument.
# If the candid type is `Blob`, dfx expects `blob "\xx\xx..."`.
# Let's check `usecommands.md` again.
# `dfx canister call doxa_backend uploadIcrc151Wasm "(blob \"$(cat wasm/icrc151.wasm | xxd -p | tr -d '\n')\")"`
# If I run this, `dfx` might interpret the hex string as the blob data if it's not escaped? 
# Actually, `dfx` supports hex string for blob if prefixed?
# Let's stick to the `usecommands.md` suggestion but verify if it works. 
# If `xxd -p` outputs hex, and we pass it as a string to `blob`, it might be interpreted as raw bytes of the hex string, which is WRONG.
# The correct way to pass a file as blob in dfx is often:
# `dfx canister call canister method --argument-file arg.idl` or similar.
# OR `dfx canister call ... --type raw --argument ...`
# Let's try to trust `usecommands.md` for now, but I suspect it might be wrong if it just pastes hex.
# Wait, `blob "..."` in candid text format:
# "Text starting with blob is a blob literal. The string following blob must be enclosed in double quotes and uses the same escape sequences as text literals."
# So `blob "\00\01"` is 2 bytes. `blob "0001"` is 4 bytes (ASCII 0, 0, 0, 1).
# So `xxd -p` outputting `6162` (for 'ab') passed as `blob "6162"` would be 4 bytes.
# We want the actual bytes.
# A common trick is `blob "\<hex>"` but we need to insert `\` before every 2 chars.
# Let's do that.

HEX=$(cat wasm/icrc151.wasm | xxd -p | tr -d '\n' | sed 's/../\\&/g')
# This might be too long for command line argument limit.
# If it fails, we might need a python script or similar.
# `upload-wasm.py` exists in the root! Let's check that.

if [ -f "upload-wasm.py" ]; then
    echo "Found upload-wasm.py, using it..."
    python3 upload-wasm.py
else
    echo "upload-wasm.py not found, attempting shell command (might fail for large files)..."
    # Fallback to the sed method if python script missing, but we see it in file list.
    dfx canister call marketfactory uploadIcrc151Wasm "(blob \"$HEX\")"
fi

echo "Deployment complete!"
