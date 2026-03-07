# adaptive-kernel/telemetry/MetricsCollector.jl - Metrics collection and reporting
# Collects: cognitive_metrics, system_metrics, security_metrics

module MetricsCollector

using Dates
using Statistics
using JSON
using Logging

# Export public API
export MetricsCollector, MetricsReport
export collect_cognitive_metrics, collect_system_metrics, collect_security_metrics
export generate_report, export_json, get_latest_metrics

# ============================================================================
# Core Types
# ============================================================================

"""
    CognitiveMetrics - Attention and entropy metrics
"""
struct CognitiveMetrics
    timestamp::DateTime
    attention_variance::Float64
    attention_focus_score::Float64  # 1.0 - variance
    policy_entropy::Float64
    decision_confidence::Float64
    cognitive_load::Float64
end

"""
    SystemMetrics - Energy and latency metrics
"""
struct SystemMetrics
    timestamp::DateTime
    energy_level::Float64
    latency_p50_ms::Float64
    latency_p99_ms::Float64
    throughput_ops::Float64
    memory_pressure::Float64
end

"""
    SecurityMetrics - Risk assessment metrics
"""
struct SecurityMetrics
    timestamp::DateTime
    tool_risk_score::Float64
    input_sanitization_rate::Float64
    confirmation_gate_pass_rate::Float64
    anomaly_detected::Bool
    threat_level::Float64  # 0.0 = safe, 1.0 = critical
end

"""
    MetricsReport - Complete metrics snapshot
"""
struct MetricsReport
    timestamp::DateTime
    cognitive::CognitiveMetrics
    system::SystemMetrics
    security::SecurityMetrics
    cycle_count::Int
    uptime_seconds::Float64
end

"""
    MetricsCollector - Aggregates and reports metrics
"""
mutable struct MetricsCollector
    # History storage
    cognitive_history::Vector{CognitiveMetrics}
    system_history::Vector{SystemMetrics}
    security_history::Vector{SecurityMetrics}
    max_history::Int
    
    # Integration references
    telemetry_engine::Any  # Optional TelemetryEngine reference
    
    # Reporting state
    last_report_time::DateTime
    report_interval::Int  # seconds
    
    # Metrics tracking
    cycle_count::Int
    start_time::DateTime
    
    function MetricsCollector(;
        history_size::Int=100,
        report_interval::Int=60)
        new(
            CognitiveMetrics[],
            SystemMetrics[],
            SecurityMetrics[],
            history_size,
            nothing,  # No telemetry engine by default
            now(),
            report_interval,
            0,
            now()
        )
    end
end

# ============================================================================
# Cognitive Metrics Collection
# ============================================================================

"""
    collect_cognitive_metrics(collector::MetricsCollector;
        attention_variance::Float64=0.0,
        policy_entropy::Float64=0.0,
        decision_confidence::Float64=0.5,
        cognitive_load::Float64=0.5)
Collect cognitive/attention metrics
"""
function collect_cognitive_metrics(collector::MetricsCollector;
    attention_variance::Float64=0.0,
    policy_entropy::Float64=0.0,
    decision_confidence::Float64=0.5,
    cognitive_load::Float64=0.5)
    
    # Calculate focus score (inverse of variance)
    attention_focus = clamp(1.0 - attention_variance, 0.0, 1.0)
    
    metrics = CognitiveMetrics(
        timestamp=now(),
        attention_variance=clamp(attention_variance, 0.0, 1.0),
        attention_focus_score=attention_focus,
        policy_entropy=clamp(policy_entropy, 0.0, 1.0),
        decision_confidence=clamp(decision_confidence, 0.0, 1.0),
        cognitive_load=clamp(cognitive_load, 0.0, 1.0)
    )
    
    push!(collector.cognitive_history, metrics)
    if length(collector.cognitive_history) > collector.max_history
        popfirst!(collector.cognitive_history)
    end
    
    return metrics
end

# ============================================================================
# System Metrics Collection
# ============================================================================

"""
    collect_system_metrics(collector::MetricsCollector;
        energy_level::Float64=1.0,
        latency_ms::Float64=0.0,
        throughput::Float64=0.0,
        memory_pressure::Float64=0.0)
Collect system/energy/latency metrics
"""
function collect_system_metrics(collector::MetricsCollector;
    energy_level::Float64=1.0,
    latency_ms::Float64=0.0,
    throughput::Float64=0.0,
    memory_pressure::Float64=0.0)
    
    # Get latency stats from recent measurements if available
    # For now, use the provided latency as p50 and estimate p99
    latency_p50 = latency_ms
    latency_p99 = latency_ms * 1.5  # Estimate
    
    metrics = SystemMetrics(
        timestamp=now(),
        energy_level=clamp(energy_level, 0.0, 1.0),
        latency_p50_ms=latency_p50,
        latency_p99_ms=latency_p99,
        throughput_ops=throughput,
        memory_pressure=clamp(memory_pressure, 0.0, 1.0)
    )
    
    push!(collector.system_history, metrics)
    if length(collector.system_history) > collector.max_history
        popfirst!(collector.system_history)
    end
    
    return metrics
end

# ============================================================================
# Security Metrics Collection
# ============================================================================

