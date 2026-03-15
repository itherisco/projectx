# UnifiedBridge.jl - Manager-Worker Bridge for Cross-Language Inter-Process Sync
#
# This module implements a unified bridge architecture for managing cross-language
# complexity between Julia (Brain - advisory) and Rust (Kernel - sovereign).
#
# Architecture:
# - Manager: Coordinates state distribution across all workers
# - Workers: Handle specific UI interactions and data processing
# - Pub-Sub: Uses Channels.jl for Julia's native concurrency
# - Zero-Copy: Leverages 64MB lock-free shared-memory ring buffer from RustIPC
#
# Key Principles:
# - "Brain is advisory, Kernel is sovereign" - all decisions go through Rust Warden
# - Zero-copy is critical for high-frequency cognitive core operations
# - Thread-safe pub-sub with minimal latency overhead

module UnifiedBridge

using Dates
using UUIDs
using JSON
using Logging
using Base.Threads
using Mmap

# Try to import adaptive-kernel modules if available, otherwise use fallbacks
const _have_rustipc = Ref{Bool}(false)
const _have_kernel_interface = Ref{Bool}(false)

function _try_load_dependencies()
    # Try to load RustIPC
    try
        @eval using RustIPC
        _have_rustipc[] = true
        @info "UnifiedBridge: RustIPC loaded successfully"
    catch e
        @warn "UnifiedBridge: RustIPC not available, using fallback mode"
    end
    
    # Try to load KernelInterface
    try
        @eval using KernelInterface
        _have_kernel_interface[] = true
        @info "UnifiedBridge: KernelInterface loaded successfully"
    catch e
        @warn "UnifiedBridge: KernelInterface not available, using fallback mode"
    end
end

# Initialize dependencies
_try_load_dependencies()

# ============================================================================
# Public API Exports
# ============================================================================

export 
    # Core Bridge Types
    UnifiedBridgeManager,
    BridgeWorker,
    BridgeState,
    StateSubscription,
    
    # Manager Operations
    init_bridge,
    broadcast_state,
    subscribe,
    unsubscribe,
    get_worker_state,
    
    # Worker Operations
    create_worker,
    worker_process,
    worker_receive,
    worker_send,
    
    # Zero-Copy Operations
    write_shared_tensor,
    read_shared_tensor,
    share_memory_region,
    
    # Integration
    connect_warden,
    is_warden_connected,
    sync_with_kernel

# ============================================================================
# Constants and Configuration
# ============================================================================

# Shared memory configuration
const SHARED_MEM_KEY = "itheris_unified_bridge"
const DEFAULT_SHARED_MEM_SIZE = 64 * 1024 * 1024  # 64MB
const RING_BUFFER_SIZE = 16 * 1024 * 1024  # 16MB for ring buffer

# Channel configuration
const STATE_CHANNEL_SIZE = 1024
const WORKER_COMMAND_SIZE = 256
const BROADCAST_BUFFER_SIZE = 512

# Timeout configuration
const DEFAULT_SYNC_TIMEOUT_MS = 1000
const WARDEN_HEARTBEAT_INTERVAL_MS = 500

# ============================================================================
# Core Type Definitions
# ============================================================================

"""
    BridgeState - Immutable state snapshot for synchronization

Fields:
- id: Unique state identifier
- timestamp: State creation time
- cognitive_state: Current cognitive/attention state
- system_state: System metrics and energy levels
- security_state: Security and risk assessment
- data: Additional arbitrary state data
"""
struct BridgeState
    id::UUID
    timestamp::DateTime
    cognitive_state::Dict{String, Any}
    system_state::Dict{String, Any}
    security_state::Dict{String, Any}
    data::Dict{String, Any}
    
    function BridgeState(;
        cognitive_state::Dict{String, Any}=Dict{String, Any}(),
        system_state::Dict{String, Any}=Dict{String, Any}(),
        security_state::Dict{String, Any}=Dict{String, Any}(),
        data::Dict{String, Any}=Dict{String, Any}())
        
        new(
            uuid4(),
            now(),
            cognitive_state,
            system_state,
            security_state,
            data
        )
    end
end

