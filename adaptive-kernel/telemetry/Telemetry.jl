# adaptive-kernel/telemetry/Telemetry.jl - Central telemetry system
# Monitors: attention variance, policy entropy, energy state, latency, tool execution risk

module Telemetry

using Dates
using Statistics
using Logging

# Export public API
export TelemetryEngine, TelemetrySnapshot
export record_attention_variance, record_policy_entropy, record_energy_state
export record_latency, record_tool_risk, get_snapshot
export start_telemetry, stop_telemetry

# ============================================================================
# Core Types
# ============================================================================

"""
    TelemetrySnapshot - Point-in-time telemetry data
"""
struct TelemetrySnapshot
    timestamp::DateTime
    attention_variance::Float64
    policy_entropy::Float64
    energy_state::Float64  # 0.0 = depleted, 1.0 = full
    latency_p50::Float64   # milliseconds
    latency_p99::Float64   # milliseconds
    tool_execution_risk::Float64  # 0.0 = safe, 1.0 = high risk
    cognitive_load::Float64
end

"""
    TelemetryEngine - Central telemetry collection and aggregation
"""
mutable struct TelemetryEngine
    # Attention tracking
    attention_history::Vector{Float64}
    max_attention_history::Int
    
    # Policy entropy tracking
    entropy_history::Vector{Float64}
    max_entropy_history::Int
    
    # Energy state
    current_energy::Float64
    
    # Latency tracking
    latency_history::Vector{Float64}
    max_latency_history::Int
    
    # Risk tracking
    risk_history::Vector{Float64}
    max_risk_history::Int
    
    # Cognitive load
    cognitive_load::Float64
    
    # State
    is_running::Bool
    last_update::DateTime
    
    function TelemetryEngine(;
        attention_history_size::Int=100,
        entropy_history_size::Int=100,
        latency_history_size::Int=1000,
        risk_history_size::Int=100)
        new(
            Float64[],
            attention_history_size,
            Float64[],
            entropy_history_size,
            1.0,  # Start with full energy
            Float64[],
            latency_history_size,
            Float64[],
            risk_history_size,
            0.5,  # Default cognitive load
            false,
            now()
        )
    end
end

# ============================================================================
# Core Recording Functions
# ============================================================================

"""
    record_attention_variance!(engine::TelemetryEngine, variance::Float64)
Record attention variance (0.0 = focused, 1.0 = highly scattered)
"""
function record_attention_variance!(engine::TelemetryEngine, variance::Float64)
    push!(engine.attention_history, variance)
    if length(engine.attention_history) > engine.max_attention_history
        popfirst!(engine.attention_history)
    end
    engine.last_update = now()
end

"""
    record_policy_entropy!(engine::TelemetryEngine, entropy::Float64)
Record policy entropy (0.0 = deterministic, 1.0 = random)
"""
function record_policy_entropy!(engine::TelemetryEngine, entropy::Float64)
    push!(engine.entropy_history, entropy)
    if length(engine.entropy_history) > engine.max_entropy_history
        popfirst!(engine.entropy_history)
    end
    engine.last_update = now()
end

"""
    record_energy_state!(engine::TelemetryEngine, energy::Float64)
Record current energy state (0.0 = depleted, 1.0 = full)
"""
function record_energy_state!(engine::TelemetryEngine, energy::Float64)
    engine.current_energy = clamp(energy, 0.0, 1.0)
    engine.last_update = now()
end

"""
    record_latency!(engine::TelemetryEngine, latency_ms::Float64)
Record operation latency in milliseconds
"""
function record_latency!(engine::TelemetryEngine, latency_ms::Float64)
    push!(engine.latency_history, latency_ms)
    if length(engine.latency_history) > engine.max_latency_history
        popfirst!(engine.latency_history)
    end
    engine.last_update = now()
end

"""
    record_tool_risk!(engine::TelemetryEngine, risk::Float64)
Record tool execution risk (0.0 = safe, 1.0 = high risk)
"""
function record_tool_risk!(engine::TelemetryEngine, risk::Float64)
    push!(engine.risk_history, clamp(risk, 0.0, 1.0))
    if length(engine.risk_history) > engine.max_risk_history
        popfirst!(engine.risk_history)
    end
    engine.last_update = now()
end

"""
    set_cognitive_load!(engine::TelemetryEngine, load::Float64)
Set current cognitive load (0.0 = idle, 1.0 = saturated)
"""
function set_cognitive_load!(engine::TelemetryEngine, load::Float64)
    engine.cognitive_load = clamp(load, 0.0, 1.0)
    engine.last_update = now()
end

# ============================================================================
# Snapshot Generation
# ============================================================================

"""
    get_snapshot(engine::TelemetryEngine)::TelemetrySnapshot
Generate current telemetry snapshot with aggregated metrics
"""
function get_snapshot(engine::TelemetryEngine)::TelemetrySnapshot
    # Calculate attention variance
    attention_var = if isempty(engine.attention_history)
        0.0
    else
        var(engine.attention_history)
    end
    
    # Calculate average entropy
    avg_entropy = if isempty(engine.entropy_history)
        0.0
    else
        mean(engine.entropy_history)
    end
    
    # Calculate latency percentiles
    latency_p50, latency_p99 = if isempty(engine.latency_history)
        (0.0, 0.0)
    else
        sorted_latencies = sort(engine.latency_history)
        p50_idx = max(1, ceil(Int, length(sorted_latencies) * 0.50))
        p99_idx = max(1, ceil(Int, length(sorted_latencies) * 0.99))
        (sorted_latencies[p50_idx], sorted_latencies[p99_idx])
    end
    
    # Average risk
    avg_risk = if isempty(engine.risk_history)
        0.0
    else
        mean(engine.risk_history)
    end
    
    TelemetrySnapshot(
        timestamp=now(),
        attention_variance=attention_var,
        policy_entropy=avg_entropy,
        energy_state=engine.current_energy,
        latency_p50=latency_p50,
        latency_p99=latency_p99,
        tool_execution_risk=avg_risk,
        cognitive_load=engine.cognitive_load
    )
end

# ============================================================================
# Engine Control
# ============================================================================

"""
    start_telemetry(engine::TelemetryEngine)
Start telemetry collection
"""
function start_telemetry(engine::TelemetryEngine)
    engine.is_running = true
    engine.last_update = now()
    @info "Telemetry engine started"
end

"""
    stop_telemetry(engine::TelemetryEngine)
Stop telemetry collection
"""
function stop_telemetry(engine::TelemetryEngine)
    engine.is_running = false
    @info "Telemetry engine stopped"
end

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    record_attention_variance(engine::TelemetryEngine, variance::Float64)
Alias for record_attention_variance! for API consistency
"""
record_attention_variance(args...) = record_attention_variance!(args...)

"""
    record_policy_entropy(engine::TelemetryEngine, entropy::Float64)
Alias for record_policy_entropy! for API consistency
"""
record_policy_entropy(args...) = record_policy_entropy!(args...)

"""
    record_energy_state(engine::TelemetryEngine, energy::Float64)
Alias for record_energy_state! for API consistency
"""
record_energy_state(args...) = record_energy_state!(args...)

"""
    record_latency(engine::TelemetryEngine, latency_ms::Float64)
Alias for record_latency! for API consistency
"""
record_latency(args...) = record_latency!(args...)

"""
    record_tool_risk(engine::TelemetryEngine, risk::Float64)
Alias for record_tool_risk! for API consistency
"""
record_tool_risk(args...) = record_tool_risk!(args...)

end # module
