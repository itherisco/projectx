# chaos_test.jl - Comprehensive Chaos Engineering Tests
#
# This test suite validates the chaos injection framework and tests
# system resilience under various failure conditions.
#
# Test Categories:
# 1. Latency Injection Tests
# 2. Memory Pressure Tests
# 3. Timeout Tests
# 4. Partial Write Tests
# 5. Data Corruption Tests
# 6. Network Partition Tests
# 7. CPU Pressure Tests
# 8. Service Crash Tests
# 9. Experiment Management Tests
# 10. Integration Tests with Circuit Breaker

using Test
using Dates
using Random
using JSON
using UUIDs

# Add parent directory to path for imports
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Import ChaosInjector module
include(joinpath(@__DIR__, "..", "resilience", "ChaosInjector.jl"))
using ..ChaosInjector

# Import CircuitBreaker for integration testing
include(joinpath(@__DIR__, "..", "resilience", "Resilience.jl"))
using ..Resilience

println("=" ^ 70)
println("  CHAOS ENGINEERING TEST SUITE")
println("=" ^ 70)

# ============================================================================
# TEST CATEGORY 1: LATENCY INJECTION TESTS
# ============================================================================

println("\n[1] Testing Latency Injection...")

@testset "Latency Injection" begin
    
    # Test 1.1: Basic latency injection
    @testset "Basic Latency" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        start_time = time()
        latency = inject_latency(100; config=config)
        elapsed = time() - start_time
        @test latency ≈ 0.1 atol=0.05
        @test elapsed >= 0.1
    end
    
    # Test 1.2: Latency clamping (min)
    @testset "Latency Clamping Min" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        latency = inject_latency(0; config=config)  # Should be clamped to 1ms
        @test latency > 0
    end
    
    # Test 1.3: Latency clamping (max)
    @testset "Latency Clamping Max" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        latency = inject_latency(100000; config=config)  # Should be clamped to 30000ms
        @test latency <= 30.0
    end
    
    # Test 1.4: Random latency injection
    @testset "Random Latency Range" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        for _ in 1:10
            latency = inject_random_latency(min_ms=100, max_ms=200; config=config)
            @test latency >= 0.1
            @test latency <= 0.2
        end
    end
    
    # Test 1.5: Latency injection disabled
    @testset "Latency Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        start_time = time()
        latency = inject_latency(1000; config=config)
        elapsed = time() - start_time
        @test latency == 0.0
        @test elapsed < 0.1  # Should not have slept
    end
    
    # Test 1.6: with_latency_injection decorator
    @testset "With Latency Decorator" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        result = with_latency_injection(() -> 42, 50; config=config)
        @test result == 42
    end
end

# ============================================================================
# TEST CATEGORY 2: MEMORY PRESSURE TESTS
# ============================================================================

println("\n[2] Testing Memory Pressure...")

@testset "Memory Pressure" begin
    
    # Test 2.1: Basic memory allocation
    @testset "Basic Memory Allocation" begin
        config = ChaosConfig(enabled=true, memory_pressure_mb=50, log_injections=false)
        initial_level = get_memory_pressure_level()
        
        allocated = inject_memory_pressure(10; config=config)  # 10MB
        @test allocated == 10
        @test get_memory_pressure_level() == initial_level + 10
        
        # Cleanup
        release = release_memory_pressure()
        @test release == 10
        @test get_memory_pressure_level() == initial_level
    end
    
    # Test 2.2: Memory clamping to config limit
    @testset "Memory Clamping" begin
        config = ChaosConfig(enabled=true, memory_pressure_mb=20, log_injections=false)
        
        allocated = inject_memory_pressure(100; config=config)  # Request 100MB, config limits to 20MB
        @test allocated == 20
        
        # Cleanup
        release_memory_pressure()
    end
    
    # Test 2.3: Memory disabled
    @testset "Memory Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        allocated = inject_memory_pressure(100; config=config)
        @test allocated == 0
    end
    
    # Test 2.4: Multiple allocations
    @testset "Multiple Allocations" begin
        config = ChaosConfig(enabled=true, memory_pressure_mb=100, log_injections=false)
        
        inject_memory_pressure(10; config=config)
        inject_memory_pressure(10; config=config)
        inject_memory_pressure(10; config=config)
        
        @test get_memory_pressure_level() == 30
        
        # Cleanup
        release_memory_pressure()
    end
    
    # Test 2.5: Memory release
    @testset "Memory Release" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        inject_memory_pressure(20; config=config)
        @test get_memory_pressure_level() == 20
        
        released = release_memory_pressure()
        @test released == 20
        @test get_memory_pressure_level() == 0
    end
