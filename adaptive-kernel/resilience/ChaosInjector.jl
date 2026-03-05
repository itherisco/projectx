# ChaosInjector.jl - Chaos Engineering Framework for Resilience Testing
#
# This module provides systematic failure injection capabilities to proactively
# identify system weaknesses before production deployment.
#
# Implementation follows chaos engineering principles:
# 1. Failure Injection: Systematically inject failures
# 2. Observe Behavior: Monitor system response
# 3. Remediate: Fix discovered vulnerabilities
#
# Features:
# - Latency Injection (500ms-5s spikes)
# - Memory Pressure Simulator
# - Random Timeout Generator
# - Partial Write Simulator
# - Corrupted Data Injector
# - Network Partition Simulator
# - CPU Pressure Generator

module ChaosInjector

using Random
using Dates
using UUIDs
using JSON

# ============================================================================
# Chaos Configuration
# ============================================================================

"""
    ChaosConfig - Configuration for chaos injection experiments

Fields:
- enabled::Bool - Whether chaos injection is active
- latency_probability::Float64 - Probability of latency injection (0-1)
- memory_pressure_mb::Int - Target memory pressure in MB
- timeout_probability::Float64 - Probability of random timeout (0-1)
- corruption_probability::Float64 - Probability of data corruption (0-1)
- log_injections::Bool - Whether to log injection events
"""
mutable struct ChaosConfig
    enabled::Bool
    latency_probability::Float64
    memory_pressure_mb::Int
    timeout_probability::Float64
    corruption_probability::Float64
    log_injections::Bool
    
    function ChaosConfig(;enabled::Bool=true,
                         latency_probability::Float64=0.1,
                         memory_pressure_mb::Int=100,
                         timeout_probability::Float64=0.05,
                         corruption_probability::Float64=0.05,
                         log_injections::Bool=true)
        new(enabled, latency_probability, memory_pressure_mb, 
            timeout_probability, corruption_probability, log_injections)
    end
end

"""
    ChaosExperiment - Represents a chaos injection experiment

Fields:
- id::UUID - Unique experiment identifier
- name::String - Human-readable experiment name
- started_at::DateTime - When experiment started
- ended_at::Union{DateTime, Nothing} - When experiment ended
- injections::Vector{Dict} - Record of all injections performed
- config::ChaosConfig - Configuration for this experiment
- results::Dict - Results of the experiment
"""
mutable struct ChaosExperiment
    id::UUID
    name::String
    description::String
    started_at::DateTime
    ended_at::Union{DateTime, Nothing}
    injections::Vector{Dict}
    config::ChaosConfig
    results::Dict{String, Any}  # Changed from Dict to allow Any values
    
    function ChaosExperiment(name::String; description::String="", config::ChaosConfig=ChaosConfig())
        new(uuid4(), name, description, now(), nothing, Dict[], config, Dict{String, Any}())
    end
end

# ============================================================================
# Latency Injection
# ============================================================================

"""
    inject_latency(latency_ms::Int; config::ChaosConfig=default_config()) -> Float64

Inject artificial latency into the system.

# Arguments
- `latency_ms::Int`: Latency to inject in milliseconds

# Returns
- Actual latency injected in seconds

# Example
```julia
latency = inject_latency(500)  # Inject 500ms latency
```
"""
function inject_latency(latency_ms::Int; config::ChaosConfig=default_config())::Float64
    if !config.enabled
        return 0.0
    end
    
    # Clamp latency to reasonable bounds (1ms - 30s)
    actual_latency = clamp(latency_ms, 1, 30000)
    
    # Convert to seconds and sleep
    sleep_time = actual_latency / 1000.0
    sleep(sleep_time)
    
    if config.log_injections
        @info "Latency injection" latency_ms=actual_latency
    end
    
    return sleep_time
end

"""
    inject_random_latency(;min_ms::Int=500, max_ms::Int=5000, config::ChaosConfig=default_config()) -> Float64

Inject random latency within specified range.

# Arguments
- `min_ms::Int`: Minimum latency in milliseconds (default: 500)
- `max_ms::Int`: Maximum latency in milliseconds (default: 5000)
- `config::ChaosConfig`: Chaos configuration

# Returns
- Actual latency injected in seconds
"""
function inject_random_latency(;min_ms::Int=500, max_ms::Int=5000, config::ChaosConfig=default_config())::Float64
    if !config.enabled
        return 0.0
    end
    
    latency_ms = rand(min_ms:max_ms)
    return inject_latency(latency_ms; config=config)
