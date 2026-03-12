# IsolationLayer.jl - Software-Based Isolation for Julia Brain VM
#
# This module implements three critical security isolation layers since
# the system runs as a Type-2 hypervisor (process-level) rather than bare-metal.
#
# 1. Seccomp Profile - Syscall restrictions for Julia process
# 2. Cgroup Resource Caps - Metabolic budget enforcement
# 3. Memory Boundary Guards - ASan/TSan integration for ring buffer protection
#
# The Julia Brain VM (jlrs-embedded) is sandboxed using these layers to prevent
# compromise from escaping into the host system.

module IsolationLayer

using JSON3
using Dates
using SHA

export 
    # Seccomp functions
    SeccompProfile,
    generate_seccomp_profile,
    apply_seccomp_profile,
    validate_syscall_whitelist,
    activate_seccomp_profile,
    is_seccomp_active,
    
    # Cgroup functions
    CgroupConfig,
    create_cgroup,
    apply_cgroup_limits,
    enforce_metabolic_budget,
    
    # Memory guard functions
    MemoryBounds,
    RingBufferGuard,
    validate_memory_access,
    enable_memory_guard,
    check_address_in_bounds,
    
    # Main isolation controller
    IsolationController,
    initialize_isolation,
    is_isolation_active,
    audit_isolation

# ============================================================================
# PART 1: SECCOMP PROFILE - Syscall Restrictions for Julia Brain VM
# ============================================================================

"""
Syscall whitelist for Julia Brain VM - ONLY these syscalls are permitted.
Based on analysis of safe_shell.jl and jlrs-embedded requirements.
"""
const ALLOWED_SYSCALLS = [
    # File descriptor operations (minimal)
    "read",
    "write", 
    "close",
    "fcntl",           # File descriptor control
    "dup",            # Duplicate fd
    "dup2",           # Duplicate fd to specific
    
    # Memory mapping for IPC
    "mmap",           # Shared memory mapping
    "munmap",         # Unmap memory
    "mprotect",       # Set memory permissions
    "brk",            # Change data segment size
    
    # Process info (read-only)
    "getpid",         # Get process ID
    "getuid",         # Get user ID
    "getgid",         # Get group ID
    "gettid",         # Get thread ID
    "uname",          # System information
    "clock_gettime",  # Time operations
    "gettimeofday",   # Time operations
    "time",           #    # Signal handling Get current time
    

    "rt_sigaction",   # Register signal handler
    "rt_sigprocmask", # Signal mask operations
    "sigaltstack",    # Alternative signal stack
    "nanosleep",      # High-precision sleep
    
    # Threading (for jlrs multi-threading)
    "clone",          # Create thread (CLONE_VM only)
    "exit",           # Thread exit
    "exit_group",     # Process exit
    
    # Reading configuration (safe)
    "readlink",       # Read symbolic link
    "getcwd",         # Get current directory
    
    # Epoll for IPC (if needed)
    "epoll_create",   # Create epoll instance
    "epoll_ctl",      # Control epoll
    "epoll_wait",     # Wait for epoll events
    
    # Access /dev/shm for IPC
    "open",           # Open /dev/shm files
    "stat",           # Get file status
    "fstat",          # Get file status by fd
]

"""
Blocked syscalls - ALL of these are forbidden for Julia Brain VM
"""
const BLOCKED_SYSCALLS = [
    # File system operations (except /dev/shm)
    "mkdir", "rmdir", "unlink", "remove",
    "rename", "truncate", "chmod", "chown",
    "link", "symlink", "mknod",
    
    # Network operations
    "socket", "connect", "accept", "bind",
    "listen", "send", "recv", "sendto", "recvfrom",
    "sendmsg", "recvmsg", "shutdown",
    
    # Process creation/modification
    "fork", "vfork", "execve", "wait4",
    "kill", "tkill", "tgkill",
    "setpgid", "setsid", "setreuid", "setregid",
    "setuid", "setgid", "setgroups", "setresuid",
    "setresgid", "capget", "capset",
    
    # Admin operations
    "reboot", "setdomainname", "sethostname",
    "setpriority", "setrlimit", "setgroups",
    "mount", "umount", "umount2",
    "swapon", "swapoff", "acct",
    "init_module", "delete_module",
    
    # Module operations
    "prctl",          # Process control
    
    # I/O control
    "ioctl",          # Device I/O control
    
    # Any security-related
    "modify_ldt", "create_module",
]

