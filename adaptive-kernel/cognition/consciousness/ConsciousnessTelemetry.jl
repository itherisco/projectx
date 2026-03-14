"""
# ConsciousnessTelemetry.jl

WebSocket-based real-time telemetry for the Consciousness Metrics dashboard.
Provides real-time streaming of consciousness metrics to connected clients.
"""
module ConsciousnessTelemetry

using JSON
using Sockets
using Dates

# Import ConsciousnessMetrics module
using ..ConsciousnessMetrics

"""
    TelemetryServer - WebSocket server for real-time consciousness metrics
"""
mutable struct TelemetryServer
    # Server configuration
    port::Int
    host::String
    
    # Server state
    server_socket::Any  # Union{Server{TCPSocket}, Nothing}
    is_running::Bool
    connected_clients::Vector{TCPSocket}
    
    # Telemetry configuration
    broadcast_interval_ms::Int
    include_history::Bool
    max_history_per_message::Int
    
    # Metrics reference
    metrics_ref::Union{Ref{ConsciousnessMetrics}, Nothing}
    context_ref::Union{Ref{ContextTracker}, Nothing}
    
    # Callbacks
    on_client_connect::Union{Function, Nothing}
    on_client_disconnect::Union{Function, Nothing}
    on_message_received::Union{Function, Nothing}
    
    function TelemetryServer(;
        port::Int=8080,
        host::String="127.0.0.1",
        broadcast_interval_ms::Int=1000,
        include_history::Bool=false,
        max_history_per_message::Int=10
    )
        new(
            port,
            host,
            nothing,
            false,
            TCPSocket[],
            broadcast_interval_ms,
            include_history,
            max_history_per_message,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing
        )
    end
end

"""
    TelemetryClient - Client for connecting to consciousness metrics stream
"""
mutable struct TelemetryClient
    host::String
    port::Int
    socket::Any  # Union{TCPSocket, Nothing}
    is_connected::Bool
    reconnect_attempts::Int
    max_reconnect_attempts::Int
    on_message::Union{Function, Nothing}
    on_connect::Union{Function, Nothing}
    on_disconnect::Union{Function, Nothing}
    
    function TelemetryClient(;
        host::String="127.0.0.1",
        port::Int=8080,
        max_reconnect_attempts::Int=5
    )
        new(
            host,
            port,
            nothing,
            false,
            0,
            max_reconnect_attempts,
            nothing,
            nothing,
            nothing
        )
    end
end

"""
    start_telemetry_server!(server::TelemetryServer, metrics, context_tracker)

Start the WebSocket telemetry server.
"""
function start_telemetry_server!(
    server::TelemetryServer,
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker
)
    # Set refs
    server.metrics_ref = Ref(metrics)
    server.context_ref = Ref(context_tracker)
    
    # Start server (simplified - actual implementation would use proper async)
    try
        server.server_socket = listen(IPAddr(server.host), server.port)
        server.is_running = true
        
        @info "Consciousness Telemetry Server started on $(server.host):$(server.port)"
        
        # In a full implementation, this would spawn async tasks
        # for accepting clients and broadcasting
        
    catch e
        @error "Failed to start telemetry server: $e"
        server.is_running = false
    end
end

"""
    stop_telemetry_server!(server::TelemetryServer)

Stop the WebSocket telemetry server.
"""
function stop_telemetry_server!(server::TelemetryServer)
    if !server.is_running
        return
    end
    
    # Close all client connections
    for client in server.connected_clients
        try
            close(client)
        catch
        end
    end
    
    # Close server
    if server.server_socket !== nothing
        try
            close(server.server_socket)
        catch
        end
    end
    
    server.is_running = false
    server.connected_clients = TCPSocket[]
    
    @info "Consciousness Telemetry Server stopped"
end

"""
    broadcast_metrics(server::TelemetryServer)

Broadcast current metrics to all connected clients.
"""
function broadcast_metrics(server::TelemetryServer)
    if !server.is_running || isempty(server.connected_clients)
        return
    end
    
    # Get current snapshot
    if server.metrics_ref === nothing || server.metrics_ref[] === nothing
        return
    end
    
    metrics = server.metrics_ref[]
    snapshot = metrics.current_snapshot
    
    if snapshot === nothing
        return
    end
    
    # Build message
    message = build_telemetry_message(snapshot, server)
    
    # Broadcast to all clients
    for client in server.connected_clients
        try
            write(client, message * "\n")
        catch e
            # Client disconnected, remove from list
            @warn "Failed to send to client: $e"
        end
    end
end

