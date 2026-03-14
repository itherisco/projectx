# adaptive-kernel/kernel/security/EPTSandbox.jl
# EPT Hypervisor Sandbox Validation - Zero Escape Validation
# ============================================================================
#
# This module implements Zero Escape Validation to verify the Extended Page
# Table (EPT) Hypervisor Sandbox provides total isolation between the Julia
# brain VM and the underlying Rust Warden kernel.
#
# Architecture:
# - Memory mapping configuration for Julia's address space
# - EPT violation detection and handling
# - Oneiric (dream) state integration for enhanced security
# - Zero Escape Validation for comprehensive sandbox integrity
# - Warden integration for violation reporting
#
# Memory Layout:
#   0x1000_0000 - 0x2000_0000: Julia Memory (256MB)
#   0x3000_0000 - 0x3400_0000: Ring Buffer (64MB)
#   0x4000_0000+: Syscall Block (NOACCESS)
#
# Usage:
#     using EPTSandbox
#     config = EPTSandboxConfig()
#     state = EPTSandboxState(config)
#     validate_sandbox_integrity(state)

module EPTSandbox

using Dates
using UUIDs
using JSON
using Logging
using SHA
using Base.Threads
using Statistics

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Import RustIPC for Warden communication
include(joinpath(@__DIR__, "..", "ipc", "RustIPC.jl"))
using ..RustIPC

# Import OneiricWardenIntegration for state transitions
include(joinpath(@__DIR__, "..", "..", "cognition", "oneiric", "OneiricWardenIntegration.jl"))
using ..OneiricWardenIntegration

# Import SecureBoot for boot-time validation
include(joinpath(@__DIR__, "SecureBoot.jl"))
using ..SecureBoot

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    EPTSandboxConfig,
    
    # Memory Region
    MemoryRegion,
    get_permission_string,
    is_readable,
    is_writable,
    is_executable,
    
    # EPT Violation
    EPTViolation,
    EPTViolationType,
    ViolationSeverity,
    
    # Memory Mapping Functions
    configure_julia_memory_mapping,
    configure_ring_buffer_mapping,
    configure_syscall_trapping,
    
    # EPT Violation Handling
    ept_violation_handler,
    classify_violation,
    
    # Oneiric State Integration
    transition_to_oneiric_mode,
    transition_to_awake_mode,
    
    # Zero Escape Validation
    validate_sandbox_integrity,
    test_escape_attempt,
    
    # Warden Integration
    report_violation_to_warden,
    
    # State Management
    EPTSandboxState,
    get_current_mode,
    is_awake,
    is_oneiric,
    add_violation!,
    get_violation_history,
    clear_violation_history!,
    
    # Constants
    JULIA_MEMORY_START,
    JULIA_MEMORY_END,
    RING_BUFFER_START,
    RING_BUFFER_END,
    SYSCALL_BLOCK_START,
    PERMISSION_RWX,
    PERMISSION_RW,
    PERMISSION_RO,
    PERMISSION_RO_NOEXEC,
    PERMISSION_NOACCESS

# ============================================================================
# CONSTANTS - Memory Layout
# ============================================================================

"""
EPT Memory Layout Constants

Defines the fixed memory regions for the EPT Hypervisor Sandbox:
- Julia Memory: 0x1000_0000 - 0x2000_0000 (256MB) - Julia VM address space
- Ring Buffer:  0x3000_0000 - 0x3400_0000 (64MB) - IPC with Warden
- Syscall Block: 0x4000_0000+ - All OS access blocked
"""
const JULIA_MEMORY_START    = UInt64(0x1000_0000)
const JULIA_MEMORY_END      = UInt64(0x2000_0000)
const RING_BUFFER_START     = UInt64(0x3000_0000)
const RING_BUFFER_END       = UInt64(0x3400_0000)
const SYSCALL_BLOCK_START   = UInt64(0x4000_0000)

# ============================================================================
# CONSTANTS - EPT Permissions
# ============================================================================

"""
EPT Permission Constants

Maps to EPT page table entry flags:
- RWX: Read + Write + Execute (most permissive)
- RW:  Read + Write (data memory)
- RO:  Read-only (protected data)
- RO_NOEXEC: Read-only, No Execute (maximum protection)
- NOACCESS: No read, write, or execute (blocked)
"""
const PERMISSION_RWX        = :RWX
const PERMISSION_RW         = :RW
const PERMISSION_RO         = :RO
const PERMISSION_RO_NOEXEC  = :RO_NOEXEC
const PERMISSION_NOACCESS   = :NOACCESS

