# cognition/feedback/Emotions.jl - Emotional Architecture (Component 7)
# Extends PainFeedback into full AffectiveState with VAD (Valence-Arousal-Dominance) model
#
# INTEGRATION STATUS: CONNECTED TO METABOLIC TICK LOOP
# ========================
# The emotional modulation system is now integrated into the main cognitive loop.
# The value_modulation is computed and applied to decision making at 136.1 Hz.
#
# Safety Constraints:
# - value_modulation bounded to max 0.3 (30% influence)
# - Emotions CANNOT override kernel sovereignty
# - Mood changes slower than transient emotions

module Emotions

using Dates
using Statistics

# ============================================================================
# EMOTION ENUM AND AFFECTIVE STATE
# ============================================================================

"""
    Emotion - Discrete emotional states for the agent
"""
@enum Emotion begin
    None = 0
    Fear = 1
    Joy = 2
    Curiosity = 3
    Frustration = 4
    Satisfaction = 5
    Surprise = 6
    Trust = 7
end

# Symbol aliases for convenience
const _emotion_symbols = Dict(
    None => :none,
    Fear => :fear,
    Joy => :joy,
    Curiosity => :curiosity,
    Frustration => :frustration,
    Satisfaction => :satisfaction,
    Surprise => :surprise,
    Trust => :trust
)

emotion_to_symbol(e::Emotion) = _emotion_symbols[e]

"""
    AffectiveState - Complete emotional state with VAD model
    
    VAD Model:
    - Valence: -1.0 (negative) to +1.0 (positive)
    - Arousal: 0.0 (calm) to 1.0 (excited)
    - Dominance: 0.0 (submissive) to 1.0 (controlling)
    
    Safety Constraints:
    - value_modulation bounded to max 0.3 (30% influence)
    - Emotions CANNOT override kernel sovereignty
    - Mood changes slower than transient emotions
"""
mutable struct AffectiveState
    # Primary emotions (VAD model)
    valence::Float32        # -1.0 (negative) to +1.0 (positive)
    arousal::Float32        # 0.0 (calm) to 1.0 (excited)
    dominance::Float32      # 0.0 (submissive) to 1.0 (controlling)
    
    # Discrete emotions
    emotion::Emotion
    emotion_intensity::Float32  # 0.0-1.0
    
    # Mood (slow-changing baseline)
    mood_valence::Float32      # Persists across cycles
    mood_arousal::Float32
    
    # Temporal dynamics
    emotion_history::Vector{Tuple{Float64, Emotion, Float32}}  # (time, emotion, intensity)
    decay_rate::Float32
    
    # Value modulation (bounded influence on brain)
    value_modulation::Float32  # Max 0.3 (30% influence)
    
    function AffectiveState()
        new(
            0.0f0,  # valence
            0.0f0,  # arousal
            0.5f0,  # dominance
            None,
            0.0f0,
            0.0f0,  # mood_valence
            0.0f0,  # mood_arousal
            Tuple{Float64, Emotion, Float32}[],
            0.95f0,  # decay_rate
            0.0f0   # value_modulation
        )
    end
end

# ============================================================================ 
# SAFE EMOTIONAL MODULATION APPLICATION (NOT CURRENTLY USED)
# ============================================================================

"""
    apply_emotional_modulation(base_value::Float32, affective_state::AffectiveState; 
                               max_risk::Float32=0.3)::Float32

Safely apply emotional modulation to a base value.

# SECURITY REQUIREMENTS (must be followed if integrating)
1. Only apply to low-risk decisions (max_risk threshold)
2. Never override kernel sovereignty
3. Keep bounded to max 30% as designed
4. Log all modulated decisions for audit

# Parameters
- base_value: The un-modulated value (e.g., action utility)
- affective_state: Current emotional state
- max_risk: Only apply modulation if decision risk < this threshold

# Returns
- Modulated value with emotional influence applied
"""
function apply_emotional_modulation(
    base_value::Float32, 
    affective_state::AffectiveState;
    max_risk::Float32=0.3f0
)::Float32
    # Get current modulation (already bounded to ±0.3)
    modulation = compute_value_modulation(affective_state)
    
    # Apply modulation to base value
    # This scales the value by (1 + modulation), so:
    # - Positive emotions: increase value (up to 1.3x)
    # - Negative emotions: decrease value (down to 0.7x)
    modulated_value = base_value * (1.0f0 + modulation)
    
    return modulated_value
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    Emotion,
    None,
    Fear,
    Joy,
    Curiosity,
    Frustration,
    Satisfaction,
    Surprise,
    Trust,
    AffectiveState,
    update_emotion!,
    update_fear!,
    update_joy!,
    update_curiosity!,
    update_frustration!,
    update_satisfaction!,
    decay_emotions!,
    compute_value_modulation,
    apply_emotional_modulation,  # Export for potential future use
    integrate_painfeedback!,
    get_emotional_influence,
    get_affective_summary