"""
    build_telemetry_message(snapshot::ConsciousnessSnapshot, server::TelemetryServer) -> String

Build JSON message for telemetry broadcast.
"""
function build_telemetry_message(
    snapshot::ConsciousnessSnapshot,
    server::TelemetryServer
)::String
    data = Dict(
        "type" => "consciousness_metrics",
        "timestamp" => string(snapshot.timestamp),
        "data" => Dict(
            "phi" => round(snapshot.phi, digits=4),
            "gws" => round(snapshot.gws, digits=4),
            "ife" => round(snapshot.ife, digits=4),
            "wmc" => round(snapshot.wmc, digits=4),
            "bci" => round(snapshot.bci, digits=4),
            "sma" => round(snapshot.sma, digits=4),
            "ccs" => round(snapshot.ccs, digits=4),
            "kba" => round(snapshot.kba, digits=4),
            "mcai" => round(snapshot.mcai, digits=4),
            "cdi" => round(snapshot.cdi, digits=4),
            "tcs" => round(snapshot.tcs, digits=4)
        ),
        "context" => Dict(
            "cycle_number" => snapshot.cycle_number,
            "turn_count" => snapshot.context_turn_count,
            "working_memory_size" => snapshot.working_memory_size,
            "num_proposals" => snapshot.num_proposals,
            "conflict_rounds" => snapshot.conflict_rounds
        ),
        "status" => get_all_metric_statuses(snapshot)
    )
    
    return JSON.json(data)
end

"""
    get_all_metric_statuses(snapshot::ConsciousnessSnapshot) -> Dict

Get status for all metrics.
"""
function get_all_metric_statuses(snapshot::ConsciousnessSnapshot)::Dict
    return Dict(
        "phi" => string(get_metric_status(:phi, snapshot.phi)),
        "gws" => string(get_metric_status(:gws, snapshot.gws)),
        "wmc" => string(get_metric_status(:wmc, snapshot.wmc)),
        "sma" => string(get_metric_status(:sma, snapshot.sma)),
        "ccs" => string(get_metric_status(:ccs, snapshot.ccs)),
        "cdi" => string(get_metric_status(:cdi, snapshot.cdi)),
        "tcs" => string(get_metric_status(:tcs, snapshot.tcs))
    )
end

"""
    connect_client!(client::TelemetryClient) -> Bool

Connect to telemetry server.
"""
function connect_client!(client::TelemetryClient)::Bool
    try
        client.socket = connect(client.host, client.port)
        client.is_connected = true
        client.reconnect_attempts = 0
        
        if client.on_connect !== nothing
            client.on_connect()
        end
        
        return true
    catch e
        client.is_connected = false
        @warn "Failed to connect to telemetry server: $e"
        return false
    end
end

"""
    disconnect_client!(client::TelemetryClient)

Disconnect from telemetry server.
"""
function disconnect_client!(client::TelemetryClient)
    if client.socket !== nothing
        try
            close(client.socket)
        catch
        end
    end
    
    client.is_connected = false
    
    if client.on_disconnect !== nothing
        client.on_disconnect()
    end
end

"""
    receive_message(client::TelemetryClient) -> Union{Dict, Nothing}

Receive and parse a message from the server.
"""
function receive_message(client::TelemetryClient)::Union{Dict, Nothing}
    if !client.is_connected || client.socket === nothing
        return nothing
    end
    
    try
        # Non-blocking read would be implemented here
        # For now, return nothing as this is simplified
        return nothing
    catch e
        @warn "Error receiving message: $e"
        disconnect_client!(client)
        return nothing
    end
end

"""
    send_command(client::TelemetryClient, command::Dict) -> Bool

Send a command to the telemetry server.
"""
function send_command(client::TelemetryClient, command::Dict)::Bool
    if !client.is_connected || client.socket === nothing
        return false
    end
    
    try
        message = JSON.json(command) * "\n"
        write(client.socket, message)
        return true
    catch e
        @warn "Failed to send command: $e"
        disconnect_client!(client)
        return false
    end
end

"""
    request_snapshot(client::TelemetryClient)

Request current metrics snapshot from server.
"""
function request_snapshot(client::TelemetryClient)
    return send_command(client, Dict("type" => "get_snapshot"))
end

"""
    subscribe_to_events(client::TelemetryClient, event_types::Vector{String})

Subscribe to specific event types.
"""
function subscribe_to_events(client::TelemetryClient, event_types::Vector{String})
    return send_command(client, Dict(
        "type" => "subscribe",
        "events" => event_types
    ))
end

# ============================================================================
# DASHBOARD DATA STRUCTURES
# ============================================================================

