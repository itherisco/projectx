# CircuitBreakerIntegration.jl - Integration layer for Circuit Breaker
# 
# This module provides integration wrappers for circuit breakers into
# critical execution paths: RustIPC, HTTP requests, and ServiceManager.
#
# Based on the "Orchestration and Control Plane" architecture for 
# system resilience.

module CircuitBreakerIntegration

# Include the CircuitBreaker module
include("CircuitBreaker.jl")
using ..CircuitBreaker

# ============================================================================
# Integration with RustIPC
# ============================================================================

"""
    IPC Circuit Breaker Wrapper
    
    Provides circuit breaker protection for IPC operations to the Itheris brain.
    If the brain becomes unresponsive, the circuit breaker prevents cascading
    failures in the cognitive system.
"""
mutable struct IPCCircuitBreaker
    registry::CircuitBreakerRegistry
    ipc_breaker_name::String
    
    function IPCCircuitBreaker(;threshold::Int=3, timeout::Int=30)
        registry = CircuitBreakerRegistry(;threshold=threshold, timeout=timeout)
        # Create the IPC circuit breaker
        get_breaker(registry, "itheris"; threshold=threshold, timeout=timeout)
        new(registry, "itheris")
    end
end

"""
    with_ipc_protection(breaker::IPCCircuitBreaker, func::Function, args...; kwargs...)
    Execute IPC operation with circuit breaker protection
"""
function with_ipc_protection(breaker::IPCCircuitBreaker, func::Function, args...; kwargs...)
    try
        return with_circuit(breaker.registry, breaker.ipc_breaker_name, func, args...; kwargs...)
    catch e
        if isa(e, CircuitBreakerOpenError)
            @error "IPC Circuit breaker OPEN - brain communication blocked: $(e.message)"
        end
        rethrow()
    end
end

"""
    is_ipc_available(breaker::IPCCircuitBreaker)::Bool
Check if IPC communication is allowed
"""
function is_ipc_available(breaker::IPCCircuitBreaker)::Bool
    is_breaker_available(breaker.registry, breaker.ipc_breaker_name)
end

"""
    get_ipc_status(breaker::IPCCircuitBreaker)::Symbol
Get IPC circuit breaker status
"""
function get_ipc_status(breaker::IPCCircuitBreaker)::Symbol
    state = get_breaker_state(breaker.registry, breaker.ipc_breaker_name)
    state === nothing && return :unknown
    state == CLOSED && return :closed
    state == OPEN && return :open
    return :half_open
end

"""
    record_ipc_success(breaker::IPCCircuitBreaker)
Manually record a successful IPC operation
"""
function record_ipc_success(breaker::IPCCircuitBreaker)
    if haskey(breaker.registry.breakers, breaker.ipc_breaker_name)
        _on_success(breaker.registry.breakers[breaker.ipc_breaker_name])
    end
end

"""
    record_ipc_failure(breaker::IPCCircuitBreaker)
Manually record a failed IPC operation
"""
function record_ipc_failure(breaker::IPCCircuitBreaker)
    if haskey(breaker.registry.breakers, breaker.ipc_breaker_name)
        _on_failure(breaker.registry.breakers[breaker.ipc_breaker_name])
    end
end

# ============================================================================
# Integration with HTTP Requests  
# ============================================================================

"""
    HTTPCircuitBreaker
    
    Provides circuit breaker protection for external HTTP API calls.
    Protects against slow or failing external services.
"""
mutable struct HTTPCircuitBreaker
    registry::CircuitBreakerRegistry
    default_timeout::Int
    
    function HTTPCircuitBreaker(;threshold::Int=5, timeout::Int=60)
        registry = CircuitBreakerRegistry(;threshold=threshold, timeout=timeout)
        # Create circuit breakers for common services
        get_breaker(registry, "http_api"; threshold=threshold, timeout=timeout)
        get_breaker(registry, "llm_api"; threshold=3, timeout=120)
        new(registry, timeout)
    end
end

"""
    with_http_protection(breaker::HTTPCircuitBreaker, url::String, func::Function, args...; kwargs...)
    Execute HTTP operation with circuit breaker protection
"""
function with_http_protection(breaker::HTTPCircuitBreaker, url::String, func::Function, args...; kwargs...)
    # Determine which breaker to use based on URL patterns
    breaker_name = _select_http_breaker(url)
    
    try
        return with_circuit(breaker.registry, breaker_name, func, args...; kwargs...)
    catch e
        if isa(e, CircuitBreakerOpenError)
            @error "HTTP Circuit breaker OPEN for $breaker_name: $(e.message)"
        end
        rethrow()
    end
end

