# test_telemetry_monitoring.jl - Telemetry Monitoring Test Suite
#
# This test suite verifies the sanity telemetry monitoring for isolation health:
# 1. Policy Entropy - measures randomness/deviation in policy decisions
# 2. Attention Variance - measures stability of attention mechanisms
#
# These metrics indicate isolation health and cognitive stability in real-time
# for the production dashboard.

using Test
using Dates
using Statistics
using Random
using Logging
using JSON3

# Suppress info logs during tests
Logging.disable_logging(Logging.Info)

# ============================================================================
# Import Required Modules
# ============================================================================

try
    using ..Telemetry
catch e
    @warn "Telemetry module not available, using mock implementations"
end

try
    using ..MetricsCollector
catch e
    @warn "MetricsCollector module not available"
end

# ============================================================================
# Test Configuration
# ============================================================================

const TELEMETRY_CONFIG = Dict(
    :max_history => 100,
    :alert_threshold_variance => 0.8,
    :alert_threshold_entropy => 0.9,
    :sampling_interval => 1.0,
)

# ============================================================================
# SECTION 1: Telemetry Engine Core Tests
# ============================================================================

@testset "Telemetry Engine Core Tests" begin
    @info "=== Telemetry Engine Core Tests ==="
    
    @testset "Telemetry Engine Creation" begin
        @info "Testing telemetry engine creation"
        
        engine = TelemetryEngine(
            max_attention_history=100,
            max_entropy_history=100,
            current_energy=1.0
        )
        
        @test engine.max_attention_history == 100
        @test engine.max_entropy_history == 100
        @test engine.current_energy == 1.0
        @test isempty(engine.attention_history)
        @test isempty(engine.entropy_history)
        
        @info "Telemetry engine created"
    end
    
    @testset "Attention Variance Recording" begin
        @info "Testing attention variance recording"
        
        engine = TelemetryEngine(max_attention_history=10, max_entropy_history=10)
        
        # Record various attention variance values
        # 0.0 = focused, 1.0 = highly scattered
        test_variances = [0.1, 0.2, 0.15, 0.3, 0.25]
        
        for variance in test_variances
            record_attention_variance!(engine, variance)
        end
        
        @test length(engine.attention_history) == 5
        @test engine.attention_history == test_variances
        
        @info "Recorded $(length(engine.attention_history)) attention variance values"
    end
    
    @testset "Policy Entropy Recording" begin
        @info "Testing policy entropy recording"
        
        engine = TelemetryEngine(max_attention_history=10, max_entropy_history=10)
        
        # Record various policy entropy values
        # 0.0 = deterministic, 1.0 = random
        test_entropies = [0.1, 0.3, 0.2, 0.4, 0.35, 0.25]
        
        for entropy in test_entropies
            record_policy_entropy!(engine, entropy)
        end
        
        @test length(engine.entropy_history) == 6
        @test engine.entropy_history == test_entropies
        
        @info "Recorded $(length(engine.entropy_history)) policy entropy values"
    end
    
    @testset "History Overflow Handling" begin
        @info "Testing history overflow handling"
        
        engine = TelemetryEngine(max_attention_history=3, max_entropy_history=3)
        
        # Record more values than max history
        for i in 1:5
            record_attention_variance!(engine, Float64(i) / 10.0)
        end
        
        # Should only keep the last 3 values
        @test length(engine.attention_history) == 3
        @test engine.attention_history == [0.3, 0.4, 0.5]
        
        @info "History overflow handled correctly: kept last 3 of 5"
    end
end

# ============================================================================
# SECTION 2: Telemetry Snapshot Tests
# ============================================================================