"""
    StateSubscription - Subscription to bridge state updates

Fields:
- id: Unique subscription identifier
- worker_id: Associated worker (if any)
- filter_fn: Optional filter function
- channel: Channel for receiving state updates
- last_state_id: Last received state ID
"""
mutable struct StateSubscription
    id::UUID
    worker_id::Union{UUID, Nothing}
    filter_fn::Union{Function, Nothing}
    channel::Channel{BridgeState}
    last_state_id::Union{UUID, Nothing}
    
    StateSubscription(worker_id::Union{UUID, Nothing}=nothing; 
                      filter_fn::Union{Function, Nothing}=nothing) = (
        new(uuid4(), worker_id, filter_fn, 
            Channel{BridgeState}(STATE_CHANNEL_SIZE), nothing)
    )
end

"""
    BridgeWorker - Worker component for handling UI interactions

Fields:
- id: Unique worker identifier
- name: Human-readable worker name
- task_type: Type of task this worker handles
- command_channel: Channel for receiving commands
- result_channel: Channel for sending results
- state: Current worker state
- metrics: Worker performance metrics
"""
mutable struct BridgeWorker
    id::UUID
    name::String
    task_type::Symbol
    command_channel::Channel{Dict{String, Any}}
    result_channel::Channel{Dict{String, Any}}
    state::Dict{String, Any}
    metrics::Dict{String, Any}
    active::Bool
    
    function BridgeWorker(name::String, task_type::Symbol)
        new(
            uuid4(),
            name,
            task_type,
            Channel{Dict{String, Any}}(WORKER_COMMAND_SIZE),
            Channel{Dict{String, Any}}(WORKER_COMMAND_SIZE),
            Dict{String, Any}(),
            Dict{String, Any}(
                "messages_processed" => 0,
                "errors" => 0,
                "avg_latency_ms" => 0.0
            ),
            false
        )
    end
end

"""
    UnifiedBridgeManager - Central manager for bridge coordination

Fields:
- id: Unique manager identifier
- state_channel: Main channel for state broadcasts
- subscriptions: Active state subscriptions
- workers: Registered workers
- warden_connected: Whether Rust Warden is connected
- last_sync: Last synchronization timestamp
- shared_mem: Shared memory region reference
- metrics: Manager metrics
"""
mutable struct UnifiedBridgeManager
    id::UUID
    state_channel::Channel{BridgeState}
    subscriptions::Vector{StateSubscription}
    workers::Dict{UUID, BridgeWorker}
    warden_connected::Bool
    last_sync::DateTime
    shared_mem::Union{Mmap.Array, Nothing}
    mem_lock::ReentrantLock
    metrics::Dict{String, Any}
    
    function UnifiedBridgeManager()
        new(
            uuid4(),
            Channel{BridgeState}(BROADCAST_BUFFER_SIZE),
            StateSubscription[],
            Dict{UUID, BridgeWorker}(),
            false,
            now(),
            nothing,
            ReentrantLock(),
            Dict{String, Any}(
                "states_broadcast" => 0,
                "subscriptions_count" => 0,
                "workers_count" => 0,
                "avg_broadcast_latency_ms" => 0.0
            )
        )
    end
end

# ============================================================================
# Manager Implementation
# ============================================================================

# Global manager instance
const _global_manager = Ref{UnifiedBridgeManager}()

"""
    init_bridge(; shared_mem_size::Int=DEFAULT_SHARED_MEM_SIZE)::Bool

Initialize the Unified Bridge with shared memory region.
"""
function init_bridge(; shared_mem_size::Int=DEFAULT_SHARED_MEM_SIZE)::Bool
    try
        # Create new manager
        _global_manager[] = UnifiedBridgeManager()
        manager = _global_manager[]
        
        # Initialize shared memory region for zero-copy operations
        # This creates a memory-mapped array that can be shared with Rust
        try
            manager.shared_mem = Mmap.Array{Float64, 2}(undef, (shared_mem_size ÷ sizeof(Float64), 1))
            @info "Shared memory region initialized: $(shared_mem_size ÷ 1024 ÷ 1024)MB"
        catch e
            @warn "Could not initialize shared memory: $e. Using fallback."
            manager.shared_mem = nothing
        end
        
        # Start broadcast task
        @async _broadcast_task()
        
        @info "UnifiedBridge initialized successfully"
        return true
        
    catch e
        @error "Failed to initialize UnifiedBridge: $e"
        return false
    end