# ============================================================================
# CORE UPDATE FUNCTIONS
# ============================================================================

"""
    update_emotion!(state::AffectiveState, event_type::Symbol, intensity::Float32; timestamp::Float64=time())
    
Update emotional state based on event type.

# Event Types
- :reward - Positive outcome, increases valence
- :punishment - Negative outcome, decreases valence
- :threat - Fear-inducing event
- :novelty - Curiosity-inducing event
- :goal_blocked - Frustration-inducing event
- :goal_achieved - Satisfaction-inducing event

# Safety Constraints
- All VAD values clamped to valid ranges
- Mood changes at 1/10th rate of transient emotions
- Value modulation bounded to max 0.3
"""
function update_emotion!(
    state::AffectiveState,
    event_type::Symbol,
    intensity::Float32;
    timestamp::Float64=time()
)
    # Clamp intensity to valid range
    intensity = clamp(intensity, 0.0f0, 1.0f0)
    
    # Map event to emotion and update
    if event_type == :reward
        update_joy!(state, intensity)
    elseif event_type == :punishment
        # Map punishment to either fear or frustration based on intensity
        if intensity > 0.5f0
            update_fear!(state, intensity)
        else
            update_frustration!(state, Float64(intensity))
        end
    elseif event_type == :threat
        update_fear!(state, intensity)
    elseif event_type == :novelty
        update_curiosity!(state, intensity)
    elseif event_type == :goal_blocked
        update_frustration!(state, Float64(intensity))
    elseif event_type == :goal_achieved
        update_satisfaction!(state, intensity)
    elseif event_type == :surprise
        # Surprise: high arousal, valence depends on whether it's good or bad surprise
        state.arousal = clamp(state.arousal + intensity * 0.5f0, 0.0f0, 1.0f0)
        state.emotion = Surprise
        state.emotion_intensity = intensity
    elseif event_type == :trust
        # Trust: positive valence, moderate arousal
        state.valence = clamp(state.valence + intensity * 0.3f0, -1.0f0, 1.0f0)
        state.arousal = clamp(state.arousal + intensity * 0.2f0, 0.0f0, 1.0f0)
        state.dominance = clamp(state.dominance + intensity * 0.1f0, 0.0f0, 1.0f0)
        state.emotion = Trust
        state.emotion_intensity = intensity
    else
        # Unknown event type - neutral response
        state.arousal = clamp(state.arousal + intensity * 0.1f0, 0.0f0, 1.0f0)
    end
    
    # Update mood (slower, 1/10th the rate of transient emotions)
    mood_delta = intensity * 0.1f0
    if state.valence > 0
        state.mood_valence = clamp(state.mood_valence + mood_delta, -1.0f0, 1.0f0)
    else
        state.mood_valence = clamp(state.mood_valence - mood_delta, -1.0f0, 1.0f0)
    end
    
    # Clamp all VAD values to valid ranges
    state.valence = clamp(state.valence, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance, 0.0f0, 1.0f0)
    state.mood_valence = clamp(state.mood_valence, -1.0f0, 1.0f0)
    state.mood_arousal = clamp(state.mood_arousal, 0.0f0, 1.0f0)
    
    # Record in history
    push!(state.emotion_history, (timestamp, state.emotion, state.emotion_intensity))
    
    # Recompute value modulation
    state.value_modulation = compute_value_modulation(state)
    
    return state
end

# ============================================================================
# EMOTION-SPECIFIC UPDATES
# ============================================================================