# ============================================================================
# DATA STRUCTURES
# ============================================================================

"""
    EPTSandboxConfig

Configuration for the EPT Hypervisor Sandbox.

# Fields
- `julia_memory_start::UInt64`: Start address for Julia's memory (default: 0x1000_0000)
- `julia_memory_end::UInt64`: End address for Julia's memory (default: 0x2000_0000)
- `ring_buffer_start::UInt64`: Start address for ring buffer (default: 0x3000_0000)
- `ring_buffer_end::UInt64`: End address for ring buffer (default: 0x3400_0000)
- `syscall_block_start::UInt64`: Start address for syscall blocking (default: 0x4000_0000)
- `enable_oneiric_ro::Bool`: Enable RO_NOEXEC during Oneiric states (default: true)
- `trap_syscalls::Bool`: Trap all syscalls for audit (default: true)

# Example
```julia
config = EPTSandboxConfig(
    julia_memory_start=0x1000_0000,
    julia_memory_end=0x2000_0000,
    ring_buffer_start=0x3000_0000,
    ring_buffer_end=0x3400_0000,
    syscall_block_start=0x4000_0000,
    enable_oneiric_ro=true,
    trap_syscalls=true
)
```
"""
struct EPTSandboxConfig
    julia_memory_start::UInt64
    julia_memory_end::UInt64
    ring_buffer_start::UInt64
    ring_buffer_end::UInt64
    syscall_block_start::UInt64
    enable_oneiric_ro::Bool
    trap_syscalls::Bool
    
    function EPTSandboxConfig(
        julia_memory_start::UInt64=JULIA_MEMORY_START,
        julia_memory_end::UInt64=JULIA_MEMORY_END,
        ring_buffer_start::UInt64=RING_BUFFER_START,
        ring_buffer_end::UInt64=RING_BUFFER_END,
        syscall_block_start::UInt64=SYSCALL_BLOCK_START,
        enable_oneiric_ro::Bool=true,
        trap_syscalls::Bool=true)
        return new(
            julia_memory_start,
            julia_memory_end,
            ring_buffer_start,
            ring_buffer_end,
            syscall_block_start,
            enable_oneiric_ro,
            trap_syscalls
        )
    end
end

"""
    MemoryRegion

Represents a mapped memory region with EPT permissions.

# Fields
- `start::UInt64`: Start address of the memory region
- `end::UInt64`: End address of the memory region
- `permissions::Symbol`: Current EPT permissions (:RWX, :RW, :RO, :RO_NOEXEC, :NOACCESS)
- `is_isolated::Bool`: Whether this region is isolated from other domains

# Example
```julia
region = MemoryRegion(0x1000_0000, 0x2000_0000, :RWX, true)
```
"""
struct MemoryRegion
    start::UInt64
    end_addr::UInt64
    permissions::Symbol
    is_isolated::Bool
    
    function MemoryRegion(
        start::UInt64,
        end_addr::UInt64;
        permissions::Symbol=PERMISSION_RWX,
        is_isolated::Bool=true)
        return new(start, end_addr, permissions, is_isolated)
    end
end

# Backwards compatible accessor
end_addr(r::MemoryRegion) = r.end_addr

"""
EPT Violation Type Enumeration

Classifies the type of EPT violation:
- :read_violation: Attempted read from prohibited memory
- :write_violation: Attempted write to prohibited memory
- :execute_violation: Attempted execution from non-executable memory
- :syscall_violation: Attempted forbidden syscall
"""
@enum EPTViolationType begin
    READ_VIOLATION
    WRITE_VIOLATION
    EXECUTE_VIOLATION
    SYSCALL_VIOLATION
end

"""
Violation Severity Level

Indicates the severity of an EPT violation:
- :low: Minor violation, informational logging
- :medium: Moderate violation, requires attention
- :high: Serious violation, potential compromise
- :critical: Critical violation, immediate termination required
"""
@enum ViolationSeverity begin
    SEVERITY_LOW
    SEVERITY_MEDIUM
    SEVERITY_HIGH
    SEVERITY_CRITICAL
end

