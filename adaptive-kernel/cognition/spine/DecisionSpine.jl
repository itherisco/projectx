# cognition/spine/DecisionSpine.jl - MANDATORY Decision Spine for Operational Cognition
# All cognitive cycles must flow through this spine
# Perception → Parallel Agent Proposals → Conflict Resolution → SINGLE Committed Decision → Kernel Approval → Execution/Rejection → Immutable Log Entry

module DecisionSpine

using Dates
using UUIDs
using JSON
using Statistics

# Remove: using Parameters  # For @with_kw

# Import shared types
include("../types.jl")
using ..SharedTypes

# Import agent types (forward declaration)
include("../cognition/types.jl")
using ..CognitionTypes

# Import memory veto functions for Phase 2.5
using ..CognitionTypes: check_doctrine_veto, check_tactical_veto, MemoryVeto, DoctrineMemory, TacticalMemory

# Import ThoughtCycle types and functions for DecisionSpine triggers
using ..SharedTypes: ThoughtCycle, ThoughtCycleType, complete_thought!

# Import IntentVector and related functions for strategic alignment scoring
using ..SharedTypes: IntentVector, add_intent!, update_alignment!, get_alignment_penalty

# ============================================================================
# CORE TYPES - Defined BEFORE includes so submodules can use them
# ============================================================================

"""
    SpineConfig - Configuration for the decision spine
"""
struct SpineConfig
    require_unanimity::Bool
    conflict_threshold::Float64
    max_deliberation_rounds::Int
    entropy_injection_enabled::Bool
    entropy_threshold::Float64
    kernel_approval_required::Bool
    log_immutable::Bool
    
    function SpineConfig(
        require_unanimity::Bool = false,
        conflict_threshold::Float64 = 0.3,
        max_deliberation_rounds::Int = 3,
        entropy_injection_enabled::Bool = true,
        entropy_threshold::Float64 = 0.85,
        kernel_approval_required::Bool = true,
        log_immutable::Bool = true
    )
        new(
            require_unanimity,
            conflict_threshold,
            max_deliberation_rounds,
            entropy_injection_enabled,
            entropy_threshold,
            kernel_approval_required,
            log_immutable
        )
    end
end

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
    # Phase 2.5: Memory Veto tracking
    vetoed::Bool                 # Whether proposal was vetoed by memory
    veto_reason::Union{String, Nothing}  # Reason for veto if vetoed
end

function AgentProposal(
    agent_id::String,
    agent_type::Symbol,
    decision::String,
    confidence::Float64;
    reasoning::String = "",
    weight::Float64 = 1.0,
    evidence::Vector{String} = String[],
    alternatives::Vector{String} = String[],
    vetoed::Bool = false,
    veto_reason::Union{String, Nothing} = nothing
)
    return AgentProposal(
        agent_id, agent_type, decision, confidence, reasoning, weight, 
        now(), evidence, alternatives, vetoed, veto_reason
    )
end

"""
    ConflictResolutionMethod - Method for resolving disagreements between agents
"""
@enum ConflictResolutionMethod begin
    CONFLICT_WEIGHTED_VOTE     # Weighted by agent confidence and historical accuracy
    CONFLICT_ADVERSARIAL       # Auditor has veto power on risky decisions
    CONFLICT_DELIBERATION      # Agents deliberate for more rounds
    CONFLICT_ESCALATION        # Escalate to higher authority
    CONFLICT_ENTROPY           # Inject randomness when too much agreement
end

"""
    ConflictResolution - Result of conflict resolution between agents
"""
struct ConflictResolution
    method::ConflictResolutionMethod
    round::Int
    votes::Dict{String, Float64}      # agent_id => vote weight
    winner::String                    # Winning agent_id
    justification::String
    timestamp::DateTime
end