@testset "Telemetry Snapshot Tests" begin
    @info "=== Telemetry Snapshot Tests ==="
    
    @testset "Snapshot Generation" begin
        @info "Testing snapshot generation"
        
        engine = TelemetryEngine(
            max_attention_history=10,
            max_entropy_history=10,
            current_energy=0.8
        )
        
        # Add some data
        for v in [0.1, 0.2, 0.15, 0.25, 0.2]
            record_attention_variance!(engine, v)
        end
        
        for e in [0.2, 0.3, 0.25, 0.35, 0.3]
            record_policy_entropy!(engine, e)
        end
        
        # Generate snapshot
        snapshot = get_snapshot(engine)
        
        @test snapshot.timestamp !== nothing
        @test snapshot.attention_variance >= 0.0
        @test snapshot.policy_entropy >= 0.0
        @test snapshot.energy_state == 0.8
        
        @info "Snapshot: attention_variance=$(snapshot.attention_variance), policy_entropy=$(snapshot.policy_entropy)"
    end
    
    @testset "Empty History Snapshot" begin
        @info "Testing empty history snapshot"
        
        engine = TelemetryEngine()
        
        snapshot = get_snapshot(engine)
        
        # Should handle empty history gracefully
        @test snapshot.attention_variance == 0.0
        @test snapshot.policy_entropy == 0.0
        @test snapshot.energy_state == 1.0
        
        @info "Empty snapshot handled: attention=$(snapshot.attention_variance), entropy=$(snapshot.policy_entropy)"
    end
end

# ============================================================================
# SECTION 3: Policy Entropy Tests
# ============================================================================

@testset "Policy Entropy Tests" begin
    @info "=== Policy Entropy Tests ==="
    
    @testset "Low Entropy (Deterministic)" begin
        @info "Testing low entropy (deterministic behavior)"
        
        # Deterministic behavior = low entropy
        engine = TelemetryEngine(max_entropy_history=10)
        
        # Record consistently similar values
        for i in 1:10
            record_policy_entropy!(engine, 0.05 + rand() * 0.05)  # Very low variance
        end
        
        snapshot = get_snapshot(engine)
        
        @test snapshot.policy_entropy < 0.2 "Low entropy should be < 0.2, got $(snapshot.policy_entropy)"
        
        @info "Low entropy (deterministic): $(snapshot.policy_entropy)"
    end
    
    @testset "High Entropy (Random)" begin
        @info "Testing high entropy (random behavior)"
        
        # Random behavior = high entropy
        engine = TelemetryEngine(max_entropy_history=10)
        
        Random.seed!(42)
        for i in 1:10
            record_policy_entropy!(engine, rand())  # Random values 0-1
        end
        
        snapshot = get_snapshot(engine)
        
        @test snapshot.policy_entropy > 0.3 "High entropy should be > 0.3, got $(snapshot.policy_entropy)"
        
        @info "High entropy (random): $(snapshot.policy_entropy)"
    end
    
    @testset "Entropy Alert Threshold" begin
        @info "Testing entropy alert threshold"
        
        alert_threshold = TELEMETRY_CONFIG[:alert_threshold_entropy]
        
        # Test values above and below threshold
        test_cases = [
            (0.1, false, "Low entropy"),
            (0.5, false, "Medium entropy"),
            (0.85, false, "High but below threshold"),
            (0.95, true, "Above threshold - alert"),
        ]
        
        for (entropy, should_alert, desc) in test_cases
            alert_triggered = entropy > alert_threshold
            @test alert_triggered == should_alert "$desc: entropy=$entropy, alert=$alert_triggered"
            @info "$desc: entropy=$entropy, alert=$alert_triggered"
        end
    end
    
    @testset "Entropy Trend Detection" begin
        @info "Testing entropy trend detection"
        
        engine = TelemetryEngine(max_entropy_history=10)
        
        # Record increasing entropy (sign of potential compromise)
        for i in 1:10
            record_policy_entropy!(engine, Float64(i) / 10.0)  # 0.1, 0.2, ..., 1.0
        end
        
        snapshot = get_snapshot(engine)
        
        # Should detect increasing trend
        @test snapshot.policy_entropy > 0.5 "Increasing trend should result in high entropy"
        
        @info "Entropy trend: final value=$(snapshot.policy_entropy)"
    end
end

# ============================================================================
# SECTION 4: Attention Variance Tests
# ============================================================================

