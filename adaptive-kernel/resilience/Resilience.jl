# Resilience.jl - Resilience Module for Itheris/JARVIS
#
# This module provides resilience patterns including:
# - CircuitBreaker: Prevent cascading failures
# - HealthMonitor: Component health tracking
# - Integration wrappers for IPC, HTTP, and Services
#
# Note: This is a convenience module that includes all resilience components.
# For production use, individual modules can be used directly.

module Resilience

# Import dependencies
using Dates

# ============================================================================
# Health Monitor (standalone module)
# ============================================================================

include("HealthMonitor.jl")

# ============================================================================
# Circuit Breaker - Core Implementation
# ============================================================================

# Circuit Breaker State
@enum CircuitState CB_CLOSED CB_OPEN CB_HALF_OPEN

# CircuitBreaker type
mutable struct CircuitBreaker
    name::String
    state::CircuitState
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int
    timeout::Int
    last_state_change::DateTime
    
    function CircuitBreaker(name::String; threshold::Int=5, timeout::Int=60)
        new(name, CB_CLOSED, 0, 0, now(), threshold, timeout, now())
    end
end

# Error type
struct CircuitBreakerOpenError <: Exception
    name::String
    message::String
end
CircuitBreakerOpenError(name::String) = CircuitBreakerOpenError(name, "Circuit breaker '$name' is OPEN")

# Execute with circuit breaker
function call(cb::CircuitBreaker, func::Function, args...; kwargs...)
    if cb.state == CB_OPEN
        elapsed = (now() - cb.last_state_change).value / 1000
        if elapsed > cb.timeout
            cb.state = CB_HALF_OPEN
            cb.success_count = 0
        else
            throw(CircuitBreakerOpenError(cb.name))
        end
    end
    
    try
        result = func(args...; kwargs...)
        _on_success(cb)
        return result
    catch e
        _on_failure(cb)
        rethrow(e)
    end
end

function _on_success(cb::CircuitBreaker)
    cb.failure_count = 0
    cb.success_count += 1
    if cb.state == CB_HALF_OPEN && cb.success_count >= 3
        cb.state = CB_CLOSED
        cb.last_state_change = now()
    end
end

function _on_failure(cb::CircuitBreaker)
    cb.failure_count += 1
    cb.success_count = 0
    cb.last_failure_time = now()
    if cb.failure_count >= cb.threshold
        cb.state = CB_OPEN
        cb.last_state_change = now()
    end
end

function reset!(cb::CircuitBreaker)
    cb.state = CB_CLOSED
    cb.failure_count = 0
    cb.success_count = 0
    cb.last_state_change = now()
end

get_state(cb::CircuitBreaker) = cb.state
function is_available(cb::CircuitBreaker)
    if cb.state == CB_OPEN
        elapsed = (now() - cb.last_state_change).value / 1000
        if elapsed > cb.timeout
            cb.state = CB_HALF_OPEN
            cb.success_count = 0
            return true
        end
        return false
    end
    return true
end

# ============================================================================
# CircuitBreakerRegistry
# ============================================================================

mutable struct CircuitBreakerRegistry
    breakers::Dict{String, CircuitBreaker}
    default_threshold::Int
    default_timeout::Int
end
CircuitBreakerRegistry(;threshold::Int=5, timeout::Int=60) = 
    CircuitBreakerRegistry(Dict{String, CircuitBreaker}(), threshold, timeout)

function get_breaker(reg::CircuitBreakerRegistry, name::String; threshold::Int=0, timeout::Int=0)
    if !haskey(reg.breakers, name)
        t = threshold > 0 ? threshold : reg.default_threshold
        to = timeout > 0 ? timeout : reg.default_timeout
        reg.breakers[name] = CircuitBreaker(name; threshold=t, timeout=to)
    end
    return reg.breakers[name]
end

function with_circuit(reg::CircuitBreakerRegistry, name::String, func::Function, args...; kwargs...)
    cb = get_breaker(reg, name)
    return call(cb, func, args...; kwargs...)
end