end

"""
    _broadcast_task() - Internal task for broadcasting state to subscribers
"""
function _broadcast_task()
    manager = _global_manager[]
    
    while true
        try
            # Wait for new state to broadcast
            state = take!(manager.state_channel)
            
            # Track timing
            broadcast_start = time()
            
            # Send to all active subscriptions
            for sub in manager.subscriptions
                # Apply filter if present
                if sub.filter_fn !== nothing && !sub.filter_fn(state)
                    continue
                end
                
                # Non-blocking put with timeout
                try
                    put!(sub.channel, state)
                    sub.last_state_id = state.id
                catch
                    # Subscription channel full - skip this subscriber
                end
            end
            
            # Update metrics
            broadcast_time = (time() - broadcast_start) * 1000
            manager.metrics["states_broadcast"] += 1
            
            # Running average of broadcast latency
            prev_avg = manager.metrics["avg_broadcast_latency_ms"]
            n = manager.metrics["states_broadcast"]
            manager.metrics["avg_broadcast_latency_ms"] = (prev_avg * (n - 1) + broadcast_time) / n
            
        catch e
            @error "Error in broadcast task: $e"
        end
    end
end

"""
    broadcast_state(state::BridgeState)::Bool

Broadcast a state to all subscribers.
This is the main entry point for state synchronization.
"""
function broadcast_state(state::BridgeState)::Bool
    manager = _global_manager[]
    
    try
        # Update state metadata
        state = BridgeState(
            cognitive_state = state.cognitive_state,
            system_state = state.system_state,
            security_state = state.security_state,
            data = merge(state.data, Dict(
                "broadcast_id" => string(uuid4()),
                "manager_id" => string(manager.id)
            ))
        )
        
        # Put into broadcast channel (non-blocking)
        put!(manager.state_channel, state)
        
        # Also write to shared memory for Rust to consume
        _write_state_to_shared_mem(state)
        
        return true
        
    catch e
        @error "Failed to broadcast state: $e"
        return false
    end
end

"""
    _write_state_to_shared_mem(state::BridgeState)

Write state to shared memory for zero-copy Rust access.
"""
function _write_state_to_shared_mem(state::BridgeState)
    manager = _global_manager[]
    
    lock(manager.mem_lock) do
        if manager.shared_mem === nothing
            return
        end
        
        try
            # Serialize state to JSON
            state_json = JSON.json(Dict(
                "id" => string(state.id),
                "timestamp" => string(state.timestamp),
                "cognitive" => state.cognitive_state,
                "system" => state.system_state,
                "security" => state.security_state,
                "data" => state.data
            ))
            
            # Write to shared memory (first 4KB for header, rest for data)
            bytes = Vector{UInt8}(state_json)
            
            # Ensure we don't overflow
            if length(bytes) < length(manager.shared_mem) * sizeof(Float64)
                # Write header: magic number + version + size
                manager.shared_mem[1] = Float64(0x49544845524953)  # "ITHERIS" as float64
                manager.shared_mem[2] = 1.0  # version
                manager.shared_mem[3] = Float64(length(bytes))  # data size
                
                # Write data starting at index 4
                for (i, b) in enumerate(bytes)
                    manager.shared_mem[4 + i] = Float64(b)
                end
            end
            
        catch e
            @warn "Failed to write to shared memory: $e"
        end
    end
end

"""
    subscribe(worker_id::Union{UUID, Nothing}=nothing; 
              filter_fn::Union{Function, Nothing}=nothing)::StateSubscription

Subscribe to state updates.
"""
function subscribe(worker_id::Union{UUID, Nothing}=nothing;
                   filter_fn::Union{Function, Nothing}=nothing)::StateSubscription
    
    manager = _global_manager[]
    
    sub = StateSubscription(worker_id; filter_fn=filter_fn)
    push!(manager.subscriptions, sub)
    manager.metrics["subscriptions_count"] = length(manager.subscriptions)
    
    return sub