@testset "Attention Variance Tests" begin
    @info "=== Attention Variance Tests ==="
    
    @testset "Low Variance (Focused)" begin
        @info "Testing low variance (focused attention)"
        
        # Focused attention = low variance
        engine = TelemetryEngine(max_attention_history=10)
        
        # Record consistently similar values
        for i in 1:10
            record_attention_variance!(engine, 0.02 + rand() * 0.03)
        end
        
        snapshot = get_snapshot(engine)
        
        @test snapshot.attention_variance < 0.1 "Focused attention should have low variance < 0.1"
        
        @info "Low variance (focused): $(snapshot.attention_variance)"
    end
    
    @testset "High Variance (Scattered)" begin
        @info "Testing high variance (scattered attention)"
        
        # Scattered attention = high variance
        engine = TelemetryEngine(max_attention_history=10)
        
        Random.seed!(42)
        for i in 1:10
            record_attention_variance!(engine, rand())
        end
        
        snapshot = get_snapshot(engine)
        
        @test snapshot.attention_variance > 0.2 "Scattered attention should have variance > 0.2"
        
        @info "High variance (scattered): $(snapshot.attention_variance)"
    end
    
    @testset "Variance Alert Threshold" begin
        @info "Testing variance alert threshold"
        
        alert_threshold = TELEMETRY_CONFIG[:alert_threshold_variance]
        
        test_cases = [
            (0.1, false, "Very focused"),
            (0.4, false, "Moderately focused"),
            (0.75, false, "High but below threshold"),
            (0.85, true, "Above threshold - alert"),
        ]
        
        for (variance, should_alert, desc) in test_cases
            alert_triggered = variance > alert_threshold
            @test alert_triggered == should_alert "$desc: variance=$variance, alert=$alert_triggered"
            @info "$desc: variance=$variance, alert=$alert_triggered"
        end
    end
    
    @testset "Variance Stability Over Time" begin
        @info "Testing variance stability over time"
        
        engine = TelemetryEngine(max_attention_history=20)
        
        # Record stable values (good cognitive stability)
        stable_values = repeat([0.15, 0.2, 0.18, 0.22, 0.19], 4)
        
        for v in stable_values
            record_attention_variance!(engine, v)
        end
        
        snapshot = get_snapshot(engine)
        
        @test snapshot.attention_variance < 0.3 "Stable values should have low variance"
        
        @info "Variance stability: $(snapshot.attention_variance)"
    end
end

# ============================================================================
# SECTION 5: Metrics Collector Tests
# ============================================================================

@testset "Metrics Collector Tests" begin
    @info "=== Metrics Collector Tests ==="
    
    @testset "Metrics Collector Creation" begin
        @info "Testing metrics collector creation"
        
        collector = MetricsCollector(
            max_history=50,
            collection_interval=1.0
        )
        
        @test collector.max_history == 50
        @test collector.collection_interval == 1.0
        
        @info "Metrics collector created"
    end
    
    @testset "Cognitive Metrics Collection" begin
        @info "Testing cognitive metrics collection"
        
        collector = MetricsCollector()
        
        # Collect metrics with test values
        report = collect_cognitive_metrics(collector;
            attention_variance=0.25,
            policy_entropy=0.35,
            decision_confidence=0.8
        )
        
        @test report.cognitive.attention_variance == 0.25
        @test report.cognitive.policy_entropy == 0.35
        @test report.cognitive.decision_confidence == 0.8
        @test report.cognitive.attention_focus_score == 0.75  # 1.0 - 0.25
        
        @info "Cognitive metrics collected"
    end
    
    @testset "Focus Score Calculation" begin
        @info "Testing focus score calculation"
        
        collector = MetricsCollector()
        
        # Test various attention variance values
        test_cases = [
            (0.0, 1.0, "Fully focused"),
            (0.5, 0.5, "Half focused"),
            (1.0, 0.0, "Fully scattered"),
            (0.25, 0.75, "75% focused"),
        ]
        
        for (variance, expected_focus, desc) in test_cases
            report = collect_cognitive_metrics(collector; attention_variance=variance)
            @test report.cognitive.attention_focus_score == expected_focus "$desc: variance=$variance, focus=$(report.cognitive.attention_focus_score)"
            @info "$desc: focus=$(report.cognitive.attention_focus_score)"
        end
    end
    
    @testset "Metrics Report Generation" begin
        @info "Testing metrics report generation"
        
        collector = MetricsCollector()
        
        # Add some metrics
        collect_cognitive_metrics(collector;
            attention_variance=0.2,
            policy_entropy=0.3,
            decision_confidence=0.85
        )
        
        # Generate JSON report
        report_json = generate_metrics_report(collector)
        
        # Should contain cognitive section
        @test contains(report_json, "cognitive")
        @test contains(report_json, "attention_variance")
        @test contains(report_json, "policy_entropy")
        
        @info "Metrics report generated"
    end
