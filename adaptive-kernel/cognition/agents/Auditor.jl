# cognition/agents/Auditor.jl - Auditor Agent
# Adversarial thinker - detects risks, blind spots, overconfidence, self-deception

module Auditor

using Dates
using UUIDs

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

export AuditorAgent, generate_proposal, detect_risks, check_overconfidence,
       apply_power_modifier, detect_narrowing_decisions, calculate_power_confidence

# ============================================================================
# AUDITOR AGENT IMPLEMENTATION
# ============================================================================

"""
    create_auditor - Create an Auditor agent instance
"""
function create_auditor(id::String = "auditor_001"; risk_threshold::Float64 = 0.5)::AuditorAgent
    return AuditorAgent(id)
end

"""
    generate_proposal - Auditor generates adversarial proposal
    Detects risks, blind spots, and potential failures
    
    Optional parameters for power metric integration:
    - power_level: Float64 (0.0-1.0) representing current optionality/agency
    - optionality: OptionalityTracker for detailed power analysis
"""
function generate_proposal(
    agent::AuditorAgent,
    perception::Dict{String, Any},
    other_proposals::Vector{AgentProposal},
    doctrine::DoctrineMemory,
    tactical::TacticalMemory;
    power_level::Union{Float64, Nothing} = nothing,
    optionality::Union{OptionalityTracker, Nothing} = nothing
)::AgentProposal
    
    # Detect risks in current situation
    risks = detect_risks(perception, doctrine, tactical)
    
    # Check for blind spots
    blind_spots = detect_blind_spots(perception, other_proposals)
    
    # Check for overconfidence in other agents
    overconfidence = check_overconfidence(other_proposals)
    
    # Generate veto or warning proposal
    risk_level = calculate_risk_level(risks, blind_spots, overconfidence)
    
    # Detect narrowing decisions in other proposals
    narrowing_penalty = 0.0
    if optionality !== nothing
        narrowing_decisions = detect_narrowing_decisions(other_proposals, optionality)
        if length(narrowing_decisions) > 0
            narrowing_penalty = 0.15 * length(narrowing_decisions)  # -0.15 per narrowing decision
        end
    end
    
    if risk_level > agent.risk_threshold
        # High risk - propose veto or additional safeguards
        risks_str = join(risks, ",")
        proposal_text = string("veto_or_safeguard:risks=", risks_str)
        confidence = min(0.95, 0.5 + 0.1 * length(risks))
        
        agent.veto_count += 1
    else
        # Lower risk - propose monitoring and safeguards
        risks_str = join(risks, ",")
        proposal_text = string("proceed_with_safeguards:risks=", risks_str)
        confidence = 0.7
    end
    
    # Apply power-based confidence modifier
    if power_level !== nothing
        confidence = apply_power_modifier(confidence, power_level)
    end
    
    # Apply narrowing penalty
    if narrowing_penalty > 0
        confidence = confidence - narrowing_penalty
    end
    
    # Ensure confidence stays in valid range
    confidence = clamp(confidence, 0.0, 1.0)
    
    push!(agent.detected_risks, risks...)
    
    risks_evidence = string(length(risks), " risks identified")
    blind_spots_evidence = string(length(blind_spots), " blind spots")
    overconfidence_evidence = string(length(overconfidence), " overconfidence signals")
    risk_level_str = string("Risk level: ", risk_level)
    
    # Add power information to reasoning if available
    power_str = ""
    if power_level !== nothing
        if power_level < 0.3
            power_str = ". LOW_POWER: increased risk awareness active"
        elseif power_level > 0.7
            power_str = ". HIGH_POWER: confident decision-making allowed"
        end
    end
    
    # Add narrowing info if detected
    narrowing_str = ""
    if narrowing_penalty > 0
        narrowing_str = string(". NARROWING_PENALTY: -", round(narrowing_penalty, digits=2))
    end
    
    return AgentProposal(
        agent.id,
        :auditor,
        proposal_text,
        confidence,
        reasoning = string("Risk analysis: ", risks_evidence, ", ", blind_spots_evidence, ", ", overconfidence_evidence, ". ", risk_level_str, power_str, narrowing_str),
        weight = 1.2,  # Auditor has higher weight due to adversarial role
        evidence = ["risk_analysis", "blind_spot_analysis", "overconfidence_check"]
    )
end

