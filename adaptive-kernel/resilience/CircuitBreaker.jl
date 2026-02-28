using Dates

"""
    CircuitBreaker - Prevent cascading failures
"""
@enum CircuitState CLOSED OPEN HALF_OPEN

mutable struct CircuitBreaker
    name::String
    state::CircuitState
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int  # failures before opening
    timeout::Int  # seconds before half-open
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
            @info "Circuit breaker '$breaker.name' entering HALF_OPEN"
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
        @info "Circuit breaker '$breaker.name' CLOSED after successful recovery"
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
        @warn "Circuit breaker '$breaker.name' OPENED after $breaker.failure_count failures"
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
    @info "Circuit breaker '$breaker.name' manually reset"
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
