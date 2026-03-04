# adaptive-kernel/tests/test_causal_world_model.jl
# Tests for Causal World Modeling - "The Challenge" Engine

using Test
using Statistics
using LinearAlgebra

# Include the causal world model module (which includes WorldModel internally)
include("../cognition/worldmodel/CausalWorldModel.jl")
using .CausalWorldModel

# We can access WorldModel through CausalWorldModel.WorldModel if needed

# ============================================================================
# Test Helper Functions
# ============================================================================

function create_test_world_model()
    """Create a test world model with some initial history."""
    model = WorldModel(horizon=5, uncertainty_threshold=0.7, state_dim=12)
    
    # Add some sample history for better predictions
    for i in 1:20
        state = rand(Float32, 12) * 2.0f0 - 1.0f0
        action = rand(1:8)
        next_state = predict_next_state(model, state, action)
        
        update_causal_graph!(model, state, action, next_state)
        record_experience!(model, state, action, rand(Float32))
    end
    
    return model
end

# ============================================================================
# Test: CausalChallengeEngine Initialization
# ============================================================================

@testset "CausalChallengeEngine Initialization" begin
    println("Testing CausalChallengeEngine Initialization...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(
        world_model;
        breakpoint_threshold=0.3f0,
        max_scenarios=100,
        scenario_seed=42
    )
    
    @test engine.world_model === world_model
    @test engine.breakpoint_threshold == 0.3f0
    @test engine.max_scenarios == 100
    @test engine.scenario_seed == 42
    @test isempty(engine.scenario_cache)
    @test isempty(engine.causal_breakpoints)
    
    println("  [PASS] CausalChallengeEngine initialized correctly")
end

# ============================================================================
# Test: What If Scenario Generation
# ============================================================================

