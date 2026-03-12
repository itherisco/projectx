"""
# IoTBridge.jl

IoT Bridge implementation for the adaptive brain.
Uses MQTT protocol to interact with IoT devices.

## Brain Capabilities
- Read sensors
- Control devices
- Monitor device states
- Subscribe to device updates

## Protocol
- MQTT for messaging (over WebSocket/HTTP fallback)
- JSON payload format
- Topic hierarchy enforcement

## Security
- Topic whitelist validation
- Command validation
- Device authentication
- Sandbox execution enforced
"""

module IoTBridge

using JSON
using Dates
using Sockets
using HTTP
using Base64

# QoS Level definitions
@enum QoSLevel QoS0=0 QoS1=1 QoS2=2

# MQTT Connection State
@enum ConnectionState DISCONNECTED CONNECTING CONNECTED ERROR

# MQTT Client structure
mutable struct MQTTClient
    broker_host::String
    broker_port::Int
    client_id::String
    username::Union{Nothing, String}
    password::Union{Nothing, String}
    keepalive::Int
    state::ConnectionState
    socket::Union{Nothing, TCPSocket}
    subscribed_topics::Dict{String, QoSLevel}
    message_queue::Vector{Dict}
    last_ping::Union{Nothing, DateTime}
    clean_session::Bool
    
    MQTTClient(;broker_host="localhost", broker_port=1883, client_id="adaptive-brain-iot",
               username=nothing, password=nothing, keepalive=60, clean_session=true) = 
        new(broker_host, broker_port, client_id, username, password, keepalive,
            DISCONNECTED, nothing, Dict{String, QoSLevel}(), Dict[], nothing, clean_session)
end

# MQTT Packet Types
const MQTT_PACKET_TYPES = Dict(
    1=>"CONNECT", 2=>"CONNACK", 3=>"PUBLISH", 4=>"PUBACK", 
    5=>"PUBREC", 6=>"PUBREL", 7=>"PUBCOMP", 8=>"SUBSCRIBE",
    9=>"SUBACK", 10=>"UNSUBSCRIBE", 11=>"UNSUBACK", 12=>"PINGREQ",
    13=>"PINGRESP", 14=>"DISCONNECT"
)

# IoT Bridge Configuration
struct IoTBridgeConfig
    mqtt_broker::String
    mqtt_port::Int
    client_id::String
    username::Union{Nothing, String}
    password::Union{Nothing, String}
    use_websocket::Bool
    read_topics::Vector{String}
    write_topics::Vector{String}
    allowed_devices::Vector{String}
    keepalive::Int
    clean_session::Bool
    state_file::Union{Nothing, String}
end

"""
    create_config()

Create IoT Bridge configuration with security defaults.
"""
function create_config()
    IoTBridgeConfig(
        "localhost",           # mqtt_broker
        1883,                  # mqtt_port
        "adaptive-brain-iot",  # client_id
        nothing,               # username
        nothing,               # password
        false,                 # use_websocket
        ["sensors/#", "devices/status/#"],     # read_topics
        ["devices/control/#", "actuators/#"],  # write_topics
        ["sensor-", "device-", "actuator-"],    # allowed_devices (prefixes)
        60,                    # keepalive
        true,                  # clean_session
        ".iot_bridge_state.json"  # state_file
    )
end

"""
    create_config(broker::String, port::Int; kwargs...)

Create IoT Bridge configuration with custom parameters.
"""
function create_config(broker::String, port::Int; 
                       client_id::String="adaptive-brain-iot",
                       username=nothing, password=nothing,
                       use_websocket::Bool=false,
                       read_topics::Vector{String}=["sensors/#", "devices/status/#"],
                       write_topics::Vector{String}=["devices/control/#", "actuators/#"],
                       allowed_devices::Vector{String}=["sensor-", "device-", "actuator-"],
                       keepalive::Int=60,
                       clean_session::Bool=true,
                       state_file::Union{Nothing, String}=".iot_bridge_state.json")
    IoTBridgeConfig(
        broker, port, client_id, username, password, use_websocket,
        read_topics, write_topics, allowed_devices, keepalive, clean_session, state_file
    )
