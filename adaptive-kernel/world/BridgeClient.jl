module BridgeClient

using Sockets
using JSON3
using Dates
using Base64

# Import Ed25519 for command signing
# Try to import from local security module, fallback to external
const ED25519_AVAILABLE = try
    include(joinpath(dirname(@__FILE__), "..", "security", "Ed25519.jl"))
    using ..Ed25519Security
    true
catch e
    @warn "Ed25519 module not available: $e"
    false
end

export HCBClient, connect!, send_heartbeat!, send_authorized_execute!, send_kill!,
       set_signing_key!, is_signed_mode, disconnect!

# ============================================================================
# HCB Protocol Constants
# ============================================================================
const SOCKET_PATH = "/tmp/itheris_kernel.sock"
const PROTOCOL_VERSION = "1.0.0"
const HEARTBEAT_INTERVAL_MS = 100  # Send heartbeats every 100ms (well within 200ms timeout)

# ============================================================================
# HCB Client
# ============================================================================
mutable struct HCBClient
    socket::Union{Nothing, Sockets.TCPSocket}  # Unix socket connection
    connected::Bool
    current_challenge::UInt64
    julia_pid::Int32
    last_heartbeat_sent::Int64
    heartbeat_task::Union{Nothing, Task}
    # Ed25519 signing support
    signing_enabled::Bool
    keypair_public::Union{Nothing, Vector{UInt8}}
    keypair_secret::Union{Nothing, Vector{UInt8}}
    
    function HCBClient()
        new(nothing, false, UInt64(0), Int32(getpid()), Int64(0), nothing, false, nothing, nothing)
    end
end

"""
    set_signing_key!(client::HCBClient, public_key::Vector{UInt8}, secret_key::Vector{UInt8})

Configure Ed25519 keys for command signing. This enables the signed command pipeline.
"""
function set_signing_key!(client::HCBClient, public_key::Vector{UInt8}, secret_key::Vector{UInt8})
    client.signing_enabled = true
    client.keypair_public = public_key
    client.keypair_secret = secret_key
    @info "Ed25519 signing enabled for HCBClient"
end

"""
    is_signed_mode(client::HCBClient) -> Bool

Check if the client is configured for signed command mode.
"""
function is_signed_mode(client::HCBClient)::Bool
    return client.signing_enabled
end

# ============================================================================
# Connection & Handshake
# ============================================================================

"""
    connect!(client::HCBClient, socket_path::String=SOCKET_PATH)

Connect to the Rust shell and perform the HCB protocol handshake.
"""
function connect!(client::HCBClient, socket_path::String=SOCKET_PATH)
    try
        # Connect to Unix domain socket
        client.socket = Sockets.connect(socket_path)
        
        # Send handshake
        handshake = Dict(
            "Handshake" => Dict(
                "julia_pid" => client.julia_pid,
                "protocol_version" => PROTOCOL_VERSION
            )
        )
        send_message!(client, handshake)
        
        # Wait for HandshakeAck
        response = receive_message!(client)
        if haskey(response, "HandshakeAck")
            ack = response["HandshakeAck"]
            if ack["accepted"]
                client.connected = true
                client.current_challenge = UInt64(ack["initial_challenge"])
                @info "HCB Protocol: Handshake accepted. Shell version: $(ack["shell_version"])"
                
                # Start heartbeat background task
                start_heartbeat!(client)
                return true
            else
                @error "HCB Protocol: Handshake rejected by Rust shell"
                return false
            end
        else
            @error "HCB Protocol: Unexpected handshake response: $response"
            return false
        end
    catch e
        @error "HCB Protocol: Connection failed" exception=(e, catch_backtrace())
        return false
    end
end

# ============================================================================
# Heartbeat System (CRITICAL - must beat every <200ms)
# ============================================================================

"""
    start_heartbeat!(client::HCBClient)

Start the background heartbeat task. Sends heartbeats every 100ms.
The Rust watchdog will SIGKILL us if we miss the 200ms deadline.
"""
function start_heartbeat!(client::HCBClient)
    client.heartbeat_task = @async begin
        while client.connected
            try
                send_heartbeat!(client)
                sleep(HEARTBEAT_INTERVAL_MS / 1000.0)  # 100ms
            catch e
                if client.connected
                    @error "HCB Protocol: Heartbeat failed" exception=(e, catch_backtrace())
                end
                break
            end
        end
    end
end

"""
    send_heartbeat!(client::HCBClient)

Send a heartbeat with the current challenge response.
"""
function send_heartbeat!(client::HCBClient)
    if !client.connected || client.socket === nothing
        return
    end
    
    now_ms = Int64(round(datetime2unix(now(UTC)) * 1000))
    
    heartbeat = Dict(
        "Heartbeat" => Dict(
            "challenge" => client.current_challenge,
            "julia_pid" => client.julia_pid,
            "timestamp" => now_ms
        )
    )
    
    send_message!(client, heartbeat)
    client.last_heartbeat_sent = now_ms
    
    # Try to read HeartbeatAck (non-blocking)
    try
        if bytesavailable(client.socket) > 0
            response = receive_message!(client)
            if haskey(response, "HeartbeatAck")
                client.current_challenge = UInt64(response["HeartbeatAck"]["new_challenge"])
            end
        end
    catch e
        # Non-fatal: we'll get the new challenge on next heartbeat
    end