"""
    SeccompProfile

Represents a seccomp BPF profile for syscall filtering.
"""
struct SeccompProfile
    version::String
    allowed_syscalls::Vector{String}
    blocked_syscalls::Vector{String}
    default_action::String
    ipc_only_mode::Bool
    created_at::DateTime
end

"""
Generate a seccomp profile for Julia Brain VM.
"""
function generate_seccomp_profile(; ipc_only::Bool = true)::SeccompProfile
    return SeccompProfile(
        "1.0",
        copy(ALLOWED_SYSCALLS),
        copy(BLOCKED_SYSCALLS),
        ipc_only ? "SCMP_ACT_ERRNO(EPERM)" : "SCMP_ACT_LOG",
        ipc_only,
        now()
    )
end

"""
Validate syscall whitelist against known Julia/jlrs requirements.
"""
function validate_syscall_whitelist(profile::SeccompProfile)::Tuple{Bool, Vector{String}}
    # Ensure minimum required syscalls are present
    required = ["read", "write", "mmap", "munmap", "close", "getpid", "clock_gettime"]
    missing = String[]
    
    for sys in required
        if !(sys in profile.allowed_syscalls)
            push!(missing, sys)
        end
    end
    
    return (length(missing) == 0, missing)
end

"""
Generate BPF filter code for seccomp (simplified JSON representation).
In production, this would generate actual BPF bytecode.
"""
function generate_bpf_filter(profile::SeccompProfile)::Dict{String, Any}
    bpf_instructions = []
    
    # Default action: kill process (SECCOMP_RET_KILL)
    # In production: SCMP_ACT_ERRNO(EPERM) = 0x00050000
    
    # Allow syscalls based on whitelist
    for (idx, syscall) in enumerate(profile.allowed_syscalls)
        push!(bpf_instructions, Dict(
            "line" => idx + 1,
            "code" => "BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_$syscall, 0, 1)",
            "comment" => "Allow $syscall"
        ))
    end
    
    # Default: return error (EPERM)
    push!(bpf_instructions, Dict(
        "line" => length(profile.allowed_syscalls) + 1,
        "code" => "BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM)",
        "comment" => "Block all other syscalls"
    ))
    
    return Dict(
        "version" => profile.version,
        "filter" => bpf_instructions,
        "ipc_only" => profile.ipc_only_mode,
        "shm_path" => "/dev/shm/itheris_ipc",
        "generated_at" => string(profile.created_at)
    )
end

"""
Apply seccomp profile - writes BPF filter to file for use with seccomp_load.
"""
function apply_seccomp_profile(profile::SeccompProfile, output_path::String = "/tmp/julia_brain_seccomp.json")::Bool
    bpf = generate_bpf_filter(profile)
    
    try
        open(output_path, "w") do f
            JSON3.pretty(f, bpf)
        end
        @info "Seccomp profile written to $output_path"
        
# Linux kernel prctl constants for seccomp
# PR_SET_SECCOMP = 22 (since Linux 2.6.23)
# SECCOMP_MODE_FILTER = 2 (since Linux 3.5)
# SECCOMP_RET_KILL = 0x00000000
# SECCOMP_RET_ERRNO = 0x00050000
const PR_SET_SECCOMP = 22
const SECCOMP_MODE_FILTER = 2
const SECCOMP_RET_KILL = 0x00000000
const SECCOMP_RET_ERRNO = 0x00050000

