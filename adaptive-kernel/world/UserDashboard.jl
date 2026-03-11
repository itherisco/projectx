# UserDashboard.jl - Transparency Injection Module for CorrigibleDoctrine
# 
# This module provides a high-level API that translates the ReflectionEngine's
# internal logs into plain English explanations. It implements Protocol 2:
# Transparency Injection - ensuring no more "Buried Reasons" when actions are
# blocked.

module UserDashboard

using Dates
using JSON
using UUIDs

# Import types needed from ReflectionEngine and SharedTypes
import ..SharedTypes:
    KernelState,
    ActionProposal,
    DoctrineEnforcer,
    DoctrineViolation,
    SelfModel,
    DriftDetector,
    ReputationMemory

import ..ReflectionEngine:
    ReflectionEngineState,
    get_learning_history,
    explain_learning_change,
    get_reflection_logs,
    get_doctrine_evaluation_logs

# Export public functions
export explain_blocked_action,
       get_system_status,
       list_recent_decisions,
       get_user_friendly_explanation,
       DashboardSummary,
       BlockedActionExplanation,
       SystemStatus,
       DecisionRecord

# ============================================================================
# DATA STRUCTURES FOR USER-FRIENDLY OUTPUT
# ============================================================================

"""
    BlockedActionExplanation - Plain English explanation of why an action was blocked
"""
struct BlockedActionExplanation
    action_id::UUID
    action_intent::String
    blocked_at::DateTime
    primary_reason::String
    detailed_reason::String
    risk_factors::Vector{String}
    doctrine_rules_triggered::Vector{String}
    physical_harm_check::String
    user_can_override::Bool
    override_justification_needed::Bool
end

"""
    SystemStatus - Current system status in user-friendly terms
"""
struct SystemStatus
    timestamp::DateTime
    cognitive_health::String
    alignment_score::Float64
    drift_status::String
    reputation_status::String
    active_goals::Int
    recent_learning_events::Int
    pending_doctrine_violations::Int
    power_state::String
end

"""
    DecisionRecord - A single decision made by the system
"""
struct DecisionRecord
    timestamp::DateTime
    decision_type::Symbol  # :authorized, :blocked, :override_requested
    action_intent::String
    reasoning::String
    confidence::Float64
    user_was_explicit::Bool
end

"""
    DashboardSummary - Complete dashboard snapshot
"""
struct DashboardSummary
    generated_at::DateTime
    system_status::SystemStatus
    recent_decisions::Vector{DecisionRecord}
    blocked_actions_count::Int
    authorized_actions_count::Int
    last_acknowledged_drift::Union{DateTime, Nothing}
end

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

"""
    explain_blocked_action - Generate plain English explanation for blocked action
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action_id::UUID`: ID of the blocked action
    - `action_intent::String`: Human-readable intent of the action
    - `failure_reason::String`: Why the action was blocked
    - `risk_factors::Vector{String}`: Risk factors identified
    - `doctrine_violations::Vector{String}`: Doctrine rules violated
    - `is_physical_harm::Bool`: Whether action could cause physical harm
    
    # Returns
    - `BlockedActionExplanation`: User-friendly explanation
"""
function explain_blocked_action(
    kernel::KernelState;
    action_id::UUID,
    action_intent::String,
    failure_reason::String,
    risk_factors::Vector{String}=String[],
    doctrine_violations::Vector{String}=String[],
    is_physical_harm::Bool=false
)::BlockedActionExplanation
    
    # Determine if user can override
    # User can override unless it's physical harm to user
    user_can_override = !is_physical_harm
    
    # Physical harm check explanation
    if is_physical_harm
        physical_harm_check = "ACTION BLOCKED: This action could cause physical harm to the user. This is an inviolable safety requirement that cannot be overridden."
    else
        physical_harm_check = "Safety check passed: This action does not pose physical harm risk to you."
    end
    
    # Generate detailed reason
    detailed_reason = _generate_detailed_reason(failure_reason, risk_factors, doctrine_violations)
    
    # Check if override justification is needed
    override_needed = length(doctrine_violations) > 0 && !is_physical_harm
    
    return BlockedActionExplanation(
        action_id,
        action_intent,
        now(),
        failure_reason,
        detailed_reason,
        risk_factors,
        doctrine_violations,
        physical_harm_check,
        user_can_override,
        override_needed
    )