end

# ============================================================================
# Authorized Command Execution
# ============================================================================

"""
    send_authorized_execute!(client::HCBClient, action_json::Vector{UInt8}, 
                              signature::Vector{UInt8}, public_key::Vector{UInt8},
                              nonce::UInt64)

Send a cryptographically signed command to the Rust shell for execution.

IMPORTANT: Julia does NOT generate signatures. The signature and public_key
must come from the user's hardware key via the itheris_link app.
Julia is merely a PASSTHROUGH for these cryptographic blobs.

For internal signing, use send_signed_execute!() instead.
"""
function send_authorized_execute!(client::HCBClient, 
                                   action_json::Vector{UInt8},
                                   signature::Vector{UInt8}, 
                                   public_key::Vector{UInt8},
                                   nonce::UInt64)
    if !client.connected
        error("HCB Protocol: Not connected to Rust shell")
    end
    
    # Base64 encode the binary blobs for JSON transport
    sig_b64 = base64encode(signature)
    pk_b64 = base64encode(public_key)
    now_ms = Int64(round(datetime2unix(now(UTC)) * 1000))
    
    msg = Dict(
        "AuthorizedExecute" => Dict(
            "authorized_command" => Dict(
                "command_payload" => collect(action_json),  # Vec<u8> as JSON array
                "signature" => sig_b64,
                "public_key" => pk_b64,
                "nonce" => nonce,
                "timestamp" => now_ms
            )
        )
    )
    
    send_message!(client, msg)
    
    # Wait for response (ActionResult or SecurityViolationReport)
    response = receive_message!(client)
    return response
end

# ============================================================================
# Signed Command Execution (Internal Ed25519)
# ============================================================================

"""
    send_signed_execute!(client::HCBClient, action::Dict)

Send a cryptographically signed command using internal Ed25519 keys.

This function signs the command using the keys configured via set_signing_key!().
It creates a unique nonce and timestamp for replay protection.

# Arguments
- `client`: The HCBClient with signing keys configured
- `action`: The action dictionary to sign and execute

# Returns
- Response from the Rust shell
"""
function send_signed_execute!(client::HCBClient, action::Dict)
    if !client.connected
        error("HCB Protocol: Not connected to Rust shell")
    end
    
    if !client.signing_enabled
        error("HCB Protocol: Signing not enabled. Call set_signing_key!() first.")
    end
    
    # Convert action to JSON bytes
    action_json = Vector{UInt8}(JSON3.write(action))
    
    # Generate nonce and timestamp for replay/freshness protection
    nonce = UInt64(round(datetime2unix(now(UTC)) * 1_000_000)) % UInt64(10^10)
    timestamp = Int64(round(datetime2unix(now(UTC)) * 1000))
    
    # Create message to sign: payload || nonce || timestamp
    # This binds the nonce and timestamp to the signature
    msg_to_sign = vcat(
        action_json,
        reinterpret(UInt8, [nonce]),
        reinterpret(UInt8, [timestamp])
    )
    
    # Sign using internal Ed25519 (if available)
    if ED25519_AVAILABLE
        signature = Ed25519Security.sign_command(client.keypair_secret, msg_to_sign)
    else
        # Fallback: use passthrough mode (external signature)
        error("Ed25519 signing not available. Use send_authorized_execute!() with external signature.")
    end
    
    # Build the authorized command
    msg = Dict(
        "AuthorizedExecute" => Dict(
            "authorized_command" => Dict(
                "command_payload" => collect(action_json),
                "signature" => base64encode(signature),
                "public_key" => base64encode(client.keypair_public),
                "nonce" => nonce,
                "timestamp" => timestamp
            )
        )
    )
    
    send_message!(client, msg)
    
    # Wait for response
    response = receive_message!(client)
    return response
end

# ============================================================================
# Kill Kernel (Hard Kill)
# ============================================================================

"""
    send_kill!(client::HCBClient, reason::String)

Send a KillKernel message to the Rust shell to hard-kill the Julia kernel.

# Arguments
- `client`: The HCBClient connection
- `reason`: String explaining why the kernel is being killed

# Returns
- Response from the Rust shell

# Notes
This is a hard kill - it will immediately terminate the Julia kernel process.
Use with caution.
"""
function send_kill!(client::HCBClient, reason::String)
    if !client.connected
        error("HCB Protocol: Not connected to Rust shell")
    end
    
    now_ms = Int64(round(datetime2unix(now(UTC)) * 1000))
    
    msg = Dict(
        "KillKernel" => Dict(
            "reason" => reason
        )
    )
    
    send_message!(client, msg)
    
    # Wait for response
    response = receive_message!(client)
    return response
end

# ============================================================================
# Low-level IPC
# ============================================================================

function send_message!(client::HCBClient, msg::Dict)
    json_str = JSON3.write(msg)
    write(client.socket, json_str * "\n")
    flush(client.socket)
end

function receive_message!(client::HCBClient)
    line = readline(client.socket)
    return JSON3.read(line, Dict)
end

# ============================================================================
# Disconnect
# ============================================================================

function disconnect!(client::HCBClient)
    client.connected = false
    if client.socket !== nothing
        try
            close(client.socket)
        catch end
    end
    client.socket = nothing
    @info "HCB Protocol: Disconnected from Rust shell"
end

end # module BridgeClient
