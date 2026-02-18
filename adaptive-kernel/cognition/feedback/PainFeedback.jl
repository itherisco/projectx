# cognition/feedback/PainFeedback.jl - Pain-Driven Feedback System
# Reward/penalty system for agent performance

module PainFeedback

using Dates
using UUIDs
using Statistics

# Import types
include("../types.jl")
using ..CognitionTypes

export 
    PainFeedback,
    RewardSignal,
    AgentPerformance,
    process_cycle_feedback,
    calculate_pain,
    calculate_reward,
    update_agent_weights

# ============================================================================
# PAIN-DRIVEN FEEDBACK SYSTEM
# ============================================================================

"""
    AgentPerformance - Tracks agent performance for feedback
"""
mutable struct AgentPerformance
    agent_id::String
    agent_type::Symbol
    
    # Pain signals (penalties)
    overconfidence_pain::Vector{Float64}
    prediction_error_pain::Vector{Float64}
    missed_risk_pain::Vector{Float64}
    
    # Reward signals
    warning_issued_rewards::Vector{Float64}
    accurate_prediction_rewards::Vector{Float64}
    risk_detected_rewards::Vector{Float64}
    
    # Cumulative scores
    total_pain::Float64
    total_reward::Float64
    
    # Current weight (can be penalized)
    current_weight::Float64
    
    function AgentPerformance(agent_id::String, agent_type::Symbol)
        new(
            agent_id, agent_type,
            Float64[], Float64[], Float64[],
            Float64[], Float64[], Float64[],
            0.0, 0.0, 1.0
        )
    end
end

"""
    process_cycle_feedback - Process feedback from a completed cycle
"""
function process_cycle_feedback(
    performance::AgentPerformance,
    cycle_outcome::Dict{String, Any}
)::Dict{String, Any}
    
    results = Dict{String, Any}()
    
    # Get actual outcome
    actual = get(cycle_outcome, "actual_outcome", "")
    expected = get(cycle_outcome, "expected_outcome", "")
    
    # Calculate prediction error
    prediction_error = calculate_prediction_error(expected, actual)
    
    # Calculate pain based on prediction error
    if prediction_error > 0.0
        pain = calculate_pain(:prediction_error, prediction_error)
        push!(performance.prediction_error_pain, pain)
        performance.total_pain += pain
        results["prediction_error_pain"] = pain
    end
    
    # Check for overconfidence
    confidence = get(cycle_outcome, "agent_confidence", 0.5)
    if confidence > 0.8 && prediction_error > 0.2
        # High confidence but wrong
        pain = calculate_pain(:overconfidence, confidence * prediction_error)
        push!(performance.overconfidence_pain, pain)
        performance.total_pain += pain
        results["overconfidence_pain"] = pain
    end
    
    # Check for missed risks
    risks_expected = get(cycle_outcome, "expected_risks", String[])
    risks_actual = get(cycle_outcome, "actual_risks", String[])
    missed_risks = setdiff(Set(risks_expected), Set(risks_actual))
    
    if !isempty(missed_risks)
        pain = calculate_pain(:missed_risk, length(missed_risks) * 0.1)
        push!(performance.missed_risk_pain, pain)
        performance.total_pain += pain
        results["missed_risk_pain"] = pain
    end
    
    # Calculate rewards
    warnings_issued = get(cycle_outcome, "warnings_issued", 0)
    if warnings_issued > 0
        reward = calculate_reward(:warning_issued, warnings_issued)
        push!(performance.warning_issued_rewards, reward)
        performance.total_reward += reward
        results["warning_reward"] = reward
    end
    
    # Accurate prediction reward (low error)
    if prediction_error < 0.1
        reward = calculate_reward(:accurate_prediction, 1.0 - prediction_error)
        push!(performance.accurate_prediction_rewards, reward)
        performance.total_reward += reward
        results["accuracy_reward"] = reward
    end
    
    # Risk detected reward
    if length(risks_actual) > 0 && !isempty(intersect(Set(risks_expected), Set(risks_actual)))
        reward = calculate_reward(:risk_detected, length(intersect(Set(risks_expected), Set(risks_actual))) / length(risks_expected))
        push!(performance.risk_detected_rewards, reward)
        performance.total_reward += reward
        results["risk_detection_reward"] = reward
    end
    
    # Update agent weight based on cumulative performance
    performance.current_weight = update_agent_weights(performance)
    results["new_weight"] = performance.current_weight
    
    return results
end

"""
    calculate_pain - Calculate numerical pain for a pain type
"""
function calculate_pain(pain_type::Symbol, magnitude::Float64)::Float64
    # Pain is always positive, scaled by magnitude
    # Different pain types have different scaling
    base_pain = magnitude
    
    if pain_type == :overconfidence
        # Overconfidence is especially punished
        return min(1.0, base_pain * 2.0)
    elseif pain_type == :prediction_error
        return min(1.0, base_pain)
    elseif pain_type == :missed_risk
        # Missed risks are dangerous
        return min(1.0, base_pain * 1.5)
    else
        return min(1.0, base_pain)
    end
end

"""
    calculate_reward - Calculate numerical reward for a reward type
"""
function calculate_reward(reward_type::Symbol, value::Float64)::Float64
    # Rewards are positive
    if reward_type == :warning_issued
        # Rewarding agents who warn first
        return min(1.0, value * 0.3)
    elseif reward_type == :accurate_prediction
        return min(1.0, value * 0.5)
    elseif reward_type == :risk_detected
        return min(1.0, value * 0.4)
    else
        return min(1.0, value * 0.2)
    end
end

"""
    calculate_prediction_error - Calculate error between expected and actual
"""
function calculate_prediction_error(expected::String, actual::String)::Float64
    if isempty(expected) || isempty(actual)
        return 0.0
    end
    
    # Simple string comparison - in practice would be more sophisticated
    if expected == actual
        return 0.0
    else
        return 1.0
    end
end

"""
    update_agent_weights - Update agent weight based on cumulative performance
"""
function update_agent_weights(performance::AgentPerformance)::Float64
    
    # Net score (reward - pain)
    net_score = performance.total_reward - performance.total_pain
    
    # Weight adjustment: starts at 1.0, can go from 0.1 to 1.5
    # Positive net score increases weight, negative decreases
    adjustment = net_score * 0.5  # 0.5 is the learning rate
    
    new_weight = clamp(1.0 + adjustment, 0.1, 1.5)
    
    return new_weight
end

"""
    get_agent_pain_summary - Get summary of agent's pain signals
"""
function get_agent_pain_summary(performance::AgentPerformance)::Dict{String, Any}
    
    return Dict(
        "agent_id" => performance.agent_id,
        "agent_type" => string(performance.agent_type),
        "current_weight" => performance.current_weight,
        "total_pain" => performance.total_pain,
        "total_reward" => performance.total_reward,
        "net_score" => performance.total_reward - performance.total_pain,
        "avg_overconfidence_pain" => isempty(performance.overconfidence_pain) ? 0.0 : mean(performance.overconfidence_pain),
        "avg_prediction_error_pain" => isempty(performance.prediction_error_pain) ? 0.0 : mean(performance.prediction_error_pain),
        "avg_missed_risk_pain" => isempty(performance.missed_risk_pain) ? 0.0 : mean(performance.missed_risk_pain),
        "warnings_issued_count" => length(performance.warning_issued_rewards),
        "accurate_predictions_count" => length(performance.accurate_prediction_rewards)
    )
end

end # module PainFeedback
