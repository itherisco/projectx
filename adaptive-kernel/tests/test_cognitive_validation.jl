# adaptive-kernel/tests/test_cognitive_validation.jl
# Phase 4: Cognitive Validation - Brain-like Behavior Assessment
# Tests whether JARVIS exhibits brain-like cognitive behaviors

using Test
using Dates
using UUIDs
using Statistics

# Import cognitive modules
push!(LOAD_PATH, joinpath(pwd(), ".."))
push!(LOAD_PATH, joinpath(pwd(), "..", "cognition"))

include("../cognition/types.jl")
using ..CognitionTypes

include("../cognition/metacognition/SelfModel.jl")
using ..SelfModel

include("../cognition/goals/GoalSystem.jl")
using ..GoalSystem

include("../cognition/attention/Attention.jl")
using ..Attention

include("../cognition/learning/OnlineLearning.jl")
using ..OnlineLearning

include("../cognition/spine/DecisionSpine.jl")
using ..DecisionSpine

# ============================================================================
# BRAIN-LIKE BEHAVIOR ASSESSMENT
# ============================================================================

println("\n" * "="^70)
println("PHASE 4: COGNITIVE VALIDATION - Brain-Like Behavior Assessment")
println("="^70)

# Track assessment results
assessment_results = Dict{Symbol, Dict}()

# ============================================================================
# TEST 1: Multi-Turn Context Maintenance
# ============================================================================
println("\n[TEST 1] Multi-Turn Context Maintenance")
println("-" ^ 50)

@testset "Multi-turn Context Maintenance" begin
    # Test 1a: Can the system track context across multiple interactions?
    println("  [1a] Testing context tracking capability...")
    
    # Check if SelfModel maintains internal state that could track context
    sm = SelfModel()
    
    # Initial introspection
    result1 = introspect(sm)
    cycles_after_first = sm.cycles_since_review
    
    # Simulate multiple "turns" by calling introspect multiple times
    for i in 1:5
        introspect(sm)
    end
    
    cycles_after_five = sm.cycles_since_review
    
    # Check if cycles incremented (indicating state tracking)
    context_tracked = cycles_after_five > cycles_after_first
    
    println("    Cycles after first: $cycles_after_first")
    println("    Cycles after five: $cycles_after_five")
    println("    Context tracked: $context_tracked")
    
    # Test 1b: Can attention maintain focus across multiple stimuli?
    println("  [1b] Testing attention focus maintenance...")
    
    state = AttentionState(max_focus=3)
    
    # Create sequence of related stimuli
    stimuli = [
        Stimulus(:focus_1, Float32[0.1, 0.2], :memory, time(), 0.8),
        Stimulus(:focus_2, Float32[0.15, 0.25], :memory, time() + 0.1, 0.7),
        Stimulus(:focus_3, Float32[0.12, 0.22], :memory, time() + 0.2, 0.6),
    ]
    
    # First selection
    focus1 = select_focus(stimuli, state)
    
    # Update context with first focus
    state.context = Float32[0.1, 0.2]
    
    # Second selection should consider context
    focus2 = select_focus(stimuli, state)
    
    println("    Initial focus: $focus1")
    println("    Context-aware focus: $focus2")
    
    # Test 1c: Does WorldModel maintain state history?
    println("  [1c] Testing WorldModel state history...")
    
    wm = WorldModel()
    
    # Add some states to history
    push!(wm.state_history, Float32[1.0, 2.0, 3.0])
    push!(wm.state_history, Float32[1.1, 2.1, 3.1])
    push!(wm.action_history, 1)
    push!(wm.action_history, 2)
    
    has_history = length(wm.state_history) >= 2
    
    println("    State history length: $(length(wm.state_history))")
    println("    Has history: $has_history")
    
    # Summary
    multi_turn_capable = context_tracked && has_history
    
    assessment_results[:multi_turn_context] = Dict(
        :tested => true,
        :context_tracking => context_tracked,
        :attention_maintains_focus => !isempty(focus1),
        :worldmodel_history => has_history,
        :implemented => multi_turn_capable,
        :score => multi_turn_capable ? 1.0 : 0.0
    )
    
    println("  RESULT: Multi-turn context = $(multi_turn_capable ? "IMPLEMENTED" : "MISSING/PARTIAL")")
