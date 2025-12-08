Make it executable:
bashchmod +x scripts/upload-wasm.sh


# 1. Navigate to your projects directory
cd ~/projects  # or wherever you keep projects

# 2. Clone ICRC-151 (outside doxa)
git clone https://github.com/xfusion-dev/icrc-151.git
cd icrc-151

# 3. Build the ICRC-151 canister
dfx start --background
dfx build icrc151

# 4. The WASM file is now at:
# .dfx/local/canisters/icrc151/icrc151.wasm

# 5. Copy WASM to your Doxa project (optional but recommended)
cp .dfx/local/canisters/icrc151/icrc151.wasm ../doxa/wasm/icrc151.wasm

# 6. Now go to your Doxa project
cd ../doxa

# 7. Upload WASM to your TokenFactory
dfx canister call doxa_backend uploadIcrc151Wasm \
  "(blob \"$(cat wasm/icrc151.wasm | xxd -p | tr -d '\n')\")"