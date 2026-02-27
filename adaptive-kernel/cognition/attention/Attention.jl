# cognition/attention/Attention.jl - Attention & Salience System
# Component 5 of JARVIS Neuro-Symbolic Architecture
# Implements attention gating with salience scoring and novelty detection

module Attention

using Statistics
using LinearAlgebra

# ============================================================================
# Type Definitions
# ============================================================================

"""
    AttentionState

Mutable state tracking current attention focus, salience scores, and context.
"""
mutable struct AttentionState
    focus::Vector{Symbol}                    # Currently focused stimuli symbols
    salience_scores::Dict{Symbol, Float32}   # Salience per stimulus
    context::Vector{Float32}                 # Context vector
    switching_cost::Float32                  # Cost of switching focus
    max_focus::Int                           # Max concurrent foci
    
    function AttentionState(; max_focus::Int=3)
        new(
            Symbol[],
            Dict{Symbol, Float32}(),
            Float32[],
            0.1f0,
            max_focus
        )
    end
end

"""
    Stimulus

Represents an incoming sensory or cognitive stimulus to be evaluated for attention.
"""
struct Stimulus
    id::Symbol
    features::Vector{Float32}
    source::Symbol  # :visual, :auditory, :telemetry, :memory, :goal
    timestamp::Float64
    intensity::Float32  # Raw intensity
end

# ============================================================================
# Novelty Detection
# ============================================================================

"""
    detect_novelty(stimulus, history; window=10) -> Float32

Compare stimulus to recent history using feature distance.
Returns novelty score 0.0-1.0 where 1.0 is maximally novel.
"""
function detect_novelty(
    stimulus::Stimulus,
    history::Vector{Stimulus};
    window::Int=10
)::Float32
    if isempty(history)
        return 1.0f0  # First stimulus is maximally novel
    end
    
    # Get recent history within window
    recent = length(history) <= window ? history : history[end-window+1:end]
    
    # Compute average feature distance to recent stimuli
    total_distance = 0.0f0
    count = 0
    
    for past in recent
        if length(stimulus.features) == length(past.features)
            # Use cosine distance for feature comparison
            dot_prod = dot(stimulus.features, past.features)
            norm_prod = norm(stimulus.features) * norm(past.features)
            if norm_prod > 0
                cosine_dist = 1.0f0 - (dot_prod / norm_prod)
                total_distance += cosine_dist
                count += 1
            end
        end
    end
    
    if count == 0
        return 1.0f0  # No comparable history
    end
    
    avg_distance = total_distance / count
    
    # Normalize to 0-1 range (assuming max distance is 2.0 for cosine)
    novelty = clamp(avg_distance / 2.0f0, 0.0f0, 1.0f0)
    
    return novelty
end

# ============================================================================
# Salience Computation
# ============================================================================

"""
    compute_salience(stimulus, current_context; novelty_weight, intensity_weight, relevance_weight) -> Float32

Compute salience from:
- Novelty: change from context
- Intensity: raw signal strength
- Relevance: match to current goals/context
Returns score 0.0-1.0
"""
function compute_salience(
    stimulus::Stimulus,
    current_context::Vector{Float32};
    novelty_weight::Float32=0.3f0,
    intensity_weight::Float32=0.4f0,
    relevance_weight::Float32=0.3f0
)::Float32
    # Normalize intensity to 0-1 (assuming typical range 0-10)
    normalized_intensity = clamp(stimulus.intensity / 10.0f0, 0.0f0, 1.0f0)
    
    # Compute relevance from context match
    relevance = 0.0f0
    if !isempty(current_context) && !isempty(stimulus.features)
        # Use cosine similarity to context
        dot_prod = dot(stimulus.features, current_context)
        norm_stim = norm(stimulus.features)
        norm_ctx = norm(current_context)
        if norm_stim > 0 && norm_ctx > 0
            relevance = (dot_prod / (norm_stim * norm_ctx) + 1.0f0) / 2.0f0
        else
            relevance = 0.5f0
        end
    else
        relevance = 0.5f0  # Default when no context
    end
    
    # For novelty, we need history - use a simplified approach
    # In practice, this would be passed in from the caller
    novelty = 0.5f0  # Default moderate novelty
    
    # Weighted combination
    salience = (novelty_weight * novelty + 
                intensity_weight * normalized_intensity + 
                relevance_weight * relevance)
    
    return clamp(salience, 0.0f0, 1.0f0)
