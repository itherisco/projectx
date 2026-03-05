using Dates

"""
    CircuitBreaker - Prevent cascading failures

Implements the circuit breaker pattern to protect against cascading failures
in external service calls. Based on the Resilience patterns from the 
"Orchestration and Control Plane" architecture.
"""
@enum CircuitState CLOSED OPEN HALF_OPEN

mutable struct CircuitBreaker
    name::String
    state::CircuitState
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int  # failures before opening
    timeout::Int    # seconds before half-open
    last_state_change::DateTime
    
    function CircuitBreaker(name::String; threshold::Int=5, timeout::Int=60)
        new(name, CLOSED, 0, 0, now(), threshold, timeout, now())
    end
end

"""
    CircuitBreakerOpenError - Error thrown when circuit is open
"""
struct CircuitBreakerOpenError <: Exception
    name::String
    message::String
    
    function CircuitBreakerOpenError(name::String)
        new(name, "Circuit breaker '$name' is OPEN")
    end
end

"""
    call(breaker::CircuitBreaker, func::Function, args...; kwargs...)
Execute function through circuit breaker
"""
function call(breaker::CircuitBreaker, func::Function, args...; kwargs...)
    # Check state
    if breaker.state == OPEN
        # Check if timeout elapsed
        elapsed = (now() - breaker.last_state_change).value / 1000
        if elapsed > breaker.timeout
            breaker.state = HALF_OPEN
            breaker.success_count = 0
            @info "Circuit breaker '$(breaker.name)' entering HALF_OPEN"
        else
            throw(CircuitBreakerOpenError(breaker.name))
        end
    end
    
    try
        result = func(args...; kwargs...)
        _on_success(breaker)
        return result
    catch e
        _on_failure(breaker)
        rethrow(e)
    end
end

"""
    _on_success - Handle successful call
"""
function _on_success(breaker::CircuitBreaker)
    breaker.failure_count = 0
    breaker.success_count += 1
    
    if breaker.state == HALF_OPEN && breaker.success_count >= 3
        breaker.state = CLOSED
        breaker.last_state_change = now()
        @info "Circuit breaker '$(breaker.name)' CLOSED after successful recovery"
    end
end

"""
    _on_failure - Handle failed call
"""
function _on_failure(breaker::CircuitBreaker)
    breaker.failure_count += 1
    breaker.success_count = 0
    breaker.last_failure_time = now()
    
    if breaker.failure_count >= breaker.threshold
        breaker.state = OPEN
        breaker.last_state_change = now()
        @warn "Circuit breaker '$(breaker.name)' OPENED after $(breaker.failure_count) failures"
    end
end

"""
    reset!(breaker::CircuitBreaker)
Manually reset a circuit breaker
"""
function reset!(breaker::CircuitBreaker)
    breaker.state = CLOSED
    breaker.failure_count = 0
    breaker.success_count = 0
    breaker.last_state_change = now()
    @info "Circuit breaker '$(breaker.name)' manually reset"
end

"""
    get_state(breaker::CircuitBreaker)::CircuitState
Get current state of circuit breaker
"""
function get_state(breaker::CircuitBreaker)::CircuitState
    return breaker.state
end

"""
    is_available(breaker::CircuitBreaker)::Bool
Check if circuit breaker allows calls
"""
function is_available(breaker::CircuitBreaker)::Bool
    if breaker.state == OPEN
        elapsed = (now() - breaker.last_state_change).value / 1000
        return elapsed > breaker.timeout
    end
    return true
end

# ============================================================================
# CircuitBreakerRegistry - Manage Multiple Circuit Breakers
# ============================================================================

"""
    CircuitBreakerRegistry - Central registry for managing circuit breakers
    across different services and components
"""
mutable struct CircuitBreakerRegistry
    breakers::Dict{String, CircuitBreaker}
    default_threshold::Int
    default_timeout::Int
    
    function CircuitBreakerRegistry(;threshold::Int=5, timeout::Int=60)
        new(Dict{String, CircuitBreaker}(), threshold, timeout)
    end
end