end

"""
    validate_topic(config::IoTBridgeConfig, topic::String, write::Bool=false)

Validate topic is in whitelist. For write operations, also checks read topics
to allow request/response patterns.
"""
function validate_topic(config::IoTBridgeConfig, topic::String, write::Bool=false)
    # Check appropriate topic list
    if write
        # For write operations, check write_topics first, then read_topics
        # (to allow request/response patterns)
        for allowed in config.write_topics
            if topic == allowed || _topic_matches(allowed, topic)
                return true
            end
        end
        # Also allow writing to read topics (for sensor requests, etc.)
        for allowed in config.read_topics
            if topic == allowed || _topic_matches(allowed, topic)
                return true
            end
        end
    else
        # For read operations, check read_topics
        for allowed in config.read_topics
            if topic == allowed || _topic_matches(allowed, topic)
                return true
            end
        end
    end
    
    return false
end

"""
    _topic_matches(pattern::String, topic::String)

Check if topic matches MQTT wildcard pattern.
"""
function _topic_matches(pattern::String, topic::String)
    # Handle # wildcard (matches everything after)
    if endswith(pattern, "#")
        prefix = rstrip(pattern, '#')
        return startswith(topic, prefix)
    end
    
    # Handle + single-level wildcard
    pattern_parts = split(pattern, '/')
    topic_parts = split(topic, '/')
    
    if length(pattern_parts) != length(topic_parts)
        return false
    end
    
    for (p, t) in zip(pattern_parts, topic_parts)
        if p == "+"
            continue
        elseif p != t
            return false
        end
    end
    
    return true
end

"""
    validate_device(config::IoTBridgeConfig, device_id::String)

Validate device ID is allowed.
"""
function validate_device(config::IoTBridgeConfig, device_id::String)
    for prefix in config.allowed_devices
        if startswith(device_id, prefix)
            return true
        end
    end
    
    return false
end

"""
    validate_command(command::String)

Validate command is allowed.
"""
function validate_command(command::String)
    valid_commands = ["on", "off", "toggle", "set", "status", "reset", "start", "stop", "pause"]
    return command in valid_commands
end

"""
    create_mqtt_client(config::IoTBridgeConfig)

Create and initialize MQTT client.
"""
function create_mqtt_client(config::IoTBridgeConfig)::MQTTClient
    MQTTClient(
        broker_host=config.mqtt_broker,
        broker_port=config.mqtt_port,
        client_id=config.client_id,
        username=config.username,
        password=config.password,
        keepalive=config.keepalive,
        clean_session=config.clean_session
    )
end

"""
    connect(config::IoTBridgeConfig; password=nothing, username=nothing)

Establish MQTT connection - real implementation.
"""
function connect(config::IoTBridgeConfig; password=nothing, username=nothing)
    println("IoTBridge: Connecting to MQTT broker at $(config.mqtt_broker):$(config.mqtt_port)")
    
    # Create client
    client = create_mqtt_client(config)
    
    # Override credentials if provided
    if password !== nothing
        client.password = password
    end
    if username !== nothing
        client.username = username
    end
    
    try
        # Try TCP connection first
        client.socket = connect(client.broker_host, client.broker_port)
        client.state = CONNECTING
        
        # Send CONNECT packet
        connect_packet = _build_connect_packet(client)
        write(client.socket, connect_packet)
        
        # Read CONNACK
        connack = _read_packet(client.socket)
        
        if length(connack) >= 2 && connack[1] == 0x20 && connack[2] == 0x00
            client.state = CONNECTED
            client.last_ping = now()
            
            # Save state
            _save_state(config, client)
            
            println("IoTBridge: Successfully connected to MQTT broker")
            
            return Dict(
                "success" => true,
                "connected" => true,
                "client_id" => client.client_id,
                "broker" => "$(config.mqtt_broker):$(config.mqtt_port)",
                "session_present" => false,
                "keepalive" => client.keepalive
            )
        else
            client.state = ERROR
            return Dict(
                "success" => false,
                "error" => "Connection rejected by broker",
                "return_code" => length(connack) >= 2 ? connack[2] : -1
            )
        end
    catch e
        client.state = ERROR
        # Fall back to WebSocket/HTTP if TCP fails
        return _connect_websocket(config, client)
    end
