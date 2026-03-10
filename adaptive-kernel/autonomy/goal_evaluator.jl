"""
# Goal Evaluator Module

Evaluates goal execution results.

Evaluation metrics:
- success: Bool - Did the goal complete?
- latency: Float64 - How long did it take?
- resource_efficiency: Float64 - How efficient was resource usage?
- system_improvement: Float64 - Did it improve the system?

Evaluation determines whether the goal produced positive impact.
"""

module GoalEvaluator

using Dates
using UUIDs

# Import types
include("goal_generator.jl")
include("planner.jl")
include("goal_executor.jl")

using .GoalGenerator
using .Planner
using .GoalExecutor

# Evaluation result structure
struct Evaluation
    goal_id::UUID
    plan_id::UUID
    timestamp::DateTime
    success::Bool
    latency_score::Float64      # 0-1, lower is better
    efficiency_score::Float64   # 0-1, higher is better
    improvement_score::Float64   # 0-1, higher is better
    overall_score::Float64      # 0-1 weighted average
    evaluation::String          # Human-readable summary
    recommendations::Vector{String}
end

# Evaluation metrics constants
const LATENCY_WEIGHT = 0.3
const EFFICIENCY_WEIGHT = 0.3
const IMPROVEMENT_WEIGHT = 0.4

"""
Evaluate a goal execution result against the system state.
"""
function evaluate(
    goal::Goal,
    plan::Plan,
    result::ExecutionResult,
    state_before::Dict{String, Any},
    state_after::Dict{String, Any}
)::Evaluation
    # Calculate latency score (0-1, lower is better)
    # Ideal: < 10 seconds, Poor: > 60 seconds
    latency_score = _calculate_latency_score(result.duration, plan.estimated_duration)
    
    # Calculate efficiency score (0-1, higher is better)
    efficiency_score = _calculate_efficiency_score(result)
    
    # Calculate improvement score (0-1, higher is better)
    improvement_score = _calculate_improvement_score(state_before, state_after)
    
    # Overall weighted score
    overall_score = (latency_score * LATENCY_WEIGHT + 
                     efficiency_score * EFFICIENCY_WEIGHT + 
                     improvement_score * IMPROVEMENT_WEIGHT)
    
    # Generate evaluation text
    evaluation = _generate_evaluation(goal, result, overall_score)
    
    # Generate recommendations
    recommendations = _generate_recommendations(goal, result, overall_score)
    
    return Evaluation(
        goal.id,
        plan.id,
        now(),
        result.success,
        latency_score,
        efficiency_score,
        improvement_score,
        overall_score,
        evaluation,
        recommendations
    )
end

"""
Calculate latency score (normalized 0-1).
"""
function _calculate_latency_score(actual_duration::Float64, estimated_duration::Float64)::Float64
    # If faster than estimated, score = 1
    # If 2x slower than estimated, score = 0
    ratio = actual_duration / max(estimated_duration, 1.0)
    return clamp(1.0 - (ratio - 1.0), 0.0, 1.0)
end

"""
Calculate efficiency score based on resource usage.
"""
function _calculate_efficiency_score(result::ExecutionResult)::Float64
    # Lower resource cost = higher efficiency
    # Normalize: 0 resource = 1.0, > 100 resource = 0.0
    return clamp(1.0 - (result.resource_cost / 100.0), 0.0, 1.0)
end

"""
Calculate system improvement score.
"""
function _calculate_improvement_score(
    state_before::Dict{String, Any},
    state_after::Dict{String, Any}
)::Float64
    # Compare CPU and memory usage
    cpu_before = get(state_before, "cpu_load", 50.0)
    cpu_after = get(state_after, "cpu_load", 50.0)
    mem_before = get(state_before, "memory_usage", 50.0)
    mem_after = get(state_after, "memory_usage", 50.0)
    
    # Improvement = lower is better for both
    cpu_improvement = (cpu_before - cpu_after) / max(cpu_before, 1.0)
    mem_improvement = (mem_before - mem_after) / max(mem_before, 1.0)
    
    # Combined score
    improvement = (cpu_improvement + mem_improvement) / 2.0
    
    return clamp(0.5 + improvement, 0.0, 1.0)  # Baseline 0.5
end

"""
Generate human-readable evaluation.
"""
function _generate_evaluation(goal::Goal, result::ExecutionResult, score::Float64)::String
    if result.success && score > 0.7
        return "Excellent: Goal '$(goal.name)' completed successfully with high overall performance."
    elseif result.success && score > 0.4
        return "Good: Goal '$(goal.name)' completed with acceptable performance."
    elseif result.success
        return "Marginal: Goal '$(goal.name)' completed but with low efficiency."
    else
        return "Failed: Goal '$(goal.name)' did not complete successfully."
    end
end

"""
Generate recommendations for improvement.
"""
function _generate_recommendations(
    goal::Goal,
    result::ExecutionResult,
    score::Float64
)::Vector{String}
    recommendations = String[]
    
    if !result.success
        push!(recommendations, "Review error messages and fix implementation")
        push!(recommendations, "Consider breaking down complex goals into smaller steps")
    end
    
    if result.duration > 60.0
        push!(recommendations, "Execution time exceeded 60s - consider optimization")
    end
    
    if score < 0.5
        push!(recommendations, "Low overall score - review goal parameters")
    end
    
    if isempty(recommendations)
        push!(recommendations, "No specific recommendations")
    end
    
    return recommendations
end

# Forward exports for external use
export Evaluation, evaluate, get_performance_summary

# Simple delta-focused evaluation (Phase 10 & 11)
"""
    evaluate(goal, initial_state, final_state)

Calculate the Delta (change in system state before and after an action).
This is the core of the Feedback Loop - analyzing what changed.
"""
function evaluate(
    goal::Goal,
    initial_state::Dict{String, Any},
    final_state::Dict{String, Any}
)
    # Calculate Delta - the change in system state
    # Positive mem_improvement = less memory used (good)
    # Positive load_change = lower load average (good)
    mem_improvement = get(initial_state, "mem_percent", 0.0) - get(final_state, "mem_percent", 0.0)
    load_change = get(initial_state, "load_avg", 0.0) - get(final_state, "load_avg", 0.0)
    
    # Basic success heuristic based on deltas
    # Success if memory improved or load decreased
    success = mem_improvement > 0 || load_change > 0
    
    evaluation = Dict(
        "goal" => goal.name,
        "success" => success,
        "impact" => Dict(
            "mem_delta" => mem_improvement,
            "load_delta" => load_change
        ),
        "timestamp" => now()
    )
    
    println("📊 Evaluation: Goal [$(goal.name)] - Success: $success (Mem Delta: $mem_improvement%, Load Delta: $load_change)")
    return evaluation
end

"""
Get performance summary across recent evaluations.
"""
function get_performance_summary(evaluations::Vector{Evaluation})::Dict{String, Any}
    if isempty(evaluations)
        return Dict(
            "total_goals" => 0,
            "success_rate" => 0.0,
            "average_score" => 0.0
        )
    end
    
    total = length(evaluations)
    successes = count(e -> e.success, evaluations)
    avg_score = sum(e.overall_score for e in evaluations) / total
    
    return Dict(
        "total_goals" => total,
        "success_rate" => successes / total,
        "average_score" => avg_score,
        "average_latency" => sum(e.latency_score for e in evaluations) / total,
        "average_efficiency" => sum(e.efficiency_score for e in evaluations) / total,
        "average_improvement" => sum(e.improvement_score for e in evaluations) / total
    )
end

end # module
