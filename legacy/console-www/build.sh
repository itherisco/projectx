#!/bin/bash
# Build script for ITHERIS WASM Console
# 
# Usage: ./build.sh [--dev]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONSOLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../console" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pkg"
DEV_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dev)
            DEV_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Building ITHERIS WASM Console...${NC}"

# Check for wasm-pack
if ! command -v wasm-pack &> /dev/null; then
    echo -e "${RED}wasm-pack not found. Installing...${NC}"
    cargo install wasm-pack
fi

# Check for wasm32 target
if ! rustup target list --installed | grep -q "wasm32-unknown-unknown"; then
    echo -e "${YELLOW}Adding wasm32-unknown-unknown target...${NC}"
    rustup target add wasm32-unknown-unknown
fi

# Build the WASM module
echo -e "${GREEN}Compiling WASM module...${NC}"

if [ "$DEV_MODE" = true ]; then
    echo -e "${YELLOW}Development mode enabled${NC}"
    wasm-pack build "$CONSOLE_DIR" \
        --target web \
        --out-dir "$OUTPUT_DIR" \
        --dev \
        --features "wasm,grpc-web,console_error_panic_hook"
else
    wasm-pack build "$CONSOLE_DIR" \
        --target web \
        --out-dir "$OUTPUT_DIR" \
        --release \
        --features "wasm,grpc-web"
fi

# Verify output
if [ -f "$OUTPUT_DIR/itheris_console.js" ]; then
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "Output: $OUTPUT_DIR"
    echo ""
    echo "To serve the WASM console:"
    echo "  cd console-www"
    echo "  python3 -m http.server 8080"
else
    echo -e "${RED}Build failed - output files not found${NC}"
    exit 1
fi