# ============================================================================
# IMPORT SUBMODULES (Phase 3 decomposition) - Types defined above are now available
# ============================================================================

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
    DecisionCommitment,
    # Semantic recall
    query_experiences,
    check_prior_experience,
    # Phase 2.5: Memory Veto
    check_memory_vetoes,
    get_vetoed_proposals,
    has_vetoed_proposals,
    # Phase 2.6: Intent Alignment
    score_proposals_for_intent,
    calculate_intent_alignment,
    # Phase 3: ThoughtCycle triggers
    should_trigger_thought_cycle,
    run_decision_thought_cycle,
    ThoughtCycleInsights,
    ThoughtCycle

# ============================================================================
# CONFLICT RESOLUTION FUNCTIONS (use submodule)
# ============================================================================

"""
    resolve_conflict - Resolve disagreement between agent proposals
    Delegates to ConflictResolution submodule
"""
function resolve_conflict(
    proposals::Vector{AgentProposal},
    config::SpineConfig
)::ConflictResolution
    return ConflictResolution.resolve_conflict(proposals, config)
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
    ThoughtCycleInsights - Container for thought cycle analysis results
    These insights are used to influence conflict resolution WITHOUT executing actions
"""
struct ThoughtCycleInsights
    trigger_reason::String                    # Why the thought cycle was triggered
    cycle_type::ThoughtCycleType              # Type of thought cycle that ran
    proposal_analysis::Dict{String, Any}       # Analysis of current proposals
    simulated_outcomes::Vector{String}        # Potential outcomes (simulated)
    doctrine_hints::Vector{String}            # Hints for doctrine refinement
    strategy_hints::Vector{String}            # Hints for strategy selection
    confidence_adjustments::Dict{String, Float64}  # Suggested confidence adjustments
    timestamp::DateTime
end

function ThoughtCycleInsights(trigger_reason::String, cycle_type::ThoughtCycleType)
    return ThoughtCycleInsights(
        trigger_reason,
        cycle_type,
        Dict{String, Any}(),
        String[],
        String[],
        String[],
        Dict{String, Float64}(),
        now()
    )
end

"""
    should_trigger_thought_cycle - Determine if ThoughtCycle should be triggered
    
    Trigger conditions (at least one must be true):
    - More than 3 proposals with similar confidence scores (conflict unclear)
    - All proposals have confidence < 0.5 (low certainty)
    - Previous cycle had a failed execution
    - More than 5 proposals total (complex decision)
    
    # Arguments
    - `proposals::Vector{AgentProposal}`: Current proposals to analyze
    - `previous_outcome::Union{DecisionOutcome, Nothing}`: Previous cycle outcome (for failed execution check)
    - `rejected_count::Int`: Number of proposals rejected in memory veto (for doctrine refinement)
    
    # Returns
    - `Tuple{Bool, String}`: (should_trigger, trigger_reason)
"""
function should_trigger_thought_cycle(
    proposals::Vector{AgentProposal},
    previous_outcome::Union{DecisionOutcome, Nothing} = nothing;
    rejected_count::Int = 0
)::Tuple{Bool, String}
    
    # Condition 1: More than 5 proposals (complex decision)
    if length(proposals) > 5
        return (true, "complex_decision: $(length(proposals)) proposals")
    end
    
    # Condition 2: More than 3 proposals with similar confidence scores
    if length(proposals) > 3
        confidences = [p.confidence for p in proposals if !p.vetoed]
        if length(confidences) > 3
            # Check if std deviation is low (similar confidence)
            mean_conf = mean(confidences)
            std_conf = std(confidences)
            if std_conf < 0.15 && mean_conf > 0.3
                return (true, "unclear_conflict: similar confidence scores (std=$(round(std_conf, digits=3)))")
            end
        end
    end
    
    # Condition 3: All proposals have confidence < 0.5 (low certainty)
    non_vetoed = filter(p -> !p.vetoed, proposals)
    if !isempty(non_vetoed) && all(p -> p.confidence < 0.5, non_vetoed)
        return (true, "low_certainty: all confidences < 0.5")
    end
    
    # Condition 4: Previous cycle had a failed execution
    if previous_outcome !== nothing && previous_outcome.status == OUTCOME_FAILED
        return (true, "failed_execution: previous cycle failed")
    end
    
    # Condition 5: Many proposals were rejected (doctrine refinement needed)
    if rejected_count > 3
        return (true, "doctrine_refinement: $rejected_count proposals rejected")
    end
    
    return (false, "")
end

"""
    run_decision_thought_cycle - Run a ThoughtCycle for pre-conflict analysis
    
    This function runs a non-executing thought cycle that:
    - Analyzes current proposals
    - Simulates potential outcomes
    - Refines doctrine if needed
    - Returns insights WITHOUT executing any actions
    
    # Arguments
    - `proposals::Vector{AgentProposal}`: Current proposals to analyze
    - `trigger_reason::String`: Why the thought cycle was triggered
    - `context::Dict{String, Any}`: Additional context for analysis
    
    # Returns
    - `ThoughtCycleInsights`: Insights from the thought cycle
