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

# Import metabolic controller (for integration)
include(joinpath(@__DIR__, "metabolic", "MetabolicController.jl"))
using .MetabolicController

# Import context module for multi-turn context (Stage 2)
include(joinpath(@__DIR__, "context", "Context.jl"))
using .Context

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

# Stage 2 - Multi-turn Context (NEW):
- `conversation_context::ConversationContext`: Multi-turn conversation history
- `working_memory::WorkingMemoryBuffer`: Short-term working memory
- `context_window::ContextWindow`: Context window optimization
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
    metabolic_state::MetabolicState  # Integrated metabolic controller
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
    
    # === STAGE 2: Multi-turn Context ===
    conversation_context::ConversationContext  # Conversation history
    working_memory::WorkingMemoryBuffer       # Short-term working memory
    context_window::ContextWindow              # Context window optimization
    
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
            initialize_metabolism(),       # metabolic_state (integrated)
            String[],                      # attention_focus
            Goal[],                        # active_goals
            zeros(Float32, 8),             # goal_context
            WorldModelState(),             # world_model
            0.0f0,                         # avg_cycle_time_ms
            0.0f0,                         # max_cycle_time_ms
            nothing,                       # ipc_channel
            nothing,                        # brain_input
            nothing,                         # brain_output
            # Stage 2: Multi-turn context
            ConversationContext(),         # conversation_context
            WorkingMemoryBuffer(),         # working_memory
            ContextWindow()                # context_window
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
    
    # === STEP 0: METABOLIC TICK (136.1 Hz) ===
    # Update metabolic state at the start of each cognitive cycle
    # This applies energy constraints to all subsequent operations
    operations = apply_metabolic_constraints(state.metabolic_state)
    
    # Sync cognitive state energy with metabolic state
    state.energy = state.metabolic_state.energy
    
    # Update cognitive mode based on metabolic mode
    if state.metabolic_state.mode == MODE_DREAMING
        state.mode = :dreaming
    elseif state.metabolic_state.mode == MODE_CRITICAL
        state.mode = :critical
    elseif state.metabolic_state.mode == MODE_RECOVERY
        state.mode = :recovery
    elseif state.metabolic_state.energy >= ENERGY_RECOVERY
        state.mode = :active
    else
        state.mode = :idle
    end
    
    # === STEP 0.5: STAGE 2 - MULTI-TURN CONTEXT PROCESSING ===
    # Extract user message from raw_input and add to conversation context
    if haskey(raw_input, "user_message") || haskey(raw_input, "message")
        user_msg = get(raw_input, "user_message", get(raw_input, "message", ""))
        if !isempty(user_msg)
            add_user_message!(state.conversation_context, user_msg)
            @debug "Added user message to conversation context" turn=state.conversation_context.turn_count
        end
    elseif haskey(raw_input, "input")
        # Alternative key for user input
        user_input = raw_input["input"]
        if user_input isa String && !isempty(user_input)
            add_user_message!(state.conversation_context, user_input)
        end
    end
    
    # Optimize context window periodically
    if state.cycle_count % 10 == 0
        update_summary!(state.conversation_context, state.context_window)
    end
    
    # === STEP 1: Sensory Processing ===
    processed_sensory = process_sensory_input(state.sensory_buffer, raw_input)
    
    # === STEP 2: Perception Formation ===
    update_perception!(state.perception, processed_sensory)
    
    # === STEP 3: Emotional Modulation (Connect Emotions to main loop) ===
    # Update affective state based on current perception and metabolic state
    # Trigger emotional responses based on system state
    if state.energy < ENERGY_CRITICAL
        # Critical energy - fear response
        update_emotion!(state.affective_state, :threat, Float32(0.8))
    elseif state.energy < ENERGY_LOW
        # Low energy - concern
        update_emotion!(state.affective_state, :threat, Float32(0.4))
    elseif state.perception.confidence > 0.8f0
        # High confidence - satisfaction
        update_emotion!(state.affective_state, :goal_achieved, state.perception.confidence)
    else
        # Normal state - curiosity
        update_emotion!(state.affective_state, :novelty, Float32(0.3))
    end
    
    # Apply emotional modulation to perception confidence (bounded to max 30%)
    emotional_modulation = apply_emotional_modulation(state.perception.confidence, state.affective_state)
    
    # Decay emotions over time
    decay_emotions!(state.affective_state)
    
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
    # Prepare brain input with emotional modulation AND multi-turn context
    # STAGE 2: Include context vector from conversation history
    context_vector = build_context_vector(state.conversation_context, state.working_memory)
    
    # Combine perception vector with context vector
    full_perception = vcat(perception_vector, context_vector)
    
    brain_input = BrainInput(
        full_perception;
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
    # Emotional state now causally modulates proposal confidence in Step 10
    
    # === STEP 9: Online Learning Integration (Connect OnlineLearning to main loop) ===
    # Update learning state based on outcomes and metabolic state
    # Learning is gated by metabolic state (apply_metabolic_gating! is called internally)
    experience = build_learning_experience(state.perception, brain_output, state.affective_state)
    
    # Only attempt learning if energy is sufficient and we have valid experience
    if state.energy > ENERGY_LOW && haskey(experience, :input) && haskey(experience, :target)
        learning_success = incremental_update!(nothing, experience, state.learning_state)
        
        # Process metabolic feedback based on learning outcome
        if learning_success
            process_metabolic_feedback!(state.metabolic_state, true, state.learning_state.confidence)
        else
            process_metabolic_feedback!(state.metabolic_state, false, 0.0f0)
        end
    end
    
    # === STEP 10: Action Proposal Generation ===
    proposal = generate_action_proposal(
        brain_output,
        state.perception,
        state.affective_state,
        state.cycle_count
    )
    
    # === STAGE 2: Store proposal in working memory for context across cycles ===
    store_working!(
        state.working_memory,
        "last_proposal",
        Dict(
            "capability" => proposal.capability_id,
            "confidence" => proposal.confidence,
            "reasoning" => proposal.reasoning,
            "cycle" => state.cycle_count
        );
        priority=0.7f0  # Higher priority for recent proposals
    )
    
    # Add system response to conversation context
    response_content = "[Action: $(proposal.capability_id)] $(proposal.reasoning)"
    add_system_message!(state.conversation_context, response_content; metadata=Dict(:confidence => proposal.confidence))
    
    # === STEP 11: METABOLIC UPDATE (136.1 Hz tick) ===
    # Update metabolic state based on operations performed this cycle
    # This tracks energy consumption and recovery
    update_metabolism!(state.metabolic_state, operations)
    
    # === STEP 12: Send to Rust Kernel for Approval ===
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
    build_learning_experience - Build learning experience from current cycle with proper format
    for incremental_update! function
"""
function build_learning_experience(
    perception::Perception, 
    brain_output::BrainOutput,
    affective_state::AffectiveState
)::Dict
    # Build perception vector as input
    input = build_perception_vector(perception)
    
    # Use brain output action as target (one-hot encoded would be ideal)
    action_idx = 1
    if length(brain_output.proposed_actions) > 0
        action_idx = parse(Int, split(string(brain_output.proposed_actions[1]), "")[1]) + 1
    end
    target = Float32[action_idx]
    
    # Calculate reward from brain output
    reward = brain_output.value_estimate
    
    return Dict(
        :input => input,
        :target => target,
        :reward => reward,
        :done => false,
        :confidence => brain_output.confidence,
        :emotional_influence => compute_value_modulation(affective_state),
        :timestamp => time_ns()
    )
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
    affective_state::AffectiveState,
    cycle_count::UInt64
)::ActionProposal
    # Select top action from brain output
    action = length(brain_output.proposed_actions) > 0 ? 
              brain_output.proposed_actions[1] : "observe"
    
    # Adjust confidence with emotional modulation (CONNECTED CAUSALLY)
    modulated_confidence = apply_emotional_modulation(brain_output.confidence, affective_state)
    
    # Simple cost/reward estimation
    predicted_cost = 0.1f0
    predicted_reward = brain_output.value_estimate
    
    # Risk based on uncertainty and emotional state
    # High arousal/low dominance increases perceived risk
    arousal_risk = affective_state.arousal * 0.2f0
    dominance_safety = (1.0f0 - affective_state.dominance) * 0.1f0
    risk = clamp(brain_output.uncertainty + arousal_risk + dominance_safety, 0.0f0, 1.0f0)
    
    reasoning = "Cycle $cycle_count: $(brain_output.reasoning) [affective_valence=$(round(affective_state.valence, digits=2))]"
    
    return ActionProposal(
        action,
        clamp(modulated_confidence, 0.0f0, 1.0f0),
        predicted_cost,
        predicted_reward,
        risk,
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
    
    # Reset metabolic state
    state.metabolic_state = initialize_metabolism()
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
        "affective_state" => get_affective_summary(state.affective_state),
        "metabolic_state" => get_metabolic_summary(state.metabolic_state)
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
    build_learning_experience,
    COGNITIVE_FREQUENCY_HZ,
    CYCLE_DURATION_MS,
    ENERGY_CRITICAL,
    ENERGY_LOW,
    ENERGY_RECOVERY

end # module
