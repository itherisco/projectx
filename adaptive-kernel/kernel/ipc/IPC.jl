# IPC.jl - Production-grade Julia IPC Channel for Rust Communication
#
# This module implements the Julia side of the IPC bridge to communicate
# with the Rust kernel via shared memory ring buffers.
#
# Requirements:
# - Connect to Rust ring buffer via shared memory or TCP
# - Handle disconnections gracefully (enter SAFE_MODE)
# - Async message processing with proper error handling
# - Timeout handling (1 second max wait)
# - Automatic reconnection with exponential backoff
# - Heartbeat monitoring

module IPC

using Sockets
using JSON3
using Dates
using Random
using Base.Threads
using SHA

export 
    IPCChannel,
    send_proposal,
    receive_verdict,
    is_brain_connected,
    connect,
    disconnect,
    HeartbeatMonitor

# ============================================================================
# Type Definitions
# ============================================================================

"""IPC Channel state"""
@enum IPCState DISCONNECTED CONNECTING CONNECTED RECONNECTING FAILED

"""
    IPCChannel - Julia-side IPC channel for Rust communication
    
    Fields:
    - socket: TCP socket connection to Rust
    - last_heartbeat: Last received heartbeat timestamp
    - reconnect_attempts: Number of reconnection attempts
    - max_reconnect_attempts: Maximum reconnection attempts before giving up
    - state: Current connection state
    - message_queue: Queue for failed sends
    - safe_mode: Whether we're in safe/fallback mode
"""
mutable struct IPCChannel
    socket::Union{TCPSocket, Nothing}
    last_heartbeat::DateTime
    reconnect_attempts::Int
    max_reconnect_attempts::Int
    state::IPCState
    message_queue::Vector{Dict{String, Any}}
    safe_mode::Bool
    lock::ReentrantLock
    
    function IPCChannel(;max_reconnect_attempts::Int=10)
        new(
            nothing,
            DateTime(0),
            0,
            max_reconnect_attempts,
            DISCONNECTED,
            Vector{Dict{String, Any}}(),
            false,
            ReentrantLock()
        )
    end
end

"""
    Proposal - Action proposal to send to Rust brain
"""
struct Proposal
    id::UInt64
    action::String
    confidence::Float32
    features::Vector{Float32}
end

"""
    Verdict - Response from Rust brain
"""
struct Verdict
    proposal_id::UInt64
    approved::Bool
    reward::Float32
    reason::Union{String, Nothing}
end

"""
    WorldState - World state update from Rust
"""
struct WorldState
    timestamp::UInt64
    energy::Float32
    observations::Dict{String, Float32}
end

"""
    Heartbeat - Heartbeat message
"""
struct Heartbeat
    sender::String
    timestamp::UInt64
end

# ============================================================================
# Constants
# ============================================================================

const DEFAULT_IPC_HOST = "127.0.0.1"
const DEFAULT_IPC_PORT = 5555
const HEARTBEAT_TIMEOUT_SECONDS = 2.0
const RECONNECT_BASE_DELAY_SECONDS = 0.1
const RECONNECT_MAX_DELAY_SECONDS = 5.0
const MESSAGE_TIMEOUT_SECONDS = 1.0

# Message type IDs (matching Rust)
const MSG_TYPE_PROPOSAL = 0x01
const MSG_TYPE_VERDICT = 0x02
const MSG_TYPE_WORLDSTATE = 0x03
const MSG_TYPE_HEARTBEAT = 0x04

# Protocol version
const IPC_PROTOCOL_VERSION = 0x01

# ============================================================================
# Connection Management
# ============================================================================