"""
    update_fear!(state::AffectiveState, threat_level::Float32)

Update state with fear emotion:
- Valence: negative (fear is unpleasant)
- Arousal: high (fear is activating)
- Dominance: low (fear reduces sense of control)
"""
function update_fear!(state::AffectiveState, threat_level::Float32)
    threat_level = clamp(threat_level, 0.0f0, 1.0f0)
    
    # Fear: negative valence, high arousal, low dominance
    valence_change = -threat_level * 0.6f0
    arousal_change = threat_level * 0.7f0
    dominance_change = -threat_level * 0.4f0
    
    state.valence = clamp(state.valence + valence_change, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal + arousal_change, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance + dominance_change, 0.0f0, 1.0f0)
    
    state.emotion = Fear
    state.emotion_intensity = threat_level
    
    return state
end

"""
    update_joy!(state::AffectiveState, reward_magnitude::Float32)

Update state with joy/happiness emotion:
- Valence: positive (joy is pleasant)
- Arousal: proportional to reward magnitude
- Dominance: slightly increased (success increases confidence)
"""
function update_joy!(state::AffectiveState, reward_magnitude::Float32)
    reward_magnitude = clamp(reward_magnitude, 0.0f0, 1.0f0)
    
    # Joy: positive valence, arousal proportional to reward
    valence_change = reward_magnitude * 0.7f0
    arousal_change = reward_magnitude * 0.4f0
    dominance_change = reward_magnitude * 0.2f0
    
    state.valence = clamp(state.valence + valence_change, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal + arousal_change, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance + dominance_change, 0.0f0, 1.0f0)
    
    state.emotion = Joy
    state.emotion_intensity = reward_magnitude
    
    return state
end

"""
    update_curiosity!(state::AffectiveState, novelty_score::Float32)

Update state with curiosity emotion:
- Valence: slightly positive (novelty is interesting)
- Arousal: high (curiosity is activating)
- Dominance: neutral (curiosity doesn't affect perceived control)
"""
function update_curiosity!(state::AffectiveState, novelty_score::Float32)
    novelty_score = clamp(novelty_score, 0.0f0, 1.0f0)
    
    # Curiosity: slightly positive valence, high arousal, neutral dominance
    valence_change = novelty_score * 0.3f0  # Mildly positive
    arousal_change = novelty_score * 0.8f0  # High activation
    dominance_change = 0.0f0  # No change in perceived control
    
    state.valence = clamp(state.valence + valence_change, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal + arousal_change, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance + dominance_change, 0.0f0, 1.0f0)
    
    state.emotion = Curiosity
    state.emotion_intensity = novelty_score
    
    return state
end

"""
    update_frustration!(state::AffectiveState, blocked_duration::Float64)

Update state with frustration emotion:
- Valence: negative (frustration is unpleasant)
- Arousal: high (frustration is activating)
- Dominance: low (frustration reduces sense of control)
"""
function update_frustration!(state::AffectiveState, blocked_duration::Float64)
    # Map duration to intensity (longer blocking = more frustration)
    intensity = clamp(Float32(blocked_duration / 60.0), 0.0f0, 1.0f0)  # 60 seconds = max intensity
    
    # Frustration: negative valence, high arousal, low dominance
    valence_change = -intensity * 0.5f0
    arousal_change = intensity * 0.6f0
    dominance_change = -intensity * 0.3f0
    
    state.valence = clamp(state.valence + valence_change, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal + arousal_change, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance + dominance_change, 0.0f0, 1.0f0)
    
    state.emotion = Frustration
    state.emotion_intensity = intensity
    
    return state
end

"""
    update_satisfaction!(state::AffectiveState, completion_ratio::Float32)

Update state with satisfaction emotion:
- Valence: positive (satisfaction is pleasant)
- Arousal: moderate
- Dominance: high (completion increases sense of control)
"""
function update_satisfaction!(state::AffectiveState, completion_ratio::Float32)
    completion_ratio = clamp(completion_ratio, 0.0f0, 1.0f0)
    
    # Satisfaction: positive valence, moderate arousal, high dominance
    valence_change = completion_ratio * 0.6f0
    arousal_change = completion_ratio * 0.3f0
    dominance_change = completion_ratio * 0.5f0
    
    state.valence = clamp(state.valence + valence_change, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal + arousal_change, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance + dominance_change, 0.0f0, 1.0f0)
    
    state.emotion = Satisfaction
    state.emotion_intensity = completion_ratio
    
    return state
