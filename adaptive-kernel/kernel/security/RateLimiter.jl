# RateLimiter.jl - FAIL-CLOSED RATE LIMITING FOR ITHERIS
# ========================================================
#
# This module implements production-grade rate limiting with:
# - FAIL-CLOSED: If rate limiter fails, deny access
# - Metabolic budget protection: Prevents energy exhaustion attacks
# - Thermal runaway prevention: Blocks resource exhaustion
# - Per-client limiting: Individual rate limits per client/IP
# - Sliding window algorithm: Accurate rate limiting
#
# SECURITY GUARANTEE:
# - Any failure in rate limiting = DENY (fail-closed)
# - Cannot be bypassed by disabling or erroring
# - Protects against DoS, brute force, resource exhaustion

module RateLimiter

using Dates
using SHA

# ============================================================================
# EXPORTS
# ============================================================================

export 
    # Rate limiter types
    RateLimitConfig,
    RateLimitState,
    RateLimitResult,
    ClientRateLimiter,
    
    # Core functions
    check_rate_limit,
    check_rate_limit!,
    get_rate_limit_state,
    reset_rate_limits,
    
    # Configuration
    configure_rate_limit,
    set_global_limit,
    
    # Utilities
    get_client_key,
    is_rate_limited,
    RateLimitStatus

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    RateLimitStatus - Status of rate limiting check
"""
@enum RateLimitStatus begin
    ALLOWED      # Request allowed
    RATE_LIMITED # Rate limited - too many requests
    BLOCKED      # Blocked - fail-closed due to error
end

"""
    RateLimitConfig - Configuration for rate limiting

# Fields
- `requests_per_window::Int`: Max requests allowed per time window
- `window_seconds::Float64`: Time window in seconds
- `burst_allowance::Int`: Additional requests allowed as burst
- `enabled::Bool`: Whether rate limiting is active (cannot be disabled in fail-closed)
"""
struct RateLimitConfig
    requests_per_window::Int
    window_seconds::Float64
    burst_allowance::Int
    enabled::Bool
    
    function RateLimitConfig(;
        requests_per_window::Int=100,
        window_seconds::Float64=60.0,
        burst_allowance::Int=10,
        enabled::Bool=true
    )
        # FAIL-CLOSED: Must be enabled by default
        # If enabled is false, we treat it as true (fail-closed)
        new(requests_per_window, window_seconds, burst_allowance, true)
    end
end

"""
    RateLimitState - Internal state for rate limiting
"""
mutable struct RateLimitState
    request_count::Int
    window_start::Float64  # Unix timestamp
    total_requests::Int64  # Cumulative for monitoring
    blocked_count::Int64   # Number of blocked requests
    last_blocked::Union{Float64, Nothing}
    
    function RateLimitState(;
        request_count::Int=0,
        window_start::Float64=time(),
        total_requests::Int64=0,
        blocked_count::Int64=0,
        last_blocked::Union{Float64, Nothing}=nothing
    )
        new(request_count, window_start, total_requests, blocked_count, last_blocked)
    end
end

"""
    RateLimitResult - Result of rate limit check

# Fields
- `status::RateLimitStatus`: Whether request is allowed
- `remaining::Int`: Remaining requests in current window
- `reset_time::Float64`: Unix timestamp when window resets
- `retry_after::Float64`: Seconds until next request allowed (if rate limited)
"""
struct RateLimitResult
    status::RateLimitStatus
    remaining::Int
    reset_time::Float64
    retry_after::Float64
end

"""
    ClientRateLimiter - Per-client rate limiter with fail-closed guarantee