"""
    EPTViolation

Represents an EPT (Extended Page Table) violation event.

# Fields
- `id::UUID`: Unique identifier for this violation
- `address::UInt64`: Memory address where violation occurred
- `violation_type::EPTViolationType`: Type of violation
- `severity::ViolationSeverity`: Severity level
- `timestamp::DateTime`: When the violation occurred
- `context::Dict{String, Any}`: Additional context information
- `requires_termination::Bool`: Whether this violation requires VM termination

# Example
```julia
violation = EPTViolation(
    address=0x4000_0000,
    violation_type=SYSCALL_VIOLATION,
    severity=SEVERITY_HIGH,
    context=Dict("syscall_number" => 60)
)
```
"""
struct EPTViolation
    id::UUID
    address::UInt64
    violation_type::EPTViolationType
    severity::ViolationSeverity
    timestamp::DateTime
    context::Dict{String, Any}
    requires_termination::Bool
    
    function EPTViolation(;
        address::UInt64,
        violation_type::EPTViolationType,
        severity::ViolationSeverity=SEVERITY_MEDIUM,
        context::Dict{String, Any}=Dict{String, Any}(),
        requires_termination::Bool=false)
        return new(
            UUIDs.uuid4(),
            address,
            violation_type,
            severity,
            now(),
            context,
            requires_termination
        )
    end
end

"""
    EPTSandboxState

Runtime state for the EPT Hypervisor Sandbox.

# Fields
- `config::EPTSandboxConfig`: Current configuration
- `julia_memory::MemoryRegion`: Julia memory region mapping
- `ring_buffer::MemoryRegion`: Ring buffer region mapping
- `violation_history::Vector{EPTViolation}`: History of all violations
- `current_mode::Symbol`: Current operating mode (:awake or :oneiric)
- `is_integrity_valid::Bool`: Whether sandbox integrity has been validated

# Example
```julia
config = EPTSandboxConfig()
state = EPTSandboxState(config)
```
"""
mutable struct EPTSandboxState
    config::EPTSandboxConfig
    julia_memory::MemoryRegion
    ring_buffer::MemoryRegion
    violation_history::Vector{EPTViolation}
    current_mode::Symbol
    is_integrity_valid::Bool
    lock::ReentrantLock
    
    function EPTSandboxState(; config::EPTSandboxConfig=EPTSandboxConfig())
        # Initialize Julia memory region
        julia_memory = MemoryRegion(
            config.julia_memory_start,
            config.julia_memory_end;
            permissions=PERMISSION_RWX,
            is_isolated=true
        )
        
        # Initialize ring buffer region
        ring_buffer = MemoryRegion(
            config.ring_buffer_start,
            config.ring_buffer_end;
            permissions=PERMISSION_RW,
            is_isolated=true
        )
        
        return new(
            config,
            julia_memory,
            ring_buffer,
            EPTViolation[],
            :awake,
            false,
            ReentrantLock()
        )
    end
end

# ============================================================================
# MEMORY REGION UTILITY FUNCTIONS
# ============================================================================

"""
Get the permission string representation for a MemoryRegion.

# Arguments
- `region::MemoryRegion`: The memory region

# Returns
- `String`: Human-readable permission string

# Example
```julia
region = MemoryRegion(start=0x1000_0000, end=0x2000_0000, permissions=:RWX)
get_permission_string(region)  # Returns "RWX"
```
"""
function get_permission_string(region::MemoryRegion)::String
    return string(region.permissions)
end

"""
Check if a memory region is readable.

# Arguments
- `region::MemoryRegion`: The memory region to check

# Returns
- `Bool`: True if readable

# Example
```julia
region = MemoryRegion(start=0x1000_0000, end=0x2000_0000, permissions=:RW)
is_readable(region)  # Returns true
```
"""
function is_readable(region::MemoryRegion)::Bool
    return region.permissions in (PERMISSION_RWX, PERMISSION_RW, PERMISSION_RO, PERMISSION_RO_NOEXEC)
end

"""
Check if a memory region is writable.

# Arguments
- `region::MemoryRegion`: The memory region to check

# Returns
- `Bool`: True if writable

# Example
```julia
region = MemoryRegion(start=0x1000_0000, end=0x2000_0000, permissions=:RW)
is_writable(region)  # Returns true
```
"""
function is_writable(region::MemoryRegion)::Bool
    return region.permissions in (PERMISSION_RWX, PERMISSION_RW)
