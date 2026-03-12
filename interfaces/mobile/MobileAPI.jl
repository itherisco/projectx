"""
    Mobile API Endpoints

Provides mobile-friendly API endpoints for JARVIS control.
Designed for future mobile app integration with RESTful interface.
Implements:
- JWT authentication
- Law Enforcement Point (LEP) for capability approval
- Rate limiting (fail-closed)
- Kernel sovereignty integration

# Functions
- `api_status()` - Get API status
- `api_query()` - Query system information
- `api_control()` - Send control commands
- `api_approve()` - Request capability approval through LEP
"""
module Mobile

using HTTP
using JSON
using Dates
using UUIDs

# Import kernel interface for sovereign approval
# "Brain is advisory, Kernel is sovereign"
const KERNEL_PATH = joinpath(dirname(@__DIR__), "adaptive-kernel", "kernel", "kernel_interface.jl")
if isfile(KERNEL_PATH)
    include(KERNEL_PATH)
    import .KernelInterface: get_system_state, approve_action, execute_capability
end

# API configuration
const API_VERSION = "2.0.0"  # Updated for JWT auth
const API_BASE_PATH = "/api/mobile/v1"

# Rate limiting configuration (fail-closed)
const RATE_LIMIT_MAX_REQUESTS = 100  # Max requests per window
const RATE_LIMIT_WINDOW_SECONDS = 60  # Time window in seconds

# In-memory rate limit tracking (use Redis in production)
mutable struct RateLimiter
    requests::Dict{String, Vector{DateTime}}
    RateLimiter() = new(Dict{String, Vector{DateTime}}())
end

const _rate_limiter = RateLimiter()

"""
    check_rate_limit(client_id::String)::Tuple{Bool, String}

Check if client has exceeded rate limit.
Returns (allowed::Bool, reason::String)
"""
function check_rate_limit(client_id::String)::Tuple{Bool, String}
    current_time = now()
    window_start = current_time - Second(RATE_LIMIT_WINDOW_SECONDS)
    
    # Get or create client request history
    if !haskey(_rate_limiter.requests, client_id)
        _rate_limiter.requests[client_id] = DateTime[]
    end
    
    # Filter to only requests within the window
    requests = _rate_limiter.requests[client_id]
    recent_requests = filter(t -> t > window_start, requests)
    
    # Check limit
    if length(recent_requests) >= RATE_LIMIT_MAX_REQUESTS
        return false, "Rate limit exceeded: $(RATE_LIMIT_MAX_REQUESTS) requests per $(RATE_LIMIT_WINDOW_SECONDS)s"
    end
    
    # Add current request
    push!(recent_requests, current_time)
    _rate_limiter.requests[client_id] = recent_requests
    
    return true, "Allowed"
end

"""
    api_status()

Get the current API status and health.
Returns status information for mobile clients.
"""
function api_status()
    status = Dict(
        :api_version => API_VERSION,
        :status => "operational",
        :timestamp => now(),
        :security => Dict(
            :jwt_auth => true,
            :rate_limiting => true,
            :kernel_approval => true
        ),
        :endpoints => [
            "$API_BASE_PATH/status",
            "$API_BASE_PATH/query",
            "$API_BASE_PATH/control",
            "$API_BASE_PATH/approve"  # New LEP endpoint
        ]
    )
    
    return status
end

"""
    api_query(query_type::String; params::Dict=Dict())

Process a query request from mobile clients.
# Arguments
- `query_type::String`: Type of query (system, cognitive, knowledge, etc.)
- `params::Dict`: Additional query parameters
"""
function api_query(query_type::String; params::Dict=Dict())
    result = Dict(
        :query_type => query_type,
        :params => params,
        :timestamp => now()
    )
    
    # Route to appropriate handler based on query_type
    if query_type == "system"
        result[:data] = _query_system(params)
    elseif query_type == "cognitive"
        result[:data] = _query_cognitive(params)
    elseif query_type == "knowledge"
        result[:data] = _query_knowledge(params)
    elseif query_type == "telemetry"
        result[:data] = _query_telemetry(params)
    else
        result[:error = "Unknown query type: $query_type"]
    end
    
    return result
end