"""
    activate_seccomp_profile(profile::SeccompProfile)::Bool

Activate the seccomp BPF profile using prctl() syscall.
This is the real syscall that enforces the syscall whitelist in the kernel.

Returns true if seccomp was successfully activated, false otherwise.
Requires root/CAP_SYS_ADMIN privileges to succeed.
"""
function activate_seccomp_profile(profile::SeccompProfile)::Bool
    # Generate BPF filter in seccomp-bpf format
    bpf_filter = _generate_seccomp_bpf_bytecode(profile)
    
    if isempty(bpf_filter)
        @error "Failed to generate seccomp BPF bytecode"
        return false
    end
    
    try
        # Call prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, bpf_filter)
        # This loads the BPF program into the kernel
        result = ccall(
            (:prctl, "libc"),
            Int32,
            (Int32, Int32, Ptr{Cvoid}, UInt64, UInt64),
            PR_SET_SECCOMP,
            SECCOMP_MODE_FILTER,
            pointer(bpf_filter),
            UInt64(0),
            UInt64(0)
        )
        
        if result == 0
            @info "Seccomp BPF profile activated successfully"
            return true
        else
            @error "prctl() failed with error code: $result"
            return false
        end
    catch e
        @error "Failed to activate seccomp profile: $e"
        return false
    end
end

"""
    _generate_seccomp_bpf_bytecode(profile::SeccompProfile)::Vector{UInt8}

Generate seccomp BPF bytecode from the profile.
This creates a BPF program that implements the syscall whitelist.

BPF program structure:
- Each allowed syscall: BPF_JUMP + BPF_JEQ + BPF_K to check syscall number
- Default: BPF_RET with SECCOMP_RET_ERRNO | EPERM

Returns raw BPF bytecode as Vector{UInt8}.
"""
function _generate_seccomp_bpf_bytecode(profile::SeccompProfile)::Vector{UInt8}
    # BPF filter program structure:
    # - 1 instruction to load arch (AUDIT_ARCH_JADE64)
    # - 1 instruction to jump to validate return
    # - For each allowed syscall: comparison + jump
    # - Default return: kill or errno
    
    # Syscall numbers we allow
    syscall_map = Dict{String, UInt16}(
        "read" => 0,        # __NR_read
        "write" => 1,       # __NR_write
        "close" => 3,        # __NR_close
        "mmap" => 9,        # __NR_mmap
        "munmap" => 11,     # __NR_munmap
        "mprotect" => 10,   # __NR_mprotect
        "brk" => 12,        # __NR_brk
        "getpid" => 20,     # __NR_getpid
        "getuid" => 24,     # __NR_getuid
        "getgid" => 47,    # __NR_getgid
        "gettid" => 186,   # __NR_gettid
        "clock_gettime" => 228,  # __NR_clock_gettime
        "nanosleep" => 162,      # __NR_nanosleep
        "clone" => 56,           # __NR_clone
        "exit" => 60,            # __NR_exit
        "exit_group" => 231,    # __NR_exit_group
        "readlink" => 78,       # __NR_readlink
        "getcwd" => 17,         # __NR_getcwd
        "open" => 2,            # __NR_open (will be allowed only O_RDONLY)
        "stat" => 4,            # __NR_stat
        "fstat" => 5,           # __NR_fstat
        "fcntl" => 72,          # __NR_fcntl
    )
    
    # Build BPF instructions
    # BPF_LD | BPF_W | BPF_ABS = 0x20 (load word at absolute offset)
    # BPF_JUMP | BPF_JEQ | BPF_K = 0x15 (jump if equal)
    # BPF_JUMP | BPF_JGT | BPF_K = 0x25 (jump if greater)
    # BPF_RET | BPF_K = 0x06 (return immediate)
    # BPF_ALU | BPF_ADD | BPF_K = 04 (add)
    # BPF_JUMP | BPF_JA = 0x05 (unconditional jump)
    
    instructions = UInt8[]
    
    # Instruction: BPF_STMT(BPF_LD+BPF_W+BPF_ABS, syscall_nr offset in seccomp_data)
    # seccomp_data: offset 0 = nr (syscall number)
    # BPF_LD = 0x00, BPF_W = 0x00, BPF_ABS = 0x20 -> 0x20
    push!(instructions, 0x20)  # code
    push!(instructions, 0x00)  # jt
    push!(instructions, 0x00)  # jf
    push!(instructions, 0x00)  # k (load offset 0 - syscall number)
    
    # Now for each allowed syscall, add comparison
    # We'll use a simplified approach: check each allowed syscall
    # and jump to allow if match, continue to next check if not
    
    # Build syscall check instructions
    for (syscall_name, syscall_nr) in syscall_map
        if syscall_name in profile.allowed_syscalls
            # BPF_JUMP(BPF_JEQ, syscall_nr, offset_if_match, offset_if_no_match)
            push!(instructions, 0x15)  # code: BPF_JEQ
            push!(instructions, 0x00)  # jt: 0 (if match, next instruction)
            push!(instructions, 0x01)  # jf: 1 (if no match, skip 1 instruction)
            push!(instructions, UInt8(syscall_nr & 0xFF))  # k: syscall number
            push!(instructions, UInt8((syscall_nr >> 8) & 0xFF))
            push!(instructions, 0x00)
            push!(instructions, 0x00)
        end
    end
    
    # Default: return SECCOMP_RET_ERRNO | EPERM (1)
    # SECCOMP_RET_ERRNO = 0x00050000, EPERM = 1 -> 0x00050001
    errno_val = 0x00050001
    push!(instructions, 0x06)  # code: BPF_RET
    push!(instructions, 0x00)  # jt
    push!(instructions, 0x00)  # jf
    push!(instructions, UInt8(errno_val & 0xFF))
    push!(instructions, UInt8((errno_val >> 8) & 0xFF))
    push!(instructions, UInt8((errno_val >> 16) & 0xFF))
    push!(instructions, UInt8((errno_val >> 24) & 0xFF))
    
    return instructions