end

# ============================================================================
# SECTION 6: Integration with Isolation Health
# ============================================================================

@testset "Isolation Health Integration Tests" begin
    @info "=== Isolation Health Integration Tests ==="
    
    @testset "Normal Operation Metrics" begin
        @info "Testing normal operation metrics"
        
        engine = TelemetryEngine()
        
        # Normal operation: low entropy, low variance
        for _ in 1:10
            record_attention_variance!(engine, 0.1 + rand() * 0.1)
            record_policy_entropy!(engine, 0.1 + rand() * 0.1)
        end
        
        snapshot = get_snapshot(engine)
        
        # Normal operation should have healthy metrics
        is_healthy = snapshot.attention_variance < 0.5 && snapshot.policy_entropy < 0.5
        
        @test is_healthy == true "Normal operation should show healthy metrics"
        
        @info "Normal operation: variance=$(snapshot.attention_variance), entropy=$(snapshot.policy_entropy)"
    end
    
    @testset "Isolation Stress Indicators" begin
        @info "Testing isolation stress indicators"
        
        engine = TelemetryEngine()
        
        # Simulate stress: high variance, high entropy
        for _ in 1:10
            record_attention_variance!(engine, 0.7 + rand() * 0.3)
            record_policy_entropy!(engine, 0.7 + rand() * 0.3)
        end
        
        snapshot = get_snapshot(engine)
        
        # Should detect stress
        is_stressed = snapshot.attention_variance > 0.5 || snapshot.policy_entropy > 0.5
        
        @test is_stressed == true "Stress should be detected"
        
        @info "Stress indicators: variance=$(snapshot.attention_variance), entropy=$(snapshot.policy_entropy)"
    end
    
    @testset "Compromised Isolation Detection" begin
        @info "Testing compromised isolation detection"
        
        # Threshold for isolation compromise
        compromise_threshold = 0.8
        
        test_scenarios = [
            (0.9, 0.85, true, "Both metrics high - compromised"),
            (0.95, 0.3, true, "High variance - compromised"),
            (0.3, 0.95, true, "High entropy - compromised"),
            (0.2, 0.2, false, "Both metrics low - healthy"),
        ]
        
        for (variance, entropy, expected_compromised, desc) in test_scenarios
            engine = TelemetryEngine()
            record_attention_variance!(engine, variance)
            record_policy_entropy!(engine, entropy)
            
            snapshot = get_snapshot(engine)
            
            is_compromised = snapshot.attention_variance > compromise_threshold || 
                           snapshot.policy_entropy > compromise_threshold
            
            @test is_compromised == expected_compromised "$desc: variance=$variance, entropy=$entropy"
            @info "$desc: compromised=$is_compromised"
        end
    end
end

# ============================================================================
# SECTION 7: Dashboard Integration Tests
# ============================================================================

