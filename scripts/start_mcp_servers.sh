#!/bin/bash
#
# start_mcp_servers.sh - Start MCP Servers for Itheris
#
# This script starts the Finance MCP Server (port 3000) and 
# GitHub MCP Server (port 3001) for Project X (Itheris).
#
# Usage:
#   ./scripts/start_mcp_servers.sh [--install] [--check-only]
#
# Options:
#   --install      Install npm dependencies first
#   --check-only   Only check dependencies and health, don't start servers
#
# Environment Variables:
#   GITHUB_TOKEN   Required for GitHub MCP Server
#   YF_API_KEY     Optional API key for Yahoo Finance Premium
#   MCP_FINANCE_ENDPOINT   Override default finance endpoint
#   MCP_GITHUB_ENDPOINT    Override default github endpoint
#
# Ports:
#   Finance MCP:  localhost:3000
#   GitHub MCP:   localhost:3001
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"

# Default ports
FINANCE_PORT=3000
GITHUB_PORT=3001

# Server names for display
FINANCE_SERVER_NAME="Finance MCP Server"
GITHUB_SERVER_NAME="GitHub MCP Server"

# Health check endpoints (MCP servers typically expose JSON-RPC)
HEALTH_CHECK_TIMEOUT=5
HEALTH_CHECK_RETRIES=12  # Wait up to 60 seconds for server startup

# ============================================================================
# SETUP FUNCTIONS
# ============================================================================

setup_directories() {
    mkdir -p "$LOG_DIR" "$PID_DIR"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================

check_node() {
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 18+ first."
        error "Visit: https://nodejs.org/"
        return 1
    fi
    
    local node_version
    node_version=$(node --version | sed 's/v//')
    local major_version
    major_version=$(echo "$node_version" | cut -d. -f1)
    
    if [ "$major_version" -lt 18 ]; then
        error "Node.js version $node_version is too old. Please upgrade to Node.js 18+."
        return 1
    fi
    
    log "Node.js version: $(node --version)"
    return 0
}

check_npm() {
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install Node.js which includes npm."
        return 1
    fi
    
    log "npm version: $(npm --version)"
    return 0
}

check_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        error "GITHUB_TOKEN environment variable is not set."
        error "Please set your GitHub token:"
        error "  export GITHUB_TOKEN='your_github_token_here'"
        error "Get a token at: https://github.com/settings/tokens"
        return 1
    fi
    
    log "GitHub token: configured (${GITHUB_TOKEN:0:4}...)"
    return 0
}

check_dependencies() {
    log "Checking dependencies..."
    
    check_node || return 1
    check_npm || return 1
    
    # Check GitHub token (required)
    check_github_token || return 1
    
    # Optional: Check for yfinance API key
    if [ -n "$YF_API_KEY" ]; then
        log "Yahoo Finance API key: configured"
    else
        log "Yahoo Finance API key: not set (using free tier)"
    fi
    
    log "All dependencies satisfied."
    return 0
}

# ============================================================================
# MCP SERVER PACKAGE INSTALLATION
# ============================================================================

install_mcp_packages() {
    log "Installing MCP server packages..."
    
    # Create a temporary directory for MCP packages
    local mcp_node_modules="$PROJECT_ROOT/.mcp_modules"
    mkdir -p "$mcp_node_modules"
    
    # Install Finance MCP Server (using @modelcontextprotocol/server-yfinance)
    log "Installing Finance MCP Server..."
    cd "$mcp_node_modules"
    npm init -y > /dev/null 2>&1 || true
    npm install @modelcontextprotocol/server-yfinance --save > /dev/null 2>&1
    
    # Install GitHub MCP Server
    log "Installing GitHub MCP Server..."
    npm install @modelcontextprotocol/server-github --save > /dev/null 2>&1
    
    log "MCP server packages installed successfully."
    
    # Return to project root
    cd "$PROJECT_ROOT"
}

check_mcp_packages() {
    local mcp_node_modules="$PROJECT_ROOT/.mcp_modules"
    
    if [ ! -d "$mcp_node_modules/node_modules/@modelcontextprotocol/server-yfinance" ]; then
        log "MCP packages not found. Run with --install to install them."
        return 1
    fi
    
    if [ ! -d "$mcp_node_modules/node_modules/@modelcontextprotocol/server-github" ]; then
        log "GitHub MCP package not found. Run with --install to install it."
        return 1
    fi
    
    log "MCP packages are installed."
    return 0
}

# ============================================================================
# SERVER STARTUP
# ============================================================================

