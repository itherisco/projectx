# cognition/CognitiveLoop.jl - Julia Cognitive Brain Loop at 136.1 Hz
# Phase 2: Complete cognitive cycle with energy management
# Pipeline: perception → world_model → memory → decision → action_proposal → send to Rust kernel
#
# 136.1 Hz = ~7.35ms per iteration

module CognitiveLoop

using Dates
using UUIDs
using Statistics
using Base.Threads

# Import existing cognitive infrastructure
include(joinpath(@__DIR__, "types.jl"))
using ..CognitionTypes

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

# Import emotions (for integration)
include(joinpath(@__DIR__, "feedback", "Emotions.jl"))
using .Emotions

# Import learning (for integration)
include(joinpath(@__DIR__, "learning", "OnlineLearning.jl"))
using .OnlineLearning

# Import goals
include(joinpath(@__DIR__, "goals", "GoalSystem.jl"))
using .GoalSystem

# Import brain for neural processing
include(joinpath(@__DIR__, "..", "brain", "Brain.jl"))
using .Brain

# Import IPC for Rust kernel communication
include(joinpath(@__DIR__, "..", "kernel", "ipc", "IPC.jl"))
using .IPC

# Import kernel types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..SharedTypes

# ============================================================================
# CONSTANTS
# ============================================================================

# 136.1 Hz timing
const COGNITIVE_FREQUENCY_HZ = 136.1
const CYCLE_DURATION_MS = 1000.0 / COGNITIVE_FREQUENCY_HZ  # ~7.35ms
const CYCLE_DURATION_SEC = CYCLE_DURATION_MS / 1000.0

# Energy thresholds
const ENERGY_CRITICAL = 0.15f0
const ENERGY_LOW = 0.30f0
const ENERGY_RECOVERY = 0.70f0

# ============================================================================
# COGNITIVE STATE
# ============================================================================

"""
    CognitiveState - Main state for the 136.1 Hz cognitive loop

# Fields
- `energy::Float32`: Current energy level (0.0-1.0)
- `last_cycle_time::UInt64`: Nanosecond timestamp of last cycle
- `mode::Symbol`: Current cognitive mode (:active, :idle, :dreaming, :recovery)
- `cycle_count::UInt64`: Total number of completed cycles
- `perception::Perception`: Current perception state
- `affective_state::AffectiveState`: Current emotional state
- `learning_state::LearningState`: Current learning state
- `attention_focus::Vector{String}`: Currently attended items
- `active_goals::Vector{Goal}`: Currently active goals
- `world_model::WorldModelState`: Internal world model
- `sensory_buffer::SensoryBuffer`: Input sensory buffer
"""
mutable struct CognitiveState
    # Core state
    energy::Float32
    last_cycle_time::UInt64
    mode::Symbol
    cycle_count::UInt64
    
    # Perception and processing
    perception::Perception
    sensory_buffer::SensoryBuffer
    
    # Cognitive modules
    affective_state::AffectiveState
    learning_state::LearningState
    attention_focus::Vector{String}
    
    # Goals and planning
    active_goals::Vector{Goal}
    goal_context::Vector{Float32}
    
    # World model
    world_model::WorldModelState
    
    # Timing
    avg_cycle_time_ms::Float32
    max_cycle_time_ms::Float32
    
    # IPC connection
    ipc_channel::Union{IPCChannel, Nothing}
    
    # Brain
    brain_input::Union{BrainInput, Nothing}
    brain_output::Union{BrainOutput, Nothing}
    
    function CognitiveState()
        new(
            1.0f0,                          # energy
            0x0,                            # last_cycle_time
            :active,                        # mode
            0x0,                            # cycle_count
            Perception(),                   # perception
            SensoryBuffer(),               # sensory_buffer
            AffectiveState(),              # affective_state
            LearningState(),               # learning_state
            String[],                      # attention_focus
            Goal[],                        # active_goals
            zeros(Float32, 8),             # goal_context
            WorldModelState(),             # world_model
            0.0f0,                         # avg_cycle_time_ms
            0.0f0,                         # max_cycle_time_ms
            nothing,                       # ipc_channel
            nothing,                        # brain_input
            nothing                         # brain_output
        )
    end
end

# ============================================================================
# COGNITIVE CYCLE - Main 136.1 Hz Loop
# ============================================================================

