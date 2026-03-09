#!/bin/bash
#===============================================================================
# ITHERIS Daemon Startup Script
# 
# Starts the ITHERIS sovereign runtime daemon with Julia brain integration
#===============================================================================

# Trap SIGINT (Ctrl+C) and SIGTERM to clean up all background processes
trap 'echo "🛑 Shutting down ITHERIS stack..."; kill 0' SIGINT SIGTERM EXIT

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DAEMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/itheris-daemon"
DAEMON_BIN="$DAEMON_DIR/target/release/itheris-daemon"
LOG_FILE="$DAEMON_DIR/itheris-daemon.log"

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  ITHERIS Sovereign Runtime Launcher${NC}"
echo -e "${GREEN}===========================================${NC}"

# Check for Julia
if ! command -v julia &> /dev/null; then
    echo -e "${RED}ERROR: Julia not found in PATH${NC}"
    echo "Please install Julia 1.10+ and add it to your PATH"
    exit 1
fi

JULIA_VERSION=$(julia --version | head -n1)
echo -e "${GREEN}Found:${NC} $JULIA_VERSION"

# Build the daemon if needed
if [ ! -f "$DAEMON_BIN" ]; then
    echo -e "${YELLOW}Building ITHERIS daemon...${NC}"
    export PATH="$HOME/.cargo/bin:$PATH"
    cd "$DAEMON_DIR"
    cargo build --release
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Build successful!${NC}"
fi

# Check if adaptive-kernel exists
if [ ! -d "./adaptive-kernel" ]; then
    echo -e "${RED}ERROR: adaptive-kernel not found${NC}"
    echo "Please ensure adaptive-kernel is in the current directory"
    exit 1
fi

echo -e "${GREEN}Starting ITHERIS daemon...${NC}"

# Start the daemon
export RUST_LOG=info
exec "$DAEMON_BIN" 2>&1 | tee -a "$LOG_FILE"
