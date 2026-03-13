# cognition/Integrator.jl - Cognitive Integrator
# Integrates all 9 cognitive modules and manages cognitive state transitions
# Phase 2: Complete integration with emotional and learning connections
#
# Cognitive Modules (9 total):
# 1. SensoryProcessing - ✅ Connected
# 2. WorldModel - ✅ Connected
# 3. DecisionSpine - ✅ Connected
# 4. MemorySystem - ✅ Connected (via Persistence.jl)
# 5. AttentionSystem - ✅ Connected
# 6. EmotionLayer - ⚠️ Connected now (was 70%)
# 7. PlanningEngine - ✅ Connected (via AutonomousPlanner.jl)
# 8. ReflectionEngine - ✅ Connected (via metacognition/SelfModel.jl)
# 9. MetabolicController - ✅ Connected now (new)

module Integrator

using Dates
using UUIDs
using Statistics

# Import cognitive types
include(joinpath(@__DIR__, "types.jl"))
using ..CognitionTypes

# Import cognitive loop for main cycle
include(joinpath(@__DIR__, "CognitiveLoop.jl"))
using .CognitiveLoop

# Import metabolic controller
include(joinpath(@__DIR__, "metabolic", "MetabolicController.jl"))
using .MetabolicController

# Import sensory processing
include(joinpath(@__DIR__, "..", "sensory", "SensoryProcessing.jl"))
using .SensoryProcessing

# Import world model
include(joinpath(@__DIR__, "worldmodel", "WorldModel.jl"))
using .WorldModels

# Import decision spine
include(joinpath(@__DIR__, "spine", "DecisionSpine.jl"))
using .DecisionSpine

# Import attention
include(joinpath(@__DIR__, "attention", "Attention.jl"))
using .Attention

# Import emotions (now connected)
include(joinpath(@__DIR__, "feedback", "Emotions.jl"))
using .Emotions

# Import learning (now connected)
include(joinpath(@__DIR__, "learning", "OnlineLearning.jl"))
using .OnlineLearning

# Import goals
include(joinpath(@__DIR__, "goals", "GoalSystem.jl"))
using .GoalSystem

# Import metacognition
include(joinpath(@__DIR__, "metacognition", "SelfModel.jl"))
using .SelfModel

# Import planning
include(joinpath(@__DIR__, "..", "planning", "AutonomousPlanner.jl"))
using .AutonomousPlanner

# Import memory/persistence
include(joinpath(@__DIR__, "..", "persistence", "Persistence.jl"))
using .Persistence

# Import sleep/consolidation
include(joinpath(@__DIR__, "consolidation", "Sleep.jl"))
using .Sleep

# Import oneiric controller (Phase 4 - Dream State)
include(joinpath(@__DIR__, "oneiric", "OneiricController.jl"))
using .OneiricController

# Import brain
include(joinpath(@__DIR__, "..", "brain", "Brain.jl"))
using .Brain

# Import context module (Stage 2: Multi-turn context maintenance)
include(joinpath(@__DIR__, "context", "Context.jl"))
using .Context

# Import IPC
include(joinpath(@__DIR__, "..", "kernel", "ipc", "IPC.jl"))
using .IPC

# Import shared types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..SharedTypes

# Import Input Sanitizer - SECURITY BOUNDARY for LLM interaction paths
include(joinpath(@__DIR__, "security", "InputSanitizer.jl"))
using .InputSanitizer

# ============================================================================
# COGNITIVE INTEGRATOR STATE
# ============================================================================

