# cognition/spine/ConflictResolution.jl - Phase 3: Conflict Resolution
# Part of DecisionSpine decomposition - resolves disagreements between agents

module ConflictResolution

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
    ConflictResolution,
    ConflictResolutionMethod,
    resolve_conflict,
    ConflictResolver

# ============================================================================
# CONFLICT RESOLUTION METHODS
# ============================================================================

@enum ConflictResolutionMethod begin
    CONFLICT_WEIGHTED_VOTE     # Weighted by agent confidence and historical accuracy
    CONFLICT_ADVERSARIAL       # Auditor has veto power on risky decisions
    CONFLICT_DELIBERATION      # Agents deliberate for more rounds
    CONFLICT_ESCALATION        # Escalate to higher authority
    CONFLICT_ENTROPY           # Inject randomness when too much agreement
    CONFLICT_CONSENSUS         # Majority consensus
end

"""
    ConflictResolver - Configuration for conflict resolution
"""
struct ConflictResolver
    method::ConflictResolutionMethod
    require_unanimity::Bool
    conflict_threshold::Float64
    max_deliberation_rounds::Int
    entropy_threshold::Float64
    auditor_veto_power::Bool
    
    ConflictResolver(
        method::ConflictResolutionMethod = CONFLICT_WEIGHTED_VOTE
    ) = new(
        method,
        false,       # Don't require unanimity by default
        0.3,         # 30% disagreement triggers resolution
        3,           # Max 3 deliberation rounds
        0.85,        # 85% agreement triggers entropy injection
        true         # Auditor has veto power
    )
end

"""
    resolve_conflict - Resolve disagreement between agent proposals
    This is the main entry point - preserves existing API
"""
function resolve_conflict(
    proposals::Vector{AgentProposal},
    config::SpineConfig
)::ConflictResolution
    resolver = ConflictResolver(config.require_unanimity ? CONFLICT_ENSEMBLE : CONFLICT_WEIGHTED_VOTE)
    return resolve_conflict(proposals, resolver)
end

"""
    resolve_conflict - Resolve with custom ConflictResolver
"""
function resolve_conflict(
    proposals::Vector{AgentProposal},
    resolver::ConflictResolver
)::ConflictResolution
    
    isempty(proposals) && return ConflictResolution(
        CONFLICT_ESCALATION, 0, Dict(), "", "No proposals", now()
    )
    
    # Handle single proposal case
    if length(proposals) == 1
        return ConflictResolution(
            CONFLICT_CONSENSUS, 0,
            Dict(proposals[1].agent_id => proposals[1].weight),
            proposals[1].agent_id,
            "Single proposal accepted",
            now()
        )
    end
    
    # Route to appropriate resolution method
    if resolver.method == CONFLICT_WEIGHTED_VOTE
        return resolve_weighted_vote(proposals, resolver)
    elseif resolver.method == CONFLICT_ENTROPY
        return resolve_entropy(proposals, resolver)
    elseif resolver.method == CONFLICT_ADVERSARIAL
        return resolve_adversarial(proposals, resolver)
    elseif resolver.method == CONFLICT_CONSENSUS
        return resolve_consensus(proposals)
    else
        return resolve_weighted_vote(proposals, resolver)
    end
end

"""
    resolve_weighted_vote - Resolve using weighted voting
"""
function resolve_weighted_vote(
    proposals::Vector{AgentProposal},
    resolver::ConflictResolver
)::ConflictResolution
    
    # Weighted vote resolution
    weighted_scores = Dict{String, Float64}()
    for proposal in proposals
        score = proposal.weight * proposal.confidence
        weighted_scores[proposal.agent_id] = get(weighted_scores, proposal.agent_id, 0.0) + score
    end
    
    # Find winner
    winner_id = argmax(weighted_scores)
    winner = first(p for p in proposals if p.agent_id == winner_id)
    
    return ConflictResolution(
        CONFLICT_WEIGHTED_VOTE, 1,
        weighted_scores,
        winner_id,
        "Winner by weighted vote: $(winner.decision) (score=$(weighted_scores[winner_id]))",
        now()
    )
end

"""
    resolve_entropy - Inject entropy when agents agree too much
"""
function resolve_entropy(
    proposals::Vector{AgentProposal},
    resolver::ConflictResolver
)::ConflictResolution
    
    confidences = [p.confidence for p in proposals]
    mean_conf = mean(confidences)
    
    if mean_conf >= resolver.entropy_threshold
        # Inject adversarial bias - flip the decision
        return ConflictResolution(
            CONFLICT_ENTROPY, 0, 
            Dict(p.agent_id => p.weight for p in proposals),
            proposals[end].agent_id,  # Last agent wins (adversarial)
            "Entropy injection: agents agreed too often (mean_conf=$mean_conf)",
            now()
        )
    end
    
    # Not enough agreement - fall back to weighted vote
    return resolve_weighted_vote(proposals, resolver)
end

"""
    resolve_adversarial - Auditor has veto power
"""
function resolve_adversarial(
    proposals::Vector{AgentProposal},
    resolver::ConflictResolver
)::ConflictResolution
    
    # Check if auditor proposes veto
    auditor_proposals = filter(p -> p.agent_type == :auditor, proposals)
    
    for auditor_prop in auditor_proposals
        if occursin("veto", auditor_prop.decision)
            return ConflictResolution(
                CONFLICT_ADVERSARIAL, 0,
                Dict(auditor_prop.agent_id => auditor_prop.weight),
                auditor_prop.agent_id,
                "Auditor veto: $(auditor_prop.decision)",
                now()
            )
        end
    end
    
    # No veto - use weighted vote
    return resolve_weighted_vote(proposals, resolver)
end

"""
    resolve_consensus - Majority consensus
"""
function resolve_consensus(
    proposals::Vector{AgentProposal}
)::ConflictResolution
    
    # Group by decision
    decision_votes = Dict{String, Float64}()
    for proposal in proposals
        decision_votes[proposal.decision] = 
            get(decision_votes, proposal.decision, 0.0) + proposal.weight
    end
    
    # Find majority
    winner_decision = argmax(decision_votes)
    winner = first(p for p in proposals if p.decision == winner_decision)
    
    return ConflictResolution(
        CONFLICT_CONSENSUS, 0,
        decision_votes,
        winner.agent_id,
        "Majority consensus: $winner_decision",
        now()
    )
end

"""
    detect_stalemate - Detect when agents cannot agree
"""
function detect_stalemate(
    proposals::Vector{AgentProposal},
    threshold::Float64 = 0.1
)::Bool
    
    length(proposals) < 2 && return false
    
    # Calculate score variance
    scores = [p.weight * p.confidence for p in proposals]
    return var(scores) < threshold
end

end # module ConflictResolution