start_finance_server() {
    log "Starting Finance MCP Server on port $FINANCE_PORT..."
    
    local mcp_node_modules="$PROJECT_ROOT/.mcp_modules"
    local log_file="$LOG_DIR/mcp-finance.log"
    local pid_file="$PID_DIR/mcp-finance.pid"
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local existing_pid
        existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log "Finance MCP Server is already running (PID: $existing_pid)"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    # Start the Finance MCP Server
    # Using stdio mode - the MCP server runs as a subprocess
    # We use npx to run the package directly
    GITHUB_TOKEN="$GITHUB_TOKEN" \
    YF_API_KEY="$YF_API_KEY" \
    node "$mcp_node_modules/node_modules/@modelcontextprotocol/server-yfinance/build/index.js" \
        > "$log_file" 2>&1 &
    
    local finance_pid=$!
    echo "$finance_pid" > "$pid_file"
    
    log "Finance MCP Server started (PID: $finance_pid)"
    return 0
}

start_github_server() {
    log "Starting GitHub MCP Server on port $GITHUB_PORT..."
    
    local mcp_node_modules="$PROJECT_ROOT/.mcp_modules"
    local log_file="$LOG_DIR/mcp-github.log"
    local pid_file="$PID_DIR/mcp-github.pid"
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local existing_pid
        existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log "GitHub MCP Server is already running (PID: $existing_pid)"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    # Start the GitHub MCP Server
    # The GitHub MCP server uses GitHub token from environment
    GITHUB_TOKEN="$GITHUB_TOKEN" \
    node "$mcp_node_modules/node_modules/@modelcontextprotocol/server-github/build/index.js" \
        > "$log_file" 2>&1 &
    
    local github_pid=$!
    echo "$github_pid" > "$pid_file"
    
    log "GitHub MCP Server started (PID: $github_pid)"
    return 0
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

check_port() {
    local port=$1
    local name=$2
    
    # Use netcat or /dev/tcp to check if port is open
    if command -v nc &> /dev/null; then
        nc -z localhost "$port" 2>/dev/null
    elif command -v timeout &> /dev/null; then
        timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null
    else
        # Fallback: try to connect with bash
        (echo >/dev/tcp/localhost/"$port") 2>/dev/null
    fi
}

wait_for_server() {
    local port=$1
    local name=$2
    local retries=$HEALTH_CHECK_RETRIES
    
    log "Waiting for $name to be ready..."
    
    while [ $retries -gt 0 ]; do
        if check_port "$port" "$name"; then
            log "$name is ready (port $port)"
            return 0
        fi
        
        sleep 5
        retries=$((retries - 1))
        echo -n "."
    done
    
    echo ""
    error "$name failed to start on port $port"
    return 1
}

check_health() {
    log "Checking MCP server health..."
    
    local finance_ready=false
    local github_ready=false
    
    # Check Finance MCP
    if check_port "$FINANCE_PORT" "$FINANCE_SERVER_NAME"; then
        log "✓ $FINANCE_SERVER_NAME: healthy (port $FINANCE_PORT)"
        finance_ready=true
    else
        error "✗ $FINANCE_SERVER_NAME: not responding (port $FINANCE_PORT)"
    fi
    
    # Check GitHub MCP
    if check_port "$GITHUB_PORT" "$GITHUB_SERVER_NAME"; then
        log "✓ $GITHUB_SERVER_NAME: healthy (port $GITHUB_PORT)"
        github_ready=true
    else
        error "✗ $GITHUB_SERVER_NAME: not responding (port $GITHUB_PORT)"
    fi
    
    if [ "$finance_ready" = true ] && [ "$github_ready" = true ]; then
        log "All MCP servers are healthy."
        return 0
    else
        error "Some MCP servers are not healthy."
        return 1
    fi
}

# ============================================================================
# SERVER STOP
# ============================================================================

stop_server() {
    local name=$1
    local pid_file=$2
    
    if [ ! -f "$pid_file" ]; then
        log "$name: not running (no PID file)"
        return 0
    fi
    
    local pid
    pid=$(cat "$pid_file")
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log "$name: not running (stale PID file)"
        rm -f "$pid_file"
        return 0
    fi
    
    log "Stopping $name (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    
    # Wait for graceful shutdown
    local count=10
    while [ $count -gt 0 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            log "$name stopped successfully."
            return 0
        fi
        sleep 1
        count=$((count - 1))
    done
    
    # Force kill if still running
    log "$name: forcing shutdown..."
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    
    log "$name stopped."
}

stop_servers() {
    log "Stopping MCP servers..."
    
    stop_server "$FINANCE_SERVER_NAME" "$PID_DIR/mcp-finance.pid"
    stop_server "$GITHUB_SERVER_NAME" "$PID_DIR/mcp-github.pid"
}

# ============================================================================
# STATUS
# ============================================================================

show_status() {
    log "MCP Server Status:"
    echo ""
    
    # Finance MCP
    if [ -f "$PID_DIR/mcp-finance.pid" ]; then
        local finance_pid
        finance_pid=$(cat "$PID_DIR/mcp-finance.pid")
        if kill -0 "$finance_pid" 2>/dev/null; then
            echo "  $FINANCE_SERVER_NAME: running (PID: $finance_pid, Port: $FINANCE_PORT)"
        else
            echo "  $FINANCE_SERVER_NAME: not running (stale PID: $finance_pid)"
        fi
    else
        echo "  $FINANCE_SERVER_NAME: not running"
    fi
    
    # GitHub MCP
    if [ -f "$PID_DIR/mcp-github.pid" ]; then
        local github_pid
        github_pid=$(cat "$PID_DIR/mcp-github.pid")
        if kill -0 "$github_pid" 2>/dev/null; then
            echo "  $GITHUB_SERVER_NAME: running (PID: $github_pid, Port: $GITHUB_PORT)"
        else
            echo "  $GITHUB_SERVER_NAME: not running (stale PID: $github_pid)"
        fi
    else
        echo "  $GITHUB_SERVER_NAME: not running"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Finance MCP Endpoint:  http://localhost:$FINANCE_PORT"
    echo "  GitHub MCP Endpoint:  http://localhost:$GITHUB_PORT"
    echo "  Log directory:         $LOG_DIR"
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Start MCP servers for Itheris (Project X).

OPTIONS:
    --install      Install npm dependencies before starting
    --check-only   Only verify dependencies, don't start servers
    --stop         Stop running MCP servers
    --status       Show status of MCP servers
    --help         Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN       Required. GitHub API token for MCP server
    YF_API_KEY         Optional. Yahoo Finance API key for premium features
    MCP_FINANCE_ENDPOINT   Optional. Override default finance endpoint
    MCP_GITHUB_ENDPOINT    Optional. Override default github endpoint

EXAMPLES:
    # Install dependencies and start servers
    export GITHUB_TOKEN='ghp_xxxx'
    ./scripts/start_mcp_servers.sh --install

    # Check if servers are running
    ./scripts/start_mcp_servers.sh --status

    # Stop servers
    ./scripts/start_mcp_servers.sh --stop

EOF
}

main() {
    # Parse arguments
    local do_install=false
    local do_check_only=false
    local do_stop=false
    local do_status=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --install)
                do_install=true
                shift
                ;;
            --check-only)
                do_check_only=true
                shift
                ;;
            --stop)
                do_stop=true
                shift
                ;;
            --status)
                do_status=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Setup directories
    setup_directories
    
    # Handle --status
    if [ "$do_status" = true ]; then
        show_status
        exit 0
    fi
    
    # Handle --stop
    if [ "$do_stop" = true ]; then
        stop_servers
        exit 0
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Handle --check-only
    if [ "$do_check_only" = true ]; then
        log "Dependency check passed."
        check_mcp_packages || true
        exit 0
    fi
    
    # Install if requested or if packages not found
    if [ "$do_install" = true ]; then
        install_mcp_packages
    else
        check_mcp_packages || install_mcp_packages
    fi
    
    # Start servers
    log "Starting MCP servers..."
    
    start_finance_server || error "Failed to start Finance MCP Server"
    start_github_server || error "Failed to start GitHub MCP Server"
    
    # Wait for servers to be ready
    wait_for_server "$FINANCE_PORT" "$FINANCE_SERVER_NAME" || {
        error "Finance MCP Server failed to start. Check logs at $LOG_DIR/mcp-finance.log"
    }
    
    wait_for_server "$GITHUB_PORT" "$GITHUB_SERVER_NAME" || {
        error "GitHub MCP Server failed to start. Check logs at $LOG_DIR/mcp-github.log"
    }
    
    # Final health check
    if check_health; then
        log "============================================"
        log "MCP Servers started successfully!"
        log "============================================"
        log ""
        log "Finance MCP:  http://localhost:$FINANCE_PORT"
        log "GitHub MCP:   http://localhost:$GITHUB_PORT"
        log ""
        log "Logs are available in: $LOG_DIR"
        log "To stop servers: $0 --stop"
    else
        error "Some servers failed health check."
        exit 1
    fi
}

# Trap signals for graceful shutdown
trap 'stop_servers; exit 0' SIGINT SIGTERM

# Run main
main "$@"
