# types.jl - Shared type definitions for Adaptive Kernel and ITHERIS
# This file consolidates common structs used across the system

module SharedTypes

using Dates
using UUIDs

export ActionProposal, Goal, GoalState, Thought, ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType, ThoughtContext,
       add_intent!, update_alignment!, get_alignment_penalty, update_goal_progress!, get_risk_value,
       # Integration types
       IntegrationActionProposal, IntegrationWorldState, IntegrationObservation, Observation

# ============================================================================
# Action Proposal - Kernel version (for deterministic kernel)
# ============================================================================

"""
    ActionProposal represents a selected action with metadata for decision making.
    
    # Backward Compatibility Note
    - `risk` can be either Float32 (new format) or String (legacy format "high"/"medium"/"low")
    - Use `get_risk_value()` to get numeric risk regardless of format
    
    SECURITY: Float32 risk values are validated to ensure:
    - Values are within [0.0, 1.0] bounds
    - Values are not NaN or Inf
    - This prevents safety score manipulation via invalid risk values
"""
struct ActionProposal
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::Union{Float32, String}  # Float32 for kernel comparison, String for legacy compatibility
    reasoning::String
    
    # Inner constructor with validation - SECURITY FIX for Vulnerability #1 & #2
    function ActionProposal(
        cap_id::String,
        confidence::Float32,
        cost::Float32,
        reward::Float32,
        risk::Union{Float32, String},
        reasoning::String
    )
        # Validate Float32 fields
        _validate_float32_bounds(confidence, "confidence", 0.0f0, 1.0f0)
        _validate_float32_bounds(cost, "predicted_cost", 0.0f0, Inf32)
        _validate_float32_bounds(reward, "predicted_reward", 0.0f0, 1.0f0)
        
        # Validate Float32 risk (not String - legacy format)
        if risk isa Float32
            _validate_float32_bounds(risk, "risk", 0.0f0, 1.0f0)
        end
        
        new(cap_id, confidence, cost, reward, risk, reasoning)
    end
end

"""
    _validate_float32_bounds(value, field_name, min_val, max_val)
    
Validate that a Float32 value is within acceptable bounds and not NaN/Inf.
Raises an error if validation fails (fail-secure approach).
"""
function _validate_float32_bounds(
    value::Float32, 
    field_name::String, 
    min_val::Float32, 
    max_val::Float32
)::Nothing
    # Check for NaN
    if isnan(value)
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name cannot be NaN. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    # Check for Inf/-Inf
    if isinf(value)
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name cannot be Inf or -Inf. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    # Check bounds
    if value < min_val || value > max_val
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name must be in [$min_val, $max_val], got $value. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    return nothing
end

"""
    get_risk_value(proposal::ActionProposal)::Float32
Get numeric risk value regardless of whether risk is Float32 or String.
"""
function get_risk_value(proposal::ActionProposal)::Float32
    if proposal.risk isa Float32
        return proposal.risk
    else
        # Convert legacy string risk to Float32
        risk_str = lowercase(string(proposal.risk))
        if risk_str == "high" || risk_str == "h"
            return 0.8f0
        elseif risk_str == "medium" || risk_str == "m"
            return 0.5f0
        elseif risk_str == "low" || risk_str == "l"
            return 0.2f0
        else
            return 0.3f0  # Default
        end
    end
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
    ThoughtContext - Typed context for thought cycles (replaces Dict{String, Any})
"""
struct ThoughtContext
    goal_id::Union{String, Nothing}
    priority::Float32
    confidence::Float32
    energy::Float32
    active_goals::Vector{String}
    recent_actions::Vector{String}
    
    ThoughtContext() = new(nothing, 0.5f0, 0.8f0, 1.0f0, String[], String[])
    ThoughtContext(goal_id::String, priority::Float32, confidence::Float32, energy::Float32) = 
        new(goal_id, priority, confidence, energy, String[], String[])
end

"""
    ThoughtCycle - Non-executing internal cognition cycle
    Used for doctrine refinement, simulation, precomputation