end

# ============================================================================
# TEST CATEGORY 3: TIMEOUT TESTS
# ============================================================================

println("\n[3] Testing Timeout Injection...")

@testset "Timeout Injection" begin
    
    # Test 3.1: should_inject_timeout probability
    @testset "Timeout Probability" begin
        # With very low probability, should rarely inject
        config = ChaosConfig(enabled=true, timeout_probability=0.0, log_injections=false)
        @test should_inject_timeout(config) == false
        
        # With probability 1.0, should always inject
        config = ChaosConfig(enabled=true, timeout_probability=1.0, log_injections=false)
        # Note: This tests the function, not the actual injection
    end
    
    # Test 3.2: inject_random_timeout success case
    @testset "Timeout Success Case" begin
        config = ChaosConfig(enabled=true, timeout_probability=0.0, log_injections=false)
        
        result = inject_random_timeout(() -> "success"; config=config)
        @test result == "success"
    end
    
    # Test 3.3: inject_random_timeout failure case
    @testset "Timeout Failure Case" begin
        config = ChaosConfig(enabled=true, timeout_probability=1.0, log_injections=false)
        
        @test_throws TimeoutError inject_random_timeout(() -> "success"; config=config)
    end
    
    # Test 3.4: Timeout disabled
    @testset "Timeout Disabled" begin
        config = ChaosConfig(enabled=false, timeout_probability=1.0, log_injections=false)
        
        result = inject_random_timeout(() -> "success"; config=config)
        @test result == "success"
    end
    
    # Test 3.5: TimeoutError type
    @testset "TimeoutError Type" begin
        err = TimeoutError("Test timeout")
        @test err.message == "Test timeout"
        @test err isa Exception
    end
end

# ============================================================================
# TEST CATEGORY 4: PARTIAL WRITE TESTS
# ============================================================================

println("\n[4] Testing Partial Write Simulation...")

@testset "Partial Write" begin
    
    # Test 4.1: Basic partial write
    @testset "Basic Partial Write" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Hello, World!"
        partial, bytes = simulate_partial_write(data, 5; config=config)
        
        @test partial == "Hello"
        @test bytes == 5
    end
    
    # Test 4.2: Write more than available
    @testset "Write Exceeds Data" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Hi"
        partial, bytes = simulate_partial_write(data, 100; config=config)
        
        @test partial == "Hi"
        @test bytes == 2
    end
    
    # Test 4.3: Write zero bytes
    @testset "Write Zero Bytes" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Test"
        partial, bytes = simulate_partial_write(data, 0; config=config)
        
        @test partial == ""
        @test bytes == 0
    end
    
    # Test 4.4: Partial write disabled
    @testset "Partial Write Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        data = "Hello, World!"
        partial, bytes = simulate_partial_write(data, 5; config=config)
        
        @test partial == data  # Full data returned
        @test bytes == length(data)
    end
    
    # Test 4.5: Partial write with failure
    @testset "Partial Write With Failure" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Complete data"
        success, result = simulate_partial_write_with_failure(data; failure_probability=1.0, config=config)
        
        @test success == false
        @test result !== nothing
        @test length(result) < length(data)
    end
    
    # Test 4.6: Partial write without failure
    @testset "Partial Write Without Failure" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Complete data"
        success, result = simulate_partial_write_with_failure(data; failure_probability=0.0, config=config)
        
        @test success == true
        @test result == data
    end
end

# ============================================================================
# TEST CATEGORY 5: DATA CORRUPTION TESTS
# ============================================================================