"""
    detect_risks - Identify risks in current situation
"""
function detect_risks(
    perception::Dict{String, Any},
    doctrine::DoctrineMemory,
    tactical::TacticalMemory
)::Vector{String}
    
    risks = String[]
    
    # Check against doctrine invariants
    for invariant in doctrine.invariants
        if violates_invariant(perception, invariant)
            push!(risks, string("doctrine_violation_", invariant))
        end
    end
    
    # Check historical failure patterns
    for pattern in tactical.failure_patterns
        if matches_pattern(perception, pattern)
            push!(risks, string("historical_failure_", pattern))
        end
    end
    
    # Check resource constraints
    resources = get(perception, "resources", Dict{String, Any}())
    for (resource, info) in resources
        if get(info, "available", 1.0) < get(info, "required", 1.0)
            push!(risks, string("resource_shortage_", resource))
        end
    end
    
    # Check for adversarial signals
    adversarial = get(perception, "adversarial_signals", Dict{String, Bool}())
    for (signal, present) in adversarial
        if present
            push!(risks, string("adversarial_signal_", signal))
        end
    end
    
    # Check timing risks
    timing = get(perception, "timing", Dict{String, Any}())
    if get(timing, "deadline_approaching", false)
        push!(risks, "deadline_pressure")
    end
    
    return risks
end

"""
    detect_blind_spots - Identify potential blind spots in decision making
"""
function detect_blind_spots(
    perception::Dict{String, Any},
    proposals::Vector{AgentProposal}
)::Vector{String}
    
    blind_spots = String[]
    
    # Check if all proposals are similar (confirmation bias)
    if length(proposals) >= 2
        decisions = [p.decision for p in proposals]
        if all(d -> d == decisions[1], decisions)
            push!(blind_spots, "confirmation_bias")
        end
    end
    
    # Check for missing perspectives
    agent_types = Set([p.agent_type for p in proposals])
    required_types = [:executor, :strategist, :auditor, :evolution]
    missing = setdiff(required_types, agent_types)
    for m in missing
        push!(blind_spots, string("missing_perspective_", m))
    end
    
    # Check for information gaps
    info_gaps = get(perception, "information_gaps", String[])
    for gap in info_gaps
        push!(blind_spots, string("information_gap_", gap))
    end
    
    return blind_spots
end

"""
    check_overconfidence - Detect overconfidence in agent proposals
"""
function check_overconfidence(
    proposals::Vector{AgentProposal}
)::Vector{String}
    
    overconfidence_signals = String[]
    
    for proposal in proposals
        # High confidence without supporting evidence
        if proposal.confidence > 0.9 && length(proposal.evidence) < 2
            push!(overconfidence_signals, string("high_conf_no_evidence_", proposal.agent_id))
        end
        
        # Confidence mismatch with historical accuracy
        # (This would require agent metrics to check properly)
    end
    
    return overconfidence_signals
end

"""
    calculate_risk_level - Calculate overall risk level
"""
function calculate_risk_level(
    risks::Vector{String},
    blind_spots::Vector{String},
    overconfidence::Vector{String}
)::Float64
    
    # Base risk from identified risks
    risk_score = min(0.6, 0.1 * length(risks))
    
    # Blind spots add risk
    blind_spot_risk = min(0.25, 0.1 * length(blind_spots))
    
    # Overconfidence is particularly dangerous
    overconfidence_risk = min(0.15, 0.05 * length(overconfidence))
    
    return risk_score + blind_spot_risk + overconfidence_risk
end

"""
    violates_invariant - Check if perception violates a doctrine invariant
"""
function violates_invariant(perception::Dict{String, Any}, invariant::String)::Bool
    # Simplified implementation
    return false
end

"""
    matches_pattern - Check if perception matches a failure pattern
"""
function matches_pattern(perception::Dict{String, Any}, pattern::String)::Bool
    # Simplified implementation  
    return false
end

# ============================================================================
# POWER METRIC INTEGRATION
# ============================================================================

"""
    apply_power_modifier - Apply confidence modifier based on current power level
    
    Scoring rules:
    - Low power (< 0.3): Reduce confidence by 0.2, prefer reversible actions
    - Medium power (0.3-0.7): No change
    - High power (> 0.7): Increase confidence by 0.1
"""
function apply_power_modifier(base_confidence::Float64, power_level::Float64)::Float64
    modified_confidence = base_confidence
    
    if power_level < 0.3
        # Low power - increase risk awareness, reduce confidence
        modified_confidence = base_confidence - 0.2
    elseif power_level > 0.7
        # High power - allow more confidence
        modified_confidence = base_confidence + 0.1
    end
    # Medium power (0.3-0.7): no change
    
    return clamp(modified_confidence, 0.0, 1.0)