"""
    DashboardData - Pre-computed data for dashboard visualization
"""
struct DashboardData
    # Current values
    current_phi::Float32
    current_gws::Float32
    current_ife::Float32
    current_wmc::Float32
    current_bci::Float32
    current_sma::Float32
    current_ccs::Float32
    current_kba::Float32
    current_mcai::Float32
    current_cdi::Float32
    current_tcs::Float32
    
    # Status colors
    phi_color::String
    gws_color::String
    wmc_color::String
    sma_color::String
    ccs_color::String
    cdi_color::String
    tcs_color::String
    
    # Context info
    cycle_number::Int64
    turn_count::Int
    working_memory_size::Int
    timestamp::DateTime
    
    function DashboardData(snapshot::ConsciousnessSnapshot)
        new(
            snapshot.phi,
            snapshot.gws,
            snapshot.ife,
            snapshot.wmc,
            snapshot.bci,
            snapshot.sma,
            snapshot.ccs,
            snapshot.kba,
            snapshot.mcai,
            snapshot.cdi,
            snapshot.tcs,
            get_status_color(get_metric_status(:phi, snapshot.phi)),
            get_status_color(get_metric_status(:gws, snapshot.gws)),
            get_status_color(get_metric_status(:wmc, snapshot.wmc)),
            get_status_color(get_metric_status(:sma, snapshot.sma)),
            get_status_color(get_metric_status(:ccs, snapshot.ccs)),
            get_status_color(get_metric_status(:cdi, snapshot.cdi)),
            get_status_color(get_metric_status(:tcs, snapshot.tcs)),
            snapshot.cycle_number,
            snapshot.context_turn_count,
            snapshot.working_memory_size,
            snapshot.timestamp
        )
    end
end

"""
    to_dashboard_json(dashboard::DashboardData) -> String

Convert dashboard data to JSON.
"""
function to_dashboard_json(dashboard::DashboardData)::String
    data = Dict(
        "phi" => round(dashboard.current_phi, digits=3),
        "gws" => round(dashboard.current_gws, digits=3),
        "ife" => round(dashboard.current_ife, digits=3),
        "wmc" => round(dashboard.current_wmc, digits=3),
        "bci" => round(dashboard.current_bci, digits=3),
        "sma" => round(dashboard.current_sma, digits=3),
        "ccs" => round(dashboard.current_ccs, digits=3),
        "kba" => round(dashboard.current_kba, digits=3),
        "mcai" => round(dashboard.current_mcai, digits=3),
        "cdi" => round(dashboard.current_cdi, digits=3),
        "tcs" => round(dashboard.current_tcs, digits=3),
        "colors" => Dict(
            "phi" => dashboard.phi_color,
            "gws" => dashboard.gws_color,
            "wmc" => dashboard.wmc_color,
            "sma" => dashboard.sma_color,
            "ccs" => dashboard.ccs_color,
            "cdi" => dashboard.cdi_color,
            "tcs" => dashboard.tcs_color
        ),
        "context" => Dict(
            "cycle" => dashboard.cycle_number,
            "turn" => dashboard.turn_count,
            "memory" => dashboard.working_memory_size
        ),
        "timestamp" => string(dashboard.timestamp)
    )
    
    return JSON.json(data)
end

# ============================================================================
# EXPORT HELPERS
# ============================================================================

"""
    create_telemetry_pipeline(
        metrics::ConsciousnessMetrics,
        context_tracker::ContextTracker;
        enable_websocket::Bool=true,
        websocket_port::Int=8080,
        enable_json_file::Bool=true,
        json_path::String="./consciousness_telemetry.json"
) -> Dict

Create a complete telemetry pipeline with WebSocket and JSON export.
"""
function create_telemetry_pipeline(
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker;
    enable_websocket::Bool=true,
    websocket_port::Int=8080,
    enable_json_file::Bool=true,
    json_path::String="./consciousness_telemetry.json"
)::Dict
    
    pipeline = Dict()
    
    # JSON file export
    if enable_json_file
        # Will be called by run_metrics_cycle!
        pipeline["json_enabled"] = true
        pipeline["json_path"] = json_path
    end
    
    # WebSocket server
    if enable_websocket
        server = TelemetryServer(
            port=websocket_port,
            broadcast_interval_ms=1000
        )
        pipeline["websocket_enabled"] = true
        pipeline["websocket_server"] = server
    else
        pipeline["websocket_enabled"] = false
    end
    
    return pipeline
end

"""
    process_telemetry(
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker,
    pipeline::Dict
)

Process telemetry for current cycle.
"""
function process_telemetry(
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker,
    pipeline::Dict
)
    # Run metrics cycle
    snapshot = update_metrics!(metrics, context_tracker)
    
    # JSON export
    if get(pipeline, "json_enabled", false)
        json_path = get(pipeline, "json_path", "./consciousness_telemetry.json")
        export_to_file(metrics, json_path)
    end
    
    # WebSocket broadcast
    if get(pipeline, "websocket_enabled", false)
        server = get(pipeline, "websocket_server", nothing)
        if server !== nothing && server.is_running
            broadcast_metrics(server)
        end
    end
    
    return snapshot
end

# Export public API
export
    TelemetryServer,
    TelemetryClient,
    start_telemetry_server!,
    stop_telemetry_server!,
    broadcast_metrics,
    connect_client!,
    disconnect_client!,
    receive_message,
    send_command,
    request_snapshot,
    subscribe_to_events,
    DashboardData,
    to_dashboard_json,
    create_telemetry_pipeline,
    process_telemetry

end # module