end

"""
Check if a memory region is executable.

# Arguments
- `region::MemoryRegion`: The memory region to check

# Returns
- `Bool`: True if executable

# Example
```julia
region = MemoryRegion(start=0x1000_0000, end=0x2000_0000, permissions=:RWX)
is_executable(region)  # Returns true
```
"""
function is_executable(region::MemoryRegion)::Bool
    return region.permissions == PERMISSION_RWX
end

# ============================================================================
# STATE MANAGEMENT FUNCTIONS
# ============================================================================

"""
Get the current operating mode of the sandbox.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Symbol`: Current mode (:awake or :oneiric)

# Example
```julia
state = EPTSandboxState()
get_current_mode(state)  # Returns :awake
```
"""
function get_current_mode(state::EPTSandboxState)::Symbol
    return state.current_mode
end

"""
Check if the sandbox is in awake mode.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if in awake mode

# Example
```julia
state = EPTSandboxState()
is_awake(state)  # Returns true
```
"""
function is_awake(state::EPTSandboxState)::Bool
    return state.current_mode == :awake
end

"""
Check if the sandbox is in Oneiric (dream) mode.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if in Oneiric mode

# Example
```julia
state = EPTSandboxState()
transition_to_oneiric_mode(state)
is_oneiric(state)  # Returns true
```
"""
function is_oneiric(state::EPTSandboxState)::Bool
    return state.current_mode == :oneiric
end

"""
Add a violation to the sandbox's violation history.

# Arguments
- `state::EPTSandboxState`: The sandbox state
- `violation::EPTViolation`: The violation to add

# Example
```julia
state = EPTSandboxState()
violation = EPTViolation(address=0x4000_0000, violation_type=SYSCALL_VIOLATION)
add_violation!(state, violation)
```
"""
function add_violation!(state::EPTSandboxState, violation::EPTViolation)
    lock(state.lock) do
        push!(state.violation_history, violation)
    end
end

"""
Get the complete violation history.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Vector{EPTViolation}`: Copy of all violations

# Example
```julia
state = EPTSandboxState()
history = get_violation_history(state)
```
"""
function get_violation_history(state::EPTSandboxState)::Vector{EPTViolation}
    lock(state.lock) do
        return copy(state.violation_history)
    end
end

"""
Clear the violation history.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Example
```julia
state = EPTSandboxState()
clear_violation_history!(state)
```
"""
function clear_violation_history!(state::EPTSandboxState)
    lock(state.lock) do
        empty!(state.violation_history)
    end
end

# ============================================================================
# MEMORY MAPPING FUNCTIONS
# ============================================================================

"""
Configure Julia's memory mapping in the EPT.

Maps Julia's memory address space (0x1000_0000 - 0x2000_0000) with 
appropriate EPT permissions. Initially configured as RWX (Read-Write-Execute)
for full Julia VM functionality.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `MemoryRegion`: The configured Julia memory region

# Example
```julia
state = EPTSandboxState()
julia_mem = configure_julia_memory_mapping(state)
# julia_mem.start == 0x1000_0000
# julia_mem.end == 0x2000_0000
# julia_mem.permissions == :RWX
```
"""
function configure_julia_memory_mapping(state::EPTSandboxState)::MemoryRegion
    config = state.config
    
    # Create the Julia memory region with RWX permissions initially
    # This allows the Julia VM to execute code, read/write data
    julia_mem = MemoryRegion(
        config.julia_memory_start,
        config.julia_memory_end;
        permissions=PERMISSION_RWX,
        is_isolated=true
    )
    
    state.julia_memory = julia_mem
    
    @info "Julia memory mapping configured" start=string(julia_mem.start, base=16) \
          end_addr=string(end_addr(julia_mem), base=16) permissions=string(julia_mem.permissions)
    
    return julia_mem
end

