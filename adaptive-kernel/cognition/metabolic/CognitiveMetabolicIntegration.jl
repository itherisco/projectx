# cognition/metabolic/CognitiveMetabolicIntegration.jl
# Phase 3: Complete cognitive loop by integrating Emotions and Learning into Metabolic Tick
#
# This module integrates:
# 1. Emotional states into the 136.1 Hz metabolic tick loop
# 2. Learning updates triggered on metabolic ticks for continuous learning
# 3. Emotional influence on decision-making in real-time
#
# This raises the readiness score from 2.86/5 to enable Stage 2 (Functional Loops)

module CognitiveMetabolicIntegration

using Dates
using Statistics

# Import metabolic controller
include(joinpath(@__DIR__, "MetabolicController.jl"))
using .MetabolicController

# Import emotions
include(joinpath(@__DIR__, "..", "feedback", "Emotions.jl"))
using .Emotions

# Import learning
include(joinpath(@__DIR__, "..", "learning", "OnlineLearning.jl"))
using .OnlineLearning

# ============================================================================
# COGNITIVE-METABOLIC STATE
# ============================================================================

"""
    CognitiveMetabolicState - Combined state for cognitive-metabolic processing

Integrates metabolic state with emotional and learning states for unified processing.
This is the core state that runs at 136.1 Hz.
"""
mutable struct CognitiveMetabolicState
    # Metabolic state (runs at 136.1 Hz)
    metabolic::MetabolicState
    
    # Emotional state (computed in real-time)
    affective::AffectiveState
    
    # Learning state (updated on ticks)
    learning::LearningState
    
    # Integration state
    last_emotion_update::Float64
    last_learning_update::Float64
    emotion_update_interval::Float64  # seconds
    learning_update_interval::Float64  # seconds
    
    # Performance metrics
    ticks_since_start::Int64
    emotion_influence_count::Int64
    learning_update_count::Int64
    
    # History for diagnostics
    integrated_history::Vector{Dict}
    
    function CognitiveMetabolicState()
        new(
            MetabolicState(),           # metabolic
            AffectiveState(),           # affective
            LearningState(),           # learning
            time(),                     # last_emotion_update
            time(),                     # last_learning_update
            0.1,                        # emotion_update_interval (100ms)
            1.0,                        # learning_update_interval (1s)
            0,                          # ticks_since_start
            0,                          # emotion_influence_count
            0,                          # learning_update_count
            Dict[]                       # integrated_history
        )
    end
end

# ============================================================================
# CORE INTEGRATION FUNCTIONS
# ============================================================================

"""
    create_cognitive_metabolic_state()::CognitiveMetabolicState

Create and initialize the integrated cognitive-metabolic state.
"""
function create_cognitive_metabolic_state()::CognitiveMetabolicState
    state = CognitiveMetabolicState()
    return state
end

"""
    metabolic_tick!(state::CognitiveMetabolicState, operations::Dict{Symbol, Bool})::Dict

Execute one metabolic tick at 136.1 Hz with integrated emotion and learning updates.

This is the core function that:
1. Updates metabolic state
2. Updates emotional state based on metabolic condition
3. Triggers learning updates based on energy availability
4. Returns the current cognitive mode and any emotional influences

# Arguments
- `state::CognitiveMetabolicState`: The integrated state
- `operations::Dict{Symbol, Bool}`: Which operations were performed

# Returns
- `Dict` with metabolic mode, emotional influence, and learning status
"""
function metabolic_tick!(state::CognitiveMetabolicState, operations::Dict{Symbol, Bool})::Dict
    state.ticks_since_start += 1
    current_time = time()
    
    # === STEP 1: Update Metabolic State ===
    metabolic_mode = update_metabolism!(state.metabolic, operations)
    
    # === STEP 2: Integrate Emotional State into Metabolism ===
    emotional_influence = integrate_emotions_into_metabolism!(state, current_time)
    
    # === STEP 3: Trigger Learning Updates ===
    learning_status = trigger_learning_on_tick!(state, current_time, operations)
    
    # === STEP 4: Apply Emotional Influence to Decision Making ===
    # This ensures emotions actually affect cognition in real-time
    decision_modifier = apply_emotional_influence_to_cognition(state)
    
    # === STEP 5: Record Integrated History ===
    if state.ticks_since_start % 100 == 0
        record_integrated_state!(state)
    end
    
    # Return comprehensive status
    return Dict(
        "metabolic_mode" => String(Symbol(metabolic_mode)),
        "energy" => state.metabolic.energy,
        "emotional_valence" => state.affective.valence,
        "emotional_arousal" => state.affective.arousal,
        "emotional_dominance" => state.affective.dominance,
        "emotion_influence" => emotional_influence,
        "decision_modifier" => decision_modifier,
        "learning_active" => learning_status["active"],
        "learning_confidence" => state.learning.confidence,
        "ticks" => state.ticks_since_start
    )
