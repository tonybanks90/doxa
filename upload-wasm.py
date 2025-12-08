#!/usr/bin/env python3
import subprocess
import sys
import os

def upload_wasm(wasm_path, canister_name):
    print(f"📦 Reading WASM file: {wasm_path}")
    
    if not os.path.exists(wasm_path):
        print(f"❌ Error: WASM file not found at {wasm_path}")
        return False
    
    try:
        with open(wasm_path, 'rb') as f:
            wasm_bytes = f.read()
        
        total_size = len(wasm_bytes)
        print(f"📏 WASM size: {total_size:,} bytes")
        
        print(f"⬆️  Uploading WASM...", end=' ')
        
        # Format as escaped hex for candid blob: \00\01...
        # hex_data is like "cafebabe"
        # We need "\ca\fe\ba\be"
        hex_data = wasm_bytes.hex()
        escaped_hex = "".join([f"\\{hex_data[i:i+2]}" for i in range(0, len(hex_data), 2)])
        
        cmd = [
            'dfx',
            'canister',
            'call',
            canister_name,
            'uploadIcrc151Wasm',
            '--argument-file',
            '-'
        ]
        
        result = subprocess.run(cmd, input=f'(blob "{escaped_hex}")', capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"❌ Failed!")
            print(result.stderr)
            return False
        
        print("✅")
        
        # Verify
        print("\n🔍 Verifying upload...")
        verify_cmd = ['dfx', 'canister', 'call', canister_name, 'hasIcrc151Wasm']
        verify_result = subprocess.run(verify_cmd, capture_output=True, text=True)
        print(verify_result.stdout)
        
        if "(true)" in verify_result.stdout:
            print("✅ WASM successfully uploaded and verified!")
            return True
        else:
            print("❌ Verification failed!")
            return False
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    wasm_path = os.path.join(os.path.dirname(__file__), "wasm", "icrc151.wasm")
    canister_name = "marketfactory"
    
    if len(sys.argv) > 1:
        wasm_path = sys.argv[1]
    if len(sys.argv) > 2:
        canister_name = sys.argv[2]
    
    print("=" * 60)
    print("ICRC-151 WASM Upload")
    print("=" * 60)
    
    success = upload_wasm(wasm_path, canister_name)
    
    print("=" * 60)
    if success:
        print("✅ SUCCESS: WASM uploaded successfully!")
    else:
        print("❌ FAILED: WASM upload failed!")
    print("=" * 60)
    
    sys.exit(0 if success else 1)