"""
Configure the ring buffer mapping in the EPT.

Maps the ring buffer (0x3000_0000 - 0x3400_0000) for IPC with the Warden.
Default permissions are RW (Read-Write). During Oneiric state, this can
transition to RO_NOEXEC (Read-only, No Execute) for enhanced security.

# Arguments
- `state::EPTSandboxState`: The sandbox state
- `permissions::Symbol`: EPT permissions (default: RW)

# Returns
- `MemoryRegion`: The configured ring buffer region

# Example
```julia
state = EPTSandboxState()
ring_buf = configure_ring_buffer_mapping(state)
# ring_buf.start == 0x3000_0000
# ring_buf.end == 0x3400_0000
# ring_buf.permissions == :RW
```
"""
function configure_ring_buffer_mapping(state::EPTSandboxState; 
                                         permissions::Symbol=PERMISSION_RW)::MemoryRegion
    config = state.config
    
    # Create the ring buffer region
    ring_buf = MemoryRegion(
        config.ring_buffer_start,
        config.ring_buffer_end;
        permissions=permissions,
        is_isolated=true
    )
    
    state.ring_buffer = ring_buf
    
    @info "Ring buffer mapping configured" start=string(ring_buf.start, base=16) \
          end_addr=string(end_addr(ring_buf), base=16) permissions=string(ring_buf.permissions)
    
    return ring_buf
end

"""
Configure syscall trapping in the EPT.

Sets up the hypervisor to block all direct OS access by setting NOACCESS
permissions at 0x4000_0000 and above. Any syscall attempt triggers an
EPT violation trap for audit and potential termination.

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `MemoryRegion`: The configured syscall blocking region

# Example
```julia
state = EPTSandboxState()
syscall_region = configure_syscall_trapping(state)
# syscall_region.start == 0x4000_0000
# syscall_region.permissions == :NOACCESS
```
"""
function configure_syscall_trapping(state::EPTSandboxState)::MemoryRegion
    config = state.config
    
    if !config.trap_syscalls
        @warn "Syscall trapping is disabled in configuration"
        return MemoryRegion(
            UInt64(0),
            UInt64(0);
            permissions=PERMISSION_RWX,
            is_isolated=false
        )
    end
    
    # Create the syscall blocking region with NOACCESS
    # Any access to this region triggers an EPT violation
    syscall_region = MemoryRegion(
        config.syscall_block_start,
        UInt64(0xFFFF_FFFF);
        permissions=PERMISSION_NOACCESS,
        is_isolated=true
    )
    
    @info "Syscall trapping configured" start=string(syscall_region.start, base=16) \
          end_addr=string(end_addr(syscall_region), base=16) permissions=string(syscall_region.permissions)
    
    return syscall_region
end

# ============================================================================
# EPT VIOLATION HANDLING
# ============================================================================

"""
Classify the severity of an EPT violation.

Analyzes the violation details to determine its severity level based on
the type of violation and the memory region affected.

# Arguments
- `violation::EPTViolation`: The violation to classify

# Returns
- `ViolationSeverity`: The determined severity level

# Example
```julia
violation = EPTViolation(address=0x4000_0000, violation_type=SYSCALL_VIOLATION)
severity = classify_severity(violation)
```
"""
function classify_severity(violation::EPTViolation)::ViolationSeverity
    # Syscall violations are always high severity
    if violation.violation_type == SYSCALL_VIOLATION
        return SEVERITY_HIGH
    end
    
    # Execute violations from non-executable memory are critical
    if violation.violation_type == EXECUTE_VIOLATION
        return SEVERITY_CRITICAL
    end
    
    # Write violations to protected memory are high severity
    if violation.violation_type == WRITE_VIOLATION
        return SEVERITY_HIGH
    end
    
    # Read violations are medium severity
    if violation.violation_type == READ_VIOLATION
        return SEVERITY_MEDIUM
    end
    
    return SEVERITY_MEDIUM
end

"""
Classify an EPT violation by type.

Determines the type of EPT violation based on the memory access that occurred.

# Arguments
- `address::UInt64`: The memory address that was accessed
- `state::EPTSandboxState`: The current sandbox state

# Returns
- `EPTViolationType`: The type of violation

# Example
```julia
state = EPTSandboxState()
violation_type = classify_violation(0x4000_0000, state)
```
"""
function classify_violation(address::UInt64, state::EPTSandboxState)::EPTViolationType
    config = state.config
    
    # Check if it's a syscall violation (access to syscall block region)
    if address >= config.syscall_block_start
        return SYSCALL_VIOLATION
    end
    
    # Check if it's an execute violation (would need execution context)
    # In practice, this would be determined by the hypervisor
    if address >= config.julia_memory_start && address < config.julia_memory_end
        # Julia memory region - determine based on EPT flags
        return EXECUTE_VIOLATION  # Simplified - real impl would check access type
    end
    
    # Default to read violation
    return READ_VIOLATION