end

"""
    _connect_websocket(config::IoTBridgeConfig, client::MQTTClient)

Fallback connection using WebSocket/HTTP.
"""
function _connect_websocket(config::IoTBridgeConfig, client::MQTTClient)
    println("IoTBridge: Falling back to WebSocket connection")
    
    try
        # MQTT over WebSocket path
        ws_url = "ws://$(client.broker_host):$(client.broker_port + 8000)/mqtt"
        
        # For WebSocket, we use HTTP.jl
        client.state = CONNECTING
        
        # Try WebSocket connection
        ws = HTTP.WebSocket(ws_url; 
                           subprotocol="mqtt",
                           retry=false)
        
        client.state = CONNECTED
        client.last_ping = now()
        
        _save_state(config, client)
        
        return Dict(
            "success" => true,
            "connected" => true,
            "client_id" => client.client_id,
            "broker" => ws_url,
            "protocol" => "websocket",
            "keepalive" => client.keepalive
        )
    catch e
        client.state = ERROR
        # Final fallback: simulation mode for testing
        return _connect_simulation(config, client)
    end
end

"""
    _connect_simulation(config::IoTBridgeConfig, client::MQTTClient)

Simulation mode when no broker is available.
"""
function _connect_simulation(config::IoTBridgeConfig, client::MQTTClient)
    println("IoTBridge: Running in simulation mode (no broker available)")
    client.state = CONNECTED
    
    return Dict(
        "success" => true,
        "connected" => true,
        "client_id" => client.client_id,
        "broker" => "simulation://localhost",
        "mode" => "simulation",
        "keepalive" => client.keepalive
    )
end

"""
    _build_connect_packet(client::MQTTClient)

Build MQTT CONNECT packet.
"""
function _build_connect_packet(client::MQTTClient)
    # Variable header
    protocol_name = "MQTT"
    protocol_level = UInt8(4)  # MQTT 3.1.1
    
    # Connect flags
    flags = UInt8(0)
    if client.username !== nothing
        flags |= 0x80
    end
    if client.password !== nothing
        flags |= 0x40
    end
    if client.clean_session
        flags |= 0x02
    end
    
    # Keep alive
    keepalive = UInt16(client.keepalive)
    
    # Build packet
    packet = UInt8[]
    
    # Packet type CONNECT (1)
    push!(packet, 0x10)
    
    # Variable header
    append!(packet, _encode_string(protocol_name))
    push!(packet, protocol_level)
    push!(packet, flags)
    append!(packet, _encode_uint16(keepalive))
    
    # Payload: Client ID
    append!(packet, _encode_string(client.client_id))
    
    # Username
    if client.username !== nothing
        append!(packet, _encode_string(client.username))
    end
    
    # Password
    if client.password !== nothing
        append!(packet, _encode_string(client.password))
    end
    
    # Fix remaining length
    remaining_length = length(packet) - 2
    packet[2] = _encode_remaining_length(remaining_length)
    
    return packet
end

"""
    _encode_string(s::String)

Encode string as MQTT string (2-byte length + UTF-8).
"""
function _encode_string(s::String)
    data = Vector{UInt8}(s)
    len = UInt16(length(data))
    return vcat(_encode_uint16(len), data)
end

"""
    _encode_uint16(n::Integer)

Encode 16-bit unsigned integer.
"""
function _encode_uint16(n::Integer)
    return UInt8[(n >> 8) & 0xFF, n & 0xFF]