"""
function run_decision_thought_cycle(
    proposals::Vector{AgentProposal},
    trigger_reason::String,
    context::Dict{String, Any} = Dict{String, Any}()
)::ThoughtCycleInsights
    
    # Determine the type of thought cycle based on trigger reason
    if occursin("doctrine_refinement", trigger_reason)
        cycle_type = THOUGHT_DOCTRINE_REFINEMENT
    elseif occursin("unclear_conflict", trigger_reason) || occursin("complex_decision", trigger_reason)
        cycle_type = THOUGHT_SIMULATION
    elseif occursin("low_certainty", trigger_reason)
        cycle_type = THOUGHT_ANALYSIS
    elseif occursin("failed_execution", trigger_reason)
        cycle_type = THOUGHT_PRECOMPUTATION
    else
        cycle_type = THOUGHT_ANALYSIS
    end
    
    # Create insights container
    insights = ThoughtCycleInsights(trigger_reason, cycle_type)
    
    # Perform analysis based on cycle type
    non_vetoed = filter(p -> !p.vetoed, proposals)
    
    if cycle_type == THOUGHT_DOCTRINE_REFINEMENT
        # Analyze rejected proposals for doctrine issues
        vetoed = filter(p -> p.vetoed, proposals)
        insights.doctrine_hints = _analyze_doctrine_issues(vetoed, non_vetoed)
        
    elseif cycle_type == THOUGHT_SIMULATION
        # Simulate potential outcomes for unclear conflicts
        insights.simulated_outcomes = _simulate_outcomes(non_vetoed)
        insights.confidence_adjustments = _calculate_confidence_hints(non_vetoed)
        
    elseif cycle_type == THOUGHT_ANALYSIS
        # Analyze low certainty situations
        insights.proposal_analysis = _analyze_proposal_confidence(non_vetoed)
        insights.strategy_hints = _suggest_strategies_for_low_confidence(non_vetoed)
        
    elseif cycle_type == THOUGHT_PRECOMPUTATION
        # Precompute strategies after failed execution
        insights.strategy_hints = _analyze_failure_patterns(proposals, context)
        insights.doctrine_hints = _suggest_doctrine_improvements(context)
    end
    
    return insights
end

"""
    _analyze_doctrine_issues - Internal: Analyze vetoed proposals for doctrine issues
"""
function _analyze_doctrine_issues(
    vetoed::Vector{AgentProposal},
    non_vetoed::Vector{AgentProposal}
)::Vector{String}
    hints = String[]
    
    if length(vetoed) > 3
        push!(hints, "High rejection rate detected: review doctrine constraints")
    end
    
    # Check for common veto reasons
    veto_reasons = [p.veto_reason for p in vetoed if p.veto_reason !== nothing]
    if any(contains.(_,"DOCTRINE"), veto_reasons)
        push!(hints, "Doctrine constraints are frequently violated - consider relaxation")
    end
    
    if isempty(non_vetoed)
        push!(hints, "All proposals were vetoed - critical doctrine misalignment")
    end
    
    return hints
end

"""
    _simulate_outcomes - Internal: Simulate potential outcomes for proposals