end

"""
    with_latency_injection(fn::Function, latency_ms::Int; config::ChaosConfig=default_config())

Execute a function with artificial latency injection.

# Arguments
- `fn::Function`: Function to execute
- `latency_ms::Int`: Latency to inject in milliseconds
- `config::ChaosConfig`: Chaos configuration

# Example
```julia
result = with_latency_injection(() -> expensive_operation(), 1000)
```
"""
function with_latency_injection(fn::Function, latency_ms::Int; config::ChaosConfig=default_config())
    inject_latency(latency_ms; config=config)
    return fn()
end

# ============================================================================
# Memory Pressure Simulation
# ============================================================================

# Track allocated memory for cleanup
const _allocated_arrays = Vector{Vector{UInt8}}()

"""
    inject_memory_pressure(target_mb::Int; config::ChaosConfig=default_config()) -> Int

Simulate memory pressure by allocating memory.

# Arguments
- `target_mb::Int`: Target memory to allocate in MB
- `config::ChaosConfig`: Chaos configuration

# Returns
- Actual memory allocated in MB

# Example
```julia
allocated_mb = inject_memory_pressure(100)  # Allocate 100MB
```
"""
function inject_memory_pressure(target_mb::Int; config::ChaosConfig=default_config())::Int
    if !config.enabled
        return 0
    end
    
    # Clamp to reasonable bounds
    actual_mb = clamp(target_mb, 1, config.memory_pressure_mb)
    
    try
        # Allocate memory in chunks to avoid immediate OOM
        chunk_size = 1024 * 1024  # 1MB chunks
        num_chunks = actual_mb
        
        for _ in 1:num_chunks
            push!(_allocated_arrays, Vector{UInt8}(undef, chunk_size))
        end
        
        if config.log_injections
            @info "Memory pressure injection" target_mb=actual_mb
        end
        
        return actual_mb
    catch e
        @warn "Memory pressure injection failed" error=e
        return 0
    end
end

"""
    release_memory_pressure() -> Int

Release previously allocated memory pressure.

# Returns
- Amount of memory released in MB
"""
function release_memory_pressure()::Int
    released = length(_allocated_arrays)
    empty!(_allocated_arrays)
    GC.gc()
    return released
end

"""
    get_memory_pressure_level() -> Int

Get current memory pressure level.

# Returns
- Current allocated memory in MB
"""
function get_memory_pressure_level()::Int
    return length(_allocated_arrays)
end

# ============================================================================
# Random Timeout Generation
# ============================================================================

"""
    should_inject_timeout(config::ChaosConfig=default_config()) -> Bool

Determine if a timeout should be injected based on probability.

# Arguments
- `config::ChaosConfig`: Chaos configuration

# Returns
- true if timeout should be injected
"""
function should_inject_timeout(config::ChaosConfig=default_config())::Bool
    if !config.enabled
        return false
    end
    return rand() < config.timeout_probability
end

"""
    inject_random_timeout(fn::Function; config::ChaosConfig=default_config())

Execute a function with random timeout injection.

# Arguments
- `fn::Function`: Function to execute
- `config::ChaosConfig`: Chaos configuration

# Returns
- Function result or throws TimeoutError

# Example
```julia
result = inject_random_timeout(() -> api_call())
```
"""
function inject_random_timeout(fn::Function; config::ChaosConfig=default_config())
    if should_inject_timeout(config)
        if config.log_injections
            @info "Random timeout injection triggered"
        end
        throw(TimeoutError("Simulated random timeout"))
    end
    return fn()
end

"""
    TimeoutError - Custom timeout error for chaos testing
"""
struct TimeoutError <: Exception
    message::String
end

# ============================================================================
# Partial Write Simulation
# ============================================================================