end

"""
    compute_salience_with_history(stimulus, history, current_context; kwargs) -> Float32

Compute salience with full novelty detection from history.
"""
function compute_salience_with_history(
    stimulus::Stimulus,
    history::Vector{Stimulus},
    current_context::Vector{Float32};
    novelty_weight::Float32=0.3f0,
    intensity_weight::Float32=0.4f0,
    relevance_weight::Float32=0.3f0
)::Float32
    # Compute novelty from history
    novelty = detect_novelty(stimulus, history)
    
    # Normalize intensity to 0-1
    normalized_intensity = clamp(stimulus.intensity / 10.0f0, 0.0f0, 1.0f0)
    
    # Compute relevance from context match
    relevance = 0.0f0
    if !isempty(current_context) && !isempty(stimulus.features)
        dot_prod = dot(stimulus.features, current_context)
        norm_stim = norm(stimulus.features)
        norm_ctx = norm(current_context)
        if norm_stim > 0 && norm_ctx > 0
            relevance = (dot_prod / (norm_stim * norm_ctx) + 1.0f0) / 2.0f0
        else
            relevance = 0.5f0
        end
    else
        relevance = 0.5f0
    end
    
    # Weighted combination
    salience = (novelty_weight * novelty + 
                intensity_weight * normalized_intensity + 
                relevance_weight * relevance)
    
    return clamp(salience, 0.0f0, 1.0f0)
end

# ============================================================================
# Context Switching
# ============================================================================

"""
    compute_switching_cost(old_focus, new_focus) -> Float32

Compute cost of switching attention from old focus to new focus.
Based on dissimilarity - more different = higher cost.
"""
function compute_switching_cost(
    old_focus::Vector{Symbol},
    new_focus::Vector{Symbol}
)::Float32
    if isempty(old_focus) || isempty(new_focus)
        return 0.0f0
    end
    
    # Count symbols that are in new but not in old
    old_set = Set(old_focus)
    new_set = Set(new_focus)
    
    # Jaccard distance as switching cost metric
    intersection = length(intersect(old_set, new_set))
    union_size = length(union(old_set, new_set))
    
    if union_size == 0
        return 1.0f0  # Complete switch
    end
    
    # Jaccard distance: 0 = no change, 1 = complete change
    jaccard_dist = 1.0f0 - (intersection / union_size)
    
    return jaccard_dist
end

"""
    should_switch(state, new_salience, current_salience) -> Bool

Determine if attention should switch to a new stimulus.
Must exceed switching cost threshold.
"""
function should_switch(
    state::AttentionState,
    new_salience::Float32,
    current_salience::Float32
)::Bool
    # Need significant improvement to justify switching
    salience_improvement = new_salience - current_salience
    
    # Must exceed switching cost
    return salience_improvement > state.switching_cost
end

# ============================================================================
# Focus Selection
# ============================================================================

"""
    select_focus(stimuli, state; budget=0.8) -> Vector{Symbol}

Score all stimuli by salience and select top foci within compute budget.
Accounts for switching cost.
"""
function select_focus(
    stimuli::Vector{Stimulus},
    state::AttentionState;
    budget::Float32=0.8f0
)::Vector{Symbol}
    if isempty(stimuli)
        return Symbol[]
    end
    
    # Score all stimuli
    scored_stimuli = Vector{Tuple{Symbol, Float32}}()
    
    for stim in stimuli
        salience = compute_salience(stim, state.context)
        push!(scored_stimuli, (stim.id, salience))
    end
    
    # Sort by salience descending
    sort!(scored_stimuli, by=x->x[2], rev=true)
    
    # Select top foci within budget
    selected = Symbol[]
    current_budget = budget
    
    for (stim_id, salience) in scored_stimuli
        # Check if we can afford this stimulus
        if salience <= current_budget && length(selected) < state.max_focus
            push!(selected, stim_id)
            current_budget -= salience
        end
    end
    
    return selected