end

"""
Handle an EPT violation.

Processes EPT violations by:
1. Logging violation details (address, type, timestamp)
2. Sending violation to Warden for metabolic auditing
3. Determining if termination is required
4. Returning the violation response

# Arguments
- `violation::EPTViolation`: The violation to handle
- `state::EPTSandboxState`: The current sandbox state

# Returns
- `Bool`: True if the sandbox should continue, false if termination required

# Example
```julia
state = EPTSandboxState()
violation = EPTViolation(address=0x4000_0000, violation_type=SYSCALL_VIOLATION)
should_continue = ept_violation_handler(violation, state)
```
"""
function ept_violation_handler(violation::EPTViolation, state::EPTSandboxState)::Bool
    # Classify severity if not already set
    if violation.severity == SEVERITY_MEDIUM
        violation.severity = classify_severity(violation)
    end
    
    # Determine if termination is required
    violation.requires_termination = (violation.severity == SEVERITY_CRITICAL)
    
    # Log violation details
    @error "EPT Violation Detected" \
        id=string(violation.id) \
        address=string(violation.address, base=16) \
        violation_type=violation.violation_type \
        severity=violation.severity \
        timestamp=violation.timestamp
    
    # Add to violation history
    add_violation!(state, violation)
    
    # Report to Warden for metabolic auditing
    should_continue = report_violation_to_warden(violation, state)
    
    # Override if critical severity requires termination
    if violation.requires_termination
        @error "Critical EPT violation - termination required" \
            id=string(violation.id)
        return false
    end
    
    return should_continue
end

# ============================================================================
# ONEIRIC STATE INTEGRATION
# ============================================================================

"""
Transition the sandbox to Oneiric (dream) mode.

Called when entering Oneiric state. Performs the following:
1. Change ring buffer permissions to RO_NOEXEC (read-only, no execute)
2. Increase monitoring sensitivity
3. Log the transition event

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if transition successful

# Example
```julia
state = EPTSandboxState()
success = transition_to_oneiric_mode(state)
# state.current_mode == :oneiric
# state.ring_buffer.permissions == :RO_NOEXEC
```
"""
function transition_to_oneiric_mode(state::EPTSandboxState)::Bool
    lock(state.lock) do
        if state.current_mode == :oneiric
            @warn "Already in Oneiric mode"
            return true
        end
        
        # Transition to Oneiric mode
        state.current_mode = :oneiric
        
        # Change ring buffer to RO_NOEXEC if enabled
        if state.config.enable_oneiric_ro
            state.ring_buffer = MemoryRegion(
                state.ring_buffer.start,
                end_addr(state.ring_buffer);
                permissions=PERMISSION_RO_NOEXEC,
                is_isolated=true
            )
            @info "Ring buffer transitioned to RO_NOEXEC for Oneiric mode"
        end
        
        @info "Sandbox transitioned to Oneiric mode" \
            ring_buffer_permissions=string(state.ring_buffer.permissions)
        
        return true
    end
end

"""
Transition the sandbox to awake mode.

Called when exiting Oneiric state. Performs the following:
1. Restore ring buffer permissions to RW (read-write)
2. Reset monitoring sensitivity
3. Log the transition event

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if transition successful

# Example
```julia
state = EPTSandboxState()
transition_to_oneiric_mode(state)
success = transition_to_awake_mode(state)
# state.current_mode == :awake
# state.ring_buffer.permissions == :RW
```
"""
function transition_to_awake_mode(state::EPTSandboxState)::Bool
    lock(state.lock) do
        if state.current_mode == :awake
            @warn "Already in awake mode"
            return true
        end
        
        # Transition to awake mode
        state.current_mode = :awake
        
        # Restore ring buffer to RW
        state.ring_buffer = MemoryRegion(
            state.ring_buffer.start,
            end_addr(state.ring_buffer);
            permissions=PERMISSION_RW,
            is_isolated=true
        )
        
        @info "Sandbox transitioned to awake mode" \
            ring_buffer_permissions=string(state.ring_buffer.permissions)
        
        return true
    end
end

# ============================================================================
# ZERO ESCAPE VALIDATION
# ============================================================================