"""
    simulate_partial_write(data::String, bytes_to_write::Int; config::ChaosConfig=default_config()) -> Tuple{String, Int}

Simulate a partial file write scenario.

# Arguments
- `data::String`: Data to write
- `bytes_to_write::Int`: Number of bytes to "write" (simulated)
- `config::ChaosConfig`: Chaos configuration

# Returns
- Tuple of (partial_data, actual_bytes_written)

# Example
```julia
partial, bytes = simulate_partial_write("complete data", 7)
# partial = "comple", bytes = 7
```
"""
function simulate_partial_write(data::String, bytes_to_write::Int; config::ChaosConfig=default_config())::Tuple{String, Int}
    if !config.enabled
        return (data, length(data))
    end
    
    # Calculate actual bytes to write
    data_bytes = length(data)
    actual_bytes = clamp(bytes_to_write, 0, data_bytes)
    
    # Get partial data
    partial = data[1:actual_bytes]
    
    if config.log_injections
        @info "Partial write simulation" original_bytes=data_bytes written_bytes=actual_bytes
    end
    
    return (partial, actual_bytes)
end

"""
    simulate_partial_write_with_failure(data::String; failure_probability::Float64=0.5, config::ChaosConfig=default_config())

Simulate partial write that may fail mid-operation.

# Arguments
- `data::String`: Data to write
- `failure_probability::Float64`: Probability of failure
- `config::ChaosConfig`: Chaos configuration

# Returns
- Tuple of (success::Bool, partial_data::Union{String, Nothing})
"""
function simulate_partial_write_with_failure(data::String; failure_probability::Float64=0.5, config::ChaosConfig=default_config())::Tuple{Bool, Union{String, Nothing}}
    if !config.enabled
        return (true, data)
    end
    
    if rand() < failure_probability
        # Simulate failure at random point
        bytes_written = rand(1:length(data))
        partial = data[1:bytes_written]
        
        if config.log_injections
            @info "Partial write failure simulation" bytes_written=bytes_written total_bytes=length(data)
        end
        
        return (false, partial)
    end
    
    return (true, data)
end

# ============================================================================
# Corrupted Data Injection
# ============================================================================

"""
    CorruptionType - Types of data corruption

Options:
- :null_byte - Inject null bytes
- :truncation - Truncate data
- :garbage - Inject random garbage bytes
- :encoding - Corrupt encoding
- :json_malformed - Make JSON unparseable
"""
@enum CorruptionType begin
    NULL_BYTE
    TRUNCATION
    GARBAGE
    ENCODING
    JSON_MALFORMED
end

"""
    inject_corruption(data::String, corruption_type::Symbol; config::ChaosConfig=default_config()) -> String

Inject corruption into data string.

# Arguments
- `data::String`: Data to corrupt
- `corruption_type::Symbol`: Type of corruption (:null_byte, :truncation, :garbage, :encoding, :json_malformed)
- `config::ChaosConfig`: Chaos configuration

# Returns
- Corrupted data string

# Example
```julia
corrupted = inject_corruption("valid data", :null_byte)
```
"""
function inject_corruption(data::String, corruption_type::Symbol; config::ChaosConfig=default_config())::String
    if !config.enabled || rand() > config.corruption_probability
        return data
    end
    
    corrupted = data
    
    if corruption_type == :null_byte || corruption_type == NULL_BYTE
        # Inject null bytes at random position
        pos = rand(1:max(1, length(data)))
        corrupted = data[1:pos-1] * "\x00" * data[pos:end]
        
    elseif corruption_type == :truncation || corruption_type == TRUNCATION
        # Truncate at random point
        if length(data) > 1
            trunc_pos = rand(1:length(data)-1)
            corrupted = data[1:trunc_pos]
        end
        
    elseif corruption_type == :garbage || corruption_type == GARBAGE
        # Replace random portion with garbage
        if length(data) > 4
            start_pos = rand(1:length(data)-3)
            end_pos = rand(start_pos+1:min(start_pos+4, length(data)))
            garbage = String(rand(UInt8, end_pos - start_pos + 1))
            corrupted = data[1:start_pos-1] * garbage * data[end_pos+1:end]
        end
        
    elseif corruption_type == :encoding || corruption_type == ENCODING
        # Corrupt UTF-8 encoding
        corrupted = transcode(String, Vector{UInt8}(data) .⊻ rand(0x01:0xFF, length(data)))
        
    elseif corruption_type == :json_malformed || corruption_type == JSON_MALFORMED
        # Make JSON unparseable by removing key structural elements
        data_stripped = strip(data)
        if length(data_stripped) > 0
            # Remove first character if it's a brace or bracket
            first_char = data_stripped[1]
            if first_char == '{' || first_char == '['
                corrupted = data_stripped[2:end]
            else
                # Just add invalid suffix
                corrupted = data_stripped * "{invalid"
            end
        else
            corrupted = data
        end
    end
    
    if config.log_injections
        @info "Data corruption injection" corruption_type=string(corruption_type) original_length=length(data) corrupted_length=length(corrupted)
    end
    
    return corrupted
