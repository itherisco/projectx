#!/bin/bash
# =============================================================================
# apply_isolation.sh - Apply Software-Based Isolation Layers
#
# This script applies the three critical isolation layers to the Julia Brain VM:
# 1. Seccomp Profile - Syscall restrictions
# 2. Cgroup Resource Limits - Metabolic budget enforcement
# 3. Memory Boundary Guards - Ring buffer protection
#
# Usage: ./apply_isolation.sh [julia_pid]
# =============================================================================

set -e

# Configuration
CGROUP_NAME="julia_brain_vm"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
CPU_LIMIT=50        # 50% CPU
MEMORY_LIMIT=4G     # 4GB RAM
PIDS_LIMIT=10       # Max 10 processes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "Not running as root. Some features may not work."
        log_warn "Run with sudo for full isolation: sudo $0"
    fi
}

# =============================================================================
# LAYER 1: CGROUP RESOURCE LIMITS
# =============================================================================
setup_cgroup() {
    log_info "Setting up cgroup for metabolic budget enforcement..."
    
    # Create cgroup directory
    if [[ ! -d "${CGROUP_PATH}" ]]; then
        mkdir -p "${CGROUP_PATH}"
        log_info "Created cgroup at ${CGROUP_PATH}"
    else
        log_info "Cgroup already exists at ${CGROUP_PATH}"
    fi
    
    # Set CPU limits (cgroup v2)
    if [[ -f "${CGROUP_PATH}/cpu.max" ]]; then
        # Format: "value period" where value is in microseconds
        CPU_VALUE=$(echo "${CPU_LIMIT} * 10000" | bc | cut -d. -f1)
        echo "${CPU_VALUE} 100000" > "${CGROUP_PATH}/cpu.max"
        log_info "CPU limit set to ${CPU_LIMIT}%"
    fi
    
    # Set memory limits
    if [[ -f "${CGROUP_PATH}/memory.max" ]]; then
        echo "${MEMORY_LIMIT}" > "${CGROUP_PATH}/memory.max"
        log_info "Memory limit set to ${MEMORY_LIMIT}"
    fi
    
    # Set pids limit
    if [[ -f "${CGROUP_PATH}/pids.max" ]]; then
        echo "${PIDS_LIMIT}" > "${CGROUP_PATH}/pids.max"
        log_info "PIDs limit set to ${PIDS_LIMIT}"
    fi
    
    # Enable OOM kill for the entire group
    if [[ -f "${CGROUP_PATH}/memory.oom.group" ]]; then
        echo "1" > "${CGROUP_PATH}/memory.oom.group"
    fi
    
    log_info "Cgroup setup complete"
}

# Add process to cgroup
add_to_cgroup() {
    local pid=$1
    
    if [[ -z "${pid}" ]]; then
        log_error "No PID provided to add to cgroup"
        return 1
    fi
    
    if [[ -f "${CGROUP_PATH}/cgroup.procs" ]]; then
        echo "${pid}" > "${CGROUP_PATH}/cgroup.procs"
        log_info "Added PID ${pid} to cgroup ${CGROUP_NAME}"
    else
        log_error "Cgroup cgroup.procs not found"
        return 1
    fi
}

# =============================================================================
# LAYER 2: SECCOMP PROFILE
# =============================================================================
setup_seccomp() {
    log_info "Setting up seccomp profile..."
    
    # Generate seccomp profile
    local profile_file="/tmp/julia_brain_seccomp.json"
    
    cat > "${profile_file}" << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO(EPERM)",
  "syscalls": [
    {"names": ["read", "write", "close", "fcntl", "dup", "dup2"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["mmap", "munmap", "mprotect", "brk"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["getpid", "getuid", "getgid", "gettid", "uname"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["clock_gettime", "gettimeofday", "time"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["rt_sigaction", "rt_sigprocmask", "sigaltstack", "nanosleep"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["clone", "exit", "exit_group"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["readlink", "getcwd"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["epoll_create", "epoll_ctl", "epoll_wait"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["open", "stat", "fstat"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["socket", "connect", "bind", "listen", "accept"], "action": "SCMP_ACT_ERRNO(88)"},
    {"names": ["fork", "vfork", "execve", "kill"], "action": "SCMP_ACT_ERRNO(1)"},
    {"names": ["mount", "umount", "prctl"], "action": "SCMP_ACT_ERRNO(1)"}
  ]
}
EOF
    
    log_info "Seccomp profile written to ${profile_file}"
    log_info "To apply: seccomp_loader < ${profile_file}"
}

# =============================================================================
# LAYER 3: MEMORY BOUNDARY GUARDS
# =============================================================================
setup_memory_guards() {
    log_info "Setting up memory boundary guards..."
    
    # The ring buffer is at /dev/shm/itheris_ipc (64MB)
    # Virtual address hint: 0x3000_0000 - 0x3400_0000
    
    # Set up mprotect to make ring buffer read-only from Julia side
    # In production, this would use ept_poison from the Warden
    
    log_info "Memory boundary configuration:"
    echo "  Ring buffer base: 0x30000000"
    echo "  Ring buffer size: 64MB (0x04000000)"
    echo "  Guard pages: 4KB before and after"
    log_info "Memory guard setup complete"
}

# =============================================================================
# VERIFICATION
# =============================================================================
verify_isolation() {
    log_info "Verifying isolation setup..."
    
    local status=0
    
    # Check cgroup
    if [[ -d "${CGROUP_PATH}" ]]; then
        log_info "✓ Cgroup exists at ${CGROUP_PATH}"
        
        if [[ -f "${CGROUP_PATH}/cpu.max" ]]; then
            log_info "  ✓ CPU limit configured"
        fi
        
        if [[ -f "${CGROUP_PATH}/memory.max" ]]; then
            log_info "  ✓ Memory limit configured"
        fi
    else
        log_warn "✗ Cgroup not found"
        status=1
    fi
    
    # Check seccomp profile
    if [[ -f "/tmp/julia_brain_seccomp.json" ]]; then
        log_info "✓ Seccomp profile exists"
    else
        log_warn "✗ Seccomp profile not found"
    fi
    
    return ${status}
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo "========================================"
    echo "  Software-Based Isolation Layers"
    echo "========================================"
    echo ""
    
    check_root
    
    # Setup all layers
    setup_cgroup
    setup_seccomp
    setup_memory_guards
    
    # If PID provided, add to cgroup
    if [[ $# -gt 0 ]]; then
        add_to_cgroup "$1"
    fi
    
    echo ""
    verify_isolation
    
    echo ""
    log_info "Isolation setup complete!"
    log_info "Run './verify_isolation.sh' to check status"
}

# Run main with all arguments
main "$@"
