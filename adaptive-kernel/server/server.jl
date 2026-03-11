# server.jl - Main server module entry point
# Provides server startup, kernel integration, and health checks

module Server

using HTTP
using JSON
using Dates
using Logging
using TOML
using Base.Threads

# Include submodules
include("events.jl")
include("websocket.jl")
include("routes.jl")
include("HTTPServer.jl")

# Import all from submodules
using .ServerEvents
using .WebSocketHandler
using .APIRoutes
using .HTTPServer

# ============================================================================
# Module State
# ============================================================================

# Global kernel reference
const _kernel = Ref{Any}(nothing)

"""
    Set the kernel reference for server integration
"""
function set_kernel!(kernel)::Nothing
    _kernel[] = kernel
    APIRoutes.set_kernel!(kernel)
    return nothing
end

"""
    Get the kernel reference
"""
function get_kernel()
    return _kernel[]
end

# ============================================================================
# Server Startup
# ============================================================================

"""
    Start the server with the given configuration
    
    # Arguments
    - config_path::String: Path to config.toml
    - blocking::Bool: Whether to block (true) or run in background (false)
    
    # Returns
    - Bool: Whether the server started successfully
"""
function start(
    config_path::String="./config.toml";
    blocking::Bool=false
)::Bool
    # Load configuration
    config = HTTPServer.load_config(config_path)
    
    @info "Starting ProjectX Server" host=config.host port=config.port ws_enabled=config.enable_ws
    
    # Start server
    if blocking
        return HTTPServer.start_server(config)
    else
        return HTTPServer.start_server_background(config)
    end
end

"""
    Stop the server
"""
function stop()::Bool
    return HTTPServer.stop_server()
end

"""
    Restart the server
"""
function restart(config_path::String="./config.toml")::Bool
    stop()
    sleep(1)  # Wait for cleanup
    return start(config_path)
end

# ============================================================================
# Kernel Integration
# ============================================================================

"""
    Initialize server integration with the kernel
    
    This should be called after kernel initialization to:
    - Set kernel reference
    - Load capability registry
    - Set up event handlers
"""
function integrate_with_kernel!(
    kernel;
    capability_registry_path::String="./adaptive-kernel/registry/capability_registry.json"
)::Nothing
    # Set kernel reference
    set_kernel!(kernel)
    
    # Load capability registry
    if isfile(capability_registry_path)
        try
            capabilities = JSON.parsefile(capability_registry_path)
            APIRoutes.set_capabilities!(capabilities)
            @info "Loaded capability registry" count=length(capabilities)
        catch e
            @warn "Failed to load capability registry" exception=e
        end
    else
        @warn "Capability registry not found" path=capability_registry_path
    end
    
    # Set up event handlers for kernel integration
    _setup_event_handlers()
    
    @info "Server kernel integration complete"
    return nothing
end

"""
    Set up event handlers for kernel events
"""
function _setup_event_handlers()::Nothing
    # Subscribe to events to forward to WebSocket clients
    # This is already handled by the WebSocket module
    return nothing
end

"""
    Process incoming message from chat API
    
    This is called when a chat message is received via HTTP or WebSocket
    and should trigger the kernel cognitive cycle.
"""
function process_chat_message(message::String; metadata::Dict{String, Any}=Dict{String, Any}())::Nothing
    kernel = _kernel[]
    
    if kernel !== nothing
        try
            # Emit thought event
            emit_thought("Processing chat message: $message"; metadata=metadata)
            
            # TODO: Integrate with kernel cognitive cycle
            # This would call the kernel's message processing function
            # For now, just emit the message event
            
        catch e
            @error "Failed to process chat message" exception=e
            emit_error("Failed to process message: $(string(e))")
        end
    else
        @warn "No kernel available for message processing"
    end
    
    return nothing
end

"""
    Update goals from kernel
"""
function update_goals!(goals::Vector{Dict{String, Any}})::Nothing
    APIRoutes.set_goals!(goals)
    return nothing
end

# ============================================================================
# Health Checks
# ============================================================================

"""
    Check server health
    
    Returns a Dict with health status information
"""
function health_check()::Dict{String, Any}
    return Dict(
        "status" => HTTPServer.is_running() ? "healthy" : "stopped",
        "server" => HTTPServer.get_server_info(),
        "clients" => Dict(
            "count" => get_client_count()
        ),
        "events" => Dict(
            "history_size" => length(ServerEvents.get_history(0))
        ),
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
end

"""
    Perform a comprehensive system check
    
    Returns a Dict with system status
"""
function system_check()::Dict{String, Any}
    kernel_healthy = _kernel[] !== nothing
    
    return Dict(
        "server" => Dict(
            "running" => HTTPServer.is_running(),
            "url" => HTTPServer.get_server_url(),
            "ws_url" => HTTPServer.get_websocket_url()
        ),
        "kernel" => Dict(
            "available" => kernel_healthy,
            "healthy" => kernel_healthy  # Could add more checks
        ),
        "clients" => Dict(
            "connected" => get_client_count()
        ),
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    Get server status summary
"""
function status()::String
    if HTTPServer.is_running()
        info = HTTPServer.get_server_info()
        return "Server running at $(info["host"]):$(info["port"]) (ws: $(info["ws_enabled"]))"
    else
        return "Server stopped"
    end
end

"""
    Broadcast message to all connected clients
"""
function broadcast_to_clients(message::Dict{String, Any})::Int
    return broadcast_message(JSON.json(message))
end

"""
    Get connection info for clients
"""
function get_connection_info()::Vector{Dict{String, Any}}
    clients = get_clients()
    return [
        Dict(
            "id" => c.id,
            "connected_at" => Dates.format(c.connected_at, Dates.ISODateTimeFormat),
            "metadata" => c.metadata
        ) for c in clients
    ]
end

# ============================================================================
# Exports
# ============================================================================

export
    # Lifecycle
    start,
    stop,
    restart,
    # Integration
    integrate_with_kernel!,
    set_kernel!,
    get_kernel,
    process_chat_message,
    update_goals!,
    # Health
    health_check,
    system_check,
    status,
    # Utilities
    broadcast_to_clients,
    get_connection_info,
    # Submodule exports
    ServerEvents,
    WebSocketHandler,
    APIRoutes,
    HTTPServer

end # module