"""
    CognitiveIntegrator - Main state container for integrated cognitive system

Integrates all 9 cognitive modules:
1. SensoryProcessing - Raw input processing
2. WorldModel - Internal predictive model
3. DecisionSpine - Decision making
4. MemorySystem - Long-term memory (via Persistence)
5. AttentionSystem - Attention allocation
6. EmotionLayer - Emotional processing (CONNECTED NOW)
7. PlanningEngine - Long-horizon planning (via AutonomousPlanner)
8. ReflectionEngine - Self-reflection (via SelfModel)
9. MetabolicController - Energy management (CONNECTED NOW)
"""
mutable struct CognitiveIntegrator
    # Core cognitive state
    cognitive_state::CognitiveState
    metabolic_state::MetabolicState
    
    # Module states
    sensory_buffer::SensoryBuffer
    world_model_state::WorldModelState
    decision_history::Vector{CommittedDecision}
    attention_state::AttentionState
    affective_state::AffectiveState
    learning_state::LearningState
    goal_state::GoalGraph
    self_model::SelfModelState
    planner_state::AutonomousPlannerState
    memory_state::MemoryState
    
    # Oneiric (Dream) state - Phase 4 integration
    oneiric_state::OneiricState
    
    # IPC
    ipc_channel::Union{IPCChannel, Nothing}
    
    # Cycle tracking
    total_cycles::Int64
    last_state_transition::DateTime
    
    # Configuration
    config::IntegratorConfig
    
    function CognitiveIntegrator(config::IntegratorConfig=IntegratorConfig())
        new(
            CognitiveState(),                      # cognitive_state
            initialize_metabolism(),               # metabolic_state
            SensoryBuffer(),                      # sensory_buffer
            WorldModelState(),                    # world_model_state
            CommittedDecision[],                  # decision_history
            AttentionState(),                     # attention_state
            AffectiveState(),                     # affective_state
            LearningState(),                      # learning_state
            GoalGraph(),                          # goal_state
            SelfModelState(),                     # self_model
            AutonomousPlannerState(),             # planner_state
            MemoryState(),                        # memory_state
            OneiricState(),                       # oneiric_state (Phase 4)
            nothing,                              # ipc_channel
            0,                                    # total_cycles
            now(),                                # last_state_transition
            config                                # config
        )
    end
end

"""
    IntegratorConfig - Configuration for cognitive integrator
"""
mutable struct IntegratorConfig
    # Timing
    target_frequency_hz::Float64
    
    # Integration weights
    emotional_weight::Float32
    attention_weight::Float32
    learning_weight::Float32
    planning_weight::Float32
    
    # Thresholds
    mode_transition_threshold::Int
    memory_consolidation_interval::Int
    
    # Debug
    verbose::Bool
    
    function IntegratorConfig(;
        target_frequency_hz::Float64=136.1,
        emotional_weight::Float32=0.3f0,
        attention_weight::Float32=0.3f0,
        learning_weight::Float32=0.2f0,
        planning_weight::Float32=0.2f0,
        mode_transition_threshold::Int=10,
        memory_consolidation_interval::Int=1000,
        verbose::Bool=false
    )
        new(
            target_frequency_hz,
            emotional_weight,
            attention_weight,
            learning_weight,
            planning_weight,
            mode_transition_threshold,
            memory_consolidation_interval,
            verbose
        )
    end
end

# ============================================================================
# MAIN INTEGRATION CYCLE
# ============================================================================