"""
function _simulate_outcomes(proposals::Vector{AgentProposal})::Vector{String}
    outcomes = String[]
    
    # Simple simulation: check confidence spread
    if length(proposals) > 1
        confidences = [p.confidence for p in proposals]
        mean_conf = mean(confidences)
        max_conf = maximum(confidences)
        min_conf = minimum(confidences)
        
        if max_conf - min_conf < 0.2
            push!(outcomes, "Simulated: proposals have similar likelihood, expect prolonged deliberation")
        end
        
        if mean_conf > 0.7
            push!(outcomes, "Simulated: high average confidence suggests decisive action possible")
        else
            push!(outcomes, "Simulated: low average confidence suggests gathering more evidence")
        end
    end
    
    return outcomes
end

"""
    _calculate_confidence_hints - Internal: Calculate confidence adjustment hints
"""
function _calculate_confidence_hints(proposals::Vector{AgentProposal})::Dict{String, Float64}
    hints = Dict{String, Float64}()
    
    # Calculate entropy of confidence distribution
    if length(proposals) > 1
        confidences = [p.confidence for p in proposals]
        mean_conf = mean(confidences)
        
        # If confidence is too uniform, suggest boosting the highest
        if std(confidences) < 0.1
            highest_agent = argmax(p -> p.confidence, proposals)
            hints[highest_agent.agent_id] = 0.1  # Boost by 10%
        end
    end
    
    return hints
end

"""
    _analyze_proposal_confidence - Internal: Analyze proposal confidence levels
"""
function _analyze_proposal_confidence(proposals::Vector{AgentProposal})::Dict{String, Any}
    analysis = Dict{String, Any}()
    
    if isempty(proposals)
        return analysis
    end
    
    confidences = [p.confidence for p in proposals]
    analysis["mean_confidence"] = mean(confidences)
    analysis["min_confidence"] = minimum(confidences)
    analysis["max_confidence"] = maximum(confidences)
    analysis["confidence_spread"] = maximum(confidences) - minimum(confidences)
    analysis["proposal_count"] = length(proposals)
    
    return analysis
end

"""
    _suggest_strategies_for_low_confidence - Internal: Suggest strategies for low confidence
"""
function _suggest_strategies_for_low_confidence(proposals::Vector{AgentProposal})::Vector{String}
    strategies = String[]
    
    push!(strategies, "Consider gathering more evidence before committing")
    push!(strategies, "May want to explore hybrid approaches between top proposals")
    
    if length(proposals) > 2
        push!(strategies, "Request additional agent perspectives to break tie")
    end
    
    return strategies
end

"""
    _analyze_failure_patterns - Internal: Analyze failure patterns from previous outcome
"""
function _analyze_failure_patterns(proposals::Vector{AgentProposal}, context::Dict{String, Any})::Vector{String}
    hints = String[]
    
    push!(hints, "Previous execution failed - recommend reviewing error details")
    push!(hints, "Consider alternative approach if similar pattern persists")
    
    return hints
end

"""
    _suggest_doctrine_improvements - Internal: Suggest doctrine improvements
"""
function _suggest_doctrine_improvements(context::Dict{String, Any})::Vector{String}
    hints = String[]
    
    push!(hints, "Review failure context for doctrine gaps")
    push!(hints, "Consider adding new tactical patterns to prevent recurrence")
    
    return hints
end

# ============================================================================
# PHASE 2.6: INTENT ALIGNMENT SCORING
# ============================================================================

"""
    calculate_intent_alignment - Calculate alignment score between a proposal and IntentVector
    
    # Arguments
    - `proposal::AgentProposal`: The proposal to score
    - `intent_vector::IntentVector`: The strategic intent vector
    
    # Returns
    - `Float64`: Alignment score in range [-0.5, 0.5], where:
      - Positive = aligns with strategic intent
      - Negative = conflicts with strategic intent
      - Zero = no alignment detected