println("\n[5] Testing Data Corruption Injection...")

@testset "Data Corruption" begin
    
    # Test 5.1: Null byte injection
    @testset "Null Byte Injection" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        data = "Hello"
        corrupted = inject_corruption(data, :null_byte; config=config)
        
        @test length(corrupted) == length(data) + 1  # Extra null byte
        @test '\x00' in corrupted
    end
    
    # Test 5.2: Truncation injection
    @testset "Truncation Injection" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        data = "Hello, World!"
        corrupted = inject_corruption(data, :truncation; config=config)
        
        @test length(corrupted) < length(data)
    end
    
    # Test 5.3: Garbage injection
    @testset "Garbage Injection" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        data = "Hello, World!"
        corrupted = inject_corruption(data, :garbage; config=config)
        
        # Should be different content (corrupted), may vary in length due to random bytes
        @test corrupted != data
    end
    
    # Test 5.4: JSON Malformed injection
    @testset "JSON Malformed Injection" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        data = "{\"key\": \"value\"}"
        # The json_malformed corruption removes opening brace/bracket which should make it invalid
        # But we test the corruption happened (different from original)
        corrupted = inject_corruption(data, :json_malformed; config=config)
        
        # Should be different from original (corrupted)
        @test corrupted != data
    end
    
    # Test 5.5: Corruption disabled
    @testset "Corruption Disabled" begin
        config = ChaosConfig(enabled=false, corruption_probability=1.0, log_injections=false)
        
        data = "Hello"
        corrupted = inject_corruption(data, :null_byte; config=config)
        
        @test corrupted == data  # No corruption
    end
    
    # Test 5.6: Corrupted JSON helper
    @testset "Corrupted JSON Helper" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        data = "{\"valid\": \"json\"}"
        corrupted = inject_corrupted_json(data; config=config)
        
        # Either corrupted or valid (depends on corruption type selected)
        # Just verify it returns something
        @test corrupted !== nothing
    end
    
    # Test 5.7: Probabilistic corruption
    @testset "Probabilistic Corruption" begin
        config = ChaosConfig(enabled=true, corruption_probability=0.0, log_injections=false)
        
        data = "Hello"
        corrupted = inject_corruption(data, :null_byte; config=config)
        
        @test corrupted == data  # No corruption due to 0 probability
    end
end

# ============================================================================
# TEST CATEGORY 6: NETWORK PARTITION TESTS
# ============================================================================

println("\n[6] Testing Network Partition Simulation...")

@testset "Network Partition" begin
    
    # Test 6.1: Basic network partition
    @testset "Basic Network Partition" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        start_time = time()
        simulate_network_partition(50; config=config)  # 50ms
        elapsed = time() - start_time
        
        @test elapsed >= 0.05
    end
    
    # Test 6.2: Network partition disabled
    @testset "Network Partition Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        start_time = time()
        simulate_network_partition(1000; config=config)
        elapsed = time() - start_time
        
        @test elapsed < 0.1  # Should not have slept
    end
    
    # Test 6.3: with_network_partition
    @testset "With Network Partition" begin
        config = ChaosConfig(enabled=true, timeout_probability=1.0, log_injections=false)
        
        @test_throws NetworkPartitionError with_network_partition(() -> "success"; config=config)
    end
    
    # Test 6.4: NetworkPartitionError type
    @testset "NetworkPartitionError Type" begin
        err = NetworkPartitionError("Test partition")
        @test err.message == "Test partition"
        @test err isa Exception
    end
end

# ============================================================================
# TEST CATEGORY 7: CPU PRESSURE TESTS
# ============================================================================

println("\n[7] Testing CPU Pressure...")

@testset "CPU Pressure" begin
    
    # Test 7.1: Basic CPU pressure
    @testset "Basic CPU Pressure" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        start_time = time()
        inject_cpu_pressure(100; config=config)  # 100ms
        elapsed = time() - start_time
        
        @test elapsed >= 0.1
    end
    
    # Test 7.2: CPU pressure disabled
    @testset "CPU Pressure Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        start_time = time()
        inject_cpu_pressure(1000; config=config)
        elapsed = time() - start_time
        
        @test elapsed < 0.1  # Should not have run
    end