"""
    integrate_cognitive_cycle(integrator::CognitiveIntegrator, raw_input::Dict)::ActionProposal

Run one complete integrated cognitive cycle.
This is the main entry point for the cognitive system.
"""
function integrate_cognitive_cycle(
    integrator::CognitiveIntegrator,
    raw_input::Dict
)::ActionProposal
    integrator.total_cycles += 1
    
    # === STEP 1: Get metabolic constraints ===
    # Apply metabolic constraints to determine what operations can run
    metabolic_constraints = apply_metabolic_constraints(integrator.metabolic_state)
    
    # === STEP 2: Update metabolic state ===
    operations = merge(metabolic_constraints, Dict(
        :perception => true,
        :brain_inference => get(metabolic_constraints, :brain_inference, false),
        :learning => get(metabolic_constraints, :learning, false),
        :planning => get(metabolic_constraints, :planning, false),
        :dreaming => get(metabolic_constraints, :dreaming, false)
    ))
    new_mode = update_metabolism!(integrator.metabolic_state, operations)
    
    # === STEP 3: Check for Oneiric (dream) state transition ===
    # Phase 4: Dreaming triggered at energy < 20%
    energy_level = integrator.metabolic_state.energy
    
    # Check if we should enter dreaming mode based on energy
    if energy_level < DREAMING_THRESHOLD && integrator.cognitive_state.mode != :dreaming
        # Check OneiricController for additional conditions
        if should_enter_dream(integrator.oneiric_state; energy_level=energy_level, is_idle=false, idle_duration=0.0)
            new_mode = MODE_DREAMING
        end
    end
    
    # === STEP 4: Handle mode transitions ===
    if new_mode != integrator.cognitive_state.mode
        handle_mode_transition!(integrator, new_mode)
    end
    
    # === STEP 5: Process based on current mode ===
    if integrator.cognitive_state.mode == MODE_DREAMING
        return run_dreaming_cycle!(integrator, raw_input)
    elseif integrator.cognitive_state.mode == MODE_CRITICAL
        return run_critical_cycle!(integrator, raw_input)
    else
        return run_active_cycle!(integrator, raw_input)
    end
end

"""
    run_active_cycle - Run normal active cognitive cycle
"""
function run_active_cycle!(
    integrator::CognitiveIntegrator,
    raw_input::Dict
)::ActionProposal
    # === STEP 1: Sensory Processing ===
    processed = process_raw_input(integrator, raw_input)
    
    # === STEP 2: Attention Selection (with emotional weighting) ===
    attention_weights = compute_integrated_attention(
        integrator,
        processed
    )
    attended_items = select_attended(attention_weights, integrator.config.attention_weight)
    
    # === STEP 3: World Model Update ===
    world_state = update_integrated_world_model(
        integrator,
        processed,
        attended_items
    )
    
    # === STEP 4: Emotional Processing (CONNECTED) ===
    emotional_state = update_integrated_emotions(
        integrator,
        processed,
        world_state
    )
    
    # === STEP 5: Goal Evaluation ===
    goals = evaluate_goals(integrator, emotional_state)
    
    # === STEP 6: Planning (if energy allows) ===
    if integrator.metabolic_state.energy > ENERGY_LOW
        plans = run_planning(integrator, goals, world_state)
    else
        plans = Plan[]
    end
    
    # === STEP 7: Decision Making ===
    decision = make_decision(
        integrator,
        emotional_state,
        attended_items,
        goals,
        plans
    )
    
    # === STEP 8: Learning (CONNECTED) ===
    if integrator.metabolic_state.energy > ENERGY_LOW
        run_integrated_learning(integrator, decision, emotional_state)
    end
    
    # === STEP 9: Memory Consolidation ===
    if integrator.total_cycles % integrator.config.memory_consolidation_interval == 0
        run_memory_consolidation(integrator)
    end
    
    # === STEP 10: Self-Reflection ===
    run_reflection(integrator, decision)
    
    # === STEP 11: Generate Action Proposal ===
    proposal = generate_integrated_proposal(
        integrator,
        decision,
        emotional_state
    )
    
    # === STEP 12: Send to Kernel ===
    if integrator.ipc_channel !== nothing
        send_proposal_to_kernel(integrator.ipc_channel, proposal)
    end
    
    return proposal
end