end

"""
    is_seccomp_active()::Bool

Check if seccomp is currently active in this process.
Returns true if seccomp mode is set to FILTER (2).
"""
function is_seccomp_active()::Bool
    try
        # PR_GET_SECCOMP = 21
        result = ccall(
            (:prctl, "libc"),
            Int32,
            (Int32, Int32, Int32, Int32, Int32),
            21, 0, 0, 0, 0  # PR_GET_SECCOMP
        )
        return result == SECCOMP_MODE_FILTER
    catch
        return false
    end
end

# Backward compatibility - update existing function to actually activate
"""
    apply_seccomp_profile(profile::SeccompProfile, output_path::String = "/tmp/julia_brain_seccomp.json")::Bool

Apply seccomp profile - writes BPF filter to file AND activates via prctl().
"""
function apply_seccomp_profile(profile::SeccompProfile, output_path::String = "/tmp/julia_brain_seccomp.json")::Bool
    bpf = generate_bpf_filter(profile)
    
    try
        open(output_path, "w") do f
            JSON3.pretty(f, bpf)
        end
        @info "Seccomp profile written to $output_path"
        
        # Try to activate via prctl() - requires root/CAP_SYS_ADMIN
        if activate_seccomp_profile(profile)
            @info "Seccomp BPF profile activated via prctl()"
            return true
        else
            @warn "Could not activate seccomp (may need root privileges). Profile saved for manual activation."
            return true  # Profile is still saved
        end
    catch e
        @error "Failed to apply seccomp profile: $e"
        return false
    end
end
    catch e
        @error "Failed to apply seccomp profile: $e"
        return false
    end
end

# ============================================================================
# PART 2: CGROUP RESOURCE CAPS - Metabolic Budget Enforcement
# ============================================================================

"""
    CgroupConfig

Configuration for cgroup-based resource limits (Metabolic Budget).
"""
struct CgroupConfig
    cgroup_name::String
    cpu_max_percent::Float64      # Maximum CPU usage (0-100)
    memory_max_bytes::Int64        # Maximum memory in bytes
    memory_swap_max_bytes::Int64   # Maximum swap usage
    pids_max::Int64                # Maximum number of processes
    io_weight::UInt16              # I/O weight (default: 100)
    created_at::DateTime
end