end

"""
    select_focus_with_history(stimuli, history, state; budget=0.8) -> Vector{Symbol}

Select focus with full novelty detection from history.
"""
function select_focus_with_history(
    stimuli::Vector{Stimulus},
    history::Vector{Stimulus},
    state::AttentionState;
    budget::Float32=0.8f0
)::Vector{Symbol}
    if isempty(stimuli)
        return Symbol[]
    end
    
    # Score all stimuli with novelty
    scored_stimuli = Vector{Tuple{Symbol, Float32}}()
    
    for stim in stimuli
        salience = compute_salience_with_history(stim, history, state.context)
        push!(scored_stimuli, (stim.id, salience))
    end
    
    # Sort by salience descending
    sort!(scored_stimuli, by=x->x[2], rev=true)
    
    # Select top foci within budget
    selected = Symbol[]
    current_budget = budget
    
    for (stim_id, salience) in scored_stimuli
        if salience <= current_budget && length(selected) < state.max_focus
            push!(selected, stim_id)
            current_budget -= salience
        end
    end
    
    return selected
end

# ============================================================================
# Bounded Compute Allocation
# ============================================================================

"""
    allocate_attention(stimuli, max_compute=0.8) -> Vector{Tuple{Symbol, Float32}}

Allocate attention budget across stimuli.
Returns (stimulus_id, allocation) pairs where sum <= max_compute.
"""
function allocate_attention(
    stimuli::Vector{Stimulus},
    max_compute::Float32=0.8f0
)::Vector{Tuple{Symbol, Float32}}
    if isempty(stimuli)
        return Tuple{Symbol, Float32}[]
    end
    
    # Score all stimuli
    scored = Vector{Tuple{Symbol, Float32}}()
    for stim in stimuli
        salience = compute_salience(stim, Float32[])
        push!(scored, (stim.id, salience))
    end
    
    # Sort by salience
    sort!(scored, by=x->x[2], rev=true)
    
    # Allocate budget proportionally
    allocations = Vector{Tuple{Symbol, Float32}}()
    remaining = max_compute
    
    total_salience = sum(s for (_, s) in scored)
    
    if total_salience > 0
        for (stim_id, salience) in scored
            # Allocate proportionally to salience
            proportion = salience / total_salience
            allocation = min(proportion * max_compute, remaining, salience)
            
            if allocation > 0.01f0  # Minimum threshold
                push!(allocations, (stim_id, allocation))
                remaining -= allocation
            end
            
            if remaining <= 0
                break
            end
        end
    else
        # Equal allocation if no salience scores
        equal_share = max_compute / length(stimuli)
        for stim in stimuli
            push!(allocations, (stim.id, equal_share))
        end
    end
    
    return allocations
end

# ============================================================================
# Deterministic Fallback
# ============================================================================

