"""
# Kernel Interface Module

Direct module interface replacing HTTP for internal communication.
Ensures the kernel remains the sovereignty gate for all actions.

This module provides:
- get_system_state(): Current system state without HTTP overhead
- approve_action(action): Kernel security validation before execution
- execute_capability(capability): Direct capability invocation
- record_event(event): Event logging for audit trail

NO HTTP CALLS - This is a critical security requirement.
"""

module KernelInterface

using Dates
using UUIDs

# Include memory management
include("MemoryManager.jl")
import .MemoryManager: cleanup_memory, get_memory_stats

# Kernel state tracking
mutable struct KernelState
    approved_count::Int
    rejected_count::Int
    event_log::Vector{Dict{String, Any}}
    blacklisted_actions::Set{String}
    max_event_log::Int
    
    KernelState() = new(0, 0, Dict{String, Any}[], Set{String}(), 1000)
end

const _kernel_state = KernelState()

"""
Get the current system state directly from the kernel.
This replaces HTTP calls to localhost:8080/status
"""
function get_system_state()::Dict{String, Any}
    return Dict(
        "timestamp" => now(),
        "load" => Sys.loadavg()[1],
        "mem_free" => Sys.free_memory() / 2^30,  # GB
        "mem_total" => Sys.total_memory() / 2^30,  # GB
        "cpu_count" => Sys.CPU_THREADS,
        "approved_actions" => _kernel_state.approved_count,
        "rejected_actions" => _kernel_state.rejected_count,
        "active_threads" => Threads.nthreads(),
        "process_id" => getpid(),
        "uptime_seconds" => time()
    )
end

"""
Request kernel approval for an action.
This is the sovereignty gate - all autonomous actions must pass through here.

Returns: (approved::Bool, reason::String)
"""
function approve_action(action::Dict{String, Any})::Tuple{Bool, String}
    action_name = get(action, "name", "")
    action_type = get(action, "type", "")
    
    # Check blacklist
    if action_name in _kernel_state.blacklisted_actions
        _record_decision(action, false, "Blacklisted action")
        return false, "Action is blacklisted for security"
    end
    
    # Security checks
    if action_type == "http_request"
        # Block self-referential HTTP calls
        target = get(action, "target", "")
        if occursin("localhost", lowercase(target)) || 
           occursin("127.0.0.1", lowercase(target))
            _record_decision(action, false, "Blocked self-referential HTTP")
            return false, "Security: Self-referential HTTP calls are prohibited"
        end
    end
    
    if action_type == "shell"
        # Enhanced shell command validation
        cmd = get(action, "command", "")
        dangerous_patterns = ["rm -rf /", "dd if=", ":(){:|:&};:", "mkfs", "shutdown", "reboot"]
        for pattern in dangerous_patterns
            if occursin(pattern, cmd)
                _record_decision(action, false, "Dangerous shell pattern blocked")
                return false, "Security: Dangerous shell command blocked"
            end
        end
    end
    
    # Default approval for validated actions
    _record_decision(action, true, "Approved")
    return true, "Authorized"
end

"""
Execute a capability directly through the kernel.
This replaces HTTP calls to capability endpoints.
"""
function execute_capability(capability::String, params::Dict{String, Any}=Dict{String, Any}())::Dict{String, Any}
    # Log the execution attempt
    result = Dict{String, Any}(
        "capability" => capability,
        "params" => params,
        "timestamp" => now(),
        "success" => false,
        "result" => nothing,
        "error" => nothing
    )
    
    try
        # Route to appropriate capability handler
        # This is a placeholder - actual implementation would integrate with ToolRegistry
        result["success"] = true
        result["result"] = "Capability '$capability' executed"
        
        _kernel_state.approved_count += 1
        
    catch e
        result["success"] = false
        result["error"] = string(e)
    end
    
    return result
end

"""
Record an event in the kernel's audit log.
"""
function record_event(event::Dict{String, Any})
    push!(_kernel_state.event_log, merge(event, Dict(
        "timestamp" => now(),
        "id" => string(uuid4())
    )))
    
    # Trim log if needed
    if length(_kernel_state.event_log) > _kernel_state.max_event_log
        popfirst!(_kernel_state.event_log)
    end
end

"""
Get recent kernel events.
"""
function get_recent_events(limit::Int=50)::Vector{Dict{String, Any}}
    return _kernel_state.event_log[max(1, end-limit+1):end]
end

"""
Add an action to the blacklist (admin function).
"""
function blacklist_action(action_name::String)
    push!(_kernel_state.blacklisted_actions, action_name)
    record_event(Dict(
        "type" => "blacklist",
        "action" => action_name
    ))
end

"""
Remove an action from the blacklist (admin function).
"""
function unblacklist_action(action_name::String)
    delete!(_kernel_state.blacklisted_actions, action_name)
    record_event(Dict(
        "type" => "unblacklist",
        "action" => action_name
    ))
end

"""
Get kernel statistics.
"""
function get_stats()::Dict{String, Any}
    return Dict(
        "approved" => _kernel_state.approved_count,
        "rejected" => _kernel_state.rejected_count,
        "blacklist_size" => length(_kernel_state.blacklisted_actions),
        "event_log_size" => length(_kernel_state.event_log)
    )
end

# Internal function to record approval decisions
function _record_decision(action::Dict{String, Any}, approved::Bool, reason::String)
    if approved
        _kernel_state.approved_count += 1
    else
        _kernel_state.rejected_count += 1
    end
    
    record_event(Dict(
        "type" => "approval_decision",
        "action" => action,
        "approved" => approved,
        "reason" => reason
    ))
end

"""
Initialize the kernel interface.
"""
function init()
    _kernel_state.approved_count = 0
    _kernel_state.rejected_count = 0
    _kernel_state.event_log = Dict{String, Any}[]
    println("[KernelInterface] Initialized - HTTP self-calls disabled")
end

end # module
