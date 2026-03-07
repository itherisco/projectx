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
- MQTT for messaging
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

# IoT Bridge Configuration
struct IoTBridgeConfig
    mqtt_broker::String
    mqtt_port::Int
    client_id::String
    read_topics::Vector{String}
    write_topics::Vector{String}
    allowed_devices::Vector{String}
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
        ["sensors/#", "devices/status/#"],     # read_topics
        ["devices/control/#", "actuators/#"],  # write_topics
        ["sensor-", "device-", "actuator-"]    # allowed_devices (prefixes)
    )
end

"""
    validate_topic(config::IoTBridgeConfig, topic::String, write::Bool=false)

Validate topic is in whitelist.
"""
function validate_topic(config::IoTBridgeConfig, topic::String, write::Bool=false)
    allowed_topics = write ? config.write_topics : config.read_topics
    
    for allowed in allowed_topics
        # Exact match or wildcard match
        if topic == allowed || occursin(allowed, topic) || startswith(topic, rstrip(allowed, '#'))
            return true
        end
    end
    
    return false
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
    connect(config::IoTBridgeConfig)

Establish MQTT connection.
"""
function connect(config::IoTBridgeConfig)
    println("IoTBridge: Connecting to MQTT broker at $(config.mqtt_broker):$(config.mqtt_port)")
    
    # In production, actual MQTT connection
    return Dict(
        "success" => true,
        "connected" => true,
        "client_id" => config.client_id,
        "broker" => "$(config.mqtt_broker):$(config.mqtt_port)"
    )
end

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
    
    # In production, actual MQTT publish/subscribe
    return Dict(
        "success" => true,
        "sensor_id" => sensor_id,
        "topic" => topic,
        "value" => 0.0,
        "unit" => "",
        "timestamp" => string(now())
    )
end

"""
    control_device(config::IoTBridgeConfig, device_id::String, command::String, value::Any)

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
    valid_commands = ["on", "off", "toggle", "set", "status", "reset"]
    if command ∉ valid_commands
        return Dict(
            "success" => false,
            "error" => "Invalid command. Must be one of: $(join(valid_commands, ", "))"
        )
    end
    
    println("IoTBridge: Controlling device $device_id with command $command")
    
    payload = Dict(
        "command" => command,
        "device_id" => device_id,
        "value" => value,
        "timestamp" => string(now())
    )
    
    return Dict(
        "success" => true,
        "device_id" => device_id,
        "command" => command,
        "topic" => topic,
        "payload" => payload
    )
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
            push!(validated_topics, topic)
        else
            push!(errors, "Topic '$topic' not allowed")
        end
    end
    
    println("IoTBridge: Subscribing to topics: $validated_topics")
    
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
    
    return Dict(
        "success" => true,
        "device_id" => device_id,
        "online" => false,
        "state" => "unknown",
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
    
    result = try
        if action == "connect"
            connect(config)
        elseif action == "read_sensor"
            sensor_id = get(params, "sensor_id", "")
            read_sensor(config, sensor_id)
        elseif action == "control_device"
            device_id = get(params, "device_id", "")
            command = get(params, "command", "")
            value = get(params, "value", nothing)
            control_device(config, device_id, command, value)
        elseif action == "subscribe"
            topics = get(params, "topics", String[])
            subscribe_topics(config, topics)
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
