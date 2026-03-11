# websocket.jl - WebSocket handling for real-time communication
# Provides WebSocket endpoint, client management, and message queue

module WebSocketHandler

using HTTP.WebSockets
using JSON
using Dates
using UUIDs
using Base.Threads
using Logging

# Import events module
include("events.jl")
using .ServerEvents

# ============================================================================
# Client Management
# ============================================================================

"""
    WSClient - Connected WebSocket client
"""
mutable struct WSClient
    id::String
    connection::HTTP.WebSockets.WebSocket
    connected_at::DateTime
    metadata::Dict{String, Any}
    active::Bool
end

"""
    Create a new WebSocket client
"""
function create_client(connection::HTTP.WebSockets.WebSocket)::WSClient
    return WSClient(
        string(uuid4()),
        connection,
        now(Dates.UTC),
        Dict{String, Any}(),
        true
    )
end

# Global client storage
const _clients = Vector{WSClient}()
const _clients_lock = ReentrantLock()

# Message queue for kernel events
const _message_queue = Channel{ServerEvent}(1024)
const _queue_task = Ref{Task}()

"""
    Get all active clients
"""
function get_clients()::Vector{WSClient}
    lock(_clients_lock) do
        return filter(c -> c.active, copy(_clients))
    end
end

"""
    Get client count
"""
function get_client_count()::Int
    lock(_clients_lock) do
        return count(c -> c.active, _clients)
    end
end

"""
    Add a client
"""
function add_client!(client::WSClient)::Nothing
    lock(_clients_lock) do
        push!(_clients, client)
    end
    @info "WebSocket client connected" client_id=client.id count=get_client_count()
    # Emit status event
    emit_status("client_connected"; metadata=Dict("client_id" => client.id))
    return nothing
end

"""
    Remove a client
"""
function remove_client!(client_id::String)::Nothing
    lock(_clients_lock) do
        for client in _clients
            if client.id == client_id
                client.active = false
                break
            end
        end
    end
    @info "WebSocket client disconnected" client_id=client_id count=get_client_count()
    emit_status("client_disconnected"; metadata=Dict("client_id" => client_id))
    return nothing
end

"""
    Find client by ID
"""
function find_client(client_id::String)::Union{WSClient, Nothing}
    lock(_clients_lock) do
        for client in _clients
            if client.id == client_id && client.active
                return client
            end
        end
    end
    return nothing
end

# ============================================================================
# WebSocket Message Handling
# ============================================================================

"""
    Send message to a specific client
"""
function send_to_client(client::WSClient, message::String)::Bool
    try
        if client.active
            write(client.connection, message)
            return true
        end
    catch e
        @error "Failed to send message to client" exception=e client_id=client.id
    end
    return false
end

"""
    Send JSON to a client
"""
function send_json(client::WSClient, data::Dict{String, Any})::Bool
    return send_to_client(client, JSON.json(data))
end

"""
    Send event to a client
"""
function send_event(client::WSClient, event::ServerEvent)::Bool
    return send_to_client(client, to_json(event))
end

"""
    Broadcast message to all active clients
"""
function broadcast_message(message::String)::Int
    count = 0
    for client in get_clients()
        if send_to_client(client, message)
            count += 1
        end
    end
    return count
end

"""
    Broadcast event to all active clients
"""
function broadcast_event(event::ServerEvent)::Int
    return broadcast_message(to_json(event))
end

# ============================================================================
# WebSocket Handler Function
# ============================================================================