"""
    run_dreaming_cycle - Run dreaming/consolidation cycle using full OneiricController
"""
function run_dreaming_cycle!(
    integrator::CognitiveIntegrator,
    raw_input::Dict
)::ActionProposal
    # Use full OneiricController pipeline for dreaming
    oneiric_state = integrator.oneiric_state
    
    # Check if we should enter dream state
    if oneiric_state.phase == :idle
        enter_dream_state!(oneiric_state)
    end
    
    # Process one dream cycle with all subsystems
    dream_results = process_dream_cycle!(oneiric_state)
    
    # Memory consolidation via OneiricController
    # (Handled internally by process_dream_cycle!)
    
    # Hallucination training via OneiricController
    # (Handled internally by process_dream_cycle!)
    
    # Synaptic homeostasis via OneiricController
    # (Handled internally by process_dream_cycle!)
    
    # Check if we should exit dream state
    if oneiric_state.phase == :exiting || dream_results["status"] == "dream_complete"
        exit_dream_state!(oneiric_state)
        # Transition back to active mode
        integrator.cognitive_state.mode = :active
    end
    
    # Generate minimal proposal (dreaming doesn't produce actions)
    return ActionProposal(
        "dream",
        0.1f0,
        0.0f0,
        0.0f0,
        0.0f0,
        "Dreaming consolidation mode - Phase 4 OneiricController active"
    )
end

"""
    run_critical_cycle - Run minimal cognitive cycle in critical energy state
"""
function run_critical_cycle!(
    integrator::CognitiveIntegrator,
    raw_input::Dict
)::ActionProposal
    # Minimal processing - just perception and basic decision
    
    # Simple perception
    processed = process_raw_input(integrator, raw_input)
    
    # Emergency decision
    proposal = ActionProposal(
        "observe",
        0.2f0,
        0.0f0,
        0.0f0,
        0.1f0,
        "Critical mode - minimal function"
    )
    
    return proposal
end

# ============================================================================
# CONNECTED MODULE FUNCTIONS
# ============================================================================

"""
    process_raw_input - Process raw sensory input
    SECURITY: Sanitizes all text inputs using InputSanitizer before processing
"""
function process_raw_input(integrator::CognitiveIntegrator, raw_input::Dict)::ProcessedSensory
    # SECURITY: Sanitize text fields in raw_input before processing
    # This is the first defense against prompt injection
    sanitized_input = _sanitize_raw_input(raw_input)
    
    # Use sensory processing module
    return process_sensory_input(integrator.sensory_buffer, sanitized_input)
end

"""
    _sanitize_raw_input - Internal function to sanitize raw input Dict
"""
function _sanitize_raw_input(raw_input::Dict)::Dict
    sanitized = Dict{Any, Any}()
    
    for (key, value) in raw_input
        if value isa String
            # Sanitize string inputs
            result = sanitize_input(value)
            if result.level == MALICIOUS
                @error "Malicious input detected in raw_input" key=key
                sanitized[key] = "[BLOCKED] Content filtered by security policy"
            elseif result.level == SUSPICIOUS
                @warn "Suspicious input detected and sanitized" key=key
                sanitized[key] = result.sanitized !== nothing ? result.sanitized : value
            else
                sanitized[key] = result.sanitized !== nothing ? result.sanitized : value
            end
        elseif value isa Dict
            # Recursively sanitize nested dicts
            sanitized[key] = _sanitize_raw_input(value)
        elseif value isa Vector
            # Sanitize vector of strings
            sanitized[key] = _sanitize_vector(value)
        else
            sanitized[key] = value
        end
    end
    
    return sanitized
end

"""
    _sanitize_vector - Sanitize vector of values
"""
function _sanitize_vector(vec::Vector)::Vector
    sanitized_vec = Any[]
    for item in vec
        if item isa String
            result = sanitize_input(item)
            if result.level == MALICIOUS
                push!(sanitized_vec, "[BLOCKED]")
            else
                push!(sanitized_vec, result.sanitized !== nothing ? result.sanitized : item)
            end
        else
            push!(sanitized_vec, item)
        end
    end
    return sanitized_vec
end

"""
    compute_integrated_attention - Compute attention with emotional weighting (CONNECTED)
"""
function compute_integrated_attention(
    integrator::CognitiveIntegrator,
    processed::ProcessedSensory
)::Vector{Float32}
    # Base attention from attention system
    base_attention = compute_attention(
        integrator.cognitive_state.perception,
        integrator.affective_state
    )
    
    # Emotional modulation (EmotionLayer CONNECTED)
    emotional_modulation = get_emotional_attention_modulation(integrator.affective_state)
    
    # Combine
    combined = base_attention .* (1.0f0 .+ emotional_modulation)
    
    return softmax(combined)