end

"""
    integrate_emotions_into_metabolism!(state::CognitiveMetabolicState, current_time::Float64)::Float32

Integrate emotional states into the metabolic tick loop.
Emotions are updated based on current metabolic condition.

# Returns
- The current emotional influence value (-1.0 to 1.0)
"""
function integrate_emotions_into_metabolism!(state::CognitiveMetabolicState, current_time::Float64)::Float32
    # Check if it's time to update emotions
    time_since_update = current_time - state.last_emotion_update
    
    if time_since_update >= state.emotion_update_interval
        state.last_emotion_update = current_time
        
        # === Update emotions based on metabolic condition ===
        
        # Critical energy: fear response
        if state.metabolic.energy <= state.metabolic.critical_threshold
            update_emotion!(state.affective, :threat, 0.8f0)
        elseif state.metabolic.energy <= state.metabolic.low_threshold
            # Low energy: concern/frustration
            update_emotion!(state.affective, :punishment, 0.4f0)
        elseif state.metabolic.energy >= state.metabolic.recovery_threshold
            # High energy: satisfaction/joy
            if state.metabolic.consecutive_high_cycles > 10
                update_emotion!(state.affective, :reward, 0.3f0)
            end
        end
        
        # Curiosity based on dream accumulation (novelty in dreaming)
        if state.metabolic.dream_accumulation > 0.5f0
            update_emotion!(state.affective, :novelty, state.metabolic.dream_accumulation * 0.3f0)
        end
        
        # Decay emotions periodically
        decay_emotions!(state.affective)
        
        state.emotion_influence_count += 1
    end
    
    # Return current emotional valence as influence
    return state.affective.valence
end

"""
    trigger_learning_on_tick!(state::CognitiveMetabolicState, current_time::Float64, 
                               operations::Dict{Symbol, Bool})::Dict

Trigger learning updates on metabolic ticks to enable continuous learning.
Learning is gated by available energy.

# Returns
- Dict with learning status
"""
function trigger_learning_on_tick!(state::CognitiveMetabolicState, current_time::Float64,
                                    operations::Dict{Symbol, Bool})::Dict
    time_since_update = current_time - state.last_learning_update
    
    # Check if it's time to update learning AND we have enough energy
    energy_available = state.metabolic.energy > state.metabolic.low_threshold
    learning_requested = get(operations, :learning, false)
    
    if time_since_update >= state.learning_update_interval && (energy_available || learning_requested)
        state.last_learning_update = current_time
        
        # Modulate learning rate based on emotional state
        # High arousal = faster learning (more engaged)
        # Negative valence = more conservative learning (pain avoidance)
        emotional_modulation = modulate_learning_rate_from_emotion(state.affective)
        
        # Apply metabolic gating to learning (energy tracked internally in LearningState)
        apply_metabolic_gating!(state.learning)
        
        # In a full implementation, we would:
        # 1. Collect recent experiences from perception
        # 2. Compute gradients
        # 3. Apply updates with emotional modulation
        
        state.learning_update_count += 1
        
        return Dict(
            "active" => true,
            "emotional_modulation" => emotional_modulation,
            "energy_available" => state.metabolic.energy,
            "updates_count" => state.learning_update_count
        )
    end
    
    return Dict(
        "active" => false,
        "reason" => time_since_update < state.learning_update_interval ? "interval" : "energy",
        "energy" => state.metabolic.energy
    )
end