"""
    Connect to the Rust brain
    
    Arguments:
    - channel::IPCChannel - The IPC channel to use
    - host::String - Host to connect to (default: 127.0.0.1)
    - port::Int - Port to connect to (default: 5555)
    
    Returns: true if connected, false otherwise
"""
function connect(channel::IPCChannel; host::String=DEFAULT_IPC_HOST, port::Int=DEFAULT_IPC_PORT)::Bool
    lock(channel.lock) do
        if channel.state == CONNECTED
            return true
        end
        
        channel.state = CONNECTING
        
        try
            # Try to connect to Rust brain
            sock = Sockets.connect(host, port)
            channel.socket = sock
            channel.state = CONNECTED
            channel.reconnect_attempts = 0
            channel.safe_mode = false
            
            println("[IPC] Connected to Rust brain at $host:$port")
            true
        catch e
            channel.state = FAILED
            println("[IPC] Failed to connect: $e")
            channel.safe_mode = true
            false
        end
    end
end

"""
    Disconnect from the Rust brain
"""
function disconnect(channel::IPCChannel)::Nothing
    lock(channel.lock) do
        if channel.socket !== nothing
            try
                close(channel.socket)
            catch e
                println("[IPC] Warning: Error closing socket: $e")
            end
            channel.socket = nothing
        end
        channel.state = DISCONNECTED
        println("[IPC] Disconnected from Rust brain")
    end
    nothing
end

"""
    Check if brain is connected
"""
function is_brain_connected(channel::IPCChannel)::Bool
    lock(channel.lock) do
        channel.state == CONNECTED && !is_heartbeat_stale(channel)
    end
end

"""
    Check if heartbeat is stale (>2 seconds since last heartbeat)
"""
function is_heartbeat_stale(channel::IPCChannel)::Bool
    if channel.last_heartbeat == DateTime(0)
        return true  # No heartbeat received yet
    end
    
    now = DateTime(now())
    diff = now - channel.last_heartbeat
    Dates.value(Second(diff)) > HEARTBEAT_TIMEOUT_SECONDS
end

# ============================================================================
# Reconnection with Exponential Backoff
# ============================================================================

"""
    Attempt to reconnect with exponential backoff
"""
function reconnect(channel::IPCChannel; max_attempts::Int=channel.max_reconnect_attempts)::Bool
    lock(channel.lock) do
        if channel.reconnect_attempts >= max_attempts
            println("[IPC] Max reconnection attempts reached")
            channel.state = FAILED
            channel.safe_mode = true
            return false
        end
        
        channel.state = RECONNECTING
        channel.reconnect_attempts += 1
        
        # Calculate delay with exponential backoff
        delay = min(
            RECONNECT_BASE_DELAY_SECONDS * (2^(channel.reconnect_attempts - 1)),
            RECONNECT_MAX_DELAY_SECONDS
        )
        
        println("[IPC] Reconnection attempt $(channel.reconnect_attempts), waiting $(round(delay, digits=2))s...")
        sleep(delay)
        
        # Try to reconnect
        try
            if channel.socket !== nothing
                try
                    close(channel.socket)
                catch
                end
            end
            
            sock = Sockets.connect(DEFAULT_IPC_HOST, DEFAULT_IPC_PORT)
            channel.socket = sock
            channel.state = CONNECTED
            channel.reconnect_attempts = 0
            
            println("[IPC] Reconnected successfully")
            true
        catch e
            println("[IPC] Reconnection failed: $e")
            channel.state = FAILED
            false
        end
    end
end

# ============================================================================
# Message Sending
# ============================================================================

"""
    Send a proposal to the Rust brain
    
    Arguments:
    - channel::IPCChannel - The IPC channel
    - proposal::Proposal - The proposal to send
    
    Returns: true if sent successfully, false otherwise
"""
function send_proposal(channel::IPCChannel, proposal::Proposal)::Bool
    lock(channel.lock) do
        if !is_brain_connected(channel)
            # Try to reconnect
            if !reconnect(channel)
                # Queue the message for later
                push!(channel.message_queue, Dict(
                    "type" => "proposal",
                    "id" => proposal.id,
                    "action" => proposal.action,
                    "confidence" => proposal.confidence,
                    "features" => proposal.features
                ))
                return false
            end
        end
        
        try
            msg = Dict(
                "version" => IPC_PROTOCOL_VERSION,
                "msg_type" => MSG_TYPE_PROPOSAL,
                "timestamp" => round(Int, time() * 1000),
                "payload" => Dict(
                    "id" => proposal.id,
                    "action" => proposal.action,
                    "confidence" => proposal.confidence,
                    "features" => proposal.features
                )
            )
            
            data = JSON3.write(msg)
            
            # Send message with timeout
            if channel.socket !== nothing
                write(channel.socket, data)
                write(channel.socket, "\n")  # Message delimiter
                flush(channel.socket)
                return true
            else
                return false
            end
        catch e
            println("[IPC] Error sending proposal: $e")
            channel.state = FAILED
            return false
        end
    end