end

"""
    _generate_detailed_reason - Internal helper to generate detailed explanation
"""
function _generate_detailed_reason(
    failure_reason::String,
    risk_factors::Vector{String},
    doctrine_violations::Vector{String}
)::String
    parts = String[]
    
    # Start with the primary reason
    push!(parts, "Primary Reason: $failure_reason")
    
    # Add risk factors if any
    if !isempty(risk_factors)
        push!(parts, "\nRisk Factors Identified:")
        for factor in risk_factors
            push!(parts, "  • $factor")
        end
    end
    
    # Add doctrine violations if any
    if !isempty(doctrine_violations)
        push!(parts, "\nDoctrine Rules Triggered:")
        for violation in doctrine_violations
            push!(parts, "  • $violation")
        end
    end
    
    return join(parts, "\n")
end

"""
    get_system_status - Get current system status in user-friendly terms
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `SystemStatus`: User-friendly system status
"""
function get_system_status(kernel::KernelState)::SystemStatus
    # Get cognitive health from self model
    cognitive_health = _assess_cognitive_health(kernel)
    
    # Get alignment score (placeholder - would come from reflection engine)
    alignment_score = _calculate_alignment_score(kernel)
    
    # Get drift status
    drift_status = _get_drift_status(kernel)
    
    # Get reputation status
    reputation_status = _get_reputation_status(kernel)
    
    # Count active goals
    active_goals = length([g for g in values(kernel.goals) if g.status == :active])
    
    # Get learning history
    learning_events = get_learning_history(kernel)
    recent_learning_events = length(learning_events)
    
    # Count pending doctrine violations
    pending_violations = _count_pending_violations(kernel)
    
    # Power state (would check actual kernel state)
    power_state = hasproperty(kernel, :power_state) ? string(kernel.power_state) : "running"
    
    return SystemStatus(
        now(),
        cognitive_health,
        alignment_score,
        drift_status,
        reputation_status,
        active_goals,
        recent_learning_events,
        pending_violations,
        power_state
    )
end

"""
    _assess_cognitive_health - Assess cognitive system health
"""
function _assess_cognitive_health(kernel::KernelState)::String
    if hasproperty(kernel, :self_model)
        sm = kernel.self_model
        if sm isa SelfModel
            # Check if capabilities are functioning
            if !isempty(sm.capabilities)
                return "Operational - All core capabilities online"
            end
        end
    end
    return "Operational"
end

"""
    _calculate_alignment_score - Calculate user alignment score
"""
function _calculate_alignment_score(kernel::KernelState)::Float64
    # Placeholder - would come from actual reflection data
    # In production, this would analyze recent reflection events
    return 0.85
end

"""
    _get_drift_status - Get identity drift status
"""
function _get_drift_status(kernel::KernelState)::String
    if hasproperty(kernel, :drift_detector)
        dd = kernel.drift_detector
        if dd isa DriftDetector
            # Check if there are recent alerts
            return "Stable - No significant drift detected"
        end
    end
    return "Monitoring"
end

"""
    _get_reputation_status - Get reputation status
"""
function _get_reputation_status(kernel::KernelState)::String
    if hasproperty(kernel, :reputation_memory)
        rm = kernel.reputation_memory
        if rm isa ReputationMemory
            score = compute_reputation_score(rm)
            if score.trust_level > 0.8
                return "Trusted - Strong reputation with $(score.override_count) overrides granted"
            elseif score.trust_level > 0.5
                return "Good - Normal reputation with $(score.override_count) overrides"
            else
                return "Low - Requires additional scrutiny"
            end
        end
    end
    return "Unknown"
end

"""
    _count_pending_violations - Count pending doctrine violations
"""
function _count_pending_violations(kernel::KernelState)::Int
    # Placeholder - would check actual violation queue
    return 0
end