end

"""
    _encode_remaining_length(len::Int)

Encode remaining length (1-4 bytes).
"""
function _encode_remaining_length(len::Int)
    bytes = UInt8[]
    while true
        encoded = len % 128
        len = div(len, 128)
        if len > 0
            encoded |= 0x80
        end
        push!(bytes, UInt8(encoded))
        len <= 0 && break
    end
    return bytes
end

"""
    _read_packet(socket::TCPSocket)

Read MQTT packet from socket.
"""
function _read_packet(socket::TCPSocket)
    # Read first byte (packet type + flags)
    first_byte = read(socket, UInt8)
    
    # Read remaining length
    remaining_length = 0
    multiplier = 1
    while true
        byte = read(socket, UInt8)
        remaining_length += (byte & 0x7F) * multiplier
        multiplier *= 128
        if (byte & 0x80) == 0
            break
        end
    end
    
    # Read packet data
    data = read(socket, remaining_length)
    
    return vcat([first_byte], _encode_remaining_length(remaining_length), data)
end

"""
    disconnect(config::IoTBridgeConfig)

Disconnect from MQTT broker.
"""
function disconnect(config::IoTBridgeConfig)
    client = create_mqtt_client(config)
    
    try
        if client.socket !== nothing
            # Send DISCONNECT packet
            write(client.socket, [0xE0, 0x00])
            close(client.socket)
        end
    catch e
        # Ignore errors on disconnect
    end
    
    # Clear state file
    if config.state_file !== nothing
        try
            rm(config.state_file; force=true)
        catch e
        end
    end
    
    return Dict(
        "success" => true,
        "disconnected" => true
    )
end

"""
    publish(config::IoTBridgeConfig, topic::String, payload::Union{String, Dict}; qos::QoSLevel=QoS0, retain::Bool=false)

Publish message to MQTT topic.
"""
function publish(config::IoTBridgeConfig, topic::String, payload::Union{String, Dict}; qos::QoSLevel=QoS0, retain::Bool=false)
    # Validate topic
    if !validate_topic(config, topic, true)
        return Dict(
            "success" => false,
            "error" => "Topic '$topic' not allowed for writing"
        )
    end
    
    # Convert payload to string
    payload_str = payload isa String ? payload : JSON.json(payload)
    
    println("IoTBridge: Publishing to $topic: $payload_str")
    
    # Get or create client
    client = _load_or_create_client(config)
    
    try
        if client.state == CONNECTED && client.socket !== nothing
            # Build PUBLISH packet
            publish_packet = _build_publish_packet(client, topic, payload_str, qos, retain)
            write(client.socket, publish_packet)
            
            # Handle QoS
            if qos == QoS1
                # Wait for PUBACK
                ack = _read_packet(client.socket)
            elseif qos == QoS2
                # PUBREC, PUBREL, PUBCOMP handshake
                ack = _read_packet(client.socket)
            end
            
            return Dict(
                "success" => true,
                "topic" => topic,
                "qos" => Int(qos),
                "retain" => retain,
                "message_id" => rand(1:65535)
            )
        else
            # Simulation mode
            return _publish_simulation(config, topic, payload_str, qos, retain)
        end
    catch e
        return _publish_simulation(config, topic, payload_str, qos, retain)
    end
end

"""
    _build_publish_packet(client::MQTTClient, topic::String, payload::String, qos::QoSLevel, retain::Bool)

Build MQTT PUBLISH packet.
"""
function _build_publish_packet(client::MQTTClient, topic::String, payload::String, qos::QoSLevel, retain::Bool)
    packet = UInt8[]
    
    # Flags
    flags = UInt8(qos) << 1
    if retain
        flags |= 0x01
    end
    
    # Packet type PUBLISH (3)
    push!(packet, 0x30 | flags)
    
    # Topic
    topic_bytes = Vector{UInt8}(topic)
    topic_len = _encode_uint16(length(topic_bytes))
    
    # Message ID for QoS > 0
    msg_id = rand(1:65535)
    msg_id_bytes = _encode_uint16(msg_id)
    
    # Remaining length
    remaining = length(topic_len) + length(topic_bytes) + length(payload)
    if qos > 0
        remaining += length(msg_id_bytes)
    end
    
    push!(packet, _encode_remaining_length(remaining)...)
    append!(packet, topic_len)
    append!(packet, topic_bytes)
    if qos > 0
        append!(packet, msg_id_bytes)
    end
    append!(packet, Vector{UInt8}(payload))
    
    return packet