"""
    get_breaker(registry::CircuitBreakerRegistry, name::String; threshold::Int=0, timeout::Int=0)
Get or create a circuit breaker by name
"""
function get_breaker(registry::CircuitBreakerRegistry, name::String; threshold::Int=0, timeout::Int=0)
    if !haskey(registry.breakers, name)
        # Use provided values or fall back to defaults
        t = threshold > 0 ? threshold : registry.default_threshold
        to = timeout > 0 ? timeout : registry.default_timeout
        registry.breakers[name] = CircuitBreaker(name; threshold=t, timeout=to)
        @info "Created new circuit breaker: $name (threshold=$t, timeout=$to)"
    end
    return registry.breakers[name]
end

"""
    with_circuit(registry::CircuitBreakerRegistry, name::String, func::Function, args...; kwargs...)
Execute a function with circuit breaker protection
"""
function with_circuit(registry::CircuitBreakerRegistry, name::String, func::Function, args...; kwargs...)
    breaker = get_breaker(registry, name)
    return call(breaker, func, args...; kwargs...)
end

"""
    is_breaker_available(registry::CircuitBreakerRegistry, name::String)::Bool
Check if a specific circuit breaker allows calls
"""
function is_breaker_available(registry::CircuitBreakerRegistry, name::String)::Bool
    if !haskey(registry.breakers, name)
        return true  # Unknown breakers are assumed available
    end
    return is_available(registry.breakers[name])
end

"""
    get_breaker_state(registry::CircuitBreakerRegistry, name::String)::Union{CircuitState, Nothing}
Get the state of a specific circuit breaker
"""
function get_breaker_state(registry::CircuitBreakerRegistry, name::String)::Union{CircuitState, Nothing}
    if !haskey(registry.breakers, name)
        return nothing
    end
    return get_state(registry.breakers[name])
end

"""
    get_all_breaker_states(registry::CircuitBreakerRegistry)::Dict{String, Symbol}
Get states of all circuit breakers
"""
function get_all_breaker_states(registry::CircuitBreakerRegistry)::Dict{String, Symbol}
    states = Dict{String, Symbol}()
    for (name, breaker) in registry.breakers
        state = get_state(breaker)
        states[name] = state == CLOSED ? :closed : (state == OPEN ? :open : :half_open)
    end
    return states
end

"""
    reset_breaker!(registry::CircuitBreakerRegistry, name::String)
Reset a specific circuit breaker
"""
function reset_breaker!(registry::CircuitBreakerRegistry, name::String)
    if haskey(registry.breakers, name)
        reset!(registry.breakers[name])
    end
end

"""
    reset_all_breakers!(registry::CircuitBreakerRegistry)
Reset all circuit breakers in the registry
"""
function reset_all_breakers!(registry::CircuitBreakerRegistry)
    for (name, breaker) in registry.breakers
        reset!(breaker)
    end
end

# ============================================================================
# Pre-configured Circuit Breakers for Critical Services
# ============================================================================

"""
    create_standard_breakers(registry::CircuitBreakerRegistry)
Create circuit breakers for standard critical services
"""
function create_standard_breakers(registry::CircuitBreakerRegistry)
    # Itheris brain communication - critical for cognition
    get_breaker(registry, "itheris"; threshold=3, timeout=30)
    
    # External HTTP APIs - can fail independently
    get_breaker(registry, "http_api"; threshold=5, timeout=60)
    
    # LLM API calls - high latency, can timeout
    get_breaker(registry, "llm_api"; threshold=3, timeout=120)
    
    # Local service management
    get_breaker(registry, "service_manager"; threshold=5, timeout=30)
    
    # IPC communication
    get_breaker(registry, "ipc"; threshold=3, timeout=15)
    
    @info "Created standard circuit breakers for critical services"
end

# ============================================================================
# Export all public functions
# ============================================================================

export CircuitBreaker, CircuitState, CircuitBreakerRegistry, CircuitBreakerOpenError,
       call, reset!, get_state, is_available,
       get_breaker, with_circuit, is_breaker_available, get_breaker_state,
       get_all_breaker_states, reset_breaker!, reset_all_breakers!,
       create_standard_breakers,
       CLOSED, OPEN, HALF_OPEN