"""
function calculate_intent_alignment(
    proposal::AgentProposal,
    intent_vector::IntentVector
)::Float64
    # If no intents defined, return neutral
    if isempty(intent_vector.intents)
        return 0.0
    end
    
    alignment_score = 0.0
    proposal_lower = lowercase(proposal.decision)
    
    # Check each intent for alignment/conflict
    for (i, intent) in enumerate(intent_vector.intents)
        intent_lower = lowercase(intent)
        strength = intent_vector.intent_strengths[i]
        
        # Check if proposal aligns with this intent
        if occursin(intent_lower, proposal_lower) || occursin(proposal_lower, intent_lower)
            # Positive alignment: proposal supports this intent
            alignment_score += strength * 0.2
        else
            # Check for conflict keywords (opposite of intent)
            conflict_indicators = ["stop", "abort", "cancel", "disable", "remove", "delete"]
            for conflict in conflict_indicators
                if occursin(conflict, proposal_lower) && !occursin("no_$conflict", proposal_lower)
                    # Negative alignment: proposal conflicts with this intent
                    alignment_score -= strength * 0.15
                end
            end
        end
    end
    
    # Clamp to [-0.5, 0.5] range
    return clamp(alignment_score, -0.5, 0.5)
end

"""
    score_proposals_for_intent - Score proposals for strategic intent alignment
    
    This function is called in Phase 2.6 (after memory veto but before conflict resolution)
    to penalize proposals that conflict with strategic intent and reward aligned ones.
    
    # Arguments
    - `proposals::Vector{AgentProposal}`: The proposals to score
    - `intent_vector::Union{IntentVector, Nothing}`: The strategic intent vector (nothing if not available)
    
    # Returns
    - `Vector{AgentProposal}`: Proposals with adjusted confidence and weight based on intent alignment