end

"""
    inject_corrupted_json(data::String; config::ChaosConfig=default_config()) -> String

Inject corruption specifically for JSON data.

# Arguments
- `data::String`: JSON string to corrupt
- `config::ChaosConfig`: Chaos configuration

# Returns
- Corrupted JSON string
"""
function inject_corrupted_json(data::String; config::ChaosConfig=default_config())::String
    corruption_types = [:null_byte, :truncation, :garbage, :json_malformed]
    selected = rand(corruption_types)
    return inject_corruption(data, selected; config=config)
end

# ============================================================================
# Network Partition Simulation
# ============================================================================

"""
    simulate_network_partition(duration_ms::Int; config::ChaosConfig=default_config())

Simulate a network partition/failure.

# Arguments
- `duration_ms::Int`: Duration of partition in milliseconds
- `config::ChaosConfig`: Chaos configuration
"""
function simulate_network_partition(duration_ms::Int; config::ChaosConfig=default_config())
    if !config.enabled
        return
    end
    
    if config.log_injections
        @info "Network partition simulation started" duration_ms=duration_ms
    end
    
    # Sleep for the duration of the partition
    sleep(duration_ms / 1000.0)
    
    if config.log_injections
        @info "Network partition simulation ended"
    end
end

"""
    NetworkPartitionError - Error for network partition simulation
"""
struct NetworkPartitionError <: Exception
    message::String
end

"""
    with_network_partition(fn::Function; config::ChaosConfig=default_config())

Execute a function with simulated network partition.

# Arguments
- `fn::Function`: Function to execute
- `config::ChaosConfig`: Chaos configuration
"""
function with_network_partition(fn::Function; config::ChaosConfig=default_config())
    if config.enabled && rand() < config.timeout_probability
        if config.log_injections
            @info "Network partition triggered for function call"
        end
        throw(NetworkPartitionError("Simulated network partition"))
    end
    return fn()
end

# ============================================================================
# CPU Pressure Generation
# ============================================================================

"""
    inject_cpu_pressure(duration_ms::Int=1000; config::ChaosConfig=default_config())

Generate CPU pressure by performing computation.

# Arguments
- `duration_ms::Int`: Duration of CPU pressure in milliseconds
- `config::ChaosConfig`: Chaos configuration
"""
function inject_cpu_pressure(duration_ms::Int=1000; config::ChaosConfig=default_config())
    if !config.enabled
        return
    end
    
    start_time = time()
    iterations = 0
    
    # Perform CPU-intensive work
    while (time() - start_time) * 1000 < duration_ms
        # Some computation to burn CPU
        x = rand(Float64, 100, 100)
        y = x * x
        iterations += 1
    end
    
    if config.log_injections
        @info "CPU pressure injection" duration_ms=duration_ms iterations=iterations
    end
end

# ============================================================================
# Service Crash Simulation
# ============================================================================

"""
    CrashType - Types of service crashes

Options:
- :immediate - Immediate crash
- :delayed - Delayed crash after some operations
- :intermittent - Intermittent crashes
- :graceful - Graceful degradation
"""
@enum CrashType begin
    IMMEDIATE
    DELAYED
    INTERMITTENT
    GRACEFUL
end

"""
    ServiceCrashError - Error for service crash simulation
"""
struct ServiceCrashError <: Exception
    message::String
    crash_type::CrashType
end