@testset "What If Scenario Generation" begin
    println("Testing What If Scenario Generation...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=100, scenario_seed=42)
    
    current_state = rand(Float32, 12) * 2.0f0 - 1.0f0
    baseline_action = 1
    
    scenarios = simulate_what_if_scenarios(
        engine,
        current_state,
        baseline_action;
        num_scenarios=100
    )
    
    @test length(scenarios) == 100
    
    # Verify scenario structure
    for scenario in scenarios
        @test scenario.id > 0
        @test scenario.hypothetical_action in 2:8  # Not baseline action
        @test length(scenario.initial_state) == 12
        @test isa(scenario.trajectory, Trajectory)
        @test scenario.outcome_score isa Float32
        @test 0.0f0 <= scenario.risk_assessment <= 1.0f0
        @test scenario.divergence_from_baseline >= 0.0f0
    end
    
    println("  [PASS] Generated $(length(scenarios)) What If scenarios")
end

# ============================================================================
# Test: Causal Breakpoint Identification
# ============================================================================

@testset "Causal Breakpoint Identification" begin
    println("Testing Causal Breakpoint Identification...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=50, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 1
    
    scenarios = simulate_what_if_scenarios(
        engine,
        current_state,
        baseline_action;
        num_scenarios=50
    )
    
    breakpoints = identify_causal_breakpoints(scenarios)
    
    @test isa(breakpoints, Vector{Dict})
    
    # Breakpoints should have required fields
    for bp in breakpoints
        @test haskey(bp, :variable)
        @test haskey(bp, :frequency)
        @test haskey(bp, :avg_risk)
        @test haskey(bp, :vulnerability_score)
        @test 0.0f0 <= bp[:vulnerability_score] <= 1.0f0
    end
    
    # Should be sorted by vulnerability
    if length(breakpoints) > 1
        for i in 1:length(breakpoints)-1
            @test breakpoints[i][:vulnerability_score] >= breakpoints[i+1][:vulnerability_score]
        end
    end
    
    println("  [PASS] Identified $(length(breakpoints)) causal breakpoints")
end

# ============================================================================
# Test: Causal Map Generation
# ============================================================================

@testset "Causal Map Generation" begin
    println("Testing Causal Map Generation...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=50, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 1
    
    scenarios = simulate_what_if_scenarios(
        engine,
        current_state,
        baseline_action;
        num_scenarios=50
    )
    
    causal_map = generate_causal_map(engine, scenarios)
    
    @test isa(causal_map, CausalMap)
    @test !isempty(causal_map.nodes)
    @test causal_map.scenario_count == 50
    
    # Verify nodes are symbols
    for node in causal_map.nodes
        @test isa(node, Symbol)
    end
    
    # Verify vulnerability scores
    for (var, score) in causal_map.vulnerability_scores
        @test isa(var, Symbol)
        @test 0.0f0 <= score <= 1.0f0
    end
    
    println("  [PASS] Generated causal map with $(length(causal_map.nodes)) nodes")
end

# ============================================================================
# Test: Action Safety Ranking
# ============================================================================

@testset "Action Safety Ranking" begin
    println("Testing Action Safety Ranking...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=100, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 1
    
    scenarios = simulate_what_if_scenarios(
        engine,
        current_state,
        baseline_action;
        num_scenarios=100
    )
    
    rankings = rank_actions_by_safety(scenarios)
    
    @test isa(rankings, Vector{Tuple{Int, Float32}})
    @test !isempty(rankings)
    
    # Verify ranking structure
    for (action, safety) in rankings
        @test action in 2:8
        @test 0.0f0 <= safety <= 1.0f0
    end
    
    # Should be sorted by safety descending
    if length(rankings) > 1
        for i in 1:length(rankings)-1
            @test rankings[i][2] >= rankings[i+1][2]
        end
    end
    
    println("  [PASS] Ranked $(length(rankings)) actions by safety")
end

# ============================================================================
# Test: Complete Scenario Analysis
# ============================================================================

@testset "Complete Scenario Analysis" begin
    println("Testing Complete Scenario Analysis...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=200, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 3
    
    result = analyze_scenarios(engine, current_state, baseline_action)
    
    @test isa(result, ScenarioAnalysisResult)
    @test length(result.scenarios) == 200
    @test isa(result.causal_map, CausalMap)
    @test isa(result.action_rankings, Vector{Tuple{Int, Float32}})
    @test result.recommended_action in 1:8
    @test isa(result.warnings, Vector{String})
    @test 0.0f0 <= result.confidence <= 1.0f0
    
    # Verify all scenarios were analyzed
    for scenario in result.scenarios
        @test scenario.hypothetical_action != baseline_action
    end
    
    println("  [PASS] Completed analysis of $(length(result.scenarios)) scenarios")
    println("  [PASS] Recommended action: $(result.recommended_action)")
    println("  [PASS] Warnings: $(length(result.warnings))")
end

# ============================================================================
# Test: Challenge Reasoning Integration
# ============================================================================

@testset "Challenge Reasoning Integration" begin
    println("Testing Challenge Reasoning Integration...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=50, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 2
    
    # Test with nothing as kernel_state (just for testing)
    challenge_result = challenge_reasoning!(
        nothing,
        engine,
        current_state,
        baseline_action
    )
    
    @test isa(challenge_result, Dict)
    @test haskey(challenge_result, "recommended_action")
    @test haskey(challenge_result, "confidence")
    @test haskey(challenge_result, "warnings")
    @test haskey(challenge_result, "action_rankings")
    @test haskey(challenge_result, "causal_map")
    @test haskey(challenge_result, "high_risk_scenarios")
    @test haskey(challenge_result, "breakpoint_count")
    
    println("  [PASS] Challenge reasoning returned valid results")
end

# ============================================================================
# Test: Causal Map JSON Export
# ============================================================================

@testset "Causal Map JSON Export" begin
    println("Testing Causal Map JSON Export...")
    
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=30, scenario_seed=42)
    
    current_state = rand(Float32, 12)
    baseline_action = 1
    
    scenarios = simulate_what_if_scenarios(
        engine,
        current_state,
        baseline_action;
        num_scenarios=30
    )
    
    causal_map = generate_causal_map(engine, scenarios)
    json_str = get_causal_map_json(causal_map)
    
    @test isa(json_str, String)
    @test occursin("nodes", json_str)
    @test occursin("edges", json_str)
    @test occursin("breakpoints", json_str)
    
    println("  [PASS] Exported causal map to JSON")
end

# ============================================================================
# Test: Create Challenge Engine from WorldModel
# ============================================================================

@testset "Create Challenge Engine from WorldModel" begin
    println("Testing Create Challenge Engine from WorldModel...")
    
    world_model = create_test_world_model()
    engine = create_challenge_engine(world_model)
    
    @test isa(engine, CausalChallengeEngine)
    @test engine.world_model === world_model
    
    println("  [PASS] Created challenge engine from existing world model")
end

# ============================================================================
# Run All Tests
# ============================================================================

println("\n" * "="^60)
println("Running Causal World Model Tests")
println("="^60 * "\n")

# Manual test execution for better output
println("\n" * "="^60)
println("Test Summary")
println("="^60)

try
    # Test 1: Initialization
    world_model = create_test_world_model()
    engine = CausalChallengeEngine(world_model; max_scenarios=10, scenario_seed=42)
    println("[PASS] Test 1: CausalChallengeEngine Initialization")
    
    # Test 2: Scenario generation
    current_state = rand(Float32, 12)
    scenarios = simulate_what_if_scenarios(engine, current_state, 1; num_scenarios=10)
    println("[PASS] Test 2: What If Scenario Generation")
    
    # Test 3: Breakpoint identification
    breakpoints = identify_causal_breakpoints(scenarios)
    println("[PASS] Test 3: Causal Breakpoint Identification")
    
    # Test 4: Causal map generation
    causal_map = generate_causal_map(engine, scenarios)
    println("[PASS] Test 4: Causal Map Generation")
    
    # Test 5: Action ranking
    rankings = rank_actions_by_safety(scenarios)
    println("[PASS] Test 5: Action Safety Ranking")
    
    # Test 6: Complete analysis
    result = analyze_scenarios(engine, current_state, 1)
    println("[PASS] Test 6: Complete Scenario Analysis")
    
    # Test 7: Challenge reasoning
    challenge_result = challenge_reasoning!(nothing, engine, current_state, 1)
    println("[PASS] Test 7: Challenge Reasoning Integration")
    
    # Test 8: JSON export
    json_str = get_causal_map_json(causal_map)
    println("[PASS] Test 8: Causal Map JSON Export")
    
    # Test 9: Create from WorldModel
    engine2 = create_challenge_engine(world_model)
    println("[PASS] Test 9: Create Challenge Engine from WorldModel")
    
    println("\n" * "="^60)
    println("ALL TESTS PASSED!")
    println("="^60)
    
catch e
    println("\nTest failed with error: $e")
    rethrow(e)
end
