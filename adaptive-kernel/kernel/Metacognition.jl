# kernel/Metacognition.jl - Metacognitive System for ITHERIS Tier 7
# Provides self-awareness and cognitive regulation capabilities
# This file should be included from Kernel.jl as a submodule

module Metacognition

using Statistics
using Dates

# Load shared types from parent
# This allows the module to be used both standalone and as part of Kernel
include("../types.jl")
using .SharedTypes

# Import specific types needed for metacognitive functions
using .SharedTypes: ActionProposal, ReflectionEvent

# Import Self-Model types for integration
using .SharedTypes: SelfModel, get_capability_rating, should_adjust_confidence

# Import Identity Drift Detection for integration
using .SharedTypes: DriftDetector, check_behavioral_drift, get_drift_severity, get_drift_alerts

# Export public functions
export estimate_cognitive_friction, should_override_action, 
       create_metacognitive_override, metacognitive_loop,
       MetacognitiveAction,
       # Cognitive Friction Monitor exports
       CognitiveFrictionMonitor, create_cognitive_friction_monitor,
       calculate_entropy, needs_strategy_shift, check_cognitive_friction,
       StrategyShiftEvent,
       # Self-Model integration exports
       integrate_self_model_with_metacognition, should_trigger_deliberate_reflection

# ============================================================================
# MetacognitiveAction Enum
# ============================================================================

@enum MetacognitiveAction begin
    STRATEGY_SHIFT
    EXTERNAL_SEARCH
    RETRY
    ABORT
end

# ============================================================================
# Cognitive Friction Monitor - Tier 7 Metacognition
# ============================================================================

"""
    CognitiveFrictionMonitor - Monitors decision uncertainty through entropy analysis
    
    Tracks Shannon entropy of action probability distributions to detect when
    the cognitive system is experiencing high uncertainty (cognitive friction).
    When entropy remains high for consecutive cycles, triggers a Strategy Shift.
    
    Fields:
    - entropy_history: Vector of entropy values from recent cycles
    - max_history: Maximum number of entropy values to track
    - entropy_threshold: Threshold above which entropy is considered high (default 0.85)
    - cycle_threshold: Number of consecutive high-entropy cycles before triggering shift (default 3)
    - strategy_shift_count: Number of strategy shifts triggered
    - last_shift_cycle: Cycle number of last strategy shift
"""
mutable struct CognitiveFrictionMonitor
    entropy_history::Vector{Float64}
    max_history::Int
    entropy_threshold::Float64
    cycle_threshold::Int
    strategy_shift_count::Int
    last_shift_cycle::Int
    
    function CognitiveFrictionMonitor(
        max_history::Int=10,
        entropy_threshold::Float64=0.85,
        cycle_threshold::Int=3
    )
        return new(
            Float64[],
            max_history,
            entropy_threshold,
            cycle_threshold,
            0,
            0
        )
    end
end

"""
    create_cognitive_friction_monitor(;kwargs...) -> CognitiveFrictionMonitor
    
    Factory function to create a CognitiveFrictionMonitor with custom parameters.
"""
function create_cognitive_friction_monitor(
    max_history::Int=10,
    entropy_threshold::Float64=0.85,
    cycle_threshold::Int=3
)::CognitiveFrictionMonitor
    return CognitiveFrictionMonitor(max_history, entropy_threshold, cycle_threshold)
end

"""
    calculate_entropy(probabilities::Vector{Float64})::Float64
    
    Calculate normalized Shannon entropy of a probability distribution.
    
    Formula: H = -Σ(p_i * log(p_i)) / log(n)
    
    Returns entropy in [0, 1] range:
    - 0.0: Perfect certainty (one action has probability 1.0)
    - 1.0: Maximum uncertainty (uniform distribution)
    
    Arguments:
    - probabilities: Vector of action probabilities (should sum to ~1.0)
"""
function calculate_entropy(probabilities::Vector{Float64})::Float64
    # Handle edge cases
    n = length(probabilities)
    
    if n == 0
        return 0.0
    end
    
    if n == 1
        return 0.0  # Single action = perfect certainty
    end
    
    # Filter out zero probabilities to avoid log(0)
    # and normalize the input
    total = sum(probabilities)
    if total <= 0.0
        return 0.0
    end
    
    # Normalize probabilities
    normalized_probs = probabilities ./ total
    
    # Calculate Shannon entropy: H = -Σ(p_i * log(p_i))
    entropy = 0.0
    for p in normalized_probs
        if p > 0.0
            entropy -= p * log(p)
        end
    end
    
    # Normalize to [0, 1] range using log(n) as maximum entropy
    max_entropy = log(n)
    if max_entropy > 0.0
        entropy = entropy / max_entropy
    end
    
    return clamp(entropy, 0.0, 1.0)