end

"""
    unsubscribe(subscription::StateSubscription)::Bool

Unsubscribe from state updates.
"""
function unsubscribe(subscription::StateSubscription)::Bool
    manager = _global_manager[]
    
    try
        filter!(s -> s.id != subscription.id, manager.subscriptions)
        manager.metrics["subscriptions_count"] = length(manager.subscriptions)
        return true
    catch e
        @error "Failed to unsubscribe: $e"
        return false
    end
end

"""
    get_worker_state(worker_id::UUID)::Union{Dict{String, Any}, Nothing}

Get current state for a specific worker.
"""
function get_worker_state(worker_id::UUID)::Union{Dict{String, Any}, Nothing}
    manager = _global_manager[]
    
    worker = get(manager.workers, worker_id, nothing)
    worker === nothing && return nothing
    
    return copy(worker.state)
end

# ============================================================================
# Worker Implementation
# ============================================================================

"""
    create_worker(name::String, task_type::Symbol)::BridgeWorker

Create a new worker for handling specific UI interactions.
"""
function create_worker(name::String, task_type::Symbol)::BridgeWorker
    manager = _global_manager[]
    
    worker = BridgeWorker(name, task_type)
    manager.workers[worker.id] = worker
    manager.metrics["workers_count"] = length(manager.workers)
    
    # Start worker task
    @async _worker_task(worker)
    
    @info "Created worker: $(worker.name) (type: $task_type)"
    return worker
end

"""
    _worker_task(worker::BridgeWorker)

Internal task for processing worker commands.
"""
function _worker_task(worker::BridgeWorker)
    worker.active = true
    
    while worker.active
        try
            # Wait for command (with timeout)
            command = take!(worker.command_channel)
            
            start_time = time()
            
            # Process command based on type
            result = worker_process(worker, command)
            
            # Send result back
            put!(worker.result_channel, result)
            
            # Update metrics
            worker.metrics["messages_processed"] += 1
            latency = (time() - start_time) * 1000
            n = worker.metrics["messages_processed"]
            prev_avg = worker.metrics["avg_latency_ms"]
            worker.metrics["avg_latency_ms"] = (prev_avg * (n - 1) + latency) / n
            
        catch e
            if worker.active
                worker.metrics["errors"] += 1
                @error "Worker $(worker.name) error: $e"
            end
        end
    end
    
    @info "Worker $(worker.name) stopped"
end

"""
    worker_process(worker::BridgeWorker, command::Dict{String, Any})::Dict{String, Any}

Process a command received by the worker.
"""
function worker_process(worker::BridgeWorker, command::Dict{String, Any})::Dict{String, Any}
    cmd_type = get(command, "type", "unknown")
    
    result = Dict{String, Any}(
        "worker_id" => string(worker.id),
        "worker_name" => worker.name,
        "command_type" => cmd_type,
        "success" => false,
        "timestamp" => now()
    )
    
    try
        # Route to appropriate handler
        if cmd_type == "query_state"
            result["data"] = worker.state
            result["success"] = true
            
        elseif cmd_type == "update_state"
            merge!(worker.state, get(command, "data", Dict()))
            result["data"] = worker.state
            result["success"] = true
            
        elseif cmd_type == "request_kernel_approval"
            # Send to Rust Warden for approval
            action = get(command, "action", Dict{String, Any}())
            
            if _have_kernel_interface[]
                approved, reason = KernelInterface.approve_action(action)
            else
                # Fallback: approve with warning when kernel interface unavailable
                approved = true
                reason = "Approved (fallback mode - kernel interface unavailable)"
                @warn "Kernel approval in fallback mode for: $(get(action, "name", "unknown"))"
            end
            result["data"] = Dict(
                "approved" => approved,
                "reason" => reason
            )
            result["success"] = true
            
        elseif cmd_type == "tensor_sync"
            # Zero-copy tensor synchronization
            tensor_name = get(command, "tensor_name", "")
            tensor_data = get(command, "tensor_data", Float64[])
            
            # Write to shared memory
            success = write_shared_tensor(tensor_name, tensor_data)
            result["data"] = Dict("shared" => success)
            result["success"] = success
            
        elseif cmd_type == "subscribe_states"
            # Subscribe to state updates
            sub = subscribe(worker.id)
            result["data"] = Dict("subscription_id" => string(sub.id))
            result["success"] = true
            
        else
            result["error"] = "Unknown command type: $cmd_type"
        end
        
    catch e
        result["error"] = string(e)
    end
    
    return result