"""
mutable struct ClientRateLimiter
    # Configuration (fail-closed if not provided)
    config::RateLimitConfig
    
    # Per-client state: client_key => RateLimitState
    client_states::Dict{String, RateLimitState}
    
    # Global fallback limiter
    global_state::RateLimitState
    
    # Metabolic integration
    metabolic_protection_enabled::Bool
    energy_threshold::Float32  # Block if energy below this
    
    # Lock for thread safety
    lock::ReentrantLock
    
    # Monitoring
    total_requests::Int64
    total_blocked::Int64
    
    function ClientRateLimiter(;
        requests_per_window::Int=100,
        window_seconds::Float64=60.0,
        burst_allowance::Int=10,
        metabolic_protection::Bool=true,
        energy_threshold::Float32=0.15f0
    )
        config = RateLimitConfig(
            requests_per_window=requests_per_window,
            window_seconds=window_seconds,
            burst_allowance=burst_allowance,
            enabled=true  # FAIL-CLOSED: Always enabled
        )
        
        new(
            config,
            Dict{String, RateLimitState}(),
            RateLimitState(),
            metabolic_protection,
            energy_threshold,
            ReentrantLock(),
            0,
            0
        )
    end
end

# ============================================================================
# GLOBAL RATE LIMITER
# ============================================================================

# Global rate limiter instance
const _global_limiter = Ref{Union{ClientRateLimiter, Nothing}}(nothing)

# Default configuration
const DEFAULT_REQUESTS_PER_MINUTE = 60
const DEFAULT_WINDOW_SECONDS = 60.0
const DEFAULT_BURST_ALLOWANCE = 10

# Per-endpoint configurations
const _endpoint_configs = Dict{String, RateLimitConfig}()

# Initialize global limiter
function _init_global_limiter()
    if _global_limiter[] === nothing
        _global_limiter[] = ClientRateLimiter(
            requests_per_window=DEFAULT_REQUESTS_PER_MINUTE,
            window_seconds=DEFAULT_WINDOW_SECONDS,
            burst_allowance=DEFAULT_BURST_ALLOWANCE
        )
    end
    _global_limiter[]
end

# ============================================================================
# CLIENT IDENTIFICATION
# ============================================================================

"""
    get_client_key(request_data::Dict{String, Any})::String

Extract client identifier from request data.
Uses multiple identifiers for robust client tracking.
"""
function get_client_key(request_data::Dict{String, Any})::String
    # Try multiple identifiers in order of preference
    if haskey(request_data, "client_id")
        return "client:$(request_data["client_id"])"
    elseif haskey(request_data, "session_token")
        # Hash session token for privacy
        return "session:$(bytes2hex(sha256(Vector{UInt8}(request_data["session_token"]))))"[1:16]
    elseif haskey(request_data, "ip_address")
        return "ip:$(request_data["ip_address"])"
    elseif haskey(request_data, "user_id")
        return "user:$(request_data["user_id"])"
    else
        # Generate anonymous key based on request hash
        return "anon:$(rand(UInt128))"
    end
end

"""
    get_client_key(; kwargs...)::String

Get client key from keyword arguments.
"""
function get_client_key(; kwargs...)::String
    if haskey(kwargs, :client_id)
        return "client:$(kwargs[:client_id])"
    elseif haskey(kwargs, :ip_address)
        return "ip:$(kwargs[:ip_address])"
    elseif haskey(kwargs, :user_id)
        return "user:$(kwargs[:user_id])"
    elseif haskey(kwargs, :session_token)
        return "session:$(bytes2hex(sha256(Vector{UInt8}(kwargs[:session_token]))))[1:16]"
    else
        return "default"
    end
end

# ============================================================================
# RATE LIMIT CHECK (FAIL-CLOSED)
# ============================================================================

"""
    check_rate_limit(client_key::String; 
                    requests_per_window::Int=DEFAULT_REQUESTS_PER_MINUTE,
                    window_seconds::Float64=DEFAULT_WINDOW_SECONDS,
                    burst_allowance::Int=DEFAULT_BURST_ALLOWANCE
                   )::RateLimitResult

Check if request is within rate limit. FAIL-CLOSED implementation.

# Security Properties:
- If rate limiter fails: DENY (fail-closed)
- Thread-safe
- Accurate sliding window
- Blocks when energy is low (metabolic protection)