"""
    cognition_cycle(state::CognitiveState, raw_input::Dict)::ActionProposal

Run one complete cognitive cycle at 136.1 Hz.
Pipeline: perception → world_model → memory → decision → action_proposal → send to Rust kernel
"""
function cognition_cycle(state::CognitiveState, raw_input::Dict)::ActionProposal
    start_time = time_ns()
    
    # Update cycle count
    state.cycle_count += 1
    
    # === STEP 1: Sensory Processing ===
    processed_sensory = process_sensory_input(state.sensory_buffer, raw_input)
    
    # === STEP 2: Perception Formation ===
    update_perception!(state.perception, processed_sensory)
    
    # === STEP 3: Emotional Modulation (Connect Emotions to main loop) ===
    # Update affective state based on current perception
    update_affective_state!(state.affective_state, state.perception)
    
    # Apply emotional modulation to perception confidence
    emotional_modulation = apply_emotional_modulation(state.affective_state, state.perception.confidence)
    
    # === STEP 4: Attention Selection ===
    attention_weights = compute_attention(state.perception, state.affective_state)
    state.attention_focus = select_attended_items(attention_weights, 5)
    
    # === STEP 5: World Model Update ===
    perception_vector = build_perception_vector(state.perception)
    state.world_model = update_world_model(state.world_model, perception_vector)
    
    # === STEP 6: Goal Evaluation ===
    state.active_goals = evaluate_active_goals(state.active_goals, state.perception, state.energy)
    state.goal_context = build_goal_context(state.active_goals)
    
    # === STEP 7: Brain Inference ===
    # Prepare brain input with emotional modulation
    brain_input = BrainInput(
        perception_vector;
        goal_context=state.goal_context,
        recent_rewards=get_recent_rewards(state.perception),
        time_budget_ms=Float32(CYCLE_DURATION_MS * 0.5)  # Use half the cycle for thinking
    )
    state.brain_input = brain_input
    
    # Run brain inference (this would normally call the neural brain)
    # For now, we create a fallback proposal
    brain_output = infer_brain_fallback(brain_input, state.affective_state)
    state.brain_output = brain_output
    
    # === STEP 8: Decision Generation with Emotional Weighting ===
    # Apply emotional weighting to decision making
    emotional_weight = compute_emotional_weight(state.affective_state)
    
    # === STEP 9: Online Learning Integration (Connect OnlineLearning to main loop) ===
    # Update learning state based on outcomes
    experience = build_experience(state.perception, brain_output)
    if state.energy > ENERGY_LOW
        incremental_update!(nothing, experience, state.learning_state)  # brain would be passed here
    end
    
    # === STEP 10: Action Proposal Generation ===
    proposal = generate_action_proposal(
        brain_output,
        state.perception,
        emotional_weight,
        state.cycle_count
    )
    
    # === STEP 11: Send to Rust Kernel for Approval ===
    if state.ipc_channel !== nothing
        send_to_kernel(state.ipc_channel, proposal)
    end
    
    # === STEP 12: Update Timing Metrics ===
    cycle_time_ns = time_ns() - start_time
    cycle_time_ms = Float32(cycle_time_ns / 1_000_000.0)
    
    # Running average of cycle time
    state.avg_cycle_time_ms = 0.9f0 * state.avg_cycle_time_ms + 0.1f0 * cycle_time_ms
    state.max_cycle_time_ms = max(state.max_cycle_time_ms, cycle_time_ms)
    
    # Update last cycle time
    state.last_cycle_time = start_time
    
    return proposal
end

"""
    infer_brain_fallback - Fallback brain inference when neural brain unavailable
"""
function infer_brain_fallback(brain_input::BrainInput, affective_state::AffectiveState)::BrainOutput
    # Simple heuristic-based inference as fallback
    # In production, this would call the actual neural brain
    
    actions = ["observe", "plan", "execute", "learn", "reflect"]
    confidence = 0.5f0 + 0.3f0 * affective_state.confidence
    value_estimate = 0.5f0
    uncertainty = 0.3f0 + 0.2f0 * (1.0f0 - affective_state.confidence)
    
    return BrainOutput(
        actions;
        confidence=confidence,
        value_estimate=value_estimate,
        uncertainty=uncertainty,
        reasoning="Fallback inference with emotional modulation"
    )
end

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

"""
    process_sensory_input - Process raw sensory input into processed features
"""
function process_sensory_input(buffer::SensoryBuffer, raw_input::Dict)::ProcessedSensory
    # Extract features from raw input
    visual = get(raw_input, "visual", zeros(Float32, 4))
    auditory = get(raw_input, "auditory", zeros(Float32, 4))
    telemetry = get(raw_input, "telemetry", zeros(Float32, 4))
    
    # Normalize and combine
    unified = vcat(visual, auditory, telemetry)
    
    return ProcessedSensory(unified, 1.0f0, Symbol("default"))