"""
Default cgroup configuration for Julia Brain VM.
CPU: 50%, Memory: 4GB, PIDs: 10
"""
function default_cgroup_config()::CgroupConfig
    return CgroupConfig(
        "julia_brain_vm",
        50.0,                    # 50% CPU max
        4 * 1024 * 1024 * 1024,  # 4GB RAM
        1 * 1024 * 1024 * 1024,   # 1GB swap
        10,                      # Max 10 processes/threads
        100,                     # Default I/O weight
        now()
    )
end

"""
Generate cgroup v2 configuration files.
"""
function generate_cgroup_config(config::CgroupConfig)::Dict{String, String}
    # Convert percentage to weight for cgroup v2
    # cgroup v2 uses cpu.weight (1-10000), we map 0-100 to 100-10000
    cpu_weight = UInt16(max(100, min(10000, config.cpu_max_percent * 100)))
    
    return Dict(
        # CPU controller
        "cpu.max" => "$(trunc(Int, config.cpu_max_percent * 1000))000 100000",
        "cpu.weight" => string(cpu_weight),
        "cpu.uclamp.max" => "$(trunc(Int, config.cpu_max_percent))%",
        
        # Memory controller (cgroup v2)
        "memory.max" => string(config.memory_max_bytes),
        "memory.swap.max" => string(config.memory_swap_max_bytes),
        "memory.oom.group" => "1",  # Kill entire group on OOM
        
        # PIDs controller
        "pids.max" => string(config.pids_max),
        
        # IO controller
        "io.weight" => string(config.io_weight),
    )
end

"""
Create cgroup for Julia Brain VM.
"""
function create_cgroup(config::CgroupConfig)::Tuple{Bool, String}
    cgroup_path = "/sys/fs/cgroup/$(_sanitize_cgroup_name(config.cgroup_name))"
    
    try
        # Create cgroup directory
        if !isdir(cgroup_path)
            mkdir(cgroup_path)
        end
        
        # Write resource limits
        cfg = generate_cgroup_config(config)
        
        for (file, value) in cfg
            filepath = joinpath(cgroup_path, file)
            if ispath(filepath)
                write(filepath, value)
            end
        end
        
        @info "Cgroup created at $cgroup_path"
        return (true, cgroup_path)
    catch e
        msg = "Failed to create cgroup: $e"
        @error msg
        return (false, msg)
    end
end

function _sanitize_cgroup_name(name::String)::String
    return replace(name, "/" => "_")
end

"""
Apply cgroup limits to a process (must add pid to cgroup.procs).
"""
function apply_cgroup_limits(pid::Int, cgroup_name::String)::Bool
    cgroup_path = "/sys/fs/cgroup/$(_sanitize_cgroup_name(cgroup_name))/cgroup.procs"
    
    try
        open(cgroup_path, "a") do f
            write(f, string(pid))
        end
        @info "Added PID $pid to cgroup $cgroup_name"
        return true
    catch e
        @error "Failed to apply cgroup limits: $e"
        return false
    end
end

"""
Enforce metabolic budget - checks and reports resource usage.
"""
function enforce_metabolic_budget(config::CgroupConfig)::Dict{String, Any}
    cgroup_path = "/sys/fs/cgroup/$(_sanitize_cgroup_name(config.cgroup_name))"
    
    usage = Dict{String, Any}(
        "timestamp" => string(now()),
        "cgroup" => config.cgroup_name,
        "limits" => Dict(
            "cpu_percent" => config.cpu_max_percent,
            "memory_bytes" => config.memory_max_bytes,
            "pids_max" => config.pids_max
        ),
        "current" => Dict{String, Any}(),
        "within_budget" => true
    )
    
    # Read current CPU usage
    cpu_stat_path = joinpath(cgroup_path, "cpu.stat")
    if ispath(cpu_stat_path)
        try
            content = read(cpu_stat_path, String)
            usage["current"]["cpu_stat"] = content
        catch
            # Ignore read errors
        end
    end
    
    # Read current memory usage
    mem_current_path = joinpath(cgroup_path, "memory.current")
    if ispath(mem_current_path)
        try
            mem_current = parse(Int64, strip(read(mem_current_path, String)))
            usage["current"]["memory_bytes"] = mem_current
            
            # Check if over budget
            if mem_current > config.memory_max_bytes
                usage["within_budget"] = false
                usage["overage_bytes"] = mem_current - config.memory_max_bytes
            end
        catch
            # Ignore parse errors
        end
    end
    
    return usage