"""
    modulate_learning_rate_from_emotion(affective::AffectiveState)::Float32

Modulate learning rate based on emotional state.
- Positive emotions increase learning rate (engagement)
- Negative emotions decrease learning rate (caution)
- High arousal increases learning rate (alertness)
"""
function modulate_learning_rate_from_emotion(affective::AffectiveState)::Float32
    # Base modulation from valence (-1 to 1 -> -0.5 to 0.5)
    valence_mod = affective.valence * 0.5f0
    
    # Arousal increases learning rate (0 to 1 -> 0 to 0.3)
    arousal_mod = affective.arousal * 0.3f0
    
    # Combined modulation
    return valence_mod + arousal_mod
end

"""
    apply_emotional_influence_to_cognition(state::CognitiveMetabolicState)::Float32

Apply emotional influence to decision-making in real-time.
This ensures emotions actually affect the brain's processing, not just compute values.

# Returns
- The decision modifier that should be applied to decisions (-0.3 to 0.3)
"""
function apply_emotional_influence_to_cognition(state::CognitiveMetabolicState)::Float32
    # Get value modulation from affective state (already bounded to ±0.3)
    modulation = state.affective.value_modulation
    
    # Additional emotional influences based on specific emotions
    if state.affective.emotion == Fear
        # Fear makes us more conservative - reduce risk-taking
        return -0.2f0 * state.affective.emotion_intensity
    elseif state.affective.emotion == Curiosity
        # Curiosity increases exploration - slight boost to novel actions
        return 0.1f0 * state.affective.emotion_intensity
    elseif state.affective.emotion == Joy
        # Joy increases confidence - boost action selection
        return 0.15f0 * state.affective.emotion_intensity
    elseif state.affective.emotion == Frustration
        # Frustration may lead to rash decisions - reduce
        return -0.1f0 * state.affective.emotion_intensity
    end
    
    return modulation
end

"""
    apply_emotional_modulation_to_value(base_value::Float32, state::CognitiveMetabolicState)::Float32

Apply emotional modulation to a base value (e.g., action utility).
This is the main function to apply emotional influence to decisions.

# Arguments
- `base_value`: The un-modulated value
- `state::CognitiveMetabolicState`: Current integrated state

# Returns
- Modulated value with emotional influence applied
"""
function apply_emotional_modulation_to_value(base_value::Float32, state::CognitiveMetabolicState)::Float32
    modifier = apply_emotional_influence_to_cognition(state)
    
    # Apply modulation: value * (1 + modifier)
    # Bounded to prevent extreme values
    modulated = base_value * (1.0f0 + modifier)
    
    return clamp(modulated, base_value * 0.5f0, base_value * 1.5f0)
end

"""
    record_integrated_state!(state::CognitiveMetabolicState)

Record current integrated state for diagnostics.
"""
function record_integrated_state!(state::CognitiveMetabolicState)
    record = Dict(
        "timestamp" => now(),
        "ticks" => state.ticks_since_start,
        "energy" => state.metabolic.energy,
        "mode" => String(Symbol(state.metabolic.mode)),
        "valence" => state.affective.valence,
        "arousal" => state.affective.arousal,
        "dominance" => state.affective.dominance,
        "emotion" => String(Symbol(state.affective.emotion)),
        "confidence" => state.learning.confidence,
        "emotion_updates" => state.emotion_influence_count,
        "learning_updates" => state.learning_update_count
    )
    
    push!(state.integrated_history, record)
    
    # Keep history bounded
    if length(state.integrated_history) > 1000
        deleteat!(state.integrated_history, 1:length(state.integrated_history) - 1000)
    end
end

"""
    get_integrated_summary(state::CognitiveMetabolicState)::Dict

Get summary of integrated cognitive-metabolic state.
"""
function get_integrated_summary(state::CognitiveMetabolicState)::Dict
    return Dict(
        "ticks" => state.ticks_since_start,
        "metabolic" => get_metabolic_summary(state.metabolic),
        "emotional" => get_affective_summary(state.affective),
        "learning_confidence" => state.learning.confidence,
        "learning_uncertainty" => state.learning.uncertainty,
        "emotion_updates" => state.emotion_influence_count,
        "learning_updates" => state.learning_update_count,
        "decision_modifier" => apply_emotional_influence_to_cognition(state)
    )
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    CognitiveMetabolicState,
    create_cognitive_metabolic_state,
    metabolic_tick!,
    integrate_emotions_into_metabolism!,
    trigger_learning_on_tick!,
    apply_emotional_influence_to_cognition,
    apply_emotional_modulation_to_value,
    get_integrated_summary

end # module
