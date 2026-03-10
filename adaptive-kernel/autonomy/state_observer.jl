"""
# State Observer Module

Collects system signals including uptime, CPU load, memory usage, active tasks,
kernel statistics, recent failures, and tool usage metrics.

Returns structured state Dict with:
- uptime: Int (seconds since system start)
- cpu_load: Float (1-minute load average)
- memory_usage: Float (percentage 0-100)
- kernel_stats: Dict with approval counts, active threads, etc.
- recent_events: Array of recent system events
"""

module StateObserver

using Dates
using UUIDs

# System state structure
struct SystemState
    uptime::Int
    cpu_load::Float64
    memory_usage::Float64
    kernel_stats::Dict{String, Any}
    recent_events::Vector{Dict{String, Any}}
    timestamp::DateTime
end

# Global state tracking
mutable struct ObserverState
    start_time::DateTime
    event_buffer::Vector{Dict{String, Any}}
    max_buffer_size::Int
    
    ObserverState() = new(now(), Dict{String, Any}[], 100)
end

const _observer_state = ObserverState()

"""
Collect all system signals and return a structured state Dict.
"""
function observe()::Dict{String, Any}
    # Calculate uptime
    uptime_seconds = round(Int, (now() - _observer_state.start_time).value / 1000)
    
    # Get CPU load (1-minute average)
    cpu_load = Sys.loadavg()[1]
    
    # Get memory usage
    total_mem = Sys.total_memory()
    free_mem = Sys.free_memory()
    used_mem = total_mem - free_mem
    memory_percent = (used_mem / total_mem) * 100.0
    
    # Get kernel statistics (from internal state)
    kernel_stats = Dict(
        "approved_actions" => _get_approved_count(),
        "rejected_actions" => _get_rejected_count(),
        "active_threads" => Threads.nthreads(),
        "process_id" => getpid()
    )
    
    # Get recent events
    recent_events = copy(_observer_state.event_buffer)
    
    return Dict(
        "uptime" => uptime_seconds,
        "cpu_load" => round(cpu_load, digits=2),
        "memory_usage" => round(memory_percent, digits=2),
        "kernel_stats" => kernel_stats,
        "recent_events" => recent_events,
        "timestamp" => now()
    )
end

"""
Record an event in the observer's event buffer.
"""
function record_event(event::Dict{String, Any})
    push!(_observer_state.event_buffer, merge(event, Dict("timestamp" => now())))
    
    # Trim buffer if needed
    if length(_observer_state.event_buffer) > _observer_state.max_buffer_size
        popfirst!(_observer_state.event_buffer)
    end
end

"""
Get recent events of a specific type.
"""
function get_recent_events(event_type::String, limit::Int=10)::Vector{Dict{String, Any}}
    filter!(e -> get(e, "type", "") == event_type, _observer_state.event_buffer)
    return _observer_state.event_buffer[max(1, end-limit+1):end]
end

"""
Check if system health is within acceptable parameters.
"""
function is_healthy(state::Dict{String, Any})::Bool
    # CPU should be below 90%
    if state["cpu_load"] > 90.0
        return false
    end
    
    # Memory should be below 95%
    if state["memory_usage"] > 95.0
        return false
    end
    
    return true
end

# Internal helpers (placeholder implementations)
function _get_approved_count()::Int
    # This would integrate with actual kernel state
    return get(_observer_state, :approved_count, 0)
end

function _get_rejected_count()::Int
    return get(_observer_state, :rejected_count, 0)
end

"""
Initialize the state observer.
"""
function init()
    _observer_state.start_time = now()
    _observer_state.event_buffer = Dict{String, Any}[]
    println("[StateObserver] Initialized at $(now())")
end

end # module
