#!/bin/bash
# Dual Kernel Startup Script
# Starts Rust Itheris Kernel (Ring 0) first, then Julia Adaptive Kernel (Ring 3)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_DIR="/home/user/projectx"
SHM_PATH="/dev/shm/itheris_ipc"

cleanup() {
    echo -e "${YELLOW}Shutting down kernels...${NC}"
    if [ ! -z "$RUST_PID" ]; then
        kill $RUST_PID 2>/dev/null || true
    fi
    if [ ! -z "$JULIA_PID" ]; then
        kill $JULIA_PID 2>/dev/null || true
    fi
    echo -e "${GREEN}Shutdown complete${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo -e "${GREEN}=== Starting Dual Kernel System ===${NC}"

# Step 1: Build and start Rust kernel
echo -e "${YELLOW}[1/3] Building Rust Itheris Kernel...${NC}"
cd "$PROJECT_DIR/Itheris/Brain"
cargo build --release

echo -e "${YELLOW}[2/3] Starting Rust Itheris Kernel...${NC}"
cargo run --release > /tmp/rust_kernel.log 2>&1 &
RUST_PID=$!
echo "Rust kernel PID: $RUST_PID"

# Step 2: Wait for shared memory
echo -e "${YELLOW}Waiting for IPC shared memory...${NC}"
for i in {1..30}; do
    if [ -e "$SHM_PATH" ]; then
        echo -e "${GREEN}Shared memory ready at $SHM_PATH${NC}"
        break
    fi
    if ! kill -0 $RUST_PID 2>/dev/null; then
        echo -e "${RED}Rust kernel died unexpectedly${NC}"
        cat /tmp/rust_kernel.log
        exit 1
    fi
    sleep 0.5
    echo -n "."
done
echo ""

# Step 3: Start Julia kernel
echo -e "${YELLOW}[3/3] Starting Julia Adaptive Kernel...${NC}"
cd "$PROJECT_DIR"
julia --project=. run_kernel.jl > /tmp/julia_kernel.log 2>&1 &
JULIA_PID=$!
echo "Julia kernel PID: $JULIA_PID"

echo -e "${GREEN}=== Both kernels running ===${NC}"
echo "Rust kernel:  PID $RUST_PID (log: /tmp/rust_kernel.log)"
echo "Julia kernel: PID $JULIA_PID (log: /tmp/julia_kernel.log)"
echo ""
echo "Press Ctrl+C to stop both kernels"

# Wait for Julia kernel
wait $JULIA_PID || true

# Cleanup
cleanup