"""
    should_crash(crash_type::Symbol; probability::Float64=0.1, config::ChaosConfig=default_config()) -> Bool

Determine if a service should crash based on probability.

# Arguments
- `crash_type::Symbol`: Type of crash
- `probability::Float64`: Probability of crash
- `config::ChaosConfig`: Chaos configuration

# Returns
- true if service should crash
"""
function should_crash(crash_type::Symbol; probability::Float64=0.1, config::ChaosConfig=default_config())::Bool
    if !config.enabled
        return false
    end
    return rand() < probability
end

"""
    simulate_service_crash(crash_type::Symbol=:immediate; config::ChaosConfig=default_config())

Simulate a service crash.

# Arguments
- `crash_type::Symbol`: Type of crash (:immediate, :delayed, :intermittent, :graceful)
- `config::ChaosConfig`: Chaos configuration

# Throws
- ServiceCrashError when crash is triggered
"""
function simulate_service_crash(crash_type::Symbol=:immediate; config::ChaosConfig=default_config())
    if !config.enabled
        return
    end
    
    if crash_type == :immediate || crash_type == IMMEDIATE
        throw(ServiceCrashError("Service crashed immediately", IMMEDIATE))
        
    elseif crash_type == :delayed || crash_type == DELAYED
        # Simulate delayed crash after some work
        throw(ServiceCrashError("Service crashed after delay", DELAYED))
        
    elseif crash_type == :intermittent || crash_type == INTERMITTENT
        # Simulate intermittent failure
        if rand() < 0.5
            throw(ServiceCrashError("Intermittent service failure", INTERMITTENT))
        end
        
    elseif crash_type == :graceful || crash_type == GRACEFUL
        # Simulate graceful degradation (not a crash per se)
        if config.log_injections
            @info "Graceful degradation mode entered"
        end
    end
end

# ============================================================================
# Chaos Experiment Management
# ============================================================================

# Global default config
const _default_config = Ref{ChaosConfig}(ChaosConfig())

"""
    default_config() -> ChaosConfig

Get the default chaos configuration.
"""
function default_config()::ChaosConfig
    return _default_config[]
end

"""
    set_default_config(config::ChaosConfig)

Set the default chaos configuration.
"""
function set_default_config(config::ChaosConfig)
    _default_config[] = config
end

"""
    create_experiment(name::String; description::String="", config::ChaosConfig=default_config()) -> ChaosExperiment

Create a new chaos experiment.

# Arguments
- `name::String`: Experiment name
- `description::String`: Experiment description
- `config::ChaosConfig`: Chaos configuration

# Returns
- New ChaosExperiment
"""
function create_experiment(name::String; description::String="", config::ChaosConfig=default_config())::ChaosExperiment
    return ChaosExperiment(name; description=description, config=config)
end

"""
    record_injection(experiment::ChaosExperiment, injection_type::String, details::Dict)

Record an injection event in an experiment.

# Arguments
- `experiment::ChaosExperiment`: Experiment to record in
- `injection_type::String`: Type of injection
- `details::Dict`: Details of the injection
"""
function record_injection!(experiment::ChaosExperiment, injection_type::String, details::Dict)
    push!(experiment.injections, Dict(
        "type" => injection_type,
        "timestamp" => now(),
        "details" => details
    ))
end

"""
    complete_experiment!(experiment::ChaosExperiment; results::Dict=Dict())

Complete a chaos experiment and record results.

# Arguments
- `experiment::ChaosExperiment`: Experiment to complete
- `results::Dict`: Final results
"""
function complete_experiment!(experiment::ChaosExperiment; results::Dict=Dict())
    experiment.ended_at = now()
    experiment.results = results
    
    # Calculate experiment duration
    duration = (experiment.ended_at - experiment.started_at).value / 1000.0
    experiment.results["duration_seconds"] = duration
    experiment.results["total_injections"] = length(experiment.injections)
end