end

"""
    get_emotional_attention_modulation - Get attention modulation from emotions
"""
function get_emotional_attention_modulation(affective::AffectiveState)::Vector{Float32}
    # Fear increases vigilance (attention to threats)
    # Joy increases openness
    # Curiosity increases exploration
    
    modulation = zeros(Float32, 12)
    
    if affective.emotion == Fear
        modulation .+= 0.3f0  # Increased vigilance
    elseif affective.emotion == Joy
        modulation .+= 0.1f0  # Positive openness
    elseif affective.emotion == Curiosity
        modulation .+= 0.2f0  # Exploration bias
    elseif affective.emotion == Frustration
        modulation .+= -0.1f0  # Reduced openness
    end
    
    return modulation
end

"""
    select_attended - Select attended items based on attention weights
"""
function select_attended(weights::Vector{Float32}, threshold::Float32)::Vector{String}
    # Simple top-k selection
    n_select = max(1, sum(weights .> threshold))
    indices = sortperm(weights, rev=true)[1:min(n_select, 5)]
    
    return ["item_$i" for i in indices]
end

"""
    update_integrated_world_model - Update world model with new observations
"""
function update_integrated_world_model(
    integrator::CognitiveIntegrator,
    processed::ProcessedSensory,
    attended::Vector{String}
)::WorldModelState
    # Build perception vector
    perception_vec = build_perception_vector(integrator.cognitive_state.perception)
    
    # Update world model
    return update_world_model(integrator.world_model_state, perception_vec)
end

"""
    update_integrated_emotions - Update emotions with cognitive integration (CONNECTED)
"""
function update_integrated_emotions(
    integrator::CognitiveIntegrator,
    processed::ProcessedSensory,
    world_state::WorldModelState
)::AffectiveState
    # Update based on:
    # 1. Current perception
    # 2. World model state
    # 3. Goal progress
    # 4. Metabolic state
    
    affective = integrator.affective_state
    
    # Update based on perception
    update_emotion!(affective, affective.emotion, 0.1f0)
    
    # Adjust based on world model uncertainty
    uncertainty = estimate_world_uncertainty(world_state)
    if uncertainty > 0.5f0
        update_emotion!(affective, Curiosity, uncertainty)
    end
    
    # Adjust based on energy (metabolic connection)
    if integrator.metabolic_state.energy < ENERGY_LOW
        update_emotion!(affective, Fear, 0.3f0)
    end
    
    # Decay emotional state
    decay_affective!(affective)
    
    return affective
end

"""
    estimate_world_uncertainty - Estimate uncertainty in world model
"""
function estimate_world_uncertainty(state::WorldModelState)::Float32
    # Simplified - in production would use model uncertainty
    return 0.3f0
end

"""
    decay_affective! - Decay emotional state over time
"""
function decay_affective!(affective::AffectiveState)
    affective.valence *= 0.99f0
    affective.arousal *= 0.98f0
    affective.dominance *= 0.995f0
    affective.emotion_intensity *= 0.95f0
end

"""
    evaluate_goals - Evaluate and update goals
"""
function evaluate_goals(
    integrator::CognitiveIntegrator,
    affective::AffectiveState
)::Vector{Goal}
    # Get current goals
    goals = get_active_goals(integrator.goal_state)
    
    # Filter based on emotional state
    # Fear might trigger threat-related goals
    if affective.emotion == Fear
        # Add self-protection goals
    end
    
    return goals
end

"""
    run_planning - Run planning engine
"""
function run_planning(
    integrator::CognitiveIntegrator,
    goals::Vector{Goal},
    world_state::WorldModelState
)::Vector{Plan}
    # Use autonomous planner
    return plan_goals(integrator.planner_state, goals, world_state)