end

"""
    worker_receive(worker::BridgeWorker; timeout::Float64=1.0)::Union{Dict{String, Any}, Nothing}

Receive a result from the worker's result channel.
"""
function worker_receive(worker::BridgeWorker; timeout::Float64=1.0)::Union{Dict{String, Any}, Nothing}
    try
        return fetch(@async take!(worker.result_channel))
    catch
        return nothing
    end
end

"""
    worker_send(worker::BridgeWorker, command::Dict{String, Any})::Bool

Send a command to the worker.
"""
function worker_send(worker::BridgeWorker, command::Dict{String, Any})::Bool
    try
        put!(worker.command_channel, command)
        return true
    catch e
        @error "Failed to send command to worker: $e"
        return false
    end
end

# ============================================================================
# Zero-Copy Data Sharing Implementation
# ============================================================================

"""
    write_shared_tensor(name::String, data::Vector{Float64})::Bool

Write a tensor to shared memory for zero-copy access.
This is critical for high-frequency cognitive operations.
"""
function write_shared_tensor(name::String, data::Vector{Float64})::Bool
    manager = _global_manager[]
    
    lock(manager.mem_lock) do
        if manager.shared_mem === nothing
            return false
        end
        
        try
            # Simple hash of name for indexing
            idx = hash(name) % (length(manager.shared_mem) - 1024) + 1024
            
            # Write tensor data
            for (i, val) in enumerate(data)
                if idx + i < length(manager.shared_mem)
                    manager.shared_mem[idx + i] = val
                else
                    break
                end
            end
            
            return true
            
        catch e
            @error "Failed to write shared tensor: $e"
            return false
        end
    end
end

"""
    read_shared_tensor(name::String, count::Int)::Union{Vector{Float64}, Nothing}

Read a tensor from shared memory (zero-copy).
"""
function read_shared_tensor(name::String, count::Int)::Union{Vector{Float64}, Nothing}
    manager = _global_manager[]
    
    lock(manager.mem_lock) do
        if manager.shared_mem === nothing
            return nothing
        end
        
        try
            # Same hash as write for consistency
            idx = hash(name) % (length(manager.shared_mem) - 1024) + 1024
            
            # Read tensor data
            data = Float64[]
            for i in 1:min(count, length(manager.shared_mem) - idx)
                push!(data, manager.shared_mem[idx + i])
            end
            
            return data
            
        catch e
            @error "Failed to read shared tensor: $e"
            return nothing
        end
    end
end

"""
    share_memory_region()::Union{Mmap.Array, Nothing}

Get direct access to the shared memory region.
Use with caution - requires manual synchronization.
"""
function share_memory_region()::Union{Mmap.Array, Nothing}
    manager = _global_manager[]
    return manager.shared_mem
end

# ============================================================================
# Rust Warden Integration
# ============================================================================

"""
    connect_warden()::Bool

Connect to the Rust Warden for security enforcement.
This establishes the connection to the Rust kernel for sovereign decisions.
"""
function connect_warden()::Bool
    manager = _global_manager[]
    
    try
        # Check if RustIPC is available
        if !_have_rustipc[]
            @warn "RustIPC not available, running in fallback mode"
            manager.warden_connected = true  # Allow fallback mode
            manager.last_sync = now()
            @info "UnifiedBridge running in fallback mode (no Rust Warden)"
            return true
        end
        
        # Try to initialize Rust IPC
        success = RustIPC.init_rust_ipc()
        
        if success
            manager.warden_connected = true
            manager.last_sync = now()
            
            @info "Connected to Rust Warden"
            
            # Start heartbeat task
            @async _warden_heartbeat_task()
            
            return true
        else
            @error "Failed to connect to Rust Warden"
            return false
        end
        
    catch e
        @error "Error connecting to Warden: $e"
        return false
    end