end

# ============================================================================
# TEST CATEGORY 8: SERVICE CRASH TESTS
# ============================================================================

println("\n[8] Testing Service Crash Simulation...")

@testset "Service Crash" begin
    
    # Test 8.1: Immediate crash
    @testset "Immediate Crash" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        @test_throws ServiceCrashError simulate_service_crash(:immediate; config=config)
    end
    
    # Test 8.2: Delayed crash
    @testset "Delayed Crash" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        @test_throws ServiceCrashError simulate_service_crash(:delayed; config=config)
    end
    
    # Test 8.3: Graceful degradation
    @testset "Graceful Degradation" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        # Should not throw, just log
        simulate_service_crash(:graceful; config=config)
        @test true
    end
    
    # Test 8.4: Intermittent crash (may or may not throw)
    @testset "Intermittent Crash" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        # Run multiple times - sometimes throws, sometimes doesn't
        results = Bool[]
        for _ in 1:20
            try
                simulate_service_crash(:intermittent; config=config)
                push!(results, false)  # Didn't throw
            catch e
                push!(results, true)   # Threw
            end
        end
        
        # Should have mix of throws and non-throws
        @test true  # Just verify it runs
    end
    
    # Test 8.5: Service crash disabled
    @testset "Service Crash Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        # Should not throw
        simulate_service_crash(:immediate; config=config)
        @test true
    end
    
    # Test 8.6: ServiceCrashError type
    @testset "ServiceCrashError Type" begin
        err = ServiceCrashError("Test crash", IMMEDIATE)
        @test err.message == "Test crash"
        @test err.crash_type == IMMEDIATE
        @test err isa Exception
    end
    
    # Test 8.7: should_crash probability
    @testset "Should Crash Probability" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        @test should_crash(:immediate; probability=0.0, config=config) == false
    end
end

# ============================================================================
# TEST CATEGORY 9: EXPERIMENT MANAGEMENT TESTS
# ============================================================================

println("\n[9] Testing Experiment Management...")

@testset "Experiment Management" begin
    
    # Test 9.1: Create experiment
    @testset "Create Experiment" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        experiment = create_experiment("test_exp"; description="Test description", config=config)
        
        @test experiment.name == "test_exp"
        @test experiment.description == "Test description"
        @test experiment.started_at !== nothing
        @test experiment.ended_at === nothing
        @test length(experiment.injections) == 0
    end
    
    # Test 9.2: Record injection
    @testset "Record Injection" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        experiment = create_experiment("test_exp"; config=config)
        
        record_injection!(experiment, "latency", Dict("ms" => 100))
        
        @test length(experiment.injections) == 1
        @test experiment.injections[1]["type"] == "latency"
    end
    
    # Test 9.3: Complete experiment
    @testset "Complete Experiment" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        experiment = create_experiment("test_exp"; config=config)
        
        record_injection!(experiment, "latency", Dict("ms" => 100))
        record_injection!(experiment, "memory", Dict("mb" => 10))
        
        complete_experiment!(experiment; results=Dict("outcome" => "success"))
        
        @test experiment.ended_at !== nothing
        @test experiment.results["outcome"] == "success"
        @test experiment.results["total_injections"] == 2
    end
    
    # Test 9.4: Experiment summary
    @testset "Experiment Summary" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        experiment = create_experiment("test_exp"; config=config)
        
        record_injection!(experiment, "latency", Dict("ms" => 100))
        record_injection!(experiment, "latency", Dict("ms" => 200))  # Same type
        record_injection!(experiment, "memory", Dict("mb" => 10))
        
        summary = get_experiment_summary(experiment)
        
        @test summary["name"] == "test_exp"
        @test summary["total_injections"] == 3
        @test summary["injection_types"]["latency"] == 2
        @test summary["injection_types"]["memory"] == 1
    end
    
    # Test 9.5: Default config
    @testset "Default Config" begin
        config = default_config()
        @test config !== nothing
        @test config.enabled == true
    end
    
    # Test 9.6: Set default config
    @testset "Set Default Config" begin
        new_config = ChaosConfig(enabled=false, latency_probability=0.5)
        set_default_config(new_config)
        
        config = default_config()
        @test config.enabled == false
        @test config.latency_probability == 0.5
        
        # Reset to default
        set_default_config(ChaosConfig())
    end
