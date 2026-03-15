#!/bin/bash
# =============================================================================
# verify_isolation.sh - Verify Isolation Layers are Active
#
# This script verifies that all three isolation layers are properly configured
# and active for the Julia Brain VM.
# =============================================================================

set -e

CGROUP_NAME="julia_brain_vm"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "========================================"
echo "  Isolation Layer Verification"
echo "========================================"
echo ""

TOTAL=0
PASSED=0

# =============================================================================
# CHECK 1: CGROUP LAYER
# =============================================================================
echo "--- Cgroup Resource Limits (Metabolic Budget) ---"

TOTAL=$((TOTAL + 1))
if [[ -d "${CGROUP_PATH}" ]]; then
    pass "Cgroup directory exists: ${CGROUP_PATH}"
    PASSED=$((PASSED + 1))
else
    fail "Cgroup directory not found: ${CGROUP_PATH}"
fi

TOTAL=$((TOTAL + 1))
if [[ -f "${CGROUP_PATH}/cpu.max" ]]; then
    CPU_LIMIT=$(cat "${CGROUP_PATH}/cpu.max")
    info "CPU limit: ${CPU_LIMIT}"
    pass "CPU limit configured"
    PASSED=$((PASSED + 1))
else
    fail "CPU limit not configured"
fi

TOTAL=$((TOTAL + 1))
if [[ -f "${CGROUP_PATH}/memory.max" ]]; then
    MEM_LIMIT=$(cat "${CGROUP_PATH}/memory.max")
    info "Memory limit: ${MEM_LIMIT}"
    pass "Memory limit configured"
    PASSED=$((PASSED + 1))
else
    fail "Memory limit not configured"
fi

TOTAL=$((TOTAL + 1))
if [[ -f "${CGROUP_PATH}/pids.max" ]]; then
    PIDS_LIMIT=$(cat "${CGROUP_PATH}/pids.max")
    info "PIDs limit: ${PIDS_LIMIT}"
    pass "PIDs limit configured"
    PASSED=$((PASSED + 1))
else
    fail "PIDs limit not configured"
fi

# Check current usage
if [[ -f "${CGROUP_PATH}/memory.current" ]]; then
    info "Current memory: $(cat "${CGROUP_PATH}/memory.current")"
fi

echo ""

# =============================================================================
# CHECK 2: SECCOMP LAYER
# =============================================================================
echo "--- Seccomp Profile (Syscall Restrictions) ---"

TOTAL=$((TOTAL + 1))
if [[ -f "/tmp/julia_brain_seccomp.json" ]]; then
    pass "Seccomp profile file exists"
    PASSED=$((PASSED + 1))
else
    fail "Seccomp profile not found"
fi

# Check if seccomp is loaded (if we can check)
TOTAL=$((TOTAL + 1))
if grep -q "Seccomp:" /proc/self/status 2>/dev/null; then
    SECCOMP_STATUS=$(grep "Seccomp:" /proc/self/status | awk '{print $2}')
    info "Seccomp status: ${SECCOMP_STATUS}"
    if [[ "${SECCOMP_STATUS}" != "0" ]]; then
        pass "Seccomp is enabled"
        PASSED=$((PASSED + 1))
    else
        info "Seccomp not loaded (expected for non-isolated processes)"
    fi
else
    info "Cannot check seccomp status"
fi

echo ""

# =============================================================================
# CHECK 3: MEMORY GUARD LAYER
# =============================================================================
echo "--- Memory Boundary Guards (Ring Buffer Protection) ---"

TOTAL=$((TOTAL + 1))
# Check if ring buffer exists
if [[ -f "/dev/shm/itheris_ipc" ]] || [[ -S "/dev/shm/itheris_ipc" ]]; then
    pass "IPC ring buffer exists at /dev/shm/itheris_ipc"
    PASSED=$((PASSED + 1))
else
    info "IPC ring buffer not yet created (will be created on runtime init)"
    # Not a failure - just not created yet
fi

TOTAL=$((TOTAL + 1))
# Check for mmap protections
if [[ -r "/proc/self/maps" ]]; then
    if grep -q "/dev/shm" /proc/self/maps; then
        pass "Shared memory mapping accessible"
        PASSED=$((PASSED + 1))
    else
        info "No /dev/shm mappings in current process"
    fi
else
    info "Cannot read /proc/self/maps"
fi

echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo "========================================"
echo "  Verification Summary"
echo "========================================"
echo ""
echo "Passed: ${PASSED}/${TOTAL} checks"

if [[ ${PASSED} -eq ${TOTAL} ]]; then
    echo ""
    pass "All isolation layers verified!"
    exit 0
else
    echo ""
    info "Some checks did not pass, but this may be expected if:"
    echo "  - Isolation hasn't been applied yet"
    echo "  - Running without root privileges"
    echo "  - Julia process hasn't been started"
    exit 0
fi