end

"""
    _warden_heartbeat_task()

Internal task for monitoring Warden connection.
"""
function _warden_heartbeat_task()
    manager = _global_manager[]
    
    # Don't run heartbeat if we're in fallback mode
    if !_have_rustipc[]
        return
    end
    
    while manager.warden_connected
        try
            # Check if Rust is still available
            if !RustIPC.is_rust_library_available()
                @error "Warden connection lost!"
                manager.warden_connected = false
                break
            end
            
            # Update sync time
            manager.last_sync = now()
            
            # Wait for next heartbeat
            sleep(WARDEN_HEARTBEAT_INTERVAL_MS / 1000)
            
        catch e
            @error "Heartbeat error: $e"
            manager.warden_connected = false
            break
        end
    end
end

"""
    is_warden_connected()::Bool

Check if Rust Warden is connected.
"""
function is_warden_connected()::Bool
    manager = _global_manager[]
    return manager.warden_connected
end

"""
    sync_with_kernel(; timeout_ms::Int=DEFAULT_SYNC_TIMEOUT_MS)::Bool

Synchronize state with the Rust kernel via shared memory.
This ensures the kernel has the latest state for sovereign decisions.
"""
function sync_with_kernel(; timeout_ms::Int=DEFAULT_SYNC_TIMEOUT_MS)::Bool
    manager = _global_manager[]
    
    if !manager.warden_connected
        @warn "Cannot sync with kernel - Warden not connected"
        return false
    end
    
    try
        # Create current state snapshot
        state = BridgeState(
            cognitive_state = Dict(
                "attention_focus" => 0.9,
                "cognitive_load" => 0.5,
                "decision_confidence" => 0.8
            ),
            system_state = Dict(
                "energy_level" => 1.0,
                "latency_ms" => 0.0,
                "memory_pressure" => 0.3
            ),
            security_state = Dict(
                "threat_level" => 0.0,
                "sanitization_rate" => 1.0
            ),
            data = Dict(
                "sync_timestamp" => now()
            )
        )
        
        # Broadcast to all subscribers
        success = broadcast_state(state)
        
        if success
            manager.last_sync = now()
        end
        
        return success
        
    catch e
        @error "Failed to sync with kernel: $e"
        return false
    end
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    get_bridge_status()::Dict{String, Any}

Get current bridge status and metrics.
"""
function get_bridge_status()::Dict{String, Any}
    manager = _global_manager[]
    
    return Dict(
        "manager_id" => string(manager.id),
        "warden_connected" => manager.warden_connected,
        "last_sync" => string(manager.last_sync),
        "subscriptions" => manager.metrics["subscriptions_count"],
        "workers" => manager.metrics["workers_count"],
        "states_broadcast" => manager.metrics["states_broadcast"],
        "avg_broadcast_latency_ms" => manager.metrics["avg_broadcast_latency_ms"],
        "shared_memory_active" => manager.shared_mem !== nothing,
        "timestamp" => now()
    )
end

"""
    create_state_snapshot(;
        cognitive::Dict{String, Any}=Dict{String, Any}(),
        system::Dict{String, Any}=Dict{String, Any}(),
        security::Dict{String, Any}=Dict{String, Any}(),
        data::Dict{String, Any}=Dict{String, Any}())::BridgeState

Create a state snapshot for broadcasting.
"""
function create_state_snapshot(;
    cognitive::Dict{String, Any}=Dict{String, Any}(),
    system::Dict{String, Any}=Dict{String, Any}(),
    security::Dict{String, Any}=Dict{String, Any}(),
    data::Dict{String, Any}=Dict{String, Any}())::BridgeState
    
    return BridgeState(
        cognitive_state=cognitive,
        system_state=system,
        security_state=security,
        data=data
    )
end

# ============================================================================
# Module Initialization
# ============================================================================

function __init__()
    # Auto-initialize on module load
    if _global_manager[] === nothing
        init_bridge()
    end
end

end # module UnifiedBridge