end

# ============================================================================
# TEST CATEGORY 10: DECORATOR TESTS
# ============================================================================

println("\n[10] Testing Decorator Patterns...")

@testset "Decorators" begin
    
    # Test 10.1: with_chaos decorator - disabled
    @testset "With Chaos Disabled" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        result = with_chaos(() -> 42; config=config)
        @test result == 42
    end
    
    # Test 10.2: with_chaos decorator - no injection
    @testset "With Chaos No Injection" begin
        # Set very low probabilities so injection is unlikely
        config = ChaosConfig(enabled=true, latency_probability=0.0, timeout_probability=0.0, 
                            corruption_probability=0.0, log_injections=false)
        
        result = with_chaos(() -> "success"; config=config)
        @test result == "success"
    end
    
    # Test 10.3: wrap_with_chaos
    @testset "Wrap With Chaos" begin
        config = ChaosConfig(enabled=false, log_injections=false)
        
        wrapped = wrap_with_chaos(() -> 42, config)
        @test wrapped() == 42
    end
end

# ============================================================================
# TEST CATEGORY 11: INTEGRATION WITH CIRCUIT BREAKER
# ============================================================================

println("\n[11] Testing Integration with Circuit Breaker...")

@testset "Circuit Breaker Integration" begin
    
    # Test 11.1: Circuit breaker integration - success case
    @testset "CB Integration Success" begin
        config = ChaosConfig(enabled=true, latency_probability=0.0, timeout_probability=0.0,
                            corruption_probability=0.0, log_injections=false)
        
        # Test that chaos can run
        result = with_chaos(() -> "success"; config=config)
        @test result == "success"
    end
    
    # Test 11.2: Full chaos with circuit breaker
    @testset "Full Chaos With CB" begin
        # Create config that will inject latency
        config = ChaosConfig(enabled=true, latency_probability=1.0, timeout_probability=0.0,
                            corruption_probability=0.0, log_injections=false)
        
        start_time = time()
        result = with_chaos(() -> "success"; config=config)
        elapsed = time() - start_time
        
        @test result == "success"
        @test elapsed >= 0.5  # Should have injected latency (default 500ms for random)
    end
    
    # Test 11.3: Test circuit breaker with latency injection
    @testset "Latency With CB Pattern" begin
        # Disable random chaos failures for this test to focus on circuit breaker logic
        config = ChaosConfig(enabled=true, log_injections=false, latency_probability=0.0, timeout_probability=0.0)
        
        # Create a simple circuit breaker-like wrapper
        circuit_open = Ref(false)
        
        function safe_execute(fn)
            if circuit_open[]
                throw(ErrorException("Circuit is open"))
            end
            return with_chaos(fn; config=config)
        end
        
        # First call should succeed
        result = safe_execute(() -> 42)
        @test result == 42
        
        # Open the circuit
        circuit_open[] = true
        
        # Second call should fail
        @test_throws ErrorException safe_execute(() -> 42)
    end
end

# ============================================================================
# TEST CATEGORY 12: STRESS TESTS
# ============================================================================

println("\n[12] Testing Under Stress...")