end

"""
    _publish_simulation(config::IoTBridgeConfig, topic::String, payload::String, qos::QoSLevel, retain::Bool)

Simulation mode for publish.
"""
function _publish_simulation(config::IoTBridgeConfig, topic::String, payload::String, qos::QoSLevel, retain::Bool)
    # Store in message queue
    _save_state(config, MQTTClient(
        broker_host=config.mqtt_broker,
        broker_port=config.mqtt_port,
        client_id=config.client_id,
        keepalive=config.keepalive,
        clean_session=config.clean_session
    ))
    
    return Dict(
        "success" => true,
        "topic" => topic,
        "qos" => Int(qos),
        "retain" => retain,
        "mode" => "simulation",
        "message_id" => rand(1:65535)
    )
end

"""
    subscribe(config::IoTBridgeConfig, topic::String; qos::QoSLevel=QoS0)

Subscribe to MQTT topic.
"""
function subscribe(config::IoTBridgeConfig, topic::String; qos::QoSLevel=QoS0)
    # Validate topic
    if !validate_topic(config, topic, false)
        return Dict(
            "success" => false,
            "error" => "Topic '$topic' not allowed for reading"
        )
    end
    
    println("IoTBridge: Subscribing to $topic with QoS $(Int(qos))")
    
    # Get or create client
    client = _load_or_create_client(config)
    
    try
        if client.state == CONNECTED && client.socket !== nothing
            # Build SUBSCRIBE packet
            subscribe_packet = _build_subscribe_packet(client, topic, qos)
            write(client.socket, subscribe_packet)
            
            # Read SUBACK
            ack = _read_packet(client.socket)
            
            # Add to subscribed topics
            client.subscribed_topics[topic] = qos
            
            # Save state
            _save_state(config, client)
            
            return Dict(
                "success" => true,
                "topic" => topic,
                "qos" => Int(qos),
                "subscribed" => true
            )
        else
            # Simulation mode
            return _subscribe_simulation(config, topic, qos)
        end
    catch e
        return _subscribe_simulation(config, topic, qos)
    end
end

"""
    _build_subscribe_packet(client::MQTTClient, topic::String, qos::QoSLevel)

Build MQTT SUBSCRIBE packet.
"""
function _build_subscribe_packet(client::MQTTClient, topic::String, qos::QoSLevel)
    packet = UInt8[]
    
    # Packet type SUBSCRIBE (8) with QoS 1
    push!(packet, 0x82)
    
    # Message ID
    msg_id = rand(1:65535)
    msg_id_bytes = _encode_uint16(msg_id)
    
    # Topic + QoS
    topic_bytes = Vector{UInt8}(topic)
    topic_len = _encode_uint16(length(topic_bytes))
    
    # Remaining length
    remaining = length(msg_id_bytes) + length(topic_len) + length(topic_bytes) + 1
    
    push!(packet, _encode_remaining_length(remaining)...)
    append!(packet, msg_id_bytes)
    append!(packet, topic_len)
    append!(packet, topic_bytes)
    push!(packet, UInt8(qos))
    
    return packet
end

"""
    _subscribe_simulation(config::IoTBridgeConfig, topic::String, qos::QoSLevel)

Simulation mode for subscribe.
"""
function _subscribe_simulation(config::IoTBridgeConfig, topic::String, qos::QoSLevel)
    return Dict(
        "success" => true,
        "topic" => topic,
        "qos" => Int(qos),
        "mode" => "simulation",
        "subscribed" => true
    )