end

# ============================================================================
# TEST 2: Goal Updates Over Time
# ============================================================================
println("\n[TEST 2] Goal Updates Over Time")
println("-" ^ 50)

@testset "Goal Updates Over Time" begin
    # Test 2a: Can goals be created and updated?
    println("  [2a] Testing goal creation and updates...")
    
    graph = GoalGraph(max_active=5)
    
    # Create a goal
    goal1 = create_goal!(
        graph,
        "Initial goal";
        priority=0.5f0,
        target_state=Float32[1.0, 2.0]
    )
    
    goal_id = goal1.id
    initial_progress = goal1.progress
    initial_priority = goal1.priority
    
    # Update goal progress
    update_goal_progress!(graph, goal_id, 0.5f0)
    
    updated_goal = graph.goals[goal_id]
    updated_progress = updated_goal.progress
    
    # Test 2b: Can goals be activated and managed over time?
    println("  [2b] Testing goal activation and lifecycle...")
    
    activated = activate_goal!(graph, goal_id)
    goal_active = updated_goal.status == :active
    
    # Test 2c: Does goal system support multiple concurrent goals?
    println("  [2c] Testing concurrent goal management...")
    
    # Create more goals
    for i in 1:4
        g = create_goal!(graph, "Goal $i"; priority=Float32(0.3 + i*0.1))
        activate_goal!(graph, g.id)
    end
    
    concurrent_goals = length(graph.active_goals)
    
    # Test 2d: Does intrinsic reward work (curiosity-driven)?
    println("  [2d] Testing curiosity-driven intrinsic reward...")
    
    visited = [Float32[0.0, 0.0], Float32[1.0, 1.0]]
    world_state = Float32[0.5, 0.5]
    
    intrinsic = compute_intrinsic_reward(goal1, visited, world_state)
    
    println("    Intrinsic reward computed: $intrinsic")
    
    # Summary
    goals_update = updated_progress > initial_progress && concurrent_goals >= 1
    
    assessment_results[:goal_updates] = Dict(
        :tested => true,
        :goal_creation => true,
        :progress_tracking => updated_progress > initial_progress,
        :goal_activation => activated,
        :concurrent_goals => concurrent_goals,
        :intrinsic_reward => intrinsic > 0,
        :implemented => goals_update,
        :score => goals_update ? 1.0 : 0.0
    )
    
    println("  RESULT: Goal updates = $(goals_update ? "IMPLEMENTED" : "MISSING/PARTIAL")")
end

# ============================================================================
# TEST 3: Adapt to User Corrections
# ============================================================================
println("\n[TEST 3] Adapt to User Corrections")
println("-" ^ 50)

@testset "Adapt to User Corrections" begin
    # Test 3a: Can pain feedback adjust agent behavior?
    println("  [3a] Testing pain feedback adaptation...")
    
    include("../cognition/feedback/PainFeedback.jl")
    using ..PainFeedback
    
    perf = AgentPerformance("test_agent", :executor)
    
    # Simulate a correction (pain from prediction error)
    outcome = Dict(
        "expected_outcome" => "action_x",
        "actual_outcome" => "action_y",  # Different = error
        "agent_confidence" => 0.9,
        "expected_risks" => ["risk_a"],
        "actual_risks" => String[],
        "warnings_issued" => 0
    )
    
    results = process_cycle_feedback(perf, outcome)
    
    # Check if pain was calculated
    has_pain = haskey(results, "prediction_error_pain")
    
    initial_weight = perf.current_weight
    println("    Initial weight: $initial_weight")
    
    # Test 3b: Can capability estimates be updated based on performance?
    println("  [3b] Testing capability update from performance...")
    
    sm = SelfModel()
    initial_cap = sm.capabilities[:reasoning]
    
    # Update capability based on poor performance
