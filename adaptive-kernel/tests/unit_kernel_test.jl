# tests/unit_kernel_test.jl - Unit tests for kernel determinism

using Test
using Dates

include("../kernel/Kernel.jl")
using .Kernel

# Import shared types from Kernel module
using .Kernel.SharedTypes

@testset "Kernel Unit Tests" begin
    
    @testset "Initialization" begin
        config = Dict(
            "goals" => [
                Dict("id" => "test_goal", "description" => "Test", "priority" => 0.8)
            ],
            "observations" => Dict("test_obs" => 1.0)
        )
        kernel = init_kernel(config)
        
        @test kernel.cycle[] == 0
        @test length(kernel.goals) == 1
        @test kernel.goals[1].id == "test_goal"
        @test kernel.self_metrics["confidence"] >= 0.7
    end
    
    @testset "Initialization with Full Config" begin
        # Test comprehensive kernel initialization with goals and observations
        config = Dict(
            "goals" => [
                Dict("id" => "goal1", "description" => "Primary goal", "priority" => 0.9),
                Dict("id" => "goal2", "description" => "Secondary goal", "priority" => 0.5)
            ],
            "observations" => Dict(
                "cpu_load" => 0.7,
                "memory_usage" => 0.8,
                "disk_io" => 0.3,
                "network_latency" => 0.2,
                "file_count" => 100,
                "process_count" => 50
            )
        )
        
        kernel = init_kernel(config)
        
        # Test cycle starts at 0
        @test kernel.cycle[] == 0
        
        # Test goals are correctly set up
        @test length(kernel.goals) == 2
        @test kernel.goals[1].id == "goal1"
        @test kernel.goals[1].priority == 0.9f0
        @test kernel.goals[2].id == "goal2"
        @test kernel.goals[2].priority == 0.5f0
        
        # Test active goal is set to first goal
        @test kernel.active_goal_id == "goal1"
        
        # Test observations are correctly set up
        @test kernel.world.observations.cpu_load ≈ 0.7f0
        @test kernel.world.observations.memory_usage ≈ 0.8f0
        
        # Test default metrics are initialized
        @test haskey(kernel.self_metrics, "confidence")
        @test haskey(kernel.self_metrics, "energy")
        @test haskey(kernel.self_metrics, "focus")
        @test kernel.self_metrics["energy"] == 1.0f0
    end
    
    @testset "Initialization with Empty Config" begin
        # Test default initialization when no config provided
        kernel = init_kernel(Dict())
        
        # Should have default goal
        @test length(kernel.goals) == 1
        @test kernel.goals[1].id == "default"
        
        # Cycle should be 0
        @test kernel.cycle[] == 0
    end
    
    @testset "Initialization with Invalid Config" begin
        # Test handling of invalid/missing data
        config = Dict(
            "goals" => "not_an_array",  # Invalid - should be array
            "observations" => 123  # Invalid - should be dict
        )
        
        kernel = init_kernel(config)
        
        # Should fallback to default goal
        @test length(kernel.goals) >= 1
        @test kernel.cycle[] == 0
    end
    
    @testset "Evaluate World" begin
        config = Dict(
            "goals" => [
                Dict("id" => "g1", "description" => "Goal 1", "priority" => 0.5),
                Dict("id" => "g2", "description" => "Goal 2", "priority" => 0.8)
            ]
        )
        kernel = init_kernel(config)
        scores = Kernel.evaluate_world(kernel)
        
        @test length(scores) == 2
        @test all(s >= 0 && s <= 1 for s in scores)
        @test sum(scores) ≈ 1.0  # Normalized
    end
    
    @testset "Select Action Deterministic" begin
        config = Dict("goals" => [Dict("id" => "g1", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        candidates = [
            Dict("id" => "cap1", "cost" => 0.1, "risk" => "low", "confidence" => 0.9),
            Dict("id" => "cap2", "cost" => 0.2, "risk" => "high", "confidence" => 0.8),
            Dict("id" => "cap3", "cost" => 0.05, "risk" => "low", "confidence" => 0.95)
        ]
        
        # Select multiple times; should be deterministic
        action1 = Kernel.select_action(kernel, candidates)
        action2 = Kernel.select_action(kernel, candidates)
        
        @test action1.capability_id == action2.capability_id
        @test action1.reasoning == action2.reasoning
    end
    
    @testset "Reflect & Memory Update" begin
        config = Dict("goals" => [Dict("id" => "g1", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        action = ActionProposal("test_cap", 0.8f0, 0.1f0, 0.5f0, 0.2f0, "test reasoning")
        result = Dict(
            "success" => true,
            "effect" => "Test effect",
            "actual_confidence" => 0.9f0,
            "energy_cost" => 0.05f0
        )
        
        old_conf = kernel.self_metrics["confidence"]
        old_energy = kernel.self_metrics["energy"]
        old_mem_size = length(kernel.episodic_memory)
        
        Kernel.reflect!(kernel, action, result)
        
        @test length(kernel.episodic_memory) == old_mem_size + 1
        @test kernel.self_metrics["confidence"] > old_conf  # Improved by good result
        @test kernel.self_metrics["energy"] < old_energy  # Used energy
    end
    
    @testset "Step Once" begin
        config = Dict("goals" => [Dict("id" => "g1", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        candidates = [Dict("id" => "test_cap", "cost" => 0.05, "risk" => "low", "confidence" => 0.8)]
        
        executed_caps = []
        exec_fn = (cap_id) -> begin
            push!(executed_caps, cap_id)
            return Dict(
                "success" => true,
                "effect" => "Executed",
                "actual_confidence" => 0.85f0,
                "energy_cost" => 0.05f0
            )
        end
        
        perm_fn = (risk) -> risk <= 0.3f0  # Allow low to medium risk
        
        kernel, action, result = Kernel.step_once(kernel, candidates, exec_fn, perm_fn)
        
        @test kernel.cycle[] == 1
        @test action.capability_id == "test_cap"
        @test result["success"] == true
        @test length(executed_caps) == 1
    end
    
    @testset "Permission Handler: Deny High Risk" begin
        config = Dict("goals" => [Dict("id" => "g1", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        candidates = [Dict("id" => "sh", "cost" => 0.1, "risk" => "high", "confidence" => 0.9)]
        
        exec_called = Ref(false)
        exec_fn = (cap_id) -> begin
            exec_called[] = true
            return Dict("success" => true, "effect" => "Should not reach", 
                       "actual_confidence" => 0.9f0, "energy_cost" => 0.1f0)
        end
        
        perm_fn = (risk) -> risk == "low"  # Deny high-risk
        
        kernel, action, result = Kernel.step_once(kernel, candidates, exec_fn, perm_fn)
        
        @test result["success"] == false
        @test exec_called[] == false  # Capability should not execute
    end
    
    @testset "Stats API" begin
        config = Dict("goals" => [Dict("id" => "g1", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        stats = Kernel.get_kernel_stats(kernel)
        
        @test haskey(stats, "cycle")
        @test haskey(stats, "confidence")
        @test haskey(stats, "energy")
        @test haskey(stats, "episodic_memory_size")
    @test stats["episodic_memory_size"] == 0
    end
end

@testset "Persistence Unit Tests" begin
    include("../persistence/Persistence.jl")
    using .Persistence

    TEST_LOG = "test_events.log"
    # Ensure test log path is used
    set_event_log_file(TEST_LOG)
    rm(TEST_LOG, force=true)

    @testset "Event Log Append" begin
        event1 = Dict("type" => "test", "data" => "first")
        event2 = Dict("type" => "test", "data" => "second")

        save_event(event1)
        save_event(event2)

        events = load_events()
        @test length(events) >= 2
        @test events[end]["data"] == "second"
    end

    # Clean up
    rm(TEST_LOG, force=true)
end

println("✓ All unit tests passed!")