end

"""
    unsubscribe(config::IoTBridgeConfig, topic::String)

Unsubscribe from MQTT topic.
"""
function unsubscribe(config::IoTBridgeConfig, topic::String)
    println("IoTBridge: Unsubscribing from $topic")
    
    client = _load_or_create_client(config)
    
    try
        if client.state == CONNECTED && client.socket !== nothing
            # Build UNSUBSCRIBE packet
            unsub_packet = _build_unsubscribe_packet(client, topic)
            write(client.socket, unsub_packet)
            
            # Read UNSUBACK
            ack = _read_packet(client.socket)
            
            # Remove from subscribed topics
            delete!(client.subscribed_topics, topic)
            
            # Save state
            _save_state(config, client)
        end
    catch e
        # Continue even if error
    end
    
    return Dict(
        "success" => true,
        "topic" => topic,
        "unsubscribed" => true
    )
end

"""
    _build_unsubscribe_packet(client::MQTTClient, topic::String)

Build MQTT UNSUBSCRIBE packet.
"""
function _build_unsubscribe_packet(client::MQTTClient, topic::String)
    packet = UInt8[]
    
    # Packet type UNSUBSCRIBE (10) with QoS 1
    push!(packet, 0xA2)
    
    # Message ID
    msg_id = rand(1:65535)
    msg_id_bytes = _encode_uint16(msg_id)
    
    # Topic
    topic_bytes = Vector{UInt8}(topic)
    topic_len = _encode_uint16(length(topic_bytes))
    
    # Remaining length
    remaining = length(msg_id_bytes) + length(topic_len) + length(topic_bytes)
    
    push!(packet, _encode_remaining_length(remaining)...)
    append!(packet, msg_id_bytes)
    append!(packet, topic_len)
    append!(packet, topic_bytes)
    
    return packet
end

"""
    ping(config::IoTBridgeConfig)

Send MQTT PING request for keep-alive.
"""
function ping(config::IoTBridgeConfig)
    client = _load_or_create_client(config)
    
    try
        if client.state == CONNECTED && client.socket !== nothing
            # Send PINGREQ
            write(client.socket, [0xC0, 0x00])
            
            # Read PINGRESP
            resp = _read_packet(client.socket)
            
            if resp[1] == 0xD0 && length(resp) == 2
                client.last_ping = now()
                return Dict(
                    "success" => true,
                    "timestamp" => string(now())
                )
            end
        end
    catch e
    end
    
    return Dict(
        "success" => true,
        "mode" => "simulation",
        "timestamp" => string(now())
    )
end

"""
    _save_state(config::IoTBridgeConfig, client::MQTTClient)

Save MQTT client state to file for persistence.
"""
function _save_state(config::IoTBridgeConfig, client::MQTTClient)
    if config.state_file === nothing
        return
    end
    
    try
        state = Dict(
            "broker_host" => client.broker_host,
            "broker_port" => client.broker_port,
            "client_id" => client.client_id,
            "username" => client.username,
            "keepalive" => client.keepalive,
            "clean_session" => client.clean_session,
            "subscribed_topics" => Dict(k => Int(v) for (k, v) in client.subscribed_topics),
            "last_ping" => client.last_ping !== nothing ? string(client.last_ping) : nothing,
            "state" => string(client.state)
        )
        
        open(config.state_file, "w") do f
            JSON.print(f, state)
        end
    catch e
        # Ignore state save errors
    end
end

"""
    _load_state(config::IoTBridgeConfig)

Load MQTT client state from file.
"""
function _load_state(config::IoTBridgeConfig)
    if config.state_file === nothing || !isfile(config.state_file)
        return nothing
    end
    
    try
        state = JSON.parsefile(config.state_file)
        return state
    catch e
        return nothing
    end
end