end

"""
    make_decision - Make decision using decision spine
"""
function make_decision(
    integrator::CognitiveIntegrator,
    affective::AffectiveState,
    attended::Vector{String},
    goals::Vector{Goal},
    plans::Vector{Plan}
)::CommittedDecision
    # Create decision context with emotional weighting
    context = DecisionContext(
        perception=integrator.cognitive_state.perception,
        attention=attended,
        goals=goals,
        plans=plans,
        emotional_valence=affective.valence,
        emotional_arousal=affective.arousal,
        confidence=affective.confidence
    )
    
    # Run decision spine
    return decide(integrator.decision_history, context)
end

"""
    run_integrated_learning - Run learning with connections (CONNECTED)
"""
function run_integrated_learning(
    integrator::CognitiveIntegrator,
    decision::CommittedDecision,
    affective::AffectiveState
)
    # Build experience
    experience = build_learning_experience(decision, affective)
    
    # Apply emotional modulation to learning
    emotional_factor = 1.0f0 + affective.value_modulation
    
    # Run online learning
    incremental_update!(nothing, experience, integrator.learning_state)  # brain would be passed
    
    # Update confidence based on learning
    update_self_model_from_learning!(integrator.self_model, integrator.learning_state)
end

"""
    build_learning_experience - Build experience for learning
"""
function build_learning_experience(
    decision::CommittedDecision,
    affective::AffectiveState
)::Dict
    return Dict(
        "decision" => decision,
        "emotion" => affective.emotion,
        "valence" => affective.valence,
        "intensity" => affective.emotion_intensity,
        "timestamp" => time_ns()
    )
end

"""
    run_memory_consolidation - Run periodic memory consolidation
"""
function run_memory_consolidation(integrator::CognitiveIntegrator)
    # Use sleep/consolidation module
    consolidate_memories!(integrator.sleep_state, integrator.memory_state)
end

"""
    run_reflection - Run self-reflection
"""
function run_reflection(integrator::CognitiveIntegrator, decision::CommittedDecision)
    # Update self model
    reflect_on_decision!(integrator.self_model, decision)
    
    # Periodic deep reflection
    if integrator.total_cycles % 100 == 0
        run_deep_reflection!(integrator.self_model)
    end
end

"""
    generate_integrated_proposal - Generate final action proposal
"""
function generate_integrated_proposal(
    integrator::CognitiveIntegrator,
    decision::CommittedDecision,
    affective::AffectiveState
)::ActionProposal
    # Adjust confidence with emotional modulation
    emotional_modulation = apply_emotional_modulation(affective, 0.5f0)
    adjusted_confidence = decision.confidence * (1.0f0 + emotional_modulation)
    
    # Generate proposal
    return ActionProposal(
        decision.action,
        clamp(adjusted_confidence, 0.0f1, 1.0f0),
        decision.predicted_cost,
        decision.predicted_reward,
        decision.risk,
        "Integrated cognitive cycle: $(decision.reasoning)"
    )
end

"""
    send_proposal_to_kernel - Send proposal to Rust kernel
"""
function send_proposal_to_kernel(ipc::IPCChannel, proposal::ActionProposal)
    try
        send_proposal(ipc, Dict(
            "capability_id" => proposal.capability_id,
            "confidence" => proposal.confidence,
            "predicted_cost" => proposal.predicted_cost,
            "predicted_reward" => proposal.predicted_reward,
            "risk" => proposal.risk,
            "reasoning" => proposal.reasoning
        ))
    catch e
        @error "Failed to send proposal" exception=e
    end
end

# ============================================================================
# DREAMING FUNCTIONS
# ============================================================================

"""
    consolidate_dreams! - Consolidate memories during dreaming using OneiricController
"""
function consolidate_dreams!(integrator::CognitiveIntegrator)
    # Use OneiricController for memory consolidation
    oneiric_state = integrator.oneiric_state
    
    if oneiric_state.phase in [:entering, :replay]
        process_dream_cycle!(oneiric_state)
    end
