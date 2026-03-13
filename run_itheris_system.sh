#!/bin/bash
# =============================================================================
# ProjectX Jarvis/ITHERIS System Launcher
# =============================================================================
# This script starts the full ITHERIS system including:
# - Warden gRPC server (itheris-daemon)
# - Terminal TUI (itheris-tui)
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
GRPC_HOST="${ITHERIS_GRPC_HOST:-127.0.0.1}"
GRPC_PORT="${ITHERIS_GRPC_PORT:-50051}"
LOG_LEVEL="${ITHERIS_LOG_LEVEL:-info}"

# =============================================================================
# Print functions
# =============================================================================
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# =============================================================================
# Check dependencies
# =============================================================================
check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing_deps=()
    
    # Check for Rust
    if ! command -v rustc &> /dev/null; then
        missing_deps+=("Rust (install from rustup.rs)")
    else
        print_success "Rust: $(rustc --version)"
    fi
    
    # Check for Cargo
    if ! command -v cargo &> /dev/null; then
        missing_deps+=("Cargo (install from rustup.rs)")
    else
        print_success "Cargo: $(cargo --version)"
    fi
    
    # Check for Julia (optional)
    if command -v julia &> /dev/null; then
        print_success "Julia: $(julia --version)"
    else
        print_warning "Julia not found - adaptive kernel features will be limited"
    fi
    
    # Check for required directories
    local dirs=("itheris-daemon" "tui")
    for dir in "${dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            print_success "Directory exists: $dir"
        else
            print_error "Directory missing: $dir"
            exit 1
        fi
    done
    
    # If there are missing critical dependencies, exit
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# =============================================================================
# Build components
# =============================================================================
build_components() {
    print_header "Building Components"
    
    # Build itheris-daemon
    print_info "Building itheris-daemon (gRPC server)..."
    cd "$PROJECT_ROOT/itheris-daemon"
    cargo build --release 2>&1 | tail -5
    
    if [ $? -eq 0 ]; then
        print_success "itheris-daemon built successfully"
    else
        print_error "Failed to build itheris-daemon"
        exit 1
    fi
    
    # Build TUI
    print_info "Building itheris-tui..."
    cd "$PROJECT_ROOT/tui"
    cargo build --release 2>&1 | tail -5
    
    if [ $? -eq 0 ]; then
        print_success "itheris-tui built successfully"
    else
        print_error "Failed to build itheris-tui"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Start gRPC server
# =============================================================================
start_grpc_server() {
    print_header "Starting Warden gRPC Server"
    
    cd "$PROJECT_ROOT/itheris-daemon"
    
    # Set environment variables
    export RUST_LOG="$LOG_LEVEL"
    export ITHERIS_GRPC_HOST="$GRPC_HOST"
    export ITHERIS_GRPC_PORT="$GRPC_PORT"
    
    print_info "Starting gRPC server on $GRPC_HOST:$GRPC_PORT..."
    
    # Run in background
    cargo run --release 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Check if server is running
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_success "gRPC server started (PID: $SERVER_PID)"
        echo $SERVER_PID > /tmp/itheris-daemon.pid
    else
        print_error "Failed to start gRPC server"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Start TUI
# =============================================================================
start_tui() {
    print_header "Starting Terminal Interface"
    
    cd "$PROJECT_ROOT/tui"
    
    # Set environment variables
    export RUST_LOG="$LOG_LEVEL"
    export ITHERIS_GRPC_HOST="$GRPC_HOST"
    export ITHERIS_GRPC_PORT="$GRPC_PORT"
    
    print_info "Connecting to gRPC server at $GRPC_HOST:$GRPC_PORT..."
    
    # Run TUI
    cargo run --release
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Stop all processes
# =============================================================================
stop_all() {
    print_header "Stopping ITHERIS System"
    
    # Stop daemon if running
    if [ -f /tmp/itheris-daemon.pid ]; then
        local pid=$(cat /tmp/itheris-daemon.pid)
        if kill -0 $pid 2>/dev/null; then
            print_info "Stopping gRPC server (PID: $pid)..."
            kill $pid 2>/dev/null || true
            print_success "gRPC server stopped"
        fi
        rm /tmp/itheris-daemon.pid
    fi
    
    # Kill any remaining child processes
    pkill -f "itheris-daemon" 2>/dev/null || true
    pkill -f "itheris-tui" 2>/dev/null || true
    
    print_success "All processes stopped"
}

# =============================================================================
# Print usage
# =============================================================================
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     Start the full system (gRPC server + TUI)"
    echo "  server    Start only the gRPC server"
    echo "  tui       Start only the TUI (requires server running)"
    echo "  stop      Stop all running processes"
    echo "  build     Build all components"
    echo "  check     Check dependencies and project structure"
    echo ""
    echo "Environment Variables:"
    echo "  ITHERIS_GRPC_HOST     gRPC server host (default: 127.0.0.1)"
    echo "  ITHERIS_GRPC_PORT     gRPC server port (default: 50051)"
    echo "  ITHERIS_LOG_LEVEL     Logging level (default: info)"
    echo ""
    echo "Examples:"
    echo "  $0 start              # Start full system"
    echo "  $0 server &           # Start server in background"
    echo "  ITHERIS_GRPC_PORT=50052 $0 start  # Use custom port"
}

# =============================================================================
# Main
# =============================================================================
main() {
    local command="${1:-start}"
    
    # Handle signals
    trap stop_all EXIT INT TERM
    
    case "$command" in
        start)
            check_dependencies
            build_components
            start_grpc_server
            start_tui
            ;;
        server)
            check_dependencies
            build_components
            start_grpc_server
            # Wait indefinitely
            wait
            ;;
        tui)
            check_dependencies
            build_components
            start_tui
            ;;
        stop)
            stop_all
            ;;
        build)
            check_dependencies
            build_components
            print_success "Build complete"
            ;;
        check)
            check_dependencies
            print_success "All checks passed"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
