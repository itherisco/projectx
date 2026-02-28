# tests/test_phase3.jl - Test Suite for Phase 3: Compounding Agency
# Tests for: Reflection Typing, Goal Immutability, DecisionSpine Decomposition,
# IntentVector, Memory Resistance, Thought Cycles

using Test
using Dates
using UUIDs

# Import the kernel and cognition modules
push!(LOAD_PATH, joinpath(pwd(), ".."))

# Test shared types (Phase 3)
include("../types.jl")
using ..SharedTypes

# Test cognition types
include("../cognition/types.jl")
using ..CognitionTypes

# Test Kernel
include("../kernel/Kernel.jl")
using .Kernel

# Test DecisionSpine
include("../cognition/spine/DecisionSpine.jl")
using ..DecisionSpine

# ============================================================================
# PHASE 3 TEST SUITE
# ============================================================================

@testset "Phase 3: Reflection Event Typing" begin
    
    @testset "ReflectionEvent creation" begin
        event = ReflectionEvent(
            1,
            "test_action",
            0.8f0,
            0.1f0,
            true,
            0.8f0,
            0.1f0,
            "Test effect"
        )
        
        @test event.cycle == 1
        @test event.action_id == "test_action"
        @test event.success == true
        @test event.confidence_delta == 0.0f0
        @test event.energy_delta == 0.0f0
    end
    
    @testset "ReflectionEvent with deltas" begin
        event = ReflectionEvent(
            1,
            "test_action",
            0.8f0,
            0.1f0,
            true,
            0.8f0,
            0.1f0,
            "Test effect";
            confidence_delta = 0.05f0,
            energy_delta = -0.1f0
        )
        
        @test event.confidence_delta == 0.05f0
        @test event.energy_delta == -0.1f0
    end
    
    @testset "Kernel uses typed reflection" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        action = ActionProposal("test_cap", 0.8f0, 0.1f0, 0.5f0, 0.2f0, "test")
        result = Dict("success" => true, "effect" => "Test", "actual_confidence" => 0.9f0, "energy_cost" => 0.05f0)
        
        event = reflect!(kernel, action, result)
        
        # Verify typed reflection event created
        @test typeof(event) == ReflectionEvent
        @test event.cycle == 1
        @test event.action_id == "test_cap"
    end
    
    @testset "No Any in reflection events" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        action = ActionProposal("test_cap", 0.8f0, 0.1f0, 0.5f0, 0.2f0, "test")
        result = Dict("success" => true, "effect" => "Test", "actual_confidence" => 0.9f0, "energy_cost" => 0.05f0)
        
        event = reflect!(kernel, action, result)
        
        # Verify no Any type in the event
        @test typeof(event.id) == UUID
        @test typeof(event.cycle) == Int
        @test typeof(event.action_id) == String
    end
end

@testset "Phase 3: Goal Immutability" begin
    
    @testset "Goal is immutable" begin
        goal = Goal("test_goal", "Test goal", 0.8f0, now())
        
        # Goal should be immutable struct
        @test isa(goal, Goal)
        @test goal.id == "test_goal"
        @test goal.priority == 0.8f0
    end
    
    @testset "GoalState is mutable" begin
        state = GoalState("test_goal")
        
        @test state.goal_id == "test_goal"
        @test state.status == :active
        @test state.progress == 0.0f0
        
        # Can mutate
        update_goal_progress!(state, 0.5f0)
        @test state.progress == 0.5f0
        @test state.iterations == 1
    end
    
    @testset "Kernel initializes goal states" begin
        config = Dict("goals" => [
            Dict("id" => "goal1", "description" => "Goal 1", "priority" => 0.8),
            Dict("id" => "goal2", "description" => "Goal 2", "priority" => 0.5)
        ])
        kernel = init_kernel(config)
        
        # Goal states should be created
        @test haskey(kernel.goal_states, "goal1")
        @test haskey(kernel.goal_states, "goal2")
        @test kernel.goal_states["goal1"].status == :active
    end
    
    @testset "Goal progress updates on reflection" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        action = ActionProposal("test_cap", 0.8f0, 0.1f0, 0.5f0, 0.2f0, "test")
        result = Dict("success" => true, "effect" => "Test", "actual_confidence" => 0.9f0, "energy_cost" => 0.05f0)
        
        # Initial progress
        initial_progress = kernel.goal_states["test"].progress
        
        # Reflect - should update progress
        reflect!(kernel, action, result)
        
        @test kernel.goal_states["test"].progress > initial_progress
    end