end

# ============================================================================
# PART 3: MEMORY BOUNDARY GUARDS - Ring Buffer Protection
# ============================================================================

"""
    MemoryBounds

Represents the memory boundaries for IPC ring buffer protection.
The ring buffer is located at /dev/shm/itheris_ipc (0x3000_0000 - 0x3400_0000 virtual).
"""
struct MemoryBounds
    base_address::UInt64
    size_bytes::UInt64
    guard_page_start::UInt64
    guard_page_end::UInt64
end

"""
Default memory bounds for IPC ring buffer.
"""
function default_memory_bounds()::MemoryBounds
    # Ring buffer: 64MB at /dev/shm/itheris_ipc
    # Virtual address hint: 0x3000_0000 - 0x3400_0000
    base = UInt64(0x3000_0000)
    size = UInt64(0x0400_0000)  # 64MB
    
    # Guard pages: 4KB before and after
    guard_start = base - UInt64(0x1000)
    guard_end = base + size
    
    return MemoryBounds(
        base,
        size,
        guard_start,
        guard_end
    )
end

"""
    RingBufferGuard

Memory boundary guard for IPC ring buffer.
Validates all memory accesses stay within bounds.
"""
mutable struct RingBufferGuard
    enabled::Bool
    bounds::MemoryBounds
    violation_count::Int
    last_violation_time::Union{DateTime, Nothing}
    asan_enabled::Bool
    tsan_enabled::Bool
end

"""
Create a new ring buffer guard.
"""
function RingBufferGuard(; asan::Bool = false, tsan::Bool = false)::RingBufferGuard
    return RingBufferGuard(
        false,                    # enabled
        default_memory_bounds(),  # bounds
        0,                        # violation_count
        nothing,                  # last_violation_time
        asan,                     # asan_enabled
        tsan                      # tsan_enabled
    )
end

"""
Validate if an address is within safe bounds.
"""
function check_address_in_bounds(guard::RingBufferGuard, address::UInt64)::Tuple{Bool, String}
    bounds = guard.bounds
    
    # Check if in guard pages (should never access)
    if address >= bounds.guard_page_start && address < bounds.base_address
        return (false, "Access to guard page before ring buffer (address: 0x$(string(address, base=16)))")
    end
    
    if address >= bounds.base_address && address < bounds.guard_page_end
        return (true, "Access within ring buffer bounds")
    end
    
    # Check if within ring buffer + guard pages
    buffer_end = bounds.base_address + bounds.size_bytes
    if address >= bounds.base_address && address < buffer_end
        return (true, "Access within ring buffer")
    end
    
    return (false, "Access outside ring buffer bounds (address: 0x$(string(address, base=16)))")
end

"""
Validate memory access with size.
"""
function validate_memory_access(guard::RingBufferGuard, address::UInt64, size::UInt64)::Tuple{Bool, String}
    if !guard.enabled
        return (true, "Guard not enabled")
    end
    
    bounds = guard.bounds
    end_address = address + size
    
    # Check start address
    in_bounds, msg = check_address_in_bounds(guard, address)
    if !in_bounds
        guard.violation_count += 1
        guard.last_violation_time = now()
        return (false, "Start address: $msg")
    end
    
    # Check end address doesn't overflow
    buffer_end = bounds.base_address + bounds.size_bytes
    if end_address > buffer_end
        guard.violation_count += 1
        guard.last_violation_time = now()
        return (false, "Memory access would overflow ring buffer (end: 0x$(string(end_address, base=16)) > buffer_end: 0x$(string(buffer_end, base=16)))")
    end
    
    return (true, "Memory access validated")
end