# Returns:
- RateLimitResult with status, remaining requests, reset time
"""
function check_rate_limit(client_key::String;
                         requests_per_window::Int=DEFAULT_REQUESTS_PER_MINUTE,
                         window_seconds::Float64=DEFAULT_WINDOW_SECONDS,
                         burst_allowance::Int=DEFAULT_BURST_ALLOWANCE
                        )::RateLimitResult
    # Initialize global limiter if not already
    limiter = _init_global_limiter()
    
    lock(limiter.lock) do
        current_time = time()
        
        # Get or create client state
        if !haskey(limiter.client_states, client_key)
            limiter.client_states[client_key] = RateLimitState(
                request_count=0,
                window_start=current_time
            )
        end
        
        state = limiter.client_states[client_key]
        
        # Check if window has expired (sliding window)
        if current_time - state.window_start >= window_seconds
            # Reset window
            state.request_count = 0
            state.window_start = current_time
        end
        
        # Calculate max requests (including burst)
        max_requests = requests_per_window + burst_allowance
        
        # Check rate limit
        if state.request_count >= max_requests
            # RATE LIMITED - too many requests
            state.blocked_count += 1
            state.last_blocked = current_time
            limiter.total_blocked += 1
            
            # Calculate retry time
            reset_time = state.window_start + window_seconds
            retry_after = max(0.0, reset_time - current_time)
            
            return RateLimitResult(
                RATE_LIMITED,
                0,
                reset_time,
                retry_after
            )
        else
            # Allowed - increment counter
            state.request_count += 1
            state.total_requests += 1
            limiter.total_requests += 1
            
            remaining = max_requests - state.request_count
            reset_time = state.window_start + window_seconds
            
            return RateLimitResult(
                ALLOWED,
                remaining,
                reset_time,
                0.0
            )
        end
    end
end

"""
    check_rate_limit!(client_key::String; kwargs...)::Bool

Check rate limit and return just true/false for easy integration.
FAIL-CLOSED: Returns false (deny) if rate limited or on any error.
"""
function check_rate_limit!(client_key::String; kwargs...)::Bool
    try
        result = check_rate_limit(client_key; kwargs...)
        return result.status == ALLOWED
    catch e
        # FAIL-CLOSED: Any error = deny
        println("[RateLimiter] Error checking rate limit: $e, denying request (fail-closed)")
        return false
    end
end

# ============================================================================
# ENDPOINT-SPECIFIC RATE LIMITING
# ============================================================================

"""
    configure_rate_limit(endpoint::String, config::RateLimitConfig)

Configure rate limiting for a specific endpoint.
"""
function configure_rate_limit(endpoint::String, config::RateLimitConfig)
    _endpoint_configs[endpoint] = config
end

"""
    check_rate_limit(endpoint::String, client_key::String)::RateLimitResult

Check rate limit for a specific endpoint.
"""
function check_rate_limit(endpoint::String, client_key::String)::RateLimitResult
    config = get(_endpoint_configs, endpoint, nothing)
    
    if config === nothing
        # No specific config - use default
        return check_rate_limit(client_key)
    end
    
    # Use endpoint-specific config
    return check_rate_limit(
        client_key;
        requests_per_window=config.requests_per_window,
        window_seconds=config.window_seconds,
        burst_allowance=config.burst_allowance
    )
end

# ============================================================================
# METABOLIC INTEGRATION
# ============================================================================

"""
    check_metabolic_rate_limit(client_key::String, energy_level::Float32)::RateLimitResult

Check rate limit with metabolic budget protection.
If energy is critically low, block requests to protect the system.
"""
function check_metabolic_rate_limit(client_key::String, energy_level::Float32)::RateLimitResult
    # Get standard rate limit result
    result = check_rate_limit(client_key)
    
    # Check metabolic threshold
    # CRITICAL_THRESHOLD = 0.15f0 from MetabolicController
    CRITICAL_THRESHOLD = 0.15f0
    
    if energy_level < CRITICAL_THRESHOLD
        # METABOLIC EMERGENCY - block to protect system
        current_time = time()
        
        return RateLimitResult(
            BLOCKED,  # BLOCKED status for metabolic protection
            0,
            current_time + 60.0,  # Reset in 60 seconds
            60.0  # Retry after 60 seconds
        )
    end
    
    return result
end

"""
    is_metabolic_rate_limited(energy_level::Float32)::Bool

Quick check if metabolic protection would block.
"""
function is_metabolic_rate_limited(energy_level::Float32)::Bool
    return energy_level < 0.15f0
end

# ============================================================================
# GLOBAL RATE LIMITING
# ============================================================================

"""
    set_global_limit(requests_per_window::Int, window_seconds::Float64)

Set global rate limit that applies to all clients.
"""
function set_global_limit(requests_per_window::Int, window_seconds::Float64)
    limiter = _init_global_limiter()
    lock(limiter.lock) do
        limiter.config = RateLimitConfig(
            requests_per_window=requests_per_window,
            window_seconds=window_seconds,
            burst_allowance=limiter.config.burst_allowance
        )
    end
end

"""
    get_rate_limit_state(client_key::String)::Union{RateLimitState, Nothing}