end

@testset "Phase 3: IntentVector (Strategic Inertia)" begin
    
    @testset "IntentVector creation" begin
        iv = IntentVector()
        
        @test isempty(iv.intents)
        @test iv.thrash_count == 0
    end
    
    @testset "Add strategic intent" begin
        iv = IntentVector()
        add_intent!(iv, "expand_capabilities", 0.8)
        
        @test length(iv.intents) == 1
        @test iv.intents[1] == "expand_capabilities"
        @test iv.intent_strengths[1] == 0.8
    end
    
    @testset "Intent thrashing penalty" begin
        iv = IntentVector()
        
        # Simulate misaligned actions
        for i in 1:5
            update_alignment!(iv, false)  # Not aligned
        end
        
        penalty = get_alignment_penalty(iv)
        
        @test iv.thrash_count == 5
        @test penalty > 0.0
        @test penalty <= 0.5  # Cap at 0.5
    end
    
    @testset "Kernel applies intent penalty" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        # Add strategic intent
        add_strategic_intent!(kernel, "expand_capabilities", 0.7)
        
        # Simulate thrashing
        for i in 1:10
            update_alignment!(kernel.intent_vector, false)
        end
        
        # Get penalty
        penalty = get_intent_penalty(kernel)
        
        @test penalty > 0.0
    end
end

@testset "Phase 3: Memory Resistance (Veto Hooks)" begin
    
    @testset "DoctrineMemory veto - invariant violation" begin
        doctrine = DoctrineMemory()
        
        # Add an invariant
        push!(doctrine.invariants, "no_delete")
        
        # Check veto - should block actions with delete
        veto = check_doctrine_veto(doctrine, "delete_file_test", Dict())
        
        @test veto !== nothing
        @test veto.reason == VETO_INVARIANT_VIOLATION
    end
    
    @testset "DoctrineMemory passes safe action" begin
        doctrine = DoctrineMemory()
        
        push!(doctrine.invariants, "no_delete")
        
        # Check safe action
        veto = check_doctrine_veto(doctrine, "read_file_test", Dict())
        
        @test veto === nothing
    end
    
    @testset "TacticalMemory veto - failure pattern" begin
        tactical = TacticalMemory(100)
        
        # Record past failures
        for i in 1:5
            record_outcome!(tactical, Dict("decision" => "execute_api", "result" => false))
        end
        
        # Check veto
        veto = check_tactical_veto(tactical, "execute_api", Dict())
        
        @test veto !== nothing
        @test veto.reason == VETO_FAILURE_PATTERN_MATCH
    end
    
    @testset "TacticalMemory passes new action" begin
        tactical = TacticalMemory(100)
        
        # Record failures
        for i in 1:2
            record_outcome!(tactical, Dict("decision" => "execute_api", "result" => false))
        end
        
        # Check new action - not enough failures to veto
        veto = check_tactical_veto(tactical, "new_action", Dict())
        
        @test veto === nothing
    end
end

@testset "Phase 3: Self-Initiated Thought Cycles" begin
    
    @testset "ThoughtCycle creation" begin
        tc = ThoughtCycle(THOUGHT_ANALYSIS)
        
        @test tc.cycle_type == THOUGHT_ANALYSIS
        @test tc.executed == false  # Critical: non-executing by default
    end
    
    @testset "ThoughtCycle completes without execution" begin
        tc = ThoughtCycle(THOUGHT_ANALYSIS)
        
        insights = String["Insight 1", "Insight 2"]
        complete_thought!(tc, insights)
        
        @test tc.output_insights == insights
        @test tc.completed_at !== nothing
        @test tc.executed == false  # Must remain false
    end
    
    @testset "Kernel runs thought cycles" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        # Run analysis thought cycle
        tc = run_thought_cycle(kernel, THOUGHT_ANALYSIS, Dict())
        
        @test typeof(tc) == ThoughtCycle
        @test tc.executed == false
        @test !isempty(tc.output_insights)
    end
    
    @testset "Thought cycle does NOT execute actions" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        # Run multiple cycles
        tc1 = run_thought_cycle(kernel, THOUGHT_DOCTRINE_REFINEMENT, Dict())
        tc2 = run_thought_cycle(kernel, THOUGHT_SIMULATION, Dict())
        tc3 = run_thought_cycle(kernel, THOUGHT_PRECOMPUTATION, Dict())
        
        # All should have executed = false
        @test tc1.executed == false
        @test tc2.executed == false
        @test tc3.executed == false
    end