end

"""
    update_perception! - Update perception state from processed sensory
"""
function update_perception!(perception::Perception, processed::ProcessedSensory)
    # Map processed sensory to perception fields
    # This is a simplified mapping
    perception.confidence = processed.confidence
    
    # Add telemetry to system state
    for (i, val) in enumerate(processed.unified_perception)
        perception.system_state["sensor_$i"] = val
    end
end

"""
    update_affective_state! - Update emotional state based on perception
"""
function update_affective_state!(affective::AffectiveState, perception::Perception)
    # Update emotions based on current state
    # This triggers emotional responses to current situation
    
    # Check energy level and update valence
    if perception.energy_level < ENERGY_CRITICAL
        # Critical energy - fear response
        update_emotion!(affective, Fear, 0.8f0)
    elseif perception.energy_level < ENERGY_LOW
        # Low energy - concern
        update_emotion!(affective, Fear, 0.4f0)
    elseif perception.confidence > 0.8f0
        # High confidence - satisfaction
        update_emotion!(affective, Satisfaction, perception.confidence)
    else
        # Normal state - curiosity
        update_emotion!(affective, Curiosity, 0.3f0)
    end
end

"""
    build_perception_vector - Build 12D perception vector for brain input
"""
function build_perception_vector(perception::Perception)::Vector{Float32}
    # Build 12D perception vector from perception state
    vec = zeros(Float32, 12)
    
    # Energy (1)
    vec[1] = perception.energy_level
    
    # Confidence (2)
    vec[2] = perception.confidence
    
    # Threat level (3)
    vec[3] = perception.threat_level
    
    # Recent outcomes (4-7)
    n_outcomes = min(length(perception.recent_outcomes), 4)
    for i in 1:n_outcomes
        vec[3 + i] = perception.recent_outcomes[i] ? 1.0f0 : 0.0f0
    end
    
    # Active goals count (8)
    vec[8] = Float32(length(perception.active_goals)) / 10.0f0
    
    # System state summary (9-12)
    state_keys = ["cpu", "memory", "disk", "network"]
    for (i, key) in enumerate(state_keys)
        vec[8 + i] = get(perception.system_state, key, 0.5f0)
    end
    
    return vec
end

"""
    build_goal_context - Build goal context vector for brain input
"""
function build_goal_context(goals::Vector{Goal})::Vector{Float32}
    context = zeros(Float32, 8)
    
    for (i, goal) in enumerate(goals)
        if i >= 8 break end
        context[i] = goal.priority
    end
    
    return context
end

"""
    get_recent_rewards - Get recent reward signals for brain input
"""
function get_recent_rewards(perception::Perception)::Vector{Float32}
    rewards = zeros(Float32, 10)
    
    n = length(perception.recent_outcomes)
    for i in 1:min(n, 10)
        rewards[i] = perception.recent_outcomes[i] ? 1.0f0 : -0.5f0
    end
    
    return rewards
end

"""
    compute_emotional_weight - Compute emotional influence on decision making
"""
function compute_emotional_weight(affective::AffectiveState)::Float32
    # Emotional influence is bounded to max 30%
    # Positive emotions increase exploration, negative increase caution
    base_weight = 0.1f0
    
    valence_effect = affective.valence * 0.1f0
    arousal_effect = affective.arousal * 0.05f0
    
    return clamp(base_weight + valence_effect + arousal_effect, 0.0f0, 0.3f0)
end

"""
    build_experience - Build learning experience from current cycle
"""
function build_experience(perception::Perception, brain_output::BrainOutput)::Dict
    return Dict(
        "perception" => perception,
        "brain_output" => brain_output,
        "timestamp" => time_ns()
    )
end

"""
    generate_action_proposal - Generate final action proposal
"""
function generate_action_proposal(
    brain_output::BrainOutput,
    perception::Perception,
    emotional_weight::Float32,
    cycle_count::UInt64
)::ActionProposal
    # Select top action from brain output
    action = length(brain_output.proposed_actions) > 0 ? 
              brain_output.proposed_actions[1] : "observe"
    
    # Adjust confidence with emotional weight
    adjusted_confidence = brain_output.confidence * (1.0f0 + emotional_weight)
    
    # Simple cost/reward estimation
    predicted_cost = 0.1f0
    predicted_reward = brain_output.value_estimate
    
    # Risk based on uncertainty and emotional state
    risk = brain_output.uncertainty + emotional_weight * 0.5f0
    
    reasoning = "Cycle $cycle_count: $(brain_output.reasoning) [emotional_weight=$emotional_weight]"
    
    return ActionProposal(
        action,
        clamp(adjusted_confidence, 0.0f0, 1.0f0),
        predicted_cost,
        predicted_reward,
        clamp(risk, 0.0f0, 1.0f0),
        reasoning
    )