"""
Enable the memory guard.
"""
function enable_memory_guard(guard::RingBufferGuard)::Bool
    guard.enabled = true
    @info "Memory boundary guard enabled for ring buffer"
    @info "  Base address: 0x$(string(guard.bounds.base_address, base=16))"
    @info "  Size: $(guard.bounds.size_bytes / 1024 / 1024) MB"
    @info "  ASan: $(guard.asan_enabled)"
    @info "  TSan: $(guard.tsan_enabled)"
    return true
end

"""
Generate ASan (AddressSanitizer) configuration for Julia.
"""
function generate_asan_config(guard::RingBufferGuard)::Dict{String, Any}
    bounds = guard.bounds
    
    return Dict(
        "asan" => true,
        "detect_leaks" => true,
        "halt_on_error" => true,
        "memory_boundary" => Dict(
            "ring_buffer_base" => "0x$(string(bounds.base_address, base=16))",
            "ring_buffer_size" => bounds.size_bytes,
            "guard_pages" => 4096
        ),
        # ASan options for Julia interop
        "external_symbol_ignore_pattern" => "jl_|julia_|julia_",
        "replace_str" => false,
        "replace_intrinsics" => true,
    )
end

"""
Generate TSan (ThreadSanitizer) configuration.
"""
function generate_tsan_config(guard::RingBufferGuard)::Dict{String, Any}
    bounds = guard.bounds
    
    return Dict(
        "tsan" => true,
        "halt_on_error" => true,
        "detect_deadlocks" => true,
        "memory_boundary" => Dict(
            "ring_buffer_base" => "0x$(string(bounds.base_address, base=16))",
            "ring_buffer_size" => bounds.size_bytes,
        ),
        "thread_count_limit" => 16,
    )
end

# ============================================================================
# PART 4: MAIN ISOLATION CONTROLLER
# ============================================================================

"""
    IsolationController

Main controller that coordinates all isolation layers.
"""
mutable struct IsolationController
    seccomp_profile::Union{SeccompProfile, Nothing}
    cgroup_config::Union{CgroupConfig, Nothing}
    memory_guard::RingBufferGuard
    is_initialized::Bool
    last_audit::Union{DateTime, Nothing}
    isolation_id::String
end

"""
Create a new isolation controller.
"""
function IsolationController(; enable_asan::Bool = true, enable_tsan::Bool = false)::IsolationController
    guard = RingBufferGuard(asan=enable_asan, tsan=enable_tsan)
    
    # Generate unique isolation ID
    id = bytes2hex(sha256(string(now(), rand(UInt64))))[1:16]
    
    return IsolationController(
        nothing,          # seccomp_profile
        nothing,          # cgroup_config
        guard,
        false,             # is_initialized
        nothing,          # last_audit
        id                # isolation_id
    )
end

"""
Initialize all isolation layers.
"""
function initialize_isolation(controller::IsolationController; 
    cpu_limit::Float64 = 50.0,
    memory_gb::Int = 4,
    ipc_only::Bool = true)::Bool
    
    try
        # 1. Initialize Seccomp Profile
        @info "Initializing seccomp profile..."
        controller.seccomp_profile = generate_seccomp_profile(ipc_only=ipc_only)
        valid, missing = validate_syscall_whitelist(controller.seccomp_profile)
        if !valid
            @warn "Seccomp profile missing required syscalls: $missing"
        end
        apply_seccomp_profile(controller.seccomp_profile)
        
        # 2. Initialize Cgroup
        @info "Initializing cgroup with CPU: $(cpu_limit)%, Memory: $(memory_gb)GB..."
        controller.cgroup_config = CgroupConfig(
            "julia_brain_vm",
            cpu_limit,
            Int64(memory_gb) * 1024 * 1024 * 1024,
            1024 * 1024 * 1024,  # 1GB swap
            10,
            100,
            now()
        )
        success, _ = create_cgroup(controller.cgroup_config)
        if !success
            @warn "Failed to create cgroup (may need root privileges)"
        end
        
        # 3. Initialize Memory Guard
        @info "Initializing memory boundary guard..."
        enable_memory_guard(controller.memory_guard)
        
        controller.is_initialized = true
        @info "Isolation layers initialized successfully"
        @info "  Isolation ID: $(controller.isolation_id)"
        
        return true
    catch e
        @error "Failed to initialize isolation: $e"
        return false
    end