"""
    _select_http_breaker(url::String)::String
Select appropriate circuit breaker based on URL
"""
function _select_http_breaker(url::String)::String
    # Check for LLM API patterns
    if occursin("openai", lowercase(url)) || 
       occursin("anthropic", lowercase(url)) ||
       occursin("llm", lowercase(url)) ||
       occursin("api.openai", url) ||
       occursin("api.anthropic", url)
        return "llm_api"
    end
    # Default to general HTTP API breaker
    return "http_api"
end

"""
    is_http_available(breaker::HTTPCircuitBreaker, url::String)::Bool
Check if HTTP request to URL is allowed
"""
function is_http_available(breaker::HTTPCircuitBreaker, url::String)::Bool
    breaker_name = _select_http_breaker(url)
    is_breaker_available(breaker.registry, breaker_name)
end

"""
    get_http_status(breaker::HTTPCircuitBreaker)::Dict{String, Symbol}
Get status of all HTTP circuit breakers
"""
function get_http_status(breaker::HTTPCircuitBreaker)::Dict{String, Symbol}
    get_all_breaker_states(breaker.registry)
end

# ============================================================================
# Integration with ServiceManager
# ============================================================================

"""
    ServiceCircuitBreaker
    
    Provides circuit breaker protection for service management operations.
    Protects against cascading failures from service restarts.
"""
mutable struct ServiceCircuitBreaker
    registry::CircuitBreakerRegistry
    
    function ServiceCircuitBreaker(;threshold::Int=5, timeout::Int=30)
        registry = CircuitBreakerRegistry(;threshold=threshold, timeout=timeout)
        get_breaker(registry, "service_manager"; threshold=threshold, timeout=timeout)
        new(registry)
    end
end

"""
    with_service_protection(breaker::ServiceCircuitBreaker, service_name::String, func::Function, args...; kwargs...)
    Execute service operation with circuit breaker protection
"""
function with_service_protection(breaker::ServiceCircuitBreaker, service_name::String, func::Function, args...; kwargs...)
    try
        return with_circuit(breaker.registry, "service_manager", func, args...; kwargs...)
    catch e
        if isa(e, CircuitBreakerOpenError)
            @error "Service Circuit breaker OPEN - service operations blocked: $(e.message)"
        end
        rethrow()
    end
end

"""
    is_service_available(breaker::ServiceCircuitBreaker)::Bool
Check if service operations are allowed
"""
function is_service_available(breaker::ServiceCircuitBreaker)::Bool
    is_breaker_available(breaker.registry, "service_manager")
end

# ============================================================================
# Global Circuit Breaker Manager
# ============================================================================

"""
    GlobalCircuitBreakerManager
    
    Singleton manager for all circuit breakers in the system.
    Provides centralized access to circuit breaker state.
"""
mutable struct GlobalCircuitBreakerManager
    ipc::IPCCircuitBreaker
    http::HTTPCircuitBreaker
    service::ServiceCircuitBreaker
    
    function GlobalCircuitBreakerManager(;ipc_threshold::Int=3, ipc_timeout::Int=30,
                                          http_threshold::Int=5, http_timeout::Int=60,
                                          service_threshold::Int=5, service_timeout::Int=30)
        new(
            IPCCircuitBreaker(;threshold=ipc_threshold, timeout=ipc_timeout),
            HTTPCircuitBreaker(;threshold=http_threshold, timeout=http_timeout),
            ServiceCircuitBreaker(;threshold=service_threshold, timeout=service_timeout)
        )
    end
end

# Global instance - lazily initialized
const _global_manager = Ref{Union{GlobalCircuitBreakerManager, Nothing}}(nothing)

"""
    get_global_circuit_breaker_manager()::GlobalCircuitBreakerManager
Get or create the global circuit breaker manager
"""
function get_global_circuit_breaker_manager()::GlobalCircuitBreakerManager
    if _global_manager[] === nothing
        _global_manager[] = GlobalCircuitBreakerManager()
    end
    return _global_manager[]
end

"""
    get_system_resilience_status(manager::GlobalCircuitBreakerManager)::Dict{String, Any}
Get comprehensive resilience status across all circuit breakers
"""
function get_system_resilience_status(manager::GlobalCircuitBreakerManager)::Dict{String, Any}
    Dict(
        "ipc" => Dict(
            "available" => is_ipc_available(manager.ipc),
            "status" => get_ipc_status(manager.ipc)
        ),
        "http" => get_http_status(manager.http),
        "service" => Dict(
            "available" => is_service_available(manager.service),
            "status" => get_breaker_state(manager.service.registry, "service_manager")
        )
    )
end

# ============================================================================
# Export
# ============================================================================

export IPCCircuitBreaker, HTTPCircuitBreaker, ServiceCircuitBreaker,
       GlobalCircuitBreakerManager,
       with_ipc_protection, with_http_protection, with_service_protection,
       is_ipc_available, is_http_available, is_service_available,
       get_ipc_status, get_http_status,
       record_ipc_success, record_ipc_failure,
       get_global_circuit_breaker_manager, get_system_resilience_status

end  # module