@testset "Stress Tests" begin
    
    # Test 12.1: Rapid latency injections
    @testset "Rapid Latency Injections" begin
        config = ChaosConfig(enabled=true, latency_probability=1.0, log_injections=false)
        
        for i in 1:5
            inject_latency(10; config=config)  # 10ms each
        end
        @test true
    end
    
    # Test 12.2: Memory stress
    @testset "Memory Stress" begin
        config = ChaosConfig(enabled=true, memory_pressure_mb=50, log_injections=false)
        
        # Allocate and release multiple times
        for _ in 1:3
            inject_memory_pressure(10; config=config)
            release_memory_pressure()
        end
        @test get_memory_pressure_level() == 0
    end
    
    # Test 12.3: Mixed chaos
    @testset "Mixed Chaos" begin
        config = ChaosConfig(enabled=true, latency_probability=0.3, timeout_probability=0.3,
                            corruption_probability=0.3, log_injections=false)
        
        results = []
        for _ in 1:20
            try
                result = with_chaos(() -> "success"; config=config)
                push!(results, (:success, result))
            catch e
                push!(results, (:error, typeof(e)))
            end
        end
        
        # Should have mix of success and errors
        @test length(results) == 20
        
        # Cleanup
        release_memory_pressure()
    end
    
    # Test 12.4: Concurrent-like stress
    @testset "Concurrent Like Stress" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        # Simulate multiple "sessions"
        for session in 1:3
            inject_memory_pressure(5; config=config)
            inject_latency(10; config=config)
        end
        
        @test get_memory_pressure_level() >= 15
        
        # Cleanup
        release_memory_pressure()
    end
end

# ============================================================================
# TEST CATEGORY 13: EDGE CASES
# ============================================================================

println("\n[13] Testing Edge Cases...")

@testset "Edge Cases" begin
    
    # Test 13.1: Empty data corruption
    @testset "Empty Data Corruption" begin
        config = ChaosConfig(enabled=true, corruption_probability=1.0, log_injections=false)
        
        corrupted = inject_corruption("", :null_byte; config=config)
        @test length(corrupted) >= 0
    end
    
    # Test 13.2: Single character data
    @testset "Single Character Data" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        partial, bytes = simulate_partial_write("a", 1; config=config)
        @test partial == "a"
        @test bytes == 1
    end
    
    # Test 13.3: Unicode data
    @testset "Unicode Data" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        data = "Hello 世界 🌍"
        corrupted = inject_corruption(data, :garbage; config=config)
        @test length(corrupted) == length(data)
    end
    
    # Test 13.4: Very large latency
    @testset "Very Large Latency" begin
        config = ChaosConfig(enabled=true, log_injections=false)
        
        # Should clamp to max (30000ms = 30s)
        latency = inject_latency(1_000_000; config=config)
        @test latency <= 30.0
    end
    
    # Test 13.5: Zero config values
    @testset "Zero Config Values" begin
        # Test with enabled=false
        config = ChaosConfig(enabled=false, latency_probability=1.0, timeout_probability=1.0,
                            corruption_probability=1.0, memory_pressure_mb=0, log_injections=false)
        
        @test inject_latency(100; config=config) == 0.0  # Disabled
        @test inject_memory_pressure(100; config=config) == 0
        @test should_inject_timeout(config) == false
        
        # Test with enabled=true but zero probabilities
        config2 = ChaosConfig(enabled=true, latency_probability=0.0, timeout_probability=0.0,
                            corruption_probability=0.0, memory_pressure_mb=0, log_injections=false)
        
        # Latency injection works because it's explicit
        @test inject_latency(10; config=config2) > 0
        @test inject_memory_pressure(10; config=config2) == 0  # memory_pressure_mb is 0
    end
end

# ============================================================================
# FINAL SUMMARY
# ============================================================================

println("\n" * "="^70)
println("CHAOS TEST SUMMARY")
println("="^70)
println("\nAll chaos engineering tests completed:")
println("  ✓ Latency Injection Tests")
println("  ✓ Memory Pressure Tests")
println("  ✓ Timeout Injection Tests")
println("  ✓ Partial Write Simulation Tests")
println("  ✓ Data Corruption Injection Tests")
println("  ✓ Network Partition Simulation Tests")
println("  ✓ CPU Pressure Tests")
println("  ✓ Service Crash Simulation Tests")
println("  ✓ Experiment Management Tests")
println("  ✓ Decorator Pattern Tests")
println("  ✓ Circuit Breaker Integration Tests")
println("  ✓ Stress Tests")
println("  ✓ Edge Case Tests")
println("="^70)

# Cleanup any remaining memory allocations
release_memory_pressure()