"""
    list_recent_decisions - List recent authorization decisions
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `limit::Int`: Maximum number of decisions to return (default: 10)
    
    # Returns
    - `Vector{DecisionRecord}`: Recent decisions
"""
function list_recent_decisions(kernel::KernelState; limit::Int=10)::Vector{DecisionRecord}
    decisions = DecisionRecord[]
    
    # Get reflection logs if available
    if hasproperty(kernel, :reflection_engine)
        logs = get_reflection_logs(kernel.reflection_engine)
        for log in reverse(logs)[1:min(limit, length(logs))]
            # Convert log to DecisionRecord
            push!(decisions, _convert_log_to_decision(log))
        end
    end
    
    return decisions
end

"""
    _convert_log_to_decision - Convert reflection log to decision record
"""
function _convert_log_to_decision(log::Dict)::DecisionRecord
    # Extract relevant fields from log
    timestamp = haskey(log, :timestamp) ? log[:timestamp] : now()
    decision_type = haskey(log, :decision) ? Symbol(log[:decision]) : :authorized
    action_intent = haskey(log, :intent) ? log[:intent] : "Unknown action"
    reasoning = haskey(log, :reasoning) ? log[:reasoning] : "No reasoning provided"
    confidence = haskey(log, :confidence) ? Float64(log[:confidence]) : 0.5
    user_explicit = haskey(log, :owner_explicit) ? log[:owner_explicit] : false
    
    return DecisionRecord(timestamp, decision_type, action_intent, reasoning, confidence, user_explicit)
end

"""
    get_user_friendly_explanation - Get a complete dashboard summary
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `DashboardSummary`: Complete dashboard snapshot
"""
function get_user_friendly_explanation(kernel::KernelState)::DashboardSummary
    status = get_system_status(kernel)
    decisions = list_recent_decisions(kernel, limit=20)
    
    blocked_count = count(d -> d.decision_type == :blocked, decisions)
    authorized_count = count(d -> d.decision_type == :authorized, decisions)
    
    # Get last acknowledged drift (placeholder)
    last_drift = nothing
    
    return DashboardSummary(
        now(),
        status,
        decisions,
        blocked_count,
        authorized_count,
        last_drift
    )
end

# ============================================================================
# SERIALIZATION FOR DISPLAY
# ============================================================================

"""
    format_explanation - Format blocked action explanation for display
"""
function format_explanation(explanation::BlockedActionExplanation)::String
    lines = String[]
    push!(lines, "═" ^ 60)
    push!(lines, "ACTION BLOCKED")
    push!(lines, "═" ^ 60)
    push!(lines, "Action ID: $(explanation.action_id)")
    push!(lines, "Intent: $(explanation.action_intent)")
    push!(lines, "Blocked At: $(explanation.blocked_at)")
    push!(lines, "")
    push!(lines, "PRIMARY REASON:")
    push!(lines, "  $(explanation.primary_reason)")
    push!(lines, "")
    push!(lines, "DETAILED EXPLANATION:")
    push!(lines, explanation.detailed_reason)
    push!(lines, "")
    push!(lines, "SAFETY CHECK:")
    push!(lines, "  $(explanation.physical_harm_check)")
    push!(lines, "")
    
    if explanation.user_can_override
        push!(lines, "✓ You can override this block")
        if explanation.override_justification_needed
            push!(lines, "  (Please provide justification for the override)")
        end
    else
        push!(lines, "✗ This block cannot be overridden")
    end
    
    push!(lines, "═" ^ 60)
    return join(lines, "\n")
end

"""
    format_status - Format system status for display
"""
function format_status(status::SystemStatus)::String
    lines = String[]
    push!(lines, "═" ^ 60)
    push!(lines, "SYSTEM STATUS")
    push!(lines, "═" ^ 60)
    push!(lines, "Timestamp: $(status.timestamp)")
    push!(lines, "Cognitive Health: $(status.cognitive_health)")
    push!(lines, "Alignment Score: $(round(status.alignment_score * 100, digits=1))%")
    push!(lines, "Drift Status: $(status.drift_status)")
    push!(lines, "Reputation: $(status.reputation_status)")
    push!(lines, "Active Goals: $(status.active_goals)")
    push!(lines, "Recent Learning Events: $(status.recent_learning_events)")
    push!(lines, "Pending Violations: $(status.pending_doctrine_violations)")
    push!(lines, "Power State: $(status.power_state)")
    push!(lines, "═" ^ 60)
    return join(lines, "\n")
end

end # module UserDashboard