"""
    Handle incoming WebSocket connection
    
    This is the main entry point for WebSocket connections.
    It runs in its own task and handles the connection lifecycle.
"""
function handle_connection(ws::HTTP.WebSockets.WebSocket)::Nothing
    client = create_client(ws)
    add_client!(client)
    
    # Send welcome message
    welcome = Dict(
        "type" => "welcome",
        "client_id" => client.id,
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    send_json(client, welcome)
    
    # Subscribe to events
    sub_id = subscribe(broadcast_event)
    
    try
        # Message receive loop
        for msg in ws
            try
                handle_message(client, msg)
            catch e
                @error "Error handling WebSocket message" exception=e client_id=client.id
            end
        end
    catch e
        if !isa(e, Base.IOError)
            @error "WebSocket connection error" exception=e client_id=client.id
        end
    finally
        # Cleanup
        unsubscribe(sub_id)
        remove_client!(client.id)
    end
    
    return nothing
end

"""
    Handle incoming message from client
"""
function handle_message(client::WSClient, raw_message::Union{String, Vector{UInt8}})::Nothing
    # Convert Vector{UInt8} to String if needed
    message = raw_message isa String ? raw_message : String(raw_message)
    
    # Parse JSON
    try
        data = JSON.parse(message)
        msg_type = get(data, "type", "")
        
        # Route to appropriate handler
        if msg_type == "ping"
            handle_ping(client, data)
        elseif msg_type == "subscribe"
            handle_subscribe(client, data)
        elseif msg_type == "unsubscribe"
            handle_unsubscribe(client, data)
        elseif msg_type == "chat"
            handle_chat_message(client, data)
        elseif msg_type == "execute"
            handle_execute(client, data)
        elseif msg_type == "get_status"
            handle_get_status(client, data)
        elseif msg_type == "get_goals"
            handle_get_goals(client, data)
        elseif msg_type == "get_history"
            handle_get_history(client, data)
        else
            # Unknown message type
            response = Dict(
                "type" => "error",
                "message" => "Unknown message type: $msg_type"
            )
            send_json(client, response)
        end
    catch e
        @error "Failed to parse message" exception=e client_id=client.id
        response = Dict(
            "type" => "error",
            "message" => "Invalid JSON"
        )
        send_json(client, response)
    end
    
    return nothing
end

"""
    Handle ping message
"""
function handle_ping(client::WSClient, data::Dict{String, Any})::Nothing
    response = Dict(
        "type" => "pong",
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    send_json(client, response)
    return nothing
end

"""
    Handle subscribe message - subscribe to specific event types
"""
function handle_subscribe(client::WSClient, data::Dict{String, Any})::Nothing
    # For now, just acknowledge - full filtering handled in events module
    response = Dict(
        "type" => "subscribed",
        "events" => get(data, "events", ["all"])
    )
    send_json(client, response)
    return nothing
end

"""
    Handle unsubscribe message
"""
function handle_unsubscribe(client::WSClient, data::Dict{String, Any})::Nothing
    response = Dict(
        "type" => "unsubscribed",
        "events" => get(data, "events", ["all"])
    )
    send_json(client, response)
    return nothing
end

"""
    Handle chat message from client
"""
function handle_chat_message(client::WSClient, data::Dict{String, Any})::Nothing
    message = get(data, "message", "")
    
    # Emit the message event (will be processed by kernel integration)
    emit_message(message, "incoming"; metadata=Dict("client_id" => client.id))
    
    # Acknowledge receipt
    response = Dict(
        "type" => "message_received",
        "message" => message,
        "client_id" => client.id
    )
    send_json(client, response)
    
    return nothing
end

"""
    Handle execute capability request
"""
function handle_execute(client::WSClient, data::Dict{String, Any})::Nothing
    capability_id = get(data, "capability_id", "")
    parameters = get(data, "parameters", Dict{String, Any}())
    
    # Emit capability event
    emit_capability(capability_id, "execute"; metadata=Dict(
        "client_id" => client.id,
        "parameters" => parameters
    ))
    
    # Acknowledge
    response = Dict(
        "type" => "execution_started",
        "capability_id" => capability_id
    )
    send_json(client, response)
    
    return nothing
end

"""
    Handle get status request
"""
function handle_get_status(client::WSClient, data::Dict{String, Any})::Nothing
    response = Dict(
        "type" => "status",
        "status" => "running",
        "clients_connected" => get_client_count(),
        "timestamp" => Dates.format(now(Dates.UTC), Dates.ISODateTimeFormat)
    )
    send_json(client, response)
    return nothing
end

"""
    Handle get goals request
"""
function handle_get_goals(client::WSClient, data::Dict{String, Any})::Nothing
    # Get recent goal events from history
    goal_events = get_history(50; event_type=EVENT_GOAL)
    
    goals = []
    for event in goal_events
        push!(goals, Dict(
            "id" => event.id,
            "goal_id" => get(event.payload, "goal_id", ""),
            "status" => get(event.payload, "status", ""),
            "timestamp" => Dates.format(event.timestamp, Dates.ISODateTimeFormat)
        ))
    end
    
    response = Dict(
        "type" => "goals",
        "goals" => goals
    )
    send_json(client, response)
    return nothing
end

"""
    Handle get history request
"""
function handle_get_history(client::WSClient, data::Dict{String, Any})::Nothing
    n = get(data, "count", 50)
    event_type_str = get(data, "event_type", "")
    
    event_type = nothing
    if event_type_str == "thought"
        event_type = EVENT_THOUGHT
    elseif event_type_str == "action"
        event_type = EVENT_ACTION
    elseif event_type_str == "goal"
        event_type = EVENT_GOAL
    elseif event_type_str == "error"
        event_type = EVENT_ERROR
    elseif event_type_str == "message"
        event_type = EVENT_MESSAGE
    end
    
    events = get_history(n; event_type=event_type)
    
    response = Dict(
        "type" => "history",
        "events" => [
            Dict(
                "id" => e.id,
                "type" => string(e.type),
                "timestamp" => Dates.format(e.timestamp, Dates.ISODateTimeFormat),
                "payload" => e.payload
            ) for e in events
        ]
    )
    send_json(client, response)
    return nothing
end

# ============================================================================
# Event Queue Background Task
# ============================================================================

"""
    Start the event queue processing task
"""
function start_queue_processor()
    if !isassigned(_queue_task) || !istaskrunning(_queue_task[])
        _queue_task[] = @task begin
            for event in _message_queue
                broadcast_event(event)
            end
        end
        schedule(_queue_task[])
    end
end

"""
    Stop the event queue processor
"""
function stop_queue_processor()
    if isassigned(_queue_task) && istaskrunning(_queue_task[])
        close(_message_queue)
    end
end

# ============================================================================
# Exports
# ============================================================================

export
    # Client management
    WSClient,
    create_client,
    add_client!,
    remove_client!,
    find_client,
    get_clients,
    get_client_count,
    # Messaging
    send_to_client,
    send_json,
    send_event,
    broadcast_message,
    broadcast_event,
    # Handler
    handle_connection,
    handle_message,
    # Queue
    start_queue_processor,
    stop_queue_processor

end # module
