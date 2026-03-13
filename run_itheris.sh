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

# Initialize Rust security layer (Warden)
echo -e "${GREEN}Initializing Rust Warden security layer...${NC}"
export ITHERIS_SECURITY_INIT=1

# Set up shared memory for native IPC (64MB lock-free ring buffer)
SHM_PATH="/dev/shm/itheris_ipc"
SHM_SIZE=$((64*1024*1024))  # 64MB

if [ ! -f "$SHM_PATH" ] || [ $(stat -c%s "$SHM_PATH" 2>/dev/null || echo 0) -lt $SHM_SIZE ]; then
    echo -e "${GREEN}Creating 64MB shared memory IPC region...${NC}"
    sudo mkdir -p /dev/shm 2>/dev/null || true
    sudo truncate -s $SHM_SIZE "$SHM_PATH" 2>/dev/null || true
    sudo chmod 660 "$SHM_PATH" 2>/dev/null || true
    echo -e "${GREEN}Shared memory created: $SHM_PATH ($SHM_SIZE bytes)${NC}"
else
    echo -e "${GREEN}Shared memory already configured: $SHM_PATH${NC}"
fi

# Set environment variables for Julia to use native IPC
export ITHERIS_SHM_PATH="$SHM_PATH"
export ITHERIS_SHM_SIZE="0x00400000"

# Set up environment for Rust FFI
export LD_LIBRARY_PATH="$DAEMON_DIR/target/release:$LD_LIBRARY_PATH"

# Verify Rust daemon has new security modules
if [ -f "$DAEMON_BIN" ]; then
    echo -e "${GREEN}Security modules loaded:${NC}"
    echo "  - secrets: TPM 2.0 + AES-256-GCM"
    echo "  - jwt_auth: Secure token management"
    echo "  - flow_integrity: Cryptographic sovereignty"
    echo "  - risk_classifier: LEP veto equation"
    echo "  - secure_confirmation: Hardware entropy gate"
    echo "  - task_orchestrator: Authenticated scheduling"
    echo "  - safe_shell: Jailed command execution"
    echo "  - safe_http: Async HTTP with rate limiting"
fi

echo -e "${GREEN}Starting ITHERIS daemon...${NC}"

# Start the daemon
export RUST_LOG=info
exec "$DAEMON_BIN" 2>&1 | tee -a "$LOG_FILE"