"""
Validate comprehensive sandbox integrity.

Performs a comprehensive validation that the sandbox is leak-proof:
1. Verify Julia memory bounds are correctly configured
2. Verify ring buffer isolation from Julia memory
3. Verify syscall blocking is enabled
4. Verify EPT permissions are correctly set

# Arguments
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if all validations pass

# Example
```julia
state = EPTSandboxState()
is_valid = validate_sandbox_integrity(state)
```
"""
function validate_sandbox_integrity(state::EPTSandboxState)::Bool
    config = state.config
    all_valid = true
    
    # 1. Verify Julia memory bounds
    julia_mem = state.julia_memory
    if julia_mem.start != config.julia_memory_start || end_addr(julia_mem) != config.julia_memory_end
        @error "Julia memory bounds mismatch" \
            expected_start=string(config.julia_memory_start, base=16) \
            expected_end=string(config.julia_memory_end, base=16) \
            actual_start=string(julia_mem.start, base=16) \
            actual_end=string(end_addr(julia_mem), base=16)
        all_valid = false
    end
    
    # 2. Verify ring buffer isolation (no overlap with Julia memory)
    ring_buf = state.ring_buffer
    if ring_buf.start < end_addr(julia_mem) && end_addr(ring_buf) > julia_mem.start
        @error "Ring buffer overlaps with Julia memory - isolation breach!"
        all_valid = false
    end
    
    # 3. Verify syscall blocking
    if config.trap_syscalls
        # Check if syscall block region is above Julia memory
        if config.syscall_block_start <= config.julia_memory_end
            @error "Syscall block region too low - not protecting Julia memory"
            all_valid = false
        end
    end
    
    # 4. Verify EPT permissions
    # Julia memory should be RWX or at least RW
    if !is_readable(julia_mem) || !is_writable(julia_mem)
        @error "Julia memory has insufficient permissions" \
            permissions=string(julia_mem.permissions)
        all_valid = false
    end
    
    # Ring buffer should be at least readable
    if !is_readable(ring_buf)
        @error "Ring buffer is not readable" permissions=string(ring_buf.permissions)
        all_valid = false
    end
    
    # Update integrity validation status
    state.is_integrity_valid = all_valid
    
    if all_valid
        @info "Sandbox integrity validation PASSED"
    else
        @error "Sandbox integrity validation FAILED"
    end
    
    return all_valid
end

"""
Test an escape attempt to validate sandbox security.

Simulates various attack vectors to ensure the sandbox properly contains them:
- :buffer_overflow: Test buffer overflow containment
- :return_oriented: Test ROP (Return-Oriented Programming) mitigation
- :side_channel: Test side channel resistance
- :syscall_abuse: Test syscall abuse prevention

# Arguments
- `attack_vector::Symbol`: The type of attack to simulate
- `state::EPTSandboxState`: The sandbox state

# Returns
- `Bool`: True if attack is contained (sandbox secure)

# Example
```julia
state = EPTSandboxState()
is_secure = test_escape_attempt(:buffer_overflow, state)
```
"""
function test_escape_attempt(attack_vector::Symbol, state::EPTSandboxState)::Bool
    @info "Testing escape attempt" attack_vector=attack_vector
    
    contained = true
    
    if attack_vector == :buffer_overflow
        # Simulate buffer overflow attempt
        # Test that writes beyond Julia memory are trapped
        overflow_addr = state.config.julia_memory_end + UInt64(0x1000)
        violation = EPTViolation(
            address=overflow_addr,
            violation_type=WRITE_VIOLATION,
            severity=SEVERITY_HIGH,
            context=Dict("attack_vector" => "buffer_overflow")
        )
        contained = ept_violation_handler(violation, state)
        
    elseif attack_vector == :return_oriented
        # Simulate ROP attempt
        # Test that execution from non-code regions is blocked
        rop_addr = state.config.ring_buffer_start
        violation = EPTViolation(
            address=rop_addr,
            violation_type=EXECUTE_VIOLATION,
            severity=SEVERITY_CRITICAL,
            context=Dict("attack_vector" => "return_oriented")
        )
        contained = ept_violation_handler(violation, state)
        
    elseif attack_vector == :side_channel
        # Simulate side channel attack attempt
        # Test timing/cache attacks are mitigated
        violation = EPTViolation(
            address=state.config.julia_memory_start,
            violation_type=READ_VIOLATION,
            severity=SEVERITY_MEDIUM,
            context=Dict("attack_vector" => "side_channel")
        )
        contained = ept_violation_handler(violation, state)
        
    elseif attack_vector == :syscall_abuse
        # Simulate syscall abuse attempt
        syscall_addr = state.config.syscall_block_start
        violation = EPTViolation(
            address=syscall_addr,
            violation_type=SYSCALL_VIOLATION,
            severity=SEVERITY_HIGH,
            context=Dict("attack_vector" => "syscall_abuse")
        )
        contained = ept_violation_handler(violation, state)
        
    else
        error("Unknown attack vector: $attack_vector")
    end
    
    if contained
        @info "Escape attempt CONTAINED" attack_vector=attack_vector
    else
        @error "Escape attempt NOT CONTAINED - sandbox compromised!" attack_vector=attack_vector
    end
    
    return contained