end

"""
    Send any message to the Rust brain
"""
function send_message(channel::IPCChannel, msg_type::UInt8, payload::Dict{String, Any})::Bool
    lock(channel.lock) do
        if !is_brain_connected(channel)
            if !reconnect(channel)
                return false
            end
        end
        
        try
            msg = Dict(
                "version" => IPC_PROTOCOL_VERSION,
                "msg_type" => msg_type,
                "timestamp" => round(Int, time() * 1000),
                "payload" => payload
            )
            
            data = JSON3.write(msg)
            
            if channel.socket !== nothing
                write(channel.socket, data)
                write(channel.socket, "\n")
                flush(channel.socket)
                return true
            else
                return false
            end
        catch e
            println("[IPC] Error sending message: $e")
            channel.state = FAILED
            return false
        end
    end
end

# ============================================================================
# Message Receiving
# ============================================================================

"""
    Receive a verdict from the Rust brain
    
    Arguments:
    - channel::IPCChannel - The IPC channel
    
    Returns: Verdict if received, nothing if no verdict or error
"""
function receive_verdict(channel::IPCChannel)::Union{Verdict, Nothing}
    lock(channel.lock) do
        if channel.socket === nothing
            return nothing
        end
        
        # Set read timeout
        channel.socket.read_timeout = MESSAGE_TIMEOUT_SECONDS
        
        try
            # Read line (message delimiter)
            data = readline(channel.socket; keep=true)
            
            if isempty(data)
                return nothing
            end
            
            # Parse JSON
            msg = JSON3.read(data, Dict{String, Any})
            
            # Check version
            version = get(msg, "version", 0)
            if version > IPC_PROTOCOL_VERSION
                println("[IPC] Warning: Version mismatch, got $version, expected $IPC_PROTOCOL_VERSION")
            end
            
            msg_type = msg["msg_type"]
            
            if msg_type == MSG_TYPE_VERDICT
                payload = msg["payload"]
                return Verdict(
                    payload["proposal_id"],
                    payload["approved"],
                    payload["reward"],
                    get(payload, "reason", nothing)
                )
            elseif msg_type == MSG_TYPE_HEARTBEAT
                # Update heartbeat
                channel.last_heartbeat = DateTime(now())
                return nothing
            else
                println("[IPC] Warning: Unexpected message type: $msg_type")
                return nothing
            end
        catch e
            if isa(e, IOError) || isa(e, MethodError)
                # Timeout or connection error - check if we need to reconnect
                if is_heartbeat_stale(channel)
                    println("[IPC] Heartbeat stale, attempting reconnection...")
                    reconnect(channel)
                end
            else
                println("[IPC] Error receiving verdict: $e")
            end
            return nothing
        end
    end
end

"""
    Receive any message from the Rust brain
    
    Returns: Dict with message data, or nothing
"""
function receive_message(channel::IPCChannel; timeout::Float64=MESSAGE_TIMEOUT_SECONDS)::Union{Dict{String, Any}, Nothing}
    lock(channel.lock) do
        if channel.socket === nothing
            return nothing
        end
        
        channel.socket.read_timeout = timeout
        
        try
            data = readline(channel.socket; keep=true)
            
            if isempty(data)
                return nothing
            end
            
            msg = JSON3.read(data, Dict{String, Any})
            
            # Update heartbeat if received
            if get(msg, "msg_type", 0) == MSG_TYPE_HEARTBEAT
                channel.last_heartbeat = DateTime(now())
            end
            
            return msg
        catch e
            if isa(e, IOError)
                # Timeout - normal case
            elseif isa(e, MethodError)
                # Parse error
                println("[IPC] Error parsing message: $e")
            else
                println("[IPC] Error receiving message: $e")
            end
            return nothing
        end
    end