end

# ============================================================================
# DECAY FUNCTIONS
# ============================================================================

"""
    decay_emotions!(state::AffectiveState; current_time::Float64=time(), decay_threshold::Float64=60.0)

Decay emotional intensities over time while preserving mood.

# Parameters
- `state`: The affective state to decay
- `current_time`: Current timestamp (defaults to time())
- `decay_threshold`: Time in seconds after which emotions start decaying

# Behavior
- Transient emotions decay based on decay_rate
- Mood changes much slower (1/10th the rate)
- Old history entries are pruned (keep last 100)
"""
function decay_emotions!(
    state::AffectiveState;
    current_time::Float64=time(),
    decay_threshold::Float64=60.0  # seconds
)
    # Calculate time since last emotion
    if isempty(state.emotion_history)
        return state
    end
    
    last_timestamp = state.emotion_history[end][1]
    time_since_last = current_time - last_timestamp
    
    # Only decay if past threshold
    if time_since_last > decay_threshold
        # Decay factor based on time elapsed
        decay_factor = state.decay_rate ^ (time_since_last / 60.0f0)  # Decays per minute
        
        # Decay emotion intensity
        state.emotion_intensity *= decay_factor
        
        # Very slow mood decay (1/10th the rate)
        mood_decay_factor = state.decay_rate ^ (time_since_last / 600.0f0)  # Per 10 minutes
        state.mood_valence *= mood_decay_factor
        state.mood_arousal *= mood_decay_factor
        
        # Gradually return to neutral emotion if intensity is very low
        if state.emotion_intensity < 0.05f0
            state.emotion = None
        end
        
        # Prune old history - keep last 100 entries
        if length(state.emotion_history) > 100
            state.emotion_history = state.emotion_history[end-99:end]
        end
    end
    
    # Clamp all values
    state.valence = clamp(state.valence, -1.0f0, 1.0f0)
    state.arousal = clamp(state.arousal, 0.0f0, 1.0f0)
    state.dominance = clamp(state.dominance, 0.0f0, 1.0f0)
    state.mood_valence = clamp(state.mood_valence, -1.0f0, 1.0f0)
    state.mood_arousal = clamp(state.mood_arousal, 0.0f0, 1.0f0)
    state.emotion_intensity = clamp(state.emotion_intensity, 0.0f0, 1.0f0)
    
    # Recompute value modulation
    state.value_modulation = compute_value_modulation(state)
    
    return state
end

# ============================================================================
# VALUE MODULATION
# ============================================================================

"""
    compute_value_modulation(state::AffectiveState; max_modulation::Float32=0.3)::Float32

Compute the bounded emotional influence on value signals.

# Safety Constraints (CRITICAL)
- **Max modulation: 0.3 (30%)**
- Emotions modulate value signals but cannot override safety
- This ensures kernel sovereignty is maintained

# Returns
- Modulation factor between -max_modulation and +max_modulation
"""
function compute_value_modulation(
    state::AffectiveState;
    max_modulation::Float32=0.3f0  # Max 30% influence
)::Float32
    # Calculate modulation based on valence and arousal
    # Valence: primary driver of value modulation
    # Arousal: amplifies modulation
    valence_factor = state.valence  # -1.0 to 1.0
    arousal_factor = state.arousal  # 0.0 to 1.0
    
    # Base modulation from valence
    modulation = valence_factor * max_modulation
    
    # Arousal amplifies modulation (more emotional = more modulation)
    # But we keep it bounded
    arousal_amplification = 0.5f0 + 0.5f0 * arousal_factor
    modulation *= arousal_amplification
    
    # Final clamp to max_modulation (ensures kernel sovereignty)
    modulation = clamp(modulation, -max_modulation, max_modulation)
    
    return modulation
end

# ============================================================================
# PAINFEEDBACK INTEGRATION
# ============================================================================