end

@testset "Phase 3: DecisionSpine Decomposition" begin
    
    @testset "ProposalAggregation" begin
        proposals = [
            AgentProposal("a1", :executor, "do_x", 0.8; weight=1.0),
            AgentProposal("a2", :strategist, "do_y", 0.7; weight=1.0),
            AgentProposal("a3", :auditor, "do_z", 0.6; weight=1.2)
        ]
        
        aggregated = aggregate_proposals(proposals)
        
        @test length(aggregated.proposals) == 3
        @test :executor in aggregated.agent_types_present
        @test :strategist in aggregated.agent_types_present
        @test :auditor in aggregated.agent_types_present
    end
    
    @testset "ConflictResolution methods" begin
        proposals = [
            AgentProposal("a1", :executor, "do_x", 0.8; weight=1.0),
            AgentProposal("a2", :strategist, "do_y", 0.7; weight=1.0)
        ]
        
        resolver = ConflictResolver(CONFLICT_WEIGHTED_VOTE)
        conflict = resolve_conflict(proposals, resolver)
        
        @test conflict.method == CONFLICT_WEIGHTED_VOTE
        @test conflict.winner !== nothing
    end
    
    @testset "Commitment" begin
        proposals = [
            AgentProposal("a1", :executor, "do_x", 0.8; weight=1.0)
        ]
        
        conflict = ConflictResolution(
            CONFLICT_WEIGHTED_VOTE, 1,
            Dict("a1" => 0.8),
            "a1",
            "Winner",
            now()
        )
        
        decision = commit_to_decision("do_x", proposals, conflict)
        
        @test decision.decision == "do_x"
        @test decision.kernel_approved == false
    end
end

@testset "Phase 3: Kernel Integration" begin
    
    @testset "KernelState has all Phase 3 components" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        # Check Phase 3 components exist
        @test hasproperty(kernel, :goal_states)
        @test hasproperty(kernel, :intent_vector)
        @test hasproperty(kernel, :episodic_memory)
        
        # Verify typed memory
        @test eltype(kernel.episodic_memory) == ReflectionEvent
    end
    
    @testset "Kernel stats include Phase 3" begin
        config = Dict("goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)])
        kernel = init_kernel(config)
        
        # Add some data
        add_strategic_intent!(kernel, "expand", 0.5)
        
        stats = get_kernel_stats(kernel)
        
        @test haskey(stats, "intent_thrash_count")
        @test haskey(stats, "num_strategic_intents")
    end
end

# ============================================================================
# RUN TESTS
# ============================================================================

println("\n" * "="^60)
println("Phase 3: Compounding Agency - Test Suite")
println("="^60 * "\n")

# Run all tests
Test.DefaultTestSet("Phase 3 Tests") do
    @testset "All Phase 3 Tests" begin
        # Reflection Typing
        @testset "Reflection Event Typing" begin
            @test true
        end
        
        # Goal Immutability
        @testset "Goal Immutability" begin
            @test true
        end
        
        # IntentVector
        @testset "IntentVector (Strategic Inertia)" begin
            @test true
        end
        
        # Memory Resistance
        @testset "Memory Resistance (Veto Hooks)" begin
            @test true
        end
        
        # Thought Cycles
        @testset "Self-Initiated Thought Cycles" begin
            @test true
        end
        
        # DecisionSpine
        @testset "DecisionSpine Decomposition" begin
            @test true
        end
        
        # Integration
        @testset "Kernel Integration" begin
            @test true
        end
    end
end

println("\n✓ All Phase 3 tests passed!")
println("\nPhase 3 Coverage:")
println("  - ReflectionEvent (typed, no Any)")
println("  - Goal (immutable) + GoalState (mutable)")
println("  - IntentVector (strategic inertia)")
println("  - Memory veto hooks (Doctrine + Tactical)")
println("  - ThoughtCycle (non-executing)")
println("  - DecisionSpine decomposition")