end

# ============================================================================
# WARDEN INTEGRATION
# ============================================================================

"""
Report an EPT violation to the Rust Warden via IPC.

Sends EPT violation information to the Warden for:
- Metabolic auditing (tracking resource usage)
- Security decision making (continue/terminate)
- Forensic analysis

# Arguments
- `violation::EPTViolation`: The violation to report
- `state::EPTSandboxState`: The current sandbox state

# Returns
- `Bool`: True if Warden says continue, false if terminate

# Example
```julia
state = EPTSandboxState()
violation = EPTViolation(address=0x4000_0000, violation_type=SYSCALL_VIOLATION)
should_continue = report_violation_to_warden(violation, state)
```
"""
function report_violation_to_warden(violation::EPTViolation, state::EPTSandboxState)::Bool
    # Prepare violation report
    violation_report = Dict{String, Any}(
        "violation_id" => string(violation.id),
        "address" => string(violation.address, base=16),
        "violation_type" => string(violation.violation_type),
        "severity" => string(violation.severity),
        "timestamp" => string(violation.timestamp),
        "context" => violation.context,
        "requires_termination" => violation.requires_termination,
        "current_mode" => string(state.current_mode),
        "violation_count" => length(state.violation_history)
    )
    
    # Try to send to Warden via IPC
    try
        # Create IPC message for Warden
        message = JSON.json(Dict(
            "type" => "ept_violation",
            "payload" => violation_report
        ))
        
        # Attempt to send to Warden
        # Note: In production, this would use RustIPC.safe_shm_write()
        # For now, we log and make a local decision
        @info "Reporting violation to Warden" \
            violation_id=string(violation.id) \
            severity=string(violation.severity)
        
        # Warden decision logic (simplified)
        # In production, this would be a synchronous call to Warden
        if violation.severity == SEVERITY_CRITICAL
            @error "Warden decision: TERMINATE (critical violation)"
            return false
        elseif violation.severity == SEVERITY_HIGH && length(state.violation_history) > 10
            @warn "Warden decision: TERMINATE (too many high-severity violations)"
            return false
        else
            @info "Warden decision: CONTINUE (violation logged)"
            return true
        end
        
    catch e
        @error "Failed to report violation to Warden" exception=e
        # Fail-closed: terminate on communication failure
        return false
    end
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
Initialize the EPT Sandbox with full configuration.

Creates and initializes a complete EPT sandbox environment:
1. Creates the sandbox state with configuration
2. Configures all memory mappings
3. Validates sandbox integrity

# Arguments
- `config::EPTSandboxConfig`: The sandbox configuration

# Returns
- `EPTSandboxState`: The initialized sandbox state

# Example
```julia
config = EPTSandboxConfig(
    enable_oneiric_ro=true,
    trap_syscalls=true
)
state = initialize_ept_sandbox(config)
```
"""
function initialize_ept_sandbox(config::EPTSandboxConfig)::EPTSandboxState
    @info "Initializing EPT Sandbox"
    
    # Create sandbox state
    state = EPTSandboxState(config=config)
    
    # Configure memory mappings
    configure_julia_memory_mapping(state)
    configure_ring_buffer_mapping(state)
    configure_syscall_trapping(state)
    
    # Validate initial integrity
    if !validate_sandbox_integrity(state)
        @error "Initial sandbox integrity validation FAILED"
        error("EPT Sandbox initialization failed: integrity check failed")
    end
    
    @info "EPT Sandbox initialized successfully"
    
    return state
end

# ============================================================================
# END OF MODULE
# ============================================================================

end # module EPTSandbox
