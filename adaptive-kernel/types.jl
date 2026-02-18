# types.jl - Shared type definitions for Adaptive Kernel and ITHERIS
# This file consolidates common structs used across the system

module SharedTypes

using Dates
using UUIDs

export ActionProposal, Goal, GoalState, Thought, ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType,
       add_intent!, update_alignment!, get_alignment_penalty, update_goal_progress!

# ============================================================================
# Action Proposal - Kernel version (for deterministic kernel)
# ============================================================================

"""
    ActionProposal represents a selected action with metadata for decision making.
"""
struct ActionProposal
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::String
    reasoning::String
end

# Constructor for backward compatibility (Julia auto-generates positional constructor)
# Removed redundant recursive constructor that caused StackOverflow

# ============================================================================
# Goal - Represents an objective for the kernel (IMMUTABLE - Phase 3)
# ============================================================================

"""
    Goal - Immutable struct representing an objective
    Priority and metadata cannot change after creation (structural integrity)
"""
struct Goal
    id::String
    description::String
    priority::Float32  # [0, 1] - IMMUTABLE after creation
    created_at::DateTime
    deadline::DateTime
    # Status removed - use GoalState for mutable tracking
end

# Constructor for convenience
function Goal(id::String, desc::String, priority::Float32, created::DateTime)
    return Goal(id, desc, priority, created, created + Dates.Hour(1))
end

# ============================================================================
# GoalState - Mutable progress tracking for Goals
# ============================================================================

"""
    GoalState - Mutable progress tracking for Goals
    Separates immutable Goal definition from mutable runtime state
"""
mutable struct GoalState
    goal_id::String
    status::Symbol  # :active, :completed, :failed, :paused
    progress::Float32  # [0, 1] completion percentage
    last_updated::DateTime
    iterations::Int
    
    GoalState(goal_id::String) = new(
        goal_id,
        :active,
        0.0f0,
        now(),
        0
    )
end

function update_goal_progress!(state::GoalState, progress::Float32)
    state.progress = clamp(progress, 0.0f0, 1.0f0)
    state.last_updated = now()
    state.iterations += 1
    
    if state.progress >= 1.0f0
        state.status = :completed
    end
end

function pause_goal!(state::GoalState)
    state.status = :paused
    state.last_updated = now()
end

function fail_goal!(state::GoalState)
    state.status = :failed
    state.last_updated = now()
end

function resume_goal!(state::GoalState)
    state.status = :active
    state.last_updated = now()
end

# ============================================================================
# Thought - Represents ITHERIS cognitive output
# ============================================================================

struct Thought
    action::Int
    probs::Vector{Float32}
    value::Float32
    uncertainty::Float32
    context_vector::Vector{Float32}
end

# ============================================================================
# ITHERIS Action Proposal (for neural network integration)
# ============================================================================

"""
    ITHERISActionProposal - version for ITHERIS brain integration
"""
mutable struct ITHERISActionProposal
    id::UUID
    action_idx::Int
    confidence::Float32
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
end

# ============================================================================
# PHASE 3: REFLECTION TYPING - ReflectionEvent
# ============================================================================

"""
    ReflectionEvent - Concrete typed event for kernel reflection
    Replaces Dict{String, Any} in reflection to eliminate Any types
"""
struct ReflectionEvent
    id::UUID
    cycle::Int
    action_id::String
    action_confidence::Float32
    action_cost::Float32
    success::Bool
    reward::Float32
    prediction_error::Float32
    effect::String
    timestamp::DateTime
    # Explicit typed fields instead of Dict{String, Any}
    confidence_delta::Float32
    energy_delta::Float32
end

function ReflectionEvent(
    cycle::Int,
    action_id::String,
    action_confidence::Float32,
    action_cost::Float32,
    success::Bool,
    reward::Float32,
    prediction_error::Float32,
    effect::String;
    confidence_delta::Float32 = 0.0f0,
    energy_delta::Float32 = 0.0f0
)::ReflectionEvent
    return ReflectionEvent(
        uuid4(),
        cycle,
        action_id,
        action_confidence,
        action_cost,
        success,
        reward,
        prediction_error,
        effect,
        now(),
        confidence_delta,
        energy_delta
    )
end

# ============================================================================
# PHASE 3: STRATEGIC INERTIA - IntentVector
# ============================================================================

"""
    IntentVector - Strategic inertia across decision cycles
    Lives across decision cycles, represents long-term strategic direction
"""
struct IntentVector
    id::UUID
    intents::Vector{String}           # Long-term strategic intents
    intent_strengths::Vector{Float64} # [0,1] strength per intent
    last_aligned_action::DateTime
    thrash_count::Int                  # Penalize intent thrashing
    alignment_history::Vector{DateTime}
    
    IntentVector() = new(
        uuid4(),
        String[],
        Float64[],
        now(),
        0,
        DateTime[]
    )
end

function add_intent!(iv::IntentVector, intent::String, strength::Float64 = 0.5)
    push!(iv.intents, intent)
    push!(iv.intent_strengths, strength)
    push!(iv.alignment_history, now())
end

function update_alignment!(iv::IntentVector, aligned::Bool)
    iv.last_aligned_action = now()
    if !aligned
        iv.thrash_count += 1
    end
end

function get_alignment_penalty(iv::IntentVector)::Float64
    # Penalize thrashing - actions that conflict with established intents
    return min(0.5, 0.05 * iv.thrash_count)
end

# ============================================================================
# PHASE 3: NON-EXECUTING THOUGHT CYCLES
# ============================================================================

@enum ThoughtCycleType begin
    THOUGHT_DOCTRINE_REFINEMENT
    THOUGHT_SIMULATION
    THOUGHT_PRECOMPUTATION
    THOUGHT_ANALYSIS
end

"""
    ThoughtCycle - Non-executing internal cognition cycle
    Used for doctrine refinement, simulation, precomputation
"""
struct ThoughtCycle
    id::UUID
    cycle_type::ThoughtCycleType
    input_context::Dict{String, Any}  # Typed context for the thought
    output_insights::Vector{String}
    started_at::DateTime
    completed_at::Union{DateTime, Nothing}
    executed::Bool  # Must remain false - this is non-executing
    
    ThoughtCycle(cycle_type::ThoughtCycleType) = new(
        uuid4(),
        cycle_type,
        Dict{String, Any}(),
        String[],
        now(),
        nothing,
        false  # Always false - non-executing by design
    )
end

function complete_thought!(tc::ThoughtCycle, insights::Vector{String})
    tc.output_insights = insights
    tc.completed_at = now()
    # executed remains false - this is critical for non-executing cycles
end

end # module SharedTypes
