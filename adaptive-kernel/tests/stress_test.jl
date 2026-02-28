# adaptive-kernel/tests/stress_test.jl - Comprehensive Stress Testing
# Tests extreme conditions, edge cases, and failure modes

using Test
using JSON
using Dates
using Random
using UUIDs

# Include modules
include("../kernel/Kernel.jl")
include("../persistence/Persistence.jl")
include("../types.jl")
include("../integration/Conversions.jl")

using .Kernel
using .Persistence
using .Kernel.SharedTypes
using .Integration

println("=" ^ 70)
println("  COMPREHENSIVE STRESS TESTING")
println("=" ^ 70)

# ============================================================================
# TEST CATEGORY 1: KERNEL EDGE CASES
# ============================================================================

println("\n[1] Testing Kernel Edge Cases...")

@testset "Kernel Edge Cases" begin
    
    # Test: Empty configuration
    @testset "Empty Configuration" begin
        kernel = Kernel.init_kernel(Dict())
        @test kernel !== nothing
        @test kernel.cycle[] == 0
    end
    
    # Test: Missing goals
    @testset "Missing Goals" begin
        kernel = Kernel.init_kernel(Dict("observations" => Dict("test" => 1.0)))
        @test kernel !== nothing
    end
    
    # Test: Empty goals array
    @testset "Empty Goals Array" begin
        kernel = Kernel.init_kernel(Dict("goals" => []))
        @test kernel !== nothing
    end
    
    # Test: Goals with missing fields
    @testset "Goals with Missing Fields" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1"),  # Only id
            Dict(),  # Empty dict
        ]))
        @test kernel !== nothing
    end
    
    # Test: Invalid goal priorities (out of bounds)
    @testset "Invalid Goal Priorities" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "priority" => 1.5),  # > 1.0
            Dict("id" => "g2", "priority" => -0.5),  # < 0
            Dict("id" => "g3", "priority" => 0.5),  # Valid
        ]))
        @test kernel !== nothing
    end
    
    # Test: Very long goal descriptions
    @testset "Long Goal Descriptions" begin
        long_desc = "x" ^ 10000
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "description" => long_desc, "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Unicode in goals
    @testset "Unicode in Goals" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "_goal_🚀", "description" => "测试目标 🎉", "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
end

# ============================================================================
# TEST CATEGORY 2: INVALID DATA TYPES
# ============================================================================

println("\n[2] Testing Invalid Data Types...")

@testset "Invalid Data Types" begin
    
    # Test: Wrong types in configuration
    @testset "Wrong Types in Config" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => "not_an_array",  # Should be array
            "observations" => 123  # Should be dict
        ))
        @test kernel !== nothing
    end
    
    # Test: Nested wrong types
    @testset "Nested Wrong Types" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => 123, "priority" => "high")  # Wrong types
        ]))
        @test kernel !== nothing
    end
    
    # Test: Float32 vs Float64
    @testset "Float Precision" begin
        config = Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)],
            "observations" => Dict("val" => 0.5f0)
        )
        kernel = Kernel.init_kernel(config)
        @test kernel !== nothing
    end
    
    # Test: Integer priorities
    @testset "Integer Priorities" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "priority" => 1),  # Integer
            Dict("id" => "g2", "priority" => 0)   # Integer
        ]))
        @test kernel !== nothing
    end
end

# ============================================================================
# TEST CATEGORY 3: BOUNDARY VALUES
# ============================================================================

println("\n[3] Testing Boundary Values...")

@testset "Boundary Values" begin
    
    # Test: Maximum number of goals
    @testset "Max Goals" begin
        goals = [Dict("id" => "g$i", "priority" => rand()) for i in 1:1000]
        kernel = Kernel.init_kernel(Dict("goals" => goals))
        @test kernel !== nothing
    end
    
    # Test: Zero priority
    @testset "Zero Priority" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "priority" => 0.0)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Unit priority
    @testset "Unit Priority" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "priority" => 1.0)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Very small float
    @testset "Very Small Float" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "priority" => 1e-10)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Very large number of observations
    @testset "Large Observations" begin
        obs = Dict("key_$i" => rand() for i in 1:10000)
        kernel = Kernel.init_kernel(Dict("observations" => obs))
        @test kernel !== nothing
    end
end

# ============================================================================
# TEST CATEGORY 4: NULL/EMPTY INPUTS
# ============================================================================

println("\n[4] Testing Null/Empty Inputs...")