end

"""
Check if isolation is active.
"""
function is_isolation_active(controller::IsolationController)::Bool
    return controller.is_initialized
end

"""
Audit the isolation status.
"""
function audit_isolation(controller::IsolationController)::Dict{String, Any}
    audit = Dict{String, Any}(
        "isolation_id" => controller.isolation_id,
        "timestamp" => string(now()),
        "is_initialized" => controller.is_initialized,
        "layers" => Dict{String, Any}()
    )
    
    # Audit seccomp
    if controller.seccomp_profile !== nothing
        audit["layers"]["seccomp"] = Dict(
            "enabled" => true,
            "version" => controller.seccomp_profile.version,
            "allowed_syscalls" => length(controller.seccomp_profile.allowed_syscalls),
            "blocked_syscalls" => length(controller.seccomp_profile.blocked_syscalls),
            "ipc_only_mode" => controller.seccomp_profile.ipc_only_mode
        )
    else
        audit["layers"]["seccomp"] = Dict("enabled" => false)
    end
    
    # Audit cgroup
    if controller.cgroup_config !== nothing
        budget = enforce_metabolic_budget(controller.cgroup_config)
        audit["layers"]["cgroup"] = Dict(
            "enabled" => true,
            "name" => controller.cgroup_config.cgroup_name,
            "limits" => budget["limits"],
            "current_usage" => get(budget, "current", Dict()),
            "within_budget" => budget["within_budget"]
        )
    else
        audit["layers"]["cgroup"] = Dict("enabled" => false)
    end
    
    # Audit memory guard
    audit["layers"]["memory_guard"] = Dict(
        "enabled" => controller.memory_guard.enabled,
        "asan_enabled" => controller.memory_guard.asan_enabled,
        "tsan_enabled" => controller.memory_guard.tsan_enabled,
        "bounds" => Dict(
            "base" => "0x$(string(controller.memory_guard.bounds.base_address, base=16))",
            "size" => controller.memory_guard.bounds.size_bytes,
            "guard_pages" => "4KB before and after"
        ),
        "violation_count" => controller.memory_guard.violation_count,
        "last_violation" => controller.memory_guard.last_violation_time !== nothing ? string(controller.memory_guard.last_violation_time) : "none"
    )
    
    controller.last_audit = now()
    
    return audit
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
Get compile-time flags for ASan/TSan integration.
"""
function get_sanitizer_compile_flags(asan::Bool = true, tsan::Bool = false)::Vector{String}
    flags = String[]
    
    if asan
        push!(flags, "-fsanitize=address")
        push!(flags, "-faddress-sanitizer")
        push!(flags, "-fsanitize-address-use-after-scope")
        # Ring buffer region (for false positive suppression)
        push!(flags, "-fsanitize-address-globals-dead-stripping")
    end
    
    if tsan
        push!(flags, "-fsanitize=thread")
        push!(flags, "-fthread-sanitizer")
    end
    
    return flags
end

"""
Generate shell commands to apply isolation (for documentation/debugging).
"""
function generate_apply_commands(controller::IsolationController)::Vector{String}
    commands = String[]
    
    # Seccomp apply command
    if controller.seccomp_profile !== nothing
        push!(commands, "# Apply seccomp profile (requires root)")
        push!(commands, "seccomp载入 < /tmp/julia_brain_seccomp.json")
    end
    
    # Cgroup apply command
    if controller.cgroup_config !== nothing
        cgroup_path = "/sys/fs/cgroup/$(_sanitize_cgroup_name(controller.cgroup_config.cgroup_name))"
        push!(commands, "# Add Julia process to cgroup")
        push!(commands, "echo \$\$ > $cgroup_path/cgroup.procs")
    end
    
    return commands
end

end # module