end

"""
    needs_strategy_shift(monitor::CognitiveFrictionMonitor)::Bool
    
    Determine if a strategy shift should be triggered.
    
    Returns true if entropy has exceeded threshold for more than
    cycle_threshold consecutive cycles.
"""
function needs_strategy_shift(monitor::CognitiveFrictionMonitor)::Bool
    history = monitor.entropy_history
    threshold = monitor.entropy_threshold
    cycle_threshold = monitor.cycle_threshold
    
    # Need at least cycle_threshold entries to trigger
    if length(history) < cycle_threshold
        return false
    end
    
    # Check the last cycle_threshold entries
    consecutive_high = 0
    for i in length(history):-1:max(1, length(history) - cycle_threshold + 1)
        if history[i] > threshold
            consecutive_high += 1
        else
            break  # Stop counting at first low entropy
        end
    end
    
    return consecutive_high >= cycle_threshold
end

"""
    StrategyShiftEvent - Event logged when a strategy shift occurs
"""
struct StrategyShiftEvent
    cycle::Int
    entropy::Float64
    entropy_history::Vector{Float64}
    reason::String
    timestamp::DateTime
end

"""
    check_cognitive_friction(
        kernel_state::Any,
        monitor::CognitiveFrictionMonitor,
        action_probs::Vector{Float64}
    )::Tuple{Float64, Bool, Union{StrategyShiftEvent, Nothing}}
    
    Main cognitive friction check function.
    
    Steps:
    1. Calculate entropy of action probability distribution
    2. Update monitor's entropy history
    3. Check if strategy shift is needed
    4. If shift triggered, log event and increment shift count
    
    Returns:
    - entropy: The calculated entropy value
    - needs_shift: Whether strategy shift was triggered
    - event: StrategyShiftEvent if shift triggered, nothing otherwise
"""
function check_cognitive_friction(
    kernel_state::Any,
    monitor::CognitiveFrictionMonitor,
    action_probs::Vector{Float64}
)::Tuple{Float64, Bool, Union{StrategyShiftEvent, Nothing}}
    
    # Get cycle number from kernel state if available
    cycle_num = 0
    try
        cycle_num = kernel_state.cycle
    catch
        cycle_num = 0
    end
    
    # Step 1: Calculate entropy
    entropy = calculate_entropy(action_probs)
    
    # Step 2: Update entropy history
    push!(monitor.entropy_history, entropy)
    
    # Trim history if it exceeds max
    if length(monitor.entropy_history) > monitor.max_history
        monitor.entropy_history = monitor.entropy_history[end-monitor.max_history+1:end]
    end
    
    # Step 3: Check if strategy shift is needed
    needs_shift = false
    event = nothing
    
    if needs_strategy_shift(monitor)
        needs_shift = true
        monitor.strategy_shift_count += 1
        monitor.last_shift_cycle = cycle_num
        
        # Create strategy shift event
        event = StrategyShiftEvent(
            cycle_num,
            entropy,
            copy(monitor.entropy_history),
            "High entropy ($entropy) for $(monitor.cycle_threshold)+ consecutive cycles",
            now()
        )
        
        @info "[Metacognition] Strategy Shift triggered!" 
              cycle=cycle_num 
              entropy=entropy 
              shift_count=monitor.strategy_shift_count
        
        # Clear recent entropy history to allow recovery
        # This prevents immediate re-triggering
        monitor.entropy_history = Float64[]
    end
    
    return entropy, needs_shift, event
end