end

# ============================================================================
# Heartbeat Monitor
# ============================================================================

"""
    HeartbeatMonitor - Background task for monitoring connection health
"""
mutable struct HeartbeatMonitor
    task::Union{Task, Nothing}
    running::Bool
    channel::IPCChannel
    
    function HeartbeatMonitor(channel::IPCChannel)
        new(nothing, false, channel)
    end
end

"""
    Start the heartbeat monitor
"""
function start_heartbeat_monitor(monitor::HeartbeatMonitor)::Nothing
    if monitor.running
        return
    end
    
    monitor.running = true
    
    monitor.task = @async begin
        while monitor.running
            # Check if heartbeat is stale
            if is_heartbeat_stale(monitor.channel)
                println("[IPC] Heartbeat stale, attempting reconnection...")
                reconnect(monitor.channel)
            end
            
            # Also try to flush any queued messages
            flush_message_queue!(monitor.channel)
            
            # Wait 1 second before next check
            sleep(1.0)
        end
    end
    
    nothing
end

"""
    Stop the heartbeat monitor
"""
function stop_heartbeat_monitor(monitor::HeartbeatMonitor)::Nothing
    monitor.running = false
    if monitor.task !== nothing
        try
            schedule(monitor.task, InterruptException())
        catch
        end
    end
    nothing
end

# ============================================================================
# Message Queue Management
# ============================================================================

"""
    Flush any queued messages
"""
function flush_message_queue!(channel::IPCChannel)::Nothing
    lock(channel.lock) do
        if isempty(channel.message_queue)
            return nothing
        end
        
        if !is_brain_connected(channel)
            return nothing
        end
        
        # Try to send queued messages
        remaining = Vector{Dict{String, Any}}()
        
        for msg in channel.message_queue
            msg_type = msg["type"]
            
            if msg_type == "proposal"
                proposal = Proposal(
                    msg["id"],
                    msg["action"],
                    msg["confidence"],
                    msg["features"]
                )
                
                if !send_proposal(channel, proposal)
                    push!(remaining, msg)
                end
            end
        end
        
        channel.message_queue = remaining
    end
    
    nothing
end

# ============================================================================
# Safe Mode
# ============================================================================

"""
    Enter safe/fallback mode when connection is lost
"""
function enter_safe_mode(channel::IPCChannel)::Nothing
    lock(channel.lock) do
        channel.safe_mode = true
        channel.state = FAILED
        println("[IPC] WARNING: Entering SAFE_MODE - operating without Rust brain")
    end
    nothing
end

"""
    Check if in safe mode
"""
function is_safe_mode(channel::IPCChannel)::Bool
    channel.safe_mode
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    Get current timestamp in milliseconds
"""
function current_timestamp_ms()::UInt64
    round(UInt64, time() * 1000)
end

"""
    Create a proposal
"""
function create_proposal(action::String, confidence::Float32; features::Vector{Float32}=Float32[], id::UInt64=rand(UInt64))::Proposal
    Proposal(id, action, confidence, features)
end

"""
    Wait for verdict with timeout
    
    Returns: Verdict if received, nothing if timeout
"""
function wait_for_verdict(channel::IPCChannel; timeout::Float64=5.0)::Union{Verdict, Nothing}
    start = time()
    
    while (time() - start) < timeout
        verdict = receive_verdict(channel)
        if verdict !== nothing
            return verdict
        end
        sleep(0.1)
    end
    
    return nothing
end

# ============================================================================
# Example Usage
# ============================================================================

# Example usage:
# ```
# channel = IPCChannel()
# connect(channel)
# 
# proposal = create_proposal("analyze_logs", 0.95, features=[1.0, 2.0, 3.0])
# send_proposal(channel, proposal)
# 
# verdict = wait_for_verdict(channel)
# if verdict !== nothing
#     println("Received verdict: approved=$(verdict.approved)")
# end
# 
# disconnect(channel)
# ```

end # module
