# HTTPServer.jl - Main HTTP server with WebSocket support
# Provides HTTP REST API and WebSocket endpoint

module HTTPServer

using HTTP
using HTTP.WebSockets
using JSON
using Dates
using Sockets
using Logging

# Import our modules
include("events.jl")
include("websocket.jl")
include("routes.jl")

using .ServerEvents
using .WebSocketHandler
using .APIRoutes

# ============================================================================
# Server Configuration
# ============================================================================

"""
    ServerConfig - Configuration for the HTTP server
"""
mutable struct ServerConfig
    host::String
    port::Int
    enable_ws::Bool
    ws_path::String
    ssl_enabled::Bool
    ssl_cert::Union{String, Nothing}
    ssl_key::Union{String, Nothing}
end

"""
    Default server configuration
"""
function default_config()::ServerConfig
    return ServerConfig(
        "0.0.0.0",    # host - listen on all interfaces
        8080,         # port
        true,         # enable_ws
        "/ws",        # ws_path
        false,        # ssl_enabled
        nothing,      # ssl_cert
        nothing       # ssl_key
    )
end

"""
    Load configuration from TOML
"""
function load_config(config_path::String="config.toml")::ServerConfig
    config = default_config()
    
    if isfile(config_path)
        try
            toml = TOML.parsefile(config_path)
            
            if haskey(toml, "server")
                server_cfg = toml["server"]
                
                if haskey(server_cfg, "server_host")
                    config.host = server_cfg["server_host"]
                end
                if haskey(server_cfg, "server_port")
                    config.port = server_cfg["server_port"]
                end
                if haskey(server_cfg, "enable_ws")
                    config.enable_ws = server_cfg["enable_ws"]
                end
                if haskey(server_cfg, "ws_path")
                    config.ws_path = server_cfg["ws_path"]
                end
                if haskey(server_cfg, "ssl_enabled")
                    config.ssl_enabled = server_cfg["ssl_enabled"]
                end
                if haskey(server_cfg, "ssl_cert")
                    config.ssl_cert = server_cfg["ssl_cert"]
                end
                if haskey(server_cfg, "ssl_key")
                    config.ssl_key = server_cfg["ssl_key"]
                end
            end
        catch e
            @warn "Failed to parse server config, using defaults" exception=e
        end
    end
    
    return config
end

# ============================================================================
# Server State
# ============================================================================

"""
    ServerState - Runtime state of the HTTP server
"""
mutable struct ServerState
    config::ServerConfig
    running::Bool
    server_task::Union{Task, Nothing}
    start_time::Union{DateTime, Nothing}
end

"""
    Create new server state
"""
function create_state(config::ServerConfig)::ServerState
    return ServerState(
        config,
        false,
        nothing,
        nothing
    )
end

# Global server state
const _server_state = Ref{ServerState}(create_state(default_config()))

"""
    Get current server state
"""
function get_state()::ServerState
    return _server_state[]
end

"""
    Check if server is running
"""
function is_running()::Bool
    return _server_state[].running
end

# ============================================================================
# HTTP Handler
# ============================================================================

"""
    Main HTTP request handler
"""
function handle_request(req::HTTP.Request)::HTTP.Response
    # Get the path
    path = HTTP.path(req)
    
    # Check if it's a WebSocket upgrade request
    if _server_state[].config.enable_ws && startswith(path, _server_state[].config.ws_path)
        # Handle WebSocket upgrade
        return handle_websocket_request(req)
    end
    
    # Handle regular HTTP request
    try
        return APIRoutes.route_request(req)
    catch e
        @error "Request handling error" exception=e
        return HTTP.Response(
            500,
            ["Content-Type" => "application/json"],
            body=JSON.json(Dict("error" => "Internal server error"))
        )
    end
end

"""
    Handle WebSocket upgrade request
"""
function handle_websocket_request(req::HTTP.Request)::HTTP.Response
    # Check if it's a WebSocket upgrade
    if HTTP.hasheader(req, "Upgrade")
        upgrade = HTTP.header(req, "Upgrade")
        if lowercase(upgrade) == "websocket"
            # Handled by HTTP.jl's WebSocket handler
            return HTTP.Response(101)  # Switch to WebSocket
        end
    end
    
    return HTTP.Response(400, body="Expected WebSocket upgrade")
