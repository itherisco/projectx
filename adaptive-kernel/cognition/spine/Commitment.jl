# cognition/spine/Commitment.jl - Phase 3: Decision Commitment
# Part of DecisionSpine decomposition - commits to a single decision

module Commitment

using Dates
using UUIDs
using Statistics

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine types
include("DecisionSpine.jl")
using ..DecisionSpine

export 
    CommittedDecision,
    DecisionCommitment,
    commit_to_decision,
    commit_with_kernel_approval,
    is_commitment_valid

# ============================================================================
# DECISION COMMITMENT
# ============================================================================

"""
    DecisionCommitment - Configuration for decision commitment
"""
struct DecisionCommitment
    require_kernel_approval::Bool
    allow_recommit::Bool
    commit_timeout_seconds::Float64
    audit_log_enabled::Bool
    
    DecisionCommitment() = new(
        true,    # Require kernel approval
        false,   # Don't allow recommit
        60.0,    # 60 second timeout
        true     # Enable audit logging
    )
end

"""
    commit_to_decision - Create a committed decision from conflict resolution
"""
function commit_to_decision(
    decision_text::String,
    proposals::Vector{AgentProposal},
    conflict::ConflictResolution
)::CommittedDecision
    influence = Dict(p.agent_id => p.weight for p in proposals)
    return CommittedDecision(
        uuid4(), decision_text, influence, conflict, false, nothing, nothing, nothing, now()
    )
end

"""
    commit_with_kernel_approval - Commit with kernel approval
"""
function commit_with_kernel_approval(
    decision_text::String,
    proposals::Vector{AgentProposal},
    conflict::ConflictResolution,
    kernel_approved::Bool;
    rejection_reason::Union{String, Nothing} = nothing
)::CommittedDecision
    
    decision = commit_to_decision(decision_text, proposals, conflict)
    decision.kernel_approved = kernel_approved
    decision.kernel_approval_timestamp = kernel_approved ? now() : nothing
    
    return decision
end

"""
    is_commitment_valid - Check if a commitment is still valid
"""
function is_commitment_valid(
    decision::CommittedDecision,
    max_age_seconds::Float64 = 300.0
)::Bool
    
    # Must have kernel approval
    decision.kernel_approved || return false
    
    # Must not be too old
    decision.decision_timestamp === nothing && return false
    age = (now() - decision.decision_timestamp).value / 1000.0
    age > max_age_seconds && return false
    
    # Must have been executed or be pending
    decision.outcome === nothing || 
        decision.outcome.status == OUTCOME_PENDING || 
        decision.outcome.status == OUTCOME_EXECUTED || return true
    
    return true
end

"""
    get_commitment_influence - Get agent influence breakdown
"""
function get_commitment_influence(
    decision::CommittedDecision
)::Dict{String, Float64}
    return decision.agent_influence
end

"""
    calculate_commitment_strength - Calculate how strong a commitment is
"""
function calculate_commitment_strength(
    decision::CommittedDecision
)::Float64
    
    # Base strength from influence
    total_influence = sum(values(decision.agent_influence))
    
    # Boost for kernel approval
    approval_boost = decision.kernel_approved ? 0.2 : 0.0
    
    # Boost for recent commitment
    recency_boost = 0.0
    if decision.decision_timestamp !== nothing
        age_seconds = (now() - decision.decision_timestamp).value / 1000.0
        recency_boost = max(0.0, 0.1 - (age_seconds / 3600.0))  # Decay over hour
    end
    
    return min(1.0, total_influence * 0.1 + approval_boost + recency_boost)
end

"""
    revoke_commitment - Revoke a decision commitment
"""
function revoke_commitment(decision::CommittedDecision)::CommittedDecision
    # Create a new decision with rejection
    new_decision = CommittedDecision(
        decision.decision,
        AgentProposal[],
        ConflictResolution(
            CONFLICT_ESCALATION, 0, Dict(), "", "Revoked", now()
        )
    )
    new_decision.kernel_approved = false
    new_decision.kernel_rejection_reason = "Commitment revoked"
    
    return new_decision
end

end # module Commitment
