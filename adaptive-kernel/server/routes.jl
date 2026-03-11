# routes.jl - API route handlers for HTTP server
# Provides REST endpoints for kernel interaction

module APIRoutes

using HTTP
using JSON
using Dates
using UUIDs

# Import events module
include("events.jl")
using .ServerEvents

# Import websocket module for client count
include("websocket.jl")
using .WebSocketHandler

# ============================================================================
# Response Helpers
# ============================================================================

"""
    Create a JSON response
"""
function json_response(data::Dict{String, Any}; status::HTTP.StatusCode=HTTP.OK)::HTTP.Response
    return HTTP.Response(
        Int(status),
        ["Content-Type" => "application/json"],
        body=JSON.json(data)
    )
end

"""
    Create an error response
"""
function error_response(message::String; status::HTTP.StatusCode=HTTP.BAD_REQUEST)::HTTP.Response
    return json_response(Dict("error" => message); status=status)
end

"""
    Create a success response
"""
function success_response(data::Dict{String, Any})::HTTP.Response
    return json_response(Dict("success" => true, "data" => data))
end

# ============================================================================
# CORS Headers
# ============================================================================

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type, Authorization"
]

"""
    Add CORS headers to response
"""
function add_cors(response::HTTP.Response)::HTTP.Response
    for (key, value) in CORS_HEADERS
        HTTP.setheader(response, key => value)
    end
    return response
end

# ============================================================================
# Route Handlers
# ============================================================================

# Global kernel reference (set by integration)
const _kernel_ref = Ref{Any}(nothing)
const _capability_registry_ref = Ref{Dict{String, Any}}(Dict())
const _goals_ref = Ref{Vector{Dict{String, Any}}}([])

"""
    Set the kernel reference for route handlers
"""
function set_kernel!(kernel)::Nothing
    _kernel_ref[] = kernel
    return nothing
end

"""
    Set the capability registry
"""
function set_capabilities!(capabilities::Dict{String, Any})::Nothing
    _capability_registry_ref[] = capabilities
    return nothing
end

"""
    Set the goals
"""
function set_goals!(goals::Vector{Dict{String, Any}})::Nothing
    _goals_ref[] = goals
    return nothing
end

# ============================================================================
# POST /api/chat
# ============================================================================