end

# ============================================================================
# Server Lifecycle
# ============================================================================

"""
    Start the HTTP server
"""
function start_server(
    config::Union{ServerConfig, Nothing}=nothing;
    host::Union{String, Nothing}=nothing,
    port::Union{Int, Nothing}=nothing
)::Bool
    # Use provided config or load from file
    if config === nothing
        config = load_config()
    end
    
    # Override with provided values
    if host !== nothing
        config.host = host
    end
    if port !== nothing
        config.port = port
    end
    
    # Update global state
    _server_state[] = create_state(config)
    
    # Start event queue processor
    start_queue_processor()
    
    # Create server
    try
        # Create the server
        server = HTTP.serve(
            handle_request,
            config.host,
            config.port;
            thread=true,
            verbose=false
        )
        
        # Update state
        _server_state[].running = true
        _server_state[].start_time = now(Dates.UTC)
        
        @info "HTTP server started" host=config.host port=config.port ws_enabled=config.enable_ws
        
        # Emit status event
        emit_status("server_started"; metadata=Dict(
            "host" => config.host,
            "port" => config.port,
            "ws_enabled" => config.enable_ws
        ))
        
        # Wait for server (this blocks)
        wait(server)
        
        return true
    catch e
        @error "Failed to start HTTP server" exception=e
        _server_state[].running = false
        emit_error("Failed to start server: $(string(e))")
        return false
    end
end

"""
    Stop the HTTP server
"""
function stop_server()::Bool
    if !_server_state[].running
        @warn "Server is not running"
        return false
    end
    
    try
        _server_state[].running = false
        
        # Stop queue processor
        stop_queue_processor()
        
        # Emit status event
        emit_status("server_stopped")
        
        @info "HTTP server stopped"
        return true
    catch e
        @error "Failed to stop server" exception=e
        return false
    end
end

"""
    Start server in background (non-blocking)
"""
function start_server_background(
    config::Union{ServerConfig, Nothing}=nothing;
    host::Union{String, Nothing}=nothing,
    port::Union{Int, Nothing}=nothing
)::Bool
    if _server_state[].running
        @warn "Server is already running"
        return false
    end
    
    # Use provided config or load from file
    if config === nothing
        config = load_config()
    end
    
    # Override with provided values
    if host !== nothing
        config.host = host
    end
    if port !== nothing
        config.port = port
    end
    
    # Update global state
    _server_state[] = create_state(config)
    
    # Start in background task
    @async begin
        start_server(config)
    end
    
    # Give it a moment to start
    sleep(0.5)
    
    return _server_state[].running
end

# ============================================================================
# WebSocket Integration
# ============================================================================

"""
    Start WebSocket server (called internally by HTTP server)
"""
function start_websocket_server(host::String, port::Int, path::String)::Bool
    try
        HTTP.WebSockets.listen(host, port) do ws
            WebSocketHandler.handle_connection(ws)
        end
        return true
    catch e
        @error "WebSocket server error" exception=e
        return false
    end
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    Get server info
"""
function get_server_info()::Dict{String, Any}
    state = _server_state[]
    return Dict(
        "running" => state.running,
        "host" => state.config.host,
        "port" => state.config.port,
        "ws_enabled" => state.config.enable_ws,
        "ws_path" => state.config.ws_path,
        "start_time" => state.start_time === nothing ? "" : Dates.format(state.start_time, Dates.ISODateTimeFormat),
        "clients_connected" => get_client_count()
    )
end

"""
    Get the server URL
"""
function get_server_url()::String
    state = _server_state[]
    protocol = state.config.ssl_enabled ? "https" : "http"
    return "$protocol://$(state.config.host):$(state.config.port)"
end

"""
    Get the WebSocket URL
"""
function get_websocket_url()::String
    state = _server_state[]
    protocol = state.config.ssl_enabled ? "wss" : "ws"
    return "$protocol://$(state.config.host):$(state.config.port)$(state.config.ws_path)"
end

# ============================================================================
# Exports
# ============================================================================

export
    # Configuration
    ServerConfig,
    default_config,
    load_config,
    # State
    ServerState,
    get_state,
    is_running,
    # Lifecycle
    start_server,
    stop_server,
    start_server_background,
    # Info
    get_server_info,
    get_server_url,
    get_websocket_url

end # module