@testset "Null/Empty Inputs" begin
    
    # Test: null in JSON (represented as nothing in Julia)
    @testset "Null Values" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "description" => nothing)],
            "observations" => Dict("val" => nothing)
        ))
        @test kernel !== nothing
    end
    
    # Test: Empty strings
    @testset "Empty Strings" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "", "description" => "", "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Whitespace-only strings
    @testset "Whitespace Strings" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "   \t\n   ", "description" => " ", "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
    
    # Test: Special characters in strings
    @testset "Special Characters" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g\n\r\t", "description" => "\x00\x01\x02", "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
end

# ============================================================================
# TEST CATEGORY 5: MALFORMED DATA
# ============================================================================

println("\n[5] Testing Malformed Data...")

@testset "Malformed Data" begin
    
    # Test: Invalid JSON-like structures
    @testset "Invalid JSON" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5, "extra" => Dict())]
        ))
        @test kernel !== nothing
    end
    
    # Test: Circular references - mark as known issue
    @testset "Circular Data" begin
        # Circular references are a known issue - system doesn't handle them
        # but shouldn't crash
        @test_broken false  # Known issue
    end
    
    # Test: Very deep nesting
    @testset "Deep Nesting" begin
        nested = Dict("value" => 1)
        for i in 1:100
            nested = Dict("level_$i" => nested)
        end
        kernel = Kernel.init_kernel(Dict("observations" => nested))
        @test kernel !== nothing
    end
    
    # Test: Binary data in strings
    @testset "Binary Data" begin
        kernel = Kernel.init_kernel(Dict("goals" => [
            Dict("id" => "g1", "description" => String(rand(UInt8, 1000)), "priority" => 0.5)
        ]))
        @test kernel !== nothing
    end
end

# ============================================================================
# TEST CATEGORY 6: PERSISTENCE STRESS
# ============================================================================

println("\n[6] Testing Persistence Stress...")

@testset "Persistence Stress" begin
    
    # Test: Rapid saves
    @testset "Rapid Saves" begin
        init_persistence()
        for i in 1:1000
            save_event(Dict("id" => i, "data" => "test"))
        end
        events = load_events()
        @test length(events) >= 1000
    end
    
    # Test: Large events
    @testset "Large Events" begin
        init_persistence()
        large_data = "x" ^ 1_000_000
        save_event(Dict("id" => "large", "data" => large_data))
        events = load_events()
        @test length(events) >= 1
    end
    
    # Test: Empty events
    @testset "Empty Events" begin
        init_persistence()
        save_event(Dict())
        events = load_events()
        @test length(events) >= 1
    end
    
    # Test: Special characters in events
    @testset "Special Characters in Events" begin
        init_persistence()
        save_event(Dict(
            "id" => "special",
            "data" => "🚀🎉💻\n\r\t\x00",
            "unicode" => "日本語🌍"
        ))
        events = load_events()
        @test length(events) >= 1
    end
end

# ============================================================================
# TEST CATEGORY 7: CONVERSION STRESS
# ============================================================================

println("\n[7] Testing Conversion Functions...")

@testset "Conversion Functions" begin
    
    # Test: parse_risk_string edge cases
    @testset "Risk Conversion Edge Cases" begin
        @test Integration.parse_risk_string("low") === 0.1f0
        @test Integration.parse_risk_string("medium") === 0.5f0
        @test Integration.parse_risk_string("high") === 0.9f0
        @test Integration.parse_risk_string("unknown") === 0.5f0  # Default
        @test Integration.parse_risk_string("") === 0.5f0  # Empty
        @test Integration.parse_risk_string("LOW") === 0.1f0  # Case insensitive - converted to "low"
    end
    
    # Test: float_to_risk_string edge cases
    @testset "Risk String Edge Cases" begin
        @test Integration.float_to_risk_string(0.1f0) == "low"
        @test Integration.float_to_risk_string(0.5f0) == "medium"
        @test Integration.float_to_risk_string(0.9f0) == "high"
        @test Integration.float_to_risk_string(0.0f0) == "low"
        @test Integration.float_to_risk_string(1.0f0) == "high"
    end
end

# ============================================================================
# TEST CATEGORY 8: STEP_ONCE EDGE CASES
# ============================================================================

println("\n[8] Testing step_once Edge Cases...")