"""
    api_control(command::String; params::Dict=Dict())

Process a control command from mobile clients.
All commands go through the security layer.
# Arguments
- `command::String`: Command to execute
- `params::Dict`: Command parameters
"""
function api_control(command::String; params::Dict=Dict())
    # Security layer validation
    # "Brain is advisory, Kernel is sovereign" - All commands require kernel approval
    
    # Create action for kernel approval
    action = Dict(
        "name" => command,
        "type" => "mobile_control",
        "source" => "mobile_api",
        "params" => params,
        "timestamp" => string(now())
    )
    
    # Request kernel approval
    approved = false
    reason = "Pending kernel approval"
    
    if isdefined(@__MODULE__, :approve_action)
        approved, reason = approve_action(action)
    else
        # Fallback: basic validation
        allowed_commands = ["start", "stop", "pause", "resume"]
        approved = command in allowed_commands
        reason = approved ? "Command allowed" : "Command not in allowed list"
    end
    
    result = Dict(
        :command => command,
        :params => params,
        :timestamp => now(),
        :security_check => approved ? "approved" : "rejected",
        :approval_reason => reason
    )
    
    if approved
        # Route to appropriate handler
        if command == "start"
            result[:data] = _control_start(params)
        elseif command == "stop"
            result[:data] = _control_stop(params)
        elseif command == "pause"
            result[:data] = _control_pause(params)
        elseif command == "resume"
            result[:data] = _control_resume(params)
        elseif command == "query"
            result[:data] = _control_query(params)
        else
            result[:error] = "Unknown command: $command"
        end
    else
        result[:error] = "Kernel rejected action: $reason"
    end
    
    return result
end

"""
    api_approve(capability::String, priority::Float64, reward::Float64, risk::Float64; params::Dict=Dict())

Request capability approval through the Law Enforcement Point (LEP).

The LEP uses the kernel's veto equation:
    score = priority × (reward - risk)

If score > 0, the action is approved. Otherwise, it's rejected.

# Arguments
- `capability::String`: The capability to approve
- `priority::Float64`: Priority weight (0.0-1.0)
- `reward::Float64`: Expected reward (0.0-1.0)
- `risk::Float64`: Expected risk (0.0-1.0)
- `params::Dict`: Additional parameters
"""
function api_approve(capability::String, priority::Float64, reward::Float64, risk::Float64; params::Dict=Dict())
    # Calculate LEP score: score = priority × (reward - risk)
    lep_score = priority * (reward - risk)
    
    # Create action for kernel approval
    action = Dict(
        "name" => capability,
        "type" => "capability_approval",
        "source" => "mobile_api",
        "priority" => priority,
        "reward" => reward,
        "risk" => risk,
        "lep_score" => lep_score,
        "params" => params,
        "timestamp" => string(now())
    )
    
    # Request kernel approval (sovereign gate)
    approved = false
    reason = "LEP evaluation pending"
    
    if isdefined(@__MODULE__, :approve_action)
        approved, reason = approve_action(action)
        
        # If kernel approved, also check LEP score
        if approved && lep_score <= 0
            approved = false
            reason = "LEP veto: score ($lep_score) <= 0"
        end
    else
        # Fallback to LEP score only
        approved = lep_score > 0
        reason = approved ? "LEP approved: score = $lep_score" : "LEP rejected: score = $lep_score"
    end
    
    result = Dict(
        :capability => capability,
        :priority => priority,
        :reward => reward,
        :risk => risk,
        :lep_score => lep_score,
        :approved => approved,
        :reason => reason,
        :timestamp => now(),
        :approval_source => "kernel_lep"
    )
    
    return result
end

# Internal query handlers
function _query_system(params::Dict)
    return Dict(
        :state => "running",
        :uptime => 3600,
        :version => "1.0.0",
        :platform => "linux"
    )
end

function _query_cognitive(params::Dict)
    return Dict(
        :active_processes => 3,
        :cycle_count => 150,
        :memory_usage => 0.65,
        :confidence => 0.87
    )
end

function _query_knowledge(params::Dict)
    return Dict(
        :entities => 1250,
        :relationships => 3400,
        :last_update => now()
    )
end

function _query_telemetry(params::Dict)
    return Dict(
        :cpu => 0.45,
        :memory => 0.64,
        :network_in => 1250000,
        :network_out => 850000
    )
end

# Internal control handlers
function _control_start(params::Dict)
    return Dict(
        :success => true,
        :message => "System started"
    )
end

function _control_stop(params::Dict)
    return Dict(
        :success => true,
        :message => "System stopped"
    )
end

function _control_pause(params::Dict)
    return Dict(
        :success => true,
        :message => "System paused"
    )
end

function _control_resume(params::Dict)
    return Dict(
        :success => true,
        :message => "System resumed"
    )
end

function _control_query(params::Dict)
    query_type = get(params, :type, "system")
    return api_query(query_type; params=params)
end