"""
    get_monitor_stats(monitor::CognitiveFrictionMonitor)::Dict{String, Any}
    
    Get statistics about the cognitive friction monitor.
"""
function get_monitor_stats(monitor::CognitiveFrictionMonitor)::Dict{String, Any}
    return Dict(
        "entropy_history" => monitor.entropy_history,
        "current_entropy" => isempty(monitor.entropy_history) ? 0.0 : monitor.entropy_history[end],
        "max_history" => monitor.max_history,
        "entropy_threshold" => monitor.entropy_threshold,
        "cycle_threshold" => monitor.cycle_threshold,
        "strategy_shift_count" => monitor.strategy_shift_count,
        "last_shift_cycle" => monitor.last_shift_cycle,
        "needs_shift" => needs_strategy_shift(monitor)
    )
end

# ============================================================================
# MetacognitiveAction Enum
# ============================================================================

@enum MetacognitiveAction begin
    STRATEGY_SHIFT
    EXTERNAL_SEARCH
    RETRY
    ABORT
end

# ============================================================================
# Cognitive Friction Estimation
# ============================================================================

"""
    estimate_cognitive_friction(state::KernelState)::Float32

Calculate the variance of the last 5 prediction_error values from episodic memory.
If there are fewer than 5 events, use whatever is available.

Returns the variance as Float32 (this is the "cognitive friction").
Higher variance indicates more uncertainty/confusion in recent predictions.
"""
function estimate_cognitive_friction(state::KernelState)::Float32
    # Get the episodic memory events
    memory = state.episodic_memory
    
    # If no memory events, return 0.0 (no friction)
    if isempty(memory)
        return Float32(0.0)
    end
    
    # Get the last up to 5 prediction errors
    n_events = length(memory)
    n_to_use = min(5, n_events)
    
    # Extract the last n_to_use prediction errors
    prediction_errors = Float32[
        memory[i].prediction_error 
        for i in (n_events - n_to_use + 1):n_events
    ]
    
    # Calculate variance
    # If only one event, variance is 0.0
    if length(prediction_errors) < 2
        return Float32(0.0)
    end
    
    # Compute variance using Statistics.var
    variance_value = var(prediction_errors, corrected=false)
    
    return Float32(variance_value)
end

# ============================================================================
# Override Decision
# ============================================================================

"""
    should_override_action(friction::Float32)::Bool

Return true if cognitive friction > 0.8.
This threshold indicates high uncertainty requiring metacognitive intervention.
"""
function should_override_action(friction::Float32)::Bool
    return friction > 0.8f0
end

# ============================================================================
# Metacognitive Override Creation
# ============================================================================

# Get reference to ActionProposal type from SharedTypes
# ActionProposal is now imported directly via `using .SharedTypes: ...`

"""
    create_metacognitive_override(action::ActionProposal, meta_action::Symbol)::ActionProposal

Create a new ActionProposal that overrides the original with metacognitive adjustments:
- capability_id: "metacognitive_override"
- confidence: 1.0 (high confidence in metacognitive decision)
- predicted_cost: action.predicted_cost * 0.5 (reduced cost due to strategic intervention)
- predicted_reward: action.predicted_reward * 2.0 (amplified reward potential)
- risk: "medium"
- reasoning: Description of the override with friction and action info
"""
function create_metacognitive_override(
    action::ActionProposal, 
    meta_action::Symbol
)::ActionProposal
    # Calculate the friction for inclusion in reasoning
    # Note: We pass friction separately since we don't have access to state here
    
    return ActionProposal(
        "metacognitive_override",  # capability_id
        1.0f0,                      # confidence - high confidence in metacognitive decision
        action.predicted_cost * 0.5f0,   # predicted_cost - reduced
        action.predicted_reward * 2.0f0, # predicted_reward - amplified
        "medium",                   # risk - medium
        "Metacognitive override: action=$meta_action"  # reasoning
    )
end