end

"""
    send_to_kernel - Send action proposal to Rust kernel via IPC
"""
function send_to_kernel(ipc::IPCChannel, proposal::ActionProposal)
    try
        proposal_dict = Dict(
            "capability_id" => proposal.capability_id,
            "confidence" => proposal.confidence,
            "predicted_cost" => proposal.predicted_cost,
            "predicted_reward" => proposal.predicted_reward,
            "risk" => proposal.risk,
            "reasoning" => proposal.reasoning
        )
        
        send_proposal(ipc, proposal_dict)
    catch e
        # Log error but don't crash - IPC failure shouldn't stop cognition
        @error "Failed to send proposal to kernel" exception=e
    end
end

# ============================================================================
# COGNITIVE LOOP RUNNER
# ============================================================================

"""
    run_cognitive_loop - Run the 136.1 Hz cognitive loop continuously

# Arguments
- `state::CognitiveState`: Initial cognitive state
- `input_channel::Channel{Dict}`: Channel for receiving input
- `output_channel::Channel{ActionProposal}`: Channel for sending output
- `duration_sec::Float64`: Duration to run (0 = infinite)
"""
function run_cognitive_loop(
    state::CognitiveState,
    input_channel::Channel{Dict},
    output_channel::Channel{ActionProposal};
    duration_sec::Float64=0.0
)
    start_time = time_ns()
    target_cycle_ns = UInt64(CYCLE_DURATION_SEC * 1e9)
    
    while true
        cycle_start = time_ns()
        
        # Check duration limit
        if duration_sec > 0.0
            elapsed = (time_ns() - start_time) / 1e9
            if elapsed >= duration_sec
                break
            end
        end
        
        # Try to get input (non-blocking)
        raw_input = try
            isready(input_channel) ? take!(input_channel) : Dict()
        catch
            Dict()
        end
        
        # Run cognitive cycle
        proposal = cognition_cycle(state, raw_input)
        
        # Send output
        try
            put!(output_channel, proposal)
        catch
            # Channel full - skip this output
        end
        
        # Sleep to maintain 136.1 Hz frequency
        elapsed_ns = time_ns() - cycle_start
        if elapsed_ns < target_cycle_ns
            sleep_ns(target_cycle_ns - elapsed_ns)
        end
    end
end

"""
    sleep_ns - Sleep for specified nanoseconds (Windows compatible)
"""
function sleep_ns(ns::UInt64)
    if ns > 0
        # Convert to seconds (fractional)
        sec = ns / 1e9
        if sec > 0.001
            sleep(sec)
        else
            # For very short sleeps, spin-wait
            spin_wait(ns)
        end
    end
end

function spin_wait(ns::UInt64)
    target = time_ns() + ns
    while time_ns() < target
        # Spin
    end
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    create_cognitive_state - Create initial cognitive state
"""
function create_cognitive_state()::CognitiveState
    return CognitiveState()
end

"""
    reset_cognitive_state! - Reset cognitive state to initial values
"""
function reset_cognitive_state!(state::CognitiveState)
    state.energy = 1.0f0
    state.mode = :active
    state.cycle_count = 0
    state.avg_cycle_time_ms = 0.0f0
    state.max_cycle_time_ms = 0.0f0
    state.attention_focus = String[]
    state.active_goals = Goal[]
end

"""
    get_cognitive_summary - Get summary of cognitive state
"""
function get_cognitive_summary(state::CognitiveState)::Dict
    return Dict(
        "energy" => state.energy,
        "mode" => state.mode,
        "cycle_count" => state.cycle_count,
        "avg_cycle_time_ms" => state.avg_cycle_time_ms,
        "max_cycle_time_ms" => state.max_cycle_time_ms,
        "attention_focus" => state.attention_focus,
        "active_goals" => length(state.active_goals),
        "affective_state" => get_affective_summary(state.affective_state)
    )
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    CognitiveState,
    cognition_cycle,
    run_cognitive_loop,
    create_cognitive_state,
    reset_cognitive_state!,
    get_cognitive_summary,
    COGNITIVE_FREQUENCY_HZ,
    CYCLE_DURATION_MS,
    ENERGY_CRITICAL,
    ENERGY_LOW,
    ENERGY_RECOVERY

end # module
