# tests/integration_simulation_test.jl - Integration test: run 20 cycles

using Test
using JSON
using Dates

include("../kernel/Kernel.jl")
include("../persistence/Persistence.jl")

using .Kernel
using .Persistence

# Explicitly import persistence functions to avoid ambiguity
import .Persistence: init_persistence, save_event, load_events

@testset "Integration: 20-Cycle Simulation" begin
    
    # Clean up before test
    rm("events.log", force=true)
    
    # Initialize
    init_persistence()
    
    config = Dict(
        "goals" => [
            Dict("id" => "g1", "description" => "Goal 1", "priority" => 0.9),
            Dict("id" => "g2", "description" => "Goal 2", "priority" => 0.7)
        ],
        "observations" => Dict("test" => 1.0)
    )
    
    kernel = Kernel.init_kernel(config)
    
    # Mock capabilities
    candidates = [
        Dict("id" => "cap1", "cost" => 0.05, "risk" => "low", "confidence" => 0.85),
        Dict("id" => "cap2", "cost" => 0.08, "risk" => "medium", "confidence" => 0.8),
        Dict("id" => "cap3", "cost" => 0.03, "risk" => "low", "confidence" => 0.9)
    ]
    
    exec_count = Ref(0)
    # Deterministic execution function: cap2 considered flaky (returns false), others succeed
    exec_fn = (cap_id) -> begin
        exec_count[] += 1
        if cap_id == "cap2"
            return Dict(
                "success" => false,
                "effect" => "Simulated failure $cap_id",
                "actual_confidence" => 0.3f0,
                "energy_cost" => 0.08f0
            )
        else
            return Dict(
                "success" => true,
                "effect" => "Executed $cap_id",
                "actual_confidence" => 0.85f0,
                "energy_cost" => 0.03f0
            )
        end
    end
    
    perm_fn = (risk) -> risk != "high"
    
    # Run 20 cycles deterministically
    for i in 1:20
        kernel, action, result = Kernel.step_once(kernel, candidates, exec_fn, perm_fn)

        event = Dict(
            "timestamp" => string(now()),
            "cycle" => kernel.cycle,
            "action" => action.capability_id,
            "success" => result["success"]
        )
        save_event(event)
    end

    # Verify outcomes
    @test kernel.cycle[] == 20
    @test exec_count[] == 20  # deterministic: one exec per cycle
    @test length(kernel.episodic_memory) == 20

    # Verify persistence
    events = load_events()
    @test length(events) >= 20

    # Verify state tracked
    stats = Kernel.get_kernel_stats(kernel)
    @test stats["cycle"] == 20
    @test 0 <= stats["confidence"] <= 1
    @test 0 <= stats["energy"] <= 1
    
end

println("✓ Integration test passed (20 cycles)!")