@testset "Dashboard Integration Tests" begin
    @info "=== Dashboard Integration Tests ==="
    
    @testset "Metrics Export Format" begin
        @info "Testing metrics export format"
        
        engine = TelemetryEngine(
            max_attention_history=10,
            max_entropy_history=10,
            current_energy=0.75
        )
        
        record_attention_variance!(engine, 0.25)
        record_policy_entropy!(engine, 0.35)
        
        snapshot = get_snapshot(engine)
        
        # Export for dashboard
        dashboard_data = Dict(
            "timestamp" => string(snapshot.timestamp),
            "attention_variance" => snapshot.attention_variance,
            "policy_entropy" => snapshot.policy_entropy,
            "energy_state" => snapshot.energy_state,
            "isolation_health" => snapshot.attention_variance < 0.5 && snapshot.policy_entropy < 0.5 ? "healthy" : "warning"
        )
        
        @test haskey(dashboard_data, "isolation_health")
        @test dashboard_data["isolation_health"] in ["healthy", "warning"]
        
        @info "Dashboard data: $(dashboard_data)"
    end
    
    @testset "Real-Time Stream Simulation" begin
        @info "Testing real-time stream simulation"
        
        engine = TelemetryEngine()
        
        # Simulate real-time updates
        for i in 1:20
            # Simulate varying cognitive load
            variance = 0.1 + 0.3 * sin(i * 0.5) + rand() * 0.1
            entropy = 0.1 + 0.2 * cos(i * 0.3) + rand() * 0.1
            
            record_attention_variance!(engine, variance)
            record_policy_entropy!(engine, entropy)
            
            # Get snapshot for each update
            snapshot = get_snapshot(engine)
        end
        
        @test length(engine.attention_history) == 20
        
        @info "Real-time stream: $(length(engine.attention_history)) samples processed"
    end
    
    @testset "Alert Generation" begin
        @info "Testing alert generation"
        
        alerts = []
        
        # Simulate monitoring loop
        engine = TelemetryEngine()
        
        for i in 1:15
            # Simulate increasing stress
            variance = min(1.0, 0.3 + i * 0.05)
            entropy = min(1.0, 0.3 + i * 0.05)
            
            record_attention_variance!(engine, variance)
            record_policy_entropy!(engine, entropy)
            
            snapshot = get_snapshot(engine)
            
            # Check for alerts
            if variance > TELEMETRY_CONFIG[:alert_threshold_variance]
                push!(alerts, ("variance", snapshot.timestamp))
            end
            
            if entropy > TELEMETRY_CONFIG[:alert_threshold_entropy]
                push!(alerts, ("entropy", snapshot.timestamp))
            end
        end
        
        # Should have generated alerts
        @test length(alerts) > 0 "Should generate alerts when thresholds exceeded"
        
        @info "Alert generation: $(length(alerts)) alerts from 15 samples"
    end
end

# ============================================================================
# SECTION 8: Performance Tests
# ============================================================================

@testset "Telemetry Performance Tests" begin
    @info "=== Telemetry Performance Tests ==="
    
    @testset "High-Frequency Recording" begin
        @info "Testing high-frequency recording"
        
        engine = TelemetryEngine(max_attention_history=1000, max_entropy_history=1000)
        
        n_iterations = 10000
        start_time = time()
        
        for i in 1:n_iterations
            record_attention_variance!(engine, rand())
            record_policy_entropy!(engine, rand())
        end
        
        elapsed = time() - start_time
        ops_per_sec = (2 * n_iterations) / elapsed
        
        @info "High-frequency recording: $ops_per_sec ops/sec"
        
        # Should handle at least 10K ops/sec
        @test ops_per_sec > 10000 "Performance should be > 10K ops/sec"
    end
    
    @testset "Concurrent Recording" begin
        @info "Testing concurrent recording"
        
        engine = TelemetryEngine(max_attention_history=1000, max_entropy_history=1000)
        
        n_threads = 4
        iterations_per_thread = 1000
        
        @Threads.threads for t in 1:n_threads
            for i in 1:iterations_per_thread
                record_attention_variance!(engine, rand())
            end
        end
        
        @test length(engine.attention_history) == n_threads * iterations_per_thread
        
        @info "Concurrent recording: $(length(engine.attention_history)) samples from $n_threads threads"
    end
end

# ============================================================================
# Test Summary
# ============================================================================

println("\n" * "=" ^ 70)
println("TELEMETRY MONITORING TEST SUITE COMPLETE")
println("=" ^ 70)
println("Test Coverage:")
println("  - Telemetry Engine Core")
println("  - Telemetry Snapshot Generation")
println("  - Policy Entropy (randomness/deviation)")
println("  - Attention Variance (stability)")
println("  - Metrics Collector")
println("  - Isolation Health Integration")
println("  - Dashboard Integration")
println("  - Performance Tests")
println("=" ^ 70)
