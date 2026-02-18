# cognition/spine/DecisionSpine.jl - MANDATORY Decision Spine for Sovereign Cognition
# All cognitive cycles must flow through this spine
# Perception → Parallel Agent Proposals → Conflict Resolution → SINGLE Committed Decision → Kernel Approval → Execution/Rejection → Immutable Log Entry

module DecisionSpine

using Dates
using UUIDs
using JSON
using Statistics

# Import shared types
include("../types.jl")
using ..SharedTypes

# Import agent types (forward declaration)
include("../cognition/types.jl")
using ..CognitionTypes

# Import submodules (Phase 3 decomposition)
include("ProposalAggregation.jl")
using .ProposalAggregation

include("ConflictResolution.jl")
using .ConflictResolution

include("Commitment.jl")
using .Commitment

export 
    DecisionCycle,
    CommittedDecision,
    AgentProposal,
    ConflictResolution,
    run_cognitive_cycle,
    DecisionOutcome,
    SpineConfig,
    # Re-export from submodules
    aggregate_proposals,
    resolve_conflict,
    commit_to_decision,
    ProposalAggregator,
    ConflictResolver,
    DecisionCommitment

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    SpineConfig - Configuration for the decision spine
"""
@with_kw struct SpineConfig
    require_unanimity::Bool = false          # If true, require all agents to agree (rare)
    conflict_threshold::Float64 = 0.3        # Threshold for triggering conflict resolution
    max_deliberation_rounds::Int = 3          # Maximum rounds of deliberation
    entropy_injection_enabled::Bool = true    # Inject entropy if agents agree too often
    entropy_threshold::Float64 = 0.85         # Agreement threshold for entropy injection
    kernel_approval_required::Bool = true    # Always require kernel approval
    log_immutable::Bool = true                # Make decision logs immutable
end

# ============================================================================
# AGENT PROPOSAL TYPE
# ============================================================================

"""
    AgentProposal - Output from a single cognitive agent
"""
struct AgentProposal
    agent_id::String
    agent_type::Symbol           # :executor, :strategist, :auditor, :evolution
    decision::String             # The proposed decision
    confidence::Float64          # [0, 1]
    reasoning::String            # Agent's reasoning
    weight::Float64              # Agent's influence weight (can be penalized)
    timestamp::DateTime
    evidence::Vector{String}     # Supporting evidence IDs
    alternatives::Vector{String} # Rejected alternatives
end

function AgentProposal(
    agent_id::String,
    agent_type::Symbol,
    decision::String,
    confidence::Float64;
    reasoning::String = "",
    weight::Float64 = 1.0,
    evidence::Vector{String} = String[],
    alternatives::Vector{String} = String[]
)
    return AgentProposal(
        agent_id, agent_type, decision, confidence, reasoning, weight, 
        now(), evidence, alternatives
    )
end

# ============================================================================
# CONFLICT RESOLUTION
# ============================================================================

"""
    ConflictResolution - Method for resolving disagreements between agents
"""
@enum ConflictResolutionMethod begin
    CONFLICT_WEIGHTED_VOTE     # Weighted by agent confidence and historical accuracy
    CONFLICT_ADVERSARIAL       # Auditor has veto power on risky decisions
    CONFLICT_DELIBERATION      # Agents deliberate for more rounds
    CONFLICT_ESCALATION        # Escalate to higher authority
    CONFLICT_ENTROPY           # Inject randomness when too much agreement
end

struct ConflictResolution
    method::ConflictResolutionMethod
    round::Int
    votes::Dict{String, Float64}      # agent_id => vote weight
    winner::String                    # Winning agent_id
    justification::String
    timestamp::DateTime
end

"""
    resolve_conflict - Resolve disagreement between agent proposals
"""
function resolve_conflict(
    proposals::Vector{AgentProposal},
    config::SpineConfig
)::ConflictResolution
    isempty(proposals) && return ConflictResolution(
        CONFLICT_ESCALATION, 0, Dict(), "", "No proposals", now()
    )
    
    # Check for entropy injection (too much agreement)
    if config.entropy_injection_enabled && length(proposals) >= 2
        confidences = [p.confidence for p in proposals]
        mean_conf = mean(confidences)
        if mean_conf >= config.entropy_threshold
            # Inject adversarial bias - flip the decision
            return ConflictResolution(
                CONFLICT_ENTROPY, 0, 
                Dict(p.agent_id => p.weight for p in proposals),
                proposals[end].agent_id,  # Last agent wins (adversarial)
                "Entropy injection: agents agreed too often (mean_conf=$mean_conf)",
                now()
            )
        end
    end
    
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

# ============================================================================
# COMMITTED DECISION
# ============================================================================

"""
    CommittedDecision - Single committed decision after conflict resolution