"""
    deterministic_attention(stimuli; fallback_focus=:telemetry) -> Vector{Symbol}

Fallback attention when neural attention is unavailable.
Uses fixed priority order: telemetry > goal > memory > visual > auditory
"""
function deterministic_attention(
    stimuli::Vector{Stimulus};
    fallback_focus::Symbol=:telemetry
)::Vector{Symbol}
    if isempty(stimuli)
        return Symbol[fallback_focus]
    end
    
    # Priority order for deterministic fallback
    priority_order = [:telemetry, :goal, :memory, :visual, :auditory]
    
    # Group by source
    by_source = Dict{Symbol, Vector{Stimulus}}()
    for stim in stimuli
        if !haskey(by_source, stim.source)
            by_source[stim.source] = Stimulus[]
        end
        push!(by_source[stim.source], stim)
    end
    
    # Select highest priority source with stimuli
    selected = Symbol[]
    for source in priority_order
        if haskey(by_source, source) && !isempty(by_source[source])
            # Take the most intense stimulus from this source
            source_stim = by_source[source]
            most_intense = reduce((a, b) -> a.intensity > b.intensity ? a : b, source_stim)
            push!(selected, most_intense.id)
            
            if length(selected) >= 3  # Max foci
                break
            end
        end
    end
    
    # If nothing selected, use fallback
    if isempty(selected)
        return Symbol[fallback_focus]
    end
    
    return selected
end

# ============================================================================
# Adversarial Protection
# ============================================================================

"""
    detect_adversarial_flood(stimuli; rate_threshold=100.0, time_window=1.0) -> Bool

Detect if too many stimuli arrive in short time window.
Could indicate adversarial attack or system malfunction.
"""
function detect_adversarial_flood(
    stimuli::Vector{Stimulus};
    rate_threshold::Float32=100.0f0,
    time_window::Float64=1.0
)::Bool
    if isempty(stimuli)
        return false
    end
    
    # Get current time (use most recent stimulus timestamp)
    current_time = maximum(s.timestamp for s in stimuli)
    
    # Count stimuli in time window
    recent_count = 0
    for stim in stimuli
        if current_time - stim.timestamp <= time_window
            recent_count += 1
        end
    end
    
    # Check if rate exceeds threshold
    rate = recent_count / time_window
    
    return rate > rate_threshold
end

"""
    filter_adversarial_stimuli(stimuli; rate_threshold=100.0, time_window=1.0) -> Vector{Stimulus>

Filter out potentially adversarial stimuli while keeping safe ones.
"""
function filter_adversarial_stimuli(
    stimuli::Vector{Stimulus};
    rate_threshold::Float32=100.0f0,
    time_window::Float64=1.0
)::Vector{Stimulus}
    if isempty(stimuli)
        return Stimulus[]
    end
    
    # If flooding detected, apply stricter filtering
    if detect_adversarial_flood(stimuli; rate_threshold, time_window)
        # Keep only highest intensity stimuli (signal over noise)
        sorted = sort(stimuli, by=s->s.intensity, rev=true)
        max_keep = min(length(sorted), 5)  # Keep top 5 max
        return sorted[1:max_keep]
    end
    
    return stimuli
end

# ============================================================================
# State Management
# ============================================================================

"""
    update_attention_state!(state, new_focus, salience_scores)

Update attention state with new focus and salience scores.
"""
function update_attention_state!(
    state::AttentionState,
    new_focus::Vector{Symbol},
    salience_scores::Dict{Symbol, Float32}
)
    state.focus = new_focus
    state.salience_scores = salience_scores
end

"""
    update_context!(state, new_context)

Update the context vector for attention.
"""
function update_context!(
    state::AttentionState,
    new_context::Vector{Float32}
)
    state.context = new_context
end

"""
    reset_attention!(state)

Reset attention state to initial values.
"""
function reset_attention!(state::AttentionState)
    empty!(state.focus)
    empty!(state.salience_scores)
    empty!(state.context)
end

# ============================================================================
# Exports
# ============================================================================

export
    # Types
    AttentionState,
    Stimulus,
    
    # Core functions
    compute_salience,
    compute_salience_with_history,
    select_focus,
    select_focus_with_history,
    
    # Novelty
    detect_novelty,
    
    # Context switching
    compute_switching_cost,
    should_switch,
    
    # Compute allocation
    allocate_attention,
    
    # Fallback
    deterministic_attention,
    
    # Adversarial protection
    detect_adversarial_flood,
    filter_adversarial_stimuli,
    
    # State management
    update_attention_state!,
    update_context!,
    reset_attention!

end # module