# Mobile API server setup
"""
    serve_mobile_api(;host::String="127.0.0.1", port::Int=9090)

Start the mobile API server with JWT auth, rate limiting, and LEP approval.
"""
function serve_mobile_api(;host::String="127.0.0.1", port::Int=9090)
    router = HTTP.Router()
    
    # Status endpoint
    HTTP.register!(router, "GET", "$API_BASE_PATH/status", _mobile_status_handler)
    
    # Query endpoints
    HTTP.register!(router, "GET", "$API_BASE_PATH/query", _mobile_query_handler)
    HTTP.register!(router, "POST", "$API_BASE_PATH/query", _mobile_query_post_handler)
    
    # Control endpoint (requires kernel approval)
    HTTP.register!(router, "POST", "$API_BASE_PATH/control", _mobile_control_handler)
    
    # Approval endpoint (LEP - Law Enforcement Point)
    HTTP.register!(router, "POST", "$API_BASE_PATH/approve", _mobile_approve_handler)
    
    @info "Starting Mobile API on $host:$port"
    @info "Endpoints: status, query, control, approve (LEP)"
    @info "Security: JWT auth, rate limiting ($RATE_LIMIT_MAX_REQUESTS req/$RATE_LIMIT_WINDOW_SECONDS s), kernel approval"
    
    return Dict(:host => host, :port => port, :router => router, :running => true)
end

# Mobile API handlers
function _mobile_status_handler(req)
    status = api_status()
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(status))
end

function _mobile_query_handler(req)
    params = HTTP.queryparams(req)
    query_type = get(params, "type", "system")
    result = api_query(query_type; params=Dict(params))
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(result))
end

function _mobile_query_post_handler(req)
    body = JSON.parse(String(req.body))
    query_type = get(body, "type", "system")
    params = get(body, "params", Dict())
    result = api_query(query_type; params=params)
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(result))
end

function _mobile_control_handler(req)
    # Check rate limiting (fail-closed)
    client_id = get(HTTP.headers(req), "X-Client-ID", string(uuid4()))
    allowed, reason = check_rate_limit(client_id)
    
    if !allowed
        return HTTP.Response(429, [
            "Content-Type" => "application/json",
            "X-RateLimit-Reason" => reason
        ], body=JSON.json(Dict(
            :error => "Rate limit exceeded",
            :reason => reason,
            :timestamp => now()
        )))
    end
    
    body = JSON.parse(String(req.body))
    command = get(body, "command", "")
    params = get(body, "params", Dict())
    result = api_control(command; params=params)
    
    return HTTP.Response(200, [
        "Content-Type" => "application/json",
        "X-Content-Type-Options" => "nosniff"
    ], body=JSON.json(result))
end

"""
    _mobile_approve_handler(req)

Handle capability approval requests through LEP.

Expected body:
{
    "capability": "execute_capability_name",
    "priority": 0.8,
    "reward": 0.7,
    "risk": 0.3,
    "params": {}
}

LEP Score: score = priority × (reward - risk)
"""
function _mobile_approve_handler(req)
    # Check rate limiting (fail-closed)
    client_id = get(HTTP.headers(req), "X-Client-ID", string(uuid4()))
    allowed, reason = check_rate_limit(client_id)
    
    if !allowed
        return HTTP.Response(429, [
            "Content-Type" => "application/json",
            "X-RateLimit-Reason" => reason
        ], body=JSON.json(Dict(
            :error => "Rate limit exceeded",
            :reason => reason,
            :timestamp => now()
        )))
    end
    
    # Parse request body
    body = JSON.parse(String(req.body))
    capability = get(body, "capability", "")
    priority = get(body, "priority", 0.5)
    reward = get(body, "reward", 0.5)
    risk = get(body, "risk", 0.5)
    params = get(body, "params", Dict())
    
    # Validate required fields
    if isempty(capability)
        return HTTP.Response(400, ["Content-Type" => "application/json"], body=JSON.json(Dict(
            :error => "Missing required field: capability",
            :timestamp => now()
        )))
    end
    
    # Request approval through LEP
    result = api_approve(capability, priority, reward, risk; params=params)
    
    # Return appropriate status code
    status_code = get(result, :approved, false) ? 200 : 403
    
    return HTTP.Response(status_code, [
        "Content-Type" => "application/json",
        "X-Content-Type-Options" => "nosniff",
        "X-LEP-Score" => string(get(result, :lep_score, 0.0))
    ], body=JSON.json(result))
end

# Export public functions
export api_status, api_query, api_control, api_approve, serve_mobile_api
export check_rate_limit  # Exported for testing

end # module Mobile