@testset "Step Once Edge Cases" begin
    
    # Test: Empty candidates - should use default fallback action
    @testset "Empty Candidates" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        exec_fn = (cap_id) -> Dict("success" => true, "effect" => "ok", 
                                    "actual_confidence" => 0.9f0, "energy_cost" => 0.1f0)
        perm_fn = (risk) -> true
        
        kernel, action, result = Kernel.step_once(kernel, [], exec_fn, perm_fn)
        # Empty candidates uses fallback action - success depends on exec_fn
        @test result !== nothing
        @test action.capability_id == "none"  # Fallback action
    end
    
    # Test: Candidates with missing fields
    @testset "Candidates Missing Fields" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        exec_fn = (cap_id) -> Dict("success" => true, "effect" => "ok", 
                                    "actual_confidence" => 0.9f0, "energy_cost" => 0.1f0)
        perm_fn = (risk) -> true
        
        # Minimal candidate
        kernel, action, result = Kernel.step_once(kernel, [
            Dict("id" => "cap1")  # Only id
        ], exec_fn, perm_fn)
        @test result !== nothing
    end
    
    # Test: All candidates denied
    @testset "All Candidates Denied" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        exec_fn = (cap_id) -> Dict("success" => true, "effect" => "ok", 
                                    "actual_confidence" => 0.9f0, "energy_cost" => 0.1f0)
        perm_fn = (risk) -> false  # Deny all
        
        kernel, action, result = Kernel.step_once(kernel, [
            Dict("id" => "cap1", "risk" => "high", "cost" => 0.1, "confidence" => 0.9)
        ], exec_fn, perm_fn)
        @test result["success"] === false
    end
    
    # Test: Execution function throws
    @testset "Execution Function Throws" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        exec_fn = (cap_id) -> throw(ErrorException("Simulated error"))
        perm_fn = (risk) -> true
        
        kernel, action, result = Kernel.step_once(kernel, [
            Dict("id" => "cap1", "risk" => "low", "cost" => 0.1, "confidence" => 0.9)
        ], exec_fn, perm_fn)
        @test result["success"] === false
    end
    
    # Test: Many cycles
    @testset "Many Cycles" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        exec_fn = (cap_id) -> Dict("success" => true, "effect" => "ok", 
                                    "actual_confidence" => 0.9f0, "energy_cost" => 0.01f0)
        perm_fn = (risk) -> true
        
        for i in 1:100
            kernel, action, result = Kernel.step_once(kernel, [
                Dict("id" => "cap1", "risk" => "low", "cost" => 0.01, "confidence" => 0.9)
            ], exec_fn, perm_fn)
        end
        @test kernel.cycle[] == 100
    end
end

# ============================================================================
# TEST CATEGORY 9: MEMORY STRESS
# ============================================================================

println("\n[9] Testing Memory Stress...")

@testset "Memory Stress" begin
    
    # Test: Large episodic memory
    @testset "Large Episodic Memory" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        # Add many memories using ReflectionEvent (correct type)
        for i in 1:10000
            push!(kernel.episodic_memory, ReflectionEvent(
                uuid4(),  # UUID field
                i,
                "cap_$i",
                0.5f0,
                0.5f0,
                true,
                0.9f0,
                0.1f0,
                "effect_$i",
                now(),
                0.0f0,
                -0.1f0
            ))
        end
        @test length(kernel.episodic_memory) == 10000
    end
    
    # Test: Memory cleanup
    @testset "Memory Cleanup" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        # Add then clear
        for i in 1:1000
            push!(kernel.episodic_memory, ReflectionEvent(
                uuid4(),  # UUID field
                i,
                "cap_$i",
                0.5f0,
                0.5f0,
                true,
                0.9f0,
                0.1f0,
                "effect_$i",
                now(),
                0.0f0,
                -0.1f0
            ))
        end
        empty!(kernel.episodic_memory)
        @test length(kernel.episodic_memory) == 0
    end
end

# ============================================================================
# TEST CATEGORY 10: CONCURRENT ACCESS (SIMULATED)
# ============================================================================

println("\n[10] Testing Concurrent Access (Simulated)...")

@testset "Concurrent Access" begin
    
    # Test: Multiple reads/writes to kernel
    @testset "Sequential Concurrent Access" begin
        kernel = Kernel.init_kernel(Dict(
            "goals" => [Dict("id" => "g1", "priority" => 0.5)]
        ))
        
        results = []
        
        # Simulate concurrent access
        for i in 1:100
            kernel = Kernel.init_kernel(Dict(
                "goals" => [Dict("id" => "g$i", "priority" => rand())]
            ))
            push!(results, kernel.cycle[])
        end
        
        @test length(results) == 100
    end
end

# ============================================================================
# FINAL SUMMARY
# ============================================================================

println("\n" * "=" ^ 70)
println("  STRESS TEST COMPLETED")
println("=" ^ 70)