"""
    Handle chat message - send user message and get response
"""
function handle_chat(req::HTTP.Request)::HTTP.Response
    # Parse request body
    try
        body = String(req.body)
        data = JSON.parse(body)
    catch e
        return add_cors(error_response("Invalid JSON body"))
    end
    
    message = get(data, "message", "")
    if isempty(message)
        return add_cors(error_response("Message is required"))
    end
    
    # Emit message event (will trigger kernel processing)
    emit_message(message, "incoming")
    
    # Return acknowledgment
    response_data = Dict(
        "message_id" => string(uuid4()),
        "status" => "processing",
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# GET /api/status
# ============================================================================

"""
    Get kernel status
"""
function handle_status(req::HTTP.Request)::HTTP.Response
    # Try to get kernel state if available
    kernel_status = "initializing"
    cycle = 0
    goals = []
    
    try
        if _kernel_ref[] !== nothing
            kernel = _kernel_ref[]
            if isdefined(kernel, :cycle)
                cycle = kernel.cycle
            end
            kernel_status = "running"
        end
    catch e
        kernel_status = "error"
    end
    
    response_data = Dict(
        "status" => kernel_status,
        "cycle" => cycle,
        "clients_connected" => get_client_count(),
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat),
        "uptime_seconds" => time()
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# POST /api/capabilities
# ============================================================================

"""
    List capabilities
"""
function handle_capabilities(req::HTTP.Request)::HTTP.Response
    # Parse request body for optional filtering
    filter = Dict{String, Any}()
    try
        if !isempty(req.body)
            body = String(req.body)
            filter = JSON.parse(body)
        end
    catch e
        # Ignore parsing errors, use empty filter
    end
    
    capabilities = _capability_registry_ref[]
    result = []
    
    for (id, cap) in capabilities
        # Apply filters if provided
        if haskey(filter, "category")
            if get(cap, "category", "") != filter["category"]
                continue
            end
        end
        if haskey(filter, "enabled")
            if get(cap, "enabled", true) != filter["enabled"]
                continue
            end
        end
        
        push!(result, Dict(
            "id" => id,
            "name" => get(cap, "name", id),
            "description" => get(cap, "description", ""),
            "category" => get(cap, "category", ""),
            "enabled" => get(cap, "enabled", true),
            "parameters" => get(cap, "parameters", Dict{String, Any}())
        ))
    end
    
    response_data = Dict(
        "capabilities" => result,
        "count" => length(result)
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# POST /api/execute
# ============================================================================

"""
    Execute a capability
"""
function handle_execute(req::HTTP.Request)::HTTP.Response
    # Parse request body
    try
        body = String(req.body)
        data = JSON.parse(body)
    catch e
        return add_cors(error_response("Invalid JSON body"))
    end
    
    capability_id = get(data, "capability_id", "")
    parameters = get(data, "parameters", Dict{String, Any}())
    
    if isempty(capability_id)
        return add_cors(error_response("capability_id is required"))
    end
    
    # Check if capability exists
    capabilities = _capability_registry_ref[]
    if !haskey(capabilities, capability_id)
        return add_cors(error_response("Capability not found: $capability_id", status=HTTP.NOT_FOUND))
    end
    
    # Emit capability event
    emit_capability(capability_id, "execute"; metadata=Dict(
        "parameters" => parameters,
        "source" => "http_api"
    ))
    
    response_data = Dict(
        "execution_id" => string(uuid4()),
        "capability_id" => capability_id,
        "status" => "started",
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# GET /api/goals
# ============================================================================

"""
    Get current goals
"""
function handle_goals(req::HTTP.Request)::HTTP.Response
    response_data = Dict(
        "goals" => _goals_ref[],
        "count" => length(_goals_ref[])
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# GET /api/events
# ============================================================================

"""
    Get recent events (history)
"""
function handle_events(req::HTTP.Request)::HTTP.Response
    # Parse query parameters
    params = HTTP.queryparams(HTTP.URI(req.target))
    
    count = parse(Int, get(params, "count", "50"))
    count = min(count, 500)  # Cap at 500
    
    event_type = nothing
    type_str = get(params, "type", "")
    if type_str == "thought"
        event_type = EVENT_THOUGHT
    elseif type_str == "action"
        event_type = EVENT_ACTION
    elseif type_str == "goal"
        event_type = EVENT_GOAL
    elseif type_str == "error"
        event_type = EVENT_ERROR
    elseif type_str == "message"
        event_type = EVENT_MESSAGE
    end
    
    events = get_history(count; event_type=event_type)
    
    response_data = Dict(
        "events" => [
            Dict(
                "id" => e.id,
                "type" => string(e.type),
                "timestamp" => Dates.format(e.timestamp, Dates.ISODateTimeFormat),
                "payload" => e.payload,
                "source" => e.source
            ) for e in events
        ],
        "count" => length(events)
    )
    
    return add_cors(success_response(response_data))
end

# ============================================================================
# GET /api/health
# ============================================================================

"""
    Health check endpoint
"""
function handle_health(req::HTTP.Response)::HTTP.Response
    response_data = Dict(
        "status" => "healthy",
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    
    return add_cors(json_response(response_data))
end

# ============================================================================
# Router
# ============================================================================

"""
    Route handler - maps requests to appropriate handlers
"""
function route_request(req::HTTP.Request)::HTTP.Response
    # Handle CORS preflight
    if HTTP.method(req) == "OPTIONS"
        return add_cors(HTTP.Response(200))
    end
    
    # Get path and method
    path = HTTP.path(req)
    method = HTTP.method(req)
    
    # Route to appropriate handler
    if method == "POST" && path == "/api/chat"
        return handle_chat(req)
    elseif method == "GET" && path == "/api/status"
        return handle_status(req)
    elseif method == "POST" && path == "/api/capabilities"
        return handle_capabilities(req)
    elseif method == "POST" && path == "/api/execute"
        return handle_execute(req)
    elseif method == "GET" && path == "/api/goals"
        return handle_goals(req)
    elseif method == "GET" && path == "/api/events"
        return handle_events(req)
    elseif method == "GET" && path == "/api/health"
        return handle_health(req)
    else
        return add_cors(error_response("Not found: $path", status=HTTP.NOT_FOUND))
    end
end

# ============================================================================
# Exports
# ============================================================================

export
    # Route handler
    route_request,
    # State setters
    set_kernel!,
    set_capabilities!,
    set_goals!

end # module