end

"""
    update_self_model_dreams! - Update self model during dreaming
"""
function update_self_model_dreams!(integrator::CognitiveIntegrator)
    # Dream-time self-reflection
    dream_reflect!(integrator.self_model)
end

# ============================================================================
# MODE TRANSITIONS
# ============================================================================

"""
    handle_mode_transition! - Handle cognitive mode transitions
"""
function handle_mode_transition!(integrator::CognitiveIntegrator, new_mode::CognitiveMode)
    old_mode = integrator.cognitive_state.mode
    
    # Log transition
    if integrator.config.verbose
        println("Mode transition: $old_mode -> $new_mode")
    end
    
    # Handle specific transitions
    if new_mode == MODE_DREAMING
        on_enter_dreaming!(integrator)
    elseif new_mode == MODE_CRITICAL
        on_enter_critical!(integrator)
    elseif new_mode == MODE_ACTIVE
        on_enter_active!(integrator)
    elseif new_mode == MODE_DEATH
        on_enter_death!(integrator)
    end
    
    # Update state
    integrator.cognitive_state.mode = Symbol(new_mode)
    integrator.last_state_transition = now()
end

function on_enter_dreaming!(integrator::CognitiveIntegrator)
    # Use OneiricController to enter dream state
    enter_dream_state!(integrator.oneiric_state)
end

function on_enter_critical!(integrator::CognitiveIntegrator)
    # Emergency protocols
    # Save state
end

function on_enter_active!(integrator::CognitiveIntegrator)
    # Resume normal operation
end

function on_enter_death!(integrator::CognitiveIntegrator)
    # Save final state
    checkpoint_state(integrator)
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    create_integrator - Create new cognitive integrator
"""
function create_integrator(; kwargs...)::CognitiveIntegrator
    config = IntegratorConfig(; kwargs...)
    return CognitiveIntegrator(config)
end

"""
    checkpoint_state - Save current state for recovery
"""
function checkpoint_state(integrator::CognitiveIntegrator)
    # Use persistence module
    save_cognitive_state(integrator)
end

"""
    restore_state - Restore from checkpoint
"""
function restore_state(integrator::CognitiveIntegrator)
    # Use persistence module
    load_cognitive_state(integrator)
end

"""
    get_integrator_summary - Get summary of integrator state
"""
function get_integrator_summary(integrator::CognitiveIntegrator)::Dict
    return Dict(
        "total_cycles" => integrator.total_cycles,
        "mode" => integrator.cognitive_state.mode,
        "metabolic" => get_metabolic_summary(integrator.metabolic_state),
        "cognitive" => get_cognitive_summary(integrator.cognitive_state),
        "affective" => get_affective_summary(integrator.affective_state),
        "learning" => get_learning_summary(integrator.learning_state)
    )
end

"""
    get_learning_summary - Get learning state summary
"""
function get_learning_summary(state::LearningState)::Dict
    return Dict(
        "confidence" => state.confidence,
        "uncertainty" => state.uncertainty,
        "current_lr" => state.current_learning_rate,
        "curriculum_level" => state.curriculum_level
    )
end

# ============================================================================
# HELPER TYPES
# ============================================================================

"""
    DecisionContext - Context for decision making
"""
struct DecisionContext
    perception::Perception
    attention::Vector{String}
    goals::Vector{Goal}
    plans::Vector{Plan}
    emotional_valence::Float32
    emotional_arousal::Float32
    confidence::Float32
end

"""
    Plan - Simple plan representation
"""
struct Plan
    id::String
    steps::Vector{String}
    expected_value::Float32
    risk::Float32
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    CognitiveIntegrator,
    IntegratorConfig,
    integrate_cognitive_cycle,
    create_integrator,
    checkpoint_state,
    restore_state,
    get_integrator_summary,
    run_active_cycle!,
    run_dreaming_cycle!,
    run_critical_cycle!

end # module