"""
    get_experiment_summary(experiment::ChaosExperiment) -> Dict

Get a summary of an experiment.

# Arguments
- `experiment::ChaosExperiment`: Experiment to summarize

# Returns
- Summary dictionary
"""
function get_experiment_summary(experiment::ChaosExperiment)::Dict
    injection_types = Dict{String, Int}()
    for injection in experiment.injections
        t = injection["type"]
        injection_types[t] = get(injection_types, t, 0) + 1
    end
    
    return Dict(
        "id" => string(experiment.id),
        "name" => experiment.name,
        "description" => experiment.description,
        "started_at" => string(experiment.started_at),
        "ended_at" => experiment.ended_at !== nothing ? string(experiment.ended_at) : "in_progress",
        "total_injections" => length(experiment.injections),
        "injection_types" => injection_types,
        "results" => experiment.results
    )
end

# ============================================================================
# Decorator Patterns for Chaos Injection
# ============================================================================

"""
    with_chaos(fn::Function; config::ChaosConfig=default_config())

Execute a function with chaos injection enabled.

This is a convenience wrapper that may inject various failures based on config.

# Arguments
- `fn::Function`: Function to execute
- `config::ChaosConfig`: Chaos configuration
"""
function with_chaos(fn::Function; config::ChaosConfig=default_config())
    if !config.enabled
        return fn()
    end
    
    # Randomly decide which chaos to inject
    chaos_roll = rand()
    
    if chaos_roll < config.latency_probability
        inject_random_latency(; config=config)
    elseif chaos_roll < config.latency_probability + config.timeout_probability
        throw(TimeoutError("Random chaos timeout"))
    elseif chaos_roll < config.latency_probability + config.timeout_probability + config.corruption_probability
        throw(NetworkPartitionError("Random chaos network failure"))
    end
    
    return fn()
end

"""
    wrap_with_chaos(fn::Function, config::ChaosConfig=default_config()) -> Function

Wrap a function with chaos injection capabilities.

# Arguments
- `fn::Function`: Function to wrap
- `config::ChaosConfig`: Chaos configuration

# Returns
- Wrapped function
"""
function wrap_with_chaos(fn::Function, config::ChaosConfig=default_config())::Function
    return () -> with_chaos(fn; config=config)
end

# ============================================================================
# Integration with Resilience Patterns
# ============================================================================

"""
    inject_with_circuit_breaker(cb::Any, fn::Function; config::ChaosConfig=default_config())

Execute function with circuit breaker and chaos injection.

This combines chaos injection with circuit breaker pattern for comprehensive testing.

# Arguments
- `cb`: Circuit breaker (any type with is_available method)
- `fn::Function`: Function to execute
- `config::ChaosConfig`: Chaos configuration
"""
function inject_with_circuit_breaker(cb::Any, fn::Function; config::ChaosConfig=default_config())
    # Check circuit breaker first
    if !is_available(cb)
        throw(ErrorException("Circuit breaker is open"))
    end
    
    # Inject chaos
    return with_chaos(fn; config=config)
end

# ============================================================================
# Module Exports
# ============================================================================

export
    # Configuration
    ChaosConfig,
    ChaosExperiment,
    
    # Latency
    inject_latency,
    inject_random_latency,
    with_latency_injection,
    
    # Memory
    inject_memory_pressure,
    release_memory_pressure,
    get_memory_pressure_level,
    
    # Timeouts
    should_inject_timeout,
    inject_random_timeout,
    TimeoutError,
    
    # Partial Writes
    simulate_partial_write,
    simulate_partial_write_with_failure,
    
    # Corruption
    inject_corruption,
    inject_corrupted_json,
    CorruptionType,
    NULL_BYTE,
    TRUNCATION,
    GARBAGE,
    ENCODING,
    JSON_MALFORMED,
    
    # Network
    simulate_network_partition,
    with_network_partition,
    NetworkPartitionError,
    
    # CPU
    inject_cpu_pressure,
    
    # Service Crashes
    simulate_service_crash,
    should_crash,
    ServiceCrashError,
    CrashType,
    IMMEDIATE,
    DELAYED,
    INTERMITTENT,
    GRACEFUL,
    
    # Experiment Management
    default_config,
    set_default_config,
    create_experiment,
    record_injection!,
    complete_experiment!,
    get_experiment_summary,
    
    # Decorators
    with_chaos,
    wrap_with_chaos,
    inject_with_circuit_breaker

end  # module
