# IPC.jl - Production-grade Julia IPC Channel for Rust Communication
#
# This module implements the Julia side of the IPC bridge to communicate
# with the Rust kernel via shared memory ring buffers.
#
# Requirements:
# - Connect to Rust ring buffer via shared memory (/dev/shm/itheris_ipc)
# - Handle disconnections gracefully (enter SAFE_MODE)
# - Async message processing with proper error handling
# - Timeout handling (1 second max wait)
# - Automatic reconnection with exponential backoff
# - Heartbeat monitoring
# - Target: 1.97M thoughts per second throughput via 64MB lock-free ring buffer

module IPC

using Sockets
using JSON3
using Dates
using Random
using Base.Threads
using SHA
using Mmap

export 
    IPCChannel,
    send_proposal,
    receive_verdict,
    is_brain_connected,
    connect,
    disconnect,
    HeartbeatMonitor,
    SHM_PATH,
    SHM_SIZE,
    connect_shm,
    disconnect_shm,
    is_shm_available,
    is_shm_mode,
    get_connection_mode,
    create_shm_region

# ============================================================================
# Type Definitions
# ============================================================================

"""IPC Channel state"""
@enum IPCState DISCONNECTED CONNECTING CONNECTED RECONNECTING FAILED

"""
    IPCChannel - Julia-side IPC channel for Rust communication
    
    Supports both shared memory (primary) and TCP (fallback) modes.
    
    Fields:
    - mode: :shm for shared memory, :tcp for TCP fallback
    - socket: TCP socket connection (when in TCP mode)
    - shm_fd: Shared memory file descriptor (when in SHM mode)
    - shm_data: Mmapped shared memory region
    - producer_idx: Atomic producer index for ring buffer
    - consumer_idx: Atomic consumer index for ring buffer
    - last_heartbeat: Last received heartbeat timestamp
    - reconnect_attempts: Number of reconnection attempts
    - max_reconnect_attempts: Maximum reconnection attempts before giving up
    - state: Current connection state
    - message_queue: Queue for failed sends
    - safe_mode: Whether we're in safe/fallback mode
"""
mutable struct IPCChannel
    mode::Symbol  # :shm or :tcp
    socket::Union{TCPSocket, Nothing}
    shm_fd::Int
    shm_data::Union{Mmap.AnonMmap, Nothing}
    producer_idx::Base.Threads.Atomic{UInt64}
    consumer_idx::Base.Threads.Atomic{UInt64}
    last_heartbeat::DateTime
    reconnect_attempts::Int
    max_reconnect_attempts::Int
    state::IPCState
    message_queue::Vector{Dict{String, Any}}
    safe_mode::Bool
    lock::ReentrantLock
    
    function IPCChannel(;max_reconnect_attempts::Int=10)
        new(
            :tcp,  # Default to TCP, will upgrade to SHM if available
            nothing,
            -1,
            nothing,
            Base.Threads.Atomic{UInt64}(0),
            Base.Threads.Atomic{UInt64}(0),
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

# Shared memory configuration - 64MB lock-free ring buffer
const SHM_PATH = "/dev/shm/itheris_ipc"
const SHM_SIZE = 0x0400_0000  # 64MB (67108864 bytes)
const SHM_ENTRIES = 256  # Ring buffer entries
const SHM_ENTRY_SIZE = div(SHM_SIZE, SHM_ENTRIES)  # 262144 bytes per entry

# Atomic index offsets (cache-line aligned)
const PRODUCER_INDEX_OFFSET = 0
const CONSUMER_INDEX_OFFSET = 64

# Message data offset (after atomic indices)
const MESSAGE_DATA_OFFSET = 128

# Default TCP fallback (for when shared memory is unavailable)
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

# IPC Magic for validation
const IPC_MAGIC = 0x49544852  # "ITHR"

# ============================================================================
# Shared Memory Support
# ============================================================================

"""
    Check if shared memory is available
"""
function is_shm_available()::Bool
    return isfile(SHM_PATH)
end

"""
    Create shared memory region if it doesn't exist
"""
function create_shm_region()::Bool
    try
        # Check if already exists
        if isfile(SHM_PATH)
            # Verify size
            current_size = filesize(SHM_PATH)
            if current_size == SHM_SIZE
                println("[IPC] Shared memory already exists with correct size: $SHM_PATH ($SHM_SIZE bytes)")
                return true
            elseif current_size > 0
                println("[IPC] Shared memory exists with wrong size: $current_size (expected: $SHM_SIZE)")
                # Try to resize
                try
                    rm(SHM_PATH)
                catch e
                    println("[IPC] Warning: Could not remove existing SHM: $e")
                    return false
                end
            end
        end
        
        # Create new shared memory region
        open(SHM_PATH, "w+") do f
            # Ensure proper size
            truncate(f, SHM_SIZE)
        end
        
        # Set secure permissions (owner only)
        chmod(SHM_PATH, 0o600)
        
        println("[IPC] Created shared memory region: $SHM_PATH ($SHM_SIZE bytes)")
        return true
    catch e
        println("[IPC] Failed to create shared memory: $e")
        return false
    end
end

"""
    Connect to shared memory region
"""
function connect_shm(channel::IPCChannel)::Bool
    lock(channel.lock) do
        try
            # Check if shared memory exists
            if !isfile(SHM_PATH)
                println("[IPC] Shared memory not found: $SHM_PATH")
                return false
            end
            
            # Open shared memory
            shm_fd = open(SHM_PATH, "r+")
            
            # Memory-map the region
            shm_data = Mmap.mmap(shm_fd, Vector{UInt8}, SHM_SIZE)
            
            # Verify magic number
            magic = reinterpret(UInt32, shm_data[1:4])[1]
            if magic != IPC_MAGIC
                println("[IPC] Warning: Invalid magic in shared memory: 0x$(string(magic, base=16))")
            end
            
            channel.shm_fd = shm_fd
            channel.shm_data = shm_data
            channel.mode = :shm
            
            # Initialize atomic indices
            channel.producer_idx[] = 0
            channel.consumer_idx[] = 0
            
            println("[IPC] Connected to Rust brain via shared memory: $SHM_PATH")
            return true
        catch e
            println("[IPC] Failed to connect to shared memory: $e")
            return false
        end
    end
end

"""
    Disconnect from shared memory
"""
function disconnect_shm(channel::IPCChannel)::Nothing
    lock(channel.lock) do
        if channel.shm_data !== nothing
            try
                # Sync and unmap
                Mmap.sync!(channel.shm_data)
                channel.shm_data = nothing
            catch e
                println("[IPC] Warning: Error unmapping shared memory: $e")
            end
        end
        
        if channel.shm_fd >= 0
            try
                close(channel.shm_fd)
                channel.shm_fd = -1
            catch e
                println("[IPC] Warning: Error closing shared memory: $e")
            end
        end
        
        channel.mode = :tcp
        println("[IPC] Disconnected from shared memory")
    end
    nothing
end

"""
    Write to shared memory ring buffer (lock-free)
"""
function shm_write(channel::IPCChannel, data::Vector{UInt8})::Bool
    if channel.mode != :shm || channel.shm_data === nothing
        return false
    end
    
    try
        # Get next write position (atomic)
        prod_idx = channel.producer_idx[]
        cons_idx = channel.consumer_idx[]
        
        # Check if ring buffer is full
        if (prod_idx - cons_idx) >= SHM_ENTRIES
            println("[IPC] Ring buffer full!")
            return false
        end
        
        # Calculate offset for this entry
        entry_offset = MESSAGE_DATA_OFFSET + (prod_idx % SHM_ENTRIES) * SHM_ENTRY_SIZE
        
        # Write data to ring buffer
        data_len = min(length(data), SHM_ENTRY_SIZE)
        channel.shm_data[entry_offset+1:entry_offset+data_len] = data[1:data_len]
        
        # Atomic increment of producer index
        channel.producer_idx[] = prod_idx + 1
        
        return true
    catch e
        println("[IPC] Error writing to shared memory: $e")
        return false
    end
end

"""
    Read from shared memory ring buffer (lock-free)
"""
function shm_read(channel::IPCChannel)::Union{Vector{UInt8}, Nothing}
    if channel.mode != :shm || channel.shm_data === nothing
        return nothing
    end
    
    try
        prod_idx = channel.producer_idx[]
        cons_idx = channel.consumer_idx[]
        
        # Check if there's data to read
        if prod_idx == cons_idx
            return nothing
        end
        
        # Calculate offset for this entry
        entry_offset = MESSAGE_DATA_OFFSET + (cons_idx % SHM_ENTRIES) * SHM_ENTRY_SIZE
        
        # Read data from ring buffer
        data = Vector{UInt8}(channel.shm_data[entry_offset+1:end])
        
        # Find the actual data length (first non-zero after offset)
        data_len = 0
        for i in 1:min(SHM_ENTRY_SIZE, length(data))
            if data[i] != 0
                data_len = i
            end
        end
        
        if data_len == 0
            return nothing
        end
        
        result = data[1:data_len]
        
        # Atomic increment of consumer index
        channel.consumer_idx[] = cons_idx + 1
        
        return result
    catch e
        println("[IPC] Error reading from shared memory: $e")
        return nothing
    end
end

# ============================================================================
# Connection Management
# ============================================================================

"""
    Connect to the Rust brain
    
    Attempts to connect via shared memory first, falls back to TCP.
    
    Arguments:
    - channel::IPCChannel - The IPC channel to use
    - host::String - Host to connect to (default: 127.0.0.1)
    - port::Int - Port to connect to (default: 5555)
    - prefer_shm::Bool - Whether to prefer shared memory (default: true)
    
    Returns: true if connected, false otherwise
"""
function connect(channel::IPCChannel; host::String=DEFAULT_IPC_HOST, port::Int=DEFAULT_IPC_PORT, prefer_shm::Bool=true)::Bool
    lock(channel.lock) do
        if channel.state == CONNECTED
            return true
        end
        
        channel.state = CONNECTING
        
        # Try shared memory first (preferred for 1.97M thoughts/sec throughput)
        if prefer_shm
            println("[IPC] Attempting shared memory connection...")
            if connect_shm(channel)
                channel.state = CONNECTED
                channel.reconnect_attempts = 0
                channel.safe_mode = false
                println("[IPC] ✓ Connected via shared memory (64MB ring buffer)")
                return true
            end
            println("[IPC] Shared memory unavailable, falling back to TCP...")
        end
        
        # Fall back to TCP
        try
            sock = Sockets.connect(host, port)
            channel.socket = sock
            channel.state = CONNECTED
            channel.reconnect_attempts = 0
            channel.safe_mode = false
            channel.mode = :tcp
            
            println("[IPC] Connected to Rust brain at $host:$port (TCP fallback)")
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
        # Disconnect based on current mode
        if channel.mode == :shm
            disconnect_shm(channel)
        end
        
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
    Get the current connection mode
"""
function get_connection_mode(channel::IPCChannel)::Symbol
    return channel.mode
end

"""
    Check if connected via shared memory (native mode)
"""
function is_shm_mode(channel::IPCChannel)::Bool
    return channel.mode == :shm
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
        # Build the message
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
        data_bytes = Vector{UInt8}(data)
        
        # Send via appropriate channel
        if channel.mode == :shm
            # Use shared memory ring buffer
            return shm_write(channel, data_bytes)
        else
            # Use TCP socket
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
        # Try shared memory first if in SHM mode
        if channel.mode == :shm
            data = shm_read(channel)
            if data !== nothing
                # Parse the data
                try
                    msg = JSON3.read(IOBuffer(data), Dict{String, Any})
                    
                    if get(msg, "msg_type", 0) == MSG_TYPE_VERDICT
                        payload = msg["payload"]
                        return Verdict(
                            payload["proposal_id"],
                            payload["approved"],
                            payload["reward"],
                            get(payload, "reason", nothing)
                        )
                    elseif get(msg, "msg_type", 0) == MSG_TYPE_HEARTBEAT
                        channel.last_heartbeat = DateTime(now())
                    end
                catch e
                    println("[IPC] Error parsing SHM message: $e")
                end
                return nothing
            end
            return nothing
        end
        
        # TCP fallback
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