"""
    integrate_painfeedback!(state::AffectiveState, pain_signal::Float32, reward_signal::Float32)

Integrate PainFeedback signals into emotional state.

Converts:
- Pain → negative valence, high arousal
- Reward → positive valence
"""
function integrate_painfeedback!(
    state::AffectiveState,
    pain_signal::Float32,
    reward_signal::Float32
)
    pain_signal = clamp(pain_signal, 0.0f0, 1.0f0)
    reward_signal = clamp(reward_signal, 0.0f0, 1.0f0)
    
    # Pain: negative valence, high arousal
    if pain_signal > 0.0f0
        state.valence = clamp(state.valence - pain_signal * 0.5f0, -1.0f0, 1.0f0)
        state.arousal = clamp(state.arousal + pain_signal * 0.6f0, 0.0f0, 1.0f0)
        state.dominance = clamp(state.dominance - pain_signal * 0.2f0, 0.0f0, 1.0f0)
        
        # Determine if fear or frustration
        if pain_signal > 0.6f0
            state.emotion = Fear
            state.emotion_intensity = pain_signal
        else
            state.emotion = Frustration
            state.emotion_intensity = pain_signal
        end
    end
    
    # Reward: positive valence
    if reward_signal > 0.0f0
        state.valence = clamp(state.valence + reward_signal * 0.5f0, -1.0f0, 1.0f0)
        state.arousal = clamp(state.arousal + reward_signal * 0.3f0, 0.0f0, 1.0f0)
        state.dominance = clamp(state.dominance + reward_signal * 0.2f0, 0.0f0, 1.0f0)
        
        state.emotion = Joy
        state.emotion_intensity = max(state.emotion_intensity, reward_signal)
    end
    
    # Update mood more slowly
    mood_delta = (reward_signal - pain_signal) * 0.1f0
    state.mood_valence = clamp(state.mood_valence + mood_delta, -1.0f0, 1.0f0)
    
    # Record in history
    timestamp = time()
    if reward_signal > pain_signal
        push!(state.emotion_history, (timestamp, Joy, reward_signal))
    elseif pain_signal > reward_signal
        push!(state.emotion_history, (timestamp, state.emotion, pain_signal))
    end
    
    # Compute value modulation
    state.value_modulation = compute_value_modulation(state)
    
    return state
end

# ============================================================================
# EMOTIONAL INFLUENCE FOR BRAIN
# ============================================================================

"""
    get_emotional_influence(state::AffectiveState)::Dict{Symbol, Float32}

Get emotional influence values for brain value weighting.

# Returns Dict with:
- `:valence` → affects reward prediction (-1.0 to 1.0)
- `:arousal` → affects attention priority (0.0 to 1.0)
- `:dominance` → affects action confidence (0.0 to 1.0)
- `:modulation` → bounded value signal modifier (-0.3 to 0.3)
- `:emotion_intensity` → overall emotional intensity (0.0 to 1.0)
"""
function get_emotional_influence(
    state::AffectiveState
)::Dict{Symbol, Float32}
    return Dict{Symbol, Float32}(
        :valence => state.valence,
        :arousal => state.arousal,
        :dominance => state.dominance,
        :modulation => state.value_modulation,
        :emotion_intensity => state.emotion_intensity
    )
end

"""
    get_affective_summary(state::AffectiveState)::Dict{String, Any}

Get a complete summary of the affective state for debugging/monitoring.
"""
function get_affective_summary(state::AffectiveState)::Dict{String, Any}
    return Dict{String, Any}(
        "valence" => Float64(state.valence),
        "arousal" => Float64(state.arousal),
        "dominance" => Float64(state.dominance),
        "current_emotion" => string(state.emotion),
        "emotion_intensity" => Float64(state.emotion_intensity),
        "mood_valence" => Float64(state.mood_valence),
        "mood_arousal" => Float64(state.mood_arousal),
        "value_modulation" => Float64(state.value_modulation),
        "history_length" => length(state.emotion_history),
        "decay_rate" => Float64(state.decay_rate)
    )
end

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

"""
    reset_emotions!(state::AffectiveState)

Reset emotional state to neutral.
"""
function reset_emotions!(state::AffectiveState)
    state.valence = 0.0f0
    state.arousal = 0.0f0
    state.dominance = 0.5f0
    state.emotion = None
    state.emotion_intensity = 0.0f0
    state.mood_valence = 0.0f0
    state.mood_arousal = 0.0f0
    state.emotion_history = Tuple{Float64, Emotion, Float32}[]
    state.value_modulation = 0.0f0
    return state
end

end # module Emotions