"""
    collect_security_metrics(collector::MetricsCollector;
        tool_risk_score::Float64=0.0,
        sanitization_rate::Float64=1.0,
        confirmation_rate::Float64=1.0,
        anomaly_detected::Bool=false,
        threat_level::Float64=0.0)
Collect security/risk metrics
"""
function collect_security_metrics(collector::MetricsCollector;
    tool_risk_score::Float64=0.0,
    sanitization_rate::Float64=1.0,
    confirmation_rate::Float64=1.0,
    anomaly_detected::Bool=false,
    threat_level::Float64=0.0)
    
    metrics = SecurityMetrics(
        timestamp=now(),
        tool_risk_score=clamp(tool_risk_score, 0.0, 1.0),
        input_sanitization_rate=clamp(sanitization_rate, 0.0, 1.0),
        confirmation_gate_pass_rate=clamp(confirmation_rate, 0.0, 1.0),
        anomaly_detected=anomaly_detected,
        threat_level=clamp(threat_level, 0.0, 1.0)
    )
    
    push!(collector.security_history, metrics)
    if length(collector.security_history) > collector.max_history
        popfirst!(collector.security_history)
    end
    
    return metrics
end

# ============================================================================
# Report Generation
# ============================================================================

"""
    generate_report(collector::MetricsCollector)::MetricsReport
Generate complete metrics report
"""
function generate_report(collector::MetricsCollector)::MetricsReport
    collector.cycle_count += 1
    collector.last_report_time = now()
    
    # Get latest metrics or use defaults
    cognitive = if isempty(collector.cognitive_history)
        CognitiveMetrics(now(), 0.0, 1.0, 0.0, 0.5, 0.5)
    else
        collector.cognitive_history[end]
    end
    
    system = if isempty(collector.system_history)
        SystemMetrics(now(), 1.0, 0.0, 0.0, 0.0, 0.0)
    else
        collector.system_history[end]
    end
    
    security = if isempty(collector.security_history)
        SecurityMetrics(now(), 0.0, 1.0, 1.0, false, 0.0)
    else
        collector.security_history[end]
    end
    
    uptime = (now() - collector.start_time).value / 1000.0
    
    return MetricsReport(
        timestamp=now(),
        cognitive=cognitive,
        system=system,
        security=security,
        cycle_count=collector.cycle_count,
        uptime_seconds=uptime
    )
end

"""
    export_json(report::MetricsReport)::String
Export metrics report as JSON
"""
function export_json(report::MetricsReport)::String
    data = Dict(
        "timestamp" => string(report.timestamp),
        "cognitive" => Dict(
            "attention_variance" => report.cognitive.attention_variance,
            "attention_focus_score" => report.cognitive.attention_focus_score,
            "policy_entropy" => report.cognitive.policy_entropy,
            "decision_confidence" => report.cognitive.decision_confidence,
            "cognitive_load" => report.cognitive.cognitive_load
        ),
        "system" => Dict(
            "energy_level" => report.system.energy_level,
            "latency_p50_ms" => report.system.latency_p50_ms,
            "latency_p99_ms" => report.system.latency_p99_ms,
            "throughput_ops" => report.system.throughput_ops,
            "memory_pressure" => report.system.memory_pressure
        ),
        "security" => Dict(
            "tool_risk_score" => report.security.tool_risk_score,
            "input_sanitization_rate" => report.security.input_sanitization_rate,
            "confirmation_gate_pass_rate" => report.security.confirmation_gate_pass_rate,
            "anomaly_detected" => report.security.anomaly_detected,
            "threat_level" => report.security.threat_level
        ),
        "cycle_count" => report.cycle_count,
        "uptime_seconds" => report.uptime_seconds
    )
    
    return JSON.json(data)
end

"""
    get_latest_metrics(collector::MetricsCollector)
Get latest collected metrics (convenience function)
"""
function get_latest_metrics(collector::MetricsCollector)
    return generate_report(collector)
end

# ============================================================================
# Integration with Telemetry Engine
# ============================================================================

"""
    set_telemetry_engine!(collector::MetricsCollector, engine)
Link MetricsCollector to TelemetryEngine for data sharing
"""
function set_telemetry_engine!(collector::MetricsCollector, engine)
    collector.telemetry_engine = engine
    @info "MetricsCollector linked to TelemetryEngine"
end

"""
    sync_from_telemetry!(collector::MetricsCollector)
Sync metrics from linked TelemetryEngine
"""
function sync_from_telemetry!(collector::MetricsCollector)
    if collector.telemetry_engine !== nothing
        engine = collector.telemetry_engine
        snapshot = get_snapshot(engine)
        
        # Sync cognitive metrics
        collect_cognitive_metrics(collector;
            attention_variance=snapshot.attention_variance,
            policy_entropy=snapshot.policy_entropy,
            cognitive_load=snapshot.cognitive_load
        )
        
        # Sync system metrics
        collect_system_metrics(collector;
            energy_level=snapshot.energy_state,
            latency_ms=snapshot.latency_p50
        )
        
        # Sync security metrics
        collect_security_metrics(collector;
            tool_risk_score=snapshot.tool_execution_risk
        )
    end
end

end # module