"""
    create_metacognitive_override(action::ActionProposal, meta_action::Symbol, friction::Float32)::ActionProposal

Create a metacognitive override with explicit friction value for detailed reasoning.
"""
function create_metacognitive_override(
    action::ActionProposal, 
    meta_action::Symbol,
    friction::Float32
)::ActionProposal
    return ActionProposal(
        "metacognitive_override",  # capability_id
        1.0f0,                      # confidence - high confidence in metacognitive decision
        action.predicted_cost * 0.5f0,   # predicted_cost - reduced
        action.predicted_reward * 2.0f0, # predicted_reward - amplified
        "medium",                   # risk - medium
        "Metacognitive override: friction=$friction, action=$meta_action"  # reasoning
    )
end

# ============================================================================
# Main Metacognitive Loop
# ============================================================================

"""
    metacognitive_loop(state::KernelState, proposed_action::ActionProposal)::ActionProposal

Main entry point for metacognitive regulation:
a) Calculate friction = estimate_cognitive_friction(state)
b) If should_override_action(friction), return create_metacognitive_override(proposed_action, :EXTERNAL_SEARCH)
c) Otherwise return the proposed_action unchanged

This implements Tier 7 metacognitive awareness - the ability to recognize
when the cognitive system is experiencing high uncertainty and needs to
switch to external search strategies.
"""
function metacognitive_loop(
    state::KernelState, 
    proposed_action::ActionProposal
)::ActionProposal
    # Step a: Calculate cognitive friction
    friction = estimate_cognitive_friction(state)
    
    # Step b: Check if override is needed
    if should_override_action(friction)
        # Return metacognitive override with EXTERNAL_SEARCH
        return create_metacognitive_override(proposed_action, :EXTERNAL_SEARCH, friction)
    end
    
    # Step c: No override needed, return original action
    return proposed_action
end

# ============================================================================
# Self-Model Integration - Metacognitive Self-Awareness
# ============================================================================

"""
    integrate_self_model_with_metacognition - Use Self-Model to inform metacognition
    
    This function uses the system's self-model to provide metacognitive insights:
    - Check if confidence predictions are calibrated
    - Adjust confidence based on historical performance
    - Use capability ratings to inform action selection
"""
function integrate_self_model_with_metacognition(
    self_model::SelfModel,
    proposed_action::ActionProposal,
    cognitive_friction::Float32
)::ActionProposal
    
    # Step 1: Check confidence calibration
    should_adjust, adjustment_factor = should_adjust_confidence(self_model)
    
    # Step 2: Get capability rating for the proposed action
    capability_rating = get_capability_rating(self_model, proposed_action.capability_id)
    
    # Step 3: Combine confidence signals
    # Base confidence from action
    adjusted_confidence = proposed_action.confidence
    
    # Apply calibration adjustment if needed
    if should_adjust
        adjusted_confidence = adjusted_confidence * Float32(adjustment_factor)
    end
    
    # Factor in capability rating (weighted average)
    # Capability rating represents historical performance
    final_confidence = 0.7 * adjusted_confidence + 0.3 * Float32(capability_rating)
    
    # If high cognitive friction, reduce confidence more
    if cognitive_friction > 0.5
        final_confidence *= 0.8
    end
    
    # Create adjusted action proposal
    return ActionProposal(
        proposed_action.capability_id,
        clamp(final_confidence, 0.1f0, 1.0f0),
        proposed_action.predicted_cost,
        proposed_action.predicted_reward,
        proposed_action.risk,
        proposed_action.reasoning * "; self_model_adjusted"
    )
end

"""
    should_trigger_deliberate_reflection - Check if self-model needs deliberate update
    
    Based on metacognitive signals, determine if the system should
    trigger a deliberate self-model update.
"""
function should_trigger_deliberate_reflection(
    self_model::SelfModel,
    cognitive_friction::Float32,
    recent_prediction_errors::Vector{Float32}
)::Bool
    
    # Trigger if cognitive friction is consistently high
    if cognitive_friction > 0.7
        return true
    end
    
    # Trigger if prediction errors are increasing
    if length(recent_prediction_errors) >= 5
        recent = recent_prediction_errors[end-4:end]
        if all(i -> recent[i] > recent[i-1], 2:length(recent))
            return true
        end
    end
    
    # Trigger if calibration error is high
    if self_model.calibration.calibration_error > 0.4
        return true
    end
    
    return false
end

end # module Metacognition