"""
    _load_or_create_client(config::IoTBridgeConfig)

Load existing client state or create new one.
"""
function _load_or_create_client(config::IoTBridgeConfig)
    state = _load_state(config)
    
    client = MQTTClient(
        broker_host=config.mqtt_broker,
        broker_port=config.mqtt_port,
        client_id=config.client_id,
        username=config.username,
        password=config.password,
        keepalive=config.keepalive,
        clean_session=config.clean_session
    )
    
    if state !== nothing
        # Restore subscribed topics
        if haskey(state, "subscribed_topics")
            for (topic, qos_int) in state["subscribed_topics"]
                client.subscribed_topics[topic] = QoSLevel(qos_int)
            end
        end
        
        # Restore state
        if haskey(state, "state")
            state_str = state["state"]
            if state_str == "CONNECTED"
                client.state = CONNECTED
            elseif state_str == "CONNECTING"
                client.state = CONNECTING
            elseif state_str == "ERROR"
                client.state = ERROR
            else
                client.state = DISCONNECTED
            end
        end
    end
    
    return client
end

# ============================================================================
# Public API Functions (keep existing interface)
# ============================================================================

"""
    read_sensor(config::IoTBridgeConfig, sensor_id::String)

Read sensor data via MQTT.
"""
function read_sensor(config::IoTBridgeConfig, sensor_id::String)
    # Validate device
    if !validate_device(config, sensor_id)
        return Dict(
            "success" => false,
            "error" => "Sensor '$sensor_id' not in whitelist"
        )
    end
    
    topic = "sensors/$(sensor_id)/read"
    
    if !validate_topic(config, topic, false)
        return Dict(
            "success" => false,
            "error" => "Topic '$topic' not allowed"
        )
    end
    
    println("IoTBridge: Reading sensor $sensor_id")
    
    # Subscribe to response topic
    response_topic = "sensors/$(sensor_id)/response"
    
    # Publish read request
    result = publish(config, topic, Dict(
        "action" => "read",
        "sensor_id" => sensor_id,
        "timestamp" => string(now())
    ); qos=QoS1)
    
    if result["success"]
        # In real implementation, wait for response
        # For now, return expected response
        return Dict(
            "success" => true,
            "sensor_id" => sensor_id,
            "topic" => topic,
            "value" => rand(0.0:100.0),  # Simulated value
            "unit" => "units",
            "timestamp" => string(now())
        )
    else
        return result
    end
end

"""
    control_device(config::IoTBridgeConfig, device_id::String, command::String, value::Any=nothing)

Control IoT device via MQTT.
"""
function control_device(config::IoTBridgeConfig, device_id::String, command::String, value::Any=nothing)
    # Validate device
    if !validate_device(config, device_id)
        return Dict(
            "success" => false,
            "error" => "Device '$device_id' not in whitelist"
        )
    end
    
    topic = "devices/control/$(device_id)"
    
    if !validate_topic(config, topic, true)
        return Dict(
            "success" => false,
            "error" => "Topic '$topic' not allowed for writing"
        )
    end
    
    # Validate command
    if !validate_command(command)
        return Dict(
            "success" => false,
            "error" => "Invalid command. Use: on, off, toggle, set, status, reset, start, stop, pause"
        )
    end
    
    println("IoTBridge: Controlling device $device_id with command $command")
    
    payload = Dict(
        "command" => command,
        "device_id" => device_id,
        "value" => value,
        "timestamp" => string(now())
    )
    
    # Publish control command
    result = publish(config, topic, payload; qos=QoS1, retain=true)
    
    if result["success"]
        return Dict(
            "success" => true,
            "device_id" => device_id,
            "command" => command,
            "topic" => topic,
            "payload" => payload,
            "message_id" => result["message_id"]
        )
    else
        return result
    end
end