"""
struct CommittedDecision
    id::UUID
    decision::String
    agent_influence::Dict{String, Float64}  # agent_id => influence weight
    conflict_resolution::ConflictResolution
    kernel_approved::Bool
    kernel_approval_timestamp::Union{DateTime, Nothing}
    execution_timestamp::Union{DateTime, Nothing}
    outcome::Union{DecisionOutcome, Nothing}
    timestamp::DateTime
end

function CommittedDecision(
    decision::String,
    proposals::Vector{AgentProposal},
    conflict::ConflictResolution
)
    influence = Dict(p.agent_id => p.weight for p in proposals)
    return CommittedDecision(
        uuid4(), decision, influence, conflict, false, nothing, nothing, nothing, now()
    )
end

"""
    DecisionOutcome - Result of decision execution
"""
@enum DecisionOutcomeStatus begin
    OUTCOME_EXECUTED
    OUTCOME_REJECTED
    OUTCOME_FAILED
    OUTCOME_PENDING
end

struct DecisionOutcome
    status::DecisionOutcomeStatus
    result::Dict{String, Any}
    actual_vs_expected::Dict{String, Float64}  # metric => error
    timestamp::DateTime
end

# ============================================================================
# DECISION CYCLE
# ============================================================================

"""
    DecisionCycle - Complete cognitive cycle through the spine
"""
mutable struct DecisionCycle
    id::UUID
    cycle_number::Int
    
    # Phase 1: Perception
    perception_input::Dict{String, Any}
    perception_timestamp::DateTime
    
    # Phase 2: Parallel Agent Proposals
    proposals::Vector{AgentProposal}
    proposal_timestamp::DateTime
    
    # Phase 3: Conflict Resolution
    conflict_resolution::Union{ConflictResolution, Nothing}
    conflict_timestamp::Union{DateTime, Nothing}
    
    # Phase 4: Single Committed Decision
    committed_decision::Union{CommittedDecision, Nothing}
    decision_timestamp::Union{DateTime, Nothing}
    
    # Phase 5: Kernel Approval
    kernel_approved::Bool
    kernel_approval_timestamp::Union{DateTime, Nothing}
    kernel_rejection_reason::Union{String, Nothing}
    
    # Phase 6: Execution or Rejection
    execution_timestamp::Union{DateTime, Nothing}
    outcome::Union{DecisionOutcome, Nothing}
    
    # Phase 7: Immutable Log Entry
    log_entry::Union{Dict{String, Any}, Nothing}
    logged::Bool
    
    function DecisionCycle(cycle_number::Int, perception::Dict{String, Any})
        new(
            uuid4(), cycle_number,
            perception, now(),
            [], nothing,
            nothing, nothing,
            nothing, nothing,
            false, nothing, nothing,
            nothing, nothing,
            nothing, false
        )
    end
end

# ============================================================================
# MAIN COGNITIVE CYCLE
# ============================================================================

"""
    run_cognitive_cycle - Execute a complete cognitive cycle through the spine
"""
function run_cognitive_cycle(
    cycle_number::Int,
    perception::Dict{String, Any},
    agents::Dict{Symbol, Any},  # agent_type => agent_instance
    kernel::Any,  # Kernel instance for approval
    config::SpineConfig = SpineConfig()
)::DecisionCycle
    
    cycle = DecisionCycle(cycle_number, perception)
    
    # =========================================================================
    # PHASE 1: PERCEPTION (already captured in constructor)
    # =========================================================================
    @info "Phase 1: Perception captured" timestamp=cycle.perception_timestamp
    
    # =========================================================================
    # PHASE 2: PARALLEL AGENT PROPOSALS
    # =========================================================================
    cycle.proposals = run_parallel_agent_proposals(agents, perception)
    cycle.proposal_timestamp = now()
    
    @info "Phase 2: Agent proposals generated" num_proposals=length(cycle.proposals)
    
    # Check if we have proposals
    isempty(cycle.proposals) && begin
        @warn "No agent proposals generated - cycle aborted"
        return cycle
    end
    
    # =========================================================================
    # PHASE 3: CONFLICT RESOLUTION
    # =========================================================================
    cycle.conflict_resolution = resolve_conflict(cycle.proposals, config)
    cycle.conflict_timestamp = now()
    
    @info "Phase 3: Conflict resolved" 
        method=cycle.conflict_resolution.method
        winner=cycle.conflict_resolution.winner
    
    # =========================================================================
    # PHASE 4: SINGLE COMMITTED DECISION
    # =========================================================================
    cycle.committed_decision = CommittedDecision(
        cycle.conflict_resolution.winner,
        cycle.proposals,
        cycle.conflict_resolution
    )
    cycle.decision_timestamp = now()
    
    @info "Phase 4: Decision committed" 
        decision=cycle.committed_decision.decision
    
    # =========================================================================
    # PHASE 5: KERNEL APPROVAL (MANDATORY)
    # =========================================================================
    if config.kernel_approval_required
        kernel_response = request_kernel_approval(kernel, cycle.committed_decision)
        cycle.kernel_approved = kernel_response.approved
        cycle.kernel_rejection_reason = kernel_response.rejection_reason
        cycle.committed_decision.kernel_approved = kernel_response.approved
        cycle.committed_decision.kernel_approval_timestamp = now()
    else
        cycle.kernel_approved = true
    end
    
    cycle.kernel_approval_timestamp = now()
    
    if !cycle.kernel_approved
        @warn "Kernel rejected decision" reason=cycle.kernel_rejection_reason
        cycle.outcome = DecisionOutcome(
            OUTCOME_REJECTED,
            Dict("rejection_reason" => cycle.kernel_rejection_reason),
            Dict(),
            now()
        )
        log_immutable_entry!(cycle)
        return cycle
    end
    
    @info "Phase 5: Kernel approved"
    
    # =========================================================================
    # PHASE 6: EXECUTION OR REJECTION
    # =========================================================================
    cycle.execution_timestamp = now()
    
    # Execute the decision (returns outcome)
    cycle.outcome = execute_decision(cycle.committed_decision, kernel)
    
    @info "Phase 6: Execution complete" 
        status=cycle.outcome.status
    
    # =========================================================================
    # PHASE 7: IMMUTABLE LOG ENTRY
    # =========================================================================
    log_immutable_entry!(cycle)
    
    @info "Phase 7: Immutable log entry created"
    
    return cycle
end

"""
    run_parallel_agent_proposals - Run all agents in parallel to generate proposals
