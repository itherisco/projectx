# tests/integration_simulation_test.jl - Integration test: run 20 cycles

using Test
using JSON

include("../kernel/Kernel.jl")
include("../persistence/Persistence.jl")

using .Kernel
using .Persistence

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
    
    kernel = init_kernel(config)
    
    # Mock capabilities
    candidates = [
        Dict("id" => "cap1", "cost" => 0.05, "risk" => "low", "confidence" => 0.85),
        Dict("id" => "cap2", "cost" => 0.08, "risk" => "medium", "confidence" => 0.8),
        Dict("id" => "cap3", "cost" => 0.03, "risk" => "low", "confidence" => 0.9)
    ]
    
    exec_count = Ref(0)
    exec_fn = (cap_id) -> begin
        exec_count[] += 1
        return Dict(
            "success" => rand() > 0.2,  # 80% success rate
            "effect" => "Executed $cap_id",
            "actual_confidence" => Float32(0.7 + 0.2 * rand()),
            "energy_cost" => Float32(0.02 + 0.05 * rand())
        )
    end
    
    perm_fn = (risk) -> risk != "high"
    
    # Run 20 cycles
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
    @test kernel.cycle == 20
    @test exec_count[] >= 15  # Most cycles should execute
    @test length(kernel.episodic_memory) >= 15
    
    # Verify persistence
    events = load_events()
    @test length(events) >= 20
    
    # Verify state tracked
    stats = Kernel.get_kernel_stats(kernel)
    @test stats["cycle"] == 20
    @test 0 <= stats["confidence"] <= 1
    @test 0 <= stats["energy"] <= 1
    
    @test !isfile("events.log") || filesize("events.log") > 0
    
end

println("✓ Integration test passed (20 cycles)!")