end

"""
    calculate_power_confidence - Calculate confidence adjustment from power level
    Returns the delta that would be applied
"""
function calculate_power_confidence(power_level::Float64)::Float64
    if power_level < 0.3
        return -0.2
    elseif power_level > 0.7
        return 0.1
    else
        return 0.0
    end
end

"""
    detect_narrowing_decisions - Detect decisions that reduce future options
    
    Narrowing decisions are those that:
    - Reduce pivot_speed significantly
    - Make decisions less reversible
    - Reduce viable action count
    - Remove leverage points
"""
function detect_narrowing_decisions(
    proposals::Vector{AgentProposal},
    optionality::OptionalityTracker
)::Vector{String}
    
    narrowing_decisions = String[]
    
    # Keywords that suggest narrowing decisions
    narrowing_keywords = [
        "commit", "irreversible", "lock_in", "final",
        "delete", "remove", "disable", "shutdown",
        "close", "terminate", "cancel", "abandon"
    ]
    
    for proposal in proposals
        decision_lower = lowercase(proposal.decision)
        
        # Check for narrowing keywords
        for keyword in narrowing_keywords
            if occursin(keyword, decision_lower)
                push!(narrowing_decisions, string(proposal.agent_id, ":", proposal.decision))
                break
            end
        end
        
        # Also check if this decision reduces optionality components
        # Low reversibility indicates narrowing
        if optionality.reversibility < 0.3
            push!(narrowing_decisions, string("low_reversibility:", optionality.reversibility))
        end
    end
    
    return narrowing_decisions
end

"""
    update_optionality! - Update optionality tracker based on executed decision
    
    Called after each cognitive cycle to track power changes:
    - Optionality gained (new capabilities/discovered paths)
    - Decision reversibility (how hard to undo decisions)
    - Dependency reduction (fewer external dependencies)
    - Leverage points created (influential positions gained)
"""
function update_optionality!(
    optionality::OptionalityTracker,
    decision::String,
    outcome_success::Bool,
    new_leverage_point::Union{String, Nothing} = nothing
)::Float64
    
    # Add the decision to viable actions if successful
    if outcome_success
        push!(optionality.viable_actions, decision)
    end
    
    # Add leverage point if discovered
    if new_leverage_point !== nothing
        push!(optionality.leverage_points, new_leverage_point)
    end
    
    # Reduce reversibility slightly for each decision (commitments accumulate)
    # But not below 0.1 to maintain some flexibility
    optionality.reversibility = max(0.1, optionality.reversibility - 0.02)
    
    # Pivot speed decreases with commitment but can be recovered
    # through new information/options
    optionality.pivot_speed = max(0.1, optionality.pivot_speed - 0.01)
    
    # Return current optionality score (0-1)
    return calculate_optionality_score(optionality)
end

"""
    calculate_optionality_score - Calculate overall optionality score (0-1)
"""
function calculate_optionality_score(optionality::OptionalityTracker)::Float64
    # Score based on multiple factors
    action_count_score = min(1.0, length(optionality.viable_actions) / 10.0)
    reversibility_score = optionality.reversibility
    pivot_score = optionality.pivot_speed
    leverage_score = min(1.0, length(optionality.leverage_points) / 5.0)
    
    # Weighted average
    return 0.3 * action_count_score + 0.3 * reversibility_score + 0.2 * pivot_score + 0.2 * leverage_score
end

"""
    recover_optionality! - Recover optionality through exploration
    Called when system gains new information or discovers new paths
"""
function recover_optionality!(
    optionality::OptionalityTracker,
    new_options::Vector{String},
    new_leverage::Union{String, Nothing} = nothing
)::Float64
    
    # Add new options
    append!(optionality.viable_actions, new_options)
    
    # Add leverage point
    if new_leverage !== nothing
        push!(optionality.leverage_points, new_leverage)
    end
    
    # Recover reversibility and pivot speed
    optionality.reversibility = min(1.0, optionality.reversibility + 0.1)
    optionality.pivot_speed = min(1.0, optionality.pivot_speed + 0.1)
    
    return calculate_optionality_score(optionality)
end

end # module Auditor