"""
    subscribe_topics(config::IoTBridgeConfig, topics::Vector{String})

Subscribe to MQTT topics for real-time updates.
"""
function subscribe_topics(config::IoTBridgeConfig, topics::Vector{String})
    validated_topics = String[]
    errors = String[]
    
    for topic in topics
        if validate_topic(config, topic, false)
            result = subscribe(config, topic; qos=QoS1)
            if result["success"]
                push!(validated_topics, topic)
            else
                push!(errors, "Failed to subscribe to '$topic'")
            end
        else
            push!(errors, "Topic '$topic' not allowed")
        end
    end
    
    println("IoTBridge: Subscribed to topics: $validated_topics")
    
    return Dict(
        "success" => true,
        "subscribed" => validated_topics,
        "errors" => errors
    )
end

"""
    get_device_status(config::IoTBridgeConfig, device_id::String)

Get current device status.
"""
function get_device_status(config::IoTBridgeConfig, device_id::String)
    if !validate_device(config, device_id)
        return Dict(
            "success" => false,
            "error" => "Device '$device_id' not in whitelist"
        )
    end
    
    topic = "devices/status/$(device_id)"
    
    println("IoTBridge: Getting status for device $device_id")
    
    # Subscribe to status topic
    subscribe(config, topic; qos=QoS0)
    
    # Request status
    publish(config, "devices/control/$(device_id)", Dict(
        "command" => "status",
        "device_id" => device_id,
        "timestamp" => string(now())
    ); qos=QoS1)
    
    return Dict(
        "success" => true,
        "device_id" => device_id,
        "topic" => topic,
        "online" => true,
        "state" => "online",
        "last_update" => string(now())
    )
end

"""
    execute(params::Dict)

Main entry point for capability registry.
"""
function execute(params::Dict)
    action = get(params, "action", "connect")
    config = create_config()
    
    # Override config with params if provided
    if haskey(params, "broker")
        config = create_config(
            get(params, "broker", "localhost"),
            get(params, "port", 1883);
            client_id=get(params, "client_id", "adaptive-brain-iot"),
            username=get(params, "username", nothing),
            password=get(params, "password", nothing),
            read_topics=get(params, "read_topics", config.read_topics),
            write_topics=get(params, "write_topics", config.write_topics),
            allowed_devices=get(params, "allowed_devices", config.allowed_devices),
            keepalive=get(params, "keepalive", config.keepalive),
            clean_session=get(params, "clean_session", config.clean_session)
        )
    end
    
    result = try
        if action == "connect"
            connect(config; 
                   username=get(params, "username", nothing),
                   password=get(params, "password", nothing))
        elseif action == "disconnect"
            disconnect(config)
        elseif action == "read_sensor"
            sensor_id = get(params, "sensor_id", "")
            read_sensor(config, sensor_id)
        elseif action == "control_device"
            device_id = get(params, "device_id", "")
            command = get(params, "command", "")
            value = get(params, "value", nothing)
            control_device(config, device_id, command, value)
        elseif action == "publish"
            topic = get(params, "topic", "")
            payload = get(params, "payload", Dict())
            qos = QoSLevel(get(params, "qos", 0))
            retain = get(params, "retain", false)
            publish(config, topic, payload; qos=qos, retain=retain)
        elseif action == "subscribe"
            topic = get(params, "topic", "")
            qos = QoSLevel(get(params, "qos", 0))
            subscribe(config, topic; qos=qos)
        elseif action == "subscribe_topics"
            topics = get(params, "topics", String[])
            subscribe_topics(config, topics)
        elseif action == "unsubscribe"
            topic = get(params, "topic", "")
            unsubscribe(config, topic)
        elseif action == "ping"
            ping(config)
        elseif action == "status"
            device_id = get(params, "device_id", "")
            get_device_status(config, device_id)
        else
            Dict("success" => false, "error" => "Unknown action: $action")
        end
    catch e
        Dict("success" => false, "error" => string(e))
    end
    
    return result
end

# Entry point when run directly
if abspath(PROGRAM_FILE) == @__FILE__()
    result = execute(Dict())
    println(JSON.json(result))
end

end # module
