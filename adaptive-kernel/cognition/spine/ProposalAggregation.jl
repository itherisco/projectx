# cognition/spine/ProposalAggregation.jl - Phase 3: Proposal Aggregation
# Part of DecisionSpine decomposition - aggregates agent proposals in parallel

module ProposalAggregation

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
    AggregatedProposals,
    aggregate_proposals,
    ProposalAggregator

# ============================================================================
# PROPOSAL AGGREGATION
# ============================================================================

"""
    AggregatedProposals - Collection of proposals from all agents
"""
struct AggregatedProposals
    id::UUID
    proposals::Vector{AgentProposal}
    aggregation_timestamp::DateTime
    agent_types_present::Set{Symbol}
    mean_confidence::Float64
    confidence_variance::Float64
end

"""
    ProposalAggregator - Configuration for proposal aggregation
"""
struct ProposalAggregator
    min_agents::Int
    require_all_types::Bool
    timeout_seconds::Float64
    confidence_threshold::Float64
    
    ProposalAggregator() = new(
        2,          # Minimum 2 agents required
        false,      # Don't require all types
        30.0,       # 30 second timeout
        0.3         # 30% confidence threshold
    )
end

"""
    aggregate_proposals - Aggregate proposals from multiple agents
"""
function aggregate_proposals(
    proposals::Vector{AgentProposal},
    config::ProposalAggregator = ProposalAggregator()
)::AggregatedProposals
    
    isempty(proposals) && return AggregatedProposals(
        uuid4(),
        AgentProposal[],
        now(),
        Set{Symbol}(),
        0.0,
        0.0
    )
    
    # Collect agent types present
    agent_types = Set{Symbol}(p.agent_type for p in proposals)
    
    # Calculate confidence statistics
    confidences = [p.confidence for p in proposals]
    mean_conf = mean(confidences)
    var_conf = var(confidences)
    
    return AggregatedProposals(
        uuid4(),
        proposals,
        now(),
        agent_types,
        mean_conf,
        var_conf
    )
end

"""
    filter_by_confidence - Filter proposals by confidence threshold
"""
function filter_by_confidence(
    proposals::Vector{AgentProposal},
    threshold::Float64
)::Vector{AgentProposal}
    return filter(p -> p.confidence >= threshold, proposals)
end

"""
    filter_by_agent_type - Filter proposals by agent type
"""
function filter_by_agent_type(
    proposals::Vector{AgentProposal},
    agent_type::Symbol
)::Vector{AgentProposal}
    return filter(p -> p.agent_type == agent_type, proposals)
end

"""
    rank_proposals - Rank proposals by weighted score
"""
function rank_proposals(proposals::Vector{AgentProposal})::Vector{AgentProposal}
    scored = [(p, p.weight * p.confidence) for p in proposals]
    sorted = sort(scored, by = x -> x[2], rev = true)
    return [p for (p, _) in sorted]
end

"""
    group_by_decision - Group proposals by their proposed decision
"""
function group_by_decision(
    proposals::Vector{AgentProposal}
)::Dict{String, Vector{AgentProposal}}
    groups = Dict{String, Vector{AgentProposal}}()
    
    for proposal in proposals
        if !haskey(groups, proposal.decision)
            groups[proposal.decision] = AgentProposal[]
        end
        push!(groups[proposal.decision], proposal)
    end
    
    return groups
end

"""
    get_consensus_decision - Find decision with majority support
"""
function get_consensus_decision(
    proposals::Vector{AgentProposal}
)::Union{String, Nothing}
    
    groups = group_by_decision(proposals)
    isempty(groups) && return nothing
    
    # Find group with highest total weight
    best_group = nothing
    best_score = -Inf
    
    for (decision, group_proposals) in groups
        score = sum(p.weight * p.confidence for p in group_proposals)
        if score > best_score
            best_score = score
            best_group = decision
        end
    end
    
    return best_group
end

end # module ProposalAggregation
