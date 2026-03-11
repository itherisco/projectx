#!/bin/bash
# Build script for cognitive-sandbox placeholder Wasm modules
# This script compiles the WAT files to binary WASM modules

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
BUILD_DIR="$SCRIPT_DIR/target/wasm"

echo "=== Building Cognitive Sandbox Wasm Modules ==="

# Check if wat2wasm is available
if ! command -v wat2wasm &> /dev/null; then
    echo "Error: wat2wasm not found. Install WABT (WebAssembly Binary Toolkit):"
    echo "  macOS: brew install wabt"
    echo "  Linux: sudo apt-get install wabt"
    echo "  Or build from source: https://github.com/WebAssembly/wabt"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Compile each WAT file
for wat_file in "$MODULES_DIR"/*.wat; do
    if [ -f "$wat_file" ]; then
        filename=$(basename "$wat_file" .wat)
        output_file="$BUILD_DIR/${filename}.wasm"
        echo "Compiling $filename.wat -> $output_file"
        wat2wasm "$wat_file" -o "$output_file"
    fi
done

echo ""
echo "=== Build Complete ==="
ls -la "$BUILD_DIR"