"""
function run_parallel_agent_proposals(
    agents::Dict{Symbol, Any},
    perception::Dict{String, Any}
)::Vector{AgentProposal}
    
    proposals = AgentProposal[]
    
    for (agent_type, agent_instance) in agents
        try
            proposal = generate_proposal(agent_instance, perception)
            push!(proposals, proposal)
        catch e
            @error "Agent $agent_type failed to generate proposal" error=string(e)
        end
    end
    
    return proposals
end

"""
    generate_proposal - Generate proposal from an agent (polymorphic)
"""
function generate_proposal(agent::Any, perception::Dict{String, Any})::AgentProposal
    # Default implementation - agents must implement this
    error("Agent $(typeof(agent)) must implement generate_proposal")
end

"""
    request_kernel_approval - Request kernel approval for a decision
"""
function request_kernel_approval(kernel::Any, decision::CommittedDecision)
    # This interfaces with the existing Kernel
    # In practice, this would call kernel's approval mechanism
    return (approved=true, rejection_reason=nothing)
end

"""
    execute_decision - Execute a committed decision
"""
function execute_decision(decision::CommittedDecision, kernel::Any)::DecisionOutcome
    # This would interface with the kernel's execution mechanism
    return DecisionOutcome(
        OUTCOME_EXECUTED,
        Dict("executed" => true),
        Dict(),
        now()
    )
end

"""
    log_immutable_entry - Create immutable log entry for the cycle
"""
function log_immutable_entry!(cycle::DecisionCycle)
    cycle.log_entry = Dict{String, Any}(
        "cycle_id" => string(cycle.id),
        "cycle_number" => cycle.cycle_number,
        "perception" => cycle.perception_input,
        "proposals" => [
            Dict(
                "agent_id" => p.agent_id,
                "agent_type" => string(p.agent_type),
                "decision" => p.decision,
                "confidence" => p.confidence,
                "reasoning" => p.reasoning,
                "weight" => p.weight
            ) for p in cycle.proposals
        ],
        "conflict_resolution" => cycle.conflict_resolution !== nothing ? Dict(
            "method" => string(cycle.conflict_resolution.method),
            "winner" => cycle.conflict_resolution.winner,
            "justification" => cycle.conflict_resolution.justification
        ) : nothing,
        "committed_decision" => cycle.committed_decision !== nothing ? Dict(
            "id" => string(cycle.committed_decision.id),
            "decision" => cycle.committed_decision.decision,
            "agent_influence" => cycle.committed_decision.agent_influence,
            "kernel_approved" => cycle.committed_decision.kernel_approved
        ) : nothing,
        "kernel_approved" => cycle.kernel_approved,
        "kernel_rejection_reason" => cycle.kernel_rejection_reason,
        "outcome" => cycle.outcome !== nothing ? Dict(
            "status" => string(cycle.outcome.status),
            "result" => cycle.outcome.result,
            "actual_vs_expected" => cycle.outcome.actual_vs_expected
        ) : nothing,
        "timestamp" => now()
    )
    cycle.logged = true
end

end # module DecisionSpine
