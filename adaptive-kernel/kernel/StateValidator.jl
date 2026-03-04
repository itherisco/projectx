# kernel/StateValidator.jl - Validates kernel state integrity
# Part of Phase 1: Kernel Sovereignty Enforcement

"""
    StateValidator - Validates kernel state integrity
    
Provides fail-closed validation of kernel state to ensure
the kernel has proper authority over execution.
"""
struct KernelStateValidator
    validation_interval::Float64
    last_validation::DateTime
    
    function KernelStateValidator(interval::Float64=1.0)
        new(interval, now())
    end
end

"""
    validate_kernel_state(state::KernelState)::Bool

Ensures kernel state is valid for operation.
Returns false if:
- state is nothing
- state.self_metrics is nothing  
- state.world is nothing

This is a fail-closed validation - assume invalid until proven valid.
"""
function validate_kernel_state(state)::Bool
    state === nothing && return false
    # Check if self_metrics exists and is valid (Julia struct field access)
    # KernelState.self_metrics is Dict{String, Float32} - check for valid entries
    if !isdefined(state, :self_metrics) || !isa(state.self_metrics, Dict) || isempty(state.self_metrics)
        return false
    end
    # Check if world exists and is valid
    if !isdefined(state, :world) || state.world === nothing
        return false
    end
    return true
end

"""
    ensure_kernel_ready(state::Union{KernelState, Nothing})::KernelState

Auto-initializes kernel if in invalid state (fail-closed).
If state is nothing, returns nothing to signal need for reinitialization.
The caller should handle initialization.

Returns the valid kernel state or nothing if invalid.
"""
function ensure_kernel_ready(state::Union{KernelState, Nothing})::Union{KernelState, Nothing}
    if state === nothing
        @error "Kernel state is nothing - initializing with defaults"
        return nothing  # Caller should handle initialization
    end
    
    # Validate the state
    if !validate_kernel_state(state)
        @error "Kernel state is invalid - needs reinitialization"
        return nothing
    end
    
    return state
end

"""
    check_kernel_approval(state::KernelState, approved_decision::Any)::Bool

Checks if the kernel's last decision matches the expected approval state.
This enforces kernel sovereignty over action execution.
"""
function check_kernel_approval(state::KernelState, approved_decision::Decision)::Bool
    state === nothing && return false
    # Julia struct field access - check if last_decision field is defined
    !isdefined(state, :last_decision) && return false
    return state.last_decision == approved_decision
end

"""
    is_kernel_ready_for_execution(state::KernelState, APPROVED::Any)::Bool

Comprehensive check if kernel is ready to approve and oversee action execution.
Returns true only if:
- State is valid (not nothing)
- Self metrics are valid
- World state is valid
- Last decision is APPROVED
"""
function is_kernel_ready_for_execution(state::KernelState, APPROVED::Decision)::Bool
    !validate_kernel_state(state) && return false
    !check_kernel_approval(state, APPROVED) && return false
    return true
end

# Export validation functions
export KernelStateValidator, validate_kernel_state, ensure_kernel_ready, 
       check_kernel_approval, is_kernel_ready_for_execution