"""
function score_proposals_for_intent(
    proposals::Vector{AgentProposal},
    intent_vector::Union{IntentVector, Nothing}
)::Vector{AgentProposal}
    # If no intent vector provided, return proposals unchanged
    if intent_vector === nothing
        @debug "No IntentVector provided - skipping intent alignment scoring"
        return proposals
    end
    
    # Get the alignment penalty from intent thrashing
    alignment_penalty = get_alignment_penalty(intent_vector)
    
    scored_proposals = AgentProposal[]
    alignment_log = Dict{String, Any}[]
    
    for proposal in proposals
        # Skip vetoed proposals
        if proposal.vetoed
            push!(scored_proposals, proposal)
            continue
        end
        
        # Calculate alignment score for this proposal
        alignment = calculate_intent_alignment(proposal, intent_vector)
        
        # Calculate confidence adjustment:
        # - Positive alignment boosts confidence
        # - Negative alignment reduces confidence
        # - Thrashing penalty applies to all proposals
        confidence_adjustment = alignment - alignment_penalty
        
        # Apply adjustment to confidence, clamped to [0, 1]
        new_confidence = clamp(proposal.confidence + confidence_adjustment, 0.0, 1.0)
        
        # Adjust weight similarly (weight reflects agent influence)
        new_weight = clamp(proposal.weight + confidence_adjustment * 0.5, 0.0, 1.0)
        
        # Build reasoning note if there was significant adjustment
        adjusted_reasoning = proposal.reasoning
        if abs(alignment) > 0.1
            alignment_note = alignment > 0 ? 
                " [INTENT: aligns with strategic intent]" : 
                " [INTENT: conflicts with strategic intent]"
            adjusted_reasoning = adjusted_reasoning * alignment_note
        end
        
        # Log the alignment scoring
        push!(alignment_log, Dict(
            "agent_id" => proposal.agent_id,
            "decision" => proposal.decision,
            "alignment_score" => alignment,
            "thrashing_penalty" => alignment_penalty,
            "confidence_adjustment" => confidence_adjustment,
            "old_confidence" => proposal.confidence,
            "new_confidence" => new_confidence
        ))
        
        # Create updated proposal
        scored_proposal = AgentProposal(
            proposal.agent_id,
            proposal.agent_type,
            proposal.decision,
            new_confidence;
            reasoning = adjusted_reasoning,
            weight = new_weight,
            evidence = proposal.evidence,
            alternatives = proposal.alternatives,
            vetoed = proposal.vetoed,
            veto_reason = proposal.veto_reason
        )
        push!(scored_proposals, scored_proposal)
    end
    
    # Log alignment scoring results
    if !isempty(alignment_log)
        @info "Phase 2.6: Intent alignment scoring complete"
            num_proposals=length(alignment_log)
            thrashing_penalty=alignment_penalty
            intent_count=length(intent_vector.intents)
            alignment_details=alignment_log
    end
    
    return scored_proposals
end

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
    
    # Phase 2.5: ThoughtCycle (pre-conflict analysis)
    thought_cycle::Union{ThoughtCycle, Nothing}
    thought_cycle_timestamp::Union{DateTime, Nothing}
    thought_cycle_insights::Vector{String}
    
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
            [], now(),
            nothing, nothing, String[],  # ThoughtCycle fields
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
    
    # Arguments
    - `cycle_number::Int`: The current cycle number
    - `perception::Dict{String, Any}`: The perception/input to process
    - `agents::Dict{Symbol, Any}`: Dictionary of agent_type => agent_instance
    - `kernel::Any`: Kernel instance for approval
    - `config::SpineConfig`: Configuration for the spine
    - `doctrine::Union{DoctrineMemory, Nothing}`: Doctrine memory for veto checks (optional)
    - `tactical::Union{TacticalMemory, Nothing}`: Tactical memory for veto checks (optional)
    - `previous_outcome::Union{DecisionOutcome, Nothing}`: Previous cycle outcome for ThoughtCycle trigger (optional)
    - `intent_vector::Union{IntentVector, Nothing}`: Strategic intent vector for alignment scoring (optional)
"""
function run_cognitive_cycle(
    cycle_number::Int,
    perception::Dict{String, Any},
    agents::Dict{Symbol, Any},  # agent_type => agent_instance
    kernel::Any,  # Kernel instance for approval
    config::SpineConfig = SpineConfig();
    doctrine::Union{DoctrineMemory, Nothing} = nothing,
    tactical::Union{TacticalMemory, Nothing} = nothing,
    previous_outcome::Union{DecisionOutcome, Nothing} = nothing,
    intent_vector::Union{IntentVector, Nothing} = nothing
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
    # PHASE 2.5: MEMORY VETO CHECK (Phase 3 - Memory Resistance)
    # =========================================================================
    cycle.proposals = check_memory_vetoes(
        cycle.proposals,
        doctrine,
        tactical,
        perception
    )
    
    @info "Phase 2.5: Memory veto check complete" 
        total_proposals=length(cycle.proposals)
        vetoed_count=count(p -> p.vetoed, cycle.proposals)
    
    # =========================================================================
    # PHASE 2.6: INTENT ALIGNMENT SCORING
    # =========================================================================
    # Score proposals for strategic intent alignment before conflict resolution
    # This penalizes proposals that conflict with strategic intent and rewards aligned ones
    cycle.proposals = score_proposals_for_intent(cycle.proposals, intent_vector)
    
    @info "Phase 2.6: Intent alignment scoring complete"
        has_intent_vector = intent_vector !== nothing
        intent_count = intent_vector !== nothing ? length(intent_vector.intents) : 0
    
    # =========================================================================
    # PHASE 2.75: THOUGHT CYCLE TRIGGER (Pre-Conflict Analysis)
    # =========================================================================
    # Check if we should trigger a ThoughtCycle for pre-conflict analysis
    # This runs BEFORE conflict resolution to provide insights
    
    # Count rejected proposals for doctrine refinement trigger
    rejected_count = count(p -> p.vetoed, cycle.proposals)
    
    # Check trigger conditions
    should_trigger, trigger_reason = should_trigger_thought_cycle(
        cycle.proposals,
        previous_outcome;  # Pass previous outcome for failed execution check
        rejected_count = rejected_count
    )
    
    if should_trigger
        @info "Phase 2.75: Triggering ThoughtCycle for pre-conflict analysis"
            reason=trigger_reason
        
        # Run the thought cycle
        thought_insights = run_decision_thought_cycle(
            cycle.proposals,
            trigger_reason,
            Dict("perception" => perception, "cycle_number" => cycle_number)
        )
        
        # Store the insights in the cycle
        cycle.thought_cycle_insights = vcat(
            thought_insights.simulated_outcomes,
            thought_insights.doctrine_hints,
            thought_insights.strategy_hints
        )
        
        # Apply confidence adjustments if any
        for (agent_id, adjustment) in thought_insights.confidence_adjustments
            for proposal in cycle.proposals
                if proposal.agent_id == agent_id
                    proposal.confidence = min(1.0, proposal.confidence + adjustment)
                end
            end
        end
        
        @info "Phase 2.75: ThoughtCycle complete"
            num_insights=length(cycle.thought_cycle_insights)
    else
        cycle.thought_cycle_insights = String[]
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
    check_memory_vetoes - Phase 2.5: Check proposals against memory veto hooks
    
    This function checks each proposal against doctrine and tactical memory vetoes.
    Vetoed proposals are marked with zero confidence but still appear in the decision
    with a veto reason recorded.
    
    # Arguments
    - `proposals::Vector{AgentProposal}`: The proposals to check
    - `doctrine::Union{DoctrineMemory, Nothing}`: Doctrine memory for invariant checking
    - `tactical::Union{TacticalMemory, Nothing}`: Tactical memory for failure pattern checking
    - `context::Dict{String, Any}`: Additional context for veto checks
    
    # Returns
    - Vector{AgentProposal}: Proposals with veto status updated
"""
function check_memory_vetoes(
    proposals::Vector{AgentProposal},
    doctrine::Union{DoctrineMemory, Nothing},
    tactical::Union{TacticalMemory, Nothing},
    context::Dict{String, Any}
)::Vector{AgentProposal}
    
    # If no memory provided, skip veto checks
    if doctrine === nothing && tactical === nothing
        @debug "No memory provided for veto checks - skipping Phase 2.5"
        return proposals
    end
    
    vetoed_proposals = AgentProposal[]
    veto_audit_log = Dict{String, Any}[]
    
    for proposal in proposals
        # Build context for veto checks
        proposal_context = merge(context, Dict(
            "agent_id" => proposal.agent_id,
            "agent_type" => string(proposal.agent_type),
            "proposal_decision" => proposal.decision
        ))
        
        vetoed = false
        veto_reason_str = ""
        
        # Check 1: Doctrine Veto (invariant violations)
        if doctrine !== nothing
            doctrine_veto = check_doctrine_veto(doctrine, proposal.decision, proposal_context)
            if doctrine_veto !== nothing
                vetoed = true
                veto_reason_str = "DOCTRINE: $(doctrine_veto.description)"
                
                # Log the veto for audit
                push!(veto_audit_log, Dict(
                    "proposal_id" => proposal.agent_id,
                    "decision" => proposal.decision,
                    "veto_type" => "doctrine",
                    "reason" => string(doctrine_veto.reason),
                    "description" => doctrine_veto.description,
                    "timestamp" => now()
                ))
                
                @warn "Doctrine veto applied" 
                    agent_id=proposal.agent_id
                    decision=proposal.decision
                    reason=doctrine_veto.description
            end
        end
        
        # Check 2: Tactical Veto (failure pattern matching)
        # Only check if not already vetoed by doctrine
        if !vetoed && tactical !== nothing
            tactical_veto = check_tactical_veto(tactical, proposal.decision, proposal_context)
            if tactical_veto !== nothing
                vetoed = true
                veto_reason_str = "TACTICAL: $(tactical_veto.description)"
                
                # Log the veto for audit
                push!(veto_audit_log, Dict(
                    "proposal_id" => proposal.agent_id,
                    "decision" => proposal.decision,
                    "veto_type" => "tactical",
                    "reason" => string(tactical_veto.reason),
                    "description" => tactical_veto.description,
                    "similar_failures" => tactical_veto.similar_failures,
                    "timestamp" => now()
                ))
                
                @warn "Tactical veto applied"
                    agent_id=proposal.agent_id
                    decision=proposal.decision
                    reason=tactical_veto.description
            end
        end
        
        # Create updated proposal with veto status
        if vetoed
            # Vetoed proposals have zero confidence but are kept in the list
            # with their veto reason for audit trail
            vetoed_proposal = AgentProposal(
                proposal.agent_id,
                proposal.agent_type,
                proposal.decision,
                0.0,  # Zero confidence - won't be selected in conflict resolution
                reasoning = proposal.reasoning * " [VETOED: $veto_reason_str]",
                weight = 0.0,  # Zero weight
                evidence = proposal.evidence,
                alternatives = proposal.alternatives,
                vetoed = true,
                veto_reason = veto_reason_str
            )
            push!(vetoed_proposals, vetoed_proposal)
        else
            # Non-vetoed proposals pass through unchanged
            push!(vetoed_proposals, proposal)
        end
    end
    
    # Log all veto decisions to audit trail
    if !isempty(veto_audit_log)
        @info "Memory veto audit trail" veto_count=length(veto_audit_log) vetoes=veto_audit_log
    end
    
    return vetoed_proposals
end

"""
    get_vetoed_proposals - Get all vetoed proposals from a cycle
"""
function get_vetoed_proposals(proposals::Vector{AgentProposal})::Vector{AgentProposal}
    return filter(p -> p.vetoed, proposals)
end

"""
    has_vetoed_proposals - Check if any proposals were vetoed
"""
function has_vetoed_proposals(proposals::Vector{AgentProposal})::Bool
    return any(p -> p.vetoed, proposals)
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
                "weight" => p.weight,
                "vetoed" => p.vetoed,
                "veto_reason" => p.veto_reason
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

# ============================================================================
# SEMANTIC RECALL INTEGRATION
# ============================================================================

# Global semantic memory reference (set by Kernel during initialization)
const GLOBAL_SEMANTIC_MEMORY = Ref{Union{Nothing, Any}}(nothing)

"""
    set_global_semantic_memory! - Set the global semantic memory for the spine
    Called during Kernel initialization
"""
function set_global_semantic_memory!(memory::Any)
    GLOBAL_SEMANTIC_MEMORY[] = memory
end

"""
    query_experiences - Query semantic memory for relevant past experiences
    Used by agents before generating proposals: "Have we dealt with this before?"
"""
function query_experiences(
    query::String;
    top_k::Int = 5,
    min_similarity::Float32 = 0.3f0
)::Vector{Dict{String, Any}}
    
    if GLOBAL_SEMANTIC_MEMORY[] === nothing
        return Dict{String, Any}[]
    end
    
    try
        sr = GLOBAL_SEMANTIC_MEMORY[]
        return Memory.recall_experience(sr, query; top_k = top_k, min_similarity = min_similarity)
    catch e
        @warn "Failed to query experiences: $e"
        return Dict{String, Any}[]
    end
end

"""
    check_prior_experience - Quick check if we've dealt with similar situation
    Returns context string if prior experience exists
"""
function check_prior_experience(
    situation::String;
    threshold::Float32 = 0.5f0
)::Union{Dict{String, Any}, Nothing}
    
    experiences = query_experiences(situation; top_k = 3, min_similarity = threshold)
    
    if isempty(experiences)
        return nothing
    end
    
    # Build context from experiences
    context_parts = String[]
    for exp in experiences
        push!(context_parts, exp["content"])
    end
    
    return Dict(
        "has_experience" => true,
        "num_experiences" => length(experiences),
        "context" => join(context_parts, " | "),
        "best_match_similarity" => experiences[1]["similarity"]
    )
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_cycle_summary - Get a summary of a decision cycle
"""
function get_cycle_summary(cycle::DecisionCycle)::Dict{String, Any}
    return Dict(
        "id" => string(cycle.id),
        "cycle_number" => cycle.cycle_number,
        "has_proposals" => !isempty(cycle.proposals),
        "has_decision" => cycle.committed_decision !== nothing,
        "kernel_approved" => cycle.kernel_approved,
        "outcome_status" => cycle.outcome !== nothing ? string(cycle.outcome.status) : "none"
    )
end

end # module DecisionSpine