function is_breaker_available(reg::CircuitBreakerRegistry, name::String)::Bool
    haskey(reg.breakers, name) ? is_available(reg.breakers[name]) : true
end

function get_breaker_state(reg::CircuitBreakerRegistry, name::String)
    haskey(reg.breakers, name) ? get_state(reg.breakers[name]) : nothing
end

function get_all_breaker_states(reg::CircuitBreakerRegistry)::Dict{String, Symbol}
    Dict(name => (get_state(cb) == CB_CLOSED ? :closed : (get_state(cb) == CB_OPEN ? :open : :half_open)) 
         for (name, cb) in reg.breakers)
end

function reset_breaker!(reg::CircuitBreakerRegistry, name::String)
    haskey(reg.breakers, name) && reset!(reg.breakers[name])
end

function create_standard_breakers(reg::CircuitBreakerRegistry)
    get_breaker(reg, "itheris"; threshold=3, timeout=30)
    get_breaker(reg, "http_api"; threshold=5, timeout=60)
    get_breaker(reg, "llm_api"; threshold=3, timeout=120)
    get_breaker(reg, "service_manager"; threshold=5, timeout=30)
    get_breaker(reg, "ipc"; threshold=3, timeout=15)
end

# ============================================================================
# Global Manager
# ============================================================================

mutable struct GlobalCircuitBreakerManager
    registry::CircuitBreakerRegistry
    
    function GlobalCircuitBreakerManager(;ipc_threshold::Int=3, ipc_timeout::Int=30,
                                          http_threshold::Int=5, http_timeout::Int=60,
                                          service_threshold::Int=5, service_timeout::Int=30)
        reg = CircuitBreakerRegistry(;threshold=http_threshold, timeout=http_timeout)
        create_standard_breakers(reg)
        new(reg)
    end
end

const _global_manager = Ref{Union{GlobalCircuitBreakerManager, Nothing}}(nothing)

function get_global_circuit_breaker_manager()::GlobalCircuitBreakerManager
    if _global_manager[] === nothing
        _global_manager[] = GlobalCircuitBreakerManager()
    end
    return _global_manager[]
end

function get_system_resilience_status(mgr::GlobalCircuitBreakerManager)::Dict{String, Any}
    Dict(
        "ipc" => Dict(
            "available" => is_breaker_available(mgr.registry, "itheris"),
            "status" => get_breaker_state(mgr.registry, "itheris")
        ),
        "http" => get_all_breaker_states(mgr.registry),
        "service" => Dict(
            "available" => is_breaker_available(mgr.registry, "service_manager"),
            "status" => get_breaker_state(mgr.registry, "service_manager")
        )
    )
end

# ============================================================================
# Initialization
# ============================================================================

function initialize_resilience(; config::Dict=Dict())::GlobalCircuitBreakerManager
    mgr = get_global_circuit_breaker_manager()
    return mgr
end

function get_resilience_summary()::Dict{String, Any}
    mgr = get_global_circuit_breaker_manager()
    return Dict(
        "circuit_breakers" => get_system_resilience_status(mgr),
        "message" => "Use get_global_circuit_breaker_manager() for detailed control"
    )
end

# ============================================================================
# Module-level exports
# ============================================================================

# CircuitBreaker exports
export CircuitBreaker, CircuitState, CircuitBreakerRegistry, CircuitBreakerOpenError,
       call, reset!, get_state, is_available,
       get_breaker, with_circuit, is_breaker_available, get_breaker_state,
       get_all_breaker_states, reset_breaker!,
       create_standard_breakers,
       CB_CLOSED, CB_OPEN, CB_HALF_OPEN

# HealthMonitor exports (re-export from HealthMonitor)
export HealthMonitor, ComponentHealth, HealthStatus,
       register_component!, record_success!, record_failure!,
       check_health, get_all_health, is_healthy, get_overall_status,
       HEALTHY, DEGRADED, UNHEALTHY, UNKNOWN

# Global manager exports
export GlobalCircuitBreakerManager,
       get_global_circuit_breaker_manager, get_system_resilience_status,
       initialize_resilience, get_resilience_summary

end  # module
