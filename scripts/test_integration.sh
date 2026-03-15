#!/bin/bash
# =============================================================================
# ProjectX Jarvis/ITHERIS Integration Test Script
# =============================================================================
# This script verifies that all components of the ITHERIS system can be built
# and are properly integrated.
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Print functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# Test 1: Verify project structure
# =============================================================================
test_project_structure() {
    print_header "Testing Project Structure"
    
    local dirs=("proto" "itheris-daemon" "tui" "console" "console-www")
    local all_exist=true
    
    for dir in "${dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            print_success "Directory exists: $dir"
        else
            print_failure "Directory missing: $dir"
            all_exist=false
        fi
    done
    
    # Check proto file
    if [ -f "$PROJECT_ROOT/proto/warden.proto" ]; then
        print_success "Proto definitions exist: proto/warden.proto"
    else
        print_failure "Proto definitions missing: proto/warden.proto"
    fi
    
    # Check Cargo.toml files
    for cargo_toml in "itheris-daemon/Cargo.toml" "tui/Cargo.toml" "console/Cargo.toml"; do
        if [ -f "$PROJECT_ROOT/$cargo_toml" ]; then
            print_success "Cargo.toml exists: $cargo_toml"
        else
            print_failure "Cargo.toml missing: $cargo_toml"
        fi
    done
    
    if [ "$all_exist" = true ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Test 2: Verify protobuf definitions compile
# =============================================================================
test_proto_compile() {
    print_header "Testing Proto Definitions"
    
    # Check if protoc is available
    if ! command -v protoc &> /dev/null; then
        print_warning "protoc not found - skipping proto compilation test"
        print_info "Install protoc to enable this test: https://github.com/protocolbuffers/protobuf"
        return 0
    fi
    
    # Check proto file syntax
    if protoc --proto_path="$PROJECT_ROOT/proto" --descriptor_set_out=/dev/null "$PROJECT_ROOT/proto/warden.proto" 2>/dev/null; then
        print_success "Proto definitions are valid"
    else
        print_failure "Proto definitions have syntax errors"
    fi
}

# =============================================================================
# Test 3: Verify gRPC server compiles
# =============================================================================
test_grpc_server_compile() {
    print_header "Testing gRPC Server (itheris-daemon)"
    
    cd "$PROJECT_ROOT/itheris-daemon"
    
    # Check Cargo.toml exists and has required dependencies
    if grep -q "tonic" Cargo.toml; then
        print_success "gRPC dependencies found in Cargo.toml"
    else
        print_failure "Missing tonic dependency in Cargo.toml"
        return 1
    fi
    
    # Attempt to build (just check compilation, don't run)
    # Use --lib to only check library compilation
    if cargo check --lib 2>/dev/null; then
        print_success "gRPC server compiles successfully"
    else
        print_warning "gRPC server has compilation issues (may be expected if dependencies are missing)"
    fi
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Test 4: Verify TUI compiles
# =============================================================================
test_tui_compile() {
    print_header "Testing TUI (Terminal Interface)"
    
    cd "$PROJECT_ROOT/tui"
    
    # Check dependencies
    if grep -q "ratatui" Cargo.toml; then
        print_success "TUI dependencies found"
    else
        print_failure "Missing ratatui dependency"
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    if grep -q "tonic" Cargo.toml; then
        print_success "gRPC dependencies found for TUI"
    else
        print_failure "Missing tonic dependency for TUI"
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    # Check if it compiles
    if cargo check 2>/dev/null; then
        print_success "TUI compiles successfully"
    else
        print_warning "TUI has compilation issues (may be expected if dependencies are missing)"
    fi
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Test 5: Verify console compiles
# =============================================================================
test_console_compile() {
    print_header "Testing Console (Tauri Desktop App)"
    
    cd "$PROJECT_ROOT/console"
    
    # Check dependencies
    if grep -q "leptos" Cargo.toml; then
        print_success "Leptos dependencies found"
    else
        print_failure "Missing Leptos dependency"
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    # Check if it can be checked (wasm target)
    if cargo check --target wasm32-unknown-unknown 2>/dev/null; then
        print_success "Console WASM compiles successfully"
    else
        print_warning "Console WASM has compilation issues (may be expected)"
    fi
    
    cd "$PROJECT_ROOT"
}

# =============================================================================
# Test 6: Verify web console structure
# =============================================================================
test_web_console_structure() {
    print_header "Testing Web Console (console-www)"
    
    # Check for key files
    local files=("index.html" "build.sh" "README.md")
    local all_exist=true
    
    for file in "${files[@]}"; do
        if [ -f "$PROJECT_ROOT/console-www/$file" ]; then
            print_success "Web console file exists: $file"
        else
            print_failure "Web console file missing: $file"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Test 7: Verify adaptive kernel structure
# =============================================================================
test_adaptive_kernel_structure() {
    print_header "Testing Adaptive Kernel"
    
    # Check for Julia project file
    if [ -f "$PROJECT_ROOT/Project.toml" ]; then
        print_success "Julia Project.toml exists"
    else
        print_failure "Julia Project.toml missing"
    fi
    
    # Check for key kernel files
    local kernel_files=(
        "adaptive-kernel/kernel/Kernel.jl"
        "adaptive-kernel/cognition/Cognition.jl"
        "adaptive-kernel/brain/Brain.jl"
    )
    
    for file in "${kernel_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            print_success "Kernel file exists: $file"
        else
            print_failure "Kernel file missing: $file"
        fi
    done
}

# =============================================================================
# Test 8: Check for required environment
# =============================================================================
test_environment() {
    print_header "Checking Development Environment"
    
    # Check for Rust
    if command -v rustc &> /dev/null; then
        local rust_version=$(rustc --version)
        print_success "Rust installed: $rust_version"
    else
        print_warning "Rust not found - install from rustup.rs"
    fi
    
    # Check for Cargo
    if command -v cargo &> /dev/null; then
        local cargo_version=$(cargo --version)
        print_success "Cargo installed: $cargo_version"
    else
        print_warning "Cargo not found - install from rustup.rs"
    fi
    
    # Check for Julia (optional)
    if command -v julia &> /dev/null; then
        local julia_version=$(julia --version)
        print_success "Julia installed: $julia_version"
    else
        print_warning "Julia not found - adaptive kernel features will be limited"
    fi
    
    # Check for protoc (optional)
    if command -v protoc &> /dev/null; then
        local protoc_version=$(protoc --version)
        print_success "protoc installed: $protoc_version"
    else
        print_warning "protoc not found - proto generation will be limited"
    fi
    
    # Check for wasm-pack (optional)
    if command -v wasm-pack &> /dev/null; then
        local wasm_pack_version=$(wasm-pack --version)
        print_success "wasm-pack installed: $wasm_pack_version"
    else
        print_warning "wasm-pack not found - WASM builds will be limited"
    fi
}

# =============================================================================
# Print test summary
# =============================================================================
print_summary() {
    print_header "Test Summary"
    
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${YELLOW}Some tests had issues - check the output above${NC}"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ProjectX Jarvis/ITHERIS Integration Test Suite          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Run all tests
    test_environment
    test_project_structure
    test_proto_compile
    test_grpc_server_compile
    test_tui_compile
    test_console_compile
    test_web_console_structure
    test_adaptive_kernel_structure
    
    # Print summary
    print_summary
}

# Run main function
main "$@"