"""
struct ThoughtCycle
    id::UUID
    cycle_type::ThoughtCycleType
    input_context::ThoughtContext  # Typed struct instead of Dict{String, Any}
    output_insights::Vector{String}
    started_at::DateTime
    completed_at::Union{DateTime, Nothing}
    executed::Bool  # Must remain false - this is non-executing
    
    ThoughtCycle(cycle_type::ThoughtCycleType) = new(
        uuid4(),
        cycle_type,
        ThoughtContext(),
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

# ============================================================================
# INTEGRATION TYPES - Unified types for brain-kernel-jarvis communication
# ============================================================================

"""
    IntegrationActionProposal - Universal action proposal format
    Used as the canonical format for all three brains to communicate.
    Combines fields from both JarvisTypes.ActionProposal and SharedTypes.ActionProposal.
"""
struct IntegrationActionProposal
    id::UUID
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::Float32              # Unified as Float32 (not String like SharedTypes)
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
end

# Constructor with auto-generated UUID and validation
function IntegrationActionProposal(
    capability_id::String,
    confidence::Float32,
    cost::Float32,
    reward::Float32,
    risk::Float32;
    reasoning::String = "",
    impact::Float32 = 0.5f0
)::IntegrationActionProposal
    # Validate all Float32 fields - SECURITY FIX for Vulnerability #1 & #2
    _validate_float32_bounds(confidence, "confidence", 0.0f0, 1.0f0)
    _validate_float32_bounds(cost, "predicted_cost", 0.0f0, Inf32)
    _validate_float32_bounds(reward, "predicted_reward", 0.0f0, 1.0f0)
    _validate_float32_bounds(risk, "risk", 0.0f0, 1.0f0)  # Risk MUST be in [0,1]
    _validate_float32_bounds(impact, "impact_estimate", 0.0f0, 1.0f0)
    
    return IntegrationActionProposal(
        uuid4(),
        capability_id,
        confidence,
        cost,
        reward,
        risk,
        reasoning,
        impact,
        now()
    )
end

"""
    IntegrationObservation - Typed observation for integration (replaces Dict{String, Any})
"""
struct IntegrationObservation
    cpu_load::Float32
    memory_usage::Float32
    disk_io::Float32
    network_latency::Float32
    file_count::Int
    process_count::Int
    energy_level::Float32
    confidence::Float32
    
    IntegrationObservation() = new(0.0f0, 0.0f0, 0.0f0, 0.0f0, 0, 0, 1.0f0, 0.8f0)
    
    # Full constructor with all fields
    function IntegrationObservation(
        cpu_load::Float32,
        memory_usage::Float32,
        disk_io::Float32,
        network_latency::Float32,
        file_count::Int,
        process_count::Int,
        energy_level::Float32,
        confidence::Float32
    )
        return new(cpu_load, memory_usage, disk_io, network_latency, file_count, process_count, energy_level, confidence)
    end
end

"""
    IntegrationWorldState - Unified world state format
    Combines Jarvis system metrics with Kernel semantic facts.
"""
struct IntegrationWorldState
    timestamp::DateTime
    
    # System metrics (from Jarvis)
    system_metrics::Dict{String, Float32}  # cpu, memory, disk, network
    
    # Security state (from Jarvis)
    severity::Float32
    threat_count::Int
    trust_level::Int  # 0-100 scale
    
    # Kernel observations (typed)
    observations::IntegrationObservation
    
    # Semantic facts (from Kernel)
    facts::Dict{String, String}
    
    # Metadata
    cycle::Int
    last_action_id::Union{String, Nothing}
end

function IntegrationWorldState(
    system_metrics::Dict{String, Float32} = Dict{String, Float32}(),
    severity::Float32 = 0.0f0,
    threat_count::Int = 0,
    trust_level::Int = 100,
    observations::IntegrationObservation = IntegrationObservation(),
    facts::Dict{String, String} = Dict{String, String}(),
    cycle::Int = 0,
    last_action_id::Union{String, Nothing} = nothing
)::IntegrationWorldState
    return IntegrationWorldState(
        now(),
        system_metrics,
        severity,
        threat_count,
        trust_level,
        observations,
        facts,
        cycle,
        last_action_id
    )
end

# Export Integration types
export IntegrationActionProposal, IntegrationWorldState

end # module SharedTypes