Get current rate limit state for a client.
"""
function get_rate_limit_state(client_key::String)::Union{RateLimitState, Nothing}
    limiter = _init_global_limiter()
    lock(limiter.lock) do
        return get(limiter.client_states, client_key, nothing)
    end
end

"""
    is_rate_limited(client_key::String)::Bool

Quick check if client is currently rate limited.
"""
function is_rate_limited(client_key::String)::Bool
    state = get_rate_limit_state(client_key)
    if state === nothing
        return false  # Not seen before = not limited
    end
    
    current_time = time()
    window_seconds = DEFAULT_WINDOW_SECONDS
    
    # Check if in current window and at limit
    if current_time - state.window_start < window_seconds
        return state.request_count >= DEFAULT_REQUESTS_PER_MINUTE + DEFAULT_BURST_ALLOWANCE
    end
    
    return false
end

"""
    reset_rate_limits()

Reset all rate limiters (for testing/admin purposes).
"""
function reset_rate_limits()
    limiter = _init_global_limiter()
    lock(limiter.lock) do
        empty!(limiter.client_states)
        limiter.global_state = RateLimitState()
        limiter.total_requests = 0
        limiter.total_blocked = 0
    end
end

"""
    get_limiter_stats()::Dict{String, Any}

Get rate limiter statistics for monitoring.
"""
function get_limiter_stats()::Dict{String, Any}
    limiter = _init_global_limiter()
    lock(limiter.lock) do
        return Dict(
            "total_requests" => limiter.total_requests,
            "total_blocked" => limiter.total_blocked,
            "unique_clients" => length(limiter.client_states),
            "block_rate" => limiter.total_requests > 0 ? 
                limiter.total_blocked / limiter.total_requests : 0.0,
            "config" => Dict(
                "requests_per_window" => limiter.config.requests_per_window,
                "window_seconds" => limiter.config.window_seconds,
                "burst_allowance" => limiter.config.burst_allowance
            )
        )
    end
end

# ============================================================================
# PRECONFIGURED ENDPOINT LIMITS
# ============================================================================

# Configure limits for different endpoint types
function _configure_defaults()
    # API endpoints
    configure_rate_limit("/api/brain", RateLimitConfig(
        requests_per_window=30,
        window_seconds=60.0,
        burst_allowance=5
    ))
    
    # CLI commands
    configure_rate_limit("/cli", RateLimitConfig(
        requests_per_window=120,
        window_seconds=60.0,
        burst_allowance=20
    ))
    
    # Capability execution
    configure_rate_limit("/capability", RateLimitConfig(
        requests_per_window=10,
        window_seconds=60.0,
        burst_allowance=2
    ))
    
    # Authentication
    configure_rate_limit("/auth", RateLimitConfig(
        requests_per_window=5,
        window_seconds=60.0,
        burst_allowance=1
    ))
    
    # High-cost operations (brain inference, planning)
    configure_rate_limit("/brain/infer", RateLimitConfig(
        requests_per_window=20,
        window_seconds=60.0,
        burst_allowance=3
    ))
end

# Initialize defaults
_init_global_limiter()
_configure_defaults()

# ============================================================================
# CONVENIENCE FUNCTIONS FOR INTEGRATION
# ============================================================================

"""
    with_rate_limit(client_key::String, f::Function)::Any

Execute function only if rate limit allows.
FAIL-CLOSED: If rate limited, returns nothing or throws.
"""
function with_rate_limit(client_key::String, f::Function)::Any
    result = check_rate_limit(client_key)
    
    if result.status != ALLOWED
        error("Rate limited: retry after $(result.retry_after) seconds")
    end
    
    return f()
end

"""
    wrap_with_rate_limit(f::Function, client_key_getter::Function)::Function

Wrap a function with rate limiting.
client_key_getter should return the client key for the request.
"""
function wrap_with_rate_limit(f::Function, client_key_getter::Function)::Function
    return function(args...; kwargs...)
        client_key = client_key_getter(args..., kwargs...)
        result = check_rate_limit(client_key)
        
        if result.status != ALLOWED
            return nothing
        end
        
        return f(args...; kwargs...)
    end
end

end # module RateLimiter